{- | The preflight rules (golem-cli ADR 0006): which checks golem preflight
runs, with which severity and thresholds. A file of rules is TOML; what it
does not write comes from the built-in rules it is based on, key by key.
Every error of the file is G09001.
-}
module Golem.Preflight.Rules
  ( Level (..),
    Tier (..),
    Rules (..),
    basicRules,
    printRules,
    noneRules,
    builtinRules,
    parseRules,
    RulesFile (..),
    rulesSchema,
    levelValues,
    fontFormatValues,
    colorSpaceValues,
    Node (..),
    Leaf (..),
  )
where

import Control.Monad (when)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Manifest (decodeStrictWith, naturalOf)
import Golem.Project.Style (Dim (..), Sp, parseDim)
import Golem.Project.TomlSchema (Leaf (..), Node (..))
import Golem.Syntax (Diagnostic, FileId)
import Numeric.Natural (Natural)
import Toml.Schema
import Toml.Schema.FromValue (typeError)
import Toml.Semantics (valueAnn)

-- | The severity a check reports with, or off. A notice cannot be chosen.
data Level = LevelError | LevelWarning | LevelOff
  deriving stock (Eq, Show)

-- | The thresholds of the effective resolution of a kind of image, in ppi; 0 skips one.
data Tier = Tier
  { tierErrorBelow :: !Natural,
    tierWarningBelow :: !Natural
  }
  deriving stock (Eq, Show)

data Rules = Rules
  { -- | the built-in rules the file is based on
    ruBasedOn :: !Text,
    -- | the name shown in the summary
    ruName :: !(Maybe Text),
    ruGlyphMissing :: !Level,
    ruFontFormats :: !Level,
    ruFontFormatsAllowed :: ![Text],
    ruTypeSize :: !Level,
    ruTypeSizeMin :: !Sp,
    ruTypeSizeMultiInkOnly :: !Bool,
    ruResolutionColor :: !Tier,
    ruResolutionGray :: !Tier,
    ruResolutionBitmap :: !Tier,
    ruImageResolutionMax :: !Level,
    ruColorMax :: !Natural,
    ruGrayMax :: !Natural,
    ruBitmapMax :: !Natural,
    ruImageColorSpace :: !Level,
    ruColorSpacesAllowed :: ![Text],
    ruImageIcc :: !Level,
    ruBleedSize :: !Level,
    ruBleedMin :: !Sp,
    ruBleedTrimHazard :: !Level,
    ruTrimHazardDistance :: !Sp,
    ruLiveArea :: !Level,
    ruLiveAreaDistance :: !Sp,
    ruOverfullLines :: !Level,
    ruPdfX :: !Level,
    ruInkCoverage :: !Level,
    ruInkMax :: !Natural,
    ruPageCount :: !Level,
    ruPageMultiple :: !Natural,
    ruBlankPages :: !Level,
    ruStrokeWeight :: !Level,
    ruStrokeMin :: !Sp,
    -- | G09019 to G09021 (docs/adr ADR 0232)
    ruFontEmbedding :: !Level,
    ruSpotColors :: !Level,
    ruCmyPlates :: !Level
  }
  deriving stock (Eq, Show)

-- | A length of style.toml in sp; the thresholds below are written with it.
len :: Text -> Sp
len t = case parseDim t of
  Just (Abs s) -> s
  _ -> 0

{- | print: the values often seen in the guides of Japanese printers
(golem-cli ADR 0006), not the values of a standard.
-}
printRules :: Rules
printRules =
  Rules
    { ruBasedOn = "print",
      ruName = Nothing,
      ruGlyphMissing = LevelError,
      ruFontFormats = LevelOff,
      ruFontFormatsAllowed = ["cff", "truetype"],
      ruTypeSize = LevelWarning,
      ruTypeSizeMin = len "5pt",
      ruTypeSizeMultiInkOnly = True,
      ruResolutionColor = Tier 150 300,
      ruResolutionGray = Tier 150 300,
      ruResolutionBitmap = Tier 600 1200,
      ruImageResolutionMax = LevelOff,
      ruColorMax = 0,
      ruGrayMax = 0,
      ruBitmapMax = 0,
      ruImageColorSpace = LevelWarning,
      ruColorSpacesAllowed = ["cmyk", "gray"],
      ruImageIcc = LevelWarning,
      ruBleedSize = LevelError,
      ruBleedMin = len "3mm",
      ruBleedTrimHazard = LevelError,
      ruTrimHazardDistance = len "3mm",
      ruLiveArea = LevelWarning,
      ruLiveAreaDistance = len "3mm",
      ruOverfullLines = LevelWarning,
      ruPdfX = LevelError,
      ruInkCoverage = LevelWarning,
      ruInkMax = 350,
      ruPageCount = LevelOff,
      ruPageMultiple = 1,
      ruBlankPages = LevelOff,
      ruStrokeWeight = LevelWarning,
      ruStrokeMin = len "0.1mm",
      ruFontEmbedding = LevelError,
      ruSpotColors = LevelError,
      ruCmyPlates = LevelOff
    }

