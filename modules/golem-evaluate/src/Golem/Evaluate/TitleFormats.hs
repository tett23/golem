{- | The title formats of numbered headings and captions (root ADR 0463):
the checks of the slots of [metadata] and [vars] of the values written
(G03297, G03298, G03299), the formats of each file with the values of
their slots in place, and the checks of the variables of the files the
numbered headings and captions are in (G02283, G02284).
-}
module Golem.Evaluate.TitleFormats
  ( titleFormatStyleDiagnostics,
    localTitleFormatDiagnostics,
    styleDefTitleFormats,
    titleFormatsOf,
    resolveTitleFormats,
    titleFormatSetDiagnostics,
    titleFormatVariables,
  )
where

import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble (Book (..), HeadingInfo (..))
import Golem.Assemble.Numbering (TitlePiece (..))
import Golem.Eval.Expr (embedValue)
import Golem.Eval.File (EvalResult (..))
import Golem.Eval.Value (Value, projectVarValues, typeName)
import Golem.Evaluate.ProjectVars (lookupProjectVar)
import Golem.Parser.AST qualified as A
import Golem.Project
import Golem.Project.Style
import Golem.Syntax

-- | The text of a value in a title: strings and numbers as they are embedded in prose.
valueText :: Value -> Maybe Text
valueText = either (const Nothing) Just . embedValue (mkSpan (FileId 0) 0 0)

{- | G03297 for each slot of [vars] without @?@ whose name is not there,
G03298 for each whose value is not a string or a number, and G03299 for
each slot of [metadata] without @?@ whose key the manifest does not have,
at the value written.
-}
refDiagnostics :: Manifest -> SrcSpan -> [(RunningRef, Bool)] -> [Diagnostic]
refDiagnostics manifest sp = concatMap one
  where
    meta = runningMetadata (manifestMetadata manifest)
    vars = projectVarValues (manifestVars manifest)
    one = \case
      (RefProjectVar n, optional) -> case lookupProjectVar vars n of
        Nothing
          | optional -> []
          | otherwise -> [diagnostic "G03297" Error sp ("題の書式が参照する変数 " <> T.intercalate "." n <> " が [vars] にありません")]
        Just v
          | isJust (valueText v) -> []
          | otherwise -> [diagnostic "G03298" Error sp ("題の書式に出せるのは文字列と数です: vars." <> T.intercalate "." n <> " は " <> typeName v)]
      (RefMeta k, optional)
        | optional || Map.member k meta -> []
        | otherwise -> [diagnostic "G03299" Error sp ("題の書式が参照する [metadata] の " <> k <> " がありません")]
      _ -> []

-- | The checks of the slots of [metadata] and [vars] of the title formats of style.toml, once for each slot.
titleFormatStyleDiagnostics :: FileId -> Text -> Manifest -> [Diagnostic]
titleFormatStyleDiagnostics styleFid styleText manifest =
  concat [refDiagnostics manifest sp refs | (sp, refs) <- titleFormatSites styleFid styleText]

{- | The lines of @style-def paragraph that write title-format, in order:
the span of the line, the name of the style and the format as written.
-}
styleDefTitleFormats :: A.File -> [(SrcSpan, Text, Text)]
styleDefTitleFormats file =
  [ (sp, name, format)
  | A.Located sp (A.BlockCommand (A.Located _ "style-def") (A.Located _ (A.Positional kind) : A.Located _ (A.Positional nameArg) : rest) _) <- A.fileBlocks file,
    Just "paragraph" <- [argText kind],
    Just name <- [argText nameArg],
    A.Located _ (A.Keyword (A.Located _ "title-format") v) <- rest,
    Just format <- [argText v]
  ]
  where
    argText = \case
      A.Word w -> Just w
      A.StringLit t -> Just t
      _ -> Nothing

{- | The checks of the slots of [metadata] and [vars] of the title formats
of @style-def, at the definition that writes each.
-}
localTitleFormatDiagnostics :: Manifest -> Project -> Map FileId EvalResult -> [Diagnostic]
localTitleFormatDiagnostics manifest project results =
  concat
    [ refDiagnostics manifest (fromMaybe (mkSpan fid 0 0) (listToMaybe [sp | (sp, n, _) <- defs, n == name])) [(ref, q) | FormatRef ref q <- parts]
    | (fid, r) <- Map.toList results,
      let defs = maybe [] (styleDefTitleFormats . sfAst) (Map.lookup fid (projectSources project)),
      (name, d) <- Map.toList (lsParaStyles (erStyles r)),
      Just parts <- [psTitleFormat d]
    ]

