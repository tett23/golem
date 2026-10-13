-- | style.toml (golem-project ADR 0002).
module Golem.Project.Style
  ( Style (..),
    Dim (..),
    Sp,
    parseDim,
    dimToSp,
    Page (..),
    Grid (..),
    FontRole (..),
    CharStyleDef (..),
    LineBreaks (..),
    ParaStyleDef (..),
    builtinCharStyles,
    builtinParaStyles,
    charStyle,
    paraStyle,
    validStyleName,
    HeadingStyle (..),
    Composition (..),
    SidenoteStyle (..),
    VerseStyle (..),
    defaultVerseStyle,
    MasterDef (..),
    Swatch (..),
    defaultStyle,
    parseStyle,
    loadStyle,
    pageSize,
    validNumberFormat,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (when)
import Data.Char (isAsciiLower, isDigit)
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
    pageGrid :: !(Maybe Grid)
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
    psSpaceBetween :: !(Maybe Int)
  }
  deriving stock (Eq, Show)

noChar :: CharStyleDef
noChar = CharStyleDef Nothing Nothing Nothing Nothing Nothing Nothing

noPara :: ParaStyleDef
noPara = ParaStyleDef Nothing Nothing Nothing Nothing Nothing

-- | The built-in character styles: bold, italic and strong.
builtinCharStyles :: Map Text CharStyleDef
builtinCharStyles =
  Map.fromList
    [ ("bold", noChar {csSyntheticBold = Just True}),
      ("italic", noChar {csSyntheticItalic = Just True}),
      ("strong", noChar {csBasedOn = Just "bold"})
    ]

-- | The built-in paragraph styles: body, verse, caption and sidenote.
builtinParaStyles :: Map Text ParaStyleDef
builtinParaStyles =
  Map.fromList
    [ ("body", noPara {psLineBreaks = Just JoinLines, psSpaceBetween = Just 0}),
      ("verse", noPara {psBasedOn = Just "body", psLineBreaks = Just KeepLines, psSpaceBetween = Just 1}),
      ("caption", noPara {psBasedOn = Just "body"}),
      ("sidenote", noPara {psBasedOn = Just "body"})
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
      defaults = noPara {psLineBreaks = Just JoinLines, psSpaceBetween = Just 0}
   in case chainOf paraParent (stParaStyles style) name of
        [] -> Nothing
        chain@(d : _) -> Just (foldr overPara defaults chain) {psBasedOn = paraParent name d}

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
    compRubyOverhang :: !Dim,
    compKenten :: !Text,
    compPretolerance :: !Int,
    compTolerance :: !Int,
    compEmergencyStretch :: !Dim,
    compProtrusion :: !Bool,
    compExpansion :: !(Maybe (Int, Int))
  }
  deriving stock (Eq, Show)

data SidenoteStyle = SidenoteStyle
  { snWidth :: !Dim,
    snGap :: !Dim,
    snFont :: !(Maybe Text),
    snSize :: !(Maybe Dim),
    snMarker :: !Text
  }
  deriving stock (Eq, Show)

{- | [verse] (docs/adr ADR 0003): the indent and the hang of the lines of
every paragraph style with line-breaks = "keep" (docs/adr ADR 0005).
-}
data VerseStyle = VerseStyle
  { -- | the start of every line
    vsIndent :: !Dim,
    -- | the continuation of a line broken at the measure, beyond the indent
    vsHang :: !Dim
  }
  deriving stock (Eq, Show)

defaultVerseStyle :: VerseStyle
defaultVerseStyle = VerseStyle (Zw 0) (Zw 2)

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
    stVerse :: !VerseStyle
  }
  deriving stock (Eq, Show)

defaultComposition :: Composition
defaultComposition = Composition True False (Zw 1) "sesame" 100 200 (Abs 0) False Nothing

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
      stVerse = defaultVerseStyle
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
    pure (Page size (binding == Just "right") (wm == Just "vertical") grid)

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
    pure (ParaStyleDef b f s ((\x -> if x == "keep" then KeepLines else JoinLines) <$> lb) sb)

instance FromValue HeadingStyle where
  fromValue = parseTableFromValue $ do
    f <- optKey "font"
    s <- dimKey "size"
    n <- optKey "number"
    pb <- enumKey "page-break" ["recto", "any"]
    rh <- fromMaybe False <$> optKey "running-head"
    pure (HeadingStyle f s n (pb == Just "recto") rh)

newtype RubyOpt = RubyOpt Dim

instance FromValue RubyOpt where
  fromValue = parseTableFromValue $ do
    _ <- enumKey "position" ["mono-center"]
    o <- dimKey "overhang"
    pure (RubyOpt (fromMaybe (Zw 1) o))

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
    let d = defaultComposition
    pure
      Composition
        { compKinsokuStrict = maybe (compKinsokuStrict d) (== "strict") k,
          compHanging = fromMaybe (compHanging d) h,
          compRubyOverhang = maybe (compRubyOverhang d) (\(RubyOpt o) -> o) r,
          compKenten = fromMaybe (compKenten d) kt,
          compPretolerance = fromMaybe (compPretolerance d) pre,
          compTolerance = fromMaybe (compTolerance d) tol,
          compEmergencyStretch = fromMaybe (compEmergencyStretch d) es,
          compProtrusion = fromMaybe False pr,
          compExpansion = (\(Expansion l s) -> (l, s)) <$> ex
        }

instance FromValue SidenoteStyle where
  fromValue = parseTableFromValue $ do
    _ <- enumKey "side" ["outside"]
    w <- reqDim "width"
    g <- reqDim "gap"
    f <- optKey "font"
    s <- dimKey "size"
    m <- enumKey "marker" ["number", "symbol", "none"]
    pure (SidenoteStyle w g f s (fromMaybe "number" m))

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

