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
    CodeStyle (..),
    defaultCodeStyle,
    codeTokenKinds,
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
    SizeSource (..),
    paraSizeSource,
    charSizeSource,
    sizeSourcePath,
    sizeSourceText,
    isCodeCharStyle,
    charStyleBackground,
    isUrlCharStyle,
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
    NotesPlacement (..),
    Composition (..),
    RubyStyleDef (..),
    defaultRubyStyleDef,
    kentenShapeNames,
    SidenoteStyle (..),
    IndexStyle (..),
    HiddenFolio (..),
    HiddenFolioPages (..),
    defaultHiddenFolio,
    MasterDef (..),
    RunningHeadDef (..),
    RunningContent (..),
    RunningRef (..),
    RunningPart (..),
    HeadForm (..),
    HeadPick (..),
    parseRunningContent,
    parseRunningFormat,
    runningRefs,
    Swatch (..),
    ListStyle (..),
    defaultListStyle,
    RuleSpec (..),
    RuleStyle (..),
    ruleStyleNames,
    paraRules,
    parseRuleSpec,
    defaultStyle,
    parseStyle,
    checkPosition,
    loadStyle,
    fontFiles,
    pageSize,
    validNumberFormat,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (join, unless, when)
import Data.Bifunctor (bimap)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Foldable (toList)
import Data.List (nub, nubBy)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble (NoteNumbering (..))
import Golem.Doc.ListMarkers (NumberFormat, parseNumberFormat)
import Golem.Project.Manifest (decodeStrictBy)
import Golem.Project.TomlMessage (schemaMessage)
import Golem.Regex (RegexError (..), compile)
import Golem.Syntax
import Toml qualified
import Toml.Schema
import Toml.Schema.Matcher (inKey)
import Toml.Semantics (valueAnn)
import Toml.Syntax (Position (..))
import Prelude hiding (fail)

-- | Scaled points: 1pt = 65536sp.
type Sp = Integer

-- | An absolute length in sp, or a length relative to the font size.
data Dim = Abs !Sp | Zw !Rational
  deriving stock (Eq, Show)

{- | Parses @"13Q"@, @"20mm"@, @"10.5pt"@, @"22H"@, @"0.125in"@, @"1zw"@
(1in = 72pt, golem-project ADR 0010). Conversion uses
exact rationals and rounds once, half to even.
-}
parseDim :: Text -> Maybe Dim
parseDim t =
  let (num, unit) = T.span (\c -> isDigit c || c == '.') (T.strip t)
   in do
        r <- decimal num
        case unit of
          "pt" -> Just (Abs (round (r * 65536)))
          "in" -> Just (Abs (round (r * 72 * 65536)))
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
and then rejected by the checks of style.toml (G03021): it is a v2 item.
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
    csBaselineShift :: !(Maybe Dim),
    {- | the swatch of the background of inline code (golem-driver ADR
    0029): Nothing is not written (the background of the paragraph style
    code), Just Nothing is false; for code styles only
    -} csBackground :: !(Maybe (Maybe Text)),
    -- | the padding before and after inline code along the line (golem-driver ADR 0029)
    csPadding :: !(Maybe Dim)
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
    psPadding :: !(Maybe Dim),
    -- | the swatch and the width of the border, for code only (golem-driver ADR 0023)
    psBorder :: !(Maybe Text),
    psBorderWidth :: !(Maybe Dim),
    {- | the rules before and after the paragraph (golem-driver ADR 0027):
    Nothing inherits, Just Nothing is false
    -} psRuleBefore :: !(Maybe (Maybe RuleSpec)),
    psRuleAfter :: !(Maybe (Maybe RuleSpec))
  }
  deriving stock (Eq, Show)

{- | [code] and [code.colors] (golem-driver ADR 0023): the format of the
listing numbers, whether code blocks have line numbers, the swatches of
the line numbers, the highlight and the diff, the wrap mark, the text of
a block continued on the next page, and the swatch of each token kind.
-}
data CodeStyle = CodeStyle
  { cdNumber :: !Text,
    cdLineNumbers :: !Bool,
    cdLineNumberColor :: !(Maybe Text),
    cdHighlight :: !(Maybe Text),
    cdAdded :: !(Maybe Text),
    cdRemoved :: !(Maybe Text),
    cdWrapMark :: !Text,
    cdContinued :: !Text,
    cdColors :: !(Map Text Text)
  }
  deriving stock (Eq, Show)

defaultCodeStyle :: CodeStyle
defaultCodeStyle = CodeStyle "リスト{chapter}-{n}" False Nothing Nothing Nothing Nothing "" "" Map.empty

-- | The token kinds of [code.colors]: skylighting's TokenType in kebab-case.
codeTokenKinds :: [Text]
codeTokenKinds =
  [ "keyword",
    "data-type",
    "dec-val",
    "base-n",
    "float",
    "char",
    "string",
    "comment",
    "other",
    "alert",
    "function",
    "region-marker",
    "error",
    "constant",
    "special-char",
    "verbatim-string",
    "special-string",
    "import",
    "documentation",
    "annotation",
    "comment-var",
    "variable",
    "control-flow",
    "operator",
    "built-in",
    "extension",
    "preprocessor",
    "attribute",
    "information",
    "warning"
  ]

-- | A regex style: a pattern and the character style for its matches (docs/adr ADR 0015).
data RegexStyleDef = RegexStyleDef
  { rdPattern :: !Text,
    rdStyle :: !Text
  }
  deriving stock (Eq, Show)

-- | A character style with no key written.
noCharDef :: CharStyleDef
noCharDef = CharStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

-- | A paragraph style with no key written.
noParaDef :: ParaStyleDef
noParaDef = ParaStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing

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