{- | The title formats of each file: of each level of [headings.<l>], and
of its captions from the paragraph style caption, @style-def of the file
included.
-}
titleFormatsOf :: Style -> Map FileId EvalResult -> Map (FileId, Maybe Int) [TitleFormatPart]
titleFormatsOf style results =
  Map.fromList
    ( [ ((fid, Nothing), format)
      | (fid, r) <- Map.toList results,
        Just format <- [paraStyle (withLocalStyles style (erStyles r)) (Just "caption") >>= psTitleFormat]
      ]
        <> [ ((fid, Just l), format)
           | fid <- Map.keys results,
             (l, h) <- Map.toList (stHeadings style),
             Just format <- [hsTitleFormat h]
           ]
    )

{- | The formats with the text of their slots of [metadata], [vars] and the
variables of the file in place, empty without a value; the text is never
read again as a format.
-}
resolveTitleFormats :: (FileId -> [Text] -> Maybe Value) -> Manifest -> Map (FileId, Maybe Int) [TitleFormatPart] -> Map (FileId, Maybe Int) [TitlePiece]
resolveTitleFormats fileVar manifest = Map.mapWithKey (\(fid, _) -> merge . map (piece fid))
  where
    meta = runningMetadata (manifestMetadata manifest)
    vars = projectVarValues (manifestVars manifest)
    piece fid = \case
      FormatPiece p -> p
      FormatRef r _ -> TitleText (fromMaybe "" (value fid r))
    value fid = \case
      RefMeta k -> Map.lookup k meta
      RefProjectVar n -> lookupProjectVar vars n >>= valueText
      RefVar n -> fileVar fid n >>= valueText
      RefHeading {} -> Nothing
    merge = \case
      TitleText a : TitleText b : rest -> merge (TitleText (a <> b) : rest)
      x : rest -> x : merge rest
      [] -> []

{- | G02283 for each numbered heading and caption with a format and each
name of a variable without @?@ the file does not have, G02284 for each
whose value is not a string or a number; at the heading or the caption,
in the order of the book.
-}
titleFormatSetDiagnostics :: (FileId -> [Text] -> Maybe Value) -> Map (FileId, Maybe Int) [TitleFormatPart] -> Book -> [Diagnostic]
titleFormatSetDiagnostics fileVar formats book =
  concat
    [ check sp n optional
    | (sp, level) <- sortOn fst sites,
      Just parts <- [Map.lookup (spanFile sp, level) formats],
      (n, optional) <- Map.toList (Map.fromListWith (&&) [(n, q) | FormatRef (RefVar n) q <- parts])
    ]
  where
    sites =
      [(sp, Just (hiLevel h)) | (sp, h) <- Map.toList (bookHeadings book), isJust (hiNumberText h)]
        <> [(sp, Nothing) | sp <- Map.keys (bookFigures book) <> Map.keys (bookListings book) <> Map.keys (bookTables book)]
    check sp n optional = case fileVar (spanFile sp) n of
      Nothing
        | optional -> []
        | otherwise -> [diagnostic "G02283" Error sp ("題の書式が参照する変数 " <> T.intercalate "." n <> " が、このファイルにありません")]
      Just v
        | isJust (valueText v) -> []
        | otherwise -> [diagnostic "G02284" Error sp ("題の書式に出せるのは文字列と数です: " <> T.intercalate "." n <> " は " <> typeName v)]

{- | The variables the title formats of a file refer to (golem lint counts
them as used): those of [headings.<l>] and of every paragraph style, its
@style-def included.
-}
titleFormatVariables :: Style -> LocalStyles -> [[Text]]
titleFormatVariables style local =
  [ n
  | parts <- [f | h <- Map.elems (stHeadings style), Just f <- [hsTitleFormat h]] <> [f | d <- Map.elems (stParaStyles (withLocalStyles style local)), Just f <- [psTitleFormat d]],
    FormatRef (RefVar n) _ <- parts
  ]
