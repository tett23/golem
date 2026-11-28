{- | The conditional pieces of a bibliography declaration (root ADR 0470).
The reader takes the caller's table of field names, and the renderer takes
already formatted field values. Neither knows the entry data or the
selected style. Field identities remain available for per-field output styles.
-}
module Golem.Assemble.BibliographyFormats
  ( BibliographyPiece,
    parseBibliographyPiece,
    bibliographyPieceFields,
    bibliographyPieceNumberNotations,
    renderBibliographyPieces,
    BibliographyFragment (..),
    renderBibliographyFragments,
    renderBibliographyFragmentsWith,
    renderBibliographyFragmentsDeferring,
    bibliographyEntryParts,
  )
where

import Data.Bifunctor (first)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TR
import Golem.Assemble.Formats (Braces (..), Notation, Piece (..), Slot (..), formatReason, notationName, notations, ordinalEnNotation, parseFormatWithNotations, unknownSlot, writeNumber)
import Golem.Bibliography (EntryPart (..))

-- | One conditional piece, parsed once; a slot keeps its name and @?@.
newtype BibliographyPiece = BibliographyPiece [Piece BibliographySlot]
  deriving stock (Eq, Show)

data BibliographySlot = FieldSlot !Text !Bool | AbsenceSlot !Text
  deriving stock (Eq, Show)

{- | Reads one piece using the common brace and notation syntax. Names
must be in the supplied table; @{volume?}@ is optional and
@{volume?:kanji}@ is its optional form with a notation. @{!DOI}@ keeps a
piece only when DOI is unavailable and never writes a value itself.
-}
parseBibliographyPiece :: [Text] -> Text -> Either Text BibliographyPiece
parseBibliographyPiece names source = do
  (pieces, _) <- first formatReason (parseFormatWithNotations (notations <> [ordinalEnNotation]) EscapesOnly table source)
  pure (BibliographyPiece pieces)
  where
    table written
      | Just name <- T.stripPrefix "!" written =
          if not (T.null name) && name `elem` names
            then Right (TextSlot (AbsenceSlot name))
            else Left (unknownSlot ("未知の不在条件です: {" <> written <> "}"))
    table written =
      let (name, optional) = maybe (written, False) (,True) (T.stripSuffix "?" written)
       in if not (T.null name) && name `elem` names
            then Right (NumberSlot (FieldSlot name optional))
            else Left (unknownSlot ("未知の差し込みです: {" <> written <> "}"))

{- | Concatenates the retained pieces. A missing required value removes
its entire piece, including punctuation; optional values alone vanish.
Empty values count as missing. Values are literal text, never formats.
An integer uses the requested notation; other values stay as written.
-}
renderBibliographyPieces :: (Text -> Maybe Text) -> [BibliographyPiece] -> Either Text Text
renderBibliographyPieces value = fmap (T.concat . map text) . renderBibliographyFragments value
  where
    text (BibliographyLiteral t) = t
    text (BibliographyField _ t) = t

-- | Literal punctuation, or a formatted value retaining its field identity.
data BibliographyFragment = BibliographyLiteral !Text | BibliographyField !Text !Text
  deriving stock (Eq, Show)

renderBibliographyFragments :: (Text -> Maybe Text) -> [BibliographyPiece] -> Either Text [BibliographyFragment]
renderBibliographyFragments value = renderBibliographyFragmentsWith (const . value)

{- | Apply per-field character styles without styling adjacent punctuation.
URL fields keep the existing URL behavior of each output.
-}
bibliographyEntryParts :: Map Text Text -> [BibliographyFragment] -> [EntryPart]
bibliographyEntryParts styles = map $ \case
  BibliographyLiteral text -> EntryText text
  BibliographyField name text ->
    let part = if name == "URL" then EntryUrl text else EntryText text
     in maybe part (\style -> EntryStyled style [part]) (Map.lookup name styles)

{- | Field lookup can distinguish a plain value from an explicit number
notation, for example a month label from its numeric month (root ADR 0470).
-}
renderBibliographyFragmentsWith :: (Text -> Maybe Notation -> Maybe Text) -> [BibliographyPiece] -> Either Text [BibliographyFragment]
renderBibliographyFragmentsWith value = fmap (map fst) . renderBibliographyFragmentsDeferring (const False) value

{- | Keep a selected field's literal value and explicit notation for a later
numbering pass. Other fields use the existing formatting and range checks.
Missing fields and conditional pieces are resolved before deferral.
-}
renderBibliographyFragmentsDeferring :: (Text -> Bool) -> (Text -> Maybe Notation -> Maybe Text) -> [BibliographyPiece] -> Either Text [(BibliographyFragment, Maybe Notation)]
renderBibliographyFragmentsDeferring defer value = fmap concat . traverse render
  where
    present name notation = value name notation >>= \t -> if T.null t then Nothing else Just t
    render (BibliographyPiece pieces)
      | any missing pieces = Right []
      | otherwise = concat <$> traverse substitute pieces
    missing = \case
      PLit _ -> False
      PText slot -> missingSlot slot Nothing
      PNumber slot notation -> missingSlot slot notation
    missingSlot (FieldSlot name optional) notation = not optional && isNothing (present name notation)
    missingSlot (AbsenceSlot name) _ = isJust (present name Nothing)
    substitute = \case
      PLit t -> Right [(fragment, Nothing) | fragment <- literal t]
      PText (AbsenceSlot _) -> Right []
      PNumber (AbsenceSlot _) _ -> Right []
      PText (FieldSlot name _) -> Right (field name (fromMaybe "" (present name Nothing)) Nothing)
      PNumber (FieldSlot name _) notation -> case present name notation of
        Nothing -> Right []
        Just t | defer name -> Right (field name t notation)
        Just t -> case (notation, integer t) of
          (Just n, Just k) -> case writeNumber n k of
            Just result -> Right (field name result notation)
            Nothing -> Left ("差し込み {" <> name <> "} の数を " <> notationName n <> " で表せません: " <> t)
          _ -> Right (field name t notation)
    integer t = case TR.signed TR.decimal t of
      Right (n, rest) | T.null rest -> Just (n :: Integer)
      _ -> Nothing

    literal t = [BibliographyLiteral t | not (T.null t)]
    field name t notation = [(BibliographyField name t, notation) | not (T.null t)]

-- | Referenced fields before conditional pieces are omitted.
bibliographyPieceFields :: BibliographyPiece -> [Text]
bibliographyPieceFields (BibliographyPiece pieces) = concatMap field pieces
  where
    field (PLit _) = []
    field (PText slot) = [slotName slot]
    field (PNumber slot _) = [slotName slot]
    slotName (FieldSlot name _) = name
    slotName (AbsenceSlot name) = name

{- | Only explicit number notations in parsed slots; literal escapes and
absence conditions do not select a number view (root ADR 0480 I5-I7).
-}
bibliographyPieceNumberNotations :: BibliographyPiece -> [(Text, Notation)]
bibliographyPieceNumberNotations (BibliographyPiece pieces) =
  [(name, notation) | PNumber (FieldSlot name _) (Just notation) <- pieces]