-- | The built-in character styles: bold, italic, strong, code (golem-driver ADR 0017) and url (golem-doc ADR 0005).
builtinCharStyles :: Map Text CharStyleDef
builtinCharStyles =
  Map.fromList
    [ ("bold", noCharDef {csSyntheticBold = Just True}),
      -- the padding of inline code (golem-driver ADR 0029)
      ("code", noCharDef {csFont = Just "code", csPadding = Just (Zw (1 % 4))}),
      ("italic", noCharDef {csSyntheticItalic = Just True}),
      ("strong", noCharDef {csBasedOn = Just "bold"}),
      ("url", noCharDef)
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
codeParaKeys = ["font", "size", "background", "padding", "border", "border-width"]

{- | Whether a character style is code or reaches code through based-on
(golem-driver ADR 0017).
-}
isCodeCharStyle :: Style -> Text -> Bool
isCodeCharStyle = reachesCharStyle "code"

{- | Whether a character style is url or reaches url through based-on
(golem-doc ADR 0005): the PDF breaks it as code, but it loads no font.
-}
isUrlCharStyle :: Style -> Text -> Bool
isUrlCharStyle = reachesCharStyle "url"

-- | Whether a character style is a built-in one or reaches it through based-on.
reachesCharStyle :: Text -> Style -> Text -> Bool
reachesCharStyle builtin style = go []
  where
    go seen name
      | name == builtin = Map.member builtin (stCharStyles style)
      | name `elem` seen = False
      | otherwise = maybe False (go (name : seen)) (Map.lookup name (stCharStyles style) >>= csBasedOn)

{- | The background of a character style, resolved (golem-driver ADR
0029): its background through based-on, or else the background of the
paragraph style code; false is none.
-}
charStyleBackground :: Style -> Text -> Maybe Text
charStyleBackground style name = case charStyle style name >>= csBackground of
  Just b -> b
  Nothing -> paraStyle style (Just "code") >>= psBackground

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
    (csBackground u <|> csBackground b)
    (csPadding u <|> csPadding b)

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
    (psBorder u <|> psBorder b)
    (psBorderWidth u <|> psBorderWidth b)
    (psRuleBefore u <|> psRuleBefore b)
    (psRuleAfter u <|> psRuleAfter b)

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

{- | The definition of style.toml that decided the size of a character
(golem-cli ADR 0008): the definition that writes @size@ (or @mark-size@,
@font-size@), not the one applied, so that one fix fixes every character
of the group.
-}
data SizeSource
  = -- | @[paragraph-styles.<name>]@ @size@, built-in styles included
    SourceParagraphStyle !Text
  | -- | @[character-styles.<name>]@ @size@, regex styles included
    SourceCharacterStyle !Text
  | -- | @[headings.<level>]@ @size@
    SourceHeading !Int
  | -- | @[notes]@ @mark-size@
    SourceNoteMark
  | -- | @[page.grid]@ @font-size@: no definition writes a size
    SourceGrid
  | -- | @[hidden-folio]@ @size@
    SourceHiddenFolio
  deriving stock (Eq, Ord, Show)

{- | The paragraph style of a based-on chain that writes @size@ (Nothing is
body); the grid when none of the chain does.
-}
paraSizeSource :: Style -> Maybe Text -> SizeSource
paraSizeSource style mname =
  maybe SourceGrid SourceParagraphStyle (firstWriting (namedChainOf paraParent (stParaStyles style) (fromMaybe "body" mname)))
  where
    firstWriting chain = case [n | (n, d) <- chain, isJust (psSize d)] of
      (n : _) -> Just n
      [] -> Nothing

-- | The character style of a based-on chain that writes @size@, if any.
charSizeSource :: Style -> Text -> Maybe Text
charSizeSource style name = case [n | (n, d) <- namedChainOf (const csBasedOn) (stCharStyles style) name, isJust (csSize d)] of
  (n : _) -> Just n
  [] -> Nothing

-- | 'chainOf' with the name of each definition.
namedChainOf :: (Text -> a -> Maybe Text) -> Map Text a -> Text -> [(Text, a)]
namedChainOf parent styles = go []
  where
    go seen name
      | name `elem` seen = []
      | otherwise = case Map.lookup name styles of
          Nothing -> []
          Just d -> (name, d) : maybe [] (go (name : seen)) (parent name d)

-- | The key of style.toml of a size source, as a path: @paragraph-styles.a.size@.
sizeSourcePath :: SizeSource -> Text
sizeSourcePath = \case
  SourceParagraphStyle n -> "paragraph-styles." <> n <> ".size"
  SourceCharacterStyle n -> "character-styles." <> n <> ".size"
  SourceHeading l -> "headings." <> T.pack (show l) <> ".size"
  SourceNoteMark -> "notes.mark-size"
  SourceGrid -> "page.grid.font-size"
  SourceHiddenFolio -> "hidden-folio.size"

-- | A size source as messages name it: @段落スタイル a の size@.
sizeSourceText :: SizeSource -> Text
sizeSourceText = \case
  SourceParagraphStyle n -> "段落スタイル " <> n <> " の size"
  SourceCharacterStyle n -> "文字スタイル " <> n <> " の size"
  SourceHeading l -> "[headings." <> T.pack (show l) <> "] の size"
  SourceNoteMark -> "[notes] の mark-size"
  SourceGrid -> "[page.grid] の font-size"
  SourceHiddenFolio -> "[hidden-folio] の size"

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

{- | The rules before and after the paragraphs of a style, resolved
through based-on (golem-driver ADR 0027).
-}
paraRules :: Style -> Maybe Text -> (Maybe RuleSpec, Maybe RuleSpec)
paraRules style name = case paraStyle style name of
  Just d -> (join (psRuleBefore d), join (psRuleAfter d))
  Nothing -> (Nothing, Nothing)

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
    -- | the least grid lines the heading takes (golem-driver ADR 0032)
    hsLines :: !(Maybe Int),
    -- | the rules before and after the heading (golem-driver ADR 0027)
    hsRuleBefore :: !(Maybe RuleSpec),
    hsRuleAfter :: !(Maybe RuleSpec)
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

{- | [index] (docs/adr ADR 0025): the columns of the index and their gap.
Without columns, the index is set in the columns of the page; without
column-gap, the gap is the column-gap of [page.grid].
-}
data IndexStyle = IndexStyle
  { ixColumns :: !(Maybe Int),
    ixColumnGap :: !(Maybe Dim),
    -- | where the value of columns starts in style.toml, for G07044
    ixColumnsAt :: !Int
  }
  deriving stock (Eq, Show)

-- | The pages that get a hidden folio (golem-driver ADR 0021).
data HiddenFolioPages = HiddenUnnumbered | HiddenAll
  deriving stock (Eq, Show)

{- | [hidden-folio] (golem-driver ADR 0021): the page number in the gutter
of a PDF with crop marks.
-}
data HiddenFolio = HiddenFolio
  { hfEnabled :: !Bool,
    hfPages :: !HiddenFolioPages,
    -- | the size of the digits, absolute
    hfSize :: !Dim,
    -- | from the trim line of the gutter to the centre line of the column, absolute
    hfGutter :: !Dim,
    -- | whether gutter was written: G03029 is at gutter, or at size without it (golem-driver ADR 0041)
    hfGutterWritten :: !Bool
  }
  deriving stock (Eq, Show)

-- | Without [hidden-folio]: enabled, on the pages without a folio, 6pt, 1.5mm.
defaultHiddenFolio :: HiddenFolio
defaultHiddenFolio = HiddenFolio True HiddenUnnumbered (Abs (6 * 65536)) (Abs (mmToSp (3 % 2))) False

{- | Every error of reading [hidden-folio] is G03006: a dimension in zw, of
0 or less or unreadable, a value of pages outside the table and an
unknown key (golem-driver ADR 0021). A gutter less than half the size is
G03029, a check after reading ('hiddenFolioChecks', golem-driver ADR 0041).
-}
instance FromValue HiddenFolio where
  fromValue = parseTableFromValue $ do
    let d = defaultHiddenFolio
    enabled <- fromMaybe (hfEnabled d) <$> optKey "enabled"
    pages <-
      optKeyOf
        "pages"
        ( withValue $ \l -> \case
            "unnumbered" -> pure HiddenUnnumbered
            "all" -> pure HiddenAll
            v -> failAt l ("[hidden-folio] の pages に使えない値です: " <> T.unpack v <> "（unnumbered, all のどれか）")
        )
    let len k = optKeyOf k $ \v -> case v of
          Text' l t ->
            (l,) <$> case parseDim t of
              Just (Abs x) | x > 0 -> pure (Abs x)
              Just (Abs _) -> failAt l ("[hidden-folio] の " <> T.unpack k <> " は 0 より大きい寸法です: " <> T.unpack t)
              -- not relative to the size of the type, as the page size (golem-driver ADR 0021)
              Just (Zw _) -> failAt l ("[hidden-folio] の " <> T.unpack k <> " には zw を使えません")
              Nothing -> failAt l ("[hidden-folio] の " <> T.unpack k <> " の長さの書き方が不正です: " <> T.unpack t)
          _ -> failAt (valueAnn v) ("[hidden-folio] の " <> T.unpack k <> " は文字列で書きます")
    sizeAt <- len "size"
    gutterAt <- len "gutter"
    let size = maybe (hfSize d) snd sizeAt
        gutter = maybe (hfGutter d) snd gutterAt
    pure (HiddenFolio enabled (fromMaybe (hfPages d) pages) size gutter (isJust gutterAt))

{- | G03029 (golem-driver ADR 0041): the column of digits, half the size on
each side of its centre line, crosses the trim line of the gutter when
the gutter is less than half the size. Half the size stands for half the
advance of a digit, which the font decides and style.toml does not know.
The path of the value to fix (gutter, or size when gutter is not
written), the message with the values in mm, and the facts in sp.
-}
hiddenFolioChecks :: HiddenFolio -> [([Scope], Text, [(Text, Fact)])]
hiddenFolioChecks hf = case (hfSize hf, hfGutter hf) of
  (Abs size, Abs gutter)
    | 2 * gutter < size ->
        let -- the fewest hundredths of a mm whose sp, doubled, reach the size
            minGutter = until (\k -> 2 * mmToSp (k % 100) >= size) (+ 1) (max 0 (floor (spToMm size * 50) - 1))
            -- the most hundredths of a mm whose sp is within twice the gutter
            maxSize = until (\k -> k <= 0 || mmToSp (k % 100) <= 2 * gutter) (subtract 1) (ceiling (spToMm (2 * gutter) * 100) + 1)
            path = map ScopeKey ["hidden-folio", if hfGutterWritten hf then "gutter" else "size"]
            message =
              "[hidden-folio] の gutter（"
                <> mm2 (spToMm gutter)
                <> "）が size（"
                <> mm2 (spToMm size)
                <> "）の半分（"
                <> mm2 (spToMm size / 2)
                <> "）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（gutter を "
                <> mm2 (minGutter % 100)
                <> " 以上にするか、size を "
                <> mm2 (maxSize % 100)
                <> " 以下にします）"
         in [(path, message, [("gutter", FactInt gutter), ("size", FactInt size), ("min-gutter", FactInt (mmToSp (minGutter % 100))), ("max-size", FactInt (mmToSp (maxSize % 100)))])]
  _ -> []
  where
    spToMm sp = toRational sp * (254 % 10) / (72 * 65536)
    -- mm to two decimals, the third rounded half up
    mm2 :: Rational -> Text
    mm2 x =
      let c = floor (x * 100 + 1 % 2) :: Integer
          (i, f) = c `divMod` 100
       in T.pack (show i <> "." <> (if f < 10 then "0" else "") <> show f <> "mm")

-- | How a heading is shown in a running head (golem-driver ADR 0014, 0022).
data HeadForm = HeadShort | HeadNumbered | HeadNumber
  deriving stock (Eq, Show)

-- | Which heading of a page a running head takes: the first or the last.
data HeadPick = PickFirst | PickLast
  deriving stock (Eq, Show)

-- | What a slot of a running head format refers to (golem-driver ADR 0022).
data RunningRef
  = -- | a heading of a level
    RefHeading !Int !HeadForm !HeadPick
  | -- | a key of [metadata]: title, title_reading and so on
    RefMeta !Text
  | -- | a variable of the page's file, with its namespace when imported
    RefVar ![Text]
  deriving stock (Eq, Show)

-- | A piece of a line of a running head: text, or a slot (True with @?@).
data RunningPart
  = PartText !Text
  | PartRef !RunningRef !Bool
  deriving stock (Eq, Show)

{- | What a running head shows: lines, from the head to the foot of the
page, or nothing. The vocabulary of golem-driver ADR 0014 is read into
lines (golem-driver ADR 0022).
-}
data RunningContent
  = RunningLines !(NonEmpty [RunningPart])
  | RunningNone
  deriving stock (Eq, Show)

-- | The slots of a running head, with whether each has @?@.
runningRefs :: RunningContent -> [(RunningRef, Bool)]
runningRefs = \case
  RunningLines ls -> [(r, q) | l <- toList ls, PartRef r q <- l]
  RunningNone -> []

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
(golem-driver ADR 0014), as a format of one line (golem-driver ADR 0022).
-}
parseRunningContent :: Text -> Maybe RunningContent
parseRunningContent = \case
  "title" -> Just (oneRef (RefMeta "title"))
  "none" -> Just RunningNone
  t -> case T.splitOn "." t of
    ["heading", l, f] | f /= "number" -> oneRef <$> headingRef l f PickFirst
    ["heading", l, f, "last"] | f /= "number" -> oneRef <$> headingRef l f PickLast
    _ -> Nothing
  where
    oneRef r = RunningLines ([PartRef r False] :| [])

-- | @heading.<l>.<form>@ of a level of 1 or more.
headingRef :: Text -> Text -> HeadPick -> Maybe RunningRef
headingRef l f pick = do
  level <- if not (T.null l) && T.all isDigit l then Just (read (T.unpack l)) else Nothing
  form <- case f of
    "short" -> Just HeadShort
    "numbered" -> Just HeadNumbered
    "number" -> Just HeadNumber
    _ -> Nothing
  if level >= 1 then Just (RefHeading level form pick) else Nothing