{- | basic: InDesign's [Basic], of the checks the build does not already
stop on.
-}
basicRules :: Rules
basicRules =
  printRules
    { ruBasedOn = "basic",
      ruTypeSize = LevelOff,
      ruResolutionColor = Tier 0 0,
      ruResolutionGray = Tier 0 0,
      ruResolutionBitmap = Tier 0 0,
      ruImageColorSpace = LevelOff,
      ruImageIcc = LevelOff,
      ruBleedSize = LevelOff,
      ruBleedTrimHazard = LevelOff,
      ruLiveArea = LevelOff,
      ruInkCoverage = LevelOff,
      ruStrokeWeight = LevelOff,
      ruSpotColors = LevelOff
    }

-- | screen: basic checks without the PDF/X-4 requirement.
screenRules :: Rules
screenRules = basicRules {ruBasedOn = "screen", ruPdfX = LevelOff}

-- | none: every check off, to write rules from nothing.
noneRules :: Rules
noneRules =
  basicRules
    { ruBasedOn = "none",
      ruGlyphMissing = LevelOff,
      ruOverfullLines = LevelOff,
      ruPdfX = LevelOff,
      ruFontEmbedding = LevelOff
    }

builtinRules :: [(Text, Rules)]
builtinRules = [("basic", basicRules), ("print", printRules), ("screen", screenRules), ("none", noneRules)]

-- | Reads a file of rules; every error is G09001 at its place in the file.
parseRules :: FileId -> Text -> Either [Diagnostic] Rules
parseRules fid src = (\(RulesFile r) -> r) <$> decodeStrictWith rulesSchema "G09001" (const "G09001") fid src

newtype RulesFile = RulesFile Rules

-- | @<key> の値が正しくありません: <value>（<why>）@
bad :: l -> Text -> Text -> Text -> Matcher l a
bad l key value why = failAt l (T.unpack (key <> " の値が正しくありません: " <> value <> "（" <> why <> "）"))

