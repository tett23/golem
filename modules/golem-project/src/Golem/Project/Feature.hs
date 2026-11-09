{- | OpenType features of style.toml (docs/adr/0268): the four ways of
writing one, @tag@, @+tag@, @-tag@ and @tag=N@, their normal form, and a
list of features with the last value of each tag kept.
-}
module Golem.Project.Feature
  ( Feature (..),
    FeatureSite (..),
    parseFeature,
    featureText,
    normalFeatures,
    normalFeatureTexts,
    featureMessage,
    maxFeatureValue,
    isFeatureTag,
  )
where

import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax (SrcSpan)

{- | Where a feature was written, for G08103 (docs/adr/0268): a value of
style.toml by its line and column, a @style-def, or nowhere (a feature
Golem makes).
-}
data FeatureSite
  = SiteNone
  | -- | the line and the column of the value in style.toml, from 1
    SiteToml !Int !Int
  | -- | the line of a @style-def
    SiteSource !SrcSpan
  deriving stock (Eq, Ord, Show)

-- | A feature: its tag of four characters and its value, 0 to 65535.
data Feature = Feature
  { ftTag :: !Text,
    ftValue :: !Int,
    ftSite :: !FeatureSite
  }
  deriving stock (Eq, Show)

-- | The largest value of a feature.
maxFeatureValue :: Int
maxFeatureValue = 65535

-- | A tag: four ASCII letters and digits.
isFeatureTag :: Text -> Bool
isFeatureTag t = T.length t == 4 && T.all (\c -> isAsciiLower c || isAsciiUpper c || isDigit c) t

{- | The tag and the value of one of the four forms (docs/adr/0268); any
other text, HarfBuzz's ranges and word values among them, is Nothing.
-}
parseFeature :: Text -> Maybe (Text, Int)
parseFeature s = case T.uncons s of
  Just ('+', t) | isFeatureTag t -> Just (t, 1)
  Just ('-', t) | isFeatureTag t -> Just (t, 0)
  _ -> case T.breakOn "=" s of
    (t, "") | isFeatureTag t -> Just (t, 1)
    (t, rest)
      | isFeatureTag t,
        Just n <- T.stripPrefix "=" rest,
        not (T.null n),
        T.length n <= 5,
        T.all isDigit n,
        let v = read (T.unpack n),
        v <= maxFeatureValue ->
          Just (t, v)
    _ -> Nothing

-- | The normal form of a feature: @-tag@ for 0, @tag@ for 1, @tag=N@ otherwise.
featureText :: (Text, Int) -> Text
featureText (t, v) = case v of
  0 -> "-" <> t
  1 -> t
  _ -> t <> "=" <> T.pack (show v)

{- | The last value of each tag, at the place of its last value
(docs/adr/0268): HarfBuzz takes the last feature of a tag, so the list
shapes as the one given.
-}
normalFeatures :: [(Text, Int)] -> [(Text, Int)]
normalFeatures fs =
  let lastAt = Map.fromList [(t, i) | (i, (t, _)) <- zip [0 :: Int ..] fs]
   in [f | (i, f@(t, _)) <- zip [0 ..] fs, Map.lookup t lastAt == Just i]

-- | 'normalFeatures' in the normal form, as the shaping and CSS take it.
normalFeatureTexts :: [Feature] -> [Text]
normalFeatureTexts fs = map featureText (normalFeatures [(ftTag f, ftValue f) | f <- fs])

-- | The message of G03124 (docs/adr/0268).
featureMessage :: Text -> Text
featureMessage s = "OpenType の機能の書き方が正しくありません: " <> s <> "（smcp、-liga、salt=2 のように書きます）"
