{- | Reading CSL-JSON into the entries of the bibliography (docs/adr ADR
0089): which fields are read and how is golem-doc ADR 0004 and 0005.
Finding and reading the files, and the diagnostics, stay in golem-driver.
-}
module Golem.Doc.Bibliography.Csl
  ( CslJsonError (..),
    decodeCslJson,
    cslEntry,
    cslYear,
  )
where

import Data.Aeson qualified as J
import Data.Aeson.Key qualified as JK
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.Maybe (mapMaybe)
import Data.Scientific (Scientific, base10Exponent, coefficient, toBoundedInteger)
import Data.Text qualified as T
import Data.Vector qualified as V
import Golem.Doc.Bibliography (CslDate (..), CslEntry (..), CslName (..))

-- | Why a file of CSL-JSON is not read: not JSON (the message of aeson), or not an array.
data CslJsonError = CslNotJson String | CslNotArray
  deriving stock (Eq, Show)

-- | The entries of a CSL-JSON array, in order; the items that are not entries are left out.
decodeCslJson :: BL.ByteString -> Either CslJsonError [CslEntry]
decodeCslJson s = case J.eitherDecode s of
  Left err -> Left (CslNotJson err)
  Right (J.Array xs) -> Right (mapMaybe cslEntry (V.toList xs))
  Right _ -> Left CslNotArray

{- | The fields of a CSL-JSON item that the bibliography shows; Nothing
without a string id (golem-doc ADR 0004, 0005). An empty string, or one
of spaces only, is a field that is not there.
-}
cslEntry :: J.Value -> Maybe CslEntry
cslEntry = \case
  J.Object o -> do
    J.String k <- KM.lookup "id" o
    pure
      CslEntry
        { ceId = k,
          ceType = str "type" o,
          ceLanguage = str "language" o,
          ceAuthors = case KM.lookup "author" o of
            Just (J.Array as) -> mapMaybe name (V.toList as)
            _ -> [],
          ceTitle = str "title" o,
          ceContainerTitle = str "container-title" o,
          ceVolume = strOrInt "volume" o,
          ceIssue = strOrInt "issue" o,
          cePage = strOrInt "page" o,
          cePublisher = str "publisher" o,
          ceIssued = KM.lookup "issued" o >>= date,
          ceUrl = str "URL" o,
          ceAccessed = KM.lookup "accessed" o >>= date
        }
  _ -> Nothing
  where
    present s = if T.null (T.strip s) then Nothing else Just s
    str k o = case KM.lookup (JK.fromText k) o of
      Just (J.String s) -> present s
      _ -> Nothing
    -- a string, or an integer as its decimal digits; a number that is not an integer is not read
    strOrInt k o = case KM.lookup (JK.fromText k) o of
      Just (J.String s) -> present s
      Just (J.Number n) -> T.pack . show <$> (toBoundedInteger n :: Maybe Int)
      _ -> Nothing
    -- literal first; a name with neither family nor given is left out
    name = \case
      J.Object a -> case (str "literal" a, str "family" a, str "given" a) of
        (Just l, _, _) -> Just (LiteralName l)
        (_, Nothing, Nothing) -> Nothing
        (_, f, g) -> Just (PersonalName f g)
      _ -> Nothing
    -- the year, month and day of the first date-parts, or else the literal
    date = \case
      J.Object i -> case KM.lookup "date-parts" i of
        Just (J.Array ps)
          | (J.Array y : _) <- V.toList ps,
            (yv : rest) <- V.toList y,
            Just yr <- dateYear yv ->
              let mo = case rest of
                    (m : _) -> datePart m
                    [] -> Nothing
                  dy = case rest of
                    (_ : d : _) | Just _ <- mo -> datePart d
                    _ -> Nothing
               in Just (DateParts yr mo dy)
        _ -> DateLiteral <$> str "literal" i
      _ -> Nothing
    -- a number, or a string of ASCII digits
    dateYear = \case
      J.Number n -> cslYear n
      J.String s | Just t <- digits s, T.length t <= 15 -> Just (read (T.unpack t))
      _ -> Nothing
    datePart = \case
      J.Number n -> toBoundedInteger n
      J.String s | Just t <- digits s, T.length t <= 9 -> Just (read (T.unpack t))
      _ -> Nothing
    digits s = if not (T.null s) && T.all isDigit s then Just s else Nothing

{- | The year of a CSL-JSON number (docs/adr ADR 0035): Nothing from 10^15
up, 0 below 0.1, and otherwise the number rounded. It is judged from the
coefficient and the exponent, so that 1e1000000000 does not become an
integer of a billion digits.
-}
cslYear :: Scientific -> Maybe Integer
cslYear n
  | c == 0 = Just 0
  | magnitude > 15 = Nothing
  | magnitude < 0 = Just 0
  | otherwise = Just (round n)
  where
    c = coefficient n
    magnitude = length (show (abs c)) + base10Exponent n