instance FromValue RulesFile where
  fromValue = parseTableFromValue $ do
    base <-
      optKeyOf "based-on" $ \case
        Text' l t -> maybe (bad l "based-on" t (T.intercalate "、" (map fst builtinRules) <> " のどれかにします")) (pure . (t,)) (lookup t builtinRules)
        v -> typeError "string" v
    let r0 = maybe printRules snd base
    name <- optKey "name"
    let r1 = r0 {ruName = name}
    r2 <- check "glyph-missing" r1 $ \r -> levelKey r ruGlyphMissing (\x -> r {ruGlyphMissing = x})
    r3 <- check "font-formats" r2 $ \r -> do
      a <- levelKey r ruFontFormats (\x -> r {ruFontFormats = x})
      textsKey "allowed" fontFormatValues a ruFontFormatsAllowed (\x -> a {ruFontFormatsAllowed = x})
    r4 <- check "type-size" r3 $ \r -> do
      a <- levelKey r ruTypeSize (\x -> r {ruTypeSize = x})
      b <- lengthKey "min-size" a ruTypeSizeMin (\x -> a {ruTypeSizeMin = x})
      maybe b (\x -> b {ruTypeSizeMultiInkOnly = x}) <$> optKey "multi-ink-only"
    r6 <- check "image-resolution" r4 $ \r -> do
      a <- tierKey "color" r ruResolutionColor (\x -> r {ruResolutionColor = x})
      b <- tierKey "gray" a ruResolutionGray (\x -> a {ruResolutionGray = x})
      tierKey "bitmap" b ruResolutionBitmap (\x -> b {ruResolutionBitmap = x})
    r7 <- check "image-resolution-max" r6 $ \r -> do
      a <- levelKey r ruImageResolutionMax (\x -> r {ruImageResolutionMax = x})
      b <- countKey "color-max" a ruColorMax (\x -> a {ruColorMax = x})
      c <- countKey "gray-max" b ruGrayMax (\x -> b {ruGrayMax = x})
      countKey "bitmap-max" c ruBitmapMax (\x -> c {ruBitmapMax = x})
    r8 <- check "image-color-space" r7 $ \r -> do
      a <- levelKey r ruImageColorSpace (\x -> r {ruImageColorSpace = x})
      textsKey "allowed" colorSpaceValues a ruColorSpacesAllowed (\x -> a {ruColorSpacesAllowed = x})
    r9 <- check "image-icc" r8 $ \r -> levelKey r ruImageIcc (\x -> r {ruImageIcc = x})
    r10 <- check "bleed-size" r9 $ \r -> do
      a <- levelKey r ruBleedSize (\x -> r {ruBleedSize = x})
      lengthKey "min" a ruBleedMin (\x -> a {ruBleedMin = x})
    r11 <- check "bleed-trim-hazard" r10 $ \r -> do
      a <- levelKey r ruBleedTrimHazard (\x -> r {ruBleedTrimHazard = x})
      lengthKey "distance" a ruTrimHazardDistance (\x -> a {ruTrimHazardDistance = x})
    r12 <- check "live-area" r11 $ \r -> do
      a <- levelKey r ruLiveArea (\x -> r {ruLiveArea = x})
      lengthKey "distance" a ruLiveAreaDistance (\x -> a {ruLiveAreaDistance = x})
    r13 <- check "overfull-lines" r12 $ \r -> levelKey r ruOverfullLines (\x -> r {ruOverfullLines = x})
    r14 <- check "pdf-x" r13 $ \r -> levelKey r ruPdfX (\x -> r {ruPdfX = x})
    r15 <- check "ink-coverage" r14 $ \r -> do
      a <- levelKey r ruInkCoverage (\x -> r {ruInkCoverage = x})
      countKey "max" a ruInkMax (\x -> a {ruInkMax = x})
    r16 <- check "page-count" r15 $ \r -> do
      a <- levelKey r ruPageCount (\x -> r {ruPageCount = x})
      positiveKey "multiple-of" a ruPageMultiple (\x -> a {ruPageMultiple = x})
    r17 <- check "blank-pages" r16 $ \r -> levelKey r ruBlankPages (\x -> r {ruBlankPages = x})
    r18 <- check "stroke-weight" r17 $ \r -> do
      a <- levelKey r ruStrokeWeight (\x -> r {ruStrokeWeight = x})
      lengthKey "min" a ruStrokeMin (\x -> a {ruStrokeMin = x})
    r19 <- check "font-embedding" r18 $ \r -> levelKey r ruFontEmbedding (\x -> r {ruFontEmbedding = x})
    r20 <- check "spot-colors" r19 $ \r -> levelKey r ruSpotColors (\x -> r {ruSpotColors = x})
    r21 <- check "cmy-plates" r20 $ \r -> levelKey r ruCmyPlates (\x -> r {ruCmyPlates = x})
    pure (RulesFile r21)
    where
      -- the table of one check, when written
      check name r p = fromMaybe r <$> optKeyOf name (parseTableFromValue (p r))
      levelKey r _ set =
        optKeyOf "severity" levelOf >>= \case
          Nothing -> pure r
          Just x -> pure (set x)
      lengthKey k r _ set = maybe r set <$> optKeyOf k (lengthOf k)
      countKey k r _ set = maybe r set <$> optKeyOf k (countOf k 0)
      positiveKey k r _ set = maybe r set <$> optKeyOf k (countOf k 1)
      textsKey k allowed r _ set = maybe r set <$> optKeyOf k (textsOf k allowed)
      tierKey k r get set = maybe r set <$> optKeyOf k (tierOf k (get r))

levelOf :: Value' l -> Matcher l Level
levelOf = \case
  Text' l t -> maybe (bad l "severity" t (T.intercalate "、" (map fst levelValues) <> " のどれかにします")) pure (lookup t levelValues)
  v -> typeError "string" v

