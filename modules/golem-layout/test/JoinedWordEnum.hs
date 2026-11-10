-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The breaks between the boxes of a Latin word that an inline boundary
cuts (docs/adr ADR 0280): W1 and W2 on the pairs of the ADR, the smallest
input of the enumeration of the marks of citations that broke L8, the
example of a book, and W3, L1 to L13 of docs/adr/0209 with W1 and W2 on
every small input: a run of the parts of 'jwParts' with each two
neighbouring parts in the same text or across a boundary of a character
style, after 'あ' set some times and before 'い' set none or a line's
worth of times, in lines of 2 to 4 em, tier n holding the runs of n
parts.

A boundary is made by setting the parts after it in a character style
(@strong@) or out of one, by turns; the style changes nothing of the
look, so that the boxes of the two sides differ only in their pieces.
-}
module JoinedWordEnum (joinedWordTests, joinedPrDepth) where

import Data.Char (GeneralCategory (..), generalCategory, isLetter)
import Data.List (mapAccumL)
import Data.Maybe (listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.CharClass (dualJapaneseClass, isDualCharacter, spanIsJapanese)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.TestSupport.Enum
import LineBreakEnum (Setting (..), advance, composeEnv, lineText, paramsOf, placings)
import LineBreakInvariants (Breach (..), Paragraph (..), breaches, bruteLimit)
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Read (readMaybe)

-- * the paragraphs

{- | The 14 parts of the ADR, its section 3: the Latin parts, the hyphens
and dashes, the apostrophe, a Japanese character, and a soft hyphen (its
「実装しないこと」).
-}
jwParts :: [Text]
jwParts = ["a", "lime-tree", "“", "”", ".", " ", "-", "‐", "‑", "–", "—", "’", "あ", "\xAD"]

-- | A paragraph: the language span, the explicit-hyphen-penalty, the expansion, the width in em, and the parts, each with whether a boundary is before it.
data Input = Input
  { inLang :: !(Maybe Text),
    inExplicit :: !Int,
    inExpansion :: !Bool,
    inWidth :: !Int,
    inPre :: !Int,
    inRun :: ![(Text, Bool)],
    inPost :: !Int
  }
  deriving stock (Eq, Show)

-- | The setting of an input: strict, no hanging, no protrusion, the span of the input.
settingOf :: Maybe Text -> Setting
settingOf = Setting True False False

-- | The composition environment: that of 'composeEnv' with the explicit-hyphen-penalty, with the patterns or without any.
envOf :: Bool -> Maybe Text -> Int -> ComposeEnv
envOf patterns l p =
  let e = (composeEnv False (settingOf l)) {ceExplicitHyphenPenalty = p}
   in if patterns then e else e {cePatterns = const Nothing}

{- | The inlines of a run: the parts between two boundaries one text, every
other such text in the character style @strong@, the whole in the span.
-}
runInlines :: Maybe Text -> [(Text, Bool)] -> [IR.Inline]
runInlines l run = maybe texts (\t -> [IR.Lang sp t texts]) l
  where
    texts = zipWith styled [0 :: Int ..] (segments run)
    styled k t = if odd k then IR.CharStyle sp "strong" [IR.Text sp t] else IR.Text sp t
    segments = \case
      [] -> []
      (t, _) : rest -> let (same, rest') = break snd rest in T.concat (t : map fst same) : segments rest'

-- | The inlines of an input, and those with the run one text.
inputInlines :: Input -> ([IR.Inline], [IR.Inline])
inputInlines i = (around (runInlines (inLang i) (inRun i)), around (runInlines (inLang i) [(T.concat (map fst (inRun i)), False) | not (null (inRun i))]))
  where
    around xs = [IR.Text sp (T.replicate (inPre i) "あ") | inPre i > 0] <> xs <> [IR.Text sp (T.replicate (inPost i) "い") | inPost i > 0]

-- | The items of inlines.
itemsWith :: ComposeEnv -> [IR.Inline] -> [Item]
itemsWith env = fst . composeInlines env

-- * W1: the items at a boundary

{- | Where 'explicitParts' cuts a word, as the ADR reads it: after each run
of @-‐–—@ with a character before it and one after it in the word.
-}
explicitCuts :: Text -> [Int]
explicitCuts w = [end | (k, (isRun, end)) <- zip [0 :: Int ..] (zip (map fst groups) ends), isRun, k > 0, k < length groups - 1]
  where
    isExplicit c = c `elem` ("-‐–—" :: String)
    groups = [(isExplicit (T.head g), g) | g <- T.groupBy (\a b -> isExplicit a == isExplicit b) w]
    ends = drop 1 (scanl (+) 0 (map (T.length . snd) groups))

{- | The boxes of items with the index of the first character of each in
the characters of the boxes, and the items after each box up to the next
box.
-}
boxesWith :: [Item] -> [(Int, BoxContent, [Item])]
boxesWith its = go 0 (dropWhile (not . isBox) its)
  where
    go at = \case
      Box _ c : rest -> let (between, more) = break isBox rest in (at, c, between) : go (at + T.length (bcText c)) more
      _ -> []
    isBox = \case
      Box {} -> True
      _ -> False

{- | The class of a character for the prohibitions across a written hyphen
(golem-layout ADR 0028): a character of both scripts in a Latin span by
its Japanese class (docs/adr/0211); an apostrophe at the start of a Latin
word with a letter after it is Latin (golem-layout ADR 0030).
-}
classIn :: BoxContent -> Char -> CharClass
classIn c ch
  | isDualCharacter ch && maybe False (not . spanIsJapanese) (lkLang (bcLook c)) = dualJapaneseClass ch
  | otherwise = lookClass (bcLook c) ch

{- | The class of the first character of a box, the box of a Latin word
after it in the joined word given: an apostrophe at the start of a Latin
word, with a letter or a digit after it in the joined word (its combining
characters left out), is Latin (golem-layout ADR 0030, docs/adr ADR 0283).
-}
startClassOf :: BoxContent -> Maybe BoxContent -> Maybe CharClass
startClassOf c next = case T.unpack (baseText (bcText c)) of
  '\x2019' : rest | Just n <- nextOf rest, isLetter n || generalCategory n == DecimalNumber -> Just Western
  ch : _ -> Just (classIn c ch)
  [] -> Nothing
  where
    nextOf = \case
      n : _ -> Just n
      [] -> next >>= fmap fst . T.uncons . baseText . bcText
    baseText t = let b = T.dropWhileEnd isExtending t in if T.null b then t else b

{- | W1: the items between two neighbouring boxes of a Latin word that the
boundaries given (indices among the characters of the boxes) fall
between are none, or one penalty of the explicit-hyphen-penalty of the
kind of an explicit hyphen, which is there where the boundary is a cut of
the joined word, the penalty is less than 10000 and no prohibition of
golem-layout ADR 0028 applies, and only there. The joined word is the run
of Latin boxes around the boundary with nothing but penalties between
them.
-}
w1Boundary :: Bool -> Int -> [Int] -> [Item] -> [Violation]
w1Boundary strict p bounds its =
  [ Violation "W1" ("at " <> show (bcText a) <> " | " <> show (bcText b) <> " in " <> show word <> ": " <> show between <> ", not " <> show want)
  | (k, ((at, a, between), (bt, b, _))) <- zip [0 :: Int ..] (zip bs (drop 1 bs)),
    bt `elem` bounds,
    at + T.length (bcText a) == bt,
    bcExpandable a && bcExpandable b,
    let word = joined k
        cut = (bt - wordStart k) `elem` explicitCuts word
        want = [Penalty 0 p ExplicitHyphen | cut, p < infPenalty, not (prohibited k a b)],
    map keyOf between /= map keyOf want
  ]
  where
    bs = boxesWith its
    -- whether box j and box j + 1 are of one word: both Latin, only penalties between them
    linked j = case (drop j bs, drop (j + 1) bs) of
      ((_, a, between) : _, (_, b, _) : _) -> bcExpandable a && bcExpandable b && all isPenalty between
      _ -> False
    isPenalty = \case
      Penalty _ q _ -> q > negate infPenalty
      _ -> False
    -- the boxes of the word the boundary after box k is in
    span' k =
      let first = k - length (takeWhile linked [k - 1, k - 2 .. 0])
          end = k + 1 + length (takeWhile linked [k + 1 .. length bs - 2])
       in take (end - first + 1) (drop first bs)
    joined k = T.concat [bcText c | (_, c, _) <- span' k]
    wordStart k = case span' k of
      (s, _, _) : _ -> s
      [] -> 0
    prohibited k a b =
      let pk = classIn a <$> lastOf a
          ck = startClassOf b (if linked (k + 1) then (\(_, d, _) -> d) <$> listToMaybe (drop (k + 2) bs) else Nothing)
       in maybe False (lineStartProhibited strict) ck || maybe False lineEndProhibited pk || (pk == Just Inseparable && ck == Just Inseparable)
    lastOf c = snd <$> T.unsnoc (bcText c)

{- | The boundaries of a run between two characters of boxes, as indices
among the characters of the boxes of the paragraph: spaces and soft
hyphens make no box, and a boundary next to one is not between two boxes.
-}
boundsOf :: Int -> [(Text, Bool)] -> [Int]
boundsOf pre run =
  [ pre + n
  | (n, before, (t, True)) <- zip3 (drop 1 starts) (scanl1 (<>) (map fst run)) (drop 1 run),
    maybe False (not . gap . snd) (T.unsnoc before),
    maybe False (not . gap . fst) (T.uncons t)
  ]
  where
    gap c = c == ' ' || c == '\xAD'
    starts = scanl (+) 0 [T.length (T.filter (not . gap) t) | (t, _) <- run]

-- * W2: the breaks of the run as one text

{- | The breaks of items, each at the index among the characters of the
boxes before it: a penalty less than 10000 with its penalty and kind, a
glue after a box but the glue that fills the last line.
-}
breaksOf :: [Item] -> [(Int, Int, Int)]
breaksOf its = concat (snd (mapAccumL step (0, False) its))
  where
    step (at, afterBox) = \case
      Box _ c -> ((at + T.length (bcText c), True), [])
      Penalty _ q h | q < infPenalty -> ((at, False), [(at, q, hyphenKind h)])
      Penalty {} -> ((at, False), [])
      Glue _ y _ _ _ | afterBox && y < filStretch -> ((at, False), [(at, -1, -1)])
      Glue {} -> ((at, False), [])

{- | Whether each character of the boxes is in a box of a Latin word, in
order: the same for the paragraph split at boundaries and for it with the
run one text (E1 of docs/adr ADR 0283), outside a language span a
character of both scripts joining a Latin word by the nearest character
in the run of the characters of the paragraph.
-}
latinMask :: [Item] -> [Bool]
latinMask its = concat [replicate (T.length (bcText c)) (bcExpandable c) | Box _ c <- its]

-- | E1 of docs/adr ADR 0283: the same characters are in Latin words split at boundaries and as one text.
e1Same :: [Item] -> [Item] -> [Violation]
e1Same its one
  | latinMask its == latinMask one = []
  | otherwise = [Violation "E1" ("the characters in Latin words are " <> show (latinMask its) <> ", as one text " <> show (latinMask one))]

{- | W2 as E2 of docs/adr ADR 0283 widens it: the breaks of the paragraph
at every position are those of it with the run one text.
-}
w2Same :: [Item] -> [Item] -> [Violation]
w2Same its one
  | breaksOf its == breaksOf one = []
  | otherwise = [Violation "W2" ("the breaks are " <> show (breaksOf its) <> ", as one text " <> show (breaksOf one))]

-- * the predicates on an input

-- | What the line breaking reads of an item.
keyOf :: Item -> (Int, Sp, Sp, Sp, Text, Int, Int)
keyOf = \case
  Box w c -> (0, w, 0, 0, bcText c, 0, 0)
  Glue w y z _ _ -> (1, w, y, z, "", 0, 0)
  Penalty w q h -> (2, w, 0, 0, "", q, hyphenKind h)

hyphenKind :: Hyphen -> Int
hyphenKind = \case
  NoHyphen -> 0
  PatternHyphen _ -> 1
  ExplicitHyphen -> 2
  WrapMark _ -> 3
  SoftHyphen _ -> 4

-- | The paragraph of an input, with the patterns of 'composeEnv'.
paragraphOf :: Input -> Paragraph
paragraphOf i =
  let its = itemsWith (envOf True (inLang i) (inExplicit i)) (fst (inputInlines i))
      s = settingOf (inLang i)
      ps = paramsOf s (inExpansion i) its
      width = fromIntegral (inWidth i) * fs
   in Paragraph
        { pText = T.replicate (inPre i) "あ" <> T.concat (map fst (inRun i)) <> T.replicate (inPost i) "い",
          pCode = "",
          pSize = fs,
          pWidth = width,
          pStrict = True,
          pItems = its,
          pParams = ps,
          pBreaks = breakParagraph ps (const width) its,
          pAdvance = advance,
          pNumberUnit = infPenalty
        }

{- | The violations of an input: L1 to L13 of docs/adr/0209 and W1 with the
patterns, W1, E1 and W2 without them (E1 and E2 of docs/adr ADR 0283); W2
where no soft hyphen is next to a boundary (docs/adr ADR 0280, its
「実装しないこと」).
-}
violations :: Input -> [Violation]
violations i =
  let p = paragraphOf i
      (split, one) = inputInlines i
      bare = envOf False (inLang i) (inExplicit i)
      itsBare = itemsWith bare split
      bounds = boundsOf (inPre i) (inRun i)
   in [Violation (show (breachOf b)) (show (breachLine b) <> ": " <> breachWhy b) | b <- breaches bruteLimit p, not (shyAtBoundary (inRun i)) || show (breachOf b) == "L8"]
        <> w1Boundary True (inExplicit i) bounds (pItems p)
        <> w1Boundary True (inExplicit i) bounds itsBare
        <> e1Same itsBare (itemsWith bare one)
        <> (if shyAtBoundary (inRun i) then [] else w2Same itsBare (itemsWith bare one))

{- | Whether a soft hyphen is next to a boundary: only L8 and W1 are
checked on such an input (the ADR, its 「実装しないこと」). The predicates
of the soft hyphens (L9 as I3 of docs/adr ADR 0272 widens it, I4) read
the soft hyphens in the text of the paragraph, where one before or after
a boundary is inside a word; the composition reads the word of each
inline, where it is at an end of it (see the pull request of the ADR).
-}
shyAtBoundary :: [(Text, Bool)] -> Bool
shyAtBoundary r = or [b && (t == "\xAD" || p == "\xAD") | ((p, _), (t, b)) <- zip r (drop 1 r)]

-- | The inputs of a run: every span and penalty, placing in lines of 2 to 4 em and expansion.
inputsOf :: [(Text, Bool)] -> [Input]
inputsOf run =
  [ Input l p e w pre run post
  | l <- [Nothing, Just "en", Just "ja"],
    p <- [50, 10000],
    (pre, post, ws) <- placings 4,
    w <- ws,
    e <- [False, True]
  ]

{- | Every input, tier n holding those of the runs of n parts: each part
after the first with a boundary before it or not.
-}
inputT :: Tiers Input
inputT =
  let Tiers xss = listsOf (Tiers [[(t, b) | t <- jwParts, b <- [False, True]]])
   in Tiers (map (concatMap inputsOf . filter (\r -> not (boundaryFirst r) && not (spaceAtBoundary r))) xss)
  where
    boundaryFirst = \case
      (_, True) : _ -> True
      _ -> False
    -- a boundary next to a space: two spaces of two inlines are two glues, a bug of its own (see the pull request of the ADR)
    spaceAtBoundary r = or [b && (t == " " || p == " ") | ((p, _), (t, b)) <- zip r (drop 1 r)]

-- | The parts of the runs: GOLEM_ENUM_JOINED_DEPTH, or 'joinedPrDepth' on pull requests.
depthOf :: IO Int
depthOf =
  lookupEnv "GOLEM_ENUM_JOINED_DEPTH" >>= \case
    Nothing -> pure joinedPrDepth
    Just "" -> pure joinedPrDepth
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure ("GOLEM_ENUM_JOINED_DEPTH is not a whole number of 0 or more: " <> show s)

-- | The parts of the runs of pull requests.
joinedPrDepth :: Int
joinedPrDepth = 2

-- * the pairs of the ADR

-- | The pairs of 「今の振る舞い」 and of the table of the boundaries, the part before a boundary and the part after it.
pairs :: [(Text, Text)]
pairs =
  [ ("a—", "b"),
    ("a—", "[1,"),
    ("a–", "b"),
    ("a‐", "b"),
    ("a‑", "b"),
    ("a-", "b"),
    ("a", "—b"),
    ("a", "–b"),
    ("a", "‐b"),
    ("a", "-b"),
    ("a’", "s"),
    ("a”", "b"),
    ("a", "’s"),
    ("a", "“b"),
    ("ab", "cd"),
    ("a.", "b"),
    ("a,", "b"),
    ("a——", "b"),
    ("a-", "-b"),
    ("a—", "”b"),
    ("a—", "’s"),
    ("a—", "“b"),
    ("—", "b"),
    ("あ", "—b")
  ]

-- | A pair in a span with a penalty: the two inlines and the run as one text.
pairInput :: Maybe Text -> Int -> (Text, Text) -> Input
pairInput l p (a, b) = Input l p False 4 0 [(a, False), (b, True)] 0

-- | The three boxes a, — and b.
threeBoxes :: Maybe Text -> Int -> Input
threeBoxes l p = Input l p False 4 0 [("a", False), ("—", True), ("b", True)] 0

-- | Every pair and the three boxes in every span with either penalty.
pairInputs :: [Input]
pairInputs = [f l p | l <- [Nothing, Just "en", Just "ja"], p <- [50, 10000], f <- threeBoxes : map (\x l' p' -> pairInput l' p' x) pairs]

-- | W1 of an input without the patterns.
w1Of :: Input -> [Violation]
w1Of i = w1Boundary True (inExplicit i) (boundsOf (inPre i) (inRun i)) (itemsWith (envOf False (inLang i) (inExplicit i)) (fst (inputInlines i)))

-- | W2 of an input without the patterns.
w2Of :: Input -> [Violation]
w2Of i = let bare = envOf False (inLang i) (inExplicit i); (split, one) = inputInlines i in e1Same (itemsWith bare split) (itemsWith bare one) <> w2Same (itemsWith bare split) (itemsWith bare one)

-- | The violations of each input of a list, with the input.
failing :: (Input -> [Violation]) -> [Input] -> Assertion
failing f is = case [(i, vs) | i <- is, let vs = f i, not (null vs)] of
  [] -> pure ()
  found -> assertFailure (unlines [show (inLang i, inExplicit i, map fst (inRun i)) <> ": " <> unwords [violationRule v <> ": " <> violationDetail v | v <- vs] | (i, vs) <- take 10 found] <> show (length found) <> " inputs")

-- | L8 of a paragraph.
l8Of :: Paragraph -> [Breach]
l8Of p = [b | b <- breaches bruteLimit p, show (breachOf b) == "L8"]

-- * the characters of both scripts across boundaries (docs/adr ADR 0283)

-- | A text, and a text in the character style @strong@: a boundary on either side.
txt, strong :: Text -> IR.Inline
txt = IR.Text sp
strong t = IR.CharStyle sp "strong" [IR.Text sp t]

{- | The paragraph as one text: the character style @strong@ taken off,
and the texts next to each other joined; the other inlines as they are.
-}
oneText :: [IR.Inline] -> [IR.Inline]
oneText = joinTexts . concatMap unstyle
  where
    unstyle = \case
      IR.CharStyle _ "strong" xs -> concatMap unstyle xs
      x -> [x]
    joinTexts = \case
      IR.Text _ a : IR.Text _ b : rest -> joinTexts (IR.Text sp (a <> b) : rest)
      x : rest -> x : joinTexts rest
      [] -> []

-- | The environment of the boundaries: that of 'envOf' without the patterns, the character style @code@ code, the mark of a citation of key a 1.
bothEnv :: Maybe Text -> ComposeEnv
bothEnv l =
  (envOf False l 50)
    { ceRestyle = \lk -> \case
        IR.CharStyle _ "code" _ -> lk {lkCode = True}
        _ -> lk,
      ceCiteNumber = \_ k -> if k == "a" then Just 1 else Nothing
    }

-- | E1 of the inlines of a paragraph: the characters in Latin words are those of it as one text.
e1Of :: Maybe Text -> [IR.Inline] -> [Violation]
e1Of l is = e1Same (itemsWith (bothEnv l) (inSpan l is)) (itemsWith (bothEnv l) (inSpan l (oneText is)))

inSpan :: Maybe Text -> [IR.Inline] -> [IR.Inline]
inSpan l is = maybe is (\x -> [IR.Lang sp x is]) l

-- | The inlines that stop the search for the nearest character (the ADR, its section 1), each with a name.
stoppers :: [(String, IR.Inline)]
stoppers =
  [ ("ruby", IR.Ruby sp () [IR.RubySegment [IR.Text sp "漢"] (Just "かん")]),
    ("code", IR.CharStyle sp "code" [IR.Text sp "x"]),
    ("the mark of a note", IR.Note sp 1 (IR.noteBody sp [IR.Text sp "n"])),
    ("the mark of a citation", IR.Cite sp [IR.CiteItem "a" Nothing [] []])
  ]

-- | An index mark: an anchor, no items.
indexMark :: IR.Inline
indexMark = IR.IndexMark sp (IR.IndexEntry ["x"] [] IR.IndexPoint)

{- | The rows of 「今の振る舞い」 of the ADR, and the places of a character
of both scripts against the nearest character across a boundary: a Latin
or a Japanese character, a space, the end of the paragraph, the inlines
that stop the search, in no span, [lang en] and [lang ja] (the far
character's or the dash's), an index mark between them, one character of
both scripts skipped and two boundaries crossed.
-}
e1Cases :: [(Maybe Text, [IR.Inline])]
e1Cases =
  [(Nothing, r) | r <- rows]
    <> [(Just "en", r) | r <- rows]
    <> [(l, r) | l <- [Nothing, Just "en", Just "ja"], far <- fars, r <- placed far]
  where
    rows =
      [ [txt "a", strong "—", txt "b"],
        [txt "aaaa", strong "—", txt "b"],
        [txt "a", strong "“", txt "b"],
        [txt "x “", strong "Ham", txt "” y"],
        [txt "aaa ’", strong "tis"],
        [txt "x ’", strong "90"],
        [txt "a", strong "“", txt "—", strong "b"],
        [txt "a", strong "“", strong "—", txt "b"],
        [txt "あ", strong "“", txt "—", strong "b"]
      ]
    fars =
      [[txt "b"], [txt "あ"], [txt " "], [], [IR.Lang sp "en" [txt "b"]], [IR.Lang sp "ja" [txt "b"]], [IR.Lang sp "ja" [txt "あ"]], [indexMark, txt "b"]]
        <> [[x] | (_, x) <- stoppers]
        <> [[x, txt "b"] | (_, x) <- stoppers]
    placed far =
      [ far <> [strong "—あ"],
        [strong "あ—"] <> reverse far,
        far <> [strong "—"] <> reverse far,
        far <> [strong "—"],
        [strong "—"] <> reverse far,
        far <> [IR.CharStyle sp "strong" [IR.Lang sp "en" [txt "—"]]],
        far <> [IR.CharStyle sp "strong" [IR.Lang sp "ja" [txt "—"]]] <> reverse far,
        far <> [strong "“", strong "—あ"]
      ]

-- | The lines of the inlines of a paragraph in a span, in lines of the width in em given.
linesIn :: Maybe Text -> Int -> [IR.Inline] -> [Text]
linesIn l w is =
  let its = itemsWith (bothEnv l) (inSpan l is)
   in map lineText (brLines (breakParagraph (paramsOf (settingOf l) False its) (const (fromIntegral w * fs)) its))

-- | Whether the box of a lone dash among the items of inlines is that of a Latin word.
dashIsLatin :: [IR.Inline] -> [Bool]
dashIsLatin is = [bcExpandable c | Box _ c <- itemsWith (bothEnv Nothing) is, bcText c == "—"]

bothScriptsTests :: TestTree
bothScriptsTests =
  testGroup
    "the roles of the characters of both scripts across inline boundaries (docs/adr ADR 0283)"
    [ testCase "E1: the rows of the ADR and the places of a character of both scripts put the same characters in Latin words as one text" $
        case [(l, is, vs) | (l, is) <- e1Cases, let vs = e1Of l is, not (null vs)] of
          [] -> pure ()
          found -> assertFailure (unlines [show l <> " " <> show is <> ": " <> unwords (map violationDetail vs) | (l, is, vs) <- take 8 found] <> show (length found) <> " of " <> show (length e1Cases)),
      testCase "E1: a, — and b in three boxes, outside a span, are one Latin word as a—b is" $
        dashIsLatin [txt "a", strong "—", txt "b"] @?= [True],
      testCase "E2: W2 at every position, the narrowings of docs/adr ADR 0280 lifted, on a, — and b, and on ’ and tis" $ do
        failing w2Of [Input l p False 4 0 [("a", False), ("—", True), ("b", True)] 0 | l <- [Nothing, Just "en", Just "ja"], p <- [50, 10000]]
        failing w2Of [Input l p False 4 0 [("aaa ", False), ("’", False), ("tis", True)] 0 | l <- [Nothing, Just "en", Just "ja"], p <- [50, 10000]]
        failing w2Of [Input l p False 4 0 [("’", False), ("a", True)] 0 | l <- [Nothing, Just "en", Just "ja"], p <- [50, 10000]],
      testCase "E3: aaa ’ and [strong: tis] in lines of 2 em are aaa and ’tis, in no span and in [lang en]" $ do
        linesIn Nothing 2 [txt "aaa ’", strong "tis"] @?= ["aaa", "’tis"]
        linesIn (Just "en") 2 [txt "aaa ’", strong "tis"] @?= ["aaa", "’tis"],
      testCase "E3: aaa ’ and [strong: 90] in lines of 2 em are aaa and ’90, in no span and in [lang en]" $ do
        linesIn Nothing 2 [txt "aaa ’", strong "90"] @?= ["aaa", "’90"]
        linesIn (Just "en") 2 [txt "aaa ’", strong "90"] @?= ["aaa", "’90"],
      testCase "E3: aaa ’ and [strong: .] do not break at the space nor before the full stop: the apostrophe is a closing bracket" $ do
        take 1 (linesIn Nothing 2 [txt "aaa ’", strong "."]) @?= ["aaa’."]
        take 1 (linesIn (Just "en") 2 [txt "aaa ’", strong "."]) @?= ["aaa’."],
      testCase "E3: an apostrophe alone after a space with no box after it is a closing bracket, as before" $
        length (linesIn (Just "en") 2 [txt "aaa ’"]) @?= 1,
      testCase "E4: ruby, code, the marks of notes and citations and a space between a and [strong: —] stop the search: b or あ beyond them changes nothing" $
        sequence_
          [ assertEqual name (dashIsLatin [txt "b", x, strong "—"]) (dashIsLatin [txt "あ", x, strong "—"])
          | (name, x) <- stoppers <> [("a space", txt " ")]
          ],
      testCase "E4: an index mark between b and [strong: —] does not stop it: the dash joins b" $ do
        dashIsLatin [txt "b", indexMark, strong "—"] @?= [True]
        dashIsLatin [txt "あ", indexMark, strong "—"] @?= [False]
    ]

joinedWordTests :: TestTree
joinedWordTests =
  testGroup
    "the breaks between the boxes of a Latin word follow the joined word (docs/adr ADR 0280)"
    [ bothScriptsTests,
      testCase "L8: the smallest input of the marks of citations, a, — and [cite a page=5] in lines of 2 em, breaks only where L8 allows" $ do
        let cite = IR.Cite sp [IR.CiteItem "a" (Just (IR.Locator IR.LocatorPage (IR.LocNumber 5))) [] []]
            env = (composeEnv False (settingOf Nothing)) {ceCiteNumber = \_ k -> if k == "a" then Just 1 else Nothing}
            its = itemsWith env [IR.Text sp "a—", cite]
            ps = paramsOf (settingOf Nothing) False its
            br = breakParagraph ps (const (2 * fs)) its
            p = Paragraph "a—[1, p. 5]" "" fs (2 * fs) True its ps br advance infPenalty
        map breachWhy (l8Of p) @?= [],
      testCase "L8: the example of a book, あ eleven times, [strong: aaaa]—bbbbbbbbbb in lines of 14 em: no line starts with the dash" $ do
        let is = [IR.Text sp (T.replicate 11 "あ"), IR.CharStyle sp "strong" [IR.Text sp "aaaa"], IR.Text sp "—bbbbbbbbbb"]
            its = itemsWith (composeEnv False (settingOf Nothing)) is
            ps = paramsOf (settingOf Nothing) False its
            br = breakParagraph ps (const (14 * fs)) its
            p = Paragraph (T.replicate 11 "あ" <> "aaaa—bbbbbbbbbb") "" fs (14 * fs) True its ps br advance infPenalty
        map breachWhy (l8Of p) @?= []
        filter ("—" `T.isPrefixOf`) (map lineText (brLines br)) @?= [],
      testCase "W1: the items between the boxes of every pair of the ADR, in no span, [lang en] and [lang ja], with explicit-hyphen-penalty 50 and 10000" $
        failing w1Of pairInputs,
      testCase "W2: every pair of the ADR has the breaks of the run as one text" $
        failing w2Of pairInputs,
      testCase "E1: no pair of docs/adr ADR 0280 has a character of both scripts that a boundary makes Japanese, a lone dash among them" $
        [map fst (inRun i) | i <- pairInputs, let bare = envOf False (inLang i) (inExplicit i); (split, one) = inputInlines i, latinMask (itemsWith bare split) /= latinMask (itemsWith bare one)]
          @?= [],
      testCase "W1 and W2: the explicit hyphen at a boundary, a— | b, and at the head of a box, a | —b" $ do
        let itemsOf' x = itemsWith (envOf False Nothing 50) (fst (inputInlines (pairInput Nothing 50 x)))
            boxes its = [bcText c | Box _ c <- its]
            pens its = [(q, hyphenKind h) | Penalty _ q h <- its, q < infPenalty, q > negate infPenalty]
        boxes (itemsOf' ("a—", "b")) @?= ["a—", "b"]
        pens (itemsOf' ("a—", "b")) @?= [(50, 2)]
        boxes (itemsOf' ("a", "—b")) @?= ["a", "—", "b"]
        pens (itemsOf' ("a", "—b")) @?= [(50, 2)],
      testCase "W1 and W2: predicate tests, the items of a penalty 0 between a— and b break both" $ do
        let i = pairInput Nothing 50 ("a—", "b")
            (split, one) = inputInlines i
            bare = envOf False Nothing 50
            its = itemsWith bare split
            -- the penalty 0 before the ADR between the two boxes
            before = concatMap (\case Penalty _ 50 ExplicitHyphen -> [Penalty 0 0 NoHyphen]; x -> [x]) its
        map violationRule (w1Boundary True 50 (boundsOf 0 (inRun i)) before) @?= ["W1"]
        map violationRule (w2Same before (itemsWith bare one)) @?= ["W2"],
      testCase "E1 and E2: predicate tests, the items of a, — and b with the dash a Japanese character, as before docs/adr ADR 0283, break E1; a penalty 0 for the explicit hyphen breaks E2" $ do
        let bare = envOf False Nothing 50
            one = itemsWith bare [IR.Text sp "a—b"]
            -- the dash Japanese, as it was outside a span before the ADR: in a Japanese span
            before = itemsWith bare [IR.Text sp "a", IR.CharStyle sp "strong" [IR.Lang sp "ja" [IR.Text sp "—"]], IR.Text sp "b"]
            zeroed = concatMap (\case Penalty _ 50 ExplicitHyphen -> [Penalty 0 0 NoHyphen]; x -> [x]) one
        map violationRule (e1Same before one) @?= ["E1"]
        map violationRule (w2Same before one) @?= ["W2"]
        map violationRule (w2Same zeroed one) @?= ["W2"],
      testCase "W3: L1 to L13 of docs/adr/0209, W1 and W2 hold for every input up to GOLEM_ENUM_JOINED_DEPTH parts" $ do
        depth <- depthOf
        case checkAllPar depth inputT violations of
          Failed k i vs -> assertFailure ("the smallest input that breaks an invariant has " <> show k <> " parts: " <> show i <> "\n" <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])
          Passed _ -> pure ()
    ]