-- | The keys of [metadata] a running head can show (golem-driver ADR 0022).
runningMetaKeys :: [Text]
runningMetaKeys = ["title", "title_reading", "edition", "publisher", "date", "language", "id"]

{- | One line of a running head format (golem-driver ADR 0022): text and
slots in braces, @{{@ and @}}@ for braces. 'Left' is the reason of G03014.
-}
parseRunningFormat :: Text -> Either Text [RunningPart]
parseRunningFormat t0
  | T.null t0 = Left "空の行があります"
  | T.any (== '\n') t0 = Left "行の中に改行があります。行は配列の要素で分けてください"
  | otherwise = merge <$> go t0
  where
    go t = case T.uncons t of
      Nothing -> Right []
      Just ('{', r)
        | Just r' <- T.stripPrefix "{" r -> (PartText "{" :) <$> go r'
        | otherwise ->
            let (name, rest) = T.break (`elem` ['{', '}']) r
             in case T.uncons rest of
                  Just ('}', r') -> (:) <$> slot name <*> go r'
                  _ -> Left "閉じていない { があります"
      Just ('}', r)
        | Just r' <- T.stripPrefix "}" r -> (PartText "}" :) <$> go r'
        | otherwise -> Left "対にならない } があります。文字の } は }} と書きます"
      Just _ ->
        let (txt, rest) = T.break (`elem` ['{', '}']) t
         in (PartText txt :) <$> go rest
    slot name0 =
      let (name, optional) = maybe (name0, False) (,True) (T.stripSuffix "?" name0)
          unknown = Left ("未知の差し込みです: {" <> name0 <> "}")
          ref r = Right (PartRef r optional)
       in if T.null name0
            then Left "空の差し込み {} があります"
            else case T.splitOn "." name of
              ["heading", l, f] -> maybe unknown ref (headingRef l f PickFirst)
              ["heading", l, f, "last"] -> maybe unknown ref (headingRef l f PickLast)
              ["meta", "creators"] -> Left "meta.creators は配列なので、柱に書けません。@set で文字列の変数を作ってください"
              ["meta", k] | k `elem` runningMetaKeys -> ref (RefMeta k)
              ("set" : ns@(_ : _)) | length ns <= 2 && all varName ns -> ref (RefVar ns)
              _ -> unknown
    varName n = case T.uncons n of
      Just (c, r) -> (isAsciiLetter c || c == '_') && T.all (\x -> isAsciiLetter x || isDigit x || x == '_') r
      Nothing -> False
    isAsciiLetter c = isAsciiLower c || isAsciiUpper c
    merge = \case
      PartText a : PartText b : r -> merge (PartText (a <> b) : r)
      x : r -> x : merge r
      [] -> []

{- | A rule of style.toml (golem-driver ADR 0024): the same keys and
checks wherever a rule is written; the user decides whether the length
is required, how the spaces are measured and the size zw is resolved by.
The colour and the line style are the same for every user (golem-driver
ADR 0028).
-}
data RuleSpec = RuleSpec
  { -- | length, greater than 0
    rsLength :: !(Maybe Dim),
    -- | weight in sp, greater than 0; 0.3pt by default
    rsWeight :: !Sp,
    -- | the space before the rule (above it, right of it in vertical text), not negative
    rsSpaceBefore :: !(Maybe Dim),
    -- | the space after the rule (below it, left of it in vertical text), not negative
    rsSpaceAfter :: !(Maybe Dim),
    -- | the swatch of the rule; none draws it without setting a colour
    rsColor :: !(Maybe Text),
    -- | the line style, its lengths resolved from the weight
    rsStyle :: !RuleStyle,
    {- | from the start of the line of the column to the start of the rule;
    negative out of the column (golem-driver ADR 0027), paragraph and
    heading rules only
    -} rsStartIndent :: !Dim,
    -- | from the end of the rule to the end of the line of the column
    rsEndIndent :: !(Maybe Dim),
    -- | whether a rule at the edge of a column stays in it
    rsKeepInColumn :: !Bool
  }
  deriving stock (Eq, Show)

-- | The line style of a rule (golem-driver ADR 0028); lengths in sp.
data RuleStyle
  = RuleSolid
  | -- | the proportions, line, gap, line, ... from the before side
    RuleMulti ![Int]
  | -- | dash, gap
    RuleDashed !Sp !Sp
  | -- | gap
    RuleDotted !Sp
  | -- | gap
    RuleJapaneseDots !Sp
  | RuleWavy
  deriving stock (Eq, Show)

{- | The values of the key style and the proportions of the styles of
several lines (golem-driver ADR 0028), in the order of the table of the ADR.
-}
ruleStyleNames :: [(Text, Maybe [Int])]
ruleStyleNames =
  [ ("solid", Nothing),
    ("thin-thin", Just [1, 1, 1]),
    ("thick-thick", Just [2, 1, 2]),
    ("thick-thin", Just [2, 1, 1]),
    ("thin-thick", Just [1, 1, 2]),
    ("thick-thin-thick", Just [2, 1, 1, 1, 2]),
    ("thin-thick-thin", Just [1, 1, 2, 1, 1]),
    ("triple", Just [1, 1, 1, 1, 1]),
    ("dashed", Nothing),
    ("dotted", Nothing),
    ("japanese-dots", Nothing),
    ("wavy", Nothing)
  ]

{- | Reads a rule spec from its table; every error is at the value or,
for an unknown key, at the table (G03006 by the path of its user). The
swatch of color is checked by the user of the style (G03013).
-}
instance FromValue RuleSpec where
  fromValue = parseTableFromValue $ do
    len <- optKeyOf "length" $ ruleDim "length" $ \l d ->
      if positiveDim d then pure d else failAt l "罫線の length は 0 より大きい寸法です"
    weight <- optKeyOf "weight" $ ruleDim "weight" $ \l -> \case
      -- the weight does not follow the size of the type
      Zw _ -> failAt l "罫線の weight には zw を使えません"
      Abs x
        | x > 0 -> pure x
        | otherwise -> failAt l "罫線の weight は 0 より大きい寸法です"
    let space key = optKeyOf key $ ruleDim key $ \l d ->
          if negativeDim d then failAt l (T.unpack ("罫線の " <> key <> " は 0 以上の寸法です")) else pure d
        -- a length of a dash or a gap: absolute, greater than 0 (golem-driver ADR 0028)
        dashLength key = optKeyOf key $ ruleDim key $ \l -> \case
          Zw _ -> failAt l (T.unpack ("罫線の " <> key <> " には zw を使えません"))
          Abs x
            | x > 0 -> pure (l, x)
            | otherwise -> failAt l (T.unpack ("罫線の " <> key <> " は 0 より大きい寸法です"))
    before <- space "space-before"
    after <- space "space-after"
    color <- optKeyOf "color" $ \case
      Text' _ t -> pure t
      v -> failAt (valueAnn v) "罫線の color はスウォッチの名前を文字列で書きます"
    styleName <- optKeyOf "style" $ \case
      Text' l t
        | Just multi <- lookup t ruleStyleNames -> pure (l, t, multi)
        | otherwise -> failAt l (T.unpack ("罫線の style に使えない値です: " <> t <> "（" <> T.intercalate ", " (map fst ruleStyleNames) <> " のどれか）"))
      v -> failAt (valueAnn v) "罫線の style は \"solid\" のように文字列で書きます"
    dash <- dashLength "dash"
    gap <- dashLength "gap"
    -- the place of a paragraph or heading rule (golem-driver ADR 0027); negative is out of the column
    let indent key = optKeyOf key $ ruleDim key (curry pure)
    startIndent <- fmap snd <$> indent "start-indent"
    endIndentAt <- indent "end-indent"
    let endIndent = snd <$> endIndentAt
    keepIn <- optKey "keep-in-column"
    case (len, endIndentAt) of
      (Just _, Just (l, _)) -> failTableAt l "罫線の length と end-indent は一緒に書けません"
      _ -> pure ()
    let w = fromMaybe defaultRuleWeight weight
        name = maybe "solid" (\(_, t, _) -> t) styleName
        -- a key without effect on the style is an error (golem-driver ADR 0028)
        refuse key = \case
          Just (l, _) -> liftMatcher (failAt l (T.unpack ("罫線の " <> key <> " は style が " <> name <> " のときには書けません")))
          Nothing -> pure ()
        orDefault x = maybe x snd
    style <- case styleName of
      Just (_, _, Just multi) -> refuse "dash" dash >> refuse "gap" gap >> pure (RuleMulti multi)
      _ -> case name of
        "dashed" -> pure (RuleDashed (orDefault (3 * w) dash) (orDefault (2 * w) gap))
        "dotted" -> refuse "dash" dash >> pure (RuleDotted (orDefault (2 * w) gap))
        "japanese-dots" -> refuse "dash" dash >> pure (RuleJapaneseDots (orDefault w gap))
        "wavy" -> refuse "dash" dash >> refuse "gap" gap >> pure RuleWavy
        _ -> refuse "dash" dash >> refuse "gap" gap >> pure RuleSolid
    pure (RuleSpec len w before after color style (fromMaybe (Zw 0) startIndent) endIndent (fromMaybe True keepIn))
    where
      ruleDim key check v = case v of
        Text' l t -> maybe (failAt l (T.unpack ("罫線の " <> key <> " を寸法として読めません: " <> t))) (check l) (parseSignedDim t)
        _ -> failAt (valueAnn v) (T.unpack ("罫線の " <> key <> " は \"0.3pt\" のように文字列で書きます"))
      positiveDim = \case
        Abs x -> x > 0
        Zw r -> r > 0

-- | 0.3pt.
defaultRuleWeight :: Sp
defaultRuleWeight = round (3 / 10 * 65536 :: Rational)

-- | A TOML document that is one rule spec, read by its 'FromValue'; errors are G03006.
parseRuleSpec :: FileId -> Text -> Either [Diagnostic] RuleSpec
parseRuleSpec = decodeStrictBy "G03006" (const "G03006")

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
    -- | [notes] placement: the foot of the page or the end of the chapter, in the PDF (golem-driver ADR 0026)
    stNotesPlacement :: !NotesPlacement,
    -- | [notes] numbering: the range over which notes are numbered (golem-driver ADR 0018)
    stNotesNumbering :: !NoteNumbering,
    -- | [notes.rule]: the rule before footnotes in the PDF, its length always there (golem-driver ADR 0024)
    stNotesRule :: !(Maybe RuleSpec),
    -- | [notes] mark-size: the size of note marks in the PDF (golem-driver ADR 0025)
    stNotesMarkSize :: !Dim,
    -- | [notes] mark-format: the text of note marks in the PDF, {n} the number (golem-driver ADR 0025)
    stNotesMarkFormat :: !Text,
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
    stAkiSets :: !(Map Text AkiSetDef),
    -- | [index]: the columns of the index (docs/adr ADR 0025)
    stIndex :: !(Maybe IndexStyle),
    -- | [code] and [code.colors] (golem-driver ADR 0023)
    stCode :: !CodeStyle,
    -- | [hidden-folio] (golem-driver ADR 0021)
    stHiddenFolio :: !HiddenFolio
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
      stNotesPlacement = PlaceFoot,
      stNotesNumbering = NumberPerChapter,
      stNotesRule = Nothing,
      stNotesMarkSize = Zw (1 % 2),
      stNotesMarkFormat = "*{n}",
      stSidenotes = Nothing,
      stFigureNumber = "図{chapter}-{n}",
      stWrapGap = Zw 1,
      stIntent = Nothing,
      stSwatches = Map.empty,
      stMasters = Map.empty,
      stTocLeader = "dots",
      stLists = defaultListStyle,
      stAkiSets = Map.empty,
      stIndex = Nothing,
      stCode = defaultCodeStyle,
      stHiddenFolio = defaultHiddenFolio
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
    _ -> failAt (valueAnn v) "判型の名前か { width = ..., height = ... } を書きます"
    where
      side l = \case
        Abs x
          | x > 0 -> pure x
          | otherwise -> failAt l "判型の幅と高さは 0 より大きい寸法です"
        -- the page size does not depend on the size of the type, as the bleed
        Zw _ -> failAt l "判型には zw を使えません"

newtype DimV = DimV Dim

instance FromValue DimV where
  fromValue (Text' l t) = case parseDim t of
    Just d -> pure (DimV d)
    Nothing
      -- the names of aki amounts and percentages are only for aki (docs/adr ADR 0019): G03020
      | Just _ <- parseAki t -> failAt l (T.unpack (akiError ("アキの量の名前と百分率は、アキの量を書く欄でだけ使えます。寸法は 0.5zw や 2mm のように書きます: " <> t)))
      | otherwise -> failAt l ("長さの書き方が不正です: " <> T.unpack t <> "（13Q や 20mm のように書きます）")
  fromValue v = failAt (valueAnn v) "長さは文字列で書きます"

{- | 'fromValue' and then a check of what it read, which fails at the
value (golem-project ADR 0008).
-}
withValue :: (FromValue a) => (l -> a -> Matcher l b) -> Value' l -> Matcher l b
withValue k v = fromValue v >>= k (valueAnn v)

-- | An optional key with the position of its value.
optKeyAt :: (FromValue a) => Text -> ParseTable l (Maybe (l, a))
optKeyAt k = optKeyOf k (\v -> (valueAnn v,) <$> fromValue v)

-- | A required key with the position of its value.
reqKeyAt :: (FromValue a) => Text -> ParseTable l (l, a)
reqKeyAt k = reqKeyOf k (\v -> (valueAnn v,) <$> fromValue v)

-- | 'optKeyAt' of a string.
textAt :: Text -> ParseTable l (Maybe (l, Text))
textAt = optKeyAt

-- | The position of the value of a key of a table; the table's own without it.
keyPosition :: Value' l -> Text -> l
keyPosition v k = case v of
  Table' l (MkTable t) -> maybe l (valueAnn . snd) (Map.lookup k t)
  _ -> valueAnn v

-- | The message of G03020 (docs/adr ADR 0019).
akiError :: Text -> Text
akiError why = "アキの量の指定が正しくありません: " <> why

-- | An aki amount of a rule.
newtype AkiV = AkiV Rational

instance FromValue AkiV where
  fromValue (Text' l t) = maybe (failAt l (T.unpack (akiError ("アキの量として読めません: " <> t)))) (pure . AkiV) (parseAki t)
  fromValue v = failAt (valueAnn v) (T.unpack (akiError "アキの量は \"四分\" や \"25%\" のように文字列で書きます"))

-- | The classes of one side of a rule: a name or an array of names.
newtype ClassesV = ClassesV [Text]

instance FromValue ClassesV where
  fromValue (Text' _ t) = pure (ClassesV [t])
  fromValue v@(List' _ _) = ClassesV <$> fromValue v
  fromValue v = failAt (valueAnn v) (T.unpack (akiError "クラスは名前の文字列か、その配列で書きます"))

instance FromValue AkiRuleDef where
  fromValue = parseTableFromValue $ do
    (lb, ClassesV before) <- reqKeyAt "before"
    (la, ClassesV after) <- reqKeyAt "after"
    (lo, AkiV o) <- reqKeyAt "optimum"
    mn <- optKeyAt "minimum"
    mx <- optKeyAt "maximum"
    let n = maybe o (\(_, AkiV x) -> x) mn
        m = maybe o (\(_, AkiV x) -> x) mx
        -- each error is at the value it asks to fix (golem-project ADR 0008)
        bad l why = failTableAt l (T.unpack (akiError why))
        known = (`elem` akiClassNames)
    case [c | c <- before, not (known c || c `elem` ["line-start", "paragraph-start"])] of
      (c : _)
        | c == "line-end" -> bad lb "line-end は after にだけ書けます"
        | otherwise -> bad lb ("未知のクラスの名前です: " <> c)
      [] -> pure ()
    case [c | c <- after, not (known c || c == "line-end")] of
      (c : _)
        | c `elem` ["line-start", "paragraph-start"] -> bad la (c <> " は before にだけ書けます")
        | otherwise -> bad la ("未知のクラスの名前です: " <> c)
      [] -> pure ()
    when (null before || null after) $ bad (if null before then lb else la) "before と after には一つ以上のクラスを書きます"
    unless (n <= o && o <= m) $
      bad (if n > o then maybe lo fst mn else maybe lo fst mx) "minimum、optimum、maximum の順に小さくない値を書きます"
    pure (AkiRuleDef before after n o m)

instance FromValue AkiSetDef where
  fromValue = parseTableFromValue (AkiSetDef <$> optKey "based-on" <*> (fromMaybe [] <$> optKey "rules"))

unDim :: Maybe DimV -> Maybe Dim
unDim = fmap (\(DimV d) -> d)

dimKey :: Text -> ParseTable l (Maybe Dim)
dimKey k = unDim <$> optKey k

reqDim :: Text -> ParseTable l Dim
reqDim k = (\(DimV d) -> d) <$> reqKey k

{- | The names of the shapes of kenten, in [kenten shape=...] and in
[composition] kenten (golem-driver ADR 0019): those of CSS
text-emphasis-style.
-}
kentenShapeNames :: [Text]
kentenShapeNames = ["sesame", "open-sesame", "dot", "open-dot", "circle", "open-circle", "double-circle", "open-double-circle", "triangle", "open-triangle"]

enumKey :: Text -> [Text] -> ParseTable l (Maybe Text)
enumKey k allowed =
  optKeyOf k $ withValue $ \l x ->
    if x `notElem` allowed
      then failAt l (T.unpack (k <> " に使えない値です: " <> x <> "（" <> T.intercalate ", " allowed <> " のどれか）"))
      else pure x

instance FromValue Grid where
  fromValue = parseTableFromValue $ do
    fs <- reqDim "font-size"
    ch <- reqKey "characters"
    ls <- reqKey "lines"
    lp <- reqDim "line-pitch"
    colsAt <- optKeyAt "columns"
    let cols = maybe 1 snd colsAt
    gap <- dimKey "column-gap"
    pos <- reqKey "position"
    case colsAt of
      Just (l, c) | c > 1 && isNothing gap -> failTableAt l "columns が 2 以上のときは column-gap が要ります"
      _ -> pure ()
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
      fmap (fromMaybe 0) . optKeyOf "bleed" . withValue $ \l -> \case
        DimV (Abs s) -> pure s
        -- the bleed does not depend on the size of the type (golem-pdf ADR 0004)
        DimV (Zw _) -> failAt l "塗り足しには zw を使えません"
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
    -- a swatch or false (golem-driver ADR 0029)
    bg <-
      optKeyOf "background" $ \v -> case v of
        Bool' _ False -> pure Nothing
        Bool' _ True -> failAt (valueAnn v) "background にはスウォッチの名前か false を書きます"
        _ -> Just <$> fromValue v
    -- a negative padding is read and reported by the checks (golem-driver ADR 0029)
    pad' <- signedDimKey "padding" "（0.25zw や 1mm のように書きます）"
    pure (CharStyleDef b f s c sb si k t p bs bg pad')

{- | kerning, tracking, proportional-metrics and baseline-shift
(docs/adr/0020). Every error is under its key, which makes it G03021.
-}
featureKeysOf :: ParseTable l (Maybe Kerning, Maybe Int, Maybe Bool, Maybe Dim)
featureKeysOf = do
  let wrong l key v = failAt l (T.unpack (key <> " の値が正しくありません: " <> v))
  k <-
    optKeyOf "kerning" $
      withValue $ \l -> \case
        "metrics" -> pure KernMetrics
        "japanese-equal-width" -> pure KernJapaneseEqualWidth
        "none" -> pure KernNone
        "optical" -> pure KernOptical
        v -> wrong l "kerning" v
  t <-
    optKeyOf "tracking" $
      withValue $ \l n ->
        if n < -1000 || n > 10000 then wrong l "tracking" (T.pack (show n) <> "（-1000 から 10000 までです）") else pure n
  p <- optKey "proportional-metrics"
  bs <- optKeyOf "baseline-shift" (withValue (\l v -> maybe (wrong l "baseline-shift" v) pure (parseSignedDim v)))
  pure (k, t, p, bs)

-- | The keys of 'featureKeysOf': their errors are G03021 (docs/adr/0020).
featureKeys :: [Text]
featureKeys = ["kerning", "tracking", "proportional-metrics", "baseline-shift"]

instance FromValue ParaStyleDef where
  fromValue = parseTableFromValue $ do
    b <- optKey "based-on"
    f <- optKey "font"
    s <- dimKey "size"
    lb <- enumKey "line-breaks" ["join", "keep"]
    sb <- optKeyOf "space-between" (withValue (\l x -> if x < 0 then failAt l "space-between は 0 以上です" else pure x))
    ind <- dimKey "indent"
    fli' <- signedDimKey "first-line-indent" "（1zw や -1zw のように書きます）"
    rs <- optKey "regex-styles"
    aki <- optKey "aki-set"
    (k, t, p, bs) <- featureKeysOf
    bg <- optKey "background"
    -- a negative padding is read and reported by the checks (golem-driver ADR 0017)
    pad' <- signedDimKey "padding" "（0.5zw や 1mm のように書きます）"
    -- the border of code; zw is reported by the checks (golem-driver ADR 0023)
    border <- optKey "border"
    bw <- dimKey "border-width"
    rb <- optKeyOf "rule-before" ruleOrFalse
    ra <- optKeyOf "rule-after" ruleOrFalse
    pure (ParaStyleDef b f s ((\x -> if x == "keep" then KeepLines else JoinLines) <$> lb) sb ind fli' rs aki k t p bs bg pad' border bw rb ra)

{- | A dimension that may be negative, read in its key so that an error is
at the value and names the key (golem-project ADR 0008).
-}
signedDimKey :: Text -> String -> ParseTable l (Maybe Dim)
signedDimKey k example = optKeyOf k $ withValue $ \l v ->
  maybe (failAt l ("長さの書き方が不正です: " <> T.unpack v <> example)) pure (parseSignedDim v)

{- | A paragraph or heading rule (golem-driver ADR 0027): a rule spec, or
false for none; true is an error.
-}
ruleOrFalse :: Value' l -> Matcher l (Maybe RuleSpec)
ruleOrFalse = \case
  Bool' _ False -> pure Nothing
  Bool' l True -> failAt l "罫線には表か false を書きます。true は書けません"
  v -> Just <$> fromValue v

instance FromValue RegexStyleDef where
  fromValue = parseTableFromValue (RegexStyleDef <$> reqKey "pattern" <*> reqKey "style")

instance FromValue HeadingStyle where
  fromValue = parseTableFromValue $ do
    f <- optKey "font"
    s <- dimKey "size"
    n <- optKey "number"
    pb <- enumKey "page-break" ["recto", "any"]
    ls <- optKeyOf "lines" $ withValue $ \at l -> if l < (1 :: Int) then failAt at ("lines は 1 以上の整数です: " <> show l) else pure l
    -- retired (golem-driver ADR 0014): G03019
    pickKey
      [ Key "running-head" (\v -> failAt (valueAnn v) "[headings.<l>] の running-head は廃止しました。柱に使う見出しは [masters.<名前>] の running-head の content で指定してください"),
        Else (pure ())
      ]
    rb <- optKeyOf "rule-before" ruleOrFalse
    ra <- optKeyOf "rule-after" ruleOrFalse
    pure (HeadingStyle f s n (pb == Just "recto") ls (join rb) (join ra))

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
    kt <- enumKey "kenten" kentenShapeNames
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
    f <- textAt "font"
    s <- textAt "size"
    case fmap fst f <|> fmap fst s of
      Just l -> failTableAt l "[sidenotes] の font と size は廃止しました。[paragraph-styles.sidenote] の font と size に書き換えます"
      Nothing -> pure ()
    m <- enumKey "marker" ["number", "symbol", "none"]
    pure (SidenoteStyle w g (fromMaybe "number" m))

-- | The positions of a running head and a folio (golem-driver ADR 0014).
masterPositions :: [Text]
masterPositions = ["top-outside", "top-inside", "top-center", "bottom-outside", "bottom-inside", "bottom-center"]

{- | A position of a master page; an unknown one is an error at its value,
which makes it G03018 (golem-driver ADR 0016).
-}
newtype MasterPosition = MasterPosition Text

instance FromValue MasterPosition where
  fromValue v = case v of
    Text' l p
      | p `elem` masterPositions -> pure (MasterPosition p)
      | otherwise -> failAt l ("未知の位置です: " <> T.unpack p)
    _ -> failAt (valueAnn v) "top-outside のような位置を書きます"

reqPosition :: ParseTable l Text
reqPosition = (\(MasterPosition p) -> p) <$> reqKey "position"

data PosContent = PosContent Text Text

instance FromValue PosContent where
  fromValue = parseTableFromValue $ do
    p <- reqPosition
    c <- optKey "content"
    f <- optKey "format"
    pure (PosContent p (fromMaybe "" (c <> f)))

-- | The message of G03014 (golem-driver ADR 0014).
runningContentMessage :: Text -> String
runningContentMessage v =
  T.unpack ("柱の内容が正しくありません: " <> v <> "。heading.<階層>.short か heading.<階層>.numbered（末尾に .last を付けられます）、title、none のどれかを、content に一つ、または even と odd の両方に書いてください")

-- | The message of G03014 for a format (golem-driver ADR 0022).
runningFormatMessage :: Text -> String
runningFormatMessage why = T.unpack ("柱の書式が正しくありません: " <> why)

{- | A content of a running head: a word of the vocabulary as a string
(golem-driver ADR 0014), or a format as an array of lines (golem-driver
ADR 0022); with what was written, for the message of a wrong combination.
A string with @{@ is a format written as a string: G03014 that points to
arrays, so that a misspelt word never shows as fixed text.
-}
runningContentOf :: Value' l -> Matcher l (Text, RunningContent)
runningContentOf v = case v of
  Text' l t
    | T.any (== '{') t -> failAt l (runningFormatMessage ("書式は文字列の配列で書いてください（[\"" <> t <> "\"]）"))
    | otherwise -> maybe (failAt l (runningContentMessage t)) (pure . ("\"" <> t <> "\"",)) (parseRunningContent t)
  List' l xs -> do
    ls <- traverse (line l) xs
    case ls of
      [] -> failAt l (runningFormatMessage "空の配列です。行を一つ以上書いてください")
      (x : rest) -> pure ("[…]", RunningLines (x :| rest))
  _ -> failAt (valueAnn v) (runningContentMessage "（文字列でも配列でもない値）")
  where
    line l = \case
      Text' _ t -> either (failAt l . runningFormatMessage) pure (parseRunningFormat t)
      _ -> failAt l (runningFormatMessage "配列の要素は文字列です")

{- | A running head: @position@, and @content@ or both @even@ and @odd@.
Errors of the contents are reported under their key, which makes them
G03014.
-}
instance FromValue RunningHeadDef where
  fromValue v = flip parseTableFromValue v $ do
    p <- reqPosition
    c <- optKeyOf "content" runningContentOf
    e <- optKeyOf "even" runningContentOf
    o <- optKeyOf "odd" runningContentOf
    let written = T.intercalate ", " [k <> " = " <> t | (k, Just (t, _)) <- [("content", c), ("even", e), ("odd", o)]]
        -- at the value of the key, or at the running head when the key is not written (golem-project ADR 0008)
        wrong k = liftMatcher (inKey k (failAt (keyPosition v k) (runningContentMessage (if T.null written then "（なし）" else written))))
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
    reqKeyOf "cmyk" $ withValue $ \l cs -> case cs of
      [c, m, y, k] | all (\x -> x >= 0 && x <= 100) cs -> pure (Swatch (c, m, y, k))
      _ -> failAt l "cmyk は 0 から 100 までの整数四つです"

newtype Numbers = Numbers (Maybe Text)

instance FromValue Numbers where
  fromValue = parseTableFromValue (Numbers <$> enumKey "vertical" ["kanji", "kanji-digits", "tcy", "auto", "auto-digits"])

-- | The retired [emphasis] (docs/adr ADR 0005): an error that names its replacement.
data EmphasisV

instance FromValue EmphasisV where
  fromValue v =
    failAt
      (valueAnn v)
      "[emphasis] は廃止しました。strong = \"italic\" は [character-styles.strong] の based-on = \"italic\" に、bold-font は [character-styles.bold] の font に、italic-font は [character-styles.italic] の font に書き換えます"

-- | Where the notes of the PDF are set (golem-driver ADR 0026).
data NotesPlacement = PlaceFoot | PlaceChapterEnd
  deriving stock (Eq, Show)

data Notes = Notes (Maybe Text) (Maybe NoteNumbering) (Maybe RuleSpec) (Maybe Dim) (Maybe Text)

instance FromValue Notes where
  fromValue =
    parseTableFromValue
      ( Notes
          <$> enumKey "placement" ["page-foot", "chapter-end"]
          <*> (fmap numbering <$> enumKey "numbering" ["chapter", "file", "book"])
          <*> optKeyOf "rule" noteRule
          <*> optKeyOf "mark-size" (withValue (\l (DimV d) -> markSize l d))
          <*> optKeyOf "mark-format" (withValue markFormat)
      )
    where
      {- the size of note marks (golem-driver ADR 0025): above 0, and at
      most the size of the text in zw -}
      markSize l d = case d of
        Abs n | n > 0 -> pure d
        Zw r | r > 0 && r <= 1 -> pure d
        _ -> failAt l "[notes] の mark-size は 0 より大きい寸法で、zw では 1 以下です"
      -- the format of note marks: {n} exactly once (golem-driver ADR 0025)
      markFormat l f
        | T.count "{n}" f == 1 = pure f
        | otherwise = failAt l ("[notes] の mark-format には {n} をちょうど一つ書きます: " <> T.unpack f)
      {- the rule before footnotes (golem-driver ADR 0024): length is
      required; a space not written is 0 when the other is written -}
      noteRule v = do
        -- the place of a rule in its column is for paragraphs and headings (golem-driver ADR 0027)
        case v of
          Table' l (MkTable m)
            | (k : _) <- filter (`Map.member` m) ["start-indent", "end-indent", "keep-in-column"] ->
                failAt l (T.unpack ("[notes.rule] には " <> k <> " を書けません。段落スタイルと見出しの罫線だけのキーです"))
          _ -> pure ()
        r <- fromValue v
        when (isNothing (rsLength r)) $ failAt (valueAnn v) "[notes.rule] には length が要ります"
        pure $ case (rsSpaceBefore r, rsSpaceAfter r) of
          (Nothing, Nothing) -> r
          (b, a) -> r {rsSpaceBefore = Just (fromMaybe (Abs 0) b), rsSpaceAfter = Just (fromMaybe (Abs 0) a)}
      -- the range over which notes are numbered (golem-driver ADR 0018)
      numbering = \case
        "file" -> NumberPerFile
        "book" -> NumberPerBook
        _ -> NumberPerChapter

-- | [code] (golem-driver ADR 0023): an unknown key or kind is G03006.
newtype CodeSec = CodeSec CodeStyle

instance FromValue CodeSec where
  fromValue = parseTableFromValue $ do
    let d = defaultCodeStyle
    number <- optKey "number"
    ln <- optKey "line-numbers"
    lnc <- optKey "line-number-color"
    hl <- optKey "highlight"
    added <- optKey "added"
    removed <- optKey "removed"
    wm <- optKey "wrap-mark"
    cont <- optKey "continued"
    colors <-
      fmap (fromMaybe Map.empty) . optKeyOf "colors" $ \v -> do
        cs <- fromValue v
        case filter (`notElem` codeTokenKinds) (Map.keys cs) of
          (k : _) -> inKey k (failAt (keyPosition v k) (T.unpack ("[code.colors] に書けない字句の種類です: " <> k <> "。" <> T.intercalate "、" codeTokenKinds <> " を書けます")))
          [] -> pure cs
    pure (CodeSec (CodeStyle (fromMaybe (cdNumber d) number) (fromMaybe False ln) lnc hl added removed (fromMaybe "" wm) (fromMaybe "" cont) colors))

data Figures = Figures (Maybe Text) (Maybe Dim)

instance FromValue Figures where
  fromValue = parseTableFromValue (Figures <$> optKey "number" <*> dimKey "wrap-gap")

-- | The retired [verse] (docs/adr ADR 0005, 0006): an error that names its replacement.
data VerseV

instance FromValue VerseV where
  fromValue v =
    failAt
      (valueAnn v)
      "[verse] は廃止しました。indent = I と hang = H は [paragraph-styles.verse] の indent = I + H と first-line-indent = -H に、stanza-gap は [paragraph-styles.verse] の space-between に書き換えます"

{- | [lists] (golem-driver ADR 0013): every error names its key; they are
G03022 by their path.
-}
newtype ListsSec = ListsSec ListStyle

instance FromValue ListsSec where
  fromValue = parseTableFromValue $ do
    bullets <- optKeyAt "bullets"
    numbers <- optKeyAt "numbers"
    gap <- textAt "gap"
    -- each error is at the value of its key (golem-project ADR 0008)
    let bad l key why = failTableAt l (T.unpack ("[lists] の " <> key <> " が正しくありません: " <> why))
        nonEmpty key = \case
          Nothing -> pure Nothing
          Just (l, []) -> bad l key "空の配列です"
          Just (l, x : rest)
            | any T.null (x : rest) -> bad l key "空の文字列があります"
            | otherwise -> pure (Just (l, x :| rest))
    bs <- fmap snd <$> nonEmpty "bullets" bullets
    ns <- nonEmpty "numbers" numbers
    fmts <- traverse (\(l, fs) -> traverse (\f -> either (\why -> bad l "numbers" (why <> ": " <> f)) pure (parseNumberFormat f)) fs) ns
    g <- case gap of
      Nothing -> pure Nothing
      Just (l, t) -> case parseSignedDim t of
        Nothing -> bad l "gap" ("寸法として読めません: " <> t)
        Just d
          | negativeDim d -> bad l "gap" ("負の寸法です: " <> t)
          | otherwise -> pure (Just d)
    pure (ListsSec (ListStyle (fromMaybe (lsBullets defaultListStyle) bs) fmts g))

{- | [index] (docs/adr ADR 0025): every error is at its value, G03025 by
its path. The position of columns is filled in by 'parseStyle'.
-}
newtype IndexSec = IndexSec IndexStyle

instance FromValue IndexSec where
  fromValue = parseTableFromValue $ do
    cs <- optKeyOf "columns" $ \v -> case v of
      Integer' _ n | n >= 1 && n <= toInteger (maxBound :: Int) -> pure (fromInteger n)
      _ -> failAt (valueAnn v) "[index] の columns は 1 以上の整数です"
    gap <- optKeyOf "column-gap" $ \v -> case v of
      Text' _ t | Just d <- parseSignedDim t, not (negativeDim d) -> pure d
      _ -> failAt (valueAnn v) "[index] の column-gap が正しくありません"
    pure (IndexSec (IndexStyle cs gap 0))

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
    hs <-
      fmap (fromMaybe []) . optKeyOf "headings" $ \v -> do
        (headings :: Map Text HeadingStyle) <- fromValue v
        traverse (headingLevel v) (Map.toList headings)
    comp <- fromMaybe defaultComposition <$> optKey "composition"
    Numbers nv <- fromMaybe (Numbers Nothing) <$> optKey "numbers"
    -- the value of a retired table fails with how to rewrite it
    (_ :: Maybe EmphasisV) <- optKey "emphasis"
    Notes np nn nr nms nmf <- fromMaybe (Notes Nothing Nothing Nothing Nothing Nothing) <$> optKey "notes"
    side <- optKey "sidenotes"
    Figures fnum fgap <- fromMaybe (Figures Nothing Nothing) <$> optKey "figures"
    ColorSec intent swatches <- fromMaybe (ColorSec Nothing Map.empty) <$> optKey "color"
    masters <- fromMaybe Map.empty <$> optKey "masters"
    (_ :: Maybe VerseV) <- optKey "verse"
    TocSec leader <- fromMaybe (TocSec Nothing) <$> optKey "toc"
    ListsSec lists <- fromMaybe (ListsSec defaultListStyle) <$> optKey "lists"
    -- the built-in sets cannot be defined again (docs/adr ADR 0019); the error is at the set
    akiSets <-
      fmap (fromMaybe Map.empty) . optKeyOf "aki-sets" $ \v -> do
        sets <- fromValue v
        case filter (`elem` builtinAkiSetNames) (Map.keys sets) of
          (n : _) -> inKey n (failAt (keyPosition v n) (T.unpack (akiError ("組み込みのアキ量のセットと同じ名前です。based-on で引き継いだ別の名前のセットを作ります: " <> n))))
          [] -> pure sets
    index <- fmap (\(IndexSec ix) -> ix) <$> optKey "index"
    CodeSec code <- fromMaybe (CodeSec defaultCodeStyle) <$> optKey "code"
    hidden <- fromMaybe defaultHiddenFolio <$> optKey "hidden-folio"
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
          stNotesPlacement = maybe (stNotesPlacement d) (\p -> if p == "chapter-end" then PlaceChapterEnd else PlaceFoot) np,
          stNotesNumbering = fromMaybe (stNotesNumbering d) nn,
          stNotesRule = nr,
          stNotesMarkSize = fromMaybe (stNotesMarkSize d) nms,
          stNotesMarkFormat = fromMaybe (stNotesMarkFormat d) nmf,
          stSidenotes = side,
          stFigureNumber = fromMaybe (stFigureNumber d) fnum,
          stWrapGap = fromMaybe (stWrapGap d) fgap,
          stIntent = T.unpack <$> intent,
          stSwatches = swatches,
          stMasters = masters,
          stTocLeader = fromMaybe (stTocLeader d) leader,
          stLists = lists,
          stAkiSets = akiSets,
          stIndex = index,
          stCode = code,
          stHiddenFolio = hidden
        }
    where
      headingLevel v (k, h) = case k of
        "1" -> pure (1, h)
        "2" -> pure (2, h)
        "3" -> pure (3, h)
        _ -> inKey k (failAt (keyPosition v k) ("見出しの段は 1、2、3 のどれかです: " <> T.unpack k))

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

{- | The position of the value at a path of a TOML table; without one,
that of the table the path ends in (golem-project ADR 0008).
-}
checkPosition :: Table' Position -> [Scope] -> Maybe Position
checkPosition top path = valueAt path <|> (case reverse path of _ : parent@(_ : _) -> valueAt (reverse parent); _ -> Nothing)
  where
    valueAt = fmap valueAnn . go (Table' (Position 0 1 1) top)
    go v = \case
      [] -> Just v
      ScopeKey k : rest | Table' _ (MkTable t) <- v -> Map.lookup k t >>= \(_, x) -> go x rest
      ScopeIndex i : rest | List' _ xs <- v, i >= 0, (x : _) <- drop i xs -> go x rest
      _ -> Nothing

{- | Parses style.toml and checks what can be checked without the
filesystem.
-}
parseStyle :: FileId -> Text -> Either [Diagnostic] Style
parseStyle fid src = do
  s0 <- either (Left . map akiCode) Right (decodeStrictBy "G03006" codeAt fid src)
  let s = s0 {stIndex = (\ix -> ix {ixColumnsAt = columnsAt}) <$> stIndex s0}
  -- the same code and message once, at the path that comes first (golem-project ADR 0008)
  case nubBy (\(c, _, m) (c', _, m') -> (c, m) == (c', m')) [(code, path, m) | (code, _, path, m) <- styleChecks "style.toml の" s] of
    [] -> Right s
    ds -> Left [(diagnostic code Error (at path) m) {diagFacts = factsOf s code} | (code, path, m) <- ds]
  where
    -- the facts of G03029 (golem-driver ADR 0041); the other checks have none
    factsOf st = \case
      "G03029" -> concat [fs | (_, _, fs) <- hiddenFolioChecks (stHiddenFolio st)]
      _ -> []
    tree = either (const Nothing) Just (Toml.parse src)
    -- the span of the value to fix, of its table, or the start of the file
    at path = case tree >>= (`checkPosition` path) of
      Just (Position _ l c) | Just off <- lineColToOffset (mkLineIndex src) (LineCol (l - 1) (c - 1)) -> mkSpan fid off off
      _ -> mkSpan fid 0 0
    -- where the value of [index] columns starts, for G07044 (docs/adr ADR 0025)
    columnsAt = spanStart (at [ScopeKey "index", ScopeKey "columns"])
    -- an aki amount wrong in any key is G03020 (docs/adr ADR 0019)
    akiCode d
      | akiError "" `T.isPrefixOf` diagMessage d = d {diagCode = DiagnosticCode "G03020"}
      | otherwise = d
    -- errors of the page size are G03017 (ADR 0005)
    codeAt = \case
      ScopeKey "page" : ScopeKey "size" : _ -> "G03017"
      -- errors of [lists] are G03022 (golem-driver ADR 0013)
      ScopeKey "lists" : _ -> "G03022"
      -- errors of [aki-sets] are G03020 (docs/adr ADR 0019)
      ScopeKey "aki-sets" : _ -> "G03020"
      -- the values of [index] are G03025, an unknown key G03006 (docs/adr ADR 0025)
      ScopeKey "index" : ScopeKey k : _ | k `elem` ["columns", "column-gap"] -> "G03025"
      -- the contents of a running head are G03014, the retired running-head of a heading G03019 (golem-driver ADR 0014)
      ScopeKey "masters" : _ : ScopeKey "running-head" : ScopeKey k : _ | k `elem` ["content", "even", "odd"] -> "G03014"
      -- an unknown position of a running head or a folio is G03018 (golem-driver ADR 0016)
      ScopeKey "masters" : _ : ScopeKey k : ScopeKey "position" : _ | k `elem` ["running-head", "folio"] -> "G03018"
      ScopeKey "headings" : _ : ScopeKey "running-head" : _ -> "G03019"
      -- the keys of kerning, tracking and baseline shift are G03021 (docs/adr/0020)
      ScopeKey t : _ : ScopeKey k : _ | t `elem` ["character-styles", "paragraph-styles"], k `elem` featureKeys -> "G03021"
      _ -> "G03006"

{- | The checks of the styles of a 'Style' (docs/adr ADR 0005, 0006, 0014):
the code, the name of the style it is about (empty when it is about no
style), the path of the value to fix in style.toml (golem-project ADR
0008) and the message. @owner@ starts the message of G03013: where the
definitions were written.
-}
styleChecks :: Text -> Style -> [(Text, Text, [Scope], Text)]
styleChecks owner s =
  [("G03006", "", path, m) | (path, m) <- numberChecks]
    <> [("G03006", n, keys [kind, n], "スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: " <> n) | (kind, n) <- map ("character-styles",) (Map.keys (stCharStyles s)) <> map ("paragraph-styles",) (Map.keys (stParaStyles s)), not (validStyleName n)]
    <> [("G03006", "", path, m) | (path, m) <- checks]
    <> [("G03006", n, path, m) | (n, path, m) <- codeChecks]
    <> [("G03006", n, path, m) | (n, path, m) <- ruleChecks]
    <> [("G03029", "", path, m) | (path, m, _) <- hiddenFolioChecks (stHiddenFolio s)]
    <> [("G03008", n, path, "style.toml にないフォントの役割です: " <> r) | (n, path, r) <- roles, Map.notMember r (stFonts s)]
    <> [("G03013", n, path, owner <> "スタイルの参照が不正です: " <> m) | (n, path, m) <- referenceChecks]
    <> [(code, n, path, m) | (n, ParaStyleDef {psRegexStyles = Just rs}) <- Map.toList (stParaStyles s), (i, r) <- zip [0 ..] rs, (code, path, m) <- regexStyleErrors owner s n i r]
    <> [("G03011", n, para n "size", "段落スタイルの文字の大きさが版面の文字の大きさを超えます: " <> n) | n <- sizeChecks]
    <> [("G03012", n, path, "段落の最初の行が版面の外に出ます。indent と first-line-indent の和を 0 以上にしてください: " <> n) | (n, path) <- indentChecks]
    <> [("G03021", n, keys [kind, n, "kerning"], "v1 ではオプティカルカーニングを使えません（" <> word <> " " <> n <> " の kerning）") | (kind, word, n) <- opticals]
  where
    keys = map ScopeKey
    para n k = keys ["paragraph-styles", n, k]
    char n k = keys ["character-styles", n, k]
    -- the first key of two that is written, the second when neither is
    either2 at written a b = if written then at a else at b
    -- optical kerning is a v2 item (docs/adr/0020)
    opticals =
      [("character-styles", "文字スタイル", n) | (n, CharStyleDef {csKerning = Just KernOptical}) <- Map.toList (stCharStyles s)]
        <> [("paragraph-styles", "段落スタイル", n) | (n, ParaStyleDef {psKerning = Just KernOptical}) <- Map.toList (stParaStyles s)]
    {- font roles named outside [fonts] must exist (golem-driver ADR 0003, 0004; docs/adr ADR 0005);
    the role code of the styles code may be missing: the body role sets code (golem-driver ADR 0017) -}
    roles =
      [("", keys ["headings", T.pack (show l), "font"], f) | (l, HeadingStyle {hsFont = Just f}) <- Map.toList (stHeadings s)]
        <> [(n, char n "font", f) | (n, CharStyleDef {csFont = Just f}) <- Map.toList (stCharStyles s), (n, f) /= ("code", "code")]
        <> [(n, para n "font", f) | (n, ParaStyleDef {psFont = Just f}) <- Map.toList (stParaStyles s), (n, f) /= ("code", "code")]
    {- the paragraph style code takes four keys; background and padding are
    for code only; a padding is not negative (golem-driver ADR 0017) -}
    codeChecks =
      [ ("code", para "code" k, "段落スタイル code に書けるキーは " <> T.intercalate "、" codeParaKeys <> " だけです: " <> T.intercalate ", " ks)
      | Just d <- [Map.lookup "code" (stParaStyles s)],
        ks@(k : _) <- [writtenOtherKeys d]
      ]
        <> [ (n, either2 (para n) (isJust (psBackground d)) "background" "padding", "background と padding は段落スタイル code にだけ書けます: " <> n)
           | (n, d) <- Map.toList (stParaStyles s),
             n /= "code",
             isJust (psBackground d) || isJust (psPadding d)
           ]
        <> [("code", para "code" "padding", "padding は 0 以上の寸法です") | Just ParaStyleDef {psPadding = Just p} <- [Map.lookup "code" (stParaStyles s)], negativeDim p]
        -- the background and the padding of inline code are for code styles only (golem-driver ADR 0029)
        <> [ (n, either2 (char n) (isJust (csBackground d)) "background" "padding", "文字スタイルの background と padding は code と based-on で code に行き着く文字スタイルにだけ書けます: " <> n)
           | (n, d) <- Map.toList (stCharStyles s),
             not (isCodeCharStyle s n),
             isJust (csBackground d) || isJust (csPadding d)
           ]
        <> [(n, char n "padding", "文字スタイル " <> n <> " の padding は 0 以上の寸法です") | (n, CharStyleDef {csPadding = Just p}) <- Map.toList (stCharStyles s), negativeDim p]
        -- the border is for code only, its width an absolute dimension (golem-driver ADR 0023)
        <> [ (n, either2 (para n) (isJust (psBorder d)) "border" "border-width", "border と border-width は段落スタイル code にだけ書けます: " <> n)
           | (n, d) <- Map.toList (stParaStyles s),
             n /= "code",
             isJust (psBorder d) || isJust (psBorderWidth d)
           ]
        <> [ ("code", para "code" "border-width", "border-width は mm、pt、Q、H、in の寸法で書きます")
           | Just ParaStyleDef {psBorderWidth = Just w} <- [Map.lookup "code" (stParaStyles s)],
             case w of
               Zw _ -> True
               Abs x -> x < 0
           ]
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
    -- the rule written first of rule-before and rule-after
    rulePath n d = either2 (para n) (isJust (psRuleBefore d)) "rule-before" "rule-after"
    {- paragraph rules (golem-driver ADR 0027): not on caption, sidenote and
    code; with a grid, a length left by the indents greater than 0 -}
    ruleChecks =
      [ (n, rulePath n d, "段落スタイル " <> n <> " には rule-before と rule-after を書けません")
      | (n, d) <- Map.toList (stParaStyles s),
        n `elem` ["caption", "sidenote", "code"],
        isJust (psRuleBefore d) || isJust (psRuleAfter d)
      ]
        <> case stPage s >>= pageGrid of
          Just Grid {gridFontSize = Abs fs, gridCharacters = chars} ->
            [ (n, maybe (para n "rule-before") (rulePath n) (Map.lookup n (stParaStyles s)), "段落スタイル " <> n <> " の罫線の長さが 0 以下です。start-indent と end-indent を狭めてください")
            | n <- Map.keys (stParaStyles s),
              Just d <- [paraStyle s (Just n)],
              let size = maybe fs (dimToSp fs) (psSize d),
              Just r <- [join (psRuleBefore d), join (psRuleAfter d)],
              isNothing (rsLength r),
              toInteger chars * fs - dimToSp size (rsStartIndent r) - maybe 0 (dimToSp size) (rsEndIndent r) <= 0
            ]
          _ -> []
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
       in [ (n, char n "based-on", "文字スタイル " <> n <> " の based-on がありません: " <> b)
          | (n, CharStyleDef {csBasedOn = Just b}) <- Map.toList cs,
            Map.notMember b cs
          ]
            <> [(n, char n "based-on", "文字スタイルの based-on が循環しています: " <> T.intercalate ", " charCycle) | n <- charCycle]
            <> [(n, char n "color", "文字スタイル " <> n <> " の color のスウォッチがありません: " <> c) | (n, CharStyleDef {csColor = Just c}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            <> [(n, char n "background", "文字スタイル " <> n <> " の background のスウォッチがありません: " <> c) | (n, CharStyleDef {csBackground = Just (Just c)}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            <> [("body", para "body" "based-on", "段落スタイル body には based-on を書けません") | Just ParaStyleDef {psBasedOn = Just _} <- [Map.lookup "body" ps]]
            <> [ (n, para n "based-on", "段落スタイル " <> n <> " の based-on がありません: " <> b)
               | (n, ParaStyleDef {psBasedOn = Just b}) <- Map.toList ps,
                 n `notElem` ["body", "code"],
                 Map.notMember b ps
               ]
            -- code is not a base of other styles (golem-driver ADR 0017)
            <> [ (n, para n "based-on", "段落スタイル code は based-on に書けません。コードブロックの段落スタイルです: " <> n)
               | (n, ParaStyleDef {psBasedOn = Just "code"}) <- Map.toList ps,
                 n /= "code"
               ]
            -- the swatch of a background (golem-driver ADR 0017)
            <> [(n, para n "background", "段落スタイル " <> n <> " の background のスウォッチがありません: " <> c) | (n, ParaStyleDef {psBackground = Just c}) <- Map.toList ps, Map.notMember c (stSwatches s)]
            <> [(n, para n "border", "段落スタイル " <> n <> " の border のスウォッチがありません: " <> c) | (n, ParaStyleDef {psBorder = Just c}) <- Map.toList ps, Map.notMember c (stSwatches s)]
            -- the swatch of a rule (golem-driver ADR 0028)
            <> [("", keys ["notes", "rule", "color"], "[notes.rule] の color のスウォッチがありません: " <> c) | Just RuleSpec {rsColor = Just c} <- [stNotesRule s], Map.notMember c (stSwatches s)]
            <> [ (n, keys ["paragraph-styles", n, k, "color"], "段落スタイル " <> n <> " の罫線の color のスウォッチがありません: " <> c)
               | (n, d) <- Map.toList ps,
                 (k, Just (Just RuleSpec {rsColor = Just c})) <- [("rule-before", psRuleBefore d), ("rule-after", psRuleAfter d)],
                 Map.notMember c (stSwatches s)
               ]
            <> [ ("", keys ["headings", T.pack (show l), k, "color"], "見出し " <> T.pack (show l) <> " の罫線の color のスウォッチがありません: " <> c)
               | (l, h) <- Map.toList (stHeadings s),
                 (k, Just RuleSpec {rsColor = Just c}) <- [("rule-before", hsRuleBefore h), ("rule-after", hsRuleAfter h)],
                 Map.notMember c (stSwatches s)
               ]
            -- the swatches of [code] and [code.colors] (golem-driver ADR 0023)
            <> [("", ScopeKey "code" : path, "[code] の " <> k <> " のスウォッチがありません: " <> c) | (k, path, c) <- codeSwatches, Map.notMember c (stSwatches s)]
            <> [(n, para n "based-on", "段落スタイルの based-on が循環しています: " <> T.intercalate ", " paraCycle) | n <- paraCycle]
            -- aki sets: aki-set and based-on name a set, without a cycle (docs/adr ADR 0019)
            <> [ (n, para n "aki-set", "段落スタイル " <> n <> " の aki-set のアキ量のセットがありません: " <> a)
               | (n, ParaStyleDef {psAkiSet = Just a}) <- Map.toList ps,
                 not (akiKnown a)
               ]
            <> [ ("", keys ["aki-sets", n, "based-on"], "アキ量のセット " <> n <> " の based-on がありません: " <> b)
               | (n, AkiSetDef {asBasedOn = Just b}) <- Map.toList (stAkiSets s),
                 not (akiKnown b)
               ]
            <> [("", keys ["aki-sets", n, "based-on"], "アキ量のセットの based-on が循環しています: " <> T.intercalate ", " akiCycle) | n <- take 1 akiCycle]
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
          written n = maybe False (isJust . psFirstLineIndent) (Map.lookup n (stParaStyles s))
       in [(n, either2 (para n) (written n) "first-line-indent" "indent") | n <- Map.keys (stParaStyles s), Just d <- [paraStyle s (Just n)], negative d]
    numberChecks =
      [ (path, "番号の書式が不正です: " <> f)
      | (path, f) <-
          (keys ["figures", "number"], stFigureNumber s)
            : (keys ["code", "number"], cdNumber (stCode s))
            : [(keys ["headings", T.pack (show l), "number"], n) | (l, HeadingStyle {hsNumber = Just n}) <- Map.toList (stHeadings s)],
        not (validNumberFormat f)
      ]
        -- a listing number has a placeholder (golem-driver ADR 0023)
        <> [(keys ["code", "number"], "[code] の number には {n} などの差し込みを書きます: " <> cdNumber (stCode s)) | not ("{" `T.isInfixOf` cdNumber (stCode s))]
    codeSwatches =
      let c = stCode s
       in [(k, [ScopeKey k], v) | (k, Just v) <- [("line-number-color", cdLineNumberColor c), ("highlight", cdHighlight c), ("added", cdAdded c), ("removed", cdRemoved c)]]
            <> [("colors." <> k, keys ["colors", k], v) | (k, v) <- Map.toList (cdColors c)]
    checks =
      [ (keys ["composition", "explicit-hyphen-penalty"], "explicit-hyphen-penalty は -9999 から 10000 までです: " <> T.pack (show p))
      | let p = compExplicitHyphenPenalty (stComposition s),
        p < -9999 || p > 10000
      ]
        <> [ (keys ["composition", "ruby", "overhang"], "ルビのかけの量は 0 以上です（[composition.ruby] の overhang）")
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
charStyleKeys = ["based-on", "font", "size", "color", "synthetic-bold", "synthetic-italic"] <> featureKeys <> ["background", "padding"]
paraStyleKeys = ["based-on", "font", "size", "line-breaks", "space-between", "indent", "first-line-indent", "aki-set"] <> featureKeys <> ["background", "padding", "border", "border-width"]
regexStyleKeys = ["pattern", "style"]

{- | The keys of one @style-def as a TOML table, read with the 'FromValue'
of style.toml: a string is a string, the words true and false are
booleans, a word of digits (with a leading -) is an integer, any other
word is a string. Errors are (code, message): G03021 for the keys of
kerning, tracking and baseline shift (docs/adr/0020), G03006 for the others.
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
    message (MatchMessage _ path msg) = (codeOf path, schemaMessage path msg)
    codeOf = \case
      ScopeKey k : _ | k `elem` featureKeys -> "G03021"
      _ -> "G03006"
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
  let base = checksOf s
   in nub [c | c <- checksOf (withLocalStyles s ls {lsRegexStyles = Map.empty}), c `notElem` base]
  where
    -- the paths are of style.toml; the errors of a file are at its @style-def
    checksOf st = [(code, n, m) | (code, n, _, m) <- styleChecks "@style-def の" st]

{- | The errors of the i-th (from 0) regex style of a paragraph style
(docs/adr ADR 0015): a pattern outside the dialect is G03015, a character
style that does not exist G03013.
-}
regexStyleErrors :: Text -> Style -> Text -> Int -> RegexStyleDef -> [(Text, [Scope], Text)]
regexStyleErrors owner s para i (RegexStyleDef p st) =
  [ ( "G03015",
      at "pattern",
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
    <> [("G03013", at "style", owner <> "スタイルの参照が不正です: 正規表現スタイルの文字スタイルがありません: " <> st) | Map.notMember st (stCharStyles s)]
  where
    -- the key of the i-th regex style of the paragraph style (golem-project ADR 0008)
    at k = [ScopeKey "paragraph-styles", ScopeKey para, ScopeKey "regex-styles", ScopeIndex i, ScopeKey k]

{- | The errors of the regex styles of a file (docs/adr ADR 0015): the
paragraph style, the place of the regex style among those the file adds
to it (from 0), the code and the message. The paragraph style must exist
(G03013); the character styles of the file count.
-}
checkLocalRegexStyles :: Style -> LocalStyles -> [(Text, Int, Text, Text)]
checkLocalRegexStyles s ls =
  let combined = withLocalStyles s ls {lsRegexStyles = Map.empty}
   in concat
        [ if Map.member p (stParaStyles combined)
            then [(p, i, code, m) | (code, _, m) <- regexStyleErrors owner combined p i r]
            else [(p, i, "G03013", owner <> "スタイルの参照が不正です: 正規表現スタイルの段落スタイルがありません: " <> p)]
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
