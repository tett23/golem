-- | Resolve a CSL record through an explicit declaration (root ADR 0470).
module Golem.Assemble.BibliographyRecords (formatBibliographyLabelWithSuffix, formatBibliographyRecord, formatBibliographyRecordWithSuffix, formatBibliographyCitation, formatBibliographyCitationWith, formatBibliographyCitationWithSuffix, formatBibliographyYearCitationWithSuffix, formatBibliographySubsequentCitationWithSuffix, formatBibliographyDeferredSubsequentCitationWithSuffix) where

import Control.Applicative ((<|>))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TR
import Golem.Assemble.BibliographyFormats
import Golem.Assemble.BibliographyNames qualified as Names
import Golem.Assemble.BibliographyRanges
import Golem.Assemble.BibliographyStyle
import Golem.Assemble.Formats (Notation, notationName, writeNumber)
import Golem.Bibliography (CslDate (..), CslEntry (ceId, ceType), CslName (..), EntryPart)
import Golem.Bibliography.Csl
import Golem.Doc.Citation (CitePiece (..))
import Golem.Doc.IR (Locator (..), LocatorLabel (..), LocatorValue (..), locatorLabelName)
import Golem.Syntax.Span (SrcSpan)

-- | Labels use the same record fields and number notation as entry pieces.
formatBibliographyLabelWithSuffix :: Text -> BibliographyStyle d -> Int -> CslRecord -> Either Text Text
formatBibliographyLabelWithSuffix suffix style number record = do
  fragments <- recordFragments suffix False Nothing style number Nothing record (maybe [] pure (bsLabel style))
  pure (foldMap (\case BibliographyField _ value -> value; BibliographyLiteral value -> value) fragments)

formatBibliographyRecord :: BibliographyStyle d -> Int -> CslRecord -> Either Text [EntryPart]
formatBibliographyRecord = formatBibliographyRecordWithSuffix ""

-- | The scope supplies the disambiguation suffix; number notation precedes it.
formatBibliographyRecordWithSuffix :: Text -> BibliographyStyle d -> Int -> CslRecord -> Either Text [EntryPart]
formatBibliographyRecordWithSuffix suffix style number record = do
  entry <- maybe (Left "文献種別の書式がありません") Right (bibliographyTypeFor (fromMaybe "" (ceType (recordEntry record))) style)
  sources <- maybe (Left "文献種別の pieces がありません") Right (btPieces entry)
  fragments <- recordFragments suffix False Nothing style number Nothing record sources
  pure (bibliographyEntryParts (btCharStyles entry) fragments)

formatBibliographyCitation :: BibliographyStyle d -> Int -> CslRecord -> Either Text [CitePiece]
formatBibliographyCitation style number = formatBibliographyCitationWith style number Nothing

formatBibliographyCitationWith :: BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]
formatBibliographyCitationWith = formatBibliographyCitationWithSuffix ""

-- | Only author-year styles use their explicit year template (root ADR 0470).
formatBibliographyYearCitationWithSuffix :: Text -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]
formatBibliographyYearCitationWithSuffix suffix style
  | bsCitationMode style == Just "author-year" = formatBibliographyCitationSelecting btcCitationYear bsCitationYear Nothing suffix style
  | otherwise = formatBibliographyCitationWithSuffix suffix style

formatBibliographyCitationWithSuffix :: Text -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]
formatBibliographyCitationWithSuffix = formatBibliographyCitationSelecting btcCitation bsCitation Nothing

formatBibliographySubsequentCitationWithSuffix :: Text -> Integer -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]

{- | The caller supplies the first displayed note number after numbering.
Page-local counters must not be guessed from a global citation number.
-}
formatBibliographySubsequentCitationWithSuffix suffix firstNote style
  | bsCitationMode style == Just "note" = formatBibliographyCitationSelecting btcSubsequent (\declaration -> bsSubsequent declaration <|> bsCitation declaration) (Just firstNote) suffix style
  | otherwise = formatBibliographyCitationWithSuffix suffix style

