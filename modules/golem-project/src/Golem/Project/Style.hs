-- | style.toml (golem-project ADR 0002).
module Golem.Project.Style
  ( Style (..),
    Dim (..),
    Sp (..),
    parseDim,
    parseSignedDim,
    dimToSp,
    parseAki,
    AkiRuleDef (..),
    AkiSetDef (..),
    defaultAkiSetName,
    akiClassNames,
    Page (..),
    PageSize (..),
    pageTrimSize,
    Grid (..),
    FontRole (..),
    Feature (..),
    FeatureSite (..),
    charFeatures,
    paraFeatures,
    CharStyleDef (..),
    Kerning (..),
    LineBreaks (..),
    ParaAlign (..),
    alignValues,
    ParaStyleDef (..),
    CodeStyle (..),
    defaultCodeStyle,
    RegexStyleDef (..),
    regexStyleKeys,
    localRegexStyleDef,
    checkLocalRegexStyles,
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
    paraLineBreaks,
    LocalStyles (..),
    noLocalStyles,
    StyleKind (..),
    LocalValue (..),
    localStyleDef,
    withLocalStyles,
    checkLocalStyles,
    charStyleKeys,
    paraStyleKeys,
    styleSchema,
    builtinCharStyles,
    builtinParaStyles,
    builtinAkiSetNames,
    lineBreaksValues,
    HeadingStyle (..),
    NotesPlacement (..),
    Composition (..),
    RubyStyleDef (..),
    kentenShapeNames,
    SidenoteStyle (..),
    IndexStyle (..),
    HiddenFolio (..),
    HiddenFolioPages (..),
    MasterDef (..),
    RunningHeadDef (..),
    RunningContent (..),
    RunningRef (..),
    RunningPart (..),
    HeadForm (..),
    HeadPick (..),
    parseRunningFormat,
    parseRunningFormatLegacy,
    runningFormatSites,
    runningRefs,
    Swatch (..),
    ListStyle (..),
    defaultListStyle,
    listBullets,
    textBullets,
    RuleSpec (..),
    RuleStyle (..),
    DecorationSpec (..),
    defaultDecoration,
    decorationStyle,
    paraRules,
    parseRuleSpec,
    defaultStyle,
    parseStyle,
    styleNotices,
    captionZeroIndentKeys,
    captionZeroIndentMessage,
    checkPosition,
    loadStyle,
    fontFiles,
    pageSize,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (join, unless, when)
import Data.Bifunctor (bimap)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Foldable (asum, toList)
import Data.List (find, nub, nubBy)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble (NoteNumbering (..))
import Golem.Assemble.Formats (Braces (..), Legacy (..), MarkFormat, NumberSlotName (..), Piece (..), Slot (..), defaultMarkFormat, notationName, parseFormat, parseHeadingNumberFormatText, parseMarkFormat, parseNumberFormatText)
import Golem.Assemble.ListMarkers (NumberFormat, parseNumberFormat, parseNumberFormatLegacy)
import Golem.Length (Sp (..))
import Golem.Length qualified as L
import Golem.Project.Feature
import Golem.Project.Manifest (decodeStrictBy, decodeStrictWith, maxNaturalInt, naturalIntOf, naturalOf, positionSpan, readTomlTable)
import Golem.Project.Position qualified as P
import Golem.Project.TomlMessage (schemaMessage)
import Golem.Project.TomlSchema
import Golem.Regex (RegexError (..), compile)
import Golem.Syntax
import Numeric.Natural (Natural)
import Toml qualified
import Toml.Schema
import Toml.Schema.Matcher (inIndex, inKey)
import Toml.Semantics (valueAnn)
import Toml.Syntax (Position (..))
import Prelude hiding (fail)

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
          "pt" -> Just (abs' L.Pt r)
          "in" -> Just (abs' L.In r)
          "mm" -> Just (abs' L.Mm r)
          "Q" -> Just (abs' L.Q r)
          "H" -> Just (abs' L.H r)
          "zw" -> Just (Zw r)
          _ -> Nothing
  where
    abs' u r = Abs (L.toSp u r)
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
dimToSp fontSize (Zw r) = L.zwToSp fontSize r

data Grid = Grid
  { gridFontSize :: !Dim,
    gridCharacters :: !Natural,
    gridLines :: !Natural,
    gridLinePitch :: !Dim,
    gridColumns :: !Natural,
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
    -- | the OpenType features of the role, checked (docs/adr/0268)
    frFeatures :: ![Feature]
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
    csPadding :: !(Maybe Dim),
    {- | the mark at the end of a line that breaks inside inline code other
    than at a space (golem-layout ADR 0034); for code styles only, the
    empty text draws none
    -} csWrapMark :: !(Maybe Text),
    {- | the OpenType features (docs/adr/0268): through based-on and over a
    definition of the same name they are added after the parent's
    -} csFeatures :: ![Feature],
    -- | normal, superscript or subscript (docs/adr/0269); Nothing is the outer one
    csPosition :: !(Maybe P.Position),
    {- | the underline and the strikethrough (docs/adr/0270): Nothing is not
    written, Just Nothing is false
    -} csUnderline :: !(Maybe (Maybe DecorationSpec)),
    csStrikethrough :: !(Maybe (Maybe DecorationSpec)),
    {- | the characters do not break between them (docs/adr ADR 0272), as
    InDesign's No Break; true in one of the styles around a character is
    true for it
    -} csNoBreak :: !(Maybe Bool)
  }
  deriving stock (Eq, Show)

-- | Whether the newlines of a paragraph break its lines.
data LineBreaks = JoinLines | KeepLines
  deriving stock (Eq, Show)

{- | How the lines of a paragraph are aligned (docs/adr/0189): the
alignments of InDesign. In vertical writing left is the top and right the
bottom of the line.
-}
data ParaAlign
  = ParaLeft
  | ParaCenter
  | ParaRight
  | ParaLeftJustified
  | ParaCenterJustified
  | ParaRightJustified
  | ParaFullyJustified
  | ParaTowardsSpine
  | ParaAwayFromSpine
  deriving stock (Eq, Show, Enum, Bounded)

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
    psRuleAfter :: !(Maybe (Maybe RuleSpec)),
    -- | the alignment of the lines (docs/adr/0189)
    psAlign :: !(Maybe ParaAlign),
    -- | the grid lines before and after the paragraph (docs/adr/0189)
    psSpaceBefore :: !(Maybe Int),
    psSpaceAfter :: !(Maybe Int),
    -- | the end of every line (docs/adr/0189)
    psEndIndent :: !(Maybe Dim),
    -- | the OpenType features, added after the parent's (docs/adr/0268)
    psFeatures :: ![Feature]
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
noCharDef = CharStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing [] Nothing Nothing Nothing Nothing

-- | A paragraph style with no key written.
noParaDef :: ParaStyleDef
noParaDef = ParaStyleDef Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing Nothing []

-- | The keys body has without a definition (docs/adr ADR 0005, 0006, 0019; docs/adr/0020, 0189).
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
      psBaselineShift = Just (Abs 0),
      psAlign = Just ParaLeftJustified,
      psSpaceBefore = Just 0,
      psSpaceAfter = Just 0,
      psEndIndent = Just (Zw 0)
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

-- | The built-in character styles: bold, italic, strong, code (golem-driver ADR 0017), url (golem-doc ADR 0005), note-mark (docs/adr/0177), superscript and subscript (docs/adr/0269) and no-break (docs/adr ADR 0272).
builtinCharStyles :: Map Text CharStyleDef
builtinCharStyles =
  Map.fromList
    [ ("bold", noCharDef {csSyntheticBold = Just True}),
      -- the padding of inline code (golem-driver ADR 0029)
      -- the wrap mark of inline code (golem-layout ADR 0034): U+23CE, which the code fonts of the manuals have, not U+21A9
      ("code", noCharDef {csFont = Just "code", csPadding = Just (Zw (1 % 4)), csWrapMark = Just "\x23CE"}),
      ("italic", noCharDef {csSyntheticItalic = Just True}),
      -- a range that does not break (docs/adr ADR 0272)
      ("no-break", noCharDef {csNoBreak = Just True}),
      -- the marks of notes in the text (docs/adr/0177): the size of the retired [notes] mark-size
      ("note-mark", noCharDef {csSize = Just (Zw (1 % 2))}),
      ("strong", noCharDef {csBasedOn = Just "bold"}),
      -- superscript and subscript (docs/adr/0269)
      ("subscript", noCharDef {csPosition = Just P.PositionSubscript}),
      ("superscript", noCharDef {csPosition = Just P.PositionSuperscript}),
      ("url", noCharDef)
    ]

{- | The first definition that writes a size on the based-on chain of the
character style of the marks of notes in the text, which [notes]
mark-size cannot be written with (docs/adr/0177, docs/adr/0214): the
chain starts at the style of mark-style, or else at note-mark. The size of
the built-in note-mark does not count; mark-size stands for it.
-}
markSizeConflict :: Map Text CharStyleDef -> Maybe Text -> Maybe Text
markSizeConflict user markStyle =
  let builtins = Map.adjust (\c -> c {csSize = Nothing}) "note-mark" builtinCharStyles
      styles = Map.unionWith overChar user builtins
      chain = chainOf (const (csBasedOn . snd)) (Map.mapWithKey (,) styles) (fromMaybe "note-mark" markStyle)
   in fst <$> find (isJust . csSize . snd) chain

-- | The message of 'markSizeConflict' for the style that writes the size (docs/adr/0214).
markSizeConflictMessage :: Maybe Text -> Text -> Text
markSizeConflictMessage markStyle definer =
  "[notes] の mark-size と、"
    <> maybe "注の印の文字スタイル note-mark" ("mark-style " <>) markStyle
    <> " の size（[character-styles."
    <> definer
    <> "] に書いたもの）は一緒に書けません。mark-size を消します"

{- | The built-in note-mark at the size of [notes] mark-size, when
mark-size is written and mark-style is not (docs/adr/0177): mark-size is
short for the size of the character style of the marks.
-}
markSizeOver :: Maybe Dim -> Maybe Text -> Map Text CharStyleDef -> Map Text CharStyleDef
markSizeOver (Just d) Nothing = Map.adjust (\c -> c {csSize = Just d}) "note-mark"
markSizeOver _ _ = id

-- | The built-in paragraph styles: body, verse (a line before and after it, docs/adr/0180), caption, sidenote and code (golem-driver ADR 0017).
builtinParaStyles :: Map Text ParaStyleDef
builtinParaStyles =
  Map.fromList
    [ ("body", bodyDefaults),
      ("verse", noParaDef {psBasedOn = Just "body", psLineBreaks = Just KeepLines, psSpaceBetween = Just 1, psSpaceBefore = Just 1, psSpaceAfter = Just 1, psIndent = Just (Zw 2), psFirstLineIndent = Just (Zw (-2))}),
      -- caption and sidenote do not take the indents of body (golem-driver ADR 0043)
      ("caption", noIndents {psBasedOn = Just "body"}),
      ("sidenote", noIndents {psBasedOn = Just "body"}),
      ("code", noParaDef {psFont = Just "code", psPadding = Just (Zw (1 % 2))})
    ]
  where
    noIndents = noParaDef {psIndent = Just (Zw 0), psFirstLineIndent = Just (Zw 0), psEndIndent = Just (Zw 0)}

{- | The non-zero indent keys written for caption or sidenote, which do not
indent (golem-driver ADR 0043): (the name of the style, the key). A zero
one is the notice G03100.
-}
captionIndentKeys :: Map Text ParaStyleDef -> [(Text, Text)]
captionIndentKeys styles =
  [ (n, k)
  | n <- ["caption", "sidenote"],
    Just d <- [Map.lookup n styles],
    (k, Just v) <- indentKeysOf d,
    not (zeroDim v)
  ]

-- | The indent keys of a definition of caption or sidenote whose value is zero (G03100, golem-driver ADR 0043).
captionZeroIndentKeys :: Text -> ParaStyleDef -> [Text]
captionZeroIndentKeys n d = [k | n `elem` ["caption", "sidenote"], (k, Just v) <- indentKeysOf d, zeroDim v]

indentKeysOf :: ParaStyleDef -> [(Text, Maybe Dim)]
indentKeysOf d = [("indent", psIndent d), ("first-line-indent", psFirstLineIndent d), ("end-indent", psEndIndent d)]

zeroDim :: Dim -> Bool
zeroDim = \case
  Abs x -> x == 0
  Zw r -> r == 0

{- | The notices of style.toml: G03100 for a zero indent or
first-line-indent of caption or sidenote, at the value, with the value as
written (golem-driver ADR 0043); the ways of writing to be retired
(docs/adr/0177), at the value: G03114 and G03115 for a format of [lists]
numbers, G03116 for a line of a running head format, G03117 for [notes]
mark-size. A style.toml that does not parse has none.
-}
styleNotices :: FileId -> Text -> [Diagnostic]
styleNotices fid src = case Toml.parse src of
  Left _ -> []
  Right top ->
    let root = Table' (Position 0 1 1) top
     in [ notice "G03100" (spanAt pos) (captionZeroIndentMessage n k ("\"" <> t <> "\""))
        | n <- ["caption", "sidenote"],
          k <- ["indent", "first-line-indent", "end-indent"],
          Just (Text' pos t) <- [lookupValue root ["paragraph-styles", n, k]],
          Just v <- [parseSignedDim t],
          zeroDim v
        ]
          <> concat
            [ [notice "G03114" (spanAt pos) ("[lists] の numbers の {{ と }} は廃止予定です。\\{ と \\} と書きます: " <> t) | LegacyBraces `elem` legacy]
                <> [notice "G03115" (spanAt pos) ("[lists] の numbers の {" <> w <> "} は廃止予定です。{n:" <> notationName n <> "} と書きます: " <> t) | LegacySample w n <- take 1 [l | l@LegacySample {} <- legacy]]
            | Just (List' _ xs) <- [lookupValue root ["lists", "numbers"]],
              Text' pos t <- xs,
              Right (_, legacy) <- [parseNumberFormatLegacy t]
            ]
          <> [ notice "G03116" (spanAt pos) ("柱の書式の {{ と }} は廃止予定です。\\{ と \\} と書きます: " <> t)
             | Just (Table' _ (MkTable masters)) <- [lookupValue root ["masters"]],
               (_, master) <- Map.elems masters,
               k <- ["content", "even", "odd"],
               Just (List' _ xs) <- [lookupValue master ["running-head", k]],
               Text' pos t <- xs,
               Right (_, legacy) <- [parseRunningFormatLegacy t],
               LegacyBraces `elem` legacy
             ]
          <> [ notice "G03117" (spanAt pos) "[notes] の mark-size は廃止予定です。[character-styles.note-mark] の size に書きます"
             | Just v <- [lookupValue root ["notes", "mark-size"]],
               let pos = valueAnn v
             ]
  where
    lookupValue v = \case
      [] -> Just v
      k : rest | Table' _ (MkTable t) <- v -> Map.lookup k t >>= \(_, x) -> lookupValue x rest
      _ -> Nothing
    spanAt (Position _ l c) = case lineColToOffset (mkLineIndex src) (LineCol (l - 1) (c - 1)) of
      Just off -> mkSpan fid off off
      Nothing -> mkSpan fid 0 0

-- | The message of G03100: a zero indent of caption or sidenote, with the value as written (golem-driver ADR 0043).
captionZeroIndentMessage :: Text -> Text -> Text -> Text
captionZeroIndentMessage n k v = "キャプションと傍注は字下げを掛けないので、" <> n <> "." <> k <> " = " <> v <> " は効果がありません"

-- | The message of an indent key of caption or sidenote (golem-driver ADR 0043).
captionIndentMessage :: Text -> Text -> Text
captionIndentMessage n k = "段落スタイル " <> n <> " には 0 でない indent、first-line-indent、end-indent を書けません。キャプションと傍注は字下げをしません: " <> k

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

{- | A user definition over a built-in one: the keys written win, but the
features are added after those of the definition below (docs/adr/0268).
-}
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
    (csWrapMark u <|> csWrapMark b)
    (csFeatures b <> csFeatures u)
    (csPosition u <|> csPosition b)
    (csUnderline u <|> csUnderline b)
    (csStrikethrough u <|> csStrikethrough b)
    (csNoBreak u <|> csNoBreak b)

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
    (psAlign u <|> psAlign b)
    (psSpaceBefore u <|> psSpaceBefore b)
    (psSpaceAfter u <|> psSpaceAfter b)
    (psEndIndent u <|> psEndIndent b)
    (psFeatures b <> psFeatures u)

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

{- | The features of a character style through its based-on chain, root
first (docs/adr/0268); none for an unknown name.
-}
charFeatures :: Style -> Text -> [Feature]
charFeatures style = maybe [] csFeatures . charStyle style

-- | The features of a paragraph style through its based-on chain, root first (docs/adr/0268).
paraFeatures :: Style -> Maybe Text -> [Feature]
paraFeatures style = maybe [] psFeatures . paraStyle style

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
    hsLines :: !(Maybe Natural),
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
  { ixColumns :: !(Maybe Natural),
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
defaultHiddenFolio = HiddenFolio True HiddenUnnumbered (Abs (L.toSp L.Pt 6)) (Abs (mmToSp (3 % 2))) False

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
        ( withValue $ \l v ->
            maybe
              (failAt l ("[hidden-folio] の pages に使えない値です: " <> T.unpack v <> "（" <> T.unpack (T.intercalate ", " (map fst hiddenFolioPagesValues)) <> " のどれか）"))
              pure
              (lookup v hiddenFolioPagesValues)
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
                <> mmText gutter
                <> "）が size（"
                <> mmText size
                <> "）の半分（"
                <> L.mmRationalText (spToMm size / 2)
                <> "）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（gutter を "
                <> hundredthsText minGutter
                <> " 以上にするか、size を "
                <> hundredthsText maxSize
                <> " 以下にします）"
         in [(path, message, [("gutter", FactInt (unSp gutter)), ("size", FactInt (unSp size)), ("min-gutter", FactInt (unSp (mmToSp (minGutter % 100)))), ("max-size", FactInt (unSp (mmToSp (maxSize % 100))))])]
  _ -> []
  where
    spToMm = L.fromSp L.Mm
    -- mm to two decimals, half to even (docs/adr ADR 0103)
    mmText = L.mmText
    -- hundredths of a mm, which come back from sp unrounded
    hundredthsText k = L.mmText (L.toSp L.Mm (k % 100))

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
  | -- | a variable of [vars] of manifest.toml, by its path in the tables (docs/adr/0185)
    RefProjectVar ![Text]
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
each depth, and the gap between a marker and the text. Without bullets,
the default of the output is used (golem-driver ADR 0044); without
numbers, the default of the writing mode.
-}
data ListStyle = ListStyle
  { lsBullets :: !(Maybe (NonEmpty Text)),
    lsNumbers :: !(Maybe (NonEmpty NumberFormat)),
    lsGap :: !(Maybe Dim)
  }
  deriving stock (Eq, Show)

-- | No [lists]: the bullet of the output, the numbers and the gap of the writing mode.
defaultListStyle :: ListStyle
defaultListStyle = ListStyle Nothing Nothing Nothing

{- | The bullets of [lists] by depth in PDF, HTML and EPUB: those written,
or • without bullets (golem-driver ADR 0044).
-}
listBullets :: ListStyle -> NonEmpty Text
listBullets = bulletsOr "•"

-- | The bullets of [lists] by depth in plain text: those written, or ・ without bullets (golem-driver ADR 0044).
textBullets :: ListStyle -> NonEmpty Text
textBullets = bulletsOr "・"

bulletsOr :: Text -> ListStyle -> NonEmpty Text
bulletsOr def = fromMaybe (pure def) . lsBullets

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

-- | @heading.<l>.<form>@ of a level of 1 to 6 (docs/adr/0188).
headingRef :: Text -> Text -> HeadPick -> Maybe RunningRef
headingRef l f pick = do
  level <- if not (T.null l) && T.all isDigit l then Just (read (T.unpack l)) else Nothing
  form <- case f of
    "short" -> Just HeadShort
    "numbered" -> Just HeadNumbered
    "number" -> Just HeadNumber
    _ -> Nothing
  if level >= 1 && level <= 6 then Just (RefHeading level form pick) else Nothing

-- | The keys of [metadata] a running head can show (golem-driver ADR 0022).
runningMetaKeys :: [Text]
runningMetaKeys = ["title", "title_reading", "edition", "publisher", "date", "language", "id"]

{- | One line of a running head format (golem-driver ADR 0022): text and
slots in braces, escapes for braces (docs/adr/0177); @{{@ and @}}@ are
read as braces until they are retired (G03116). 'Left' is the reason of
G03014.
-}
parseRunningFormat :: Text -> Either Text [RunningPart]
parseRunningFormat = fmap fst . parseRunningFormatLegacy

-- | 'parseRunningFormat' with the forms to be retired the line uses (G03116).
parseRunningFormatLegacy :: Text -> Either Text ([RunningPart], [Legacy])
parseRunningFormatLegacy t0
  | T.null t0 = Left "空の行があります"
  | T.any (== '\n') t0 = Left "行の中に改行があります。行は配列の要素で分けてください"
  | otherwise = do
      (ps, legacy) <- parseFormat DoubledToo (fmap TextSlot . slot) t0
      pure (merge [part p | p <- ps], legacy)
  where
    part = \case
      PLit t -> PartText t
      PText r -> r
      PNumber r _ -> r
    slot name0 =
      let (name, optional) = maybe (name0, False) (,True) (T.stripSuffix "?" name0)
          unknown = Left ("未知の差し込みです: {" <> name0 <> "}")
          slotRef r = Right (PartRef r optional)
       in case T.splitOn "." name of
            ["heading", l, f] -> maybe unknown slotRef (headingRef l f PickFirst)
            ["heading", l, f, "last"] -> maybe unknown slotRef (headingRef l f PickLast)
            ["meta", "creators"] -> Left "meta.creators は配列なので、柱に書けません。@set で文字列の変数を作ってください"
            ["meta", k] | k `elem` runningMetaKeys -> slotRef (RefMeta k)
            ("set" : ns@(_ : _)) | length ns <= 2 && all varName ns -> slotRef (RefVar ns)
            -- a variable of [vars], in its tables too (docs/adr/0185)
            ("vars" : ns@(_ : _)) | all varName ns -> slotRef (RefProjectVar ns)
            _ -> unknown
    varName n = case T.uncons n of
      Just (c, r) -> (isAsciiLetter c || c == '_') && T.all (\x -> isAsciiLetter x || isDigit x || x == '_') r
      Nothing -> False
    isAsciiLetter c = isAsciiLower c || isAsciiUpper c
    merge = \case
      PartText a : PartText b : r -> merge (PartText (a <> b) : r)
      x : r -> x : merge r
      [] -> []

{- | The lines of the running head formats of style.toml, where they are
written (docs/adr/0185): the master page, the span of the string and the
slots of the line. Style keeps no positions; this reads the text again.
A line that is not a format is left out: G03014 reports it.
-}
runningFormatSites :: FileId -> Text -> [(Text, SrcSpan, [(RunningRef, Bool)])]
runningFormatSites fid src = case readTomlTable src of
  Nothing -> []
  Just (MkTable top) ->
    [ (name, positionSpan fid src (Just pos), [(r, q) | PartRef r q <- parts])
    | Just (_, Table' _ (MkTable masters)) <- [Map.lookup "masters" top],
      (name, (_, Table' _ (MkTable master))) <- Map.toList masters,
      Just (_, Table' _ (MkTable rh)) <- [Map.lookup "running-head" master],
      key <- ["content", "even", "odd"],
      Just (_, List' _ xs) <- [Map.lookup key rh],
      Text' pos t <- xs,
      Right parts <- [parseRunningFormat t]
    ]

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

{- | An underline or a strikethrough of a character style (docs/adr/0270):
the keys of a rule spec that draw the line, with zw (the size of the
character the line belongs to) in the weight, the dash and the gap, and
the offset from the face of the characters.
-}
data DecorationSpec = DecorationSpec
  { -- | greater than 0; 0.05zw by default
    dsWeight :: !Dim,
    -- | from the face; 0 by default
    dsOffset :: !Dim,
    -- | the name of the line style and the proportions of the styles of several lines
    dsStyle :: !(Text, Maybe [Int]),
    dsDash :: !(Maybe Dim),
    dsGap :: !(Maybe Dim),
    -- | the swatch; none is the colour of the characters
    dsColor :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

-- | The line of true and of an empty table: 0.05zw, at the face, solid, the colour of the characters.
defaultDecoration :: DecorationSpec
defaultDecoration = DecorationSpec (Zw (1 % 20)) (Abs 0) ("solid", Nothing) Nothing Nothing Nothing

{- | The weight and the line style of a decoration at a size, its lengths
in sp: the defaults of the dash and the gap are those of a rule of the
weight (golem-driver ADR 0028).
-}
decorationStyle :: Sp -> DecorationSpec -> (Sp, RuleStyle)
decorationStyle size d =
  let w = dimToSp size (dsWeight d)
      len = fmap (dimToSp size)
   in (w, lineStyle w (dsStyle d) (len (dsDash d)) (len (dsGap d)))

-- | The line style of a name with its dash and gap, the defaults from the weight (golem-driver ADR 0028).
lineStyle :: Sp -> (Text, Maybe [Int]) -> Maybe Sp -> Maybe Sp -> RuleStyle
lineStyle w (name, multi) dash gap = case multi of
  Just ratios -> RuleMulti ratios
  Nothing -> case name of
    "dashed" -> RuleDashed (fromMaybe (3 * w) dash) (fromMaybe (2 * w) gap)
    "dotted" -> RuleDotted (fromMaybe (2 * w) gap)
    "japanese-dots" -> RuleJapaneseDots (fromMaybe w gap)
    "wavy" -> RuleWavy
    _ -> RuleSolid

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
  deriving stock (Eq, Ord, Show)

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
    LineKeys weight' color styleOf dashOf gapOf <- lineKeys False
    let weight = (\case Abs x -> x; Zw _ -> 0) <$> weight'
        space key = optKeyOf key $ ruleDim key $ \l d ->
          if negativeDim d then failAt l (T.unpack ("罫線の " <> key <> " は 0 以上の寸法です")) else pure d
    before <- space "space-before"
    after <- space "space-after"
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
        abs' = fmap (\case Abs x -> x; Zw _ -> 0)
        style = lineStyle w styleOf (abs' dashOf) (abs' gapOf)
    pure (RuleSpec len w before after color style (fromMaybe (Zw 0) startIndent) endIndent (fromMaybe True keepIn))
    where
      ruleDim key check v = case v of
        Text' l t -> maybe (failAt l (T.unpack ("罫線の " <> key <> " を寸法として読めません: " <> t))) (check l) (parseSignedDim t)
        _ -> failAt (valueAnn v) (T.unpack ("罫線の " <> key <> " は \"0.3pt\" のように文字列で書きます"))
      positiveDim = \case
        Abs x -> x > 0
        Zw r -> r > 0

-- | The keys of a rule spec and of a decoration that draw the line (golem-driver ADR 0028, docs/adr/0270).
data LineKeys = LineKeys !(Maybe Dim) !(Maybe Text) !(Text, Maybe [Int]) !(Maybe Dim) !(Maybe Dim)

{- | Reads weight, color, style, dash and gap of a rule spec, or of a
decoration when zw is allowed (docs/adr/0270): the weight, the dash and
the gap greater than 0, a dash or a gap only for the styles that use it
(golem-driver ADR 0028). One reading for both, with the same messages.
-}
lineKeys :: Bool -> ParseTable l LineKeys
lineKeys zwAllowed = do
  let positive key = optKeyOf key $ ruleDim key $ \l -> \case
        Zw r
          | not zwAllowed -> failAt l (T.unpack ("罫線の " <> key <> " には zw を使えません"))
          | r > 0 -> pure (l, Zw r)
          | otherwise -> failAt l (T.unpack ("罫線の " <> key <> " は 0 より大きい寸法です"))
        Abs x
          | x > 0 -> pure (l, Abs x)
          | otherwise -> failAt l (T.unpack ("罫線の " <> key <> " は 0 より大きい寸法です"))
  weight <- positive "weight"
  color <- optKeyOf "color" $ \case
    Text' _ t -> pure t
    v -> failAt (valueAnn v) "罫線の color はスウォッチの名前を文字列で書きます"
  styleName <- optKeyOf "style" $ \case
    Text' l t
      | Just multi <- lookup t ruleStyleNames -> pure (l, t, multi)
      | otherwise -> failAt l (T.unpack ("罫線の style に使えない値です: " <> t <> "（" <> T.intercalate ", " (map fst ruleStyleNames) <> " のどれか）"))
    v -> failAt (valueAnn v) "罫線の style は \"solid\" のように文字列で書きます"
  dash <- positive "dash"
  gap <- positive "gap"
  let name = maybe "solid" (\(_, t, _) -> t) styleName
      multi = styleName >>= \(_, _, m) -> m
      -- a key without effect on the style is an error (golem-driver ADR 0028)
      refuse key = \case
        Just (l, _) -> liftMatcher (failAt l (T.unpack ("罫線の " <> key <> " は style が " <> name <> " のときには書けません")))
        Nothing -> pure ()
  case (multi, name) of
    (Just _, _) -> refuse "dash" dash >> refuse "gap" gap
    (_, "dashed") -> pure ()
    (_, n) | n `elem` ["dotted", "japanese-dots"] -> refuse "dash" dash
    _ -> refuse "dash" dash >> refuse "gap" gap
  pure (LineKeys (snd <$> weight) color (name, multi) (snd <$> dash) (snd <$> gap))
  where
    ruleDim key check v = case v of
      Text' l t -> maybe (failAt l (T.unpack ("罫線の " <> key <> " を寸法として読めません: " <> t))) (check l) (parseSignedDim t)
      _ -> failAt (valueAnn v) (T.unpack ("罫線の " <> key <> " は \"0.3pt\" のように文字列で書きます"))

{- | The table of an underline or a strikethrough (docs/adr/0270): the keys
of a rule spec that draw the line, zw allowed, and offset; the keys of
the length and the place of a rule are unknown keys (G03006).
-}
instance FromValue DecorationSpec where
  fromValue = parseTableFromValue $ do
    LineKeys weight color style dash gap <- lineKeys True
    offset <- optKeyOf "offset" $ \case
      Text' l t -> maybe (failAt l (T.unpack ("offset の長さの書き方が不正です: " <> t <> "（0.05zw や -1pt のように書きます）"))) pure (parseSignedDim t)
      v -> failAt (valueAnn v) "offset は \"0.05zw\" のように文字列で書きます"
    let d = defaultDecoration
    pure (DecorationSpec (fromMaybe (dsWeight d) weight) (fromMaybe (dsOffset d) offset) style dash gap color)

-- | 0.3pt.
defaultRuleWeight :: Sp
defaultRuleWeight = L.toSp L.Pt (3 % 10)

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
    -- | [numbers] ref-page: the numerals of [ref-page] in vertical text; Nothing follows vertical (docs/adr/0118)
    stNumbersRefPage :: !(Maybe Text),
    -- | [notes] placement: the foot of the page or the end of the chapter, in the PDF (golem-driver ADR 0026)
    stNotesPlacement :: !NotesPlacement,
    -- | [notes] numbering: the range over which notes are numbered (golem-driver ADR 0018)
    stNotesNumbering :: !NoteNumbering,
    -- | [notes.rule]: the rule before footnotes in the PDF, its length always there (golem-driver ADR 0024)
    stNotesRule :: !(Maybe RuleSpec),
    {- | [notes] mark-size, to be retired (docs/adr/0177): the size of the
    marks in the text in the PDF (golem-driver ADR 0025), over that of
    their character style; Nothing when it is not written
    -} stNotesMarkSize :: !(Maybe Dim),
    -- | [notes] mark-format: the text of note marks in the PDF, the number in a notation (golem-driver ADR 0025, docs/adr/0177)
    stNotesMarkFormat :: !MarkFormat,
    -- | [notes] mark-style: the character style of the marks in the text in the PDF (docs/adr/0177)
    stNotesMarkStyle :: !Text,
    -- | [notes] body-mark-style: the character style of the marks at the start of note bodies in the PDF; Nothing is none (docs/adr/0177)
    stNotesBodyMarkStyle :: !(Maybe Text),
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
      stNumbersRefPage = Nothing,
      stNotesPlacement = PlaceFoot,
      stNotesNumbering = NumberPerChapter,
      stNotesRule = Nothing,
      stNotesMarkSize = Nothing,
      stNotesMarkFormat = defaultMarkFormat,
      stNotesMarkStyle = "note-mark",
      stNotesBodyMarkStyle = Nothing,
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
pageSize n = lookup n pageSizes

-- | The named page sizes, in millimetres (the values of size, docs/adr ADR 0169).
pageSizes :: [(Text, (Rational, Rational))]
pageSizes =
  [ ("A4", (210, 297)),
    ("A5", (148, 210)),
    ("A6", (105, 148)),
    ("B5", (182, 257)),
    ("B6", (128, 182)),
    ("四六判", (127, 188)),
    -- ADR 0005
    ("菊判", (150, 220)),
    ("新書判", (103, 182)),
    -- 4.25in x 6.875in (ADR 0003): exactly 107.95mm x 174.625mm, so that
    -- the size is rounded to sp once, in pageTrimSize
    ("mass-market", (10795 % 100, 174625 % 1000))
  ]

-- | 仕上がりの幅と高さ（sp）。
pageTrimSize :: Page -> (Sp, Sp)
pageTrimSize p = case pageSizeSpec p of
  -- the name was checked against the table when style.toml was read
  NamedSize n -> maybe (0, 0) (bimap mmToSp mmToSp) (pageSize n)
  CustomSize w h -> (w, h)

-- | Millimetres to sp, rounded once, half to even.
mmToSp :: Rational -> Sp
mmToSp = L.toSp L.Mm

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
    ch <- reqKeyOf "characters" naturalIntOf
    ls <- reqKeyOf "lines" naturalIntOf
    lp <- reqDim "line-pitch"
    colsAt <- optKeyOf "columns" (\v -> (valueAnn v,) <$> naturalIntOf v)
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
    binding <- enumKey "binding" bindingValues
    wm <- enumKey "writing-mode" writingModeValues
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
      (FontRole . fmap T.unpack <$> optKey "ja") <*> (fmap T.unpack <$> optKey "latin") <*> featuresKey

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
    wm <- optKey "wrap-mark"
    fs <- featuresKey
    -- normal, superscript or subscript (docs/adr/0269)
    pos <- enumKey "position" (map fst P.positionValues)
    -- the underline and the strikethrough: true, a table or false (docs/adr/0270)
    ul <- optKeyOf "underline" decorationOrFalse
    st <- optKeyOf "strikethrough" decorationOrFalse
    nb <- optKey "no-break"
    pure (CharStyleDef b f s c sb si k t p bs bg pad' wm fs (pos >>= (`lookup` P.positionValues)) ul st nb)

{- | An underline or a strikethrough (docs/adr/0270): true is the default
line, a table the keys written, false none.
-}
decorationOrFalse :: Value' l -> Matcher l (Maybe DecorationSpec)
decorationOrFalse = \case
  Bool' _ False -> pure Nothing
  Bool' _ True -> pure (Just defaultDecoration)
  v@Table' {} -> Just <$> fromValue v
  v -> failAt (valueAnn v) "下線と打ち消し線には true、false か表を書きます"

{- | The key features (docs/adr/0268): an array of the four forms of
'parseFeature'. Each element that is not one fails at itself, all of them
at once, in their order (G03124 by the path of the element).
-}
featuresKey :: ParseTable l [Feature]
featuresKey =
  fmap (fromMaybe []) . optKeyOf "features" $ \case
    List' _ xs -> do
      read' <- sequence [inIndex i ((valueAnn x,) <$> fromValue x) | (i, x) <- zip [0 ..] xs]
      case [inIndex i (failAt l (T.unpack (featureMessage t))) | (i, (l, t)) <- zip [0 ..] read', Nothing <- [parseFeature t]] of
        [] -> pure [Feature tag v SiteNone | (_, t) <- read', Just (tag, v) <- [parseFeature t]]
        bad -> asum bad
    v -> failAt (valueAnn v) "features には配列を書きます（[\"smcp\", \"-liga\"] のように書きます）"

{- | kerning, tracking, proportional-metrics and baseline-shift
(docs/adr/0020). Every error is under its key, which makes it G03021.
-}
featureKeysOf :: ParseTable l (Maybe Kerning, Maybe Int, Maybe Bool, Maybe Dim)
featureKeysOf = do
  let wrong l key v = failAt l (T.unpack (key <> " の値が正しくありません: " <> v))
  k <-
    optKeyOf "kerning" $
      withValue $
        \l v -> maybe (wrong l "kerning" v) pure (lookup v kerningValues)
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
    lb <- enumKey "line-breaks" lineBreaksValues
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
    -- the alignment, the spaces before and after and the end indent (docs/adr/0189)
    al <- enumKey "align" alignValues
    sbefore <- optKeyOf "space-before" (withValue (\l x -> if x < 0 then failAt l "space-before は 0 以上です" else pure x))
    safter <- optKeyOf "space-after" (withValue (\l x -> if x < 0 then failAt l "space-after は 0 以上です" else pure x))
    endInd <- dimKey "end-indent"
    fs <- featuresKey
    let align = al >>= \v -> lookup v (zip alignValues [minBound .. maxBound])
    pure (ParaStyleDef b f s ((\x -> if x == "keep" then KeepLines else JoinLines) <$> lb) sb ind fli' rs aki k t p bs bg pad' border bw rb ra align sbefore safter endInd fs)

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
    pb <- enumKey "page-break" pageBreakValues
    ls <- optKeyOf "lines" $ \v -> naturalIntOf v >>= \l -> if l < 1 then failAt (valueAnn v) ("lines は 1 以上の整数です: " <> show l) else pure l
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
    m <- enumKey "mono-align" monoAlignValues
    g <- enumKey "group-align" groupAlignValues
    b <- enumKey "base-spacing" baseSpacingValues
    o <- dimKey "overhang"
    onto <- enumKey "overhang-onto" overhangOntoValues
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
    k <- enumKey "kinsoku" kinsokuValues
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
    _ <- enumKey "side" sideValues
    w <- reqDim "width"
    g <- reqDim "gap"
    f <- textAt "font"
    s <- textAt "size"
    case fmap fst f <|> fmap fst s of
      Just l -> failTableAt l "[sidenotes] の font と size は廃止しました。[paragraph-styles.sidenote] の font と size に書き換えます"
      Nothing -> pure ()
    m <- enumKey "marker" markerValues
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

-- | [numbers]: vertical and ref-page (golem-parser ADR 0011, docs/adr/0118).
data Numbers = Numbers (Maybe Text) (Maybe Text)

instance FromValue Numbers where
  fromValue = parseTableFromValue (Numbers <$> enumKey "vertical" verticalValues <*> enumKey "ref-page" refPageValues)

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

data Notes = Notes (Maybe Text) (Maybe NoteNumbering) (Maybe RuleSpec) (Maybe Dim) (Maybe MarkFormat) (Maybe Text) (Maybe Text)

instance FromValue Notes where
  fromValue =
    parseTableFromValue
      ( Notes
          <$> enumKey "placement" placementValues
          <*> (fmap numbering <$> enumKey "numbering" numberingValues)
          <*> optKeyOf "rule" noteRule
          <*> optKeyOf "mark-size" (withValue (\l (DimV d) -> markSize l d))
          <*> optKeyOf "mark-format" (withValue markFormat)
          <*> optKey "mark-style"
          <*> optKey "body-mark-style"
      )
    where
      {- the size of note marks (golem-driver ADR 0025): above 0, and at
      most the size of the text in zw -}
      markSize l d = case d of
        Abs n | n > 0 -> pure d
        Zw r | r > 0 && r <= 1 -> pure d
        _ -> failAt l "[notes] の mark-size は 0 より大きい寸法で、zw では 1 以下です"
      -- the format of note marks: one number, {n} or {n:<notation>} (golem-driver ADR 0025, docs/adr/0177)
      markFormat l f = either (\why -> failAt l (T.unpack ("[notes] の mark-format が正しくありません（" <> why <> "）: " <> f))) pure (parseMarkFormat f)
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
    pure (ListsSec (ListStyle bs fmts g))

{- | [index] (docs/adr ADR 0025): every error is at its value, G03025 by
its path. The position of columns is filled in by 'parseStyle'.
-}
newtype IndexSec = IndexSec IndexStyle

instance FromValue IndexSec where
  fromValue = parseTableFromValue $ do
    cs <- optKeyOf "columns" $ \v -> case v of
      -- a natural number: a negative one is G02103 (docs/adr ADR 0102)
      Integer' {} ->
        naturalOf v >>= \n ->
          -- up to 2^31 - 1 on every target (docs/adr ADR 0247)
          if n >= 1 && n <= maxNaturalInt then pure n else failAt (valueAnn v) "[index] の columns は 1 以上の整数です"
      _ -> failAt (valueAnn v) "[index] の columns は 1 以上の整数です"
    gap <- optKeyOf "column-gap" $ \v -> case v of
      Text' _ t | Just d <- parseSignedDim t, not (negativeDim d) -> pure d
      _ -> failAt (valueAnn v) "[index] の column-gap が正しくありません"
    pure (IndexSec (IndexStyle cs gap 0))

newtype TocSec = TocSec (Maybe Text)

instance FromValue TocSec where
  fromValue = parseTableFromValue (TocSec <$> enumKey "leader" leaderValues)

data ColorSec = ColorSec (Maybe Text) (Map Text Swatch)

instance FromValue ColorSec where
  fromValue = parseTableFromValue (ColorSec <$> optKey "intent" <*> (fromMaybe Map.empty <$> optKey "swatches"))

instance FromValue Style where
  fromValue = parseTableFromValue $ do
    page <- optKey "page"
    fonts <- fromMaybe Map.empty <$> optKey "fonts"
    cstyles <- fromMaybe Map.empty <$> optKey "character-styles"
    -- the indents of caption and sidenote, as written (golem-driver ADR 0043)
    pstyles <-
      fmap (fromMaybe Map.empty) . optKeyOf "paragraph-styles" $ \v -> do
        (styles :: Map Text ParaStyleDef) <- fromValue v
        case captionIndentKeys styles of
          (n, k) : _ ->
            let style = case v of
                  Table' _ (MkTable t) -> maybe v snd (Map.lookup n t)
                  _ -> v
             in inKey n (inKey k (failAt (keyPosition style k) (T.unpack (captionIndentMessage n k))))
          [] -> pure styles
    hs <-
      fmap (fromMaybe []) . optKeyOf "headings" $ \v -> do
        (headings :: Map Text HeadingStyle) <- fromValue v
        traverse (headingLevel v) (Map.toList headings)
    comp <- fromMaybe defaultComposition <$> optKey "composition"
    Numbers nv nrp <- fromMaybe (Numbers Nothing Nothing) <$> optKey "numbers"
    -- the value of a retired table fails with how to rewrite it
    (_ :: Maybe EmphasisV) <- optKey "emphasis"
    Notes np nn nr nms nmf nmst nbst <-
      fmap (fromMaybe (Notes Nothing Nothing Nothing Nothing Nothing Nothing Nothing)) . optKeyOf "notes" $ \v -> do
        notes@(Notes _ _ _ size _ markStyle _) <- fromValue v
        -- two values that decide the size of the marks: neither wins (docs/adr/0177)
        case (size, markSizeConflict cstyles markStyle) of
          (Just _, Just d) -> inKey "mark-size" (failAt (keyPosition v "mark-size") (T.unpack (markSizeConflictMessage markStyle d)))
          _ -> pure notes
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
          stCharStyles = markSizeOver nms nmst (Map.unionWith overChar cstyles builtinCharStyles),
          stParaStyles = Map.unionWith overPara pstyles builtinParaStyles,
          stHeadings = Map.fromList hs,
          stComposition = comp,
          stNumbersVertical = fromMaybe (stNumbersVertical d) nv,
          stNumbersRefPage = nrp,
          stNotesPlacement = maybe (stNotesPlacement d) (\p -> if p == "chapter-end" then PlaceChapterEnd else PlaceFoot) np,
          stNotesNumbering = fromMaybe (stNotesNumbering d) nn,
          stNotesRule = nr,
          stNotesMarkSize = nms,
          stNotesMarkFormat = fromMaybe (stNotesMarkFormat d) nmf,
          stNotesMarkStyle = fromMaybe (stNotesMarkStyle d) nmst,
          stNotesBodyMarkStyle = nbst,
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
      -- the levels 1 to 6 (docs/adr/0188)
      headingLevel v (k, h) = case T.unpack k of
        [c] | c >= '1', c <= '6' -> pure (fromEnum c - fromEnum '0', h)
        _ -> inKey k (failAt (keyPosition v k) ("見出しの段は 1 から 6 のどれかです: " <> T.unpack k))

negativeDim :: Dim -> Bool
negativeDim = \case
  Abs x -> x < 0
  Zw r -> r < 0

{- | Whether a number format reads (docs/adr/0177): the slots @{n}@,
@{1}@, @{2}@ and @{chapter}@, each with a notation of the table after a
colon or none, and the escapes.
-}
validNumberFormat :: Text -> Bool
validNumberFormat = either (const False) (const True) . parseNumberFormatText

{- | What is wrong with the number format of a heading of a level
(docs/adr/0188): one that does not read, or a slot @{k}@ of a level k not
above the heading's, whose value would always be empty.
-}
headingFormatError :: Int -> Text -> Maybe Text
headingFormatError l f = case parseHeadingNumberFormatText f of
  Left _ -> Just ("番号の書式が不正です: " <> f)
  Right ps -> case [k + 1 | PNumber (SlotLevel k) _ <- ps, k + 1 >= l] of
    k : _ -> Just ("見出しの番号の書式の {" <> T.pack (show k) <> "} は上の階層の番号です。階層 " <> T.pack (show l) <> " の見出しには書けません: " <> f)
    [] -> Nothing

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
  s0 <- either (Left . map akiCode) Right (decodeStrictWith styleSchema "G03006" codeAt fid src)
  let s = sited s0 {stIndex = (\ix -> ix {ixColumnsAt = columnsAt}) <$> stIndex s0}
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
    {- each feature with where it is written, for G08103 (docs/adr/0268):
    the built-in styles have none, so the features of a style are those of
    its table, in order -}
    sited st =
      st
        { stFonts = Map.mapWithKey (\r fr -> fr {frFeatures = siteAll ["fonts", r] (frFeatures fr)}) (stFonts st),
          stCharStyles = Map.mapWithKey (\n d -> d {csFeatures = siteAll ["character-styles", n] (csFeatures d)}) (stCharStyles st),
          stParaStyles = Map.mapWithKey (\n d -> d {psFeatures = siteAll ["paragraph-styles", n] (psFeatures d)}) (stParaStyles st)
        }
    siteAll prefix fs =
      [ f {ftSite = maybe SiteNone (\(Position _ l c) -> SiteToml l c) (tree >>= \t -> checkPosition t (map ScopeKey (prefix <> ["features"]) <> [ScopeIndex i]))}
      | (i, f) <- zip [0 ..] fs
      ]
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
      -- an element of features that does not read is G03124 (docs/adr/0268)
      [ScopeKey t, _, ScopeKey "features", ScopeIndex _] | t `elem` ["fonts", "character-styles", "paragraph-styles"] -> "G03124"
      _ -> "G03006"

{- | The checks of the styles of a 'Style' (docs/adr ADR 0005, 0006, 0014):
the code, the name of the style it is about (empty when it is about no
style), the path of the value to fix in style.toml (golem-project ADR
0008) and the message. @owner@ starts the message of G03013: where the
definitions were written. Each rule is a function of its own; the order
of the diagnostics is that of the rules here (docs/adr/0173).
-}
styleChecks :: Text -> Style -> [(Text, Text, [Scope], Text)]
styleChecks owner s =
  numberFormatChecks s
    <> styleNameChecks s
    <> compositionChecks s
    <> codeStyleChecks s
    <> ruleStyleChecks s
    <> [("G03029", "", path, m) | (path, m, _) <- hiddenFolioChecks (stHiddenFolio s)]
    <> fontRoleChecks s
    <> styleReferenceChecks owner s
    <> regexStyleChecks owner s
    <> paraSizeChecks s
    <> firstLineIndentChecks s
    <> opticalKerningChecks s
    <> spineAlignChecks s
    <> markPositionChecks s

{- | G03125 (docs/adr/0269): the character style of the marks of notes in
the text (mark-style, or else note-mark) whose based-on chain resolves
position to other than normal, at the position of the definition that
writes it. [notes] places the marks.
-}
markPositionChecks :: Style -> [(Text, Text, [Scope], Text)]
markPositionChecks s =
  [ ("G03125", name, charKey definer "position", "注の印の文字スタイル " <> name <> " の position は \"normal\" だけを書けます（印の位置は [notes] で決まります）")
  | let name = stNotesMarkStyle s,
    (definer, d) <- take 1 [nd | nd@(_, d') <- namedChainOf (const csBasedOn) (stCharStyles s) name, isJust (csPosition d')],
    csPosition d /= Just P.PositionNormal
  ]

-- | The path of a key of style.toml.
styleKeys :: [Text] -> [Scope]
styleKeys = map ScopeKey

-- | The path of a key of a paragraph style.
paraKey :: Text -> Text -> [Scope]
paraKey n k = styleKeys ["paragraph-styles", n, k]

-- | The path of a key of a character style.
charKey :: Text -> Text -> [Scope]
charKey n k = styleKeys ["character-styles", n, k]

-- | The first key of two that is written, the second when neither is.
firstWritten :: (Text -> [Scope]) -> Bool -> Text -> Text -> [Scope]
firstWritten at written a b = if written then at a else at b

-- | G03006: the number formats of figures, listings, headings and folios (docs/adr/0177).
numberFormatChecks :: Style -> [(Text, Text, [Scope], Text)]
numberFormatChecks s =
  [ ("G03006", "", path, m)
  | (path, m) <-
      [ (path, "番号の書式が不正です: " <> f)
      | (path, f) <-
          (styleKeys ["figures", "number"], stFigureNumber s)
            : (styleKeys ["code", "number"], cdNumber (stCode s))
            -- the format of a folio reads as the other number formats (docs/adr/0177)
            : [(styleKeys ["masters", m, "folio", "format"], f) | (m, MasterDef {mdFolio = Just (_, f)}) <- Map.toList (stMasters s)],
        not (validNumberFormat f)
      ]
        <> [ (styleKeys ["headings", T.pack (show l), "number"], m)
           | (l, HeadingStyle {hsNumber = Just n}) <- Map.toList (stHeadings s),
             Just m <- [headingFormatError l n]
           ]
        -- a listing number has a placeholder (golem-driver ADR 0023)
        <> [(styleKeys ["code", "number"], "[code] の number には {n} などの差し込みを書きます: " <> cdNumber (stCode s)) | not ("{" `T.isInfixOf` cdNumber (stCode s))]
  ]

-- | G03006: the names of the character and paragraph styles.
styleNameChecks :: Style -> [(Text, Text, [Scope], Text)]
styleNameChecks s =
  [("G03006", n, styleKeys [kind, n], "スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: " <> n) | (kind, n) <- map ("character-styles",) (Map.keys (stCharStyles s)) <> map ("paragraph-styles",) (Map.keys (stParaStyles s)), not (validStyleName n)]

-- | G03006: the ranges of the values of [composition].
compositionChecks :: Style -> [(Text, Text, [Scope], Text)]
compositionChecks s =
  [ ("G03006", "", path, m)
  | (path, m) <-
      [ (styleKeys ["composition", "explicit-hyphen-penalty"], "explicit-hyphen-penalty は -9999 から 10000 までです: " <> T.pack (show p))
      | let p = compExplicitHyphenPenalty (stComposition s),
        p < -9999 || p > 10000
      ]
        <> [ (styleKeys ["composition", "ruby", "overhang"], "ルビのかけの量は 0 以上です（[composition.ruby] の overhang）")
           | negativeDim (rdOverhang (compRuby (stComposition s)))
           ]
  ]

{- | G03006: the paragraph style code takes four keys; background and
padding are for code only; a padding is not negative (golem-driver ADR
0017).
-}
codeStyleChecks :: Style -> [(Text, Text, [Scope], Text)]
codeStyleChecks s =
  [ ("G03006", n, path, m)
  | (n, path, m) <-
      [ ("code", paraKey "code" k, "段落スタイル code に書けるキーは " <> T.intercalate "、" codeParaKeys <> " だけです: " <> T.intercalate ", " ks)
      | Just d <- [Map.lookup "code" (stParaStyles s)],
        ks@(k : _) <- [writtenOtherKeys d]
      ]
        <> [ (n, firstWritten (paraKey n) (isJust (psBackground d)) "background" "padding", "background と padding は段落スタイル code にだけ書けます: " <> n)
           | (n, d) <- Map.toList (stParaStyles s),
             n /= "code",
             isJust (psBackground d) || isJust (psPadding d)
           ]
        <> [("code", paraKey "code" "padding", "padding は 0 以上の寸法です") | Just ParaStyleDef {psPadding = Just p} <- [Map.lookup "code" (stParaStyles s)], negativeDim p]
        -- the background and the padding of inline code are for code styles only (golem-driver ADR 0029)
        <> [ (n, firstWritten (charKey n) (isJust (csBackground d)) "background" "padding", "文字スタイルの background と padding は code と based-on で code に行き着く文字スタイルにだけ書けます: " <> n)
           | (n, d) <- Map.toList (stCharStyles s),
             not (isCodeCharStyle s n),
             isJust (csBackground d) || isJust (csPadding d)
           ]
        <> [(n, charKey n "padding", "文字スタイル " <> n <> " の padding は 0 以上の寸法です") | (n, CharStyleDef {csPadding = Just p}) <- Map.toList (stCharStyles s), negativeDim p]
        -- the wrap mark of inline code is for code styles only (golem-layout ADR 0034)
        <> [ (n, charKey n "wrap-mark", "文字スタイルの wrap-mark は code と based-on で code に行き着く文字スタイルにだけ書けます: " <> n)
           | (n, CharStyleDef {csWrapMark = Just _}) <- Map.toList (stCharStyles s),
             not (isCodeCharStyle s n)
           ]
        -- the border is for code only, its width an absolute dimension (golem-driver ADR 0023)
        <> [ (n, firstWritten (paraKey n) (isJust (psBorder d)) "border" "border-width", "border と border-width は段落スタイル code にだけ書けます: " <> n)
           | (n, d) <- Map.toList (stParaStyles s),
             n /= "code",
             isJust (psBorder d) || isJust (psBorderWidth d)
           ]
        <> [ ("code", paraKey "code" "border-width", "border-width は mm、pt、Q、H、in の寸法で書きます")
           | Just ParaStyleDef {psBorderWidth = Just w} <- [Map.lookup "code" (stParaStyles s)],
             case w of
               Zw _ -> True
               Abs x -> x < 0
           ]
  ]
  where
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
            ("baseline-shift", isJust (psBaselineShift d)),
            ("align", isJust (psAlign d)),
            ("space-before", isJust (psSpaceBefore d)),
            ("space-after", isJust (psSpaceAfter d)),
            ("end-indent", isJust (psEndIndent d))
          ],
        written
      ]

{- | G03006: paragraph rules (golem-driver ADR 0027): not on caption,
sidenote and code; with a grid, a length left by the indents greater than
0.
-}
ruleStyleChecks :: Style -> [(Text, Text, [Scope], Text)]
ruleStyleChecks s =
  [ ("G03006", n, path, m)
  | (n, path, m) <-
      [ (n, rulePath n d, "段落スタイル " <> n <> " には rule-before と rule-after を書けません")
      | (n, d) <- Map.toList (stParaStyles s),
        n `elem` ["caption", "sidenote", "code"],
        isJust (psRuleBefore d) || isJust (psRuleAfter d)
      ]
        <> case stPage s >>= pageGrid of
          Just Grid {gridFontSize = Abs fs, gridCharacters = chars} ->
            [ (n, maybe (paraKey n "rule-before") (rulePath n) (Map.lookup n (stParaStyles s)), "段落スタイル " <> n <> " の罫線の長さが 0 以下です。start-indent と end-indent を狭めてください")
            | n <- Map.keys (stParaStyles s),
              Just d <- [paraStyle s (Just n)],
              let size = maybe fs (dimToSp fs) (psSize d),
              Just r <- [join (psRuleBefore d), join (psRuleAfter d)],
              isNothing (rsLength r),
              fromIntegral chars * fs - dimToSp size (rsStartIndent r) - maybe 0 (dimToSp size) (rsEndIndent r) <= 0
            ]
          _ -> []
  ]
  where
    -- the rule written first of rule-before and rule-after
    rulePath n d = firstWritten (paraKey n) (isJust (psRuleBefore d)) "rule-before" "rule-after"

{- | G03008: font roles named outside [fonts] must exist (golem-driver ADR
0003, 0004; docs/adr ADR 0005); the role code of the styles code may be
missing: the body role sets code (golem-driver ADR 0017).
-}
fontRoleChecks :: Style -> [(Text, Text, [Scope], Text)]
fontRoleChecks s =
  [("G03008", n, path, "style.toml にないフォントの役割です: " <> r) | (n, path, r) <- roles, Map.notMember r (stFonts s)]
  where
    roles =
      [("", styleKeys ["headings", T.pack (show l), "font"], f) | (l, HeadingStyle {hsFont = Just f}) <- Map.toList (stHeadings s)]
        <> [(n, charKey n "font", f) | (n, CharStyleDef {csFont = Just f}) <- Map.toList (stCharStyles s), (n, f) /= ("code", "code")]
        <> [(n, paraKey n "font", f) | (n, ParaStyleDef {psFont = Just f}) <- Map.toList (stParaStyles s), (n, f) /= ("code", "code")]

{- | G03013: based-on names an existing style without a cycle; body has
none; colours exist (docs/adr ADR 0005). @owner@ starts the message.
-}
styleReferenceChecks :: Text -> Style -> [(Text, Text, [Scope], Text)]
styleReferenceChecks owner s =
  [("G03013", n, path, owner <> "スタイルの参照が不正です: " <> m) | (n, path, m) <- referenceChecks]
  where
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
       in [ ("", styleKeys ["notes", k], "[notes] の " <> k <> " の文字スタイルがありません: " <> n)
          | -- the character styles of the marks of notes (docs/adr/0177)
            (k, Just n) <- [("mark-style", Just (stNotesMarkStyle s)), ("body-mark-style", stNotesBodyMarkStyle s)],
            Map.notMember n cs
          ]
            <> [ (n, charKey n "based-on", "文字スタイル " <> n <> " の based-on がありません: " <> b)
               | (n, CharStyleDef {csBasedOn = Just b}) <- Map.toList cs,
                 Map.notMember b cs
               ]
            <> [(n, charKey n "based-on", "文字スタイルの based-on が循環しています: " <> T.intercalate ", " charCycle) | n <- charCycle]
            <> [(n, charKey n "color", "文字スタイル " <> n <> " の color のスウォッチがありません: " <> c) | (n, CharStyleDef {csColor = Just c}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            <> [(n, charKey n "background", "文字スタイル " <> n <> " の background のスウォッチがありません: " <> c) | (n, CharStyleDef {csBackground = Just (Just c)}) <- Map.toList cs, Map.notMember c (stSwatches s)]
            -- the swatches of the underline and the strikethrough (docs/adr/0270)
            <> [ (n, styleKeys ["character-styles", n, k, "color"], "文字スタイル " <> n <> " の " <> k <> " の color のスウォッチがありません: " <> c)
               | (n, d) <- Map.toList cs,
                 (k, Just (Just DecorationSpec {dsColor = Just c})) <- [("underline", csUnderline d), ("strikethrough", csStrikethrough d)],
                 Map.notMember c (stSwatches s)
               ]
            <> [("body", paraKey "body" "based-on", "段落スタイル body には based-on を書けません") | Just ParaStyleDef {psBasedOn = Just _} <- [Map.lookup "body" ps]]
            <> [ (n, paraKey n "based-on", "段落スタイル " <> n <> " の based-on がありません: " <> b)
               | (n, ParaStyleDef {psBasedOn = Just b}) <- Map.toList ps,
                 n `notElem` ["body", "code"],
                 Map.notMember b ps
               ]
            -- code is not a base of other styles (golem-driver ADR 0017)
            <> [ (n, paraKey n "based-on", "段落スタイル code は based-on に書けません。コードブロックの段落スタイルです: " <> n)
               | (n, ParaStyleDef {psBasedOn = Just "code"}) <- Map.toList ps,
                 n /= "code"
               ]
            -- the swatch of a background (golem-driver ADR 0017)
            <> [(n, paraKey n "background", "段落スタイル " <> n <> " の background のスウォッチがありません: " <> c) | (n, ParaStyleDef {psBackground = Just c}) <- Map.toList ps, Map.notMember c (stSwatches s)]
            <> [(n, paraKey n "border", "段落スタイル " <> n <> " の border のスウォッチがありません: " <> c) | (n, ParaStyleDef {psBorder = Just c}) <- Map.toList ps, Map.notMember c (stSwatches s)]
            -- the swatch of a rule (golem-driver ADR 0028)
            <> [("", styleKeys ["notes", "rule", "color"], "[notes.rule] の color のスウォッチがありません: " <> c) | Just RuleSpec {rsColor = Just c} <- [stNotesRule s], Map.notMember c (stSwatches s)]
            <> [ (n, styleKeys ["paragraph-styles", n, k, "color"], "段落スタイル " <> n <> " の罫線の color のスウォッチがありません: " <> c)
               | (n, d) <- Map.toList ps,
                 (k, Just (Just RuleSpec {rsColor = Just c})) <- [("rule-before", psRuleBefore d), ("rule-after", psRuleAfter d)],
                 Map.notMember c (stSwatches s)
               ]
            <> [ ("", styleKeys ["headings", T.pack (show l), k, "color"], "見出し " <> T.pack (show l) <> " の罫線の color のスウォッチがありません: " <> c)
               | (l, h) <- Map.toList (stHeadings s),
                 (k, Just RuleSpec {rsColor = Just c}) <- [("rule-before", hsRuleBefore h), ("rule-after", hsRuleAfter h)],
                 Map.notMember c (stSwatches s)
               ]
            -- the swatches of [code] and [code.colors] (golem-driver ADR 0023)
            <> [("", ScopeKey "code" : path, "[code] の " <> k <> " のスウォッチがありません: " <> c) | (k, path, c) <- codeSwatches, Map.notMember c (stSwatches s)]
            <> [(n, paraKey n "based-on", "段落スタイルの based-on が循環しています: " <> T.intercalate ", " paraCycle) | n <- paraCycle]
            -- aki sets: aki-set and based-on name a set, without a cycle (docs/adr ADR 0019)
            <> [ (n, paraKey n "aki-set", "段落スタイル " <> n <> " の aki-set のアキ量のセットがありません: " <> a)
               | (n, ParaStyleDef {psAkiSet = Just a}) <- Map.toList ps,
                 not (akiKnown a)
               ]
            <> [ ("", styleKeys ["aki-sets", n, "based-on"], "アキ量のセット " <> n <> " の based-on がありません: " <> b)
               | (n, AkiSetDef {asBasedOn = Just b}) <- Map.toList (stAkiSets s),
                 not (akiKnown b)
               ]
            <> [("", styleKeys ["aki-sets", n, "based-on"], "アキ量のセットの based-on が循環しています: " <> T.intercalate ", " akiCycle) | n <- take 1 akiCycle]
    codeSwatches =
      let c = stCode s
       in [(k, [ScopeKey k], v) | (k, Just v) <- [("line-number-color", cdLineNumberColor c), ("highlight", cdHighlight c), ("added", cdAdded c), ("removed", cdRemoved c)]]
            <> [("colors." <> k, styleKeys ["colors", k], v) | (k, v) <- Map.toList (cdColors c)]

-- | The checks of the regex styles of the paragraph styles (docs/adr ADR 0014).
regexStyleChecks :: Text -> Style -> [(Text, Text, [Scope], Text)]
regexStyleChecks owner s =
  [(code, n, path, m) | (n, ParaStyleDef {psRegexStyles = Just rs}) <- Map.toList (stParaStyles s), (i, r) <- zip [0 ..] rs, (code, path, m) <- regexStyleErrors owner s n i r]

-- | G03011: a paragraph style no larger than the grid (docs/adr ADR 0005).
paraSizeChecks :: Style -> [(Text, Text, [Scope], Text)]
paraSizeChecks s =
  [("G03011", n, paraKey n "size", "段落スタイルの文字の大きさが版面の文字の大きさを超えます: " <> n) | n <- sizeChecks]
  where
    sizeChecks = case stPage s >>= pageGrid of
      Just Grid {gridFontSize = Abs fs} ->
        [ n
        | n <- Map.keys (stParaStyles s),
          Just ParaStyleDef {psSize = Just d} <- [paraStyle s (Just n)],
          dimToSp fs d > fs
        ]
      _ -> []

{- | G03012: the first line inside the type area: indent +
first-line-indent >= 0 (docs/adr ADR 0006); zw and absolute lengths
together only with a grid.
-}
firstLineIndentChecks :: Style -> [(Text, Text, [Scope], Text)]
firstLineIndentChecks s =
  [("G03012", n, path, "段落の最初の行が版面の外に出ます。indent と first-line-indent の和を 0 以上にしてください: " <> n) | (n, path) <- indentChecks]
  where
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
       in [(n, firstWritten (paraKey n) (written n) "first-line-indent" "indent") | n <- Map.keys (stParaStyles s), Just d <- [paraStyle s (Just n)], negative d]

-- | G03021: optical kerning is a v2 item (docs/adr/0020).
opticalKerningChecks :: Style -> [(Text, Text, [Scope], Text)]
opticalKerningChecks s =
  [("G03021", n, styleKeys [kind, n, "kerning"], "v1 ではオプティカルカーニングを使えません（" <> word <> " " <> n <> " の kerning）") | (kind, word, n) <- opticals]
  where
    opticals =
      [("character-styles", "文字スタイル", n) | (n, CharStyleDef {csKerning = Just KernOptical}) <- Map.toList (stCharStyles s)]
        <> [("paragraph-styles", "段落スタイル", n) | (n, ParaStyleDef {psKerning = Just KernOptical}) <- Map.toList (stParaStyles s)]

-- | G03118: the spine is beside the lines only in horizontal writing (docs/adr/0189).
spineAlignChecks :: Style -> [(Text, Text, [Scope], Text)]
spineAlignChecks s =
  [ ("G03118", n, paraKey n "align", "縦組みの本では、段落スタイル " <> n <> " の align に " <> v <> " を書けません。ノドと小口は横組みの本でだけ使えます")
  | maybe False pageVertical (stPage s),
    (n, ParaStyleDef {psAlign = Just a}) <- Map.toList (stParaStyles s),
    (v, a') <- [("towards-spine", ParaTowardsSpine), ("away-from-spine", ParaAwayFromSpine)],
    a == a'
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
-- features, an array in style.toml, is one string of elements separated by commas in @style-def (docs/adr/0268)
charStyleKeys = scalarKeys charStyleNode <> ["features", "underline", "strikethrough"]
paraStyleKeys = scalarKeys paraStyleNode <> ["features"]
regexStyleKeys = scalarKeys regexStyleNode

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
readLocal kvs = run (Table (table [(k, value k v) | (k, v) <- kvs]))
  where
    run :: (FromValue a) => Value -> Either [(Text, Text)] a
    run v = case runMatcher (fromValue v) of
      Failure es -> Left (map message es)
      Success [] a -> Right a
      Success ws _ -> Left (map message ws)
    message (MatchMessage _ path msg) = (codeOf path, schemaMessage path msg)
    codeOf = \case
      ScopeKey k : _ | k `elem` featureKeys -> "G03021"
      -- an element of features that does not read (docs/adr/0268)
      ScopeKey "features" : ScopeIndex _ : _ -> "G03124"
      _ -> "G03006"
    -- features is one string of elements separated by commas (docs/adr/0268)
    value k v
      | k == "features" = case v of
          LocalString t -> List (map Text (T.splitOn "," t))
          LocalWord t -> List (map Text (T.splitOn "," t))
      | otherwise = tomlValue v
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
      -- the indents of caption and sidenote, as written (golem-driver ADR 0043)
      indents = [("G03006", n, captionIndentMessage n k) | (n, k) <- captionIndentKeys (lsParaStyles ls)]
   in nub (indents <> [c | c <- checksOf (withLocalStyles s ls {lsRegexStyles = Map.empty}), c `notElem` base])
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

-- ------------------------------------------------------------------ the schema

{- | The values of the enumerations of style.toml, written once for the
decoder and the schema (docs/adr ADR 0169).
-}
bindingValues, writingModeValues, lineBreaksValues, pageBreakValues, monoAlignValues, groupAlignValues, baseSpacingValues, overhangOntoValues, kinsokuValues, sideValues, markerValues, verticalValues, refPageValues, placementValues, numberingValues, leaderValues :: [Text]
bindingValues = ["right", "left"]
writingModeValues = ["vertical", "horizontal"]
lineBreaksValues = ["join", "keep"]
pageBreakValues = ["recto", "any"]
monoAlignValues = ["center", "start"]
groupAlignValues = ["1:2:1", "0:1:0", "center", "start"]
baseSpacingValues = ["1:2:1", "0:1:0", "center"]
overhangOntoValues = ["kana", "none"]
kinsokuValues = ["strict", "loose"]
sideValues = ["outside"]
markerValues = ["number", "symbol", "none"]
verticalValues = ["kanji", "kanji-digits", "tcy", "auto", "auto-digits"]
refPageValues = verticalValues <> ["sideways"]
placementValues = ["page-foot", "chapter-end"]
numberingValues = ["chapter", "file", "book"]
leaderValues = ["dots", "none"]

-- | The values of align, in the order of 'ParaAlign' (docs/adr/0189).
alignValues :: [Text]
alignValues = ["left", "center", "right", "left-justified", "center-justified", "right-justified", "fully-justified", "towards-spine", "away-from-spine"]

-- | The values of kerning (docs/adr/0020).
kerningValues :: [(Text, Kerning)]
kerningValues = [("metrics", KernMetrics), ("japanese-equal-width", KernJapaneseEqualWidth), ("none", KernNone), ("optical", KernOptical)]

-- | The values of pages of [hidden-folio] (golem-driver ADR 0021).
hiddenFolioPagesValues :: [(Text, HiddenFolioPages)]
hiddenFolioPagesValues = [("unnumbered", HiddenUnnumbered), ("all", HiddenAll)]

{- | The keys of style.toml and their values (docs/adr ADR 0169), in the
order the decoder reads them. A key the decoder reads and the schema does
not have is unknown to 'parseStyle'; a key the schema has and the decoder
does not read is caught by the test of the schema.
-}
styleSchema :: Node
styleSchema =
  NTable
    [ ("page", pageNode),
      ("fonts", NNamed (Just FontRoles) (NTable [("ja", str), ("latin", str), ("features", features)])),
      ("character-styles", NNamed (Just CharStyles) charStyleNode),
      ("paragraph-styles", NNamed (Just ParaStyles) paraStyleNode),
      ("headings", NNamed Nothing headingNode),
      ("composition", compositionNode),
      ("numbers", NTable [("vertical", enum verticalValues), ("ref-page", enum refPageValues)]),
      ("emphasis", NRejected),
      ("notes", notesNode),
      ("sidenotes", NTable [("side", enum sideValues), ("width", dim), ("gap", dim), ("font", NRejected), ("size", NRejected), ("marker", enum markerValues)]),
      ("figures", NTable [("number", str), ("wrap-gap", dim)]),
      ("color", NTable [("intent", str), ("swatches", NNamed (Just Swatches) (NTable [("cmyk", NArray int)]))]),
      ("masters", NNamed (Just Masters) masterNode),
      ("verse", NRejected),
      ("toc", NTable [("leader", enum leaderValues)]),
      ("lists", NTable [("bullets", NArray str), ("numbers", NArray str), ("gap", dim)]),
      ("aki-sets", NNamed (Just AkiSets) akiSetNode),
      ("index", NTable [("columns", int), ("column-gap", dim)]),
      ("code", codeNode),
      ("hidden-folio", NTable [("enabled", bool), ("pages", enum (map fst hiddenFolioPagesValues)), ("size", dim), ("gutter", dim)])
    ]
  where
    pageNode =
      NTable
        [ ("size", NEither [enum (map fst pageSizes), NTable [("width", dim), ("height", dim)]]),
          ("binding", enum bindingValues),
          ("writing-mode", enum writingModeValues),
          ("grid", gridNode),
          ("bleed", dim)
        ]
    gridNode =
      NTable
        [ ("font-size", dim),
          ("characters", int),
          ("lines", int),
          ("line-pitch", dim),
          ("columns", int),
          ("column-gap", dim),
          ("position", NTable [("top", dim), ("gutter", dim)])
        ]
    headingNode =
      NTable
        [ ("font", ref FontRoles),
          ("size", dim),
          ("number", str),
          ("page-break", enum pageBreakValues),
          ("lines", int),
          -- retired (golem-driver ADR 0014): G03019
          ("running-head", NRejected),
          ("rule-before", ruleOrFalseNode),
          ("rule-after", ruleOrFalseNode)
        ]
    compositionNode =
      NTable
        [ ("kinsoku", enum kinsokuValues),
          ("hanging-punctuation", bool),
          ( "ruby",
            NTable
              [ ("mono-align", enum monoAlignValues),
                ("group-align", enum groupAlignValues),
                ("base-spacing", enum baseSpacingValues),
                ("overhang", dim),
                ("overhang-onto", enum overhangOntoValues)
              ]
          ),
          ("kenten", enum kentenShapeNames),
          ("pretolerance", int),
          ("tolerance", int),
          ("emergency-stretch", dim),
          ("protrusion", bool),
          ("expansion", NTable [("limit", int), ("step", int)]),
          ("explicit-hyphen-penalty", int)
        ]
    notesNode =
      NTable
        [ ("placement", enum placementValues),
          ("numbering", enum numberingValues),
          -- the place of a rule in its column is for paragraphs and headings (golem-driver ADR 0027)
          ("rule", NTable ([kv | kv@(k, _) <- ruleKeys, k `notElem` columnKeys] <> [(k, NRejected) | k <- columnKeys])),
          ("mark-size", dim),
          ("mark-format", str),
          ("mark-style", ref CharStyles),
          ("body-mark-style", ref CharStyles)
        ]
    columnKeys = ["start-indent", "end-indent", "keep-in-column"]
    masterNode =
      NTable
        [ ( "running-head",
            NTable [("position", enum masterPositions), ("content", runningContent), ("even", runningContent), ("odd", runningContent)]
          ),
          ("folio", NTable [("position", enum masterPositions), ("content", str), ("format", str)])
        ]
    runningContent = NEither [str, NArray str]
    akiSetNode =
      NTable
        [ ("based-on", ref AkiSets),
          ( "rules",
            NArray
              ( NTable
                  [ ("before", classes (akiClassNames <> ["line-start", "paragraph-start"])),
                    ("after", classes (akiClassNames <> ["line-end"])),
                    ("optimum", str),
                    ("minimum", str),
                    ("maximum", str)
                  ]
              )
          )
        ]
    classes cs = NEither [enum cs, NArray (enum cs)]
    codeNode =
      NTable
        [ ("number", str),
          ("line-numbers", bool),
          ("line-number-color", ref Swatches),
          ("highlight", ref Swatches),
          ("added", ref Swatches),
          ("removed", ref Swatches),
          ("wrap-mark", str),
          ("continued", str),
          -- the kinds are checked by the decoder, with its own message (golem-driver ADR 0023)
          ("colors", NNamed Nothing (ref Swatches))
        ]

-- | [character-styles.<name>].
charStyleNode :: Node
charStyleNode =
  NTable
    ( [ ("based-on", ref CharStyles),
        ("font", ref FontRoles),
        ("size", dim),
        ("color", ref Swatches),
        ("synthetic-bold", bool),
        ("synthetic-italic", bool)
      ]
        <> featureNodes
        <> [ ("background", NEither [ref Swatches, NValue LFalse]),
             ("padding", dim),
             ("wrap-mark", str),
             ("no-break", bool),
             ("features", features),
             ("position", enum (map fst P.positionValues)),
             ("underline", decorationNode),
             ("strikethrough", decorationNode)
           ]
    )

-- | An underline or a strikethrough: true, false or a table (docs/adr/0270).
decorationNode :: Node
decorationNode =
  NEither
    [ bool,
      NTable
        [ ("weight", dim),
          ("offset", dim),
          ("style", enum (map fst ruleStyleNames)),
          ("dash", dim),
          ("gap", dim),
          ("color", ref Swatches)
        ]
    ]

-- | [paragraph-styles.<name>].
paraStyleNode :: Node
paraStyleNode =
  NTable
    ( [ ("based-on", ref ParaStyles),
        ("font", ref FontRoles),
        ("size", dim),
        ("line-breaks", enum lineBreaksValues),
        ("space-between", int),
        ("space-before", int),
        ("space-after", int),
        ("align", enum alignValues),
        ("indent", dim),
        ("first-line-indent", dim),
        ("end-indent", dim),
        ("regex-styles", NArray regexStyleNode),
        ("aki-set", ref AkiSets)
      ]
        <> featureNodes
        <> [ ("background", ref Swatches),
             ("padding", dim),
             ("border", ref Swatches),
             ("border-width", dim),
             ("rule-before", ruleOrFalseNode),
             ("rule-after", ruleOrFalseNode),
             ("features", features)
           ]
    )

-- | One regex style of a paragraph style (docs/adr ADR 0015).
regexStyleNode :: Node
regexStyleNode = NTable [("pattern", str), ("style", ref CharStyles)]

-- | The keys of 'featureKeysOf'.
featureNodes :: [(Text, Node)]
featureNodes = zip featureKeys [enum (map fst kerningValues), int, bool, dim]

-- | A rule spec, or false (golem-driver ADR 0027).
ruleOrFalseNode :: Node
ruleOrFalseNode = NEither [NValue LFalse, NTable ruleKeys]

-- | The keys of a rule spec (golem-driver ADR 0024, 0027, 0028).
ruleKeys :: [(Text, Node)]
ruleKeys =
  [ ("length", dim),
    ("weight", dim),
    ("space-before", dim),
    ("space-after", dim),
    ("color", ref Swatches),
    ("style", enum (map fst ruleStyleNames)),
    ("dash", dim),
    ("gap", dim),
    ("start-indent", dim),
    ("end-indent", dim),
    ("keep-in-column", bool)
  ]

-- | The OpenType features of a role or a style (docs/adr/0268).
features :: Node
features = NArray str

str, dim, int, bool :: Node
str = NValue LString
dim = NValue LDimension
int = NValue LInteger
bool = NValue LBoolean

enum :: [Text] -> Node
enum = NValue . LEnum

ref :: Namespace -> Node
ref = NValue . LRef
