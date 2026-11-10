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
module JoinedWordEnum (joinedWordTests) where

import Data.Char (isLetter)
import Data.List (mapAccumL)
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

startClassOf :: BoxContent -> Maybe CharClass
startClassOf c = case T.unpack (bcText c) of
  '\x2019' : n : _ | isLetter n -> Just Western
  ch : _ -> Just (classIn c ch)
  [] -> Nothing

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
        want = [Penalty 0 p ExplicitHyphen | cut, p < infPenalty, not (prohibited a b)],
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
    prohibited a b =
      let pk = classIn a <$> lastOf a
          ck = startClassOf b
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
      Glue _ y _ | afterBox && y < filStretch -> ((at, False), [(at, -1, -1)])
      Glue {} -> ((at, False), [])

{- | Whether each character of the boxes is in a box of a Latin word, in
order. Outside a language span a character of both scripts joins a Latin
word only by the letters of its own text (golem-layout ADR 0008), so that
a boundary next to it can make it a Japanese character: W2 compares two
paragraphs whose Latin words have the same characters.
-}
latinMask :: [Item] -> [Bool]
latinMask its = concat [replicate (T.length (bcText c)) (bcExpandable c) | Box _ c <- its]

{- | W2: the breaks of the paragraph inside its Latin words (a character
of a Latin word on either side) are those of it with the run one text,
where the boundaries leave the Latin words their characters. The breaks
between a Latin word and a Japanese character are not the ADR's (its
「実装しないこと」): a box of an apostrophe alone after a boundary is a
closing bracket to the character before it in a Latin span, the
apostrophe of a word in one text (golem-layout ADR 0030).
-}
w2Same :: [Item] -> [Item] -> [Violation]
w2Same its one
  | mask /= latinMask one = []
  | inside its == inside one = []
  | otherwise = [Violation "W2" ("the breaks inside Latin words are " <> show (inside its) <> ", as one text " <> show (inside one))]
  where
    mask = latinMask its
    inside xs = [b | b@(at, _, _) <- breaksOf xs, at > 0, at < length mask, mask !! (at - 1), mask !! at]

-- * the predicates on an input

-- | What the line breaking reads of an item.
keyOf :: Item -> (Int, Sp, Sp, Sp, Text, Int, Int)
keyOf = \case
  Box w c -> (0, w, 0, 0, bcText c, 0, 0)
  Glue w y z -> (1, w, y, z, "", 0, 0)
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
patterns, W1 and W2 without them; W2 where no part is a soft hyphen (the
ADR, its 「実装しないこと」).
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
        <> (if any ((== "\xAD") . fst) (inRun i) then [] else w2Same itsBare (itemsWith bare one))

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
w2Of i = let bare = envOf False (inLang i) (inExplicit i); (split, one) = inputInlines i in w2Same (itemsWith bare split) (itemsWith bare one)

-- | The violations of each input of a list, with the input.
failing :: (Input -> [Violation]) -> [Input] -> Assertion
failing f is = case [(i, vs) | i <- is, let vs = f i, not (null vs)] of
  [] -> pure ()
  found -> assertFailure (unlines [show (inLang i, inExplicit i, map fst (inRun i)) <> ": " <> unwords [violationRule v <> ": " <> violationDetail v | v <- vs] | (i, vs) <- take 10 found] <> show (length found) <> " inputs")

-- | L8 of a paragraph.
l8Of :: Paragraph -> [Breach]
l8Of p = [b | b <- breaches bruteLimit p, show (breachOf b) == "L8"]

joinedWordTests :: TestTree
joinedWordTests =
  testGroup
    "the breaks between the boxes of a Latin word follow the joined word (docs/adr ADR 0280)"
    [ testCase "L8: the smallest input of the marks of citations, a, — and [cite a page=5] in lines of 2 em, breaks only where L8 allows" $ do
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
      testCase "W2: the pairs whose boundary makes a character of both scripts Japanese, outside a span: a lone dash" $
        [map fst (inRun i) | i <- pairInputs, let bare = envOf False (inLang i) (inExplicit i); (split, one) = inputInlines i, latinMask (itemsWith bare split) /= latinMask (itemsWith bare one), inExplicit i == 50]
          @?= [["a", "—", "b"], ["—", "b"]],
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
      testCase "W3: L1 to L13 of docs/adr/0209, W1 and W2 hold for every input up to GOLEM_ENUM_JOINED_DEPTH parts" $ do
        depth <- depthOf
        case checkAllPar depth inputT violations of
          Failed k i vs -> assertFailure ("the smallest input that breaks an invariant has " <> show k <> " parts: " <> show i <> "\n" <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])
          Passed _ -> pure ()
    ]
