-- | style.toml (golem-project ADR 0002).
module Golem.Project.Style
  ( Style (..),
    Dim (..),
    Sp,
    parseDim,
    parseSignedDim,
    dimToSp,
    parseAki,
    AkiRuleDef (..),
    AkiSetDef (..),
    builtinAkiSetNames,
    defaultAkiSetName,
    akiClassNames,
    Page (..),
    PageSize (..),
    pageTrimSize,
    Grid (..),
    FontRole (..),
    CharStyleDef (..),
    Kerning (..),
    featureKeys,
    LineBreaks (..),
    ParaStyleDef (..),
    RegexStyleDef (..),
    regexStyleKeys,
    localRegexStyleDef,
    checkLocalRegexStyles,
    builtinCharStyles,
    builtinParaStyles,
    noCharDef,
    noParaDef,
    charStyle,
    paraStyle,
    isCodeCharStyle,
    codeParaKeys,
    paraLineBreaks,
    validStyleName,
    LocalStyles (..),
    noLocalStyles,
    StyleKind (..),
    LocalValue (..),
    localStyleDef,
    withLocalStyles,
    checkLocalStyles,
    charStyleKeys,
    paraStyleKeys,
    HeadingStyle (..),
    Composition (..),
    RubyStyleDef (..),
    defaultRubyStyleDef,
    SidenoteStyle (..),
    MasterDef (..),
    RunningHeadDef (..),
    RunningContent (..),
    HeadForm (..),
    HeadPick (..),
    parseRunningContent,
    Swatch (..),
    ListStyle (..),
    defaultListStyle,
    defaultStyle,
    parseStyle,
    loadStyle,
    fontFiles,
    pageSize,
    validNumberFormat,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (unless, when, (>=>))
import Data.Bifunctor (bimap)
import Data.Char (isAsciiLower, isDigit)
import Data.List (nub)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.ListMarkers (NumberFormat, parseNumberFormat)
import Golem.Project.Manifest (decodeStrictBy)
import Golem.Regex (RegexError (..), compile)
import Golem.Syntax
import Toml.Schema
import Toml.Schema.FromValue (typeError)
import Toml.Schema.Matcher (inKey)
import Toml.Semantics (valueAnn)

-- | Scaled points: 1pt = 65536sp.
type Sp = Integer

-- | An absolute length in sp, or a length relative to the font size.
data Dim = Abs !Sp | Zw !Rational
  deriving stock (Eq, Show)

{- | Parses @"13Q"@, @"20mm"@, @"10.5pt"@, @"22H"@, @"1zw"@. Conversion uses
exact rationals and rounds once, half to even.
-}
parseDim :: Text -> Maybe Dim
parseDim t =
  let (num, unit) = T.span (\c -> isDigit c || c == '.') (T.strip t)
   in do
        r <- decimal num
        case unit of
          "pt" -> Just (Abs (round (r * 65536)))
          "mm" -> Just (Abs (mmToSp r))
          "Q" -> Just (Abs (mmToSp (r * (1 % 4))))
          "H" -> Just (Abs (mmToSp (r * (1 % 4))))
          "zw" -> Just (Zw r)
          _ -> Nothing
  where
    decimal s = case T.splitOn "." s of
      [i] | not (T.null i) -> Just (fromInteger (read (T.unpack i)))
      [i, f] | not (T.null i), not (T.null f) -> Just (read (T.unpack (i <> f)) % (10 ^ T.length f))
      _ -> Nothing

{- | A dimension that may be negative: one leading @-@ and a dimension
(docs/adr ADR 0006).
-}
parseSignedDim :: Text -> Maybe Dim
parseSignedDim t = case T.stripPrefix "-" (T.strip t) of
  Just rest
    | not ("-" `T.isPrefixOf` rest) -> negateDim <$> parseDim rest
    | otherwise -> Nothing
  Nothing -> parseDim t
  where
    negateDim = \case
      Abs x -> Abs (negate x)
      Zw r -> Zw (negate r)

-- | Resolves a dimension against a font size.
dimToSp :: Sp -> Dim -> Sp
dimToSp _ (Abs s) = s
dimToSp fontSize (Zw r) = round (r * fromInteger fontSize)

data Grid = Grid
  { gridFontSize :: !Dim,
    gridCharacters :: !Int,
    gridLines :: !Int,
    gridLinePitch :: !Dim,
    gridColumns :: !Int,
    gridColumnGap :: !(Maybe Dim),
    gridTop :: !Dim,
    gridGutter :: !Dim
  }
  deriving stock (Eq, Show)

-- | [page] の size。名前は読み込みで表と照合済みである（ADR 0005）。
data PageSize
  = -- | 判型の表の名前
    NamedSize !Text
  | -- | 幅と高さ（sp）
    CustomSize !Sp !Sp
  deriving stock (Eq, Show)

data Page = Page
  { pageSizeSpec :: !PageSize,
    pageBindingRight :: !Bool,
    pageVertical :: !Bool,
    pageGrid :: !(Maybe Grid),
    -- | the bleed around the trimmed page (golem-pdf ADR 0004); 0 by default
    pageBleed :: !Sp
  }
  deriving stock (Eq, Show)

data FontRole = FontRole
  { frJa :: !(Maybe FilePath),
    frLatin :: !(Maybe FilePath),
    frFeatures :: ![Text]
  }
  deriving stock (Eq, Show)

{- | The kerning method of a style (docs/adr/0020). 'KernOptical' is read
and then rejected by the checks of style.toml (G0321): it is a v2 item.
-}
data Kerning = KernMetrics | KernJapaneseEqualWidth | KernNone | KernOptical
  deriving stock (Eq, Ord, Show)

-- | [character-styles.<name>] (docs/adr ADR 0005).
data CharStyleDef = CharStyleDef
  { csBasedOn :: !(Maybe Text),
    csFont :: !(Maybe Text),
    csSize :: !(Maybe Dim),
    csColor :: !(Maybe Text),
    csSyntheticBold :: !(Maybe Bool),
    csSyntheticItalic :: !(Maybe Bool),
    -- | the kerning method (docs/adr/0020)
    csKerning :: !(Maybe Kerning),
    -- | the space added after each character, in 1/1000 of the size
    csTracking :: !(Maybe Int),
    -- | palt (vpal in vertical text) on Japanese characters
    csProportional :: !(Maybe Bool),
    -- | up in horizontal text, right in vertical text
    csBaselineShift :: !(Maybe Dim)
  }
  deriving stock (Eq, Show)

-- | Whether the newlines of a paragraph break its lines.
data LineBreaks = JoinLines | KeepLines
  deriving stock (Eq, Show)

-- | [paragraph-styles.<name>] (docs/adr ADR 0005).
data ParaStyleDef = ParaStyleDef
  { psBasedOn :: !(Maybe Text),
    psFont :: !(Maybe Text),
    psSize :: !(Maybe Dim),
    psLineBreaks :: !(Maybe LineBreaks),
    psSpaceBetween :: !(Maybe Int),
    -- | the start of every line (docs/adr ADR 0006)
    psIndent :: !(Maybe Dim),
    -- | added to the indent on the first line; negative hangs
    psFirstLineIndent :: !(Maybe Dim),
    -- | the regex styles, in order (docs/adr ADR 0015); replaced as a whole through based-on
    psRegexStyles :: !(Maybe [RegexStyleDef]),
    -- | the aki set the paragraph is set with (docs/adr ADR 0019)
    psAkiSet :: !(Maybe Text),
    -- | the kerning method, tracking, proportional metrics and baseline shift (docs/adr/0020)
    psKerning :: !(Maybe Kerning),
    psTracking :: !(Maybe Int),
    psProportional :: !(Maybe Bool),
    psBaselineShift :: !(Maybe Dim),
    {- | the swatch of the background and the padding inside it (golem-driver
    ADR 0017); v1 sets them only for the paragraph style code
    -} psBackground :: !(Maybe Text),
    psPadding :: !(Maybe Dim)
  }
  deriving stock (Eq, Show)

-- | A regex style: a pattern and the character style for its matches (docs/adr ADR 0015).
data RegexStyleDef = RegexStyleDef
  { rdPattern :: !Text,
    rdStyle :: !Text
  }
  deriving stock (Eq, Show)

-- | A character style with no key written.
noCharDef :: CharStyleDef
noCharDef = CharStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | A paragraph style with no key written.
noParaDef :: ParaStyleDef
noParaDef = ParaStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | The keys body has without a definition (docs/adr ADR 0005, 0006, 0019; docs/adr/0020).
bodyDefaults :: ParaStyleDef
bodyDefaults =
  noParaDef
    { psLineBreaks = Just JoinLines,
      psSpaceBetween = Just 0,
      psIndent = Just (Zw 0),
      psFirstLineIndent = Just (Zw 0),
      psAkiSet = Just defaultAkiSetName,
      psKerning = Just KernMetrics,
      psTracking = Just 0,
      psProportional = Just False,
      psBaselineShift = Just (Abs 0)
    }

{- | An aki amount (docs/adr ADR 0019): a name (ベタ, 全角, 二分, 三分, 四分,
五分, 六分, 八分, 二分四分), a decimal in zw, or a percentage of zw. The
value is in zw; negative amounts are not written.
-}
parseAki :: Text -> Maybe Rational
parseAki t = case T.strip t of
  "ベタ" -> Just 0
  "全角" -> Just 1
  "二分" -> Just (1 % 2)
  "三分" -> Just (1 % 3)
  "四分" -> Just (1 % 4)
  "五分" -> Just (1 % 5)
  "六分" -> Just (1 % 6)
  "八分" -> Just (1 % 8)
  "二分四分" -> Just (3 % 4)
  s -> case T.stripSuffix "%" s of
    Just p -> (/ 100) <$> decimalOf p
    Nothing -> case parseDim s of
      Just (Zw r) | T.isSuffixOf "zw" s -> Just r
      _ -> Nothing

-- | A rule of an aki set: the classes before and after, and (minimum, optimum, maximum) in zw.
data AkiRuleDef = AkiRuleDef
  { arBefore :: ![Text],
    arAfter :: ![Text],
    arMinimum :: !Rational,
    arOptimum :: !Rational,
    arMaximum :: !Rational
  }
  deriving stock (Eq, Show)

-- | [aki-sets.<name>]: the set it is based on and the rules added after the base's.
data AkiSetDef = AkiSetDef
  { asBasedOn :: !(Maybe Text),
    asRules :: ![AkiRuleDef]
  }
  deriving stock (Eq, Show)

-- | The built-in aki sets, which a user cannot define again.
builtinAkiSetNames :: [Text]
builtinAkiSetNames = ["gyomatsu-yakumono-hankaku", "gyomatsu-yakumono-zenkaku"]

-- | The aki set of body, and the base of a set without based-on.
defaultAkiSetName :: Text
defaultAkiSetName = "gyomatsu-yakumono-hankaku"

-- | The names of the character classes of the rules (JLReq; docs/adr ADR 0019).
akiClassNames :: [Text]
akiClassNames =
  [ "opening",
    "closing",
    "hyphen",
    "dividing",
    "middle-dot",
    "full-stop",
    "comma",
    "inseparable",
    "iteration",
    "prolonged-sound",
    "small-kana",
    "ideographic-space",
    "kana",
    "ideograph",
    "western",
    "japanese"
  ]

-- | A non-negative decimal: digits with an optional fraction.
decimalOf :: Text -> Maybe Rational
decimalOf s = case T.splitOn "." s of
  [i] | not (T.null i), T.all isDigit i -> Just (fromInteger (read (T.unpack i)))
  [i, f] | not (T.null i), not (T.null f), T.all isDigit (i <> f) -> Just (read (T.unpack (i <> f)) % (10 ^ T.length f))
  _ -> Nothing

-- | The built-in character styles: bold, italic, strong and code (golem-driver ADR 0017).
builtinCharStyles :: Map Text CharStyleDef
builtinCharStyles =
  Map.fromList
    [ ("bold", noCharDef {csSyntheticBold = Just True}),
      ("code", noCharDef {csFont = Just "code"}),
      ("italic", noCharDef {csSyntheticItalic = Just True}),
      ("strong", noCharDef {csBasedOn = Just "bold"})
    ]

-- | The built-in paragraph styles: body, verse, caption, sidenote and code (golem-driver ADR 0017).
builtinParaStyles :: Map Text ParaStyleDef
builtinParaStyles =
  Map.fromList
    [ ("body", bodyDefaults),
      ("verse", noParaDef {psBasedOn = Just "body", psLineBreaks = Just KeepLines, psSpaceBetween = Just 1, psIndent = Just (Zw 2), psFirstLineIndent = Just (Zw (-2))}),
      ("caption", noParaDef {psBasedOn = Just "body"}),
      ("sidenote", noParaDef {psBasedOn = Just "body"}),
      ("code", noParaDef {psFont = Just "code", psPadding = Just (Zw (1 % 2))})
    ]

-- | The keys the paragraph style code takes (golem-driver ADR 0017).
codeParaKeys :: [Text]
codeParaKeys = ["font", "size", "background", "padding"]

{- | Whether a character style is code or reaches code through based-on
(golem-driver ADR 0017).
-}
isCodeCharStyle :: Style -> Text -> Bool
isCodeCharStyle style = go []
  where
    go seen name
      | name == "code" = Map.member "code" (stCharStyles style)
      | name `elem` seen = False
      | otherwise = maybe False (go (name : seen)) (Map.lookup name (stCharStyles style) >>= csBasedOn)

-- | A user definition over a built-in one: the keys written win.
overChar :: CharStyleDef -> CharStyleDef -> CharStyleDef
overChar u b =
  CharStyleDef
    (csBasedOn u <|> csBasedOn b)
    (csFont u <|> csFont b)
    (csSize u <|> csSize b)
    (csColor u <|> csColor b)
    (csSyntheticBold u <|> csSyntheticBold b)
    (csSyntheticItalic u <|> csSyntheticItalic b)
    (csKerning u <|> csKerning b)
    (csTracking u <|> csTracking b)
    (csProportional u <|> csProportional b)
    (csBaselineShift u <|> csBaselineShift b)

overPara :: ParaStyleDef -> ParaStyleDef -> ParaStyleDef
overPara u b =
  ParaStyleDef
    (psBasedOn u <|> psBasedOn b)
    (psFont u <|> psFont b)
    (psSize u <|> psSize b)
    (psLineBreaks u <|> psLineBreaks b)
    (psSpaceBetween u <|> psSpaceBetween b)
    (psIndent u <|> psIndent b)
    (psFirstLineIndent u <|> psFirstLineIndent b)
    (psRegexStyles u <|> psRegexStyles b)
    (psAkiSet u <|> psAkiSet b)
    (psKerning u <|> psKerning b)
    (psTracking u <|> psTracking b)
    (psProportional u <|> psProportional b)
    (psBaselineShift u <|> psBaselineShift b)
    (psBackground u <|> psBackground b)
    (psPadding u <|> psPadding b)

{- | The parent of a paragraph style: body and code have none (golem-driver
ADR 0017), the others are based on body by default.
-}
paraParent :: Text -> ParaStyleDef -> Maybe Text
paraParent n d = if n `elem` ["body", "code"] then Nothing else Just (fromMaybe "body" (psBasedOn d))

-- | A chain of definitions from a name to its root; stops at a missing name or a cycle.
chainOf :: (Text -> a -> Maybe Text) -> Map Text a -> Text -> [a]
chainOf parent styles = go []
  where
    go seen name
      | name `elem` seen = []
      | otherwise = case Map.lookup name styles of
          Nothing -> []
          Just d -> d : maybe [] (go (name : seen)) (parent name d)

{- | A character style with its based-on chain resolved; an unknown name is
'Nothing'. Keys no style of the chain sets stay 'Nothing' (the outer look).
-}
charStyle :: Style -> Text -> Maybe CharStyleDef
charStyle style name = case chainOf (const csBasedOn) (stCharStyles style) name of
  [] -> Nothing
  chain@(d : _) -> Just (foldr1 overChar chain) {csBasedOn = csBasedOn d}

{- | A paragraph style with its based-on chain resolved (Nothing is body);
an unknown name is 'Nothing'. Every key but the font and the size has a
value; based-on is the style's parent.
-}
paraStyle :: Style -> Maybe Text -> Maybe ParaStyleDef
paraStyle style mname =
  let name = fromMaybe "body" mname
   in case chainOf paraParent (stParaStyles style) name of
        [] -> Nothing
        chain@(d : _) -> Just (foldr overPara bodyDefaults chain) {psBasedOn = paraParent name d}

-- | Whether each paragraph style keeps its lines, resolved (docs/adr ADR 0005).
paraLineBreaks :: Style -> Map Text LineBreaks
paraLineBreaks style =
  Map.fromList [(n, fromMaybe JoinLines (psLineBreaks d)) | n <- Map.keys (stParaStyles style), Just d <- [paraStyle style (Just n)]]

-- | Style names are used as HTML classes: [a-z][a-z0-9-]*.
validStyleName :: Text -> Bool
validStyleName n = case T.uncons n of
  Just (c, rest) -> isAsciiLower c && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
  Nothing -> False

data HeadingStyle = HeadingStyle
  { hsFont :: !(Maybe Text),
    hsSize :: !(Maybe Dim),
    hsNumber :: !(Maybe Text),
    hsRectoBreak :: !Bool
  }
  deriving stock (Eq, Show)

data Composition = Composition
  { compKinsokuStrict :: !Bool,
    compHanging :: !Bool,
    -- | [composition.ruby] (golem-layout ADR 0009)
    compRuby :: !RubyStyleDef,
    compKenten :: !Text,
    compPretolerance :: !Int,
    compTolerance :: !Int,
    compEmergencyStretch :: !Dim,
    compProtrusion :: !Bool,
    compExpansion :: !(Maybe (Int, Int)),
    -- | the penalty of a break after an explicit hyphen (golem-layout ADR 0008)
    compExplicitHyphenPenalty :: !Int
  }
  deriving stock (Eq, Show)

-- | The placement of ruby (golem-layout ADR 0009).
data RubyStyleDef = RubyStyleDef
  { -- | "center" | "start"
    rdMonoAlign :: !Text,
    -- | "1:2:1" | "0:1:0" | "center" | "start"
    rdGroupAlign :: !Text,
    -- | "1:2:1" | "0:1:0" | "center"
    rdBaseSpacing :: !Text,
    rdOverhang :: !Dim,
    -- | "kana" | "none"
    rdOverhangOnto :: !Text
  }
  deriving stock (Eq, Show)

-- | JLReq's usual setting.
defaultRubyStyleDef :: RubyStyleDef
defaultRubyStyleDef = RubyStyleDef "center" "1:2:1" "1:2:1" (Zw (1 % 2)) "kana"

{- | [sidenotes]: the sidenote column and the marker. The font and the size
are the paragraph style sidenote's (golem-driver ADR 0011).
-}
data SidenoteStyle = SidenoteStyle
  { snWidth :: !Dim,
    snGap :: !Dim,
    snMarker :: !Text
  }
  deriving stock (Eq, Show)

-- | How a heading is shown in a running head (golem-driver ADR 0014).
data HeadForm = HeadShort | HeadNumbered
  deriving stock (Eq, Show)

-- | Which heading of a page a running head takes: the first or the last.
data HeadPick = PickFirst | PickLast
  deriving stock (Eq, Show)

-- | What a running head shows.
data RunningContent
  = -- | a heading of a level
    RunningHeading !Int !HeadForm !HeadPick
  | -- | the title of the book
    RunningTitle
  | RunningNone
  deriving stock (Eq, Show)

-- | The running head of a master page: its position and the contents of odd and even pages.
data RunningHeadDef = RunningHeadDef
  { rhPosition :: !Text,
    rhOdd :: !RunningContent,
    rhEven :: !RunningContent
  }
  deriving stock (Eq, Show)

data MasterDef = MasterDef
  { mdRunningHead :: !(Maybe RunningHeadDef),
    mdFolio :: !(Maybe (Text, Text)) -- position, format
  }
  deriving stock (Eq, Show)

{- | [lists] (golem-driver ADR 0013): the bullet and the number format of
each depth, and the gap between a marker and the text. Without numbers,
the default of the writing mode is used.
-}
data ListStyle = ListStyle
  { lsBullets :: !(NonEmpty Text),
    lsNumbers :: !(Maybe (NonEmpty NumberFormat)),
    lsGap :: !(Maybe Dim)
  }
  deriving stock (Eq, Show)

-- | No [lists]: the bullet ・, the numbers and the gap of the writing mode.
defaultListStyle :: ListStyle
defaultListStyle = ListStyle ("・" :| []) Nothing Nothing

{- | A content value of a running head: @heading.<l>.short@,
@heading.<l>.numbered@ (either with @.last@), @title@ or @none@
(golem-driver ADR 0014).
-}
parseRunningContent :: Text -> Maybe RunningContent
parseRunningContent = \case
  "title" -> Just RunningTitle
  "none" -> Just RunningNone
  t -> case T.splitOn "." t of
    ["heading", l, f] -> heading l f PickFirst
    ["heading", l, f, "last"] -> heading l f PickLast
    _ -> Nothing
  where
    heading l f pick = do
      level <- if not (T.null l) && T.all isDigit l then Just (read (T.unpack l)) else Nothing
      form <- case f of
        "short" -> Just HeadShort
        "numbered" -> Just HeadNumbered
        _ -> Nothing
      if level >= 1 then Just (RunningHeading level form pick) else Nothing

newtype Swatch = Swatch (Int, Int, Int, Int)
  deriving stock (Eq, Show)

data Style = Style
  { stPage :: !(Maybe Page),
    stFonts :: !(Map Text FontRole),
    -- | the built-in character styles with the user's definitions over them
    stCharStyles :: !(Map Text CharStyleDef),
    -- | the built-in paragraph styles with the user's definitions over them
    stParaStyles :: !(Map Text ParaStyleDef),
    stHeadings :: !(Map Int HeadingStyle),
    stComposition :: !Composition,
    stNumbersVertical :: !Text,
    stNotesPlacement :: !Text,
    stSidenotes :: !(Maybe SidenoteStyle),
    stFigureNumber :: !Text,
    stWrapGap :: !Dim,
    stIntent :: !(Maybe FilePath),
    stSwatches :: !(Map Text Swatch),
    stMasters :: !(Map Text MasterDef),
    -- | [toc] leader: "dots" or "none" (golem-driver ADR 0009)
    stTocLeader :: !Text,
    -- | [lists]: the markers of lists, for the whole book (golem-driver ADR 0013)
    stLists :: !ListStyle,
    -- | [aki-sets.<name>]: the user's aki sets, not the built-in ones (docs/adr ADR 0019)
    stAkiSets :: !(Map Text AkiSetDef)
  }
  deriving stock (Eq, Show)

defaultComposition :: Composition
defaultComposition = Composition True False defaultRubyStyleDef "sesame" 100 200 (Abs 0) False Nothing 50

defaultStyle :: Style
defaultStyle =
  Style
    { stPage = Nothing,
      stFonts = Map.empty,
      stCharStyles = builtinCharStyles,
      stParaStyles = builtinParaStyles,
      stHeadings = Map.empty,
      stComposition = defaultComposition,
      stNumbersVertical = "kanji",
      stNotesPlacement = "page-foot",
      stSidenotes = Nothing,
      stFigureNumber = "図{chapter}-{n}",
      stWrapGap = Zw 1,
      stIntent = Nothing,
      stSwatches = Map.empty,
      stMasters = Map.empty,
      stTocLeader = "dots",
      stLists = defaultListStyle,
      stAkiSets = Map.empty
    }

-- | JIS B series, A series, 四六判, 菊判, 新書判 and mass-market, in millimetres.
pageSize :: Text -> Maybe (Rational, Rational)
pageSize = \case
  "A4" -> Just (210, 297)
  "A5" -> Just (148, 210)
  "A6" -> Just (105, 148)
  "B5" -> Just (182, 257)
  "B6" -> Just (128, 182)
  "四六判" -> Just (127, 188)
  -- ADR 0005
  "菊判" -> Just (150, 220)
  "新書判" -> Just (103, 182)
  -- 4.25in x 6.875in (ADR 0003)
  "mass-market" -> Just (17 / 4 * 254 / 10, 55 / 8 * 254 / 10)
  _ -> Nothing

-- | 仕上がりの幅と高さ（sp）。
pageTrimSize :: Page -> (Sp, Sp)
pageTrimSize p = case pageSizeSpec p of
  -- the name was checked against the table when style.toml was read
  NamedSize n -> maybe (0, 0) (bimap mmToSp mmToSp) (pageSize n)
  CustomSize w h -> (w, h)

-- | Millimetres to sp, rounded once, half to even.
mmToSp :: Rational -> Sp
mmToSp mm = round (mm * 72 * 65536 / (254 % 10))

{- | A name of the table, or @{ width, height }@ in absolute dimensions
greater than 0 (ADR 0005). Errors are at the value of size.
-}
instance FromValue PageSize where
  fromValue v = case v of
    Text' l n
      | isJust (pageSize n) -> pure (NamedSize n)
      | otherwise -> failAt l ("未知の判型です: " <> T.unpack n <> "。表にない判型は size = { width = \"…\", height = \"…\" } で書きます")
    Table' l _ -> do
      (w, h) <- parseTableFromValue ((,) <$> dimKey "width" <*> dimKey "height") v
      case (w, h) of
        (Just w', Just h') -> CustomSize <$> side l w' <*> side l h'
        _ -> failAt l "判型の width と height はどちらも必須です"
    _ -> typeError "page size name or { width = ..., height = ... }" v
    where
      side l = \case
        Abs x
          | x > 0 -> pure x
          | otherwise -> failAt l "判型の幅と高さは 0 より大きい寸法です"
        -- the page size does not depend on the size of the type, as the bleed
        Zw _ -> failAt l "判型には zw を使えません"

newtype DimV = DimV Dim

instance FromValue DimV where
  fromValue (Text' _ t) = case parseDim t of
    Just d -> pure (DimV d)
    Nothing
      -- the names of aki amounts and percentages are only for aki (docs/adr ADR 0019): G0320
      | Just _ <- parseAki t -> fail (T.unpack (akiError ("アキの量の名前と百分率は、アキの量を書く欄でだけ使えます。寸法は 0.5zw や 2mm のように書きます: " <> t)))
      | otherwise -> fail ("長さの書き方が不正です: " <> T.unpack t <> "（13Q や 20mm のように書きます）")
  fromValue _ = fail "長さは文字列で書きます"

-- | The message of G0320 (docs/adr ADR 0019).
akiError :: Text -> Text
akiError why = "アキの量の指定が正しくありません: " <> why

-- | An aki amount of a rule.
newtype AkiV = AkiV Rational

instance FromValue AkiV where
  fromValue (Text' _ t) = maybe (fail (T.unpack (akiError ("アキの量として読めません: " <> t)))) (pure . AkiV) (parseAki t)
  fromValue _ = fail (T.unpack (akiError "アキの量は \"四分\" や \"25%\" のように文字列で書きます"))

-- | The classes of one side of a rule: a name or an array of names.
newtype ClassesV = ClassesV [Text]

instance FromValue ClassesV where
  fromValue (Text' _ t) = pure (ClassesV [t])
  fromValue v@(List' _ _) = ClassesV <$> fromValue v
  fromValue _ = fail (T.unpack (akiError "クラスは名前の文字列か、その配列で書きます"))

instance FromValue AkiRuleDef where
  fromValue = parseTableFromValue $ do
    ClassesV before <- reqKey "before"
    ClassesV after <- reqKey "after"
    AkiV o <- reqKey "optimum"
    n <- maybe o (\(AkiV x) -> x) <$> optKey "minimum"
    m <- maybe o (\(AkiV x) -> x) <$> optKey "maximum"
    let bad why = fail (T.unpack (akiError why))
        known = (`elem` akiClassNames)
    case [c | c <- before, not (known c || c `elem` ["line-start", "paragraph-start"])] of
      (c : _)
        | c == "line-end" -> bad "line-end は after にだけ書けます"
        | otherwise -> bad ("未知のクラスの名前です: " <> c)
      [] -> pure ()
    case [c | c <- after, not (known c || c == "line-end")] of
      (c : _)
        | c `elem` ["line-start", "paragraph-start"] -> bad (c <> " は before にだけ書けます")
        | otherwise -> bad ("未知のクラスの名前です: " <> c)
      [] -> pure ()
    when (null before || null after) $ bad "before と after には一つ以上のクラスを書きます"
    unless (n <= o && o <= m) $ bad "minimum、optimum、maximum の順に小さくない値を書きます"
    pure (AkiRuleDef before after n o m)

instance FromValue AkiSetDef where
  fromValue = parseTableFromValue (AkiSetDef <$> optKey "based-on" <*> (fromMaybe [] <$> optKey "rules"))

unDim :: Maybe DimV -> Maybe Dim
unDim = fmap (\(DimV d) -> d)

dimKey :: Text -> ParseTable l (Maybe Dim)
dimKey k = unDim <$> optKey k

reqDim :: Text -> ParseTable l Dim
reqDim k = (\(DimV d) -> d) <$> reqKey k

enumKey :: Text -> [Text] -> ParseTable l (Maybe Text)
enumKey k allowed = do
  v <- optKey k
  case v of
    Just x | x `notElem` allowed -> fail (T.unpack (k <> " に使えない値です: " <> x <> "（" <> T.intercalate ", " allowed <> " のどれか）"))
    _ -> pure v

instance FromValue Grid where
  fromValue = parseTableFromValue $ do
    fs <- reqDim "font-size"
    ch <- reqKey "characters"
    ls <- reqKey "lines"
    lp <- reqDim "line-pitch"
    cols <- fromMaybe 1 <$> optKey "columns"
    gap <- dimKey "column-gap"
    pos <- reqKey "position"
    when (cols > 1 && isNothing gap) $ fail "columns が 2 以上のときは column-gap が要ります"
    let Position2 t g = pos
    pure (Grid fs ch ls lp cols gap t g)

data Position2 = Position2 Dim Dim

instance FromValue Position2 where
  fromValue = parseTableFromValue (Position2 <$> reqDim "top" <*> reqDim "gutter")

instance FromValue Page where
  fromValue = parseTableFromValue $ do
    size <- reqKey "size"
    binding <- enumKey "binding" ["right", "left"]
    wm <- enumKey "writing-mode" ["vertical", "horizontal"]
    grid <- optKey "grid"
    bleed <-
      dimKey "bleed" >>= \case
        Nothing -> pure 0
        Just (Abs s) -> pure s
        -- the bleed does not depend on the size of the type (golem-pdf ADR 0004)
        Just (Zw _) -> fail "塗り足しには zw を使えません"
    pure (Page size (binding == Just "right") (wm == Just "vertical") grid bleed)

instance FromValue FontRole where
  fromValue =
    parseTableFromValue $
      (FontRole . fmap T.unpack <$> optKey "ja") <*> (fmap T.unpack <$> optKey "latin") <*> (fromMaybe [] <$> optKey "features")

instance FromValue CharStyleDef where
  fromValue = parseTableFromValue $ do
    b <- optKey "based-on"
    f <- optKey "font"
    s <- dimKey "size"
    c <- optKey "color"
    sb <- optKey "synthetic-bold"
    si <- optKey "synthetic-italic"
    (k, t, p, bs) <- featureKeysOf
    pure (CharStyleDef b f s c sb si k t p bs)

{- | kerning, tracking, proportional-metrics and baseline-shift
(docs/adr/0020). Every error is under its key, which makes it G0321.
-}
featureKeysOf :: ParseTable l (Maybe Kerning, Maybe Int, Maybe Bool, Maybe Dim)
featureKeysOf = do
  let wrong key v = fail (T.unpack (key <> " の値が正しくありません: " <> v))
  k <-
    optKeyOf "kerning" $
      fromValue >=> \case
        "metrics" -> pure KernMetrics
        "japanese-equal-width" -> pure KernJapaneseEqualWidth
        "none" -> pure KernNone
        "optical" -> pure KernOptical
        v -> wrong "kerning" v
  t <-
    optKeyOf "tracking" $
      fromValue >=> \n ->
        if n < -1000 || n > 10000 then wrong "tracking" (T.pack (show n) <> "（-1000 から 10000 までです）") else pure n
  p <- optKey "proportional-metrics"
  bs <- optKeyOf "baseline-shift" (fromValue >=> \v -> maybe (wrong "baseline-shift" v) pure (parseSignedDim v))
  pure (k, t, p, bs)

-- | The keys of 'featureKeysOf': their errors are G0321 (docs/adr/0020).
featureKeys :: [Text]
featureKeys = ["kerning", "tracking", "proportional-metrics", "baseline-shift"]

instance FromValue ParaStyleDef where
  fromValue = parseTableFromValue $ do
    b <- optKey "based-on"
    f <- optKey "font"
    s <- dimKey "size"
    lb <- enumKey "line-breaks" ["join", "keep"]
    sb <- optKey "space-between"
    when (maybe False (< 0) sb) $ fail "space-between は 0 以上です"
    ind <- dimKey "indent"
    fli <- optKey "first-line-indent"
    fli' <- traverse (\v -> maybe (fail ("長さの書き方が不正です: " <> T.unpack v <> "（1zw や -1zw のように書きます）")) pure (parseSignedDim v)) fli
    rs <- optKey "regex-styles"
    aki <- optKey "aki-set"
    (k, t, p, bs) <- featureKeysOf
    bg <- optKey "background"
    pad <- optKey "padding"
    -- a negative padding is read and reported by the checks (golem-driver ADR 0017)
    pad' <- traverse (\v -> maybe (fail ("長さの書き方が不正です: " <> T.unpack v <> "（0.5zw や 1mm のように書きます）")) pure (parseSignedDim v)) pad
    pure (ParaStyleDef b f s ((\x -> if x == "keep" then KeepLines else JoinLines) <$> lb) sb ind fli' rs aki k t p bs bg pad')

instance FromValue RegexStyleDef where
  fromValue = parseTableFromValue (RegexStyleDef <$> reqKey "pattern" <*> reqKey "style")

instance FromValue HeadingStyle where
  fromValue = parseTableFromValue $ do
    f <- optKey "font"
    s <- dimKey "size"
    n <- optKey "number"
    pb <- enumKey "page-break" ["recto", "any"]
    -- retired (golem-driver ADR 0014): G0319
    pickKey
      [ Key "running-head" (\v -> failAt (valueAnn v) "[headings.<l>] の running-head は廃止しました。柱に使う見出しは [masters.<名前>] の running-head の content で指定してください"),
        Else (pure ())
      ]
    pure (HeadingStyle f s n (pb == Just "recto"))

instance FromValue RubyStyleDef where
  fromValue = parseTableFromValue $ do
    m <- enumKey "mono-align" ["center", "start"]
    g <- enumKey "group-align" ["1:2:1", "0:1:0", "center", "start"]
    b <- enumKey "base-spacing" ["1:2:1", "0:1:0", "center"]
    o <- dimKey "overhang"
    onto <- enumKey "overhang-onto" ["kana", "none"]
    let d = defaultRubyStyleDef
    pure
      RubyStyleDef
        { rdMonoAlign = fromMaybe (rdMonoAlign d) m,
          rdGroupAlign = fromMaybe (rdGroupAlign d) g,
          rdBaseSpacing = fromMaybe (rdBaseSpacing d) b,
          rdOverhang = fromMaybe (rdOverhang d) o,
          rdOverhangOnto = fromMaybe (rdOverhangOnto d) onto
        }

data Expansion = Expansion Int Int

instance FromValue Expansion where
  fromValue = parseTableFromValue (Expansion <$> reqKey "limit" <*> reqKey "step")

instance FromValue Composition where
  fromValue = parseTableFromValue $ do
    k <- enumKey "kinsoku" ["strict", "loose"]
    h <- optKey "hanging-punctuation"
    r <- optKey "ruby"
    kt <- optKey "kenten"
    pre <- optKey "pretolerance"
    tol <- optKey "tolerance"
    es <- dimKey "emergency-stretch"
    pr <- optKey "protrusion"
    ex <- optKey "expansion"
    eh <- optKey "explicit-hyphen-penalty"
    let d = defaultComposition
    pure
      Composition
        { compKinsokuStrict = maybe (compKinsokuStrict d) (== "strict") k,
          compHanging = fromMaybe (compHanging d) h,
          compRuby = fromMaybe (compRuby d) r,
          compKenten = fromMaybe (compKenten d) kt,
          compPretolerance = fromMaybe (compPretolerance d) pre,
          compTolerance = fromMaybe (compTolerance d) tol,
          compEmergencyStretch = fromMaybe (compEmergencyStretch d) es,
          compProtrusion = fromMaybe False pr,
          compExpansion = (\(Expansion l s) -> (l, s)) <$> ex,
          compExplicitHyphenPenalty = fromMaybe (compExplicitHyphenPenalty d) eh
        }

instance FromValue SidenoteStyle where
  fromValue = parseTableFromValue $ do
    _ <- enumKey "side" ["outside"]
    w <- reqDim "width"
    g <- reqDim "gap"
    f <- optKey "font"
    s <- optKey "size"
    when (isJust (f :: Maybe Text) || isJust (s :: Maybe Text)) $
      fail "[sidenotes] の font と size は廃止しました。[paragraph-styles.sidenote] の font と size に書き換えます"
    m <- enumKey "marker" ["number", "symbol", "none"]
    pure (SidenoteStyle w g (fromMaybe "number" m))

-- | The positions of a running head and a folio (golem-driver ADR 0014).
masterPositions :: [Text]
masterPositions = ["top-outside", "top-inside", "top-center", "bottom-outside", "bottom-inside", "bottom-center"]

{- | A position of a master page; an unknown one is an error at its value,
which makes it G0318 (golem-driver ADR 0016).
-}
newtype MasterPosition = MasterPosition Text

instance FromValue MasterPosition where
  fromValue v = case v of
    Text' l p
      | p `elem` masterPositions -> pure (MasterPosition p)
      | otherwise -> failAt l ("未知の位置です: " <> T.unpack p)
    _ -> typeError "position such as top-outside" v

reqPosition :: ParseTable l Text
reqPosition = (\(MasterPosition p) -> p) <$> reqKey "position"

data PosContent = PosContent Text Text

instance FromValue PosContent where
  fromValue = parseTableFromValue $ do
    p <- reqPosition
    c <- optKey "content"
    f <- optKey "format"
    pure (PosContent p (fromMaybe "" (c <> f)))

-- | The message of G0314 (golem-driver ADR 0014).
runningContentMessage :: Text -> String
runningContentMessage v =
  T.unpack ("柱の内容が正しくありません: " <> v <> "。heading.<階層>.short か heading.<階層>.numbered（末尾に .last を付けられます）、title、none のどれかを、content に一つ、または even と odd の両方に書いてください")

{- | A running head: @position@, and @content@ or both @even@ and @odd@.
Errors of the contents are reported under their key, which makes them
G0314.
-}
instance FromValue RunningHeadDef where
  fromValue = parseTableFromValue $ do
    p <- reqPosition
    let contentOf v = do
          t <- fromValue v
          maybe (failAt (valueAnn v) (runningContentMessage t)) (pure . (t,)) (parseRunningContent t)
    c <- optKeyOf "content" contentOf
    e <- optKeyOf "even" contentOf
    o <- optKeyOf "odd" contentOf
    let written = T.intercalate ", " [k <> " = \"" <> t <> "\"" | (k, Just (t, _)) <- [("content", c), ("even", e), ("odd", o)]]
        wrong k = liftMatcher (inKey k (fail (runningContentMessage (if T.null written then "（なし）" else written))))
    case (c, e, o) of
      (Just (_, x), Nothing, Nothing) -> pure (RunningHeadDef p x x)
      (Nothing, Just (_, x), Just (_, y)) -> pure (RunningHeadDef p y x)
      (Just _, _, _) -> wrong "content"
      (Nothing, Just _, Nothing) -> wrong "odd"
      (Nothing, Nothing, Just _) -> wrong "even"
      (Nothing, Nothing, Nothing) -> wrong "content"

instance FromValue MasterDef where
  fromValue = parseTableFromValue $ do
    rh <- optKey "running-head"
    fo <- optKey "folio"
    let pc (PosContent a b) = (a, b)
    pure (MasterDef rh (pc <$> fo))

instance FromValue Swatch where
  fromValue = parseTableFromValue $ do
    cs <- reqKey "cmyk"
    case cs of
      [c, m, y, k] | all (\x -> x >= 0 && x <= 100) cs -> pure (Swatch (c, m, y, k))
      _ -> fail "cmyk は 0 から 100 までの整数四つです"

newtype Numbers = Numbers (Maybe Text)

instance FromValue Numbers where
  fromValue = parseTableFromValue (Numbers <$> enumKey "vertical" ["kanji", "kanji-digits", "tcy"])

-- | The retired [emphasis] (docs/adr ADR 0005): an error that names its replacement.
data EmphasisV

instance FromValue EmphasisV where
  fromValue _ =
    fail
      "[emphasis] は廃止しました。strong = \"italic\" は [character-styles.strong] の based-on = \"italic\" に、bold-font は [character-styles.bold] の font に、italic-font は [character-styles.italic] の font に書き換えます"

newtype Notes = Notes (Maybe Text)

instance FromValue Notes where
  fromValue = parseTableFromValue (Notes <$> enumKey "placement" ["page-foot", "chapter-end"])

data Figures = Figures (Maybe Text) (Maybe Dim)

instance FromValue Figures where
  fromValue = parseTableFromValue (Figures <$> optKey "number" <*> dimKey "wrap-gap")

-- | The retired [verse] (docs/adr ADR 0005, 0006): an error that names its replacement.
data VerseV

instance FromValue VerseV where
  fromValue _ =
    fail
      "[verse] は廃止しました。indent = I と hang = H は [paragraph-styles.verse] の indent = I + H と first-line-indent = -H に、stanza-gap は [paragraph-styles.verse] の space-between に書き換えます"

{- | [lists] (golem-driver ADR 0013): every error names its key; they are
G0322 by their path.
-}
newtype ListsSec = ListsSec ListStyle

instance FromValue ListsSec where
  fromValue = parseTableFromValue $ do
    bullets <- optKey "bullets"
    numbers <- optKey "numbers"
    gap <- optKey "gap"
    let bad key why = fail (T.unpack ("[lists] の " <> key <> " が正しくありません: " <> why))
        nonEmpty key = \case
          Nothing -> pure Nothing
          Just [] -> bad key "空の配列です"
          Just (x : rest)
            | any T.null (x : rest) -> bad key "空の文字列があります"
            | otherwise -> pure (Just (x :| rest))
    bs <- nonEmpty "bullets" bullets
    ns <- nonEmpty "numbers" numbers
    fmts <- traverse (traverse (\f -> either (\why -> bad "numbers" (why <> ": " <> f)) pure (parseNumberFormat f))) ns
    g <- case gap of
      Nothing -> pure Nothing
      Just t -> case parseSignedDim t of
        Nothing -> bad "gap" ("寸法として読めません: " <> t)
        Just d
          | negativeDim d -> bad "gap" ("負の寸法です: " <> t)
          | otherwise -> pure (Just d)
    pure (ListsSec (ListStyle (fromMaybe (lsBullets defaultListStyle) bs) fmts g))

newtype TocSec = TocSec (Maybe Text)

instance FromValue TocSec where
  fromValue = parseTableFromValue (TocSec <$> enumKey "leader" ["dots", "none"])

data ColorSec = ColorSec (Maybe Text) (Map Text Swatch)

instance FromValue ColorSec where
  fromValue = parseTableFromValue (ColorSec <$> optKey "intent" <*> (fromMaybe Map.empty <$> optKey "swatches"))

instance FromValue Style where
  fromValue = parseTableFromValue $ do
    page <- optKey "page"
    fonts <- fromMaybe Map.empty <$> optKey "fonts"
    cstyles <- fromMaybe Map.empty <$> optKey "character-styles"
    pstyles <- fromMaybe Map.empty <$> optKey "paragraph-styles"
    headings <- fromMaybe Map.empty <$> optKey "headings"
    comp <- fromMaybe defaultComposition <$> optKey "composition"
    Numbers nv <- fromMaybe (Numbers Nothing) <$> optKey "numbers"
    -- the value of a retired table fails with how to rewrite it
    (_ :: Maybe EmphasisV) <- optKey "emphasis"
    Notes np <- fromMaybe (Notes Nothing) <$> optKey "notes"
    side <- optKey "sidenotes"
    Figures fnum fgap <- fromMaybe (Figures Nothing Nothing) <$> optKey "figures"
    ColorSec intent swatches <- fromMaybe (ColorSec Nothing Map.empty) <$> optKey "color"
    masters <- fromMaybe Map.empty <$> optKey "masters"
    (_ :: Maybe VerseV) <- optKey "verse"
    TocSec leader <- fromMaybe (TocSec Nothing) <$> optKey "toc"
    ListsSec lists <- fromMaybe (ListsSec defaultListStyle) <$> optKey "lists"
    akiSets <- fromMaybe Map.empty <$> optKey "aki-sets"
    -- the built-in sets cannot be defined again (docs/adr ADR 0019)
    case filter (`elem` builtinAkiSetNames) (Map.keys akiSets) of
      (n : _) -> liftMatcher (inKey "aki-sets" (inKey n (fail (T.unpack (akiError ("組み込みのアキ量のセットと同じ名前です。based-on で引き継いだ別の名前のセットを作ります: " <> n))))))
      [] -> pure ()
    hs <- traverse headingLevel (Map.toList (headings :: Map Text HeadingStyle))
    let d = defaultStyle
    pure
      Style
        { stPage = page,
          stFonts = fonts,
          stCharStyles = Map.unionWith overChar cstyles builtinCharStyles,
          stParaStyles = Map.unionWith overPara pstyles builtinParaStyles,
          stHeadings = Map.fromList hs,
          stComposition = comp,
          stNumbersVertical = fromMaybe (stNumbersVertical d) nv,
          stNotesPlacement = fromMaybe (stNotesPlacement d) np,
          stSidenotes = side,
          stFigureNumber = fromMaybe (stFigureNumber d) fnum,
          stWrapGap = fromMaybe (stWrapGap d) fgap,
          stIntent = T.unpack <$> intent,
          stSwatches = swatches,
          stMasters = masters,
          stTocLeader = fromMaybe (stTocLeader d) leader,
          stLists = lists,
          stAkiSets = akiSets
        }
    where
      headingLevel (k, v) = case k of
        "1" -> pure (1, v)
        "2" -> pure (2, v)
        "3" -> pure (3, v)
        _ -> fail ("見出しの段は 1、2、3 のどれかです: " <> T.unpack k)

negativeDim :: Dim -> Bool
negativeDim = \case
  Abs x -> x < 0
  Zw r -> r < 0

-- | Placeholders allowed in number formats.
validNumberFormat :: Text -> Bool
validNumberFormat = go
  where
    go t = case T.breakOn "{" t of
      (_, rest)
        | T.null rest -> True
        | otherwise ->
            let (inside, after) = T.breakOn "}" (T.drop 1 rest)
             in not (T.null after)
                  && inside `elem` ["n", "n:kanji", "1", "2", "chapter"]
                  && go (T.drop 1 after)

{- | Parses style.toml and checks what can be checked without the
filesystem.
-}
parseStyle :: FileId -> Text -> Either [Diagnostic] Style
parseStyle fid src = do
  s <- either (Left . map akiCode) Right (decodeStrictBy "G0306" codeAt fid src)
  case nub [(code, m) | (code, _, m) <- styleChecks "style.toml の" s] of
    [] -> Right s
    ds -> Left [diagnostic code Error (mkSpan fid 0 0) m | (code, m) <- ds]
  where
    -- an aki amount wrong in any key is G0320 (docs/adr ADR 0019)
    akiCode d
      | akiError "" `T.isPrefixOf` diagMessage d = d {diagCode = DiagnosticCode "G0320"}
      | otherwise = d
    -- errors of the page size are G0317 (ADR 0005)
    codeAt = \case
      ScopeKey "page" : ScopeKey "size" : _ -> "G0317"
      -- errors of [lists] are G0322 (golem-driver ADR 0013)
      ScopeKey "lists" : _ -> "G0322"
      -- errors of [aki-sets] are G0320 (docs/adr ADR 0019)
      ScopeKey "aki-sets" : _ -> "G0320"
      -- the contents of a running head are G0314, the retired running-head of a heading G0319 (golem-driver ADR 0014)
      ScopeKey "masters" : _ : ScopeKey "running-head" : ScopeKey k : _ | k `elem` ["content", "even", "odd"] -> "G0314"
      -- an unknown position of a running head or a folio is G0318 (golem-driver ADR 0016)
      ScopeKey "masters" : _ : ScopeKey k : ScopeKey "position" : _ | k `elem` ["running-head", "folio"] -> "G0318"
      ScopeKey "headings" : _ : ScopeKey "running-head" : _ -> "G0319"
      -- the keys of kerning, tracking and baseline shift are G0321 (docs/adr/0020)
      ScopeKey t : _ : ScopeKey k : _ | t `elem` ["character-styles", "paragraph-styles"], k `elem` featureKeys -> "G0321"
      _ -> "G0306"

{- | The checks of the styles of a 'Style' (docs/adr ADR 0005, 0006, 0014):
the code, the name of the style it is about (empty when it is about no
style) and the message. @owner@ starts the message of G0313: where the
definitions were written.
-}
styleChecks :: Text -> Style -> [(Text, Text, Text)]
styleChecks owner s =
  [("G0306", "", m) | m <- numberChecks]
    <> [("G0306", n, "スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: " <> n) | n <- Map.keys (stCharStyles s) <> Map.keys (stParaStyles s), not (validStyleName n)]
    <> [("G0306", "", m) | m <- checks]
    <> [("G0306", n, m) | (n, m) <- codeChecks]
    <> [("G0308", n, "style.toml にないフォントの役割です: " <> r) | (n, r) <- roles, Map.notMember r (stFonts s)]
    <> [("G0313", n, owner <> "スタイルの参照が不正です: " <> m) | (n, m) <- referenceChecks]
    <> [(code, n, m) | (n, ParaStyleDef {psRegexStyles = Just rs}) <- Map.toList (stParaStyles s), (i, r) <- zip [0 ..] rs, (code, m) <- regexStyleErrors owner s n i r]
    <> [("G0311", n, "段落スタイルの文字の大きさが版面の文字の大きさを超えます: " <> n) | n <- sizeChecks]
    <> [("G0312", n, "段落の最初の行が版面の外に出ます。indent と first-line-indent の和を 0 以上にしてください: " <> n) | n <- indentChecks]
    <> [("G0321", n, "v1 ではオプティカルカーニングを使えません（" <> kind <> " " <> n <> " の kerning）") | (kind, n) <- opticals]
  where
    -- optical kerning is a v2 item (docs/adr/0020)
    opticals =
      [("文字スタイル", n) | (n, CharStyleDef {csKerning = Just KernOptical}) <- Map.toList (stCharStyles s)]
        <> [("段落スタイル", n) | (n, ParaStyleDef {psKerning = Just KernOptical}) <- Map.toList (stParaStyles s)]
    {- font roles named outside [fonts] must exist (golem-driver ADR 0003, 0004; docs/adr ADR 0005);
    the role code of the styles code may be missing: the body role sets code (golem-driver ADR 0017) -}
    roles =
      [("", f) | HeadingStyle {hsFont = Just f} <- Map.elems (stHeadings s)]
        <> [(n, f) | (n, CharStyleDef {csFont = Just f}) <- Map.toList (stCharStyles s), (n, f) /= ("code", "code")]
        <> [(n, f) | (n, ParaStyleDef {psFont = Just f}) <- Map.toList (stParaStyles s), (n, f) /= ("code", "code")]
    {- the paragraph style code takes four keys; background and padding are
    for code only; a padding is not negative (golem-driver ADR 0017) -}
    codeChecks =
      [ ("code", "段落スタイル code に書けるキーは " <> T.intercalate "、" codeParaKeys <> " だけです: " <> T.intercalate ", " ks)
      | Just d <- [Map.lookup "code" (stParaStyles s)],
        let ks = writtenOtherKeys d,
        not (null ks)
      ]
        <> [ (n, "background と padding は段落スタイル code にだけ書けます: " <> n)
           | (n, d) <- Map.toList (stParaStyles s),
             n /= "code",
             isJust (psBackground d) || isJust (psPadding d)
           ]
        <> [("code", "padding は 0 以上の寸法です") | Just ParaStyleDef {psPadding = Just p} <- [Map.lookup "code" (stParaStyles s)], negativeDim p]
    writtenOtherKeys d =
      [ k
      | (k, written) <-
          [ ("based-on", isJust (psBasedOn d)),
            ("line-breaks", isJust (psLineBreaks d)),
            ("space-between", isJust (psSpaceBetween d)),
            ("indent", isJust (psIndent d)),
            ("first-line-indent", isJust (psFirstLineIndent d)),
            ("regex-styles", isJust (psRegexStyles d)),
            ("aki-set", isJust (psAkiSet d)),
            ("kerning", isJust (psKerning d)),
            ("tracking", isJust (psTracking d)),
            ("proportional-metrics", isJust (psProportional d)),
            ("baseline-shift", isJust (psBaselineShift d))
          ],
        written
      ]
    -- based-on names an existing style without a cycle; body has none; colours exist (docs/adr ADR 0005)
    referenceChecks =
      let cs = stCharStyles s
          ps = stParaStyles s
          cyclic parent styles n = go [n] (Map.lookup n styles >>= parent n)
            where
              go seen = \case
                Nothing -> False
                Just m
                  | m `elem` seen -> True
                  | otherwise -> go (m : seen) (Map.lookup m styles >>= parent m)
          charCycle = [n | n <- Map.keys cs, cyclic (const csBasedOn) cs n]
          paraCycle = [n | n <- Map.keys ps, n /= "body", cyclic paraParent ps n]
          akiKnown n = n `elem` builtinAkiSetNames || Map.member n (stAkiSets s)
          akiCycle = [n | n <- Map.keys (stAkiSets s), cyclic (const asBasedOn) (stAkiSets s) n]
       in [ (n, "文字スタイル " <> n <> " の based-on がありません: " <> b)
          | (n, CharStyleDef {csBasedOn = Just b}) <- Map.toList cs,
            Map.notMember b cs
          ]
            <> [(n, "文字スタイルの based-on が循環しています: " <> T.intercalate ", " charCycle) | n <- charCycle]
            <> [(n, "文字スタイル " <> n <> " の color のスウォッチがありません: " <> c) | (n, CharStyleDef {csColor = Just c}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            <> [("body", "段落スタイル body には based-on を書けません") | Just ParaStyleDef {psBasedOn = Just _} <- [Map.lookup "body" ps]]
            <> [ (n, "段落スタイル " <> n <> " の based-on がありません: " <> b)
               | (n, ParaStyleDef {psBasedOn = Just b}) <- Map.toList ps,
                 n `notElem` ["body", "code"],
                 Map.notMember b ps
               ]
            -- code is not a base of other styles (golem-driver ADR 0017)
            <> [ (n, "段落スタイル code は based-on に書けません。コードブロックの段落スタイルです: " <> n)
               | (n, ParaStyleDef {psBasedOn = Just "code"}) <- Map.toList ps,
                 n /= "code"
               ]
            -- the swatch of a background (golem-driver ADR 0017)
            <> [(n, "段落スタイル " <> n <> " の background のスウォッチがありません: " <> c) | (n, ParaStyleDef {psBackground = Just c}) <- Map.toList ps, Map.notMember c (stSwatches s)]
            <> [(n, "段落スタイルの based-on が循環しています: " <> T.intercalate ", " paraCycle) | n <- paraCycle]
            -- aki sets: aki-set and based-on name a set, without a cycle (docs/adr ADR 0019)
            <> [ (n, "段落スタイル " <> n <> " の aki-set のアキ量のセットがありません: " <> a)
               | (n, ParaStyleDef {psAkiSet = Just a}) <- Map.toList ps,
                 not (akiKnown a)
               ]
            <> [ ("", "アキ量のセット " <> n <> " の based-on がありません: " <> b)
               | (n, AkiSetDef {asBasedOn = Just b}) <- Map.toList (stAkiSets s),
                 not (akiKnown b)
               ]
            <> [("", "アキ量のセットの based-on が循環しています: " <> T.intercalate ", " akiCycle) | not (null akiCycle)]
    -- a paragraph style no larger than the grid (docs/adr ADR 0005)
    sizeChecks = case stPage s >>= pageGrid of
      Just Grid {gridFontSize = Abs fs} ->
        [ n
        | n <- Map.keys (stParaStyles s),
          Just ParaStyleDef {psSize = Just d} <- [paraStyle s (Just n)],
          dimToSp fs d > fs
        ]
      _ -> []
    {- the first line inside the type area: indent + first-line-indent >= 0
    (docs/adr ADR 0006); zw and absolute lengths together only with a grid -}
    indentChecks =
      let gridSize = case stPage s >>= pageGrid of
            Just Grid {gridFontSize = Abs fs} -> Just fs
            _ -> Nothing
          negative d = case (psIndent d, psFirstLineIndent d) of
            (Just (Zw a), Just (Zw b)) -> a + b < 0
            (Just (Abs a), Just (Abs b)) -> a + b < 0
            (Just a, Just b) | Just fs <- gridSize -> let size = maybe fs (dimToSp fs) (psSize d) in dimToSp size a + dimToSp size b < 0
            _ -> False
       in [n | n <- Map.keys (stParaStyles s), Just d <- [paraStyle s (Just n)], negative d]
    numberChecks =
      [ "番号の書式が不正です: " <> f
      | f <- stFigureNumber s : [n | HeadingStyle {hsNumber = Just n} <- Map.elems (stHeadings s)],
        not (validNumberFormat f)
      ]
    checks =
      [ "explicit-hyphen-penalty は -9999 から 10000 までです: " <> T.pack (show p)
      | let p = compExplicitHyphenPenalty (stComposition s),
        p < -9999 || p > 10000
      ]
        <> [ "ルビのかけの量は 0 以上です（[composition.ruby] の overhang）"
           | negativeDim (rdOverhang (compRuby (stComposition s)))
           ]

-- ------------------------------------------------------------------ styles in a file

{- | Styles defined in a file (docs/adr ADR 0014). A name of style.toml or
a built-in style has only the keys written, laid over the definition of
the same name by 'withLocalStyles'.
-}
data LocalStyles = LocalStyles
  { lsCharStyles :: !(Map Text CharStyleDef),
    lsParaStyles :: !(Map Text ParaStyleDef),
    -- | the regex styles of @style-def regex by paragraph style, in the order written (docs/adr ADR 0015)
    lsRegexStyles :: !(Map Text [RegexStyleDef])
  }
  deriving stock (Eq, Show)

noLocalStyles :: LocalStyles
noLocalStyles = LocalStyles Map.empty Map.empty Map.empty

-- | The kind of a style @style-def defines.
data StyleKind = CharacterKind | ParagraphKind
  deriving stock (Eq, Show)

-- | A value in the source: a word or a string.
data LocalValue = LocalWord Text | LocalString Text
  deriving stock (Eq, Show)

-- | The keys @style-def takes, as style.toml's (for completion).
charStyleKeys, paraStyleKeys, regexStyleKeys :: [Text]
charStyleKeys = ["based-on", "font", "size", "color", "synthetic-bold", "synthetic-italic"] <> featureKeys
paraStyleKeys = ["based-on", "font", "size", "line-breaks", "space-between", "indent", "first-line-indent", "aki-set"] <> featureKeys <> ["background", "padding"]
regexStyleKeys = ["pattern", "style"]

{- | The keys of one @style-def as a TOML table, read with the 'FromValue'
of style.toml: a string is a string, the words true and false are
booleans, a word of digits (with a leading -) is an integer, any other
word is a string. Errors are (code, message): G0321 for the keys of
kerning, tracking and baseline shift (docs/adr/0020), G0306 for the others.
-}
localStyleDef :: StyleKind -> [(Text, LocalValue)] -> Either [(Text, Text)] (Either CharStyleDef ParaStyleDef)
localStyleDef kind kvs = case kind of
  CharacterKind -> Left <$> readLocal kvs
  ParagraphKind -> Right <$> readLocal kvs

-- | The keys of one @style-def regex (docs/adr ADR 0015), read as a regex style of style.toml.
localRegexStyleDef :: [(Text, LocalValue)] -> Either [Text] RegexStyleDef
localRegexStyleDef = either (Left . map snd) Right . readLocal

readLocal :: (FromValue a) => [(Text, LocalValue)] -> Either [(Text, Text)] a
readLocal kvs = run (Table (table [(k, tomlValue v) | (k, v) <- kvs]))
  where
    run :: (FromValue a) => Value -> Either [(Text, Text)] a
    run v = case runMatcher (fromValue v) of
      Failure es -> Left (map message es)
      Success [] a -> Right a
      Success ws _ -> Left (map message ws)
    message (MatchMessage _ path msg) = (codeOf path, T.pack (msg <> concatMap scope path))
    codeOf = \case
      ScopeKey k : _ | k `elem` featureKeys -> "G0321"
      _ -> "G0306"
    scope = \case
      ScopeKey k -> " (" <> T.unpack k <> ")"
      ScopeIndex i -> " [" <> show i <> "]"
    tomlValue = \case
      LocalString t -> Text t
      LocalWord "true" -> Bool True
      LocalWord "false" -> Bool False
      LocalWord w
        | isInteger w -> Integer (read (T.unpack w))
        | otherwise -> Text w
    isInteger w =
      let digits = fromMaybe w (T.stripPrefix "-" w)
       in not (T.null digits) && T.all isDigit digits

{- | The styles of style.toml with the definitions of a file over them:
the same name by 'overChar' and 'overPara' (the keys written win), a new
name added.
-}
withLocalStyles :: Style -> LocalStyles -> Style
withLocalStyles s ls =
  let laid =
        s
          { stCharStyles = Map.unionWith overChar (lsCharStyles ls) (stCharStyles s),
            stParaStyles = Map.unionWith overPara (lsParaStyles ls) (stParaStyles s)
          }
      -- the regex styles of the file after those the style resolves to (docs/adr ADR 0015)
      added p rs d = d {psRegexStyles = Just (fromMaybe [] (paraStyle laid (Just p) >>= psRegexStyles) <> rs)}
   in laid {stParaStyles = Map.foldrWithKey (\p rs -> Map.adjust (added p rs) p) (stParaStyles laid) (lsRegexStyles ls)}

{- | The checks of style.toml on the styles of a file laid over it, less
those style.toml has by itself: (code, the name of the style, message).
-}
checkLocalStyles :: Style -> LocalStyles -> [(Text, Text, Text)]
checkLocalStyles s ls =
  let base = styleChecks owner s
   in nub [c | c <- styleChecks owner (withLocalStyles s ls {lsRegexStyles = Map.empty}), c `notElem` base]
  where
    owner = "@style-def の"

{- | The errors of the i-th (from 0) regex style of a paragraph style
(docs/adr ADR 0015): a pattern outside the dialect is G0315, a character
style that does not exist G0313.
-}
regexStyleErrors :: Text -> Style -> Text -> Int -> RegexStyleDef -> [(Text, Text)]
regexStyleErrors owner s para i (RegexStyleDef p st) =
  [ ( "G0315",
      "正規表現を解釈できません: "
        <> reMessage e
        <> "（"
        <> para
        <> " の "
        <> T.pack (show (i + 1))
        <> " 番目の正規表現の "
        <> T.pack (show (reOffset e + 1))
        <> " 字目）"
    )
  | Left e <- [compile p]
  ]
    <> [("G0313", owner <> "スタイルの参照が不正です: 正規表現スタイルの文字スタイルがありません: " <> st) | Map.notMember st (stCharStyles s)]

{- | The errors of the regex styles of a file (docs/adr ADR 0015): the
paragraph style, the place of the regex style among those the file adds
to it (from 0), the code and the message. The paragraph style must exist
(G0313); the character styles of the file count.
-}
checkLocalRegexStyles :: Style -> LocalStyles -> [(Text, Int, Text, Text)]
checkLocalRegexStyles s ls =
  let combined = withLocalStyles s ls {lsRegexStyles = Map.empty}
   in concat
        [ if Map.member p (stParaStyles combined)
            then [(p, i, code, m) | (code, m) <- regexStyleErrors owner combined p i r]
            else [(p, i, "G0313", owner <> "スタイルの参照が不正です: 正規表現スタイルの段落スタイルがありません: " <> p)]
        | (p, rs) <- Map.toList (lsRegexStyles ls),
          (i, r) <- zip [0 ..] rs
        ]
  where
    owner = "@style-def の"

{- | Reads style.toml from the project root; a missing file means the
defaults. The files it names are not looked for here: each target checks
the files it uses (golem-project ADR 0004).
-}
loadStyle :: FileId -> Maybe Text -> Either [Diagnostic] Style
loadStyle fid = maybe (Right defaultStyle) (parseStyle fid)

-- | Font files named by [fonts]: role, then Japanese before Latin, roles in name order.
fontFiles :: Style -> [(Text, FilePath)]
fontFiles s = [(r, p) | (r, FontRole ja la _) <- Map.toAscList (stFonts s), Just p <- [ja, la]]
