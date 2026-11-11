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
    emetTextOf,
    Completion (..),
    CompletionKind (..),
    completions,
    tomlFileCompletions,
    isSettingsFile,
    hover,
    formatting,
    Outline (..),
    outline,
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
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Either (fromRight)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver (Evaluated (..), metadataValues)
import Golem.Emet (Export (..), Kind (..), Program, formatEmet, programExports, programModules)
import Golem.Emet.Highlight (Highlight (..), HlType (..), emetHighlights)
import Golem.Emet.Ide (IdeKind (..), emetCompletions, emetDefinition, emetExportAt, emetHover, emetLocalHover)
import Golem.Emet.Rename qualified as R
import Golem.Eval.Expr (embedValue, evalExpr, plainEnv)
import Golem.Eval.File (EvalResult (..), Usage (..), builtinInlineCommands)
import Golem.Eval.Value (Value (..), projectVarValues, typeName)
import Golem.Fmt (FormatResult (..), format)
import Golem.Lsp.Toml (Context (..), Quote (..), contextAt, definedPaths)
import Golem.Lsp.Workspace
import Golem.Parser (parse)
import Golem.Parser.AST
import Golem.Parser.CST qualified as C
import Golem.Parser.SourceSettings (sourceKeys)
import Golem.Preflight.Rules (rulesSchema)
import Golem.Project
import Golem.Project.Paths (normalizeRelative)
import Golem.Project.Style (FontRole, LocalStyles (..), Style (..), StyleKind (..), alignValues, builtinAkiSetNames, builtinCharStyles, builtinParaStyles, charStyleKeys, defaultStyle, layoutValueNames, layoutValueSites, lineBreaksValues, noLocalStyles, paraStyleKeys, parseStyle, regexStyleKeys, styleSchema)
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
  deriving stock (Show)

labelCommands :: [Text]
labelCommands = ["ref-number", "ref-title", "ref-page"]

