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
    renameLabel,
    Completion (..),
    CompletionKind (..),
    completions,
    hover,
    formatting,
    Outline (..),
    outline,
    Encoding (..),
    toLineCol,
    fromLineCol,
    chooseEncoding,
    encodingKind,
  )
where

import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver (Evaluated (..))
import Golem.Eval.Expr (Env (..), embedValue, evalExpr)
import Golem.Eval.File (EvalResult (..), Usage (..), builtinInlineCommands)
import Golem.Eval.Value (Value (..), typeName)
import Golem.Fmt (FormatResult (..), format)
import Golem.Lsp.Workspace
import Golem.Parser.AST
import Golem.Parser.SourceSettings (sourceKeys)
import Golem.Project
import Golem.Project.Style (FontRole, LocalStyles (..), Style (..), StyleKind (..), charStyleKeys, defaultStyle, noLocalStyles, paraStyleKeys, regexStyleKeys)
import Golem.Syntax
import Language.LSP.Protocol.Types (PositionEncodingKind (..))

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
      BlockCommand (Located _ name) args body -> blockCommand sp name args <> concatMap block body
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
      Command (Located _ name) args slots ->
        ( case (name, args) of
            (n, Located asp (Positional (Word l)) : _)
              | n `elem` labelCommands -> [(asp, OccLabelRef l)] <> [(sp, OccPageRef l) | n == "ref-page"]
            ("style", [Located asp (Positional (Word n))]) -> [(asp, OccStyleRef CharacterKind n)]
            _ -> concatMap argument args
        )
          <> concatMap (concatMap inline) slots
      SoftBreak -> []
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
      ECall _ es -> concatMap expr es
      EUnary _ a -> expr a
      EBinary _ a b -> expr a <> expr b
      _ -> []

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
  Nothing -> []
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
  Nothing -> []
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

data RenameError = NotALabel | LabelExists Text | InvalidName Text
  deriving stock (Eq, Show)

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

-- ------------------------------------------------------------------ completion

data CompletionKind = CkCommand | CkLabel | CkPath | CkSwatch | CkCharStyle | CkParaStyle | CkSettingKey | CkSettingValue | CkStyleKind
  deriving stock (Eq, Show)

data Completion = Completion {cmpLabel :: !Text, cmpKind :: !CompletionKind}
  deriving stock (Eq, Show)

-- | Completion from the text before the cursor on its line.
completions :: Workspace -> FilePath -> Int -> [Completion]
completions ws path off = case sourceOf ws path of
  Nothing -> []
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
     in if "@import " `T.isPrefixOf` T.stripStart lineBefore
          then [Completion (T.pack p) CkPath | p <- wsSourceFiles ws, p /= path]
          else case (T.stripPrefix "@manifest " (T.stripStart lineBefore), T.stripPrefix "@style-def " (T.stripStart lineBefore)) of
            (Just rest, _) -> manifestCompletions rest
            (_, Just rest) -> styleDefCompletions style paraNames charNames rest
            _ ->
              -- the kinds of a page break (docs/adr ADR 0017)
              if "@page-break " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                then [Completion k CkSettingValue | k <- ["recto", "verso"]]
                else
                  -- paragraph styles after @style at the start of a line (docs/adr ADR 0005)
                  if "@style " `T.isPrefixOf` T.stripStart lineBefore && length (T.words lineBefore) <= 2 && not ("[" `T.isInfixOf` lineBefore)
                    then [Completion n CkParaStyle | n <- paraNames]
                    else
                      if not hasOpen || T.isInfixOf "]" lastOpen
                        then []
                        else case ws' of
                          [] -> commandNames
                          [_] | not (T.isSuffixOf " " lastOpen) -> commandNames
                          (cmd : _)
                            | cmd `elem` labelCommands -> [Completion l CkLabel | l <- labels]
                            | cmd == "color" -> [Completion n CkSwatch | n <- Map.keys (stSwatches style)]
                            | cmd == "style" -> [Completion n CkCharStyle | n <- charNames]
                          _ -> []
  where
    commandNames = [Completion c CkCommand | c <- builtinInlineCommands]

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
      "line-breaks" | kind == "paragraph" -> [Completion v CkSettingValue | v <- ["join", "keep"]]
      _ -> []

-- ------------------------------------------------------------------ hover

{- | The value of the @[= ...]@ under the cursor. Values decided by S1 use
the S1 result; page numbers are decided by layout (S2).
-}
hover :: Workspace -> FilePath -> Int -> Maybe Text
hover ws path off = do
  src <- sourceOf ws path
  (_, occ) <- listToMaybe (sortOn (negate . spanLength . fst) [o | o@(sp, OccExpr _) <- occurrences (srcAst src), spanStart sp <= off, off <= spanEnd sp]) `orElse` occurrenceAt src off
  case occ of
    OccExpr e -> Just (evaluate src e)
    OccPageRef _ -> Just "ページ番号はレイアウト（S2）で決まるため、ここでは表示できません"
    _ -> Nothing
  where
    orElse (Just x) _ = Just x
    orElse Nothing y = y
    evaluate src e =
      let r = srcResult src
          vars = maybe Map.empty erExports r
          imports =
            Map.fromList
              [ (ns, maybe Map.empty erExports (sourceOf ws target >>= srcResult))
              | Just res <- [r],
                (ns, target, _) <- usageImports (erUsage res)
              ]
          chapterCount = maybe 0 (length . projectChapters . evProject) (wsEvaluated ws)
          docNs = Map.fromList [("chapters", VHash (Map.fromList [("count", VInt (fromIntegral chapterCount))]))]
          s1 = isJust (wsEvaluated ws >>= evBook)
          env = Env vars (Map.insert "doc" docNs imports)
       in case evalExpr env e of
            Left d -> "評価できません: " <> diagMessage d
            Right v ->
              let shown = fromRight (typeName v) (embedValue (locSpan e) v)
               in if usesDoc (locValue e) && not s1 then shown <> "（文書構造 S1 が未確定）" else shown
    usesDoc = \case
      EVar ("doc" : _) -> True
      EBinary _ a b -> usesDoc (locValue a) || usesDoc (locValue b)
      EUnary _ a -> usesDoc (locValue a)
      ECall _ es -> any (usesDoc . locValue) es
      _ -> False

-- ------------------------------------------------------------------ formatting

{- | The formatted text of the whole file, or Nothing when it has syntax
errors or is already formatted.
-}
formatting :: Workspace -> FilePath -> Maybe Text
formatting ws path = do
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
      SoftBreak -> ""
      _ -> TE.decodeUtf8Lenient (BS.take (spanLength sp) (BS.drop (spanStart sp) (TE.encodeUtf8 (srcText src))))
    nest [] = []
    nest (o : rest) =
      let (kids, others) = span ((> olLevel o) . olLevel) rest
       in o {olChildren = nest kids} : nest others