-- | The values of severity: a notice cannot be chosen (golem-cli ADR 0006).
levelValues :: [(Text, Level)]
levelValues = [("error", LevelError), ("warning", LevelWarning), ("off", LevelOff)]

-- | The values of allowed of [font-formats] and of [image-color-space].
fontFormatValues, colorSpaceValues :: [Text]
fontFormatValues = ["cff", "cff2", "truetype"]
colorSpaceValues = ["cmyk", "gray", "rgb"]

{- | The keys of a file of rules and their values (docs/adr ADR 0169), in
the order the decoder reads them. A key the decoder reads and the schema
does not have is unknown to 'parseRules'; a key the schema has and the
decoder does not read is caught by the test of the schema.
-}
rulesSchema :: Node
rulesSchema =
  NTable
    [ ("based-on", NValue (LEnum (map fst builtinRules))),
      ("name", NValue LString),
      ("glyph-missing", check []),
      ("font-formats", check [("allowed", NArray (NValue (LEnum fontFormatValues)))]),
      ("type-size", check [("min-size", len'), ("multi-ink-only", NValue LBoolean)]),
      ("image-resolution", NTable [("color", tier), ("gray", tier), ("bitmap", tier)]),
      ("image-resolution-max", check [("color-max", count), ("gray-max", count), ("bitmap-max", count)]),
      ("image-color-space", check [("allowed", NArray (NValue (LEnum colorSpaceValues)))]),
      ("image-icc", check []),
      ("bleed-size", check [("min", len')]),
      ("bleed-trim-hazard", check [("distance", len')]),
      ("live-area", check [("distance", len')]),
      ("overfull-lines", check []),
      ("pdf-x", check []),
      ("ink-coverage", check [("max", count)]),
      ("page-count", check [("multiple-of", count)]),
      ("blank-pages", check []),
      ("stroke-weight", check [("min", len')]),
      ("font-embedding", check []),
      ("spot-colors", check []),
      ("cmy-plates", check [])
    ]
  where
    check kvs = NTable (("severity", NValue (LEnum (map fst levelValues))) : kvs)
    tier = NTable [("error-below", count), ("warning-below", count)]
    len' = NValue LDimension
    count = NValue LInteger

lengthOf :: Text -> Value' l -> Matcher l Sp
lengthOf k = \case
  Integer' _ 0 -> pure 0
  Text' l t -> case parseDim t of
    Just (Abs s) -> pure s
    Just (Zw _) -> bad l k t "zw は使えません。3mm や 0.25pt のように書きます"
    Nothing -> bad l k t "長さは 3mm や 0.25pt のように書きます"
  v -> typeError "string" v

{- | A natural number at least @low@ and at most 1000000, read as
toml-parser reads a 'Natural': a negative number is G02103 (docs/adr ADR
0102).
-}
countOf :: Text -> Natural -> Value' l -> Matcher l Natural
countOf k low = \case
  v@(Integer' l _) ->
    naturalOf v >>= \n ->
      if n < low
        then bad l k (T.pack (show n)) (T.pack (show low) <> " 以上の整数にします")
        else
          if n > 1000000
            then bad l k (T.pack (show n)) "大きすぎます"
            else pure n
  v -> typeError "integer" v

textsOf :: Text -> [Text] -> Value' l -> Matcher l [Text]
textsOf k allowed v = do
  ts <- fromValue v
  case [t | t <- ts, t `notElem` allowed] of
    (t : _) -> bad (valueAnn v) k t (T.intercalate "、" allowed <> " のどれかにします")
    [] -> pure ts

tierOf :: Text -> Tier -> Value' l -> Matcher l Tier
tierOf k base v@(Table' l _) = do
  (e, w) <- parseTableFromValue ((,) <$> optKeyOf "error-below" (countOf "error-below" 0) <*> optKeyOf "warning-below" (countOf "warning-below" 0)) v
  let t = Tier (fromMaybe (tierErrorBelow base) e) (fromMaybe (tierWarningBelow base) w)
  when (tierWarningBelow t /= 0 && tierErrorBelow t > tierWarningBelow t) $
    bad l (k <> ".error-below") (T.pack (show (tierErrorBelow t))) ("warning-below の " <> T.pack (show (tierWarningBelow t)) <> " より大きくできません")
  pure t
tierOf _ _ v = typeError "table" v