-- | Preserve first-note identity for a caller that resolves page-local numbering later.
formatBibliographyDeferredSubsequentCitationWithSuffix :: Text -> (SrcSpan, Int) -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]
formatBibliographyDeferredSubsequentCitationWithSuffix suffix target@(_, firstNote) style
  | bsCitationMode style == Just "note" = formatBibliographyCitationSelectingWith (Just target) btcSubsequent (\declaration -> bsSubsequent declaration <|> bsCitation declaration) (Just (toInteger firstNote)) suffix style
  | otherwise = formatBibliographyCitationWithSuffix suffix style

formatBibliographyCitationSelecting :: (BibliographyTypeCitations -> Maybe [Text]) -> (BibliographyStyle d -> Maybe [Text]) -> Maybe Integer -> Text -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]
formatBibliographyCitationSelecting = formatBibliographyCitationSelectingWith Nothing

formatBibliographyCitationSelectingWith :: Maybe (SrcSpan, Int) -> (BibliographyTypeCitations -> Maybe [Text]) -> (BibliographyStyle d -> Maybe [Text]) -> Maybe Integer -> Text -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> Either Text [CitePiece]
formatBibliographyCitationSelectingWith target typeTemplate globalTemplate firstNote suffix style number location record = do
  let selected = do
        kind <- bibliographyTypeNameFor (fromMaybe "" (ceType (recordEntry record))) style
        templates <- Map.lookup kind (bsTypeCitations style)
        typeTemplate templates
  sources <- maybe (Left "citation がありません") Right (selected <|> globalTemplate style)
  fragments <- recordFragmentsDeferring (\name -> name == "first-note" && isJust target) suffix (bsCitationMode style `elem` [Just "numeric", Just "author-year"]) firstNote style number location record sources
  pure
    [ case fragment of
        BibliographyField "first-note" _
          | Just (targetSpan, n) <- target ->
              CiteNoteNumber targetSpan n (notationName <$> notation) (maybe (Just (T.pack (show n))) (\selectedNotation -> writeNumber selectedNotation (toInteger n)) notation)
        BibliographyField "number" value | value == T.pack (show number) -> CiteNumber (ceId (recordEntry record)) number
        BibliographyField "number" value -> CiteReference (ceId (recordEntry record)) value
        BibliographyField "locator" value
          | Just label <- citationLocatorLabel style location,
            Just at <- location ->
              let kind = locatorLabelName (locLabel at)
                  position = Map.findWithDefault "before" kind (bsLocatorPositions style)
                  delimiter = Map.findWithDefault " " kind (bsLocatorDelimiters style)
                  explicit = Map.member kind (bsLocatorPositions style) || Map.member kind (bsLocatorDelimiters style)
               in if not explicit
                    then if T.null label then CiteText value else CiteLocator label value
                    else CiteLocatorFormatted label delimiter value (position == "after")
        BibliographyField _ value -> CiteText value
        BibliographyLiteral value -> CiteText value
    | (fragment, notation) <- fragments
    ]

recordFragments :: Text -> Bool -> Maybe Integer -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> [Text] -> Either Text [BibliographyFragment]
recordFragments suffix shortAuthor firstNote style number location record sources =
  map fst <$> recordFragmentsDeferring (const False) suffix shortAuthor firstNote style number location record sources

