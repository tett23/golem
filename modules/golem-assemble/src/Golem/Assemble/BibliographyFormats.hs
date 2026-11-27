{- | The conditional pieces of a bibliography declaration (root ADR 0470).
The reader takes the caller's table of field names, and the renderer takes
already formatted field values. Neither knows the entry data or the
selected style, and no package dependency is added for this format.
-}
module Golem.Assemble.BibliographyFormats
  ( BibliographyPiece,
    parseBibliographyPiece,
    renderBibliographyPieces,
  )
where

import Data.Bifunctor (first)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Read qualified as TR
import Golem.Assemble.Formats (Braces (..), Piece (..), Slot (..), formatReason, notationName, parseFormat, unknownSlot, writeNumber)

-- | One conditional piece, parsed once; a slot keeps its name and @?@.
newtype BibliographyPiece = BibliographyPiece [Piece (Text, Bool)]
  deriving stock (Eq, Show)

{- | Reads one piece using the common brace and notation syntax. Names
must be in the supplied table; @{volume?}@ is optional and
@{volume?:kanji}@ is its optional form with a notation.
-}
parseBibliographyPiece :: [Text] -> Text -> Either Text BibliographyPiece
parseBibliographyPiece names source = do
  (pieces, _) <- first formatReason (parseFormat EscapesOnly table source)
  pure (BibliographyPiece pieces)
  where
    table written =
      let (name, optional) = maybe (written, False) (,True) (T.stripSuffix "?" written)
       in if not (T.null name) && name `elem` names
            then Right (NumberSlot (name, optional))
            else Left (unknownSlot ("未知の差し込みです: {" <> written <> "}"))

{- | Concatenates the retained pieces. A missing required value removes
its entire piece, including punctuation; optional values alone vanish.
Empty values count as missing. Values are literal text, never formats.
An integer uses the requested notation; other values stay as written.
-}
renderBibliographyPieces :: (Text -> Maybe Text) -> [BibliographyPiece] -> Either Text Text
renderBibliographyPieces value = fmap T.concat . traverse render
  where
    present name = value name >>= \t -> if T.null t then Nothing else Just t
    render (BibliographyPiece pieces)
      | any missing pieces = Right ""
      | otherwise = T.concat <$> traverse substitute pieces
    missing = \case
      PLit _ -> False
      PText (name, optional) -> not optional && isNothing (present name)
      PNumber (name, optional) _ -> not optional && isNothing (present name)
    substitute = \case
      PLit t -> Right t
      PText (name, _) -> Right (fromMaybe "" (present name))
      PNumber (name, _) notation -> case present name of
        Nothing -> Right ""
        Just t -> case (notation, integer t) of
          (Just n, Just k) -> case writeNumber n k of
            Just result -> Right result
            Nothing -> Left ("差し込み {" <> name <> "} の数を " <> notationName n <> " で表せません: " <> t)
          _ -> Right t
    integer t = case TR.signed TR.decimal t of
      Right (n, rest) | T.null rest -> Just (n :: Integer)
      _ -> Nothing
