{- | The features of the language server as pure functions over the
workspace, in UTF-8 byte offsets (golem-lsp ADR 0001).
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
  )
where

import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, listToMaybe, mapMaybe)
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
import Golem.Project
import Golem.Project.Style (Style (..))
import Golem.Syntax

-- ------------------------------------------------------------------ positions

data Encoding = Utf8 | Utf16
  deriving stock (Eq, Show)

toLineCol :: Encoding -> LineIndex -> Int -> LineCol
toLineCol Utf8 = offsetToUtf8LineCol
toLineCol Utf16 = offsetToUtf16LineCol

fromLineCol :: Encoding -> LineIndex -> LineCol -> Maybe Int
fromLineCol Utf8 = utf8LineColToOffset
fromLineCol Utf16 = utf16LineColToOffset

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
      _ -> concatMap argument args
    inline (Located sp i) = case i of
      Expr e -> (sp, OccExpr e) : expr e
      Command (Located _ name) args slots ->
        ( case (name, args) of
            (n, Located asp (Positional (Word l)) : _)
              | n `elem` labelCommands -> [(asp, OccLabelRef l)] <> [(sp, OccPageRef l) | n == "ref-page"]
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
    _ -> []

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

data CompletionKind = CkCommand | CkLabel | CkPath | CkSwatch | CkCharStyle
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
        style = evStyle <$> wsEvaluated ws
        labels = nub [l | s <- allSources ws, (_, OccLabelDef l) <- occurrences (srcAst s)]
     in if "@import " `T.isPrefixOf` T.stripStart lineBefore
          then [Completion (T.pack p) CkPath | p <- wsSourceFiles ws, p /= path]
          else
            if not hasOpen || T.isInfixOf "]" lastOpen
              then []
              else case ws' of
                [] -> commandNames
                [_] | not (T.isSuffixOf " " lastOpen) -> commandNames
                (cmd : _)
                  | cmd `elem` labelCommands -> [Completion l CkLabel | l <- labels]
                  | cmd == "color" -> [Completion n CkSwatch | Just st <- [style], n <- Map.keys (stSwatches st)]
                  | cmd == "style" -> [Completion n CkCharStyle | Just st <- [style], n <- Map.keys (stCharStyles st)]
                _ -> []
  where
    commandNames = [Completion c CkCommand | c <- builtinInlineCommands]

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