instance FromValue VerseStyle where
  fromValue = parseTableFromValue $ do
    i <- dimKey "indent"
    h <- dimKey "hang"
    g <- optKey "stanza-gap"
    when (isJust (g :: Maybe Int)) $ fail "[verse] の stanza-gap は廃止しました。[paragraph-styles.verse] の space-between に書き換えます"
    let d = defaultVerseStyle
    pure (VerseStyle (fromMaybe (vsIndent d) i) (fromMaybe (vsHang d) h))

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
    verse <- fromMaybe defaultVerseStyle <$> optKey "verse"
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
          stVerse = verse
        }
    where
      headingLevel (k, v) = case k of
        "1" -> pure (1, v)
        "2" -> pure (2, v)
        "3" -> pure (3, v)
        _ -> fail ("heading level must be 1, 2 or 3: " <> T.unpack k)

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
  case [diagnostic "G0306" Error (mkSpan fid 0 0) m | m <- checks s]
    <> [diagnostic "G0308" Error (mkSpan fid 0 0) m | m <- roleChecks s]
    <> [diagnostic "G0313" Error (mkSpan fid 0 0) ("style.toml のスタイルの参照が不正です: " <> m) | m <- referenceChecks s]
    <> [diagnostic "G0311" Error (mkSpan fid 0 0) ("段落スタイルの文字の大きさが版面の文字の大きさを超えます: " <> n) | n <- sizeChecks s] of
    [] -> Right s
    ds -> Left ds
  where
    -- font roles named outside [fonts] must exist (golem-driver ADR 0003, 0004; docs/adr ADR 0005)
    roleChecks s =
      [ "style.toml にないフォントの役割です: " <> r
      | r <-
          [f | HeadingStyle {hsFont = Just f} <- Map.elems (stHeadings s)]
            <> [f | CharStyleDef {csFont = Just f} <- Map.elems (stCharStyles s)]
            <> [f | ParaStyleDef {psFont = Just f} <- Map.elems (stParaStyles s)],
        Map.notMember r (stFonts s)
      ]
    -- based-on names an existing style without a cycle; body has none; colours exist (docs/adr ADR 0005)
    referenceChecks s =
      let cs = stCharStyles s
          ps = stParaStyles s
          cyclic parent styles n = go [n] (Map.lookup n styles >>= parent n)
            where
              go seen = \case
                Nothing -> False
                Just m
                  | m `elem` seen -> True
                  | otherwise -> go (m : seen) (Map.lookup m styles >>= parent m)
       in [ "文字スタイル " <> n <> " の based-on がありません: " <> b
          | (n, CharStyleDef {csBasedOn = Just b}) <- Map.toList cs,
            Map.notMember b cs
          ]
            <> ["文字スタイルの based-on が循環しています: " <> T.intercalate ", " ns | let ns = [n | n <- Map.keys cs, cyclic (const csBasedOn) cs n], not (null ns)]
            <> ["文字スタイル " <> n <> " の color のスウォッチがありません: " <> c | (n, CharStyleDef {csColor = Just c}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            <> ["段落スタイル body には based-on を書けません" | Just ParaStyleDef {psBasedOn = Just _} <- [Map.lookup "body" ps]]
            <> [ "段落スタイル " <> n <> " の based-on がありません: " <> b
               | (n, ParaStyleDef {psBasedOn = Just b}) <- Map.toList ps,
                 n /= "body",
                 Map.notMember b ps
               ]
            <> ["段落スタイルの based-on が循環しています: " <> T.intercalate ", " ns | let ns = [n | n <- Map.keys ps, n /= "body", cyclic paraParent ps n], not (null ns)]
    -- a paragraph style no larger than the grid (docs/adr ADR 0005)
    sizeChecks s = case stPage s >>= pageGrid of
      Just Grid {gridFontSize = Abs fs} ->
        [ n
        | n <- Map.keys (stParaStyles s),
          Just ParaStyleDef {psSize = Just d} <- [paraStyle s (Just n)],
          dimToSp fs d > fs
        ]
      _ -> []
    checks s =
      [ "番号の書式が不正です: " <> f
      | f <- stFigureNumber s : [n | HeadingStyle {hsNumber = Just n} <- Map.elems (stHeadings s)],
        not (validNumberFormat f)
      ]
        <> ["スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: " <> n | n <- Map.keys (stCharStyles s) <> Map.keys (stParaStyles s), not (validStyleName n)]
        <> [ "未知の判型です: " <> pageSizeName p
           | Just p <- [stPage s],
             isNothing (pageSize (pageSizeName p)),
             not (T.any (== 'x') (pageSizeName p))
           ]

{- | Reads style.toml from the project root; a missing file means the
defaults. File references (fonts, ICC profile) must exist.
-}
loadStyle :: (FilePath -> IO Bool) -> FileId -> Maybe Text -> IO (Either [Diagnostic] Style)
loadStyle exists fid = \case
  Nothing -> pure (Right defaultStyle)
  Just src -> case parseStyle fid src of
    Left ds -> pure (Left ds)
    Right s -> do
      let refs = [p | FontRole ja la _ <- Map.elems (stFonts s), Just p <- [ja, la]] <> maybe [] pure (stIntent s)
      missing <- filter (not . snd) <$> traverse (\p -> (p,) <$> exists p) refs
      pure $ case missing of
        [] -> Right s
        ms -> Left [diagnostic "G0306" Error (mkSpan fid 0 0) ("style.toml が指すファイルがありません: " <> T.pack p) | (p, _) <- ms]