recordFragmentsDeferring :: (Text -> Bool) -> Text -> Bool -> Maybe Integer -> BibliographyStyle d -> Int -> Maybe Locator -> CslRecord -> [Text] -> Either Text [(BibliographyFragment, Maybe Notation)]
recordFragmentsDeferring defer suffix shortAuthor firstNote style number location record sources = do
  pieces <- traverse (parseBibliographyPiece bibliographyFields) sources
  let fields = concatMap bibliographyPieceFields pieces
  located <- case location of
    Just at | "locator" `elem` fields -> do
      _ <- maybe (Left ("locator-labels." <> locatorLabelName (locLabel at) <> " がありません")) Right (citationLocatorLabel style location)
      Just <$> locatorValueText style at
    _ -> pure Nothing
  author <- names fields "author"
  editor <- names fields "editor"
  let editorLabel = do
        options <- Map.lookup "editor" (bsNames style)
        labels <- bnLabel options
        Names.bibliographyEditorLabel labels (people "editor")
      derived = Map.fromList [("author", author), ("editor", editor), ("editor-label", editorLabel), ("number", Just (tshow number)), ("year", year), ("month", month), ("day", day), ("page", page), ("locator", located), ("first-note", tshow <$> firstNote)]
      value key notation
        | key == "month", Just _ <- notation = numericMonth
        | otherwise = fromMaybe (recordText key record) (Map.lookup key derived)
  fragments <- renderBibliographyFragmentsDeferring defer value pieces
  pure [(case fragment of BibliographyField "year" text -> BibliographyField "year" (text <> suffix); _ -> fragment, notation) | (fragment, notation) <- fragments]
  where
    people key = [case name of PersonalName family given -> Names.PersonalName family given; LiteralName literal -> Names.LiteralName literal | CslPerson name _ <- recordNames key record]
    names fields key
      | key `notElem` fields || null (people key) = Right Nothing
      | otherwise = do
          let role = if shortAuthor && key == "author" then "short" else key
          options <- maybe (Left ("名前の書式がありません: " <> role)) Right (Map.lookup role (bsNames style))
          text <-
            if role == "short"
              then do
                (format, extras) <- Names.resolveBibliographyShortNames options
                pure (Names.formatShortNamesWith extras format (people key))
              else do
                (format, extras) <- Names.resolveBibliographyNames options
                pure (Names.formatBibliographyNamesWith extras format (people key))
          pure (Just text)
    (year, numericMonth, day) = case recordDate "issued" record of
      Just (DateParts y m d) -> (Just (tshow y), tshow <$> m, tshow <$> d)
      Just (DateLiteral literal) -> (Just literal, Nothing, Nothing)
      _ -> (Nothing, Nothing, Nothing)
    month = case recordDate "issued" record of
      Just (DateParts _ (Just n) _) -> (bsMonths style >>= lookup n . zip [1 ..]) <|> Just (tshow n)
      _ -> Nothing
    page = fmap range (recordText "page" record)
    range source = case (bsPageRange style, bsRangeDelimiter style, endpoints source) of
      (Just mode, Just delimiter, Just (a, b)) -> formatBibliographyRange (if mode == "minimal" then MinimalPageRange else FullPageRange) delimiter a b
      _ -> source
    endpoints source = case T.splitOn "-" source of
      [a, b] -> (,) <$> natural a <*> natural b
      _ -> Nothing
    natural source = case TR.decimal source of
      Right (n, rest) | T.null rest -> Just n
      _ -> Nothing
    tshow :: (Show a) => a -> Text
    tshow = T.pack . show

-- | Singular/plural depends on the typed interval, never on a guessed string.
citationLocatorLabel :: BibliographyStyle d -> Maybe Locator -> Maybe Text
citationLocatorLabel style location = do
  Locator label value <- location
  labels <- Map.lookup (locatorLabelName label) (bsLocatorLabels style)
  pure $ case value of
    LocRange a b | a /= b -> snd labels
    _ -> fst labels

locatorValueText :: BibliographyStyle d -> Locator -> Either Text Text
locatorValueText style (Locator label value) = case value of
  LocNumber n | n >= 0 -> Right (T.pack (show n))
  LocNumber _ -> Left "引用の位置の数が負です"
  LocRange a b
    | a < 0 || b < a -> Left "引用の位置の範囲が負か逆向きです"
    | a == b -> Right (T.pack (show a))
    | otherwise -> do
        delimiter <- maybe (Left "range-delimiter がありません") Right (bsRangeDelimiter style)
        mode <-
          if label /= LocatorPage
            then Right FullPageRange
            else case bsPageRange style of
              Just "full" -> Right FullPageRange
              Just "minimal" -> Right MinimalPageRange
              _ -> Left "page-range がありません"
        pure (formatBibliographyRange mode delimiter (fromInteger a) (fromInteger b))
  LocText text | T.null text -> Left "引用の位置の文字列が空です"
  LocText text -> Right text