-- | Every occurrence in a file with its span.
occurrences :: File -> [(SrcSpan, Occurrence)]
occurrences (File _ bs) = concatMap block bs
  where
    block (Located sp b) = case b of
      Paragraph is -> concatMap inline is
      Heading _ is -> concatMap inline is
      BulletList items -> concatMap (concatMap block) items
      OrderedList items -> concatMap (concatMap block) items
      DefList gs -> concatMap (\g -> concatMap (concatMap inline) (dgTerms g) <> concatMap (concatMap block) (dgDefs g)) gs
      Table _ h rows -> concatMap (concatMap inline) h <> concatMap (concatMap (concatMap inline)) rows
      SetVar (Located vsp v) e -> (vsp, OccVar Nothing v) : expr e
      BlockCommand (Located nsp name) args body -> [(nsp, OccCommand False name) | T.isInfixOf "." name] <> blockCommand sp name args <> concatMap block body
      Attributed cs t -> concatMap block cs <> maybe [] block t
      _ -> []
    blockCommand _ name args = case (name, args) of
      ("import", Located asp (Positional (Word p)) : _) -> [(asp, OccImport p)]
      ("import", Located asp (Positional (StringLit p)) : _) -> [(asp, OccImport p)]
      ("label", Located asp (Positional (Word l)) : _) -> [(asp, OccLabelDef l)]
      ("style", [Located asp (Positional (Word n))]) -> [(asp, OccStyleRef ParagraphKind n)]
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
        [(nsp, OccCommand True name) | T.isInfixOf "." name]
          <> ( case (name, args) of
                 (n, Located asp (Positional (Word l)) : _)
                   | n `elem` labelCommands -> [(asp, OccLabelRef l)] <> [(sp, OccPageRef l) | n == "ref-page"]
                 ("style", [Located asp (Positional (Word n))]) -> [(asp, OccStyleRef CharacterKind n)]
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
      ECall f es -> [(sp, OccFunction f) | T.isInfixOf "." f] <> concatMap expr es
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
    [ (isNamespace site, p)
    | Right site <- importsOf (srcAst src),
      ".emet" `T.isSuffixOf` isPath site,
      Right p <- [normalizeRelative (T.unpack (isPath site))]
    ]

-- | The function of a .emet a name of a source calls: ns.name of a kind.
exportOf :: Workspace -> Source -> Kind -> Text -> Maybe Export
exportOf ws src kind q = programOf ws >>= \p -> exportIn p src kind q

-- | The same, in a program.
exportIn :: Program -> Source -> Kind -> Text -> Maybe Export
exportIn p src kind q = do
  let (ns, rest) = T.breakOn "." q
  n <- T.stripPrefix "." rest
  path <- Map.lookup ns (emetImports src)
  listToMaybe [e | e <- Map.findWithDefault [] path (programExports p), exKind e == kind, exName e == n]

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
    (sp, occ) <- occurrences (srcAst s),
    Just (kind, q) <- [called occ],
    Just e' <- [exportIn p s kind q],
    exPath e' == exPath e,
    exKind e' == exKind e,
    exName e' == exName e
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
  _ -> Nothing

-- | The innermost occurrence at an offset.
occurrenceAt :: Source -> Int -> Maybe (SrcSpan, Occurrence)
occurrenceAt src off =
  listToMaybe (sortOn (spanLength . fst) [o | o@(sp, _) <- occurrences (srcAst src), spanStart sp <= off, off <= spanEnd sp])

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
    Just (OccVar Nothing v) -> [loc src sp | Just r <- [srcResult src], (d, sp) <- usageDefined (erUsage r), d == v]
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

styleDefs :: Source -> StyleKind -> Text -> [Location]
styleDefs src k n = take 1 [loc src sp | (sp, OccStyleDef k' n') <- occurrences (srcAst src), k' == k, n' == n]

styleKindOf :: Text -> Maybe StyleKind
styleKindOf = \case
  "character" -> Just CharacterKind
  "paragraph" -> Just ParagraphKind
  _ -> Nothing

labelDefs :: Workspace -> Text -> [Location]
labelDefs ws l = [loc s sp | s <- allSources ws, (sp, OccLabelDef l') <- occurrences (srcAst s), l' == l]

labelRefs :: Workspace -> Text -> [Location]
labelRefs ws l = [loc s sp | s <- allSources ws, (sp, OccLabelRef l') <- occurrences (srcAst s), l' == l]

-- ------------------------------------------------------------------ references

{- | References, the definition included. Labels are searched across files;
a variable in its file and through namespaces in the files importing it.
-}
references :: Workspace -> FilePath -> Int -> [Location]
references ws path off = case sourceOf ws path of
  -- a function of a .emet: the calls of it in the sources (docs/adr/0162)
  Nothing -> [l | Just text <- [emetText ws path], Just prog <- [programOf ws], Just e <- [emetExportAt prog path text off], l <- callsOf ws e]
  Just src | Just e <- occurrenceAt src off >>= occurrenceExport ws src . snd -> callsOf ws e
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
        [loc t sp | (sp, OccVar Nothing v') <- occurrences (srcAst t), v' == v]
          <> [ loc s sp
             | s <- allSources ws,
               Just r <- [srcResult s],
               (ns, target, _) <- usageImports (erUsage r),
               target == srcPath t,
               (sp, OccVar (Just ns') v') <- occurrences (srcAst s),
               ns' == ns,
               v' == v
             ]

-- ------------------------------------------------------------------ rename

data RenameError = NotALabel | LabelExists Text | InvalidName Text | NotALayoutValue | LayoutValueExists Text | InvalidLayoutValue Text | EmetRename R.RenameError
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
    style = either (const defaultStyle) id (parseStyle (FileId 0) styleText)
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
                Just l <- map (nameIn old) (callsIn prog ws e)
              ]
                <> [l | kind == KindFilter, l <- filterNames manifest p old]
        _ -> []
  pure ([(Location p s e, new) | (p, s, e) <- R.rnEdits r] <> [(l, new) | l <- gmEdits])
  where
    -- the name after the namespace in a call of .gm: ns.name
    nameIn old (Location p s e) = do
      src <- sourceOf ws p
      let piece = BS.take (e - s) (BS.drop s (TE.encodeUtf8 (srcText src)))
          needle = TE.encodeUtf8 ("." <> old)
          (pre, rest) = BS.breakSubstring needle piece
          after = BS.drop (BS.length needle) rest
          isNameByte b = b == 95 || b == 45 || (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
      if BS.null rest || maybe False (isNameByte . fst) (BS.uncons after)
        then Nothing
        else Just (Location p (s + BS.length pre + 1) (s + BS.length pre + BS.length needle))

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

data CompletionKind = CkCommand | CkLabel | CkPath | CkSwatch | CkCharStyle | CkParaStyle | CkSettingKey | CkSettingValue | CkStyleKind | CkTable
  deriving stock (Eq, Show)

data Completion = Completion {cmpLabel :: !Text, cmpKind :: !CompletionKind}
  deriving stock (Eq, Show)

-- | Completion from the text before the cursor on its line.
completions :: Workspace -> FilePath -> Int -> [Completion]
completions ws path off = case sourceOf ws path of
  _ | isJust (settingsSchemaOf path) -> maybe [] (\t -> tomlFileCompletions path t off) (Map.lookup path (wsOverlay ws))
  -- a .emet (docs/adr/0162)
  Nothing -> [Completion n (emetKind k) | Just text <- [emetText ws path], (n, k) <- emetCompletions (programOf ws) path text off]
  Just src
    | Just names <- namespaceCompletions ws src off -> names
  Just src ->
    let before = TE.decodeUtf8Lenient (BS.take off (TE.encodeUtf8 (srcText src)))
        lineBefore = T.takeWhileEnd (/= '\n') before
        lastOpen = T.takeWhileEnd (/= '[') lineBefore
        hasOpen = T.isInfixOf "[" lineBefore
        ws' = T.words lastOpen
        style = maybe defaultStyle evStyle (wsEvaluated ws)
        {- the styles of the file (docs/adr ADR 0014): of its evaluation, and
        of its @style-def lines while it does not evaluate -}
        local = maybe noLocalStyles erStyles (srcResult src)
        defined k = [n | (_, OccStyleDef k' n) <- occurrences (srcAst src), k' == k]
        -- code is the style of code blocks, not of @style, based-on or regex styles (golem-driver ADR 0017)
        paraNames = filter (/= "code") (nub (Map.keys (stParaStyles style) <> Map.keys (lsParaStyles local) <> defined ParagraphKind))
        charNames = nub (Map.keys (stCharStyles style) <> Map.keys (lsCharStyles local) <> defined CharacterKind)
        labels = nub [l | s <- allSources ws, (_, OccLabelDef l) <- occurrences (srcAst s)]
        -- the dotted name before the cursor in an expression
        metaPath = case T.stripPrefix "=" (T.stripStart lastOpen) of
          Just _ -> Just (T.splitOn "." (T.takeWhileEnd (\c -> c == '.' || c == '_' || c `elem` ['a' .. 'z'] || c `elem` ['A' .. 'Z'] || c `elem` ['0' .. '9']) lastOpen))
          Nothing -> Nothing
        meta = maybe Map.empty (metadataValues . manifestMetadata . projectManifest . evProject) (wsEvaluated ws)
        projectVars = projectVarsOf ws
     in if "@import " `T.isPrefixOf` T.stripStart lineBefore
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
                      -- paragraph styles after @style at the start of a line (docs/adr ADR 0005)
                      if "@style " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                        then [Completion n CkParaStyle | n <- paraNames]
                        else
                          if not hasOpen || T.isInfixOf "]" lastOpen
                            then []
                            else case metaPath of
                              -- the keys of meta and of meta.roles (docs/adr ADR 0033)
                              Just ["meta", _] -> [Completion k CkSettingKey | k <- Map.keys meta]
                              Just ["meta", "roles", _] | Just (VHash rs) <- Map.lookup "roles" meta -> [Completion k CkSettingKey | k <- Map.keys rs]
                              -- the keys of [vars] and of its tables (docs/adr/0185)
                              Just ("vars" : keyPath@(_ : _)) | Just keys <- varKeys projectVars (init keyPath) -> [Completion k CkSettingKey | k <- keys]
                              _ -> case ws' of
                                [] -> commandNames
                                [_] | not (T.isSuffixOf " " lastOpen) -> commandNames
                                (cmd : _)
                                  | cmd `elem` labelCommands -> [Completion l CkLabel | l <- labels]
                                  | cmd == "color" -> [Completion n CkSwatch | n <- Map.keys (stSwatches style)]
                                  | cmd == "style" -> [Completion n CkCharStyle | n <- charNames]
                                _ -> []
  where
    -- the built-in commands, then those of the plugins (docs/adr ADR 0031)
    commandNames = [Completion c CkCommand | c <- builtinInlineCommands <> maybe [] evPluginCommands (wsEvaluated ws)]

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
      names kind = Just [Completion (exName e) CkCommand | e <- exports, exKind e == kind]
  case () of
    _
      | T.strip rest == "@" -> names KindBlock
      | inExpression rest -> names KindFn
      | "[" `T.isSuffixOf` rest -> names KindInline
      | otherwise -> Nothing
  where
    isAsciiAlphaNum c = isAsciiLower c || isAsciiUpper c || isDigit c
    -- the text before the name is inside [= ... ] that is not closed
    inExpression rest = case T.breakOnEnd "[=" rest of
      ("", _) -> False
      (_, after) -> not (T.isInfixOf "]" after)

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
      "paragraph-separator" -> ["blank-line", "line"]
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

-- | style.toml or preflight.toml at the root.
isSettingsFile :: FilePath -> Bool
isSettingsFile = isJust . settingsSchemaOf

-- | Completion in style.toml or preflight.toml at the root, from its text; none in another file.
tomlFileCompletions :: FilePath -> Text -> Int -> [Completion]
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
      | Just kind <- layoutKind path =
          [ Completion (if q == Bare then "\"" <> name <> "\"" else name) CkSettingValue
          | ["values", declaredKind, name] <- defined,
            declaredKind == kind,
            path /= ["values", kind, name]
          ]
      | otherwise = []
    layoutKind path = case path of
      ["values", kind, _] | kind `elem` ["length", "aki", "count"] -> Just kind
      _ -> case nodeAt styleSchema path of
        Just (NValue LDimension) -> Just "length"
        Just (NValue LInteger) | last path `elem` ["lines", "keep-first-lines", "keep-last-lines", "keep-with-next", "space-before", "space-after", "space-between"] -> Just "count"
        _ | "aki-sets" `elem` path, last path `elem` ["optimum", "minimum", "maximum"] -> Just "aki"
        _ -> Nothing
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
      case [e | (sp, occ) <- occurrences (srcAst src), onName sp occ, Just e <- [occurrenceExport ws src occ]] of
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
  (_, occ) <- listToMaybe (sortOn (negate . spanLength . fst) [o | o@(sp, OccExpr _) <- occurrences (srcAst src), spanStart sp <= off, off <= spanEnd sp]) `orElse` occurrenceAt src off
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
