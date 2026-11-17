module Names (Quantity(..),readNames,lookupName) where
import Control.Monad (foldM)
import Data.Char (isAsciiLower)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Manifest (maxNaturalInt)
import Golem.Project.Style (Dim,parseSignedDim,parseAki)
import Toml qualified
import Toml.Schema (Table'(..),Value'(..))

data Quantity = Length Dim | Aki Rational | Count Integer deriving stock (Eq,Show)
type Names = Map Text Quantity

readNames :: Text -> Either Text Names
readNames source = do
  MkTable root <- either (const (Left "invalid TOML")) Right (Toml.parse source)
  case Map.lookup "values" root of
    Nothing -> Right Map.empty
    Just (_,Table' _ (MkTable types)) -> foldM readType Map.empty (Map.toList types)
    _ -> Left "invalid values table"
  where
    readType acc (kind,(_,Table' _ (MkTable entries))) | kind `elem` ["length","aki","count"] =
      foldM (readEntry kind) acc (Map.toList entries)
    readType _ _ = Left "invalid quantity type table"
    readEntry kind acc (name,(_,value))
      | not (validName name) = Left "G03255"
      | Map.member name acc = Left "G03254"
      | otherwise = case (kind,value) of
          ("length",Text' _ s) -> insert (Length <$> parseSignedDim s)
          ("aki",Text' _ s) -> insert (Aki <$> parseAki s)
          ("count",Integer' _ n) | n >= 0 && n <= toInteger maxNaturalInt -> insert (Just (Count n))
          _ -> Left "G03256"
      where insert = maybe (Left "G03256") (Right . (\q -> Map.insert name q acc))
    validName name = case T.uncons name of
      Just (c,rest) -> isAsciiLower c && T.all (\x -> isAsciiLower x || (x >= '0' && x <= '9') || x=='-') rest
      Nothing -> False

lookupName :: Text -> Text -> Names -> Either Text Quantity
lookupName kind ref names = case T.stripPrefix "$" ref >>= (`Map.lookup` names) of
  Nothing -> Left "G03257"
  Just q -> if kind==kindOf q then Right q else Left "G03258"
  where
    kindOf (Length _) = "length"
    kindOf (Aki _) = "aki"
    kindOf (Count _) = "count"
