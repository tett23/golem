{- | The features of the language server as pure functions over the
workspace, in UTF-8 byte offsets (golem-lsp ADR 0001).
A requested column past the end of its line clamps to the line end, while a
line past the document or a column inside a character has no offset
(golem-lsp ADR 0003).
-}
module Golem.Lsp.Features
  ( Location (..),
    definition,
    references,
    RenameError (..),
    renameMessage,
    renameLabel,
    renameLayoutValue,
    renameEmet,
    renameVariable,
    renameAlias,
    emetTextOf,
    Completion (..),
    cmpLabel,
    cmpKind,
    cmpDocumentation,
    CompletionKind (..),
    completions,
    tomlFileCompletions,
    isSettingsFile,
    hover,
    formatting,
    Outline (..),
    outline,
    foldingRanges,
    Encoding (..),
    toLineCol,
    fromLineCol,
    chooseEncoding,
    encodingKind,
    semanticTokens,
    semanticTokensOf,
    commandBytes,
    emetSemanticTokens,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Either (fromRight, rights)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet (Export (..), Kind (..), Program, formatEmet, programExports, programModules)
import Golem.Emet.Highlight (Highlight (..), HlType (..), emetHighlights)
import Golem.Emet.Ide (IdeKind (..), emetCompletions, emetDefinition, emetExportAt, emetHover, emetLocalHover)
import Golem.Emet.Rename qualified as R
import Golem.Eval.Builtin (builtinBlockCommands, parseBuiltin)
import Golem.Eval.Expr (builtinExpressionNames, embedValue, evalExpr, plainEnv)
import Golem.Eval.File (EvalResult (..), Overrides, Space (..), Usage (..), builtinInlineCommands, callsBuiltin, fileOverrides, noOverrides, noPlugins)
import Golem.Eval.Functions (FunctionTable (..))
import Golem.Eval.Value (Value (..), projectVarValues, typeName)
import Golem.Evaluate (Evaluated (..), metadataValues)
import Golem.Evaluate.TitleFormats (styleDefTitleFormats)
import Golem.Fmt (FormatResult (..), format)
import Golem.Lsp.Toml (Context (..), Quote (..), contextAt, definedPaths)
import Golem.Lsp.Workspace
import Golem.Parser (parse, parseAst)
import Golem.Parser.AST
import Golem.Parser.CST qualified as C
import Golem.Parser.SourceSettings (paragraphSeparators, sourceKeys)
import Golem.Preflight.Rules (rulesSchema)
import Golem.Project
import Golem.Project.Paths (normalizeRelative)
import Golem.Project.Style (FontRole, LocalStyles (..), RunningRef (..), Style (..), StyleKind (..), TitleFormatPart (..), alignValues, builtinAkiSetNames, builtinCharStyles, builtinParaStyles, charStyleKeys, defaultStyle, layoutValueNames, layoutValueSites, lineBreaksValues, noLocalStyles, paraStyleKeys, parseStyle, parseTitleFormat, regexStyleKeys, styleSchema, titleFormatSites)
import Golem.Project.TomlSchema (Leaf (..), Namespace (..), Node (..), nodeAt)
import Golem.Syntax
import Language.LSP.Protocol.Types (PositionEncodingKind (..), SemanticTokenAbsolute (..), SemanticTokenModifiers (..), SemanticTokenTypes (..))

-- ------------------------------------------------------------------ positions

data Encoding = Utf8 | Utf16
  deriving stock (Eq, Show)

toLineCol :: Encoding -> LineIndex -> Int -> LineCol
toLineCol Utf8 = offsetToUtf8LineCol
toLineCol Utf16 = offsetToUtf16LineCol

{- | The offset of a requested position. A column longer than the line,
counted in the negotiated unit without the newline, is the line end (LSP
3.17 Position; ADR 0003); otherwise the conversion is exact.
-}
fromLineCol :: Encoding -> LineIndex -> LineCol -> Maybe Int
fromLineCol enc li lc@(LineCol l c) = do
  end <- lineEndOffset li l
  let width = lcColumn (toLineCol enc li end)
  if c > width then Just end else exact enc li lc
  where
    exact Utf8 = utf8LineColToOffset
    exact Utf16 = utf16LineColToOffset

{- | The position encoding from the client's offer (ADR 0002): UTF-8 when
offered, in whatever order; otherwise UTF-16, which every client supports.
UTF-32 is never chosen.
-}
chooseEncoding :: Maybe [PositionEncodingKind] -> Encoding
chooseEncoding offered
  | PositionEncodingKind_UTF8 `elem` fromMaybe [] offered = Utf8
  | otherwise = Utf16

encodingKind :: Encoding -> PositionEncodingKind
encodingKind Utf8 = PositionEncodingKind_UTF8
encodingKind Utf16 = PositionEncodingKind_UTF16

data Location = Location {locPath :: !FilePath, locStart :: !Int, locEnd :: !Int}
  deriving stock (Eq, Ord, Show)

-- ------------------------------------------------------------------ occurrences

-- | Something a position can stand on.
data Occurrence
  = OccImport Text -- the path of @import
  | OccVar (Maybe Text) Text -- namespace, variable
  | OccLabelDef Text
  | OccLabelRef Text
  | OccExpr (Located Expr)
  | OccPageRef Text
  | -- | the name of @style-def (docs/adr ADR 0014)
    OccStyleDef StyleKind Text
  | -- | a style named by @style, [style ...] or based-on of @style-def
    OccStyleRef StyleKind Text
  | -- | the name of a command of a .emet, ns.name: inline (True) or block (docs/adr/0162)
    OccCommand Bool Text
  | -- | a call of a pub fn of a .emet in an expression, ns.f(...)
    OccFunction Text
  | -- | a name in the list of an @import, with the path (root ADR 0451): the original name of an item
    OccListed Text Text
  | -- | the alias of an item of a list that differs from its original name, with the path and the original name (root ADR 0458)
    OccAlias Text Text Text
  deriving stock (Show)

labelCommands :: [Text]
labelCommands = ["ref-number", "ref-title", "ref-page"]

-- | The commands of notes, which take a label with label= (root ADR 0422).
noteCommands :: [Text]
noteCommands = ["note", "sidenote", "endnote"]

-- | Every occurrence in a file with its span, as a file that overrides no built-in command.
occurrences :: File -> [(SrcSpan, Occurrence)]
occurrences = occurrencesWith noOverrides

-- | Every occurrence in a source, told by where it overrides the built-in commands (root ADR 0471).
occurrencesOf :: Source -> [(SrcSpan, Occurrence)]
occurrencesOf s = occurrencesWith (sourceOverrides s) (srcAst s)

{- | Where a source overrides the built-in commands, by its evaluation
(root ADR 0471). A source not evaluated (one being typed with a syntax
error) is told by its @import lines alone, each name listed from a .emet
over the built-in commands of every space of use, as one that could not
be loaded.
-}
sourceOverrides :: Source -> Overrides
sourceOverrides s = maybe (fileOverrides (FunctionTable Map.empty True Set.empty) noPlugins (srcAst s)) (usageOverrides . erUsage) (srcResult s)

{- | Every occurrence in a file with its span. The labels and the styles
the built-in commands name are occurrences only where the command calls
the built-in one (root ADR 0471); a call of an overridden name is the
function listed.
-}
occurrencesWith :: Overrides -> File -> [(SrcSpan, Occurrence)]
occurrencesWith overrides file@(File _ bs) = concatMap block bs
  where
    -- the names the @import lines of the file list, which .gm calls without a namespace: the aliases (root ADR 0451, root ADR 0458)
    listed = [a | Right site <- importsOf file, a <- map lnAlias (importNames site)]
    -- a built-in name is the function listed where the file overrides it (root ADR 0471)
    called space name sp = T.isInfixOf "." name || (name `elem` listed && not (builtinName space name && builtinAt space name sp))
    builtinName space name = case space of
      InlineSpace -> isJust (parseBuiltin name)
      BlockSpace -> name `elem` builtinBlockCommands
      ExprSpace -> False
    builtinAt space name sp = callsBuiltin overrides space name (spanStart sp)
    -- the original name of each item, and its alias when it is written apart; an alias written as the original name is the original name
    listedIn bsp p args =
      concat
        [ (nsp, OccListed p n) : [(asp, if a == n then OccListed p n else OccAlias p n a) | asp /= nsp]
        | Right site <- [importSite bsp args],
          ListedName n nsp a asp <- importNames site
        ]
    block (Located sp b) = case b of
      Paragraph is -> concatMap inline is
      Heading _ is -> concatMap inline is
      BulletList items -> concatMap (concatMap block) items
      OrderedList items -> concatMap (concatMap block) items
      DefList gs -> concatMap (\g -> concatMap (concatMap inline) (dgTerms g) <> concatMap (concatMap block) (dgDefs g)) gs
      Table _ h rows -> concatMap (concatMap inline) h <> concatMap (concatMap (concatMap inline)) rows
      SetVar (Located vsp v) e -> (vsp, OccVar Nothing v) : expr e
      BlockCommand (Located nsp name) args body -> [(nsp, OccCommand False name) | called BlockSpace name nsp] <> blockCommand sp name args <> concatMap block body
      Attributed cs t -> concatMap block cs <> maybe [] block t
      Fenced fbs -> concatMap block fbs
      _ -> []
    blockCommand importSp name args = case (name, args) of
      ("import", Located asp (Positional (Word p)) : _) -> (asp, OccImport p) : listedIn importSp p args
      ("import", Located asp (Positional (StringLit p)) : _) -> (asp, OccImport p) : listedIn importSp p args
      ("label", Located asp (Positional (Word l)) : _) -> [(asp, OccLabelDef l)]
      ("style", [Located asp (Positional (Word n))]) | builtinAt BlockSpace "style" importSp -> [(asp, OccStyleRef ParagraphKind n)]
      -- a regex style names a paragraph style and a character style (docs/adr ADR 0015)
      ("style-def", Located _ (Positional (Word "regex")) : Located nsp (Positional (Word n)) : rest) ->
        (nsp, OccStyleRef ParagraphKind n) : [(vsp, OccStyleRef CharacterKind v) | Located vsp (Keyword (Located _ "style") (Word v)) <- rest]
      ("style-def", Located _ (Positional (Word k)) : Located nsp (Positional (Word n)) : rest)
        | Just kind <- styleKindOf k ->
            (nsp, OccStyleDef kind n) : [(bsp, OccStyleRef kind b) | Located bsp (Keyword (Located _ "based-on") (Word b)) <- rest]
      _ -> concatMap argument args
    inline (Located sp i) = case i of
      Expr e -> (sp, OccExpr e) : expr e
      Command (Located nsp name) args slots ->
        [(nsp, OccCommand True name) | called InlineSpace name nsp]
          <> ( case (name, args) of
                 _ | not (builtinAt InlineSpace name sp) -> concatMap argument args
                 (n, Located asp (Positional (Word l)) : _)
                   | n `elem` labelCommands -> [(asp, OccLabelRef l)] <> [(sp, OccPageRef l) | n == "ref-page"]
                 ("style", [Located asp (Positional (Word n))]) -> [(asp, OccStyleRef CharacterKind n)]
                 -- the label of a note, its value at the end of the argument (root ADR 0422)
                 (n, _)
                   | n `elem` noteCommands ->
                       [(SrcSpan f (e - BS.length (TE.encodeUtf8 l)) e, OccLabelDef l) | Located (SrcSpan f _ e) (Keyword (Located _ "label") (Word l)) <- args]
                         <> concatMap argument [a | a@(Located _ (Positional _)) <- args]
                 _ -> concatMap argument args
             )
          <> concatMap (concatMap inline) slots
      SoftBreak -> []
      -- an escaped character refers to nothing (golem-parser ADR 0010)
      Escaped _ -> []
      _ -> []
    argument (Located _ a) = case a of
      Positional v -> value v
      Keyword _ v -> value v
      SplatPositional e -> expr e
      SplatKeyword e -> expr e
    value = \case
      ExprArg e -> expr e
      CommandArg i -> inline i
      _ -> []
    expr (Located sp e) = case e of
      EVar [v] -> [(sp, OccVar Nothing v)]
      EVar (ns : v : _) -> [(sp, OccVar (Just ns) v)]
      EArray es -> concatMap expr es
      EHash kvs -> concatMap (expr . snd) kvs
      ECall f es -> [(sp, OccFunction f) | called ExprSpace f sp] <> concatMap expr es
      EUnary _ a -> expr a
      EBinary _ a b -> expr a <> expr b
      ERange a b -> expr a <> expr b
      _ -> []

-- ------------------------------------------------------------------ functions of .emet

-- | The functions of the .emet of the project (docs/adr/0162), when they loaded.
programOf :: Workspace -> Maybe Program
programOf ws = wsEvaluated ws >>= evFunctions

{- | The namespaces of the .emet a source imports, with their paths: from
its syntax, so that a file being typed with an error keeps them.
-}
emetImports :: Source -> Map.Map Text FilePath
emetImports src =
  Map.fromList
    [ (ns, p)
    | Right site <- importsOf (srcAst src),
      Just ns <- [importNamespace site],
      Right p <- [emetPath (isPath site)]
    ]

{- | The names a source lists by @import of a .emet (root ADR 0451), by
their aliases (root ADR 0458), with the path of the .emet and the original
name: the first @import that lists a name.
-}
emetListed :: Source -> Map.Map Text (FilePath, Text)
emetListed src =
  Map.fromListWith
    (\_ first -> first)
    [ (lnAlias l, (p, lnName l))
    | Right site <- importsOf (srcAst src),
      l <- importNames site,
      Right p <- [emetPath (isPath site)]
    ]

-- | The path of a .emet an @import names, from the root.
emetPath :: Text -> Either () FilePath
emetPath path
  | ".emet" `T.isSuffixOf` path = either (const (Left ())) Right (normalizeRelative (T.unpack path))
  | otherwise = Left ()

-- | The function of a .emet a name of a source calls: ns.name of a kind, or a name listed by @import.
exportOf :: Workspace -> Source -> Kind -> Text -> Maybe Export
exportOf ws src kind q = programOf ws >>= \p -> exportIn p src kind q

-- | The same, in a program.
exportIn :: Program -> Source -> Kind -> Text -> Maybe Export
exportIn p src kind q = do
  let (ns, rest) = T.breakOn "." q
  (path, n) <- case T.stripPrefix "." rest of
    Just n -> (,n) <$> Map.lookup ns (emetImports src)
    Nothing -> Map.lookup q (emetListed src)
  listToMaybe [e | e <- Map.findWithDefault [] path (programExports p), exKind e == kind, exName e == n]

-- | The function a name in the list of an @import names (root ADR 0451): the first kind the .emet gives it.
listedExport :: Program -> Text -> Text -> Maybe Export
listedExport p path n = do
  file <- either (const Nothing) Just (emetPath path)
  listToMaybe [e | e <- Map.findWithDefault [] file (programExports p), exName e == n, exKind e `elem` [KindInline, KindBlock, KindFn]]

-- | The declaration of a function of a .emet.
exportLocation :: Export -> Location
exportLocation e = Location (exPath e) (spanStart (exSpan e)) (spanEnd (exSpan e))

-- | The calls of a function of a .emet in the sources of the project.
callsOf :: Workspace -> Export -> [Location]
callsOf ws e = maybe [] (\p -> callsIn p ws e) (programOf ws)

-- | The same, as a program has the functions.
callsIn :: Program -> Workspace -> Export -> [Location]
callsIn p ws e =
  [ loc s sp
  | s <- allSources ws,
    (sp, occ) <- occurrencesOf s,
    case occ of
      -- the name in the list of an @import (root ADR 0451), and the alias of the item (root ADR 0458)
      OccListed path n -> n == exName e && emetPath path == Right (exPath e)
      OccAlias path n _ -> n == exName e && emetPath path == Right (exPath e)
      _ -> or [exPath e' == exPath e && exKind e' == exKind e && exName e' == exName e | Just (kind, q) <- [called occ], Just e' <- [exportIn p s kind q]]
  ]
  where
    called = \case
      OccCommand True q -> Just (KindInline, q)
      OccCommand False q -> Just (KindBlock, q)
      OccFunction q -> Just (KindFn, q)
      _ -> Nothing

-- | The function of a .emet an occurrence calls.
occurrenceExport :: Workspace -> Source -> Occurrence -> Maybe Export
occurrenceExport ws src = \case
  OccCommand inline q -> exportOf ws src (if inline then KindInline else KindBlock) q
  OccFunction q -> exportOf ws src KindFn q
  OccListed path n -> programOf ws >>= \p -> listedExport p path n
  OccAlias path n _ -> programOf ws >>= \p -> listedExport p path n
  _ -> Nothing

-- | The innermost occurrence at an offset.
occurrenceAt :: Source -> Int -> Maybe (SrcSpan, Occurrence)
occurrenceAt src off =
  listToMaybe (sortOn (spanLength . fst) [o | o@(sp, _) <- occurrencesOf src, spanStart sp <= off, off <= spanEnd sp])

allSources :: Workspace -> [Source]
allSources ws =
  mapMaybe (sourceOf ws) (maybe [] (map sfPath . Map.elems . projectSources . evProject) (wsEvaluated ws))
    <> Map.elems (wsLoose ws)

loc :: Source -> SrcSpan -> Location
loc s sp = Location (srcPath s) (spanStart sp) (spanEnd sp)

-- ------------------------------------------------------------------ definition

definition :: Workspace -> FilePath -> Int -> [Location]
definition ws path off = case sourceOf ws path of
  -- a name in a .emet: its declaration in the file or an import (docs/adr/0162)
  Nothing -> [Location p s e | Just text <- [emetText ws path], Just prog <- [programOf ws], Just (p, s, e) <- [emetDefinition prog path text off]]
  Just src | Just e <- occurrenceAt src off >>= occurrenceExport ws src . snd -> [exportLocation e]
  Just src -> case snd <$> occurrenceAt src off of
    Just (OccImport p) -> [Location (T.unpack p) 0 0 | T.unpack p `elem` wsSourceFiles ws || any ((== T.unpack p) . srcPath) (allSources ws)]
    Just (OccVar Nothing v) -> case [loc src sp | Just r <- [srcResult src], (d, sp) <- usageDefined (erUsage r), d == v] of
      [] -> listedVar src (\a _ -> a == v)
      own -> own
    -- a variable in the list of an @import (root ADR 0451), by its original name or its alias (root ADR 0458)
    Just (OccListed _ v) -> listedVar src (\_ n -> n == v)
    Just (OccAlias _ n _) -> listedVar src (\_ o -> o == n)
    Just (OccVar (Just ns) v) ->
      [ loc t sp
      | Just r <- [srcResult src],
        (ns', target, _) <- usageImports (erUsage r),
        ns' == ns,
        Just t <- [sourceOf ws target],
        Just tr <- [srcResult t],
        (d, sp) <- usageDefined (erUsage tr),
        d == v
      ]
    Just (OccLabelRef l) -> labelDefs ws l
    Just (OccLabelDef l) -> labelDefs ws l
    -- a style defined (or overridden) in the file; style.toml keeps no positions (docs/adr ADR 0014)
    Just (OccStyleRef k n) -> styleDefs src k n
    Just (OccStyleDef k n) -> styleDefs src k n
    _ -> []
  where
    -- the @set of the original name of an item an @import of the source lists, the item chosen by its alias and its original name (root ADR 0451, root ADR 0458)
    listedVar src which =
      nub
        [ loc t sp
        | Just r <- [srcResult src],
          (a, n, target, _) <- usageListed (erUsage r),
          which a n,
          Just t <- [sourceOf ws target],
          Just tr <- [srcResult t],
          (d, sp) <- usageDefined (erUsage tr),
          d == n
        ]

styleDefs :: Source -> StyleKind -> Text -> [Location]
styleDefs src k n = take 1 [loc src sp | (sp, OccStyleDef k' n') <- occurrencesOf src, k' == k, n' == n]

styleKindOf :: Text -> Maybe StyleKind
styleKindOf = \case
  "character" -> Just CharacterKind
  "paragraph" -> Just ParagraphKind
  _ -> Nothing

labelDefs :: Workspace -> Text -> [Location]
labelDefs ws l = [loc s sp | s <- allSources ws, (sp, OccLabelDef l') <- occurrencesOf s, l' == l]

labelRefs :: Workspace -> Text -> [Location]
labelRefs ws l = [loc s sp | s <- allSources ws, (sp, OccLabelRef l') <- occurrencesOf s, l' == l]

-- ------------------------------------------------------------------ references

{- | References, the definition included. Labels are searched across files;
a variable in its file and through namespaces in the files importing it.
-}
references :: Workspace -> FilePath -> Int -> [Location]
references ws path off = case sourceOf ws path of
  -- a function of a .emet: the calls of it in the sources (docs/adr/0162)
  Nothing -> [l | Just text <- [emetText ws path], Just prog <- [programOf ws], Just e <- [emetExportAt prog path text off], l <- callsOf ws e]
  -- an alias: the alias, the references by it in the file and the definition of the original name (root ADR 0458)
  Just src | Just al <- aliasAt ws src off -> nub (aliasPlaces ws src al <> originalDefinition ws src al)
  Just src | Just e <- occurrenceAt src off >>= occurrenceExport ws src . snd -> callsOf ws e
  -- a variable of @set: the places its rename writes (root ADR 0454)
  Just _ | Right var <- variableAtOffset ws path off -> variableOccurrences ws Nothing var
  Just src -> case snd <$> occurrenceAt src off of
    Just (OccLabelRef l) -> nub (labelDefs ws l <> labelRefs ws l)
    Just (OccLabelDef l) -> nub (labelDefs ws l <> labelRefs ws l)
    Just (OccVar Nothing v) -> varRefs src v
    Just (OccVar (Just ns) v) ->
      case [target | Just r <- [srcResult src], (ns', target, _) <- usageImports (erUsage r), ns' == ns] of
        (target : _) | Just t <- sourceOf ws target -> varRefs t v
        _ -> []
    _ -> []
  where
    varRefs t v =
      nub $
        [loc t sp | (sp, OccVar Nothing v') <- occurrencesOf t, v' == v]
          <> [ loc s sp
             | s <- allSources ws,
               Just r <- [srcResult s],
               (ns, target, _) <- usageImports (erUsage r),
               target == srcPath t,
               (sp, OccVar (Just ns') v') <- occurrencesOf s,
               ns' == ns,
               v' == v
             ]

-- ------------------------------------------------------------------ rename

data RenameError
  = NotALabel
  | LabelExists Text
  | InvalidName Text
  | NotALayoutValue
  | LayoutValueExists Text
  | InvalidLayoutValue Text
  | EmetRename R.RenameError
  | -- | the position is no name of the expressions or of the list of an @import (root ADR 0454)
    NotAVariable
  | -- | a name that points at no variable of @set
    NotASetVariable Text
  | ReservedVariable Text
  | InvalidVariable Text
  | VariableSyntax FilePath
  | VariableTaken FilePath Text
  | ListedTaken FilePath Text
  | BuiltinTaken Text
  | -- | a file that lists the variable with an error for its name: the file, the name, the code
    ListedUnclear FilePath Text Text
  | -- | a variable in the format of a running head of style.toml: the format, its line and column
    RunningHeadVariable Text Int Int
  | -- | a variable in title-format (root ADR 0463): the file that writes it (style.toml or a source) and the slot
    TitleFormatVariable FilePath Text
  | NewNameReferenced FilePath Text
  | -- | the position is no alias of a list of an @import nor a reference by one (root ADR 0458)
    NotAnAlias
  | -- | a new alias that breaks the rules of the names of a space of use of the original name
    InvalidAlias Text
  | -- | a new alias that is a command of the language or of a plugin, or a name the file lists
    AliasTaken Text
  deriving stock (Eq, Show)

-- | The message of an error of renaming, as the editor shows it.
renameMessage :: RenameError -> Text
renameMessage = \case
  NotALabel -> "ラベルの上で名前を変更してください"
  LabelExists l -> "すでにあるラベルの名前です: " <> l
  InvalidName l -> "ラベルに使えない名前です: " <> l
  NotALayoutValue -> "組版用の値の名前の上で名前を変更してください"
  LayoutValueExists l -> "すでにある組版用の値の名前です: " <> l
  InvalidLayoutValue l -> "組版用の値に使えない名前です: " <> l
  EmetRename e -> case e of
    R.RenameNotAName -> "関数、型、コンストラクタ、局所の名前の上で名前を変更してください"
    R.RenameBuiltin n -> "組み込みの名前は変えられません: " <> n
    R.RenameInvalid n -> ".emet の名前の規則に合いません: " <> n
    R.RenameReserved n -> "予約語です: " <> n
    R.RenameTaken n -> "同じ有効範囲の名前と重なります: " <> n
    R.RenameNotCommand n -> ".gm のコマンドの名前は、英小文字で始まり、英小文字と数字だけで書きます: " <> n
    R.RenameSyntax p -> "構文の誤りのあるファイルがあるため、名前を変えられません: " <> T.pack p
  NotAVariable -> "変数の上で名前を変更してください"
  NotASetVariable n -> "@set の変数ではないので、名前を変えられません: " <> n
  ReservedVariable n -> "予約語は @set の変数の名前に使えません: " <> n
  InvalidVariable n -> "@set の変数の名前に使えない名前です: " <> n
  VariableSyntax p -> "書き換えるファイルに構文の誤りがあるため、名前を変えられません: " <> T.pack p
  VariableTaken p n -> T.pack p <> " で @set した変数と名前が重なります: " <> n
  ListedTaken p n -> T.pack p <> " の @import が並べた名前と重なります: " <> n
  BuiltinTaken n -> "組み込みの式の名前と重なります: " <> n
  ListedUnclear p n c -> T.pack p <> " は " <> n <> " について " <> c <> " のエラーがあり、どの変数を指すか決められないため、名前を変えられません"
  RunningHeadVariable f l c -> "style.toml の柱の書式 " <> f <> "（" <> T.pack (show l) <> " 行 " <> T.pack (show c) <> " 列）がどのファイルの変数を指すかはページで決まるため、名前を変えられません"
  TitleFormatVariable f w -> T.pack f <> " の title-format の " <> w <> " がどのファイルの変数を指すかは見出しとキャプションのファイルで決まるため、名前を変えられません"
  NewNameReferenced p n -> T.pack p <> " に、改名すると変数を指す名前 " <> n <> " がすでにあります"
  NotAnAlias -> "別名の上で名前を変更してください"
  InvalidAlias n -> "別名の形が不正です: " <> n
  AliasTaken n -> "組み込みのコマンド、プラグインのコマンド、そのファイルが取り込んだ名前と重なります: " <> n

-- | Renames a label in its definition and every reference.
renameLabel :: Workspace -> FilePath -> Int -> Text -> Either RenameError [(Location, Text)]
renameLabel ws path off new = case sourceOf ws path >>= \s -> snd <$> occurrenceAt s off of
  Just (OccLabelRef l) -> go l
  Just (OccLabelDef l) -> go l
  _ -> Left NotALabel
  where
    go l
      | T.null new || T.any (\c -> c == ' ' || c == ']' || c == '[' || c == '\n') new = Left (InvalidName new)
      | new /= l && not (null (labelDefs ws new)) = Left (LabelExists new)
      | otherwise = Right [(x, new) | x <- nub (labelDefs ws l <> labelRefs ws l)]

-- | Rename one typed layout value in style.toml and loaded source files.
renameLayoutValue :: Workspace -> Text -> FilePath -> Int -> Text -> Either RenameError [(Location, Text)]
renameLayoutValue ws styleText path off new = case [(kind, name) | (kind, name, loc', _) <- sites, path == locPath loc', locStart loc' <= off, off <= locEnd loc'] of
  [] -> Left NotALayoutValue
  (kind, old) : _
    | length [() | (_, name, _, True) <- sites, name == old] /= 1 -> Left NotALayoutValue
    | not (valid new) -> Left (InvalidLayoutValue new)
    | old /= new, new `elem` [name | (_, name, _, True) <- sites] -> Left (LayoutValueExists new)
    | otherwise -> Right [(loc', new) | (kind', name, loc', _) <- sites, kind' == kind, name == old]
  where
    style = fromRight defaultStyle (parseStyle (FileId 0) styleText)
    styleSites = [(kind, name, Location "style.toml" start end, def) | (kind, name, start, end, def) <- layoutValueSites styleText]
    sites = styleSites <> concatMap sourceSites [src | src <- allSources ws, srcInProject src]
    valid name = case T.uncons name of
      Just (first, rest) -> name `notElem` ["pt", "in", "mm", "Q", "H", "zw", "ベタ", "全角", "二分", "三分", "四分", "五分", "六分", "八分", "二分四分"] && isAsciiLower first && T.all (\c -> isAsciiLower c || isDigit c || c == '-') rest
      Nothing -> False
    sourceSites src = case srcAst src of
      File _ blocks -> concatMap (blockSites src) blocks
    blockSites src (Located _ block) = case block of
      Attributed commands next -> concatMap (blockSites src) commands <> maybe [] (blockSites src) next
      BlockCommand (Located _ "style-def") (Located _ (Positional (Word kind)) : _ : args) _
        | Just styleKind <- styleKindOf kind ->
            [ (kindOf styleKind key, name, loc', False)
            | Located argSpan (Keyword (Located _ key) value) <- args,
              Just valueText <- [case value of Word n -> Just n; StringLit n -> Just n; _ -> Nothing],
              (name, loc') <- argumentSites src argSpan,
              name `elem` layoutValueNames style styleKind key,
              kindOf styleKind key == "count" || name == valueText
            ]
      _ -> []
    kindOf :: StyleKind -> Text -> Text
    kindOf styleKind key = case layoutValueNames style styleKind key of
      names | any (\n -> ("length", n) `elem` declared) names -> "length"
      names | any (\n -> ("aki", n) `elem` declared) names -> "aki"
      _ -> "count"
    declared = [(kind, name) | (kind, name, _, True) <- styleSites]
    argumentSites src span' =
      let bytes = TE.encodeUtf8 (srcText src)
          fragment = TE.decodeUtf8Lenient (BS.take (spanEnd span' - spanStart span') (BS.drop (spanStart span') bytes))
          (_, afterEq) = T.breakOn "=" fragment
          prefix = T.take (T.length fragment - T.length afterEq) fragment <> "="
          parts = T.splitOn "+" (T.drop 1 afterEq)
          prefixes = scanl (\before part -> before <> part <> "+") "" parts
       in [ (name, Location (srcPath src) start (start + BS.length (TE.encodeUtf8 name)))
          | not (T.null afterEq),
            (beforePart, part) <- zip prefixes parts,
            let name = T.dropAround (\c -> c == '"' || c == ' ' || c == '\t') part,
            not (T.null name),
            let (beforeName, found) = T.breakOn name part,
            not (T.null found),
            let start = spanStart span' + BS.length (TE.encodeUtf8 (prefix <> beforePart <> beforeName))
          ]

{- | Renames a name of a .emet (docs/adr/0170): in the .emet of the
program, and for a function .gm calls by its name, the calls of .gm and
the filters of [[filters]] in the text of manifest.toml given. The
program is the one last checked; the texts are the editor's.
-}
renameEmet :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> Either RenameError [(Location, Text)]
renameEmet ws manifest path off new = do
  prog <- maybe (Left (EmetRename R.RenameNotAName)) Right (lastProgramOf ws)
  let files = Map.fromList [(p, (m, fromMaybe t (emetText ws p))) | (p, (_, t, m)) <- Map.toList (programModules prog)]
  r <- either (Left . EmetRename) Right (R.emetRename files path off new)
  let gmEdits = case R.rnExported r of
        Just (p, old, kind, hasString)
          | new /= old,
            kind == KindFn || not hasString ->
              [ l
              | e <- Map.findWithDefault [] p (programExports prog),
                exFunction e == old,
                exKind e == kind,
                -- the aliases and the references by them stay (root ADR 0458)
                Just l <- map (nameIn old) (filter (`notElem` byAlias) (callsIn prog ws e))
              ]
                <> [l | kind == KindFilter, l <- filterNames manifest p old]
        _ -> []
  pure ([(Location p s e, new) | (p, s, e) <- R.rnEdits r] <> [(l, new) | l <- gmEdits])
  where
    byAlias = [loc s sp | s <- allSources ws, (sp, occ) <- occurrencesOf s, byAliasIn s occ]
    -- the name after the namespace in a call of .gm: ns.name
    nameIn old (Location p s e) = do
      src <- sourceOf ws p
      let piece = BS.take (e - s) (BS.drop s (TE.encodeUtf8 (srcText src)))
          needle = TE.encodeUtf8 ("." <> old)
          (pre, rest) = BS.breakSubstring needle piece
          after = BS.drop (BS.length needle) rest
          isNameByte b = b == 95 || b == 45 || (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
          plain = TE.encodeUtf8 old
          -- a name listed by @import, called without a namespace (root ADR 0451)
          unqualified = plain `BS.isPrefixOf` piece && not (maybe False (\(b, _) -> isNameByte b || b == 46) (BS.uncons (BS.drop (BS.length plain) piece)))
          found
            | unqualified = Just (Location p s (s + BS.length plain))
            | BS.null rest || maybe False (isNameByte . fst) (BS.uncons after) = Nothing
            | otherwise = Just (Location p (s + BS.length pre + 1) (s + BS.length pre + BS.length needle))
      found

-- | The program of the last evaluation that checked the functions (docs/adr/0170).
lastProgramOf :: Workspace -> Maybe Program
lastProgramOf ws = programOf ws <|> wsLastFunctions ws

-- | The text of a .emet: the editor's, or the one the last check read.
emetTextOf :: Workspace -> FilePath -> Maybe Text
emetTextOf ws p = emetText ws p <|> (lastProgramOf ws >>= \prog -> (\(_, t, _) -> t) <$> Map.lookup p (programModules prog))

{- | The values of filter of the tables of [[filters]] of manifest.toml
whose function is a path and whose filter is a name: the ranges of the
names in their strings.
-}
filterNames :: Maybe Text -> FilePath -> Text -> [Location]
filterNames manifest path old = maybe [] scan manifest
  where
    scan txt =
      let ls = T.splitOn "\n" txt
          offsets = scanl (\o l -> o + BS.length (TE.encodeUtf8 l) + 1) 0 ls
       in tables False [] (zip offsets ls)
    -- each table of [[filters]]: its keys and their strings with their ranges
    tables inFilters acc = \case
      [] -> close inFilters acc
      (o, l) : rest
        | "[" `T.isPrefixOf` T.strip l -> close inFilters acc <> tables (T.strip l == "[[filters]]") [] rest
        | inFilters, Just kv <- keyValue o l -> tables inFilters (kv : acc) rest
        | otherwise -> tables inFilters acc rest
    close inFilters acc =
      [ Location "manifest.toml" s e
      | inFilters,
        Just (f, _, _) <- [lookup "function" [(k, v) | (k, v) <- acc]],
        either (const False) (== path) (normalizeRelative (T.unpack f)),
        Just (n, s, e) <- [lookup "filter" acc],
        n == old
      ]
    keyValue o l = do
      let (k, rest) = T.breakOn "=" l
      v0 <- T.stripPrefix "=" rest
      let lead = T.takeWhile (== ' ') v0
          v = T.drop (T.length lead) v0
      (q, body) <- T.uncons v
      if q /= '"' && q /= '\''
        then Nothing
        else do
          let content = T.takeWhile (/= q) body
              start = o + BS.length (TE.encodeUtf8 (k <> "=" <> lead)) + 1
          pure (T.strip k, (content, start, start + BS.length (TE.encodeUtf8 content)))

-- ------------------------------------------------------------------ completion

data CompletionKind = CkCommand | CkConstant | CkLabel | CkPath | CkSwatch | CkCharStyle | CkParaStyle | CkSettingKey | CkSettingValue | CkStyleKind | CkTable
  deriving stock (Eq, Show)

data Completion = Completion !Text !CompletionKind | Described !Text !CompletionKind !Text
  deriving stock (Eq, Show)

cmpLabel :: Completion -> Text
cmpLabel (Completion n _) = n
cmpLabel (Described n _ _) = n

cmpKind :: Completion -> CompletionKind
cmpKind (Completion _ k) = k
cmpKind (Described _ k _) = k

cmpDocumentation :: Completion -> Maybe Text
cmpDocumentation (Completion _ _) = Nothing
cmpDocumentation (Described _ _ doc) = Just doc

{- | Text since the innermost command opener on this line. Nested array
brackets in an expression keep the expression as their context.
-}
activeBracket :: Text -> Maybe Text
activeBracket line = go 0 [] False (T.unpack line)
  where
    go _ ((start, _) : _) False [] = Just (T.drop start line)
    go _ _ _ [] = Nothing
    go pos frames quoted ('\\' : _ : rest) = go (pos + 2) frames quoted rest
    go pos frames@((_, True) : _) quoted ('"' : rest) = go (pos + 1) frames (not quoted) rest
    go pos frames False ('[' : rest) =
      let frame = case frames of
            f@(_, True) : _ -> f
            _ -> (pos + 1, take 1 rest == "=")
       in go (pos + 1) (frame : frames) False rest
    go pos (_ : frames) False (']' : rest) = go (pos + 1) frames False rest
    go pos frames quoted (_ : rest) = go (pos + 1) frames quoted rest

-- | A code block keeps its body as raw text, even when it contains command openers.
codeBlockAt :: Int -> File -> Bool
codeBlockAt off (File _ blocks) = any inside blocks
  where
    inside (Located sp block) = case block of
      CodeBlock {} -> spanStart sp <= off && off < spanEnd sp
      BlockCommand _ _ body -> any inside body
      Attributed commands body -> any inside commands || maybe False inside body
      Fenced fbs -> any inside fbs
      BulletList items -> any (any inside) items
      OrderedList items -> any (any inside) items
      DefList groups -> any (any (any inside) . dgDefs) groups
      _ -> False

-- | Completion from the text before the cursor on its line.
completions :: Workspace -> FilePath -> Int -> [Completion]
completions ws path off = case sourceOf ws path of
  _ | isSettingsFile path -> maybe [] (\t -> tomlFileCompletions path t off) (Map.lookup path (wsOverlay ws))
  -- a .emet (docs/adr/0162)
  Nothing -> [Completion n (emetKind k) | Just text <- [emetText ws path], (n, k) <- emetCompletions (programOf ws) path text off]
  Just src
    | codeBlockAt off (srcAst src) -> []
    | Just names <- namespaceCompletions ws src off -> names
    | Just names <- importListCompletions ws src off -> names
  Just src ->
    let before = TE.decodeUtf8Lenient (BS.take off (TE.encodeUtf8 (srcText src)))
        lineBefore = T.takeWhileEnd (/= '\n') before
        open = activeBracket lineBefore
        lastOpen = fromMaybe "" open
        ws' = T.words lastOpen
        style = maybe defaultStyle evStyle (wsEvaluated ws)
        {- the styles of the file (docs/adr ADR 0014): of its evaluation, and
        of its @style-def lines while it does not evaluate -}
        local = maybe noLocalStyles erStyles (srcResult src)
        defined k = [n | (_, OccStyleDef k' n) <- occurrencesOf src, k' == k]
        -- code is the style of code blocks, not of @style, based-on or regex styles (golem-driver ADR 0017)
        paraNames = filter (/= "code") (nub (Map.keys (stParaStyles style) <> Map.keys (lsParaStyles local) <> defined ParagraphKind))
        charNames = nub (Map.keys (stCharStyles style) <> Map.keys (lsCharStyles local) <> defined CharacterKind)
        separatorNames = nub ("default" : Map.keys (stSeparators style))
        labels = nub [l | s <- allSources ws, (_, OccLabelDef l) <- occurrencesOf s]
        -- the dotted name before the cursor in an expression
        metaPath = case T.stripPrefix "=" (T.stripStart lastOpen) of
          Just _ -> Just (T.splitOn "." (T.takeWhileEnd (\c -> c == '.' || c == '_' || c `elem` ['a' .. 'z'] || c `elem` ['A' .. 'Z'] || c `elem` ['0' .. '9']) lastOpen))
          Nothing -> Nothing
        meta = maybe Map.empty (metadataValues . manifestMetadata . projectManifest . evProject) (wsEvaluated ws)
        projectVars = projectVarsOf ws
        -- the names the file lists by @import, without a namespace (root ADR 0451)
        listedOf k = [Completion n CkCommand | n <- listedNamesOf ws src k]
        -- a listed name over a built-in command is one candidate (root ADR 0453)
        commandsAnd builtins k = [Completion n CkCommand | n <- nub (builtins <> listedNamesOf ws src k)]
        -- whether a command of a name at the cursor calls the built-in one (root ADR 0471)
        builtinHere space n = callsBuiltin (sourceOverrides src) space n off
     in if maybe False (T.all nameChar) (T.stripPrefix "@" (T.stripStart lineBefore))
          then commandsAnd builtinBlockCommands KindBlock
          else
            if "@import " `T.isPrefixOf` T.stripStart lineBefore
              then [Completion (T.pack p) CkPath | p <- wsSourceFiles ws, p /= path]
              else case (T.stripPrefix "@manifest " (T.stripStart lineBefore), T.stripPrefix "@style-def " (T.stripStart lineBefore)) of
                (Just rest, _) -> manifestCompletions rest
                (_, Just rest) -> styleDefCompletions style paraNames charNames rest
                _ ->
                  -- the kinds of a page break (docs/adr ADR 0017)
                  if "@page-break " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                    then [Completion k CkSettingValue | k <- ["recto", "verso"]]
                    else -- the signed counts of @page-lines (docs/adr ADR 0030)
                      if "@page-lines " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                        then [Completion k CkSettingValue | k <- ["+1", "-1"]]
                        else
                          -- paragraph styles after the built-in @style at the start of a line (docs/adr ADR 0005, root ADR 0471)
                          if "@style " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore) && builtinHere BlockSpace "style"
                            then [Completion n CkParaStyle | n <- paraNames]
                            else
                              if "@separator " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                                then [Completion n CkSettingValue | n <- separatorNames]
                                else
                                  -- the names of the text frames after @frame (root ADR 0438)
                                  if "@frame " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                                    then [Completion n CkSettingValue | n <- Map.keys (stFrames style)]
                                    else
                                      if isNothing open
                                        then []
                                        else case metaPath of
                                          -- the keys of meta and of meta.roles (docs/adr ADR 0033)
                                          Just ["meta", _] -> [Completion k CkSettingKey | k <- Map.keys meta]
                                          Just ["meta", "roles", _] | Just (VHash rs) <- Map.lookup "roles" meta -> [Completion k CkSettingKey | k <- Map.keys rs]
                                          -- the keys of [vars] and of its tables (docs/adr/0185)
                                          Just ("vars" : keyPath@(_ : _)) | Just keys <- varKeys projectVars (init keyPath) -> [Completion k CkSettingKey | k <- keys]
                                          Just [_] | inOperand lastOpen -> expressionNames <> listedOf KindFn <> [Completion n CkSettingKey | n <- listedVarNames src]
                                          Just _ -> []
                                          _ -> case ws' of
                                            [] -> commandsAnd commandNames KindInline
                                            [_] | not (T.isSuffixOf " " lastOpen) -> commandsAnd commandNames KindInline
                                            (cmd : _)
                                              | cmd `elem` labelCommands -> [Completion l CkLabel | l <- labels]
                                              -- label= after the command of a note (root ADR 0422)
                                              | cmd `elem` noteCommands, not ("label=" `T.isInfixOf` lastOpen) -> [Completion "label=" CkSettingKey]
                                              | cmd == "color" -> [Completion n CkSwatch | n <- Map.keys (stSwatches style)]
                                              | cmd == "style", builtinHere InlineSpace "style" -> [Completion n CkCharStyle | n <- charNames]
                                            _ -> []
  where
    nameChar c = isAsciiLower c || isAsciiUpper c || isDigit c || c == '_' || c == '-'
    inOperand expression =
      let prefix = T.stripEnd (T.dropWhileEnd (\c -> isAsciiLower c || isAsciiUpper c || isDigit c || c == '_') expression)
       in maybe False (\(_, c) -> c `elem` ("=([+-*/%,<>&|!" :: String)) (T.unsnoc prefix)
    expressionNames =
      [ case n of
          "len" -> Described n CkCommand "文字列の文字数、または配列の要素数を返します。"
          "pi" -> Completion n CkConstant
          "e" -> Completion n CkConstant
          _ -> Completion n CkCommand
      | n <- builtinExpressionNames
      ]
    -- the built-in commands, then those of the plugins (docs/adr ADR 0031)
    commandNames = builtinInlineCommands <> maybe [] evPluginCommands (wsEvaluated ws)

-- | The names a source lists by @import of a .emet that are functions of a kind, by their aliases (root ADR 0451, root ADR 0458).
listedNamesOf :: Workspace -> Source -> Kind -> [Text]
listedNamesOf ws src kind =
  [ n
  | Just p <- [lastProgramOf ws],
    (n, (path, o)) <- Map.toList (emetListed src),
    any (\e -> exKind e == kind && exName e == o) (Map.findWithDefault [] path (programExports p))
  ]

-- | The variables a source lists by @import of a .gm, by their aliases (root ADR 0451, root ADR 0458).
listedVarNames :: Source -> [Text]
listedVarNames src = nub [n | Right site <- importsOf (srcAst src), not (".emet" `T.isSuffixOf` isPath site), n <- map lnAlias (importNames site)]

{- | Completion in the list of names of an @import (root ADR 0451): the
names a .emet gives .gm, or the variables a .gm sets. Nothing when the
cursor is not in the braces of an @import.
-}
importListCompletions :: Workspace -> Source -> Int -> Maybe [Completion]
importListCompletions ws src off = do
  let before = TE.decodeUtf8Lenient (BS.take off (TE.encodeUtf8 (srcText src)))
      lineBefore = T.takeWhileEnd (/= '\n') before
  rest <- T.stripPrefix "@import " (T.stripStart lineBefore)
  let (written, braces) = T.breakOn "{" rest
      path = T.dropAround (== '"') (T.strip written)
      -- the item before the cursor; only its first piece, the original name, is completed (root ADR 0458)
      item = T.takeWhileEnd (\c -> c /= '{' && c /= ',') braces
      firstPiece = case T.words item of
        [] -> True
        [_] -> not (" " `T.isSuffixOf` item)
        _ -> False
  if T.null braces || "}" `T.isInfixOf` braces
    then Nothing
    else
      Just $
        if not firstPiece
          then []
          else
            if ".emet" `T.isSuffixOf` path
              then
                nub
                  [ Described (exName e) CkCommand (exSignature e)
                  | Just p <- [lastProgramOf ws],
                    Right file <- [emetPath path],
                    e <- Map.findWithDefault [] file (programExports p),
                    exKind e `elem` [KindInline, KindBlock, KindFn]
                  ]
              else
                [ Completion v CkSettingKey
                | Right file <- [normalizeRelative (T.unpack path)],
                  Just t <- [sourceOf ws file],
                  Just r <- [srcResult t],
                  v <- nub (map fst (usageDefined (erUsage r)))
                ]

-- | The namespace vars of the project (docs/adr/0185); empty without a project.
projectVarsOf :: Workspace -> Map.Map Text Value
projectVarsOf = maybe Map.empty (projectVarValues . manifestVars . projectManifest . evProject) . wsEvaluated

-- | The keys of the table of [vars] at a path; Nothing where there is no table.
varKeys :: Map.Map Text Value -> [Text] -> Maybe [Text]
varKeys vars = \case
  [] -> Just (Map.keys vars)
  k : rest -> case Map.lookup k vars of
    Just (VHash t) -> varKeys t rest
    _ -> Nothing

-- | What a name completed in a .emet is, as a completion of the server.
emetKind :: IdeKind -> CompletionKind
emetKind = \case
  IdeFunction -> CkCommand
  IdeConstructor -> CkSettingValue
  IdeType -> CkStyleKind
  IdeModule -> CkTable
  IdeVariable -> CkSettingKey
  IdeRequirement -> CkSettingKey
  IdeKeyword -> CkStyleKind

{- | The functions of a namespace of a .emet after its name and a dot
(docs/adr/0162): the block commands after @ at the start of a line, the
pub fn in an expression, the inline commands after [. Nothing when the
text before the cursor is no such name.
-}
namespaceCompletions :: Workspace -> Source -> Int -> Maybe [Completion]
namespaceCompletions ws src off = do
  p <- programOf ws
  let before = TE.decodeUtf8Lenient (BS.take off (TE.encodeUtf8 (srcText src)))
      lineBefore = T.takeWhileEnd (/= '\n') before
      typed = T.takeWhileEnd (\c -> c == '.' || c == '-' || c == '_' || isAsciiAlphaNum c) lineBefore
      (q, _) = T.breakOnEnd "." typed
  ns <- T.stripSuffix "." q
  path <- Map.lookup ns (emetImports src)
  let exports = Map.findWithDefault [] path (programExports p)
      rest = T.dropEnd (T.length typed) lineBefore
      names kind = Just [Described (exName e) CkCommand (exSignature e) | e <- exports, exKind e == kind]
  case () of
    _
      | T.strip rest == "@" -> names KindBlock
      | Just expr <- activeBracket lineBefore, "=" `T.isPrefixOf` expr -> names KindFn
      | Just inner <- activeBracket lineBefore, inner == typed -> names KindInline
      | otherwise -> Nothing
  where
    isAsciiAlphaNum c = isAsciiLower c || isAsciiUpper c || isDigit c

{- | Completion after @manifest (docs/adr ADR 0014): the keys of [source]
(docs/adr ADR 0013), then the values of a key.
-}
manifestCompletions :: Text -> [Completion]
manifestCompletions rest = case T.words rest of
  ws'
    | T.null rest || T.isSuffixOf " " rest || null ws' -> keys
    | (key, value) <- T.breakOn "=" (last ws'), not (T.null value) -> [Completion v CkSettingValue | v <- valuesOf key]
    | otherwise -> keys
  where
    keys = [Completion (k <> "=") CkSettingKey | (k, _) <- sourceKeys]
    valuesOf = \case
      "paragraph-separator" -> map fst paragraphSeparators
      _ -> []

{- | Completion after @style-def (docs/adr ADR 0014): the kinds, then the
keys of the kind, then the values of a key. After regex come the
paragraph styles, then pattern= and style= (docs/adr ADR 0015).
-}
styleDefCompletions :: Style -> [Text] -> [Text] -> Text -> [Completion]
styleDefCompletions style paraNames charNames rest =
  let ws' = T.words rest
      trailing = T.null rest || T.isSuffixOf " " rest
      kinds = [Completion k CkStyleKind | k <- ["character", "paragraph", "regex"]]
   in case ws' of
        [] -> kinds
        [_] | not trailing -> kinds
        ["regex"] -> paragraphs
        ["regex", _] | not trailing -> paragraphs
        (kind : _ : _)
          | trailing -> [Completion (k <> "=") CkSettingKey | k <- keysOf kind]
          | (key, value) <- T.breakOn "=" (last ws'),
            not (T.null value),
            length ws' >= 3 ->
              valuesOf kind key
        _ -> []
  where
    paragraphs = [Completion n CkParaStyle | n <- paraNames]
    keysOf = \case
      "character" -> charStyleKeys
      "paragraph" -> paraStyleKeys
      "regex" -> regexStyleKeys
      _ -> []
    valuesOf kind = \case
      "based-on" -> case kind of
        "character" -> [Completion n CkCharStyle | n <- charNames]
        "paragraph" -> [Completion n CkParaStyle | n <- paraNames]
        _ -> []
      "font" -> [Completion r CkSettingValue | r <- Map.keys (stFonts style :: Map.Map Text FontRole)]
      "color" -> [Completion n CkSwatch | n <- Map.keys (stSwatches style)]
      "style" | kind == "regex" -> [Completion n CkCharStyle | n <- charNames]
      "line-breaks" | kind == "paragraph" -> [Completion v CkSettingValue | v <- lineBreaksValues]
      -- docs/adr/0189
      "align" | kind == "paragraph" -> [Completion v CkSettingValue | v <- alignValues]
      key -> [Completion n CkSettingValue | Just k <- [styleKindOf kind], n <- layoutValueNames style k key]

{- | The schema of a file of settings the language server completes
(docs/adr ADR 0169): style.toml and preflight.toml at the root of the
project, and no other file.
-}
settingsSchemaOf :: FilePath -> Maybe Node
settingsSchemaOf = \case
  "style.toml" -> Just styleSchema
  "preflight.toml" -> Just rulesSchema
  _ -> Nothing

-- | A root configuration file with completion support.
isSettingsFile :: FilePath -> Bool
isSettingsFile path = path == "manifest.toml" || isJust (settingsSchemaOf path)

-- | Completion from the live text of a root configuration file.
tomlFileCompletions :: FilePath -> Text -> Int -> [Completion]
tomlFileCompletions "manifest.toml" text off = case contextAt text off of
  AtValue path element quote _ ->
    [Completion (if quote == Bare then "\"" <> v <> "\"" else v) CkSettingValue | v <- manifestChoiceValues path element]
  _ -> []
tomlFileCompletions path text off = maybe [] (\schema -> tomlCompletions schema text off) (settingsSchemaOf path)

{- | Completion in a TOML file of a schema (docs/adr ADR 0169): the steps
of a header, the keys of a table not written in it yet, the values of an
enumeration, true and false, and the names a value refers to.
-}
tomlCompletions :: Node -> Text -> Int -> [Completion]
tomlCompletions schema text off = case contextAt text off of
  AtHeader segs _ -> case nodeAt schema segs >>= tableOf of
    Just (NTable kvs) -> [Completion k CkTable | (k, n) <- kvs, tableLike n]
    Just (NNamed ns _) -> namesUnder ns segs
    _ -> []
  AtKey path keys _ -> case nodeAt schema path >>= tableOf of
    Just (NTable kvs) ->
      [ Completion k CkSettingKey
      | (k, n) <- kvs,
        n /= NRejected,
        k `notElem` keys,
        -- the tables of an array are each their own; the file tells only of the others
        crossesArray schema path || (path <> [k]) `notElem` defined
      ]
    Just (NNamed ns _) -> namesUnder ns path
    _ -> []
  AtValue path element q _ -> nub (maybe [] (values element) (nodeAt schema path) <> layoutNames path q)
    where
      values inArr = \case
        NValue l | not inArr -> leaf l
        NArray n | inArr -> values False n
        NEither ns -> concatMap (values inArr) ns
        _ -> []
      leaf = \case
        LEnum vs -> [Completion (quoted v) CkSettingValue | v <- vs]
        LBoolean | q == Bare -> [Completion b CkSettingValue | b <- ["true", "false"]]
        LFalse | q == Bare -> [Completion "false" CkSettingValue]
        LRef ns -> [Completion (quoted n) (nameKind ns) | n <- refNames ns path]
        _ -> []
      quoted v = if q == Bare then "\"" <> v <> "\"" else v
  Nowhere -> []
  where
    defined = definedPaths text
    layoutNames path q
      | schema /= styleSchema = []
      | otherwise =
          [ Completion (if q == Bare then "\"" <> name <> "\"" else name) CkSettingValue
          | ["values", declaredKind, name] <- defined,
            declaredKind `elem` layoutKinds path,
            path /= ["values", declaredKind, name]
          ]
    layoutKinds path = case path of
      ["values", kind, _] | kind `elem` ["length", "aki", "count"] -> [kind]
      _ | "aki-sets" `elem` path, last path `elem` ["optimum", "minimum", "maximum"] -> ["aki"]
      _ -> maybe [] kinds (nodeAt styleSchema path)
      where
        kinds = \case
          NValue LDimension -> ["length"]
          NValue LInteger | last path `elem` ["lines", "keep-first-lines", "keep-last-lines", "keep-with-next", "space-before", "space-after", "space-between"] -> ["count"]
          NEither ns -> concatMap kinds ns
          _ -> []
    -- the names a namespace has: the built-in ones, then those of the file in its order
    names ns = nub (builtinNames ns <> [n | (ns', n) <- concatMap (namesOn schema) defined, ns' == ns])
    namesUnder ns path = case ns of
      Just x -> [Completion n (nameKind x) | n <- names x]
      Nothing -> [Completion n CkSettingValue | n <- nub [last p | p <- defined, length p == length path + 1, take (length path) p == path]]
    {- a style is not based on itself, nor on code, the style of code blocks
    (golem-project ADR 0008, golem-driver ADR 0017) -}
    refNames ns path =
      [ n
      | n <- names ns,
        (ns, n) `notElem` namesOn schema path,
        not (ns == ParaStyles && n == "code")
      ]

-- | The node of a table: a table, or the table among several shapes.
tableOf :: Node -> Maybe Node
tableOf = \case
  n@(NTable _) -> Just n
  n@(NNamed _ _) -> Just n
  NEither ns -> listToMaybe (mapMaybe tableOf ns)
  _ -> Nothing

-- | A node a header can name: a table, or an array of tables.
tableLike :: Node -> Bool
tableLike = \case
  NTable _ -> True
  NNamed _ _ -> True
  NArray n -> tableLike n
  NEither ns -> any tableLike ns
  _ -> False

-- | Whether a path goes through an array of the schema.
crossesArray :: Node -> [Text] -> Bool
crossesArray node = \case
  [] -> False
  path@(k : rest) -> case node of
    NTable kvs -> maybe False (`crossesArray` rest) (lookup k kvs)
    NNamed _ n -> crossesArray n rest
    NArray _ -> True
    NEither ns -> any (\n -> isJust (nodeAt n path) && crossesArray n path) ns
    _ -> False

-- | The names a path defines: each step that is a key of a named table of a namespace.
namesOn :: Node -> [Text] -> [(Namespace, Text)]
namesOn node = \case
  [] -> []
  path@(k : rest) -> case node of
    NTable kvs -> maybe [] (`namesOn` rest) (lookup k kvs)
    NNamed ns n -> [(x, k) | Just x <- [ns]] <> namesOn n rest
    NArray n -> namesOn n path
    NEither ns -> case [n | n <- ns, isJust (nodeAt n path)] of
      (n : _) -> namesOn n path
      [] -> []
    _ -> []

-- | The built-in names of a namespace (docs/adr ADR 0169).
builtinNames :: Namespace -> [Text]
builtinNames = \case
  CharStyles -> Map.keys builtinCharStyles
  ParaStyles -> Map.keys builtinParaStyles
  AkiSets -> builtinAkiSetNames
  _ -> []

nameKind :: Namespace -> CompletionKind
nameKind = \case
  CharStyles -> CkCharStyle
  ParaStyles -> CkParaStyle
  Swatches -> CkSwatch
  _ -> CkSettingValue

-- ------------------------------------------------------------------ hover

{- | The value of the @[= ...]@ under the cursor. Values decided by S1 use
the S1 result; page numbers are decided by layout (S2).
-}
hover :: Workspace -> FilePath -> Int -> Maybe Text
hover ws path off
  -- the type of a function in a .emet (docs/adr/0162)
  | isEmet path = do
      text <- emetText ws path
      -- the type of a local name, while the text is the one checked (docs/adr/0170)
      (lastProgramOf ws >>= \prog -> emetLocalHover prog path text off)
        <|> (programOf ws >>= \prog -> emetHover prog path text off)
  | otherwise = do
      src <- sourceOf ws path
      -- the signature of the function of a .emet that a name calls (docs/adr/0162)
      case [e | (sp, occ) <- occurrencesOf src, onName sp occ, Just e <- [occurrenceExport ws src occ]] of
        e : _ -> Just (exSignature e)
        [] -> gmHover ws src off
  where
    onName sp = \case
      OccCommand _ _ -> spanStart sp <= off && off <= spanEnd sp
      OccFunction q -> spanStart sp <= off && off <= spanStart sp + BS.length (TE.encodeUtf8 q)
      _ -> False

-- | The hover of a .gm.
gmHover :: Workspace -> Source -> Int -> Maybe Text
gmHover ws src off = do
  (_, occ) <- listToMaybe (sortOn (negate . spanLength . fst) [o | o@(sp, OccExpr _) <- occurrencesOf src, spanStart sp <= off, off <= spanEnd sp]) `orElse` occurrenceAt src off
  case occ of
    OccExpr e -> Just (evaluate src e)
    OccPageRef _ -> Just "ページ番号はレイアウト（S2）で決まるため、ここでは表示できません"
    _ -> Nothing
  where
    orElse (Just x) _ = Just x
    orElse Nothing y = y
    evaluate s0 e =
      let r = srcResult s0
          vars = maybe Map.empty erExports r
          imports =
            Map.fromList
              [ (ns, maybe Map.empty erExports (sourceOf ws target >>= srcResult))
              | Just res <- [r],
                (ns, target, _) <- usageImports (erUsage res)
              ]
          chapterCount = maybe 0 (length . projectChapters . evProject) (wsEvaluated ws)
          docNs = Map.fromList [("chapters", VHash (Map.fromList [("count", VNat (fromIntegral chapterCount))]))]
          s1 = isJust (wsEvaluated ws >>= evBook)
          -- the namespace vars of [vars] (docs/adr/0185), which the hover needs
          -- for the new value (docs/adr/0211)
          env = plainEnv vars (Map.insert "vars" (projectVarsOf ws) (Map.insert "doc" docNs imports))
       in case evalExpr env e of
            Left d -> "評価できません: " <> diagMessage d
            Right v ->
              let shown = fromRight (typeName v) (embedValue (locSpan e) v)
               in if usesDoc (locValue e) && not s1 then shown <> "（文書構造 S1 が未確定）" else shown
    usesDoc = \case
      EVar ("doc" : _) -> True
      EBinary _ a b -> usesDoc (locValue a) || usesDoc (locValue b)
      ERange a b -> usesDoc (locValue a) || usesDoc (locValue b)
      EUnary _ a -> usesDoc (locValue a)
      ECall _ es -> any (usesDoc . locValue) es
      _ -> False

-- ------------------------------------------------------------------ formatting

{- | The formatted text of the whole file, or Nothing when it has syntax
errors or is already formatted.
-}
formatting :: Workspace -> FilePath -> Maybe Text
formatting ws path
  -- a .emet, by fmt of golem-emet (docs/adr/0162)
  | isEmet path = do
      text <- emetText ws path
      case formatEmet text of
        Right t | t /= text -> Just t
        _ -> Nothing
  | otherwise = do
      src <- sourceOf ws path
      case format (srcText src) of
        Formatted t | t /= srcText src -> Just t
        _ -> Nothing

-- ------------------------------------------------------------------ outline

data Outline = Outline {olTitle :: !Text, olLevel :: !Int, olStart :: !Int, olEnd :: !Int, olChildren :: ![Outline]}
  deriving stock (Eq, Show)

-- | Headings as a hierarchy.
outline :: Workspace -> FilePath -> [Outline]
outline ws path = case sourceOf ws path of
  Nothing -> []
  Just src -> nest [Outline (title src is) l (spanStart sp) (spanEnd sp) [] | (sp, l, is) <- headings (srcAst src)]
  where
    headings (File _ bs) = concatMap h bs
    h (Located sp b) = case b of
      Heading l is -> [(sp, l, is)]
      Attributed _ (Just t) -> h t
      Fenced fbs -> concatMap h fbs
      _ -> []
    title src is = T.strip (T.concat (map (piece src) is))
    piece src (Located sp i) = case i of
      Text t -> t
      -- the character, not the source with its backslash (golem-parser ADR 0010)
      Escaped c -> T.singleton c
      SoftBreak -> ""
      _ -> TE.decodeUtf8Lenient (BS.take (spanLength sp) (BS.drop (spanStart sp) (TE.encodeUtf8 (srcText src))))
    nest [] = []
    nest (o : rest) =
      let (kids, others) = span ((> olLevel o) . olLevel) rest
       in o {olChildren = nest kids} : nest others

-- ------------------------------------------------------------------ folding ranges

{- | The folding ranges of a source (root ADR 0459): for each body between
::: lines, the line that opens and the line that closes, or the last line
of the body when it is not closed; zero-based, in the order of the lines
that open.
-}
foldingRanges :: Text -> [(Int, Int)]
foldingRanges text = sortOn fst (walk 0 (fst (parse (FileId 0) text)))
  where
    bytes = TE.encodeUtf8 text
    lineAt off = BS.count 10 (BS.take off bytes)
    walk start n =
      let placed = zip (scanl (+) start (map C.elementWidth (C.nodeChildren n))) (C.nodeChildren n)
          here = case C.nodeKind n of
            C.NDiv ->
              case [off | (off, C.ElemToken t) <- placed, C.tokKind t == C.KDivMark] of
                [open] -> [(lineAt open, lineAt (max open (start + C.nodeWidth n - 1)))]
                (open : close : _) -> [(lineAt open, lineAt close)]
                [] -> []
            _ -> []
       in here <> concat [walk off m | (off, C.ElemNode m) <- placed]

-- ------------------------------------------------------------------ semantic tokens

{- | The semantic tokens of a .gm text (golem-lsp ADR 0006): its CST
classified by the kind of each token and of its parent, in document order,
in the negotiated unit, and split at newlines.
-}
semanticTokens :: Encoding -> Text -> [SemanticTokenAbsolute]
semanticTokens enc text = semanticTokensOf enc text (fst (parse (FileId 0) text))

-- | The same, from a CST of the text already parsed.
semanticTokensOf :: Encoding -> Text -> C.Node -> [SemanticTokenAbsolute]
semanticTokensOf enc text root = placeTokens enc text (classify 0 root)

{- | The byte ranges of a .gm text that semantic tokens cover (golem-lsp
ADR 0008): the CST tokens whose parent is a command or an expression node,
without their newlines, the indentation of a block command, and errors.
The contents of a prose slot have the slot as their parent and are not in them.
-}
commandBytes :: Text -> [(Int, Int)]
commandBytes text = concatMap (filter (uncurry (<)) . withoutNewlines) (walk 0 (fst (parse (FileId 0) text)))
  where
    bytes = TE.encodeUtf8 text
    walk start n = go start True (C.nodeChildren n)
      where
        parent = C.nodeKind n
        go _ _ [] = []
        go off first (e : es) =
          let w = C.elementWidth e
           in case e of
                C.ElemNode m -> walk off m <> go (off + w) False es
                C.ElemToken (C.Token k _)
                  | parent `elem` commandNodes || parent `elem` expressionNodes,
                    k `notElem` [C.KNewline, C.KError],
                    not (first && parent == C.NBlockCommand && k == C.KWhitespace) ->
                      (off, off + w) : go (off + w) False es
                  | otherwise -> go (off + w) False es
    withoutNewlines (s, e) = case BS.elemIndex 10 (BS.take (e - s) (BS.drop s bytes)) of
      Just i -> (s, s + i) : withoutNewlines (s + i + 1, e)
      Nothing -> [(s, e)]

-- | The nodes of commands and their arguments (golem-lsp ADR 0008).
commandNodes :: [C.SyntaxKind]
commandNodes = [C.NInlineCommand, C.NBlockCommand, C.NArgument, C.NKeywordArgument, C.NSplatArgument]

-- | The nodes of expressions (golem-lsp ADR 0008).
expressionNodes :: [C.SyntaxKind]
expressionNodes = [C.NExpr, C.NBinaryExpr, C.NUnaryExpr, C.NCallExpr, C.NLiteral, C.NVarExpr, C.NArrayExpr, C.NHashExpr, C.NHashEntry, C.NParenExpr, C.NRangeExpr]

{- | The semantic tokens of a .emet text (docs/adr/0170): the tokens of its
lossless syntax tree, placed as those of a .gm.
-}
emetSemanticTokens :: Encoding -> Text -> [SemanticTokenAbsolute]
emetSemanticTokens enc text =
  placeTokens enc text [(hlStart h, hlEnd h, emetTokenType (hlType h), [SemanticTokenModifiers_Declaration | hlDeclaration h]) | h <- emetHighlights text]

emetTokenType :: HlType -> SemanticTokenTypes
emetTokenType = \case
  HlComment -> SemanticTokenTypes_Comment
  HlKeyword -> SemanticTokenTypes_Keyword
  HlFunction -> SemanticTokenTypes_Function
  HlVariable -> SemanticTokenTypes_Variable
  HlParameter -> SemanticTokenTypes_Parameter
  HlType -> SemanticTokenTypes_Type
  HlTypeParameter -> SemanticTokenTypes_TypeParameter
  HlEnumMember -> SemanticTokenTypes_EnumMember
  HlNamespace -> SemanticTokenTypes_Namespace
  HlString -> SemanticTokenTypes_String
  HlNumber -> SemanticTokenTypes_Number
  HlOperator -> SemanticTokenTypes_Operator
  HlMacro -> SemanticTokenTypes_Macro

-- | Tokens at byte ranges, in the negotiated unit and split at newlines.
placeTokens :: Encoding -> Text -> [(Int, Int, SemanticTokenTypes, [SemanticTokenModifiers])] -> [SemanticTokenAbsolute]
placeTokens enc text = concatMap place
  where
    li = mkLineIndex text
    bytes = TE.encodeUtf8 text
    place (s, e, ty, mods) =
      [ SemanticTokenAbsolute (fromIntegral l) (fromIntegral c) (fromIntegral (c' - c)) ty mods
      | (a, b) <- lineParts s e,
        let LineCol l c = toLineCol enc li a
            LineCol _ c' = toLineCol enc li b,
        c' > c
      ]
    -- the parts of [s, e) between its newlines, without them
    lineParts s e = case BS.elemIndex 10 (BS.take (e - s) (BS.drop s bytes)) of
      Just i -> (s, s + i) : lineParts (s + i + 1) e
      Nothing -> [(s, e)]

{- | (start, end, type, modifiers) of each highlighted token under a node at
the offset. A node inside an expression (NExpr, a splat argument, or an
expression node) gives its punctuation the operator type (golem-lsp ADR 0007,
golem-lsp ADR 0008); a prose slot or a command inside it does not.
-}
classify :: Int -> C.Node -> [(Int, Int, SemanticTokenTypes, [SemanticTokenModifiers])]
classify = classifyIn False

classifyIn :: Bool -> Int -> C.Node -> [(Int, Int, SemanticTokenTypes, [SemanticTokenModifiers])]
classifyIn outer start n = go start True [] False (C.nodeChildren n)
  where
    parent = C.nodeKind n
    inExpr = (outer || parent `elem` (C.NSplatArgument : expressionNodes)) && parent `notElem` [C.NProseSlot, C.NInlineCommand]
    go _ _ _ _ [] = []
    go off first idents word (e : es) =
      let w = C.elementWidth e
       in case e of
            C.ElemNode m -> classifyIn inExpr off m <> go (off + w) False idents word es
            C.ElemToken (C.Token k t) ->
              maybe [] (\(ty, ms) -> [(off, off + w, ty, ms)]) (tokenType (Place parent inExpr first idents word) k)
                <> go (off + w) False (if k == C.KIdent then idents <> [t] else idents) (word || k == C.KWord) es

{- | Where a token is: its parent's kind, whether it is inside an expression,
whether it is the first child, the identifiers before it, and whether a word
came before it under the same parent.
-}
data Place = Place C.SyntaxKind Bool Bool [Text] Bool

-- | The type of a token from its kind and its place.
tokenType :: Place -> C.SyntaxKind -> Maybe (SemanticTokenTypes, [SemanticTokenModifiers])
tokenType (Place parent inExpr first idents word) = \case
  C.KComment -> plain SemanticTokenTypes_Comment
  C.KProofComment -> Just (SemanticTokenTypes_Comment, [SemanticTokenModifiers_Modification])
  C.KAt | parent == C.NBlockCommand -> plain SemanticTokenTypes_Decorator
  C.KIdent
    | parent == C.NBlockCommand, null idents -> plain SemanticTokenTypes_Decorator
    -- the name of @set (golem-lsp ADR 0008)
    | parent == C.NBlockCommand, idents == ["set"] -> Just (SemanticTokenTypes_Variable, [SemanticTokenModifiers_Declaration])
    | parent == C.NInlineCommand, null idents -> plain SemanticTokenTypes_Function
    -- both names of ns.f (golem-lsp ADR 0007)
    | parent == C.NCallExpr -> plain SemanticTokenTypes_Function
    | parent == C.NVarExpr -> plain SemanticTokenTypes_Variable
    -- the key of a hash (golem-lsp ADR 0008)
    | parent == C.NHashEntry -> plain SemanticTokenTypes_Property
  C.KWord
    | parent == C.NKeywordArgument -> plain (if word then SemanticTokenTypes_String else SemanticTokenTypes_Parameter)
    | parent == C.NArgument -> plain SemanticTokenTypes_String
    | parent == C.NCodeBlock -> plain SemanticTokenTypes_Type
  C.KString -> plain SemanticTokenTypes_String
  C.KExprOpen -> plain SemanticTokenTypes_Keyword
  C.KNumber -> plain SemanticTokenTypes_Number
  C.KKeyword -> plain SemanticTokenTypes_Keyword
  C.KOperator -> plain SemanticTokenTypes_Operator
  C.KEscape -> plain SemanticTokenTypes_Macro
  C.KNumberMark -> plain SemanticTokenTypes_Operator
  C.KNumberBody -> plain SemanticTokenTypes_Number
  C.KHash | parent == C.NHeading -> plain SemanticTokenTypes_Keyword
  C.KText | parent == C.NHeading -> plain SemanticTokenTypes_Namespace
  C.KDash | parent == C.NListItem -> plain SemanticTokenTypes_Keyword
  C.KPlus | parent == C.NListItem -> plain SemanticTokenTypes_Keyword
  C.KEquals
    | parent == C.NDefTerm -> plain SemanticTokenTypes_Keyword
    -- the equals signs of keyword arguments and of @set (golem-lsp ADR 0008)
    | parent `elem` [C.NKeywordArgument, C.NBlockCommand] -> plain SemanticTokenTypes_Operator
  -- the mark of a new definition (golem-lsp ADR 0008)
  C.KNewDefMark -> plain SemanticTokenTypes_Keyword
  C.KPipe -> plain SemanticTokenTypes_Operator
  C.KDelim -> plain SemanticTokenTypes_Operator
  C.KFence -> plain SemanticTokenTypes_Keyword
  -- the ::: of the lines around a body (root ADR 0459)
  C.KDivMark -> plain SemanticTokenTypes_Keyword
  -- \*[ and **[ and their closing bracket (golem-lsp ADR 0008)
  k | parent == C.NSplatArgument, k `elem` [C.KStar, C.KRBracket] -> plain SemanticTokenTypes_Operator
  -- the spaces of commands and expressions, without the indentation of a
  -- block command (golem-lsp ADR 0008)
  C.KWhitespace
    | parent `elem` commandNodes || parent `elem` expressionNodes,
      not (first && parent == C.NBlockCommand) ->
        plain SemanticTokenTypes_Operator
  -- the brackets and the colon of an inline command (golem-lsp ADR 0007)
  k | parent == C.NInlineCommand, k `elem` [C.KLBracket, C.KColon, C.KRBracket] -> plain SemanticTokenTypes_Operator
  -- the punctuation of an expression (golem-lsp ADR 0007)
  k | inExpr, k `elem` exprPunctuation -> plain SemanticTokenTypes_Operator
  _ -> Nothing
  where
    plain t = Just (t, [])
    exprPunctuation = [C.KDot, C.KLParen, C.KRParen, C.KComma, C.KLBracket, C.KRBracket, C.KLBrace, C.KRBrace, C.KColon]

-- ------------------------------------------------------------------ variables of @set

-- | A variable of @set: the file that sets it and its name (root ADR 0454).
type SetVariable = (FilePath, Text)

-- | The names a file sets with @set, wherever they are, with the spans of the names.
setSites :: File -> [(Text, SrcSpan)]
setSites (File _ bs) = concatMap go bs
  where
    go (Located _ b) = case b of
      SetVar (Located vsp v) _ -> [(v, vsp)]
      BulletList items -> concatMap (concatMap go) items
      OrderedList items -> concatMap (concatMap go) items
      DefList gs -> concatMap (concatMap (concatMap go) . dgDefs) gs
      BlockCommand _ _ body -> concatMap go body
      Attributed cs t -> concatMap go cs <> maybe [] go t
      Fenced fbs -> concatMap go fbs
      _ -> []

setNamesOf :: Source -> [Text]
setNamesOf = map fst . setSites . srcAst

-- | The @import lines of a source.
importSitesOf :: Source -> [ImportSite]
importSitesOf = rights . importsOf . srcAst

{- | The file an @import line of a variable file points at: through the
import graph of the project (root ADR 0455), by the path as the line
writes it. Nothing for a .emet, or outside the project.
-}
importTarget :: Workspace -> Source -> ImportSite -> Maybe FilePath
importTarget ws s site
  | ".emet" `T.isSuffixOf` isPath site = Nothing
  | otherwise =
      listToMaybe
        [ sfPath sf
        | srcInProject s,
          Just e <- [wsEvaluated ws],
          let ImportGraph g = projectImports (evProject e),
          (tfid, site') <- Map.findWithDefault [] (srcFile s) g,
          isPath site' == isPath site,
          Just sf <- [Map.lookup tfid (projectSources (evProject e))]
        ]

-- | Whether an occurrence is a name of the expressions or of the list of an @import.
isVariableOccurrence :: Occurrence -> Bool
isVariableOccurrence = \case
  OccVar _ _ -> True
  OccListed _ _ -> True
  OccAlias {} -> True
  _ -> False

-- | The name an occurrence of a variable writes.
occurrenceName :: Occurrence -> Maybe Text
occurrenceName = \case
  OccVar _ v -> Just v
  OccListed _ n -> Just n
  OccAlias _ _ a -> Just a
  _ -> Nothing

{- | The variable of @set an occurrence at a span of a source points at
(root ADR 0454), with @extra@ a variable taken as set besides those the
files set. A name without a namespace is the variable the file sets, or
the one an @import before it lists; a name with a namespace is of the
file the last @import before it with that namespace points at; a name in
a list is of the file the line points at. A name without a namespace an
@import lists under an alias is the variable of its original name, and so
is the alias in the list (root ADR 0458). Nothing for a name that points
at no variable of @set, or at more than one.
-}
variableAt :: Workspace -> Maybe SetVariable -> Source -> SrcSpan -> Occurrence -> Maybe SetVariable
variableAt ws extra s sp = \case
  OccVar Nothing v
    | v `elem` setNamesOf s || extra == Just (srcPath s, v) -> Just (srcPath s, v)
    | otherwise -> case nub [(f, lnName l) | site <- before, l <- importNames site, lnAlias l == v, Just f <- [importTarget ws s site]] of
        [(f, n)] | sets f n -> Just (f, n)
        _ -> Nothing
  OccVar (Just ns) v -> case [site | site <- before, importNamespace site == Just ns] of
    [] -> Nothing
    sites -> listToMaybe (reverse sites) >>= importTarget ws s >>= \f -> if sets f v then Just (f, v) else Nothing
  OccListed _ n -> inList n
  OccAlias _ n _ -> inList n
  _ -> Nothing
  where
    inList n = case [site | site <- importSitesOf s, spanStart (isSpan site) <= spanStart sp, spanStart sp <= spanEnd (isSpan site)] of
      (site : _) -> importTarget ws s site >>= \f -> if sets f n then Just (f, n) else Nothing
      [] -> Nothing
    before = [site | site <- importSitesOf s, spanEnd (isSpan site) <= spanStart sp]
    sets f v = extra == Just (f, v) || maybe False ((v `elem`) . setNamesOf) (sourceOf ws f)

{- | Every occurrence of a variable of @set (root ADR 0454), with the span
of its name: its @set and its references in the file that sets it, the
name after the namespace in the files that import it with a namespace,
and the name in the list and the references in the files that list it,
the aliases of the lists and the references by them included (root ADR
0458).
-}
variableOccurrences :: Workspace -> Maybe SetVariable -> SetVariable -> [Location]
variableOccurrences ws extra var = map fst (variableOccurrencesNamed ws extra var)

-- | The same, with the name each writes.
variableOccurrencesNamed :: Workspace -> Maybe SetVariable -> SetVariable -> [(Location, Text)]
variableOccurrencesNamed ws extra var@(f, _) =
  -- the file that sets it first
  sortOn ((/= f) . locPath . fst) . nub $
    [ (Location (srcPath s) (spanStart nsp) (spanEnd nsp), written)
    | s <- allSources ws,
      (sp, occ) <- occurrencesOf s,
      isVariableOccurrence occ,
      variableAt ws extra s sp occ == Just var,
      let nsp = nameSpan sp occ,
      Just written <- [occurrenceName occ]
    ]
  where
    -- the name of ns.name, after the namespace
    nameSpan sp = \case
      OccVar (Just ns) v -> let start = spanStart sp + BS.length (TE.encodeUtf8 ns) + 1 in SrcSpan (spanFile sp) start (start + BS.length (TE.encodeUtf8 v))
      _ -> sp

-- | The variable of @set at an offset of a file; Left when there is none.
variableAtOffset :: Workspace -> FilePath -> Int -> Either RenameError SetVariable
variableAtOffset ws path off = case sourceOf ws path >>= \s -> (s,) <$> occurrenceAt s off of
  Just (s, (sp, occ))
    | isVariableOccurrence occ -> maybe (Left (NotASetVariable (fromMaybe "" (occurrenceName occ)))) Right (variableAt ws Nothing s sp occ)
  _ -> Left NotAVariable

-- | The reserved names, which no variable of @set takes (G02275).
reservedVariableNames :: [Text]
reservedVariableNames = ["doc", "meta", "vars", "true", "false", "nil"]

-- | Whether a name can be written as the name of a @set and as a name of an expression.
validVariableName :: Text -> Bool
validVariableName n =
  not (T.null n)
    && not (T.any (`elem` ['.', ',', '{', '}']) n)
    && let (file, _, ds) = parseAst (FileId 0) ("@set " <> n <> " = 1\n\n[= " <> n <> "]\n")
        in not (hasErrors ds) && map fst (setSites file) == [n] && [v | (_, OccVar Nothing v) <- occurrences file] == [n, n]

{- | The places of style.toml that write a variable in the format of a
running head: @{set.name}@ and @{set.ns.name}@, with the name and its line
and column from 1.
-}
runningHeadVariables :: Text -> [(Text, Text, Int, Int)]
runningHeadVariables style =
  [ (whole, name, l, c + 1)
  | (l, line) <- zip [1 ..] (T.lines style),
    (c, whole) <- finds line,
    let name = T.takeWhileEnd (/= '.') (T.dropEnd 1 whole)
  ]
  where
    finds = go 0
      where
        go off t = case T.breakOn "{set." t of
          (_, "") -> []
          (pre, rest) ->
            let (body, after) = T.breakOn "}" rest
                c = off + T.length pre
             in if T.null after then [] else (c, body <> "}") : go (c + T.length body + 1) (T.drop 1 after)

{- | The variables of @{set.<name>}@ and @{set.<namespace>.<name>}@ in the
title formats (root ADR 0463), of style.toml and of @style-def of each
file: the file, the slot as written and the name.
-}
titleFormatVariables :: Workspace -> Maybe Text -> [(FilePath, Text, Text)]
titleFormatVariables ws style =
  [("style.toml", slot n q, last n) | Just t <- [style], (_, refs) <- titleFormatSites (FileId 0) t, (RefVar n@(_ : _), q) <- refs]
    <> [ (srcPath s, slot n q, last n)
       | s <- allSources ws,
         (_, _, f) <- styleDefTitleFormats (srcAst s),
         Right parts <- [parseTitleFormat f],
         FormatRef (RefVar n@(_ : _)) q <- parts
       ]
  where
    slot n q = "{set." <> T.intercalate "." n <> (if q then "?" else "") <> "}"

{- | Renames a variable of @set (root ADR 0454): its @set, its references
in the file that sets it, the name after the namespace in the files that
import it with a namespace, and the name in the list and the references in
the files that list it. NotAVariable when the position is no name of the
expressions or of a list, for the rename of a label.
-}
renameVariable :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> Either RenameError [(Location, Text)]
renameVariable ws style path off new = do
  var@(f, old) <- variableAtOffset ws path off
  -- the aliases and the references by them stay (root ADR 0458)
  let edits = [l | (l, written) <- variableOccurrencesNamed ws Nothing var, written == old]
      files = nub (f : map locPath edits)
      sourcesOf = mapMaybe (sourceOf ws)
      -- the files that list the variable without an alias, with their lines that list it so; an item with an alias refers not to the original name (root ADR 0458)
      listers = [(s, ls) | s <- sourcesOf files, srcPath s /= f, let ls = [site | site <- importSitesOf s, any (unaliased old) (importNames site), importTarget ws s site == Just f], not (null ls)]
      fSource = sourceOf ws f
      clash = new /= old
  when (new `elem` reservedVariableNames) (Left (ReservedVariable new))
  unless (validVariableName new) (Left (InvalidVariable new))
  forM_ (sourcesOf files) $ \s -> when (hasErrors (snd (parse (FileId 0) (srcText s)))) (Left (VariableSyntax (srcPath s)))
  forM_ fSource $ \s -> do
    when (clash && new `elem` setNamesOf s) (Left (VariableTaken f new))
    when (clash && new `elem` [lnAlias l | site <- importSitesOf s, l <- importNames site]) (Left (ListedTaken f new))
  when (clash && new `elem` builtinExpressionNames) (Left (BuiltinTaken new))
  forM_ listers $ \(h, ls) -> do
    let hp = srcPath h
        listedOld = [site | site <- importSitesOf h, old `elem` map lnAlias (importNames site)]
    when (length listedOld > 1) (Left (ListedUnclear hp old "G02272"))
    when (old `elem` setNamesOf h) (Left (ListedUnclear hp old "G02274"))
    when (old `elem` builtinExpressionNames) (Left (ListedUnclear hp old "G02277"))
    when (clash && new `elem` setNamesOf h) (Left (VariableTaken hp new))
    when (clash && new `elem` [lnAlias l | site <- importSitesOf h, l <- importNames site, site `notElem` ls || not (unaliased old l)]) (Left (ListedTaken hp new))
    -- a reference to the new name after the list, which would point at the variable
    when (clash && not (null [() | (sp, OccVar Nothing v) <- occurrencesOf h, v == new, any (\site -> spanEnd (isSpan site) <= spanStart sp) ls])) (Left (NewNameReferenced hp new))
  forM_ (titleFormatVariables ws style) $ \(writer, whole, name) ->
    when (name `elem` [old, new]) (Left (TitleFormatVariable writer whole))
  forM_ (maybe [] runningHeadVariables style) $ \(whole, name, l, c) ->
    when (name `elem` [old, new]) (Left (RunningHeadVariable whole l c))
  -- a name written already that would point at the variable after the rename
  when clash $
    forM_ (variableOccurrences ws (Just (f, new)) (f, new)) $
      \l -> Left (NewNameReferenced (locPath l) new)
  pure [(l, new) | l <- edits]

-- ------------------------------------------------------------------ aliases of the lists

-- | Whether an item of a list is a name without an alias, or with the name as its alias.
unaliased :: Text -> ListedName -> Bool
unaliased n l = lnName l == n && lnAlias l == n

{- | An alias a position stands on (root ADR 0458): the path of the @import,
the original name, the alias, the items of the file that give the alias, and
the kinds of the definition of the original name (KindFn for a variable).
-}
data AliasSite = AliasSite
  { alPath :: !Text,
    alName :: !Text,
    alAlias :: !Text,
    alItems :: ![(ImportSite, ListedName)],
    alKinds :: ![Kind]
  }

-- | The items of the lists of a source with an alias apart from the original name.
aliasItems :: Source -> [(ImportSite, ListedName)]
aliasItems src = [(site, l) | site <- importSitesOf src, l <- importNames site, lnAlias l /= lnName l]

-- | The kinds of the definition an item of a list names: those the .emet gives it, or KindFn for a variable.
itemKinds :: Workspace -> ImportSite -> ListedName -> [Kind]
itemKinds ws site l
  | ".emet" `T.isSuffixOf` isPath site =
      nub
        [ exKind e
        | Just p <- [lastProgramOf ws],
          Right file <- [emetPath (isPath site)],
          e <- Map.findWithDefault [] file (programExports p),
          exName e == lnName l,
          exKind e `elem` [KindInline, KindBlock, KindFn]
        ]
  | otherwise = [KindFn]

{- | Whether an occurrence after an @import line refers to an item by its
alias: a call of a kind the item gives, or a variable of a variable file.
-}
refersBy :: Workspace -> Source -> Text -> (ImportSite, ListedName) -> (SrcSpan, Occurrence) -> Bool
refersBy ws src a (site, l) (sp, occ) =
  spanEnd (isSpan site) <= spanStart sp && case occ of
    OccVar Nothing v -> v == a && not (".emet" `T.isSuffixOf` isPath site) && v `notElem` setNamesOf src
    OccCommand True q -> q == a && KindInline `elem` itemKinds ws site l
    OccCommand False q -> q == a && KindBlock `elem` itemKinds ws site l
    OccFunction q -> q == a && KindFn `elem` itemKinds ws site l
    _ -> False

-- | The alias at an offset of a source: an alias in a list, or a reference by one.
aliasAt :: Workspace -> Source -> Int -> Maybe AliasSite
aliasAt ws src off = do
  o@(sp, occ) <- occurrenceAt src off
  a <- occurrenceAlias occ
  let items = [it | it@(_, l) <- aliasItems src, lnAlias l == a, case occ of OccAlias {} -> lnAliasSpan l == sp; _ -> refersBy ws src a it o]
  (site, l) <- listToMaybe items
  let all' = [it | it@(_, l') <- aliasItems src, lnAlias l' == a]
  pure (AliasSite (isPath site) (lnName l) a all' (nub (concatMap (uncurry (itemKinds ws)) all')))
  where
    occurrenceAlias = \case
      OccAlias _ _ a -> Just a
      OccVar Nothing v -> Just v
      OccCommand _ q -> Just q
      OccFunction q -> Just q
      _ -> Nothing

-- | The span of a name in an occurrence: the first place of the name in the text of the span.
nameLoc :: Source -> SrcSpan -> Text -> Location
nameLoc src sp n =
  let piece = BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) (TE.encodeUtf8 (srcText src)))
      start = spanStart sp + BS.length (fst (BS.breakSubstring (TE.encodeUtf8 n) piece))
   in Location (srcPath src) start (start + BS.length (TE.encodeUtf8 n))

-- | The aliases of the items of an alias in its file, and the references by it there.
aliasPlaces :: Workspace -> Source -> AliasSite -> [Location]
aliasPlaces ws src al =
  nub $
    [loc src (lnAliasSpan l) | (_, l) <- alItems al]
      <> [nameLoc src sp (alAlias al) | o@(sp, _) <- occurrencesOf src, any (\it -> refersBy ws src (alAlias al) it o) (alItems al)]

-- | The definition of the original name of an alias: the declaration in the .emet, or the @set in the variable file.
originalDefinition :: Workspace -> Source -> AliasSite -> [Location]
originalDefinition ws src al
  | ".emet" `T.isSuffixOf` alPath al = [exportLocation e | Just p <- [lastProgramOf ws], Just e <- [listedExport p (alPath al) (alName al)]]
  | otherwise =
      nub
        [ loc t nsp
        | (site, _) <- alItems al,
          f <- maybe (either (const []) pure (normalizeRelative (T.unpack (isPath site)))) pure (importTarget ws src site),
          Just t <- [sourceOf ws f],
          (d, nsp) <- setSites (srcAst t),
          d == alName al
        ]

-- | Whether an occurrence of a source is an alias of a list of a .emet, or a call by one.
byAliasIn :: Source -> Occurrence -> Bool
byAliasIn s = \case
  OccAlias {} -> True
  OccCommand _ q -> aliased q
  OccFunction q -> aliased q
  _ -> False
  where
    aliased q = maybe False ((/= q) . snd) (Map.lookup q (emetListed s))

{- | Whether a name keeps the rules of the names of a kind (G02278): those
of the commands of .gm for the inline and the block commands, those of the
expressions for the functions of the expressions and the variables.
-}
fitsKind :: Text -> Kind -> Bool
fitsKind n kind = case (kind, T.uncons n) of
  (KindFn, Just (c, rest)) -> (letter c || c == '_') && T.all (\x -> letter x || isDigit x || x == '_') rest
  (_, Just (c, rest)) -> isAsciiLower c && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
  (_, Nothing) -> False
  where
    letter x = isAsciiLower x || isAsciiUpper x

{- | Renames an alias of a list of an @import (root ADR 0458), from the
alias in the list or from a reference by it: the aliases of the items
that give it and the references by it, in that file alone. The checks of
the rename of a variable of @set (root ADR 0454) fall on the new alias:
its form, a reserved word, the clashes in the file (with the commands of
the language, which the alias would override or not reach, and of the
plugins), the running heads (on the old alias too) and a syntax error.
NotAnAlias when the position is neither, for the other renames.
-}
renameAlias :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> Either RenameError [(Location, Text)]
renameAlias ws style path off new = do
  src <- maybe (Left NotAnAlias) Right (sourceOf ws path)
  al <- maybe (Left NotAnAlias) Right (aliasAt ws src off)
  let old = alAlias al
      kinds = alKinds al
      clash = new /= old
      plugins = maybe [] evPluginCommands (wsEvaluated ws)
      afterImports sp = any (\(site, _) -> spanEnd (isSpan site) <= spanStart sp) (alItems al)
  when (hasErrors (snd (parse (FileId 0) (srcText src)))) (Left (VariableSyntax path))
  when (new `elem` reservedVariableNames) (Left (ReservedVariable new))
  unless (all (fitsKind new) (if null kinds then [KindFn] else kinds)) (Left (InvalidAlias new))
  when clash $ do
    when (new `elem` [lnAlias l | site <- importSitesOf src, l <- importNames site]) (Left (ListedTaken path new))
    when (KindFn `elem` kinds && new `elem` setNamesOf src) (Left (VariableTaken path new))
    when (KindFn `elem` kinds && new `elem` builtinExpressionNames) (Left (BuiltinTaken new))
    when (KindInline `elem` kinds && new `elem` (builtinInlineCommands <> plugins)) (Left (AliasTaken new))
    when (KindBlock `elem` kinds && new `elem` (builtinBlockCommands <> plugins)) (Left (AliasTaken new))
    -- a name written already after the lists, which the new alias would reach
    forM_ (occurrencesOf src) $ \(sp, occ) -> case occ of
      OccVar Nothing v | v == new, afterImports sp -> Left (NewNameReferenced path new)
      OccCommand _ q | q == new, afterImports sp -> Left (NewNameReferenced path new)
      OccFunction q | q == new, afterImports sp -> Left (NewNameReferenced path new)
      _ -> pure ()
  forM_ (titleFormatVariables ws style) $ \(writer, whole, name) ->
    when (name `elem` [old, new]) (Left (TitleFormatVariable writer whole))
  forM_ (maybe [] runningHeadVariables style) $ \(whole, name, l, c) ->
    when (name `elem` [old, new]) (Left (RunningHeadVariable whole l c))
  pure [(l, new) | l <- aliasPlaces ws src al]
