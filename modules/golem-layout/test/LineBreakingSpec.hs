{- | Invariants of Knuth–Plass line breaking (golem-layout ADR 0001) as
properties: when every word fits the measure, no line is overfull and
no set line reaches past its target length.
-}
module LineBreakingSpec (lineBreakingTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, look0, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Align (LineAlign (..), ParaAlign (..), breakAligned, lineShift)
import Golem.Layout.Japanese (ComposeEnv (..), composeInlines, defaultComposeEnv)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (LinkTarget (..), Look (..), noBoxSource)
import Golem.Length qualified as L
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import KnuthPlassReference (finish, referenceLook)
import LineBreakEnum (Input (..), Setting (..), advance, breakInput, composeEnv, inlinesOf, itemsOf, lineText, paramsOf)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

-- | Words of the given widths separated by glue of width 6, stretch 3 and shrink 2.
paragraph :: [Sp] -> [Item]
paragraph ws = concat [Box w (BoxContent "w" False 0 0 0 referenceLook 0 0 [] 0 0 noBoxSource Nothing noLeaf 0) : [Glue 6 3 2 | i < length ws - 1] | (i, w) <- zip [0 :: Int ..] ws] <> finish

-- | Where the last box of a set line ends.
lastBoxEnd :: Line -> Sp
lastBoxEnd l = maximum (0 : [x + w | (Box w _, x) <- placeLine l])

-- | A length from @lo@ to @hi@ sp.
genSp :: Sp -> Sp -> Gen Sp
genSp lo hi = Sp <$> Gen.integral (Range.linear (unSp lo) (unSp hi))

-- | A paragraph whose words all fit a measure of 60 to 200.
genFitting :: Gen ([Sp], Sp)
genFitting = do
  target <- genSp 60 200
  ws <- Gen.list (Range.linear 1 25) (genSp 1 target)
  pure (ws, target)

-- | A paragraph with at least one word wider than the measure of 60 to 200 (docs/adr/0067).
genWithWide :: Gen ([Sp], Sp)
genWithWide = do
  target <- genSp 60 200
  ws <- Gen.list (Range.linear 0 12) (genSp 1 (2 * target))
  wide <- genSp (target + 1) (3 * target)
  at <- Gen.int (Range.linear 0 (length ws))
  let (before, rest) = splitAt at ws
  pure (before <> [wide] <> rest, target)

lineBreakingTests :: TestTree
lineBreakingTests =
  testGroup
    "line breaking invariants (golem-layout ADR 0001)"
    [ testProperty "when every word fits the measure, no line is overfull" $ property $ do
        (ws, target) <- forAll genFitting
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        filter lineOverfull (brLines r) === [],
      testProperty "when every word fits the measure, no set line ends past it" $ property $ do
        (ws, target) <- forAll genFitting
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        filter (> target) (map lastBoxEnd (brLines r)) === [],
      testProperty "the lines hold every word once, in order" $ property $ do
        (ws, target) <- forAll genFitting
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        [w | l <- brLines r, Box w _ <- lineItems l] === ws,
      testProperty "with a word wider than the measure, the lines still hold every word once, in order" $ property $ do
        (ws, target) <- forAll genWithWide
        let r = breakParagraph defaultParams (const target) (paragraph ws)
        [w | l <- brLines r, Box w _ <- lineItems l] === ws,
      kinsokuTests,
      trailingSpaceTests,
      lowLineTests,
      apostropheTests,
      penaltyWidthTests
    ]

-- | The setting of the defaults: strict kinsoku, no hanging, no protrusion, no span.
plain :: Setting
plain = Setting True False False Nothing

-- | The lines of a run in the setting given, in lines of the width given in em.
linesIn :: Setting -> Int -> [Text] -> [Text]
linesIn s w run = let (_, _, br) = breakInput (Input s False w 0 run 0) in map lineText (brLines br)

-- | The items of a run, a box as its text, glue as its widths, a penalty as its value and kind.
shapes :: Setting -> [Text] -> [String]
shapes s run = map shape (itemsOf False s 0 run 0)
  where
    shape = \case
      Box _ c -> T.unpack (bcText c)
      Glue w y z -> "_" <> show (unSp w, unSp y, unSp z)
      Penalty _ p h ->
        "|" <> show p <> case h of
          PatternHyphen _ -> "P"
          ExplicitHyphen -> "E"
          WrapMark m -> "W" <> T.unpack m
          NoHyphen -> ""

-- | The glue that fills the last line.
fil :: String
fil = "_" <> show (0 :: Integer, unSp filStretch, 0 :: Integer)

-- | The glue of a space between Latin words in the advances of the tests.
space :: String
space = let sw = L.zwToSp fs (advance True ' ') in "_" <> show (unSp sw, unSp sw `div` 2, unSp sw `div` 3)

{- | Kinsoku across a space between words and the break after a hyphen
or a dash written in a word (golem-layout ADR 0028), on lines of 2 em.
-}
kinsokuTests :: TestTree
kinsokuTests =
  testGroup
    "kinsoku across spaces and written hyphens (golem-layout ADR 0028)"
    [ testCase "K2: あ「 いい does not end a line with 「 at the space after it" $
        linesIn plain 2 ["あ", "「", " ", "い", "い"] @?= ["あ", "「い", "い"],
      testCase "K1: あ 〜 does not start a line with 〜 at the space before it" $
        linesIn plain 2 ["あ", " ", "〜"] @?= ["あ〜"],
      testCase "K4: … … may break at the space between the two ellipses" $
        linesIn plain 2 ["あ", "…", " ", "…"] @?= ["あ…", "…"],
      testCase "K3: …—… in a span of en does not break between the dash and the ellipsis" $
        linesIn plain {sLang = Just "en"} 2 ["あ", "…", "—", "…"] @?= ["あ", "…—…"],
      testCase "K1: …—” in a span of en does not start a line with ” after the dash" $
        linesIn plain {sLang = Just "en"} 2 ["あ", "…", "—", "”"] @?= ["あ", "…—”"],
      testCase "K1: a—” out of a span does not start a line with ” after the dash" $
        linesIn plain 2 ["あ", "a", "—", "”"] @?= ["あ", "a—”"],
      testCase "K5: “ a and a ” break as the opening and the closing quotation mark, in no span, en and ja" $
        sequence_
          [ do
              linesIn plain {sLang = l} 2 ["あ", "あ", "“", " ", "a"] @?= ["ああ", "“a"]
              linesIn plain {sLang = l} 2 ["あ", "a", " ", "”"] @?= ["あ", "a”"]
          | l <- [Nothing, Just "en", Just "ja"]
          ],
      testCase "K6: the items of a space and of a written hyphen no prohibition applies to are as before" $ do
        shapes plain ["a", " ", "table"] @?= ["a", space, "ta", "|50P", "ble", "|10000", fil, "|-10000"]
        shapes plain ["lime-tree"] @?= ["lime-", "|50E", "tree", "|10000", fil, "|-10000"],
      testCase "K7: where a space is no longer a break, it is the only glue between the two characters" $
        -- the space of the paragraph start before 「, as before
        take 4 (drop 1 (shapes plain ["「", " ", "a"])) @?= ["「", "|10000", space, "a"]
    ]

-- | The items of inlines in the setting given, as 'shapes' writes them.
shapesOf :: [IR.Inline] -> [String]
shapesOf is = map shapeOf (fst (composeInlines (composeEnv False plain) is))

{- | Word spaces before the end of a paragraph and before a forced break
are dropped before the line breaking (golem-layout ADR 0032), on lines of
2 em.
-}
trailingSpaceTests :: TestTree
trailingSpaceTests =
  testGroup
    "word spaces before the end of a paragraph (golem-layout ADR 0032)"
    [ testCase "T1: ああ and あ「「 with a space after them are one line, no empty line after it" $ do
        linesIn plain 2 ["あ", "あ", " "] @?= ["ああ"]
        linesIn plain 2 ["あ", "「", "「", " "] @?= ["あ「「"],
      testCase "T2: the items of ああ with a space after it are those of ああ" $
        shapes plain ["あ", "あ", " "] @?= shapes plain ["あ", "あ"],
      testCase "T2: the space after a Latin word before the end goes, and the penalty before it after an opening bracket" $ do
        shapes plain ["a", " "] @?= shapes plain ["a"]
        shapes plain ["あ", "「", " "] @?= shapes plain ["あ", "「"],
      testCase "T2: a space before a forced break goes, the space after it stays a break" $
        shapesOf [IR.Text sp "ああ ", IR.LineBreak sp, IR.Text sp "いい"] @?= shapesOf [IR.Text sp "ああ", IR.LineBreak sp, IR.Text sp "いい"],
      testCase "T3: a space of code at the end stays" $ do
        let items = fst (composeInlines (defaultComposeEnv fs) {ceLook = look0 {lkCode = True}} [IR.Text sp "a "])
        [() | Glue _ 0 0 <- items] @?= [()],
      testCase "T1: a centred last line of ああ and a space is where that of ああ is" $ do
        let centred = Ragged LineCenter
            lastLine run =
              let its = itemsOf False plain 0 run 0
               in last (brLines (breakAligned centred (paramsOf plain False its) (const (4 * fs)) its))
            at = lineShift centred True
        at (lastLine ["あ", "あ", " "]) @?= at (lastLine ["あ", "あ"])
    ]

-- | The items of a run as 'shapes' gives them, with explicit-hyphen-penalty 10000.
shapesUnbroken :: [Text] -> [String]
shapesUnbroken run = map shapeOf (fst (composeInlines ((composeEnv False plain) {ceExplicitHyphenPenalty = 10000}) (inlinesOf plain 0 run 0)))

-- | An item as 'shapes' writes it.
shapeOf :: Item -> String
shapeOf = \case
  Box _ c -> T.unpack (bcText c)
  Glue w y z -> "_" <> show (unSp w, unSp y, unSp z)
  Penalty _ p h ->
    "|" <> show p <> case h of
      PatternHyphen _ -> "P"
      ExplicitHyphen -> "E"
      WrapMark m -> "W" <> T.unpack m
      NoHyphen -> ""

-- | The end of a paragraph, as 'shapes' writes it.
paragraphEnd :: [String]
paragraphEnd = ["|10000", fil, "|-10000"]

-- | The text before each break inside a text in a look (the paragraph end left out), and its penalty.
breaksIn :: Look -> Text -> [(Text, Int)]
breaksIn lk t = go "" (take (length items - 3) items)
  where
    items = fst (composeInlines (defaultComposeEnv fs) {ceLook = lk} [IR.Text sp t])
    go acc = \case
      Box _ c : rest -> go (acc <> bcText c) rest
      Penalty _ p _ : rest | p < infPenalty -> (acc, p) : go acc rest
      _ : rest -> go acc rest
      [] -> []

{- | Line breaks after the low lines of identifiers (golem-layout ADR 0031):
after each run of U+005F but the first and the last of a word, a break of
100 with no hyphen, and no hyphens of the patterns in the word.
-}
lowLineTests :: TestTree
lowLineTests =
  testGroup
    "line breaks after low lines in identifiers (golem-layout ADR 0031)"
    [ testCase "U1, U2: THIRD_PARTY_LICENSES breaks after each low line with 100, and the patterns do not break it" $
        shapes plain ["THIRD_PARTY_LICENSES"] @?= ["THIRD_", "|100", "PARTY_", "|100", "LICENSES"] <> paragraphEnd,
      testCase "U1, U2: in a span of en and of fr alike" $
        sequence_ [shapes plain {sLang = l} ["third_party_licenses"] @?= ["third_", "|100", "party_", "|100", "licenses"] <> paragraphEnd | l <- [Just "en", Just "fr"]],
      testCase "U1, U2: not after the first run (_private, __init__) nor after the last (foo_): one box, no hyphens of the patterns" $ do
        shapes plain ["_private"] @?= "_private" : paragraphEnd
        shapes plain ["__init__"] @?= "__init__" : paragraphEnd
        shapes plain ["foo_"] @?= "foo_" : paragraphEnd
        shapes plain ["hyphenation_"] @?= "hyphenation_" : paragraphEnd,
      testCase "U1: a word of a link is one box, a low line in it or not" $
        breaksIn look0 {lkLink = Just (LinkUri "https://example.com/")} "THIRD_PARTY_LICENSES" @?= [],
      testCase "U1: a run of low lines is one break after it: a__b" $
        shapes plain ["a__b"] @?= ["a__", "|100", "b"] <> paragraphEnd,
      testCase "U1: with an explicit hyphen, both breaks; explicit-hyphen-penalty 10000 keeps only the low lines" $ do
        shapes plain ["foo_bar-baz"] @?= ["foo_", "|100", "bar-", "|50E", "baz"] <> paragraphEnd
        shapesUnbroken ["foo_bar-baz"] @?= ["foo_", "|100", "bar-baz"] <> paragraphEnd,
      testCase "U1: a full stop and quotation marks stay in the boxes" $ do
        shapes plain ["foo_bar", "."] @?= ["foo_", "|100", "bar."] <> paragraphEnd
        shapes plain ["“", "foo_bar", "”"] @?= ["“foo_", "|100", "bar”"] <> paragraphEnd,
      testCase "U1: in code, after the low lines with 100 and after a slash with 0" $ do
        breaksIn look0 {lkCode = True} "THIRD_PARTY_LICENSES/x" @?= [("THIRD_", 100), ("THIRD_PARTY_", 100), ("THIRD_PARTY_LICENSES/", 0)]
        breaksIn look0 {lkCode = True} "__init__" @?= []
        breaksIn look0 {lkCode = True} "_private" @?= []
        breaksIn look0 {lkCode = True} "a__b" @?= [("a__", 100)],
      -- golem-layout ADR 0034 breaks before a Japanese character after a first run of low lines too, and after a Japanese character
      testCase "U1: in code, a first run of low lines before Japanese text is a break of 100 (golem-layout ADR 0034); one between two characters is" $ do
        breaksIn look0 {lkCode = True} "_あ" @?= [("_", 100)]
        breaksIn look0 {lkCode = True} "あ_b" @?= [("あ", 0), ("あ_", 100)],
      testCase "U3: lines broken after the low lines end with no hyphen and join into the word" $ do
        let (_, _, br) = breakInput (Input plain False 4 0 ["THIRD_PARTY_LICENSES"] 0)
        map lineText (brLines br) @?= ["THIRD_", "PARTY_", "LICENSES"]
        T.concat (map lineText (brLines br)) @?= "THIRD_PARTY_LICENSES"
        [() | l <- brLines br, Penalty w _ _ <- lineItems l, w > 0] @?= [],
      testCase "U4: words without a low line are as before" $ do
        shapes plain ["table"] @?= ["ta", "|50P", "ble"] <> paragraphEnd
        shapes plain ["lime-tree"] @?= ["lime-", "|50E", "tree"] <> paragraphEnd
        shapes plain ["table", "."] @?= ["ta", "|50P", "ble."] <> paragraphEnd,
      testCase "U5: a URL breaks as before" $ do
        breaksIn look0 {lkUrl = True} "a_b" @?= [("a_", 100)]
        breaksIn look0 {lkUrl = True} "THIRD_PARTY_LICENSES/x" @?= [("THIRD_", 100), ("THIRD_PARTY_", 100), ("THIRD_PARTY_LICENSES/", 0)],
      testCase "U6: in code, a break after a slash is 0 as before" $
        breaksIn look0 {lkCode = True} "a/b" @?= [("a/", 0)]
    ]

-- | Whether the space after a box of the text given is no break: a penalty of 10000 right before its glue.
noBreakBefore :: String -> [String] -> Bool
noBreakBefore t xs = or [a == t && p == "|10000" && g == space | (a, p, g) <- zip3 xs (drop 1 xs) (drop 2 xs)]

{- | An apostrophe at the start of a word (golem-layout ADR 0030): U+2019
first in a Latin word, a letter or a digit after it, is a Latin character
for kinsoku, on lines of 2 em.
-}
apostropheTests :: TestTree
apostropheTests =
  testGroup
    "apostrophes at word starts are not closing brackets (golem-layout ADR 0030)"
    [ testCase "A1: aaa ’tis and aaa ’90 break at the space before the apostrophe, in no span and in en" $
        sequence_
          [ do
              linesIn plain {sLang = l} 2 ["aaa", " ", "’tis"] @?= ["aaa", "’tis"]
              linesIn plain {sLang = l} 2 ["aaa", " ", "’Tis"] @?= ["aaa", "’Tis"]
              linesIn plain {sLang = l} 2 ["aaa", " ", "’90"] @?= ["aaa", "’90"]
          | l <- [Nothing, Just "en"]
          ],
      testCase "A1: a letter with a combining character after the apostrophe is a letter" $
        linesIn plain 2 ["aaa", " ", "’e\x0301tis"] @?= ["aaa", "’e\x0301tis"],
      testCase "A1: a space after a box that ends in an opening bracket is still no break" $
        assertBool "no break" (noBreakBefore "a“" (shapes plain ["a“", " ", "’tis"])),
      testCase "A2: no penalty of 10000 between あ and ’tis" $
        let xs = shapes plain ["あ", "’tis"] in filter (== "|10000") (take (length xs - 3) xs) @?= [],
      testCase "A3: ’ alone, ’” and ’. after a space are still closing brackets: no break at the space" $
        sequence_
          [ assertBool (show (r, l)) (noBreakBefore "aaa" (shapes plain {sLang = l} ("aaa" : " " : r)))
          | r <- [["’"], ["’", "”"], ["’", "."]],
            l <- [Nothing, Just "en"]
          ],
      testCase "A4: in a span of ja, ’ is a closing bracket: no break before it" $
        assertBool "no break" (noBreakBefore "aaa" (shapes plain {sLang = Just "ja"} ["aaa", " ", "’tis"])),
      testCase "A1: in a span of fr, the apostrophe at a word start is Latin" $
        linesIn plain {sLang = Just "fr"} 2 ["aaa", " ", "’tis"] @?= ["aaa", "’tis"],
      testCase "A6: an apostrophe inside a word and at its end is as before" $ do
        shapes plain ["I’ll"] @?= ["I’ll", "|10000", fil, "|-10000"]
        linesIn plain 2 ["aaa", " ", "as’"] @?= ["aaa", "as’"]
    ]

{- | The node a line overfull only by the width of the penalty at a break
stays alive (golem-layout ADR 0036): the items of its N1 to N3 by hand, a
box of 1 em, a penalty of 0 as wide as given, a box of 1/2 em, the same
penalty, a box of the width given and the end, in lines of 2 em.
-}
penaltyWidthTests :: TestTree
penaltyWidthTests =
  testGroup
    "the width of a penalty (golem-layout ADR 0036)"
    [ testCase "N1, N2: a penalty of 1 em, wider than the box after it, leaves the line of the whole paragraph, which fits" $
        linesOf half em @?= [[em, half, half]],
      testCase "N1, N2: a penalty of 1/4 em gives the one line too" $
        linesOf half quarter @?= [[em, half, half]],
      testCase "N1: when the line overflows even without the penalty, the paragraph is broken at the first penalty, the line holding its width within the measure" $ do
        let br = breakWidths em em
        map boxesOf (brLines br) @?= [[em], [half, em]]
        filter lineOverfull (brLines br) @?= []
        [sum (map itemWidth (lineItems l)) | l <- take 1 (brLines br)] @?= [2 * em],
      testCase "N3: with penalties of no width, the line of the whole paragraph, as when a node overfull at a break dies" $
        linesOf half 0 @?= [[em, half, half]]
    ]
  where
    em = fs
    half = Sp (unSp fs `div` 2)
    quarter = Sp (unSp fs `div` 4)
    box w = Box w (BoxContent "w" False 0 0 0 referenceLook 0 0 [] 0 0 noBoxSource Nothing noLeaf 0)
    itemsWith lastBox penW = [box em, Penalty penW 0 NoHyphen, box half, Penalty penW 0 NoHyphen, box lastBox] <> finish
    breakWidths lastBox penW = breakParagraph defaultParams (const (2 * em)) (itemsWith lastBox penW)
    boxesOf l = [w | Box w _ <- lineItems l]
    linesOf lastBox penW = map boxesOf (brLines (breakWidths lastBox penW))
