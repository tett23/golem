-- | style.toml (golem-project ADR 0002).
module Golem.Project.Style
  ( Style (..),
    Dim (..),
    Sp,
    parseDim,
    parseSignedDim,
    dimToSp,
    Page (..),
    Grid (..),
    FontRole (..),
    CharStyleDef (..),
    LineBreaks (..),
    ParaStyleDef (..),
    builtinCharStyles,
    builtinParaStyles,
    noCharDef,
    noParaDef,
    charStyle,
    paraStyle,
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
    Swatch (..),
    defaultStyle,
    parseStyle,
    loadStyle,
    fontFiles,
    pageSize,
    validNumberFormat,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (when)
import Data.Char (isAsciiLower, isDigit)
import Data.List (nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Manifest (decodeStrict)
import Golem.Syntax
import Toml.Schema
import Toml.Schema.FromValue (typeError)

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
          "mm" -> Just (Abs (round (r * mmToSp)))
          "Q" -> Just (Abs (round (r * (1 % 4) * mmToSp)))
          "H" -> Just (Abs (round (r * (1 % 4) * mmToSp)))
          "zw" -> Just (Zw r)
          _ -> Nothing
  where
    mmToSp = 72 * 65536 / (254 % 10)
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

data Page = Page
  { pageSizeName :: !Text,
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

-- | [character-styles.<name>] (docs/adr ADR 0005).
data CharStyleDef = CharStyleDef
  { csBasedOn :: !(Maybe Text),
    csFont :: !(Maybe Text),
    csSize :: !(Maybe Dim),
    csColor :: !(Maybe Text),
    csSyntheticBold :: !(Maybe Bool),
    csSyntheticItalic :: !(Maybe Bool)
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
    psFirstLineIndent :: !(Maybe Dim)
  }
  deriving stock (Eq, Show)

-- | A character style with no key written.
noCharDef :: CharStyleDef
noCharDef = CharStyleDef Nothing Nothing Nothing Nothing Nothing Nothing

-- | A paragraph style with no key written.
noParaDef :: ParaStyleDef
noParaDef = ParaStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | The built-in character styles: bold, italic and strong.
builtinCharStyles :: Map Text CharStyleDef
builtinCharStyles =
  Map.fromList
    [ ("bold", noCharDef {csSyntheticBold = Just True}),
      ("italic", noCharDef {csSyntheticItalic = Just True}),
      ("strong", noCharDef {csBasedOn = Just "bold"})
    ]

-- | The built-in paragraph styles: body, verse, caption and sidenote.
builtinParaStyles :: Map Text ParaStyleDef
builtinParaStyles =
  Map.fromList
    [ ("body", noParaDef {psLineBreaks = Just JoinLines, psSpaceBetween = Just 0, psIndent = Just (Zw 0), psFirstLineIndent = Just (Zw 0)}),
      ("verse", noParaDef {psBasedOn = Just "body", psLineBreaks = Just KeepLines, psSpaceBetween = Just 1, psIndent = Just (Zw 2), psFirstLineIndent = Just (Zw (-2))}),
      ("caption", noParaDef {psBasedOn = Just "body"}),
      ("sidenote", noParaDef {psBasedOn = Just "body"})
    ]

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

-- | The parent of a paragraph style: body has none, the others are based on body by default.
paraParent :: Text -> ParaStyleDef -> Maybe Text
paraParent n d = if n == "body" then Nothing else Just (fromMaybe "body" (psBasedOn d))

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
      defaults = noParaDef {psLineBreaks = Just JoinLines, psSpaceBetween = Just 0, psIndent = Just (Zw 0), psFirstLineIndent = Just (Zw 0)}
   in case chainOf paraParent (stParaStyles style) name of
        [] -> Nothing
        chain@(d : _) -> Just (foldr overPara defaults chain) {psBasedOn = paraParent name d}

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
    hsRectoBreak :: !Bool,
    hsRunningHead :: !Bool
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

data MasterDef = MasterDef
  { mdRunningHead :: !(Maybe (Text, Text)), -- position, content
    mdFolio :: !(Maybe (Text, Text)) -- position, format
  }
  deriving stock (Eq, Show)

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
    stTocLeader :: !Text
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
      stTocLeader = "dots"
    }

-- | JIS B series, A series and 四六判, in millimetres.
pageSize :: Text -> Maybe (Rational, Rational)
pageSize = \case
  "A4" -> Just (210, 297)
  "A5" -> Just (148, 210)
  "A6" -> Just (105, 148)
  "B5" -> Just (182, 257)
  "B6" -> Just (128, 182)
  "四六判" -> Just (127, 188)
  -- 4.25in x 6.875in (ADR 0003)
  "mass-market" -> Just (17 / 4 * 254 / 10, 55 / 8 * 254 / 10)
  _ -> Nothing

newtype DimV = DimV Dim

instance FromValue DimV where
  fromValue v@(Text' _ t) = maybe (typeError "dimension such as 13Q or 20mm" v) (pure . DimV) (parseDim t)
  fromValue v = typeError "dimension string" v

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
    Just x | x `notElem` allowed -> fail ("unknown value " <> T.unpack x <> " for " <> T.unpack k)
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
    when (cols > 1 && isNothing gap) $ fail "column-gap is required when columns > 1"
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
  fromValue =
    parseTableFromValue $
      CharStyleDef
        <$> optKey "based-on"
        <*> optKey "font"
        <*> dimKey "size"
        <*> optKey "color"
        <*> optKey "synthetic-bold"
        <*> optKey "synthetic-italic"

instance FromValue ParaStyleDef where
  fromValue = parseTableFromValue $ do
    b <- optKey "based-on"
    f <- optKey "font"
    s <- dimKey "size"
    lb <- enumKey "line-breaks" ["join", "keep"]
    sb <- optKey "space-between"
    when (maybe False (< 0) sb) $ fail "space-between must be 0 or more"
    ind <- dimKey "indent"
    fli <- optKey "first-line-indent"
    fli' <- traverse (\v -> maybe (fail ("dimension such as 1zw or -1zw: " <> T.unpack v)) pure (parseSignedDim v)) fli
    pure (ParaStyleDef b f s ((\x -> if x == "keep" then KeepLines else JoinLines) <$> lb) sb ind fli')

instance FromValue HeadingStyle where
  fromValue = parseTableFromValue $ do
    f <- optKey "font"
    s <- dimKey "size"
    n <- optKey "number"
    pb <- enumKey "page-break" ["recto", "any"]
    rh <- fromMaybe False <$> optKey "running-head"
    pure (HeadingStyle f s n (pb == Just "recto") rh)

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

data PosContent = PosContent Text Text

instance FromValue PosContent where
  fromValue = parseTableFromValue $ do
    p <- reqKey "position"
    c <- optKey "content"
    f <- optKey "format"
    pure (PosContent p (fromMaybe "" (c <> f)))

instance FromValue MasterDef where
  fromValue = parseTableFromValue $ do
    rh <- optKey "running-head"
    fo <- optKey "folio"
    let pc (PosContent a b) = (a, b)
    pure (MasterDef (pc <$> rh) (pc <$> fo))

instance FromValue Swatch where
  fromValue = parseTableFromValue $ do
    cs <- reqKey "cmyk"
    case cs of
      [c, m, y, k] | all (\x -> x >= 0 && x <= 100) cs -> pure (Swatch (c, m, y, k))
      _ -> fail "cmyk must be four integers from 0 to 100"

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
    retiredEmphasis <- optKey "emphasis"
    when (isJust (retiredEmphasis :: Maybe EmphasisV)) $ fail "[emphasis] は廃止しました"
    Notes np <- fromMaybe (Notes Nothing) <$> optKey "notes"
    side <- optKey "sidenotes"
    Figures fnum fgap <- fromMaybe (Figures Nothing Nothing) <$> optKey "figures"
    ColorSec intent swatches <- fromMaybe (ColorSec Nothing Map.empty) <$> optKey "color"
    masters <- fromMaybe Map.empty <$> optKey "masters"
    retiredVerse <- optKey "verse"
    when (isJust (retiredVerse :: Maybe VerseV)) $ fail "[verse] は廃止しました"
    TocSec leader <- fromMaybe (TocSec Nothing) <$> optKey "toc"
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
          stTocLeader = fromMaybe (stTocLeader d) leader
        }
    where
      headingLevel (k, v) = case k of
        "1" -> pure (1, v)
        "2" -> pure (2, v)
        "3" -> pure (3, v)
        _ -> fail ("heading level must be 1, 2 or 3: " <> T.unpack k)

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
  s <- decodeStrict "G0306" fid src
  case nub [(code, m) | (code, _, m) <- styleChecks "style.toml の" s] of
    [] -> Right s
    ds -> Left [diagnostic code Error (mkSpan fid 0 0) m | (code, m) <- ds]

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
    <> [("G0308", n, "style.toml にないフォントの役割です: " <> r) | (n, r) <- roles, Map.notMember r (stFonts s)]
    <> [("G0313", n, owner <> "スタイルの参照が不正です: " <> m) | (n, m) <- referenceChecks]
    <> [("G0311", n, "段落スタイルの文字の大きさが版面の文字の大きさを超えます: " <> n) | n <- sizeChecks]
    <> [("G0312", n, "段落の最初の行が版面の外に出ます。indent と first-line-indent の和を 0 以上にしてください: " <> n) | n <- indentChecks]
  where
    -- font roles named outside [fonts] must exist (golem-driver ADR 0003, 0004; docs/adr ADR 0005)
    roles =
      [("", f) | HeadingStyle {hsFont = Just f} <- Map.elems (stHeadings s)]
        <> [(n, f) | (n, CharStyleDef {csFont = Just f}) <- Map.toList (stCharStyles s)]
        <> [(n, f) | (n, ParaStyleDef {psFont = Just f}) <- Map.toList (stParaStyles s)]
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
       in [ (n, "文字スタイル " <> n <> " の based-on がありません: " <> b)
          | (n, CharStyleDef {csBasedOn = Just b}) <- Map.toList cs,
            Map.notMember b cs
          ]
            <> [(n, "文字スタイルの based-on が循環しています: " <> T.intercalate ", " charCycle) | n <- charCycle]
            <> [(n, "文字スタイル " <> n <> " の color のスウォッチがありません: " <> c) | (n, CharStyleDef {csColor = Just c}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            <> [("body", "段落スタイル body には based-on を書けません") | Just ParaStyleDef {psBasedOn = Just _} <- [Map.lookup "body" ps]]
            <> [ (n, "段落スタイル " <> n <> " の based-on がありません: " <> b)
               | (n, ParaStyleDef {psBasedOn = Just b}) <- Map.toList ps,
                 n /= "body",
                 Map.notMember b ps
               ]
            <> [(n, "段落スタイルの based-on が循環しています: " <> T.intercalate ", " paraCycle) | n <- paraCycle]
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
        <> [ "未知の判型です: " <> pageSizeName p
           | Just p <- [stPage s],
             isNothing (pageSize (pageSizeName p)),
             not (T.any (== 'x') (pageSizeName p))
           ]

-- ------------------------------------------------------------------ styles in a file

{- | Styles defined in a file (docs/adr ADR 0014). A name of style.toml or
a built-in style has only the keys written, laid over the definition of
the same name by 'withLocalStyles'.
-}
data LocalStyles = LocalStyles
  { lsCharStyles :: !(Map Text CharStyleDef),
    lsParaStyles :: !(Map Text ParaStyleDef)
  }
  deriving stock (Eq, Show)

noLocalStyles :: LocalStyles
noLocalStyles = LocalStyles Map.empty Map.empty

-- | The kind of a style @style-def defines.
data StyleKind = CharacterKind | ParagraphKind
  deriving stock (Eq, Show)

-- | A value in the source: a word or a string.
data LocalValue = LocalWord Text | LocalString Text
  deriving stock (Eq, Show)

-- | The keys @style-def takes, as style.toml's (for completion).
charStyleKeys, paraStyleKeys :: [Text]
charStyleKeys = ["based-on", "font", "size", "color", "synthetic-bold", "synthetic-italic"]
paraStyleKeys = ["based-on", "font", "size", "line-breaks", "space-between", "indent", "first-line-indent"]

{- | The keys of one @style-def as a TOML table, read with the 'FromValue'
of style.toml: a string is a string, the words true and false are
booleans, a word of digits (with a leading -) is an integer, any other
word is a string. Errors are messages of G0306.
-}
localStyleDef :: StyleKind -> [(Text, LocalValue)] -> Either [Text] (Either CharStyleDef ParaStyleDef)
localStyleDef kind kvs =
  let tab = Table (table [(k, tomlValue v) | (k, v) <- kvs])
   in case kind of
        CharacterKind -> Left <$> run tab
        ParagraphKind -> Right <$> run tab
  where
    run :: (FromValue a) => Value -> Either [Text] a
    run v = case runMatcher (fromValue v) of
      Failure es -> Left (map message es)
      Success [] a -> Right a
      Success ws _ -> Left (map message ws)
    message (MatchMessage _ path msg) = T.pack (msg <> concatMap scope path)
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
  s
    { stCharStyles = Map.unionWith overChar (lsCharStyles ls) (stCharStyles s),
      stParaStyles = Map.unionWith overPara (lsParaStyles ls) (stParaStyles s)
    }

{- | The checks of style.toml on the styles of a file laid over it, less
those style.toml has by itself: (code, the name of the style, message).
-}
checkLocalStyles :: Style -> LocalStyles -> [(Text, Text, Text)]
checkLocalStyles s ls =
  let base = styleChecks owner s
   in nub [c | c <- styleChecks owner (withLocalStyles s ls), c `notElem` base]
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
