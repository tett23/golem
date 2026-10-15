module Main (main) where

import Control.Monad (forM_)
import Data.List (isPrefixOf, maximumBy, subsequences)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Ord (Down (..), comparing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.IR
import Golem.Layout.Aki (AkiSet, akiPositions, builtinAkiSets, defaultAkiSet, withAkiRule)
import Golem.Layout.Aki qualified as Aki
import Golem.Layout.Code
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look
import Golem.Layout.Orientation
import Golem.Layout.Paginate
import Golem.Layout.Ruby hiding (RubyAlign (..))
import Golem.Layout.Ruby qualified as R (RubyAlign (..))
import Golem.Layout.Sidenotes
import Golem.Layout.Table
import Golem.Layout.Wrap
import Golem.Syntax (FileId (..), mkSpan)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import KnuthPlassReference
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog (testProperty)

main :: IO ()
main = defaultMain tests

fs :: Sp
fs = 10 * 65536

box :: Sp -> Item
box w = Box w (BoxContent "x" False 0 0 0 look0 0 0 [])

-- | The original look of 'defaultComposeEnv'.
look0 :: Look
look0 = ceLook (defaultComposeEnv fs)

-- | Words of the given widths separated by interword glue.
paragraph :: [Sp] -> [Item]
paragraph ws = concat [box w : [Glue 6 3 2 | i < length ws - 1] | (i, w) <- zip [0 :: Int ..] ws] <> finish

refBox :: Text -> Sp -> Item
refBox t w = Box w (BoxContent t False 0 0 0 referenceLook 0 0 [])

knuthPlassWords, knuthPlassLog :: FilePath
knuthPlassWords = "test/data/knuth-plass/frog-king.words"
knuthPlassLog = "test/data/knuth-plass/frog-king.log"

-- | The \hsize values of frog-king.tex, in points.
referenceHsizes :: [Integer]
referenceHsizes = [160, 200, 240, 260, 300]

{- | A hand-written trace: the first run fails the first pass and takes a
detour (@@2 is not on the chosen path); the second ends in the first pass.
cc-dd counts as two words, cut after its hyphen (ADR 0008).
-}
sampleTrace :: Text
sampleTrace =
  T.unlines
    [ "This is TeX",
      "GOLEM-HSIZE=6553600",
      "@firstpass",
      "[]\\tenrm A bb ",
      "@ via @@0 b=* p=0 d=*",
      "@secondpass",
      "[]\\tenrm A bb ",
      "@ via @@0 b=10 p=0 d=400",
      "@@1: line 1.1 t=400 -> @@0",
      "cc-dd ",
      "@ via @@0 b=20 p=0 d=900",
      "@@2: line 1.1 t=900 -> @@0",
      "eee. ",
      "@\\par via @@1 b=0 p=-10000 d=100",
      "@\\par via @@2 b=0 p=-10000 d=100",
      "@@3: line 2.2- t=500 -> @@1",
      "",
      "> \\box1=",
      "\\vbox(10.0+2.0)x100.0",
      ".\\hbox(6.94444+1.94444)x100.0, glue set - 0.5",
      "..\\tenrm A",
      ".\\glue(\\baselineskip) 3.11111",
      ".\\hbox(6.94444+1.94444)x100.0, glue set 0.33333",
      "..\\tenrm e",
      "",
      "! OK.",
      "GOLEM-HSIZE=13107200",
      "@firstpass",
      "[]\\tenrm A bb cc-dd eee. ",
      "@\\par via @@0 b=0 p=-10000 d=100",
      "@@1: line 1.2- t=100 -> @@0",
      "",
      "> \\box1=",
      "\\vbox(10.0+2.0)x200.0",
      ".\\hbox(6.94444+1.94444)x200.0, glue set 7.0fil",
      "..\\tenrm A",
      "",
      "! OK."
    ]

noPretol :: Params
noPretol = defaultParams {pPretolerance = -1, pTolerance = 10000}

{- | Of all break sequences, those with the least total demerits, and of
them the one TeX keeps (ADR 0008). 'Nothing' if no sequence is feasible.
-}
bruteBest :: Params -> (Int -> Sp) -> [Item] -> Maybe (Integer, [Int])
bruteBest ps lw items =
  let end = length items - 1
      scored = [r | s <- subsequences (filter (/= end) (legal items)), Just r <- [bruteScore ps lw items (s <> [end])]]
   in case scored of
        [] -> Nothing
        _ ->
          let d = minimum (map fst scored)
              -- the last line's fitness, the smaller first; then the
              -- (position, fitness) pairs compared from the end, the greatest wins (ADR 0010)
              key rpath = case rpath of
                x : rest -> (Down (snd x), rest)
                [] -> (Down 0, [])
           in Just (d, map fst (reverse (maximumBy (comparing key) [reverse path | (d', path) <- scored, d' == d])))

{- | Total demerits of a break sequence and the (position, fitness) of
each break, computed directly from the rules.
-}
bruteScore :: Params -> (Int -> Sp) -> [Item] -> [Int] -> Maybe (Integer, [(Int, Fitness)])
bruteScore ps lw items brks = go 0 2 False (-1) brks 0 []
  where
    n = length items
    at = (items !!)
    afterBrk i = let s = dropWhile isDiscard [i + 1 .. n - 1] in case s of (j : _) -> j; [] -> n
    isDiscard j = case at j of
      Box {} -> False
      Penalty _ p _ -> p > negate infPenalty
      Glue {} -> True
    go _ _ _ _ [] acc path = Just (acc, reverse path)
    go line prevFit prevFlag prev (b : rest) acc path =
      let s = if prev < 0 then 0 else afterBrk prev
          seg = [at j | j <- [s .. b - 1]]
          penW = case at b of Penalty w _ _ -> w; _ -> 0
          natural = sum (map itemWidth seg) + penW
          y = sum [st | Glue _ st _ <- seg]
          z = sum [sh | Glue _ _ sh <- seg]
          target = lw line
          short = target - natural
          (bad, shrinking, over)
            | short > 0 = (badness short y, False, False)
            | short == 0 = (0, False, False)
            | negate short > z = (10000, True, True)
            | otherwise = (badness (negate short) z, True, False)
          fit = fitnessOf shrinking bad
          (pen, flag) = case at b of Penalty _ p h -> (p, h /= NoHyphen); _ -> (0, False)
          d =
            lineDemerits ps bad pen
              + (if prevFlag && flag then toInteger (pDoubleHyphenDemerits ps) else 0)
              + (if abs (fit - prevFit) > 1 then toInteger (pAdjDemerits ps) else 0)
       in if over || bad > pTolerance ps then Nothing else go (line + 1) fit flag b rest (acc + d) ((b, fit) : path)

legal :: [Item] -> [Int]
legal items =
  [ i
  | (i, it) <- zip [0 ..] items,
    case it of
      Penalty _ p _ -> p < infPenalty
      Glue {} -> i > 0 && isBox (items !! (i - 1))
      Box {} -> False
  ]
  where
    isBox = \case Box {} -> True; _ -> False

-- | A note key for tests: the note at offset k of file 0.
nid :: Int -> NoteId
nid k = NoteId (mkSpan (FileId 0) k (k + 1)) 0

noteMarkTests :: [TestTree]
noteMarkTests =
  [ testCase "a note mark joins the character before it, without spacing" $ do
      let items = fst (composeInlines (defaultComposeEnv fs) [sp0 "漢", note 1, sp0 "字"])
      case items of
        (Box _ a : Penalty 0 p NoHyphen : Box _ m : rest) -> do
          bcText a @?= "漢"
          p @?= infPenalty
          bcText m @?= "*1"
          boxKind m @?= KindNoteMark
          [bcText c | Box _ c <- rest] @?= ["字"]
          -- after the mark, what comes between 漢 and 字 without it: no spacing of Latin text
          rest @?= drop 1 (compose (defaultComposeEnv fs) "漢字")
        other -> assertFailure (show other),
    testCase "the width of a mark: its advance at half the size across, half the size down" $ do
      let env = (defaultComposeEnv fs) {ceWordAdvance = \lk t -> fromIntegral (T.length t) * (if lkSize lk == fs `div` 2 then 3 / 5 else 1)}
          markWidth e = [w | Box w c <- fst (composeInlines e [sp0 "漢", note 1, sp0 "字"]), boxKind c == KindNoteMark]
      markWidth env @?= [round (2 * 3 / 5 * toRational (fs `div` 2) :: Rational)]
      markWidth env {ceVertical = True} @?= [fs `div` 2],
    testCase "the spacing of the pair around the mark comes after it" $ do
      let env = defaultComposeEnv fs
          without = compose env "」あ"
          with = fst (composeInlines env [sp0 "」", note 1, sp0 "あ"])
          afterMark = drop 1 (dropWhile (\case Box _ c -> boxKind c /= KindNoteMark; _ -> True) with)
      afterMark @?= drop 1 without,
    testCase "the mark of a paragraph start has no leading space, its line end edge is 0" $ do
      let with = fst (composeInlines (defaultComposeEnv fs) [note 1, sp0 "「あ」"])
          without = compose (defaultComposeEnv fs) "「あ」"
      case [c | Box _ c <- with] of
        (m : _) -> (boxKind m, bcEdgeStart m, bcEdgeEnd m) @?= (KindNoteMark, 0, 0)
        [] -> assertFailure "no boxes"
      [w | Box w c <- with, boxKind c /= KindNoteMark] @?= [w | Box w _ <- without],
    testCase "a numbered sidenote marker is a note mark of the number alone" $ do
      let sn = Sidenote (mkSpan (FileId 0) 3 9) 1 [sp0 "注"]
      [(bcText c, boxKind c) | Box _ c <- fst (composeInlines (defaultComposeEnv fs) [sp0 "本", sn]), boxKind c /= KindText] @?= [("1", KindNoteMark)],
    testCase "two notes of a paragraph have anchors of different spans" $ do
      let anchors = snd (composeInlines (defaultComposeEnv fs) [sp0 "あ", Note (mkSpan (FileId 0) 1 5) 1 [sp0 "注"], sp0 "い", Note (mkSpan (FileId 0) 6 9) 2 [sp0 "注"]])
      [s | AnchorNote _ _ s _ <- anchors] @?= [mkSpan (FileId 0) 1 5, mkSpan (FileId 0) 6 9],
    testCase "two notes 1 of different keys on one page are two footnotes" $ do
      let a = NoteId (mkSpan (FileId 1) 0 5) 0
          b = NoteId (mkSpan (FileId 2) 0 5) 0
          ps = paginate 1 10 [FParagraph [LineBox 0 [NoteBody a 1] [] [], LineBox 1 [NoteBody b 2] [] []]]
      map poFootnotes ps @?= [[(a, 0, 1), (b, 0, 2)]]
  ]
  where
    note n = Note (mkSpan (FileId 0) 1 2) n [sp0 "注"]

sp0 :: Text -> Inline
sp0 = Text (mkSpan (FileId 0) 0 0)

compose :: ComposeEnv -> Text -> [Item]
compose env t = fst (composeInlines env [sp0 t])

-- | Advances that ignore variation selectors, so that boxes with and without them compare equal.
vsEnv :: ComposeEnv
vsEnv = (defaultComposeEnv fs) {ceWordAdvance = \_ t -> fromIntegral (T.length (T.filter (not . isVs) t))}

isVs :: Char -> Bool
isVs c = (c >= '\xFE00' && c <= '\xFE0F') || (c >= '\xE0100' && c <= '\xE01EF')

-- | The items with the variation selectors removed from the box texts.
stripVs :: Item -> Item
stripVs = \case
  Box w c -> Box w c {bcText = T.filter (not . isVs) (bcText c)}
  it -> it

-- | The environment with the bundled US English patterns.
enUS :: ComposeEnv
enUS = (defaultComposeEnv fs) {cePatterns = Just englishUS}

-- | The composed items without the paragraph end: box texts and penalties.
shape :: [Item] -> [String]
shape items =
  [ s
  | it <- take (length items - 3) items,
    s <- case it of
      Box _ c -> [T.unpack (bcText c)]
      Penalty w p h -> ["pen " <> show w <> " " <> show p <> " " <> show h]
      Glue {} -> ["glue"]
  ]

-- | Is there a legal break before the n-th box (counting from 0)?
breakBeforeBox :: [Item] -> Int -> Bool
breakBeforeBox items k =
  let idxs = [i | (i, Box {}) <- zip [0 ..] items]
   in case drop k idxs of
        (b : _) -> let prevBox = last [i | i <- idxs, i < b] in any (`elem` legal items) [prevBox + 1 .. b - 1]
        [] -> False

tests :: TestTree
tests =
  testGroup
    "golem-layout"
    [ testGroup "kenten shapes (golem-driver ADR 0019)" kentenTests,
      testGroup "code blocks and code (golem-driver ADR 0017)" codeTests,
      testGroup "note marks and note keys (golem-driver ADR 0018)" noteMarkTests,
      testGroup "vertical orientation (golem-driver ADR 0015)" orientationTests,
      testGroup "kerning, tracking and baseline shift (docs/adr/0020)" characterFeatureTests,
      testGroup "aki sets and [aki] (docs/adr ADR 0019)" akiTests,
      testGroup
        "Knuth-Plass (ADR 0001)"
        [ testCase "TeX badness" $ do
            badness 0 10 @?= 0
            badness 10 0 @?= 10000
            badness 10 10 @?= 100
            badness 5 10 @?= 12 -- TeX's approximation of 12.5
            badness 100 1 @?= 10000,
          testProperty "the result has the least total demerits of all break sequences" $ property $ do
            ws <- forAll (Gen.list (Range.linear 1 7) (Gen.integral (Range.linear 10 60)))
            target <- forAll (Gen.integral (Range.linear 60 140))
            let items = paragraph ws
                r = breakParagraph noPretol (const target) items
            case bruteBest noPretol (const target) items of
              Nothing -> brPass r === 4
              Just (d, c) -> do
                brPass r === 2
                brDemerits r === d
                -- ties go to the loosest last line, then the sequence greatest from the end (ADR 0010)
                brPositions r === c,
          testCase "every line fits its own target length (L*(i))" $ do
            let items = paragraph (replicate 20 30)
                lw :: Int -> Sp
                lw i = if i < 3 then 100 else 160
                r = breakParagraph defaultParams lw items
            assertBool "not overfull" (not (any lineOverfull (brLines r)))
            mapM_ (\(i, l) -> lineTarget l @?= lw i) (zip [0 ..] (brLines r))
            assertBool "short lines first" (all (\l -> sum [w | Box w _ <- lineItems l] <= 100) (take 3 (brLines r))),
          testCase "equal demerits: the later break wins, as in TeX (ADR 0008)" $ do
            -- A(10) | B(0) | C(10): breaking after A or after B both give two exact lines
            let items = [box 10, Penalty 0 0 NoHyphen, box 0, Penalty 0 0 NoHyphen, box 10] <> finish
                r = breakParagraph defaultParams (const 10) items
            brPositions r @?= [3, length items - 1]
            brDemerits r @?= 200,
          testCase "equal demerits: the path TeX keeps, here four lines over three (ADR 0008)" $ do
            let fil = Glue 0 filStretch 0
                items = [box 20, Penalty 0 0 NoHyphen, box 10, fil, Penalty 0 0 NoHyphen, box 10, fil, Penalty 0 0 NoHyphen, box 20] <> finish
                r = breakParagraph defaultParams {pLinePenalty = 0, pAdjDemerits = 0} (const 20) items
            length (brLines r) @?= 4
            brDemerits r @?= 0,
          testProperty "of the least-demerit break sequences, the loosest last line, then the one greatest from the end, is chosen" $ property $ do
            ws <- forAll (Gen.list (Range.linear 1 7) (Gen.integral (Range.linear 0 60)))
            target <- forAll (Gen.integral (Range.linear 30 140))
            let items = paragraph ws
                r = breakParagraph noPretol (const target) items
            case bruteBest noPretol (const target) items of
              Nothing -> brPass r === 4
              Just (_, c) -> brPositions r === c,
          testCase "equal demerits: fitness counts in the comparison from the end (ADR 0008)" $ do
            -- [3, 9, 13] and [5, 9, 13] tie; at 9 the first is tight, the second very loose
            let items = paragraph [15, 34, 33, 24, 25, 43]
                r = breakParagraph noPretol (const 90) items
            brDemerits r @?= 100032200
            brPositions r @?= [3, 9, 13]
            fmap snd (bruteBest noPretol (const 90) items) @?= Just (brPositions r),
          testCase "equal demerits: the loosest last line wins, as in TeX (ADR 0010)" $ do
            -- after B: decent then tight; after C: tight then decent; both 484
            let items = [box 50, Penalty 0 infPenalty NoHyphen, Glue 0 10 10, box 50, Penalty 0 0 NoHyphen, box 6, Penalty 0 0 NoHyphen, box 50, Penalty 0 infPenalty NoHyphen, Glue 0 10 10, box 50] <> finish
                r = breakParagraph defaultParams {pLinePenalty = 0, pAdjDemerits = 0} (const 100) items
            brPositions r @?= [6, length items - 1]
            brDemerits r @?= 484
            brPass r @?= 1
            -- the last line is set at its natural width: badness 0, decent (2)
            map lineRatio (brLines r) @?= [negate (3 / 5), 0],
          testCase "a line's demerits are capped as in TeX (ADR 0008)" $ do
            lineDemerits defaultParams 9990 0 @?= 100000000
            lineDemerits defaultParams 9989 0 @?= 99980001,
          testCase "an explicit hyphen breaks in the first pass; a pattern hyphen does not (ADR 0008)" $ do
            let items h = [box 30, Penalty 0 50 h, box 30] <> finish
                r = breakParagraph defaultParams (const 30) (items ExplicitHyphen)
            brPass r @?= 1
            brPositions r @?= [1, length (items ExplicitHyphen) - 1]
            assertBool "pattern hyphens wait for the second pass" (brPass (breakParagraph defaultParams (const 30) (items PatternHyphen)) /= 1)
            case brLines r of
              (l : _) -> do
                [w | Penalty w _ _ <- lineItems l] @?= [w | Penalty w _ _ <- lineItems l, w == 0]
                case reverse (placeLine l) of
                  ((Box w _, x) : _) -> x + w @?= 30
                  _ -> assertFailure "no box"
              [] -> assertFailure "no lines",
          testCase "an unbreakable word reaches the fourth pass and is overfull" $ do
            let items = paragraph [50, 500, 50]
                r = breakParagraph defaultParams {pEmergencyStretch = 20} (const 100) items
            brPass r @?= 4
            assertBool "overfull" (any lineOverfull (brLines r)),
          testCase "a penalty inside a line takes no width; at the line end it does" $ do
            let items = [box 30, Penalty 5 50 PatternHyphen, box 30, Glue 6 3 2, box 30, Penalty 5 50 PatternHyphen, box 30] <> finish
                r = breakParagraph defaultParams (const 1000) items
            case brLines r of
              [l] -> [x | (Box {}, x) <- placeLine l] @?= [0, 30, 66, 96]
              ls -> assertFailure (show (length ls))
            let r2 = breakParagraph noPretol (const 70) ([box 30, Glue 6 3 2, box 30, Penalty 5 50 PatternHyphen, box 30] <> finish)
            case brLines r2 of
              (l : _) -> case reverse (lineItems l) of
                (Penalty 5 _ PatternHyphen : _) -> pure ()
                other -> assertFailure ("the break penalty should end the line: " <> show (take 1 other))
              [] -> assertFailure "no lines",
          testCase "set lines fill the target exactly" $ do
            let items = paragraph (replicate 12 37)
                r = breakParagraph defaultParams (const 150) items
            mapM_
              ( \l -> case reverse (placeLine l) of
                  ((Box w _, x) : _) | not (lineOverfull l) && lineRatio l < 1 -> x + w @?= lineTarget l
                  _ -> pure ()
              )
              (init (brLines r))
        ],
      testGroup
        "Knuth-Plass reference (ADR 0007)"
        ( [ testCase "parseTrace reads the passes, the chosen path and the glue settings" $
              parseTrace sampleTrace
                @?= [ TexRun
                        { trHsize = 100 * 65536,
                          trPass = 2,
                          trBreaks = [TexBreak 1 1 400, TexBreak 4 2 100],
                          trTotalDemerits = 500,
                          trGlueSet = [negate (32768 / 65536), 21845 / 65536]
                        },
                      TexRun
                        { trHsize = 200 * 65536,
                          trPass = 1,
                          trBreaks = [TexBreak 4 2 100],
                          trTotalDemerits = 100,
                          trGlueSet = [7]
                        }
                    ],
            testCase "glue settings go back to the scaled integers TeX printed" $ do
              parseScaled "0.33333" @?= 21845
              parseScaled "- 0.5" @?= -32768
              parseScaled "1.0" @?= 65536
              parseScaled "104.05528fil" @?= 104 * 65536 + 3623,
            testCase "paragraphItems: indent, words, interword glue and the paragraph end" $
              paragraphItems (Words (6, 3, 2) 20 0 [WordBox "a" 10, WordBox "b" 12])
                @?= [refBox "" 20, refBox "a" 10, Glue 6 3 2, refBox "b" 12] <> finish,
            testCase "an exhyphen record becomes an explicit hyphen penalty (ADR 0008)" $ do
              fmap wBoxes (parseWords "space 6 3 2\nparindent 20\nwhole 0\nbox 7 lime-\nexhyphen\nbox 5 tree\n")
                @?= Right [WordBox "lime-" 7, WordExHyphen, WordBox "tree" 5]
              paragraphItems (Words (6, 3, 2) 20 0 [WordBox "lime-" 7, WordExHyphen, WordBox "tree" 5])
                @?= [refBox "" 20, refBox "lime-" 7, Penalty 0 50 ExplicitHyphen, refBox "tree" 5] <> finish,
            testCase "printed words are split after a hyphen followed by more (ADR 0008)" $ do
              length (wordsOf "lime-tree in") @?= 3
              length (wordsOf "lime-") @?= 1,
            testCase "at 260pt TeX breaks after lime- in the first pass (ADR 0008)" $ do
              ws <- readWords knuthPlassWords
              runs <- parseTrace <$> TIO.readFile knuthPlassLog
              let limeIx = length (takeWhile (/= WordBox "lime-" 1419949) [b | b@WordBox {} <- wBoxes ws])
              case filter ((== 260 * 65536) . trHsize) runs of
                [run] -> do
                  trPass run @?= 1
                  assertBool "lime- ends a line" (limeIx `elem` map tbWordIndex (trBreaks run))
                  compareRun ws run @?= []
                rs -> assertFailure ("expected one run, found " <> show (length rs)),
            testCase "the data has every \\hsize of frog-king.tex, from both passes" $ do
              runs <- parseTrace <$> TIO.readFile knuthPlassLog
              map trHsize runs @?= map (* 65536) referenceHsizes
              assertBool "a run that ends in the first pass" (any ((== 1) . trPass) runs)
              assertBool "a run that reaches the second pass" (any ((== 2) . trPass) runs),
            testCase "the words add up to the paragraph TeX set in one box" $ do
              ws <- readWords knuthPlassWords
              let (space, _, _) = wSpace ws
                  widths = [w | WordBox _ w <- wBoxes ws]
                  n = toInteger (length widths)
                  ex = toInteger (length [() | WordExHyphen <- wBoxes ws])
              sum widths + (n - 1 - ex) * space @?= wWhole ws
          ]
            <> [ testCase ("\\hsize=" <> show h <> "pt agrees with TeX") $ do
                   ws <- readWords knuthPlassWords
                   runs <- parseTrace <$> TIO.readFile knuthPlassLog
                   case filter ((== h * 65536) . trHsize) runs of
                     [run] -> case compareRun ws run of
                       [] -> pure ()
                       ds -> assertFailure (unlines ds)
                     rs -> assertFailure ("expected one run, found " <> show (length rs))
               | h <- referenceHsizes
               ]
        ),
      testGroup
        "hyphenation (Liang)"
        [ testCase "the example from Liang's thesis" $ do
            let ps = parsePatterns 2 3 "hy3ph he2n hena4 hen5at 1na n2at 1tio 2io o2n"
            hyphenate ps "hyphenation" @?= ["hy", "phen", "ation"]
            hyphenate ps "on" @?= ["on"],
          testCase "the bundled US English patterns (hyph-utf8)" $ do
            hyphenate englishUS "hyphenation" @?= ["hy", "phen", "ation"]
            hyphenate englishUS "algorithm" @?= ["al", "go", "rithm"]
            hyphenate englishUS "Typesetting" @?= ["Type", "set", "ting"]
            -- at least two letters before and three after a break
            all (\w -> T.length (head' (hyphenate englishUS w)) >= 2 && T.length (last' (hyphenate englishUS w)) >= 3) ["hyphenation", "algorithm", "typesetting", "deterministic"] @?= True,
          testCase "exceptions override the patterns" $ do
            hyphenate englishUS "table" @?= ["ta", "ble"]
            hyphenate englishUS "project" @?= ["project"]
            hyphenate englishUS "associates" @?= ["as", "so", "ciates"],
          testCase "composition offers flagged hyphen penalties inside words" $ do
            let env = (defaultComposeEnv fs) {cePatterns = Just englishUS}
            length [() | Penalty _ 50 PatternHyphen <- compose env "hyphenation"] @?= 2
        ],
      testGroup
        "explicit hyphens (golem-layout ADR 0008)"
        [ testCase "a hyphen in a word is a break with no added hyphen" $
            shape (compose enUS "lime-tree") @?= ["lime-", "pen 0 50 ExplicitHyphen", "tree"],
          testCase "words with an explicit hyphen get no pattern hyphens" $ do
            shape (compose enUS "well-known") @?= ["well-", "pen 0 50 ExplicitHyphen", "known"]
            shape (compose enUS "self-evident") @?= ["self-", "pen 0 50 ExplicitHyphen", "evident"],
          testCase "explicit-hyphen-penalty 10000 keeps the word whole" $
            shape (compose enUS {ceExplicitHyphenPenalty = 10000} "lime-tree") @?= ["lime-tree"],
          testCase "no break after a leading or trailing hyphen; one after a run" $ do
            shape (compose enUS "-5") @?= ["-5"]
            shape (compose enUS "pre-") @?= ["pre-"]
            shape (compose enUS "a--b") @?= ["a--", "pen 0 50 ExplicitHyphen", "b"],
          testCase "an em dash between quotations is a break" $
            shape (compose enUS "us!”—“We") @?= ["us!”—", "pen 0 50 ExplicitHyphen", "“We"],
          testCase "U+2010 and U+2013 between Latin letters join the word" $ do
            shape (compose enUS "lime‐tree") @?= ["lime‐", "pen 0 50 ExplicitHyphen", "tree"]
            shape (compose enUS "1990–2000") @?= ["1990–", "pen 0 50 ExplicitHyphen", "2000"],
          testCase "an en dash in Japanese text stays a character with no break before it" $ do
            let items = compose enUS "東京–大阪"
            [bcText c | Box _ c <- items] @?= ["東", "京", "–", "大", "阪"]
            breakBeforeBox items 2 @?= False
            [() | Penalty _ _ ExplicitHyphen <- items] @?= [],
          testCase "a non-breaking hyphen (U+2011) is no break" $ do
            shape (compose enUS "non‑breaking") @?= ["non‑breaking"]
            charClass '‑' @?= Hyphen
        ],
      testGroup
        "Japanese composition (ADR 0002)"
        [ testCase "no break before a full stop or a closing bracket, nor after an opening bracket" $ do
            let items = compose (defaultComposeEnv fs) "本「文」。"
            -- boxes: 本 「 文 」 。
            breakBeforeBox items 1 @?= True
            breakBeforeBox items 2 @?= False
            breakBeforeBox items 3 @?= False
            breakBeforeBox items 4 @?= False,
          testCase "strict kinsoku keeps small kana and the long vowel mark off the line start" $ do
            let strict = compose (defaultComposeEnv fs) "あっあー"
                loose = compose (defaultComposeEnv fs) {ceKinsokuStrict = False} "あっあー"
            (breakBeforeBox strict 1, breakBeforeBox strict 3) @?= (False, False)
            (breakBeforeBox loose 1, breakBeforeBox loose 3) @?= (True, True),
          testCase "punctuation spacing: closing then opening keeps a half em, closing then closing none" $ do
            let glues t = [w | Glue w _ _ <- compose (defaultComposeEnv fs) t, w > 0]
            glues "」「" @?= [fs `div` 2]
            glues "）」" @?= []
            glues "あ。」" @?= [],
          testCase "apostrophes inside Latin words belong to the word" $ do
            [bcText c | Box _ c <- compose (defaultComposeEnv fs) "I’ll warrant the masters’ whistle"] @?= ["I’ll", "warrant", "the", "masters’", "whistle"],
          testCase "quotation marks touching Latin text belong to the word" $ do
            [bcText c | Box _ c <- compose (defaultComposeEnv fs) "“Mercy on us!”—“We split!”]"] @?= ["“Mercy", "on", "us!”—", "“We", "split!”]"]
            -- in Japanese text they stay punctuation
            [bcText c | Box _ c <- compose (defaultComposeEnv fs) "彼は“あ”と"] @?= ["彼", "は", "“", "あ", "”", "と"],
          testCase "a quarter em between Japanese and Latin text" $ do
            let items = compose (defaultComposeEnv fs) "日本Golem語"
            [w | Glue w _ _ <- items, w > 0, w < filStretch] @?= [fs `div` 4, fs `div` 4],
          testCase "ruby wider than its base overhangs, then widens the base" $ do
            let seg base r = RubySegment [Text (mkSpan (FileId 0) 0 0) base] (Just r)
                rubyW e segs = [w | Box w c <- fst (composeInlines e [sp0 "の", Ruby (mkSpan (FileId 0) 0 0) () segs, sp0 "の"]), boxKind c `elem` [KindRuby, KindGroupRuby]]
                env = (defaultComposeEnv fs) {ceRuby = (defaultRubyStyle fs) {rsOverhang = fs `div` 2}}
            rubyW env [seg "字" "じ"] @?= [fs] -- fits
            rubyW env [seg "字" "あいう"] @?= [fs] -- 1.5em reading: overhang absorbs it
            rubyW env [seg "字" "あいうえおか"] @?= [fs * 2] -- 3em: half an em overhangs each kana, the base widens
            -- mono ruby may break between bases
            assertBool "mono" (any (\case Penalty 0 0 _ -> True; _ -> False) (fst (composeInlines env [Ruby (mkSpan (FileId 0) 0 0) () [seg "漢" "かん", seg "字" "じ"]]))),
          testCase "tate-chu-yoko and tcy numbers are one em boxes; Latin is rotated in vertical text" $ do
            let env = (defaultComposeEnv fs) {ceVertical = True}
                boxes is = [(w, boxKind c) | Box w c <- fst (composeInlines env is)]
            boxes [Tcy (mkSpan (FileId 0) 0 0) "12"] @?= [(fs, KindTcy)]
            boxes [Number (mkSpan (FileId 0) 0 0) 10 (Just StyleTcy)] @?= [(fs, KindTcy)]
            map snd (boxes [sp0 "ab"]) @?= [KindRotated]
            [bcText c | Box _ c <- fst (composeInlines env [Number (mkSpan (FileId 0) 0 0) 120 Nothing])] @?= ["百", "二", "十"]
        ],
      testGroup "ruby placement (ADR 0009)" rubyTests,
      testGroup "ruby base character styles (ADR 0011)" rubyBaseTests,
      testGroup
        "microtypography (ADR 0005)"
        [ testCase "protrusion of hyphens and full stops follows the table" $ do
            let env = (defaultComposeEnv fs) {ceProtrusion = True}
            case [(w, c) | Box w c <- compose env "end."] of
              [(w, c)] -> do
                bcProtrudeEnd c @?= w * 700 `div` 1000 -- the full stop: 70% of… the word box
                bcExpandable c @?= True
              other -> assertFailure (show other),
          testCase "Japanese glyphs never expand" $
            [bcExpandable c | Box _ c <- compose (defaultComposeEnv fs) "日本語"] @?= [False, False, False],
          testProperty "expansion is within the limit and a multiple of the step" $ property $ do
            ws <- forAll (Gen.list (Range.linear 3 12) (Gen.integral (Range.linear 20 70)))
            let items = [Box w (BoxContent "w" True 0 0 0 look0 0 0 []) | w <- ws] `interleave` Glue 6 3 2 <> finish
                r = breakParagraph defaultParams {pExpansion = Just (20, 5)} (const 150) items
            mapM_ (\l -> assert (abs (lineExpansion l) <= 20 && lineExpansion l `mod` 5 == 0)) (brLines r),
          testCase "expansion lowers the spread of adjustment ratios" $ do
            let ws = [23, 41, 37, 19, 52, 33, 28, 45, 31, 26, 39, 22, 48, 35, 29, 41]
                items = [Box (w * 100) (BoxContent "w" True 0 0 0 look0 0 0 []) | w <- ws] `interleave` Glue 600 300 200 <> finish
                variance ps =
                  let rs = map glueRatio (init (brLines (breakParagraph ps (const 15000) items)))
                      m = sum rs / fromIntegral (length rs)
                   in sum [(r - m) ^ (2 :: Int) | r <- rs] / fromIntegral (length rs)
            assertBool "smaller" (variance defaultParams {pExpansion = Just (20, 5)} < variance defaultParams)
        ],
      testGroup
        "pagination (ADR 0003)"
        [ testCase "no orphan: a paragraph's first line is not left alone at the page end" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 4), FParagraph (lines' 10 3)]
            slots ps @?= [[0, 1, 2, 3], [10, 11, 12]],
          testCase "no widow: the last line is not sent alone to the next page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 6)]
            slots ps @?= [[0, 1, 2, 3], [4, 5]],
          testCase "headings and definition terms stay with what follows" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 3), FHeading 2 False 1 (lines' 20 1), FParagraph (lines' 30 3)]
            slots ps @?= [[0, 1, 2], [20, 30, 31, 32]]
            let qs = paginate 1 5 [FParagraph (lines' 0 4), FDefTerm (lines' 20 1), FParagraph (lines' 30 2)]
            slots qs @?= [[0, 1, 2, 3], [20, 30, 31]],
          testCase "a recto heading starts on an odd page after a blank page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 3), FHeading 1 True 1 (lines' 20 1)]
            map poBlank ps @?= [False, True, False]
            map poNumber ps @?= [1, 2, 3],
          testCase "a figure that does not fit goes to the next page; text moves up" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 3), FFigure 99 3 ["fig"] [], FParagraph (lines' 10 2)]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 10), (4, SLine 11)], [(0, SFigure 99)]],
          testCase "footnotes sit on the page of their marker and continue when too long" $ do
            let withNote i n = LineBox i [NoteBody (nid (100 + i)) n] [] []
                ps = paginate 1 6 [FParagraph [LineBox 0 [] [] [], withNote 1 2, LineBox 2 [] [] [], withNote 3 1, LineBox 4 [] [] []]]
            map poFootnotes ps @?= [[(nid 101, 0, 2)], [(nid 103, 0, 1)]]
            let long = paginate 1 4 [FParagraph [withNote 0 5, LineBox 1 [] [] []]]
            map poFootnotes long @?= [[(nid 100, 0, 2)], [(nid 100, 2, 2)], [(nid 100, 4, 1)]],
          testCase "index marks go to the page of their line (golem-driver ADR 0007)" $ do
            let m = mkSpan (FileId 0) 10 20
                ps = paginate 1 1 [FParagraph [LineBox 0 [] [] [], LineBox 1 [] [] [m], LineBox 2 [] [] []]]
            map poNumber ps @?= [1, 2, 3]
            markPages ps @?= Map.fromList [(m, 2)],
          testCase "the marks of a figure go with it to the next page" $ do
            let m = mkSpan (FileId 0) 10 20
                ps = paginate 1 5 [FParagraph (lines' 0 3), FFigure 99 3 ["fig"] [m], FParagraph (lines' 10 2)]
            markPages ps @?= Map.fromList [(m, 2)],
          testCase "page references converge when the page count gains a digit" $ do
            -- the reference sits before the label; at three digits the reference line wraps
            let layout assumed =
                  let refWidthLines = if Map.findWithDefault 1 "end" assumed >= 100 then 2 else 1
                   in paginate 1 5 (FParagraph (lines' 0 refWidthLines) : [FParagraph (lines' (1000 + i * 10) 2) | i <- [0 .. 196]] <> [FParagraph [LineBox 9999 [] ["end"] []]])
            case resolvePageRefs layout of
              Right ps -> Map.lookup "end" (labelPages ps) @?= Just (toInteger (poNumber (last ps)))
              Left ls -> assertFailure (show ls),
          testCase "references that never settle are an error" $ do
            let layout assumed = paginate 1 5 (replicate (fromInteger (if Map.findWithDefault 1 "x" assumed < 10 then 9 else 1)) (FParagraph (lines' 0 5)) <> [FParagraph [LineBox 1 [] ["x"] []]])
            resolvePageRefs layout @?= Left ["x"],
          testCase "a space between stanzas takes grid lines (docs/adr ADR 0003)" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 4), FSpace 1, FParagraph (lines' 10 1)]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 3)], [(0, SLine 10)]]
            let qs = paginate 1 5 [FParagraph (lines' 0 2), FSpace 2, FParagraph (lines' 10 1)]
            map poSlots qs @?= [[(0, SLine 0), (1, SLine 1), (4, SLine 10)]],
          testCase "a space at the top of a page takes nothing" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 5), FSpace 1, FParagraph (lines' 10 1)]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 3), (4, SLine 4)], [(0, SLine 10)]]
            map poSlots (paginate 1 5 [FSpace 3, FParagraph (lines' 0 1)]) @?= [[(0, SLine 0)]]
        ],
      testGroup
        "forced breaks (docs/adr ADR 0017)"
        [ testCase "a page break in the middle of page 1 starts page 2" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakPage, FParagraph (lines' 10 1)]
            slots ps @?= [[0], [10]]
            map poBlank ps @?= [False, False],
          testCase "two page breaks in a row make a blank page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakPage, FBreak BreakPage, FParagraph (lines' 10 1)]
            map poBlank ps @?= [False, True, False]
            slots ps @?= [[0], [], [10]],
          testCase "a page break at the start of the book makes page 1 blank" $ do
            let ps = paginate 1 5 [FBreak BreakPage, FParagraph (lines' 0 1)]
            map poBlank ps @?= [True, False]
            slots ps @?= [[], [0]],
          testCase "a recto break goes to the next odd page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakRecto, FParagraph (lines' 10 1)]
            map poBlank ps @?= [False, True, False]
            slots ps @?= [[0], [], [10]]
            let qs = paginate 1 5 [FParagraph (lines' 0 5), FParagraph (lines' 10 1), FBreak BreakRecto, FParagraph (lines' 20 1)]
            map poBlank qs @?= [False, False, False]
            slots qs @?= [[0, 1, 2, 3, 4], [10], [20]],
          testCase "a recto break on an empty odd page does nothing" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakPage, FBreak BreakPage, FBreak BreakRecto, FParagraph (lines' 10 1)]
            map poBlank ps @?= [False, True, False]
            slots ps @?= [[0], [], [10]],
          testCase "a verso break goes to the next even page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakVerso, FParagraph (lines' 10 1)]
            map poBlank ps @?= [False, False]
            slots ps @?= [[0], [10]]
            let qs = paginate 1 5 [FParagraph (lines' 0 5), FParagraph (lines' 10 1), FBreak BreakVerso, FParagraph (lines' 20 1)]
            map poBlank qs @?= [False, False, True, False]
            slots qs @?= [[0, 1, 2, 3, 4], [10], [], [20]],
          testCase "breaks at the end of the book add no page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakPage]
                qs = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakRecto]
            map poBlank ps @?= [False]
            map poBlank qs @?= [False],
          testCase "a recto heading after a page break adds a blank page only on an even page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 1), FBreak BreakPage, FHeading 1 True 1 (lines' 20 1)]
            map poBlank ps @?= [False, True, False]
            slots ps @?= [[0], [], [20]]
            let qs = paginate 1 5 [FParagraph (lines' 0 5), FParagraph (lines' 10 1), FBreak BreakPage, FHeading 1 True 1 (lines' 20 1)]
            map poBlank qs @?= [False, False, False]
            slots qs @?= [[0, 1, 2, 3, 4], [10], [20]],
          testCase "a figure sent on goes to the top of the page after the break, not to a blank page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 3), FFigure 99 3 ["fig"] [], FBreak BreakPage, FParagraph (lines' 10 1)]
            map poBlank ps @?= [False, False]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2)], [(0, SFigure 99), (3, SLine 10)]],
          testCase "a column break on one column is a page break" $ do
            let flows k = [FParagraph (lines' 0 1), FBreak k, FBreak k, FParagraph (lines' 10 1)]
            paginate 1 5 (flows BreakColumn) @?= paginate 1 5 (flows BreakPage)
            paginate 1 5 [FBreak BreakColumn, FParagraph (lines' 0 1)] @?= paginate 1 5 [FBreak BreakPage, FParagraph (lines' 0 1)]
        ],
      testGroup
        "looks: emphasis, character styles and colour (golem-driver ADR 0004)"
        [ testCase "a bold role measures its characters in its own font" $ do
            let env = lookEnv (\lk -> \case CharStyle _ "bold" _ -> lk {lkFace = "wide", lkLatinFace = "wide"}; _ -> lk)
                boxes = [(w, lkFace (bcLook c)) | Box w c <- fst (composeInlines env [bold [sp0 "AB"], sp0 "C"])]
            case boxes of
              [(ab, fab), (c, fc)] -> do
                -- A and B are each twice as wide as C
                ab @?= 4 * c
                (fab, fc) @?= ("wide", "body")
              other -> assertFailure (show other),
          testCase "synthetic bold keeps the widths" $ do
            let env = lookEnv (\lk -> \case CharStyle _ "bold" _ -> lk {lkSynthetic = both, lkLatinSynthetic = both}; _ -> lk)
                widths is = [w | Box w _ <- fst (composeInlines env is)]
            widths [bold [sp0 "AB"], sp0 "C"] @?= widths [sp0 "AB", sp0 "C"]
            [synBold (lkLatinSynthetic (bcLook c)) | Box _ c <- fst (composeInlines env [bold [sp0 "AB"], sp0 "C"])] @?= [True, False],
          testCase "the space after a closing bracket follows the bracket's size" $ do
            let env = lookEnv (\lk -> \case CharStyle {} -> lk {lkSize = 2 * lkSize lk}; _ -> lk)
                items = fst (composeInlines env [CharStyle sp "big" [sp0 "」"], sp0 "あ"])
            [w | Glue w _ _ <- items, w > 0, w < filStretch] @?= [fs],
          testCase "a look boundary inside a Latin word is no break" $ do
            let env = lookEnv (\lk -> \case CharStyle _ "bold" _ -> lk {lkSynthetic = both, lkLatinSynthetic = both}; _ -> lk)
                items = fst (composeInlines env [bold [sp0 "Gol"], sp0 "em"])
            [bcText c | Box _ c <- items] @?= ["Gol", "em"]
            breakBeforeBox items 1 @?= False,
          testCase "nested looks inherit what they do not set" $ do
            let env = lookEnv $ \lk -> \case
                  CharStyle _ "bold" _ -> lk {lkSynthetic = (lkSynthetic lk) {synBold = True}, lkLatinSynthetic = (lkLatinSynthetic lk) {synBold = True}}
                  CharStyle _ "italic" _ -> lk {lkSynthetic = (lkSynthetic lk) {synSlant = True}, lkLatinSynthetic = (lkLatinSynthetic lk) {synSlant = True}}
                  Color _ c _ -> lk {lkColor = Just c}
                  _ -> lk
            [bcLook c | Box _ c <- fst (composeInlines env [Color sp "accent" [CharStyle sp "italic" [bold [sp0 "x"]]]])]
              @?= [look0 {lkColor = Just "accent", lkSynthetic = Synthetic True True, lkLatinSynthetic = Synthetic True True}],
          testCase "a line break composes to a forced break (docs/adr ADR 0016)" $ do
            let env = lookEnv const
                items = fst (composeInlines env [sp0 "ab", LineBreak sp, sp0 "cd"])
                marks = \case
                  Box _ c -> [T.unpack (bcText c)]
                  Penalty _ p _ | p >= infPenalty -> ["+inf"] | p <= negate infPenalty -> ["-inf"]
                  Glue _ st _ | st >= filStretch -> ["fil"]
                  _ -> []
            take 7 (concatMap marks items) @?= ["ab", "+inf", "fil", "-inf", "cd", "+inf", "fil"],
          testCase "a forced break always breaks the line (docs/adr ADR 0016)" $ do
            let env = lookEnv const
                items = fst (composeInlines env [sp0 "ab", LineBreak sp, sp0 "cd"])
                r = breakParagraph defaultParams (const (100 * fs)) items
            map (\l -> [T.unpack (bcText c) | Box _ c <- lineItems l]) (brLines r) @?= [["ab"], ["cd"]],
          testCase "no space between Japanese and Latin across a forced break (docs/adr ADR 0016)" $ do
            let env = lookEnv const
                items = fst (composeInlines env [sp0 "あい", LineBreak sp, sp0 "cd"])
                quarter = fs `div` 4
            [w | Glue w _ _ <- items, w == quarter] @?= []
            assertBool "the space appears without the break" (not (null [w | Glue w _ _ <- fst (composeInlines env [sp0 "あいcd"]), w == quarter]))
        ],
      testGroup
        "heading blocks (golem-driver ADR 0003)"
        [ testCase "a 20Q heading on a 13Q, 22H grid takes two grid lines, three when it wraps" $ do
            let q x = round (x / 4 * 72 * 65536 / (254 / 10) :: Rational) :: Sp
                (bfs, bp, s) = (q 13, q 22, q 20)
                hp = round (toRational bp * toRational s / toRational bfs)
                expect m =
                  let e = toInteger (m - 1) * hp + s
                      n = max 1 ((e + bp - bfs + bp - 1) `div` bp)
                   in HeadingBlock hp (fromInteger n) (((n - 1) * bp + bfs - e) `div` 2)
            headingBlock bfs bp s 1 @?= expect (1 :: Int)
            headingBlock bfs bp s 2 @?= expect (2 :: Int)
            hbSpan (headingBlock bfs bp s 1) @?= 2
            hbSpan (headingBlock bfs bp s 2) @?= 3,
          testCase "a heading of the body size sits on the grid" $
            mapM_ (\m -> headingBlock fs (fs * 3 `div` 2) fs m @?= HeadingBlock (fs * 3 `div` 2) m 0) [1, 2, 3],
          testCase "a heading block takes its span; the next paragraph starts after it" $ do
            let ps = paginate 1 10 [FHeading 1 False 3 (lines' 20 1), FParagraph (lines' 30 3)]
            map poSlots ps @?= [[(0, SHeading 20 1), (3, SLine 30), (4, SLine 31), (5, SLine 32)]],
          testCase "a heading block is not split; it goes whole to the next page" $ do
            let ps = paginate 1 6 [FParagraph (lines' 0 4), FHeading 2 False 3 (lines' 20 1), FParagraph (lines' 30 2)]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 3)], [(0, SHeading 20 1), (3, SLine 30), (4, SLine 31)]],
          testCase "keeping a heading with the next paragraph counts its span and two lines" $ do
            -- 2 used, 5 free: span 3 + 2 lines fit
            let fits = paginate 1 7 [FParagraph (lines' 0 2), FHeading 2 False 3 (lines' 20 1), FParagraph (lines' 30 4)]
            take 1 (map (map snd . poSlots) fits) @?= [[SLine 0, SLine 1, SHeading 20 1, SLine 30, SLine 31]]
            -- 3 used, 4 free: span 3 + 2 lines do not fit
            let moves = paginate 1 7 [FParagraph (lines' 0 3), FHeading 2 False 3 (lines' 20 1), FParagraph (lines' 30 4)]
            map (map snd . poSlots) moves @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30, SLine 31, SLine 32, SLine 33]]
        ],
      testGroup
        "tables (golem-driver ADR 0008)"
        [ testCase "cell extents: the widest unbreakable piece and the natural width" $ do
            let env = defaultComposeEnv fs
            cellExtent (compose env "PDF") @?= (fs * 3 `div` 2, fs * 3 `div` 2)
            cellExtent (compose env "日本語") @?= (fs, 3 * fs)
            let (mn, nat) = cellExtent (compose env "あ。")
            mn @?= nat,
          testCase "column widths: natural when they fit" $
            columnWidths 100 [(10, 30), (20, 40)] @?= Right [30, 40],
          testCase "column widths: the rest shared in proportion, the remainder from the first column" $
            columnWidths 100 [(10, 60), (20, 80)] @?= Right [42, 58],
          testCase "column widths: minimum widths that do not fit are an error" $
            columnWidths 20 [(10, 30), (20, 40)] @?= Left (ColumnsTooWide 30 20),
          testCase "a row is as high as its tallest cell" $ do
            let env = defaultComposeEnv fs
            case layoutTable defaultParams (5 * fs) fs [AlignDefault, AlignDefault] [compose env "見", compose env "出"] [[compose env "あいうえお", compose env "い"]] of
              Right t -> do
                stWidths t @?= [3 * fs, fs]
                (stHeaderLines t, stRowLines t) @?= (1, [2])
              Left e -> assertFailure (show e),
          testCase "right and centre alignment shift a cell by the room it leaves" $ do
            let env = defaultComposeEnv fs
                table al = layoutTable defaultParams (10 * fs) fs [AlignLeft, al] [compose env "見出し", compose env "数"] [[compose env "あ", compose env "1"]]
                offsetOf al = case table al of
                  Right t -> [scOffset c | (_ : c : _) <- stRows t]
                  Left e -> error (show e)
            offsetOf AlignRight @?= [4 * fs + (fs - fs `div` 2)]
            offsetOf AlignCenter @?= [4 * fs + (fs - fs `div` 2) `div` 2]
            offsetOf AlignLeft @?= [4 * fs],
          testCase "cells do not hang punctuation: no line is wider than its column" $ do
            let env = (defaultComposeEnv fs) {ceHanging = False}
            case layoutTable defaultParams {pProtrusion = True} (4 * fs) fs [AlignDefault, AlignDefault] [compose env "見", compose env "出"] [[compose env "あいうえおかきくけこ。", compose env "い"]] of
              Right t ->
                sequence_
                  [ assertBool (show (end, w)) (end <= w)
                  | (row : _) <- stRows t,
                    (w : _) <- [stWidths t],
                    l <- scLines row,
                    let end = maybe 0 (\(Box bw _, x) -> x + bw) (lastBox (placeLine l))
                  ]
              Left e -> assertFailure (show e)
        ],
      testGroup
        "columns (docs/adr ADR 0018)"
        [ testCase "a paragraph fills the columns of a page in order, then the next page" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 8)]
            cols ps @?= [(1, 0), (1, 1), (2, 0)]
            map (length . poSlots) ps @?= [3, 3, 2]
            slots ps @?= [[0, 1, 2], [3, 4, 5], [6, 7]],
          testCase "an orphan at the end of a column goes to the next column" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 2), FParagraph (lines' 10 3)]
            cols ps @?= [(1, 0), (1, 1)]
            slots ps @?= [[0, 1], [10, 11, 12]],
          testCase "a recto heading starts in column 0 of the next odd page; the rest of the page stays empty" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 5), FHeading 1 True 1 (lines' 20 1)]
            cols ps @?= [(1, 0), (1, 1), (2, 0), (3, 0)]
            map poBlank ps @?= [False, False, True, False]
            slots ps @?= [[0, 1, 2], [3, 4], [], [20]],
          testCase "footnotes sit in the column of their marker and continue in the next column" $ do
            let withNote i n = LineBox i [NoteBody (nid (100 + i)) n] [] []
                ps = paginate 2 4 [FParagraph [withNote 0 1, LineBox 1 [] [] [], LineBox 2 [] [] [], LineBox 3 [] [] [], LineBox 4 [] [] []]]
            cols ps @?= [(1, 0), (1, 1)]
            map poFootnotes ps @?= [[(nid 100, 0, 1)], []]
            let long = paginate 2 4 [FParagraph [withNote 0 5, LineBox 1 [] [] []]]
            cols long @?= [(1, 0), (1, 1), (2, 0)]
            map poFootnotes long @?= [[(nid 100, 0, 2)], [(nid 100, 2, 2)], [(nid 100, 4, 1)]],
          testCase "a figure that does not fit goes to the top of the next column; text moves up" $ do
            let ps = paginate 2 5 [FParagraph (lines' 0 3), FFigure 99 3 ["fig"] [], FParagraph (lines' 10 2)]
            cols ps @?= [(1, 0), (1, 1)]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 10), (4, SLine 11)], [(0, SFigure 99)]],
          testCase "a table across a column boundary repeats its header" $ do
            let ps = paginate 2 4 [FTable 100 (lines' 0 1) [lines' (10 + i) 1 | i <- [0 .. 4]]]
            cols ps @?= [(1, 0), (1, 1)]
            map (map snd . poSlots) ps @?= [[SLine 0, SLine 10, SLine 11, SLine 12], [SLine 0, SLine 13, SLine 14]]
            map poTables ps @?= [[TableSegment 100 0 0 3], [TableSegment 100 0 0 2]],
          testCase "a label in the second column is on the page of that column" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 3), FParagraph [LineBox 50 [] ["x"] []]]
            cols ps @?= [(1, 0), (1, 1)]
            labelPages ps @?= Map.fromList [("x", 1)],
          testCase "a column break goes to the next column, then to the next page" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 1), FBreak BreakColumn, FParagraph (lines' 10 1), FBreak BreakColumn, FParagraph (lines' 20 1)]
            cols ps @?= [(1, 0), (1, 1), (2, 0)]
            slots ps @?= [[0], [10], [20]],
          testCase "a column break at the top of an empty column leaves it empty" $ do
            let ps = paginate 2 3 [FBreak BreakColumn, FParagraph (lines' 0 1)]
            cols ps @?= [(1, 1)]
            slots ps @?= [[0]],
          testCase "a column break on one column is a page break" $ do
            let flows k = [FParagraph (lines' 0 1), FBreak k, FParagraph (lines' 10 1)]
            paginate 1 3 (flows BreakColumn) @?= paginate 1 3 (flows BreakPage),
          testCase "one column: every part of the output is column 0 of its page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 12), FHeading 1 True 1 (lines' 20 1), FParagraph (lines' 30 3)]
            map poColumn ps @?= map (const 0) ps
            map poNumber ps @?= [1 .. length ps],
          testCase "a page break in column 0 goes to column 0 of the next page" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 1), FBreak BreakPage, FParagraph (lines' 10 1)]
            cols ps @?= [(1, 0), (2, 0)]
            slots ps @?= [[0], [10]]
            map poBlank ps @?= [False, False]
        ],
      testGroup
        "index columns (docs/adr ADR 0025)"
        [ testCase "without a switch every part is in the columns of the page" $ do
            let ps = paginate 2 3 [FParagraph (lines' 0 8)]
            map poColumnSet ps @?= map (const (ColumnSet 2 0 0 0)) ps,
          testCase "one column: after a heading of 2 lines the rest of the page is two columns of 8 lines" $ do
            let ps = paginate 1 10 ([FHeading 1 False 2 (lines' 0 1), FSwitchColumns index2] <> entries 100 16 <> [FRestoreColumns])
            sets ps @?= [(1, 0, 1, 0), (1, 0, 2, 2), (1, 1, 2, 2)]
            map (map fst . poSlots) ps @?= [[0], [2 .. 9], [2 .. 9]]
            slots ps @?= [[0], [100 .. 107], [108 .. 115]],
          testCase "twenty entries: the last 4 start column 0 of the next page" $ do
            let ps = paginate 1 10 ([FHeading 1 False 2 (lines' 0 1), FSwitchColumns index2] <> entries 100 20 <> [FRestoreColumns])
            sets ps @?= [(1, 0, 1, 0), (1, 0, 2, 2), (1, 1, 2, 2), (2, 0, 2, 0)]
            map (map fst . poSlots) (drop 3 ps) @?= [[0 .. 3]]
            slots (drop 3 ps) @?= [[116 .. 119]],
          testCase "no line left on the page: the columns start at line 0 of the next page" $ do
            let ps = paginate 1 10 ([FHeading 1 False 10 (lines' 0 1), FSwitchColumns index2] <> entries 100 3 <> [FRestoreColumns])
            sets ps @?= [(1, 0, 1, 0), (2, 0, 2, 0)]
            map (map fst . poSlots) ps @?= [[0], [0 .. 2]],
          testCase "footnotes on the page of the switch: the columns leave their lines" $ do
            let withNote i n = LineBox i [NoteBody (nid (500 + i)) n] [] []
                -- a note of 1 line and its separator: 2 grid lines
                ps = paginate 1 10 ([FParagraph [withNote 0 1, LineBox 1 [] [] []], FSwitchColumns index2] <> entries 100 12 <> [FRestoreColumns])
            sets ps @?= [(1, 0, 1, 0), (1, 0, 2, 2), (1, 1, 2, 2)]
            map (map fst . poSlots) ps @?= [[0, 1], [2 .. 7], [2 .. 7]]
            map poFootnotes ps @?= [[(nid 500, 0, 1)], [], []],
          testCase "two columns: the page is closed and three columns start at line 0 of the next page" $ do
            let ps = paginate 2 10 ([FParagraph (lines' 0 3), FSwitchColumns index3 {csColumns = 3}] <> entries 100 4 <> [FRestoreColumns])
            sets ps @?= [(1, 0, 2, 0), (2, 0, 3, 0)]
            map (map fst . poSlots) ps @?= [[0, 1, 2], [0 .. 3]],
          testCase "after the index the flow goes on at line 0 of the next page in the columns of the page" $ do
            let ps = paginate 1 10 ([FHeading 1 False 2 (lines' 0 1), FSwitchColumns index2] <> entries 100 3 <> [FRestoreColumns, FParagraph (lines' 200 2)])
            sets ps @?= [(1, 0, 1, 0), (1, 0, 2, 2), (2, 0, 1, 0)]
            last (map poColumnSet ps) @?= ColumnSet 1 0 0 0
            slots (drop 2 ps) @?= [[200, 201]],
          testCase "an index at the end of the book makes no page after it" $ do
            let ps = paginate 1 10 ([FHeading 1 False 2 (lines' 0 1), FSwitchColumns index2] <> entries 100 3 <> [FRestoreColumns])
            map poNumber ps @?= [1, 1],
          testCase "the column set is the same in either writing direction: paginate knows no direction" $ do
            let flows = [FHeading 1 False 2 (lines' 0 1), FSwitchColumns index2] <> entries 100 16 <> [FRestoreColumns]
            map poColumnSet (paginate 1 10 flows) @?= [ColumnSet 1 0 0 0, index2 {csFirstLine = 2}, index2 {csFirstLine = 2}]
        ],
      testGroup
        "table pagination (golem-driver ADR 0008)"
        [ testCase "a table breaks between rows and repeats its header" $ do
            let ps = paginate 1 4 [FTable 100 (lines' 0 1) [lines' (10 + i) 1 | i <- [0 .. 4]]]
            map (map snd . poSlots) ps @?= [[SLine 0, SLine 10, SLine 11, SLine 12], [SLine 0, SLine 13, SLine 14]]
            map poTables ps @?= [[TableSegment 100 0 0 3], [TableSegment 100 0 0 2]],
          testCase "the header's label and note are counted once" $ do
            let header = [LineBox 0 [NoteBody (nid 900) 1] ["tbl"] []]
                ps = paginate 1 4 [FTable 100 header [lines' (10 + i) 1 | i <- [0 .. 4]]]
            map poLabels ps @?= ["tbl"] : replicate (length ps - 1) []
            [(poNumber p, n) | p <- ps, (n, _, _) <- poFootnotes p] @?= [(1, nid 900)],
          testCase "a table that cannot start with its header and first row goes to the next page" $ do
            let ps = paginate 1 4 [FParagraph (lines' 0 3), FTable 100 (lines' 20 1) [lines' 30 1]]
            map (map snd . poSlots) ps @?= [[SLine 0, SLine 1, SLine 2], [SLine 20, SLine 30]],
          testCase "a row is never split across pages" $ do
            let ps = paginate 1 4 [FTable 100 (lines' 0 1) [lines' 10 1, lines' 20 1, lines' 30 2]]
            map (map snd . poSlots) ps @?= [[SLine 0, SLine 10, SLine 20], [SLine 0, SLine 30, SLine 31]],
          testCase "a heading before a table stays with its header and first row" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 3), FHeading 1 False 1 (lines' 20 1), FTable 100 (lines' 30 1) [lines' 40 2]]
            map (map snd . poSlots) ps @?= [[SLine 0, SLine 1, SLine 2], [SHeading 20 1, SLine 30, SLine 40, SLine 41]]
        ],
      testGroup
        "wrapped figures (ADR 0004)"
        [ testCase "the exclusion rounds up to grid lines and shortens only the lines beside it" $ do
            let ex = exclusion WrapEnd 17 3 40 50
            exLines ex @?= 4
            [wrappedLineWidth 100 ex 0 i | i <- [0 .. 5]] @?= [57, 57, 57, 57, 100, 100]
            [wrappedLineWidth 100 ex 3 i | i <- [0 .. 2]] @?= [57, 100, 100],
          testCase "a paragraph beside the exclusion is broken with L*(i)" $ do
            let ex = exclusion WrapStart 17 3 40 30
                r = breakParagraph defaultParams (wrappedLineWidth 160 ex 0) (paragraph (replicate 14 30))
            map lineTarget (take 3 (brLines r)) @?= [117, 117, 160],
          testCase "a continued paragraph has no first line to keep from being an orphan (golem-driver ADR 0005)" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 4), FContinued (lines' 10 3)]
            slots ps @?= [[0, 1, 2, 3, 10], [11, 12]]
            -- the last line alone would be a widow: break a line earlier
            let qs = paginate 1 5 [FParagraph (lines' 0 2), FContinued (lines' 10 4)]
            slots qs @?= [[0, 1, 10, 11], [12, 13]],
          testCase "a wrapped figure that does not fit the page goes to the next page" $ do
            let ps = paginate 1 5 [FParagraph (lines' 0 3), FWrapped 7 3 [] [] (lines' 50 3)]
            map (map snd . poSlots) ps @?= [[SLine 0, SLine 1, SLine 2], [SWrapped 7, SLine 50, SLine 51, SLine 52]]
        ],
      testGroup
        "sidenotes (ADR 0006)"
        [ testCase "notes sit at their marker line when they do not collide" $
            placeSidenotes 100 2 [(0, 10), (30, 10)] @?= Right [0, 30],
          testCase "close notes are pushed down in order" $
            placeSidenotes 100 2 [(0, 10), (5, 10), (6, 10)] @?= Right [0, 12, 24],
          testCase "notes near the bottom pull earlier ones up" $
            placeSidenotes 100 2 [(70, 10), (85, 20)] @?= Right [68, 80],
          testCase "a sidenote in a vertical paragraph is an error" $ do
            let sn = Sidenote (mkSpan (FileId 0) 3 9) 1 [sp0 "注"]
            length (verticalSidenotes (defaultComposeEnv fs) {ceVertical = True} [sp0 "本文", sn]) @?= 1
            verticalSidenotes (defaultComposeEnv fs) [sn] @?= [],
          testCase "an anchor indexes its marker among the composed items, spacing included" $ do
            let (items, anchors) = composeInlines (defaultComposeEnv fs) [sp0 "あいうえお", Note (mkSpan (FileId 0) 0 1) 1 [sp0 "注"], sp0 "かき"]
            case anchors of
              [AnchorNote i 1 _ _] -> case drop i items of
                (Box _ c : _) -> bcText c @?= "*1"
                other -> assertFailure (show (take 1 other))
              other -> assertFailure (show other),
          testCase "an index mark keeps its span and indexes the next item (golem-driver ADR 0007)" $ do
            let m = mkSpan (FileId 0) 3 9
                e = IndexEntry ["組版"] ["くみはん"]
                (items, anchors) = composeInlines (defaultComposeEnv fs) [sp0 "前", IndexMark m e, sp0 "後"]
            case anchors of
              [AnchorIndex i m' e'] -> do
                (m', e') @?= (m, e)
                [bcText c | Box _ c <- take 1 (drop i items)] @?= ["後"]
              other -> assertFailure (show other),
          testCase "a citation shows its number when there is one" $ do
            let cite = [Cite (mkSpan (FileId 0) 0 1) "knuth1981"]
                texts env = [bcText c | Box _ c <- fst (composeInlines env cite)]
            T.concat (texts (defaultComposeEnv fs) {ceCiteNumber = \k -> if k == "knuth1981" then Just 1 else Nothing}) @?= "[1]"
            T.concat (texts (defaultComposeEnv fs)) @?= "[knuth1981]",
          testCase "the sidenote marker in the text follows the style (golem-driver ADR 0006)" $ do
            let snSpan = mkSpan (FileId 0) 3 9
                sn = Sidenote snSpan 1 [sp0 "注"]
                boxes m = [bcText c | Box _ c <- fst (composeInlines (defaultComposeEnv fs) {ceSidenoteMarker = m} [sp0 "本", sn])]
            boxes MarkerNumber @?= ["本", "1"]
            boxes MarkerSymbol @?= ["本", "※"]
            boxes MarkerNone @?= ["本"]
            -- the anchor indexes the marker box, after the spacing before it
            snd (composeInlines (defaultComposeEnv fs) [sp0 "本", sn]) @?= [AnchorSidenote 2 1 snSpan [sp0 "注"]],
          testCase "a variation selector joins the box of its base character (golem-pdf ADR 0006)" $ do
            [bcText c | Box _ c <- compose vsEnv "葛\xE0100あ"] @?= ["葛\xE0100", "あ"]
            [bcText c | Box _ c <- compose vsEnv "a\xFE00葛\xE0100\xFE01"] @?= ["a\xFE00", "葛\xE0100\xFE01"],
          testCase "a variation selector is shaped with its base character for the advance" $ do
            let env = (defaultComposeEnv fs) {ceWordAdvance = \_ t -> if t == "葛\xE0100" then 3 / 2 else 1}
            [w | Box w _ <- compose env "葛\xE0100"] @?= [fs + fs `div` 2],
          testCase "punctuation spacing after a variation selector is as without it" $
            map stripVs (compose vsEnv "葛\xE0100、あ") @?= compose vsEnv "葛、あ",
          testCase "line-start prohibitions after an opening bracket with a variation selector are as without it" $ do
            let items = compose vsEnv "「\xFE00あい"
            map stripVs items @?= compose vsEnv "「あい"
            breakBeforeBox items 1 @?= False,
          testCase "a variation selector at the paragraph start stays a box of its own" $
            [bcText c | Box _ c <- compose vsEnv "\xE0100葛"] @?= ["\xE0100", "葛"],
          testCase "too many notes, or one taller than the column, are errors" $ do
            placeSidenotes 30 2 [(0, 10), (0, 10), (0, 10)] @?= Left (DoesNotFit 2)
            placeSidenotes 30 2 [(0, 40)] @?= Left (TooTall 0)
        ]
    ]
  where
    sp = mkSpan (FileId 0) 0 0
    bold = CharStyle sp "bold"
    both = Synthetic True False
    -- Latin characters: one em in the role "wide", half an em otherwise
    lookEnv restyle =
      let adv lk c
            | charClass c /= Western = 1
            | lkLatinFace lk == "wide" = 1
            | otherwise = 1 / 2
       in (defaultComposeEnv fs) {ceAdvance = adv, ceWordAdvance = \lk w -> sum (map (adv lk) (T.unpack w)), ceRestyle = restyle}
    interleave xs g = concat [x : [g | i < length xs - 1] | (i, x) <- zip [0 :: Int ..] xs]
    head' (x : _) = x
    head' [] = ""
    lastBox xs = case [x | x@(Box {}, _) <- xs] of
      [] -> Nothing
      bs -> Just (last bs)
    last' xs = if null xs then "" else last xs
    lines' base n = [LineBox (base + i) [] [] [] | i <- [0 .. n - 1]]
    slots = map (\p -> [i | (_, s) <- poSlots p, i <- slotLines s] <> [i | (_, SFigure i) <- poSlots p])
    cols = map (\p -> (poNumber p, poColumn p))
    -- page, column, columns of the set and its first line (docs/adr ADR 0025)
    sets = map (\p -> (poNumber p, poColumn p, csColumns (poColumnSet p), csFirstLine (poColumnSet p)))
    index2 = ColumnSet 2 (15 * 65536) (2 * 65536) 0
    index3 = index2
    entries base n = [FParagraph [LineBox (base + i) [] [] []] | i <- [0 .. n - 1]]
    slotLines = \case
      SLine i -> [i]
      SHeading i n -> [i .. i + n - 1]
      _ -> []

{- | The ruby style of the tests with every alignment the same and a half-em overhang.
| Kerning, tracking and baseline shift (docs/adr/0020).
-}
characterFeatureTests :: [TestTree]
characterFeatureTests =
  [ testCase "the plain look: metrics, no tracking, no proportional metrics, no shift" $
      (lkKerning look0, lkTracking look0, lkProportional look0, lkBaselineShift look0) @?= (KernMetrics, 0, False, 0),
    testCase "the default environment kerns nothing" $
      ceKern (defaultComposeEnv fs) look0 'あ' 'い' @?= 0,
    testCase "a Japanese pair is kerned: the first box narrower, its end edge given back" $ do
      [(w, bcEdgeEnd c) | Box w c <- compose kernEnv "あい"] @?= [(fs - tenth, tenth), (fs, 0)]
      let none = kernEnv {ceLook = look0 {lkKerning = KernNone}}
      [(w, bcEdgeEnd c) | Box w c <- compose none "あい"] @?= [(fs, 0), (fs, 0)]
      let equal = kernEnv {ceLook = look0 {lkKerning = KernJapaneseEqualWidth}}
      [(w, bcEdgeEnd c) | Box w c <- compose equal "あい"] @?= [(fs, 0), (fs, 0)],
    testCase "pairs with punctuation are not kerned" $ do
      let anyPair = kernEnv {ceKern = \_ _ _ -> -(1 / 10)}
      [(bcText c, bcEdgeEnd c) | Box _ c <- compose anyPair "あ」"] @?= [("あ", 0), ("」", 0)]
      [(bcText c, bcEdgeEnd c) | Box _ c <- compose anyPair "「あ"] @?= [("「", 0), ("あ", 0)]
      [(bcText c, bcEdgeEnd c) | Box _ c <- compose anyPair "あ、い"] @?= [("あ", 0), ("、", 0), ("い", 0)],
    testCase "a pair of different looks is not kerned" $ do
      let env = kernEnv {ceRestyle = \lk _ -> lk {lkColor = Just "red"}}
      [(w, bcEdgeEnd c) | Box w c <- fst (composeInlines env [sp0 "あ", Color (mkSpan (FileId 0) 0 0) "red" [sp0 "い"]])] @?= [(fs, 0), (fs, 0)],
    testCase "tracking widens Japanese boxes, Latin words and spaces; every box gives it back at its end" $ do
      let env = (defaultComposeEnv fs) {ceLook = look0 {lkTracking = 100}}
          plain = defaultComposeEnv fs
      [(w, bcEdgeEnd c) | Box w c <- compose env "あ"] @?= [(fs + tenth, negate tenth)]
      let wordBoxes e = [(w, bcEdgeEnd c) | Box w c <- compose e "abc def"]
          gluesOf e = [w | Glue w _ _ <- take 3 (compose e "abc def")]
      wordBoxes env @?= [(w + 3 * tenth, negate tenth) | (w, _) <- wordBoxes plain]
      gluesOf env @?= [w + tenth | w <- gluesOf plain],
    testCase "ruby, tate-chu-yoko and note marks get no tracking" $ do
      let env = (defaultComposeEnv fs) {ceLook = look0 {lkTracking = 100}}
          sp = mkSpan (FileId 0) 0 0
      [(w, bcEdgeEnd c) | Box w c <- fst (composeInlines env [Tcy sp "12"])] @?= [(fs, 0)]
      [(w, bcEdgeEnd c) | Box w c <- fst (composeInlines env [Note sp 1 []])] @?= [(fs `div` 2, 0)],
    testCase "with tracking, the last box of every line ends at the measure" $ do
      let env = (defaultComposeEnv fs) {ceLook = look0 {lkTracking = 100}}
          items = compose env (T.replicate 40 "あ")
          ls = brLines (breakParagraph defaultParams (const (10 * fs)) items)
      assertBool "several lines" (length ls > 2)
      sequence_
        [ case [(off, w, c) | (Box w c, off) <- placeLine l] of
            [] -> assertFailure "no box"
            bs -> let (off, w, c) = last bs in assertBool (show (off + w + bcEdgeEnd c, lineTarget l)) (abs (off + w + bcEdgeEnd c - lineTarget l) <= 1)
        | l <- init ls
        ],
    testCase "the baseline shift does not change the line breaks" $ do
      let at shift = (defaultComposeEnv fs) {ceLook = look0 {lkBaselineShift = shift}}
          breaksOf e = brPositions (breakParagraph defaultParams (const (10 * fs)) (compose e (T.replicate 25 "あい、")))
      breaksOf (at (2 * 65536)) @?= breaksOf (at 0),
    testCase "pairs with an inseparable character are not kerned, horizontal or vertical (golem-driver ADR 0020)" $ do
      let kernAll v = (defaultComposeEnv fs) {ceKern = \_ _ _ -> -(88 / 1000), ceVertical = v}
          plain v = (defaultComposeEnv fs) {ceVertical = v}
          boxes e t = [(bcText c, w, bcEdgeEnd c) | Box w c <- compose e t]
      sequence_
        [ boxes (kernAll v) t @?= boxes (plain v) t
        | v <- [False, True],
          t <- ["あ\x2014\x2014い", "あ……い", "あ‥‥い", "漢\x2014", "\x2014漢"]
        ]
      sequence_ [assertBool (show (boxes (plain v) "あ\x2014\x2014い")) (all (\(_, _, e) -> e == 0) (boxes (plain v) "あ\x2014\x2014い")) | v <- [False, True]]
      -- a Japanese pair is kerned as before
      sequence_ [map (\(_, _, e) -> e) (boxes (kernAll v) "あい") @?= [round (toRational fs * 88 / 1000), 0] | v <- [False, True]]
  ]
  where
    tenth = fs `div` 10
    kernEnv = (defaultComposeEnv fs) {ceKern = \_ a b -> if (a, b) == ('あ', 'い') then -(1 / 10) else 0}

{- | Ruby base character styles (golem-layout ADR 0011): an advance of 1
in the body role and 1.2 in the heading role; the character style h sets
the heading role, a colour its swatch.
-}
rubyBaseTests :: [TestTree]
rubyBaseTests =
  [ testCase "a character style in a group ruby base: the looks of the base and the width" $ do
      let (looks, ws) = baseOf [rubyIn [([t "漢", CharStyle sp "h" [t "字"]], Just "か")]]
      looks @?= [[outer, heading]]
      ws @?= [2200],
    testCase "no character style: every base character has the outer look, the width is as before" $ do
      let (looks, ws) = baseOf [rubyIn [([t "漢字"], Just "か")]]
      looks @?= [[outer, outer]]
      ws @?= [2000],
    testCase "a colour in the base: the character has its swatch" $ do
      let (looks, _) = baseOf [rubyIn [([t "漢", Color sp "red" [t "字"]], Just "かんじ")]]
      looks @?= [[outer, outer {lkColor = Just "red"}]],
    testCase "kenten in the base: the character's look is the look around it, without kenten" $ do
      let (looks, _) = baseOf [rubyIn [([Kenten sp Nothing [t "漢"], t "字"], Just "かんじ")]]
      looks @?= [[outer, outer]],
    testCase "mono ruby: the allowance onto the neighbour is measured in the neighbour's base looks" $ do
      let style = rubyStyle R.AlignCenter
          env' = env {ceRuby = style}
          boxesOf segs = rubyBoxes env' [rubyIn segs, t "の"]
          -- the first base in the heading role is 1200 wide: 350 free beside its reading of 500
          expected room = let p = placeRuby style MonoRuby [1000] [500, 500, 500, 500] (room, 500) in (rpWidth p, (rpOverhang p, rpOverhang p))
      drop 1 (boxesOf [([CharStyle sp "h" [t "東"]], Just "ひ"), ([t "京"], Just "きょうと")]) @?= [expected 350]
      assertBool "the look matters" (expected 350 /= expected 250),
    testCase "boxes other than ruby have no base looks" $ do
      let items = fst (composeInlines env [t "前", rubyIn [([t "字"], Just "じ")], CharStyle sp "h" [t "後"], Tcy sp "12"])
      [bcBaseLooks c | Box _ c <- items, boxKind c `notElem` [KindRuby, KindGroupRuby]] @?= [[], [], []]
  ]
  where
    sp = mkSpan (FileId 0) 0 0
    t = Text sp
    env =
      (defaultComposeEnv 1000)
        { ceAdvance = \lk _ -> if lkFace lk == "heading" then 6 / 5 else 1,
          ceRestyle = \lk -> \case
            CharStyle _ "h" _ -> lk {lkFace = "heading", lkLatinFace = "heading"}
            Color _ c _ -> lk {lkColor = Just c}
            _ -> lk
        }
    outer = ceLook env
    heading = outer {lkFace = "heading", lkLatinFace = "heading"}
    rubyIn segs = Ruby sp () [RubySegment base r | (base, r) <- segs]
    baseOf is = unzip [(bcBaseLooks c, w) | Box w c <- fst (composeInlines env is), boxKind c `elem` [KindRuby, KindGroupRuby]]

rubyStyle :: R.RubyAlign -> RubyStyle
rubyStyle a = RubyStyle a a a 500 True

{- | Ruby boxes of composed inlines at 1000sp: their width and their edges.
| The boxes of one-character text: the character, its kind and its kenten shape.
-}
kentenBoxes :: [Inline] -> [(Text, BoxKind, Maybe KentenShape)]
kentenBoxes is = [(bcText c, boxKind c, lkKenten (bcLook c)) | Box _ c <- fst (composeInlines (defaultComposeEnv 1000) is)]

kentenTests :: [TestTree]
kentenTests =
  [ testCase "the ten shapes and their characters" $
      map kentenChar [minBound .. maxBound] @?= "\xFE45\xFE46\x2022\x25E6\x25CF\x25CB\x25C9\x25CE\x25B2\x25B3",
    testCase "the names of the shapes" $ do
      map kentenShapeName [minBound .. maxBound] @?= ["sesame", "open-sesame", "dot", "open-dot", "circle", "open-circle", "double-circle", "open-double-circle", "triangle", "open-triangle"]
      map (kentenShapeFromName . kentenShapeName) [minBound .. maxBound] @?= map Just [minBound .. maxBound]
      kentenShapeFromName "star" @?= Nothing,
    testCase "plainLook has no kenten" $
      lkKenten (plainLook "body" 1000) @?= Nothing,
    testCase "punctuation in kenten is punctuation; ideographs and the long vowel mark get the shape" $
      kentenBoxes [Kenten sp00 (Just "circle") [sp0 "漢、「字」ー"]]
        @?= [ ("漢", KindKenten, Just KentenCircle),
              ("、", KindPunctuation, Just KentenCircle),
              ("「", KindPunctuation, Just KentenCircle),
              ("字", KindKenten, Just KentenCircle),
              ("」", KindPunctuation, Just KentenCircle),
              ("ー", KindKenten, Just KentenCircle)
            ],
    testCase "a space and an iteration mark in kenten" $
      [(t, k) | (t, k, _) <- kentenBoxes [Kenten sp00 (Just "dot") [sp0 "々\x3000"]]] @?= [("々", KindKenten), ("\x3000", KindText)],
    testCase "the inner kenten wins" $
      kentenBoxes [Kenten sp00 (Just "dot") [sp0 "あ", Kenten sp00 (Just "circle") [sp0 "い"]]]
        @?= [("あ", KindKenten, Just KentenDot), ("い", KindKenten, Just KentenCircle)],
    testCase "kenten without a shape is sesame" $
      kentenBoxes [Kenten sp00 Nothing [sp0 "あ"]] @?= [("あ", KindKenten, Just KentenSesame)],
    testCase "a Latin word in kenten stays text" $
      [k | (t, k, _) <- kentenBoxes [Kenten sp00 (Just "circle") [sp0 "Golem"]], t == "Golem"] @?= [KindText],
    testCase "text outside kenten has no shape" $
      kentenBoxes [sp0 "字"] @?= [("字", KindText, Nothing)]
  ]
  where
    sp00 = mkSpan (FileId 0) 0 0

rubyBoxes :: ComposeEnv -> [Inline] -> [(Sp, (Sp, Sp))]
rubyBoxes env is = [(w, (bcEdgeStart c, bcEdgeEnd c)) | Box w c <- fst (composeInlines env is), boxKind c `elem` [KindRuby, KindGroupRuby]]

rubyOf :: [(Text, Maybe Text)] -> Inline
rubyOf segs = Ruby (mkSpan (FileId 0) 0 0) () [RubySegment [Text (mkSpan (FileId 0) 0 0) b] r | (b, r) <- segs]

-- | A box with edges (the overhang of a ruby).
edgeBox :: Sp -> (Sp, Sp) -> Item
edgeBox w (a, b) = Box w (BoxContent "r" False 0 0 0 look0 a b [])

-- | The start and end of each box of a set line.
boxSpans :: Line -> [(Sp, Sp)]
boxSpans l =
  let placed = placeLine l
      ends = [round (toRational off + toRational w) | (Box w _, off) <- placed]
   in zip [off | (Box {}, off) <- placed] ends

rubyTests :: [TestTree]
rubyTests =
  [ testCase "a group ruby shorter than its base, in each alignment" $ do
      let at a = placeRuby (rubyStyle a) GroupRuby [1000, 1000, 1000] [500, 500] (0, 0)
      rpReading (at R.Align121) @?= [500, 2000]
      rpReading (at R.Align010) @?= [0, 2500]
      rpReading (at R.AlignCenter) @?= [1000, 1500]
      rpReading (at R.AlignStart) @?= [0, 500]
      mapM_ (\a -> (rpWidth (at a), rpBase (at a)) @?= (3000, [0, 1000, 2000])) [R.Align121, R.Align010, R.AlignCenter, R.AlignStart],
    testCase "a one-character reading: 1:2:1 and 0:1:0 centre it" $ do
      let at a = rpReading (placeRuby (rubyStyle a) GroupRuby [1000, 1000] [500] (0, 0))
      at R.Align121 @?= at R.AlignCenter
      at R.Align010 @?= at R.AlignCenter,
    testCase "a mono ruby: centred or at the start" $ do
      rpReading (placeRuby (rubyStyle R.AlignCenter) MonoRuby [1000] [500] (0, 0)) @?= [250]
      rpReading (placeRuby (rubyStyle R.AlignStart) MonoRuby [1000] [500] (0, 0)) @?= [0],
    testCase "a long reading overhangs, then spaces the base" $ do
      let reading = replicate 6 500
          full = placeRuby (rubyStyle R.Align121) GroupRuby [1000, 1000] reading (500, 500)
      (rpOverhang full, rpWidth full, take 1 (rpReading full), rpBase full) @?= (500, 2000, [-500], [0, 1000])
      let at a = placeRuby (rubyStyle a) GroupRuby [1000, 1000] reading (250, 250)
      (rpWidth (at R.Align121), take 1 (rpReading (at R.Align121))) @?= (2500, [-250])
      rpBase (at R.Align121) @?= [125, 1375]
      rpBase (at R.Align010) @?= [0, 1500]
      rpBase (at R.AlignCenter) @?= [250, 1250]
      let oneSide = placeRuby (rubyStyle R.Align121) GroupRuby [1000, 1000] reading (500, 0)
      (rpOverhang oneSide, rpWidth oneSide) @?= (0, 3000),
    testProperty "ruby placement: the box holds the base, the reading fits the overhang, positions increase" $ property $ do
      base <- forAll (Gen.list (Range.linear 1 5) (Gen.integral (Range.linear 100 2000)))
      reading <- forAll (Gen.list (Range.linear 1 8) (Gen.integral (Range.linear 50 1000)))
      a <- forAll (Gen.integral (Range.linear 0 1000))
      b <- forAll (Gen.integral (Range.linear 0 1000))
      align <- forAll (Gen.element [R.Align121, R.Align010, R.AlignCenter, R.AlignStart])
      kind <- forAll (Gen.element [MonoRuby, GroupRuby])
      let r = placeRuby (rubyStyle align) kind base reading (a, b)
          increasing xs = and (zipWith (<) xs (drop 1 xs))
      assert (rpWidth r >= sum base)
      assert (rpWidth r >= sum reading - 2 * rpOverhang r)
      assert (increasing (rpBase r) && increasing (rpReading r))
      assert (last (rpBase r) + last base <= rpWidth r),
    testCase "a reading overhangs kana on both sides" $
      rubyBoxes (defaultComposeEnv 1000) [sp0 "の", rubyOf [("字", Just "あいう")], sp0 "の"] @?= [(1000, (250, 250))],
    testCase "no overhang onto a kanji, a kenten character or with overhang-onto none" $ do
      rubyBoxes (defaultComposeEnv 1000) [sp0 "漢", rubyOf [("字", Just "あいう")], sp0 "の"] @?= [(1500, (0, 0))]
      rubyBoxes (defaultComposeEnv 1000) [Kenten (mkSpan (FileId 0) 0 0) Nothing [sp0 "の"], rubyOf [("字", Just "あいう")], sp0 "の"] @?= [(1500, (0, 0))]
      let none = (defaultComposeEnv 1000) {ceRuby = (defaultRubyStyle 1000) {rsOverhangOntoKana = False}}
      map fst (rubyBoxes none [sp0 "の", rubyOf [("字", Just "あいう")], sp0 "の"]) @?= [1500],
    testCase "mono ruby overhangs only the free space of the next reading" $ do
      map fst (rubyBoxes (defaultComposeEnv 1000) [sp0 "の", rubyOf [("東", Just "とう"), ("京", Just "きょう")], sp0 "の"]) @?= [1000, 1500]
      rubyBoxes (defaultComposeEnv 1000) [sp0 "の", rubyOf [("東", Just "ひ"), ("京", Just "きょう")], sp0 "の"] @?= [(1000, (0, 0)), (1000, (250, 250))],
    testCase "a Latin reading is measured with the advances" $
      map fst (rubyBoxes (defaultComposeEnv 1000) [rubyOf [("字", Just "abcde")]]) @?= [1250],
    testCase "the edges of a box at the line start, inside and at the line end" $
      mapM_
        ( \prot -> do
            let params = defaultParams {pProtrusion = prot}
                lineOf items w = case brLines (breakParagraph params (const w) (items <> finish)) of
                  [l] -> pure l
                  other -> assertFailure (show (length other))
            start <- lineOf [edgeBox 10 (3, 0), Glue 5 5 5, box 10, Glue 5 5 5, box 10] 38
            take 1 (boxSpans start) @?= [(3, 13)]
            map snd (drop 2 (boxSpans start)) @?= [38]
            lineEdge start @?= (3, 0)
            middle <- lineOf [box 10, Glue 5 5 5, edgeBox 10 (3, 3), Glue 5 5 5, box 10] 40
            map fst (boxSpans middle) @?= [0, 15, 30]
            end <- lineOf [box 10, Glue 5 5 5, box 10, Glue 5 5 5, edgeBox 10 (0, 3)] 38
            map snd (drop 2 (boxSpans end)) @?= [35]
        )
        [False, True]
  ]

orientationTests :: [TestTree]
orientationTests =
  [ testCase "the characters of the ADR take their UAX #50 values" $ do
      let of' = map verticalOrientation
      of' "\x2014\x2015\x2026\x2E3A" @?= replicate 4 Rotated
      of' "\x301C\xFF5E\x300C\x30FC" @?= replicate 4 TransformedRotated
      of' "\x3001" @?= [TransformedUpright]
      of' "漢あ\xFE31" @?= replicate 3 Upright
      map turnsInVertical "\x2014\x301C\x3001漢" @?= [True, True, False, False],
    testCase "the ranges ascend and do not overlap" $ do
      assertBool "not empty" (not (null orientationRanges))
      assertBool "each range ordered" (and [lo <= hi | (lo, hi, _) <- orientationRanges])
      assertBool "ascending and disjoint" (and (zipWith (\(_, hi, _) (lo, _, _) -> hi < lo) orientationRanges (drop 1 orientationRanges)))
      assertBool ("the Unicode version: " <> orientationVersion) ("VerticalOrientation-" `isPrefixOf` orientationVersion),
    testCase "unlisted code points follow the defaults of the file" $ do
      -- unassigned in CJK Unified Ideographs Extension B..C: listed as U
      verticalOrientation '\x2A6E0' @?= Upright
      -- unassigned in Greek, not listed: the @missing value R
      verticalOrientation '\x0378' @?= Rotated
      verticalOrientation '\x10FFFF' @?= Rotated
  ]

-- ------------------------------------------------------------------ aki (docs/adr ADR 0019)

-- | A character of each of the 15 classes.
akiRepresentatives :: [Char]
akiRepresentatives = "「」゠！・。、…々ーぁ\x3000あ漢A"

{- | The spacing of the composition before docs/adr ADR 0019, as it was
written in 'normalize', applied to the boxes of a composition and its
paragraph end. The inter-character stretch is rounded, as the aki sets
convert it.
-}
referenceNormalize :: ComposeEnv -> [Item] -> [Item]
referenceNormalize env items = go Nothing [it | it@Box {} <- items] <> lineEndItems
  where
    lineEndItems = [Penalty 0 infPenalty NoHyphen, Glue 0 filStretch 0, Penalty 0 (negate infPenalty) NoHyphen]
    fsz = ceFontSize env
    em r = round (r * toRational fsz)
    go _ [] = []
    go prev (x : rest) = case (prev, x) of
      (Just p, Box _ c) -> between p c <> [x] <> go (Just c) rest
      (_, Box _ c) -> leading c <> [x] <> go (Just c) rest
      _ -> x : go Nothing rest
    sizeOf c = toRational (lkSize (bcLook c))
    leading c = case textClass c of
      Just cls | fst (punctSpace cls) > 0 -> let w = round (fst (punctSpace cls) * sizeOf c) in [Glue w 0 w]
      _ -> []
    trailingSpace c = maybe 0 (snd . punctSpace) (textClass c) * sizeOf c
    leadingSpace c = maybe 0 (fst . punctSpace) (textClass c) * sizeOf c
    textClass c = case T.unsnoc (bcText c) of
      Just (_, ch) | boxKind c `elem` [KindText, KindPunctuation, KindKenten] && T.length (bcText c) == 1 -> Just (charClass ch)
      _ -> Nothing
    firstClass c = case T.uncons (bcText c) of
      Just (ch, _) | not (isRubyBox c) -> Just (charClass ch)
      _ -> Nothing
    lastClass c = case T.unsnoc (bcText c) of
      Just (_, ch) | not (isRubyBox c) -> Just (charClass ch)
      _ -> Nothing
    isRubyBox c = boxKind c `elem` [KindRuby, KindGroupRuby]
    between p c =
      let pc = lastClass p
          cc = firstClass c
          strict = ceKinsokuStrict env
          noBreak =
            maybe False (lineStartProhibited strict) cc
              || maybe False lineEndProhibited pc
              || (pc == Just Inseparable && cc == Just Inseparable)
              || (pc == Just Western && cc == Just Western && bcExpandable p && bcExpandable c)
          space = combined (trailingSpace p) (leadingSpace c) pc cc
          isJa k = k /= Just Western
          notPunct = maybe True (\cl -> punctSpace cl == (0, 0))
          waou = (pc == Just Western && isJa cc && isJust cc && space == 0 && notPunct cc) || (cc == Just Western && isJa pc && isJust pc && space == 0 && notPunct pc)
          pen = [Penalty 0 infPenalty NoHyphen | noBreak]
       in if space > 0
            then pen <> [Glue (round space) 0 (round space)]
            else
              if waou
                then pen <> [Glue (em (1 / 4)) (em (1 / 4)) (em (1 / 8))]
                else
                  if noBreak
                    then []
                    else
                      if bothJapanese pc cc
                        then [Glue 0 (em (1 / 10)) 0]
                        else [Penalty 0 0 NoHyphen | not (bcExpandable p && bcExpandable c)]
    bothJapanese pc cc = maybe False (/= Western) pc && maybe False (/= Western) cc
    combined post pre pc cc
      | post == 0 = pre
      | pre == 0 = if cc `elem` map Just [Closing, FullStop, Comma] then 0 else post
      | pc `elem` map Just [Closing, FullStop, Comma] && cc == Just Opening = max post pre
      | pc == Just MiddleDot || cc == Just MiddleDot = post + pre
      | otherwise = 0

-- | The texts of the composition: every pair of representatives, and each alone.
akiTexts :: [Text]
akiTexts = [T.pack [a, b] | a <- akiRepresentatives, b <- akiRepresentatives] <> [T.singleton a | a <- akiRepresentatives]

-- | The set gyomatsu-yakumono-hankaku with one more rule.
akiWith :: [Text] -> [Text] -> Aki.Aki -> AkiSet
akiWith bs as a = withAkiRule (concatMap akiPositions bs) (concatMap akiPositions as) a defaultAkiSet

akiEnv :: AkiSet -> ComposeEnv
akiEnv s = (defaultComposeEnv fs) {ceAkiSet = s}

-- | The distance from the right edge of the last box of a set line to the line end.
trailingRoom :: Line -> Sp
trailingRoom l = case reverse [(it, x) | (it@Box {}, x) <- placeLine l] of
  ((Box w _, x) : _) -> lineTarget l - (x + w)
  _ -> lineTarget l

akiTests :: [TestTree]
akiTests =
  [ testCase "gyomatsu-yakumono-hankaku composes as before (kinsoku strict)" $ do
      let env = akiEnv defaultAkiSet
      [t | t <- akiTexts, compose env t /= referenceNormalize env (compose env t)] @?= [],
    testCase "with kinsoku loose only Japanese before small kana and the long vowel mark differ" $ do
      let env = (akiEnv defaultAkiSet) {ceKinsokuStrict = False}
          differ = [t | t <- akiTexts, compose env t /= referenceNormalize env (compose env t)]
          ja = filter (`notElem` ("「」・。、A" :: String)) akiRepresentatives
      differ @?= [T.pack [a, b] | a <- ja, b <- "ーぁ"] `orderedAs` akiTexts
      let stretch = Glue 0 (fs `div` 10) 0
          asBreak it = if it == stretch then Penalty 0 0 NoHyphen else it
      [t | t <- differ, compose env t /= map asBreak (referenceNormalize env (compose env t))] @?= [],
    testCase "a set with (四分, 三分, 二分) between Japanese and Latin" $ do
      let s = withAkiRule (akiPositions "western") (akiPositions "japanese") (Aki.Aki (1 / 4) (1 / 3) (1 / 2)) (akiWith ["japanese"] ["western"] (Aki.Aki (1 / 4) (1 / 3) (1 / 2)))
          third = round (toRational fs / 3)
          half = fs `div` 2
          quarter = fs `div` 4
      [g | g@Glue {} <- compose (akiEnv s) "漢A", itemStretch g < filStretch] @?= [Glue third (half - third) (third - quarter)]
      [g | g@Glue {} <- compose (akiEnv s) "A漢", itemStretch g < filStretch] @?= [Glue third (half - third) (third - quarter)],
    testCase "gyomatsu-yakumono-zenkaku keeps a half em after a closing bracket at the line end" $ do
      let txt = "あいう」えおかき"
          firstLine s w = case brLines (breakParagraph defaultParams (const w) (compose (akiEnv s) txt)) of
            (l : _) -> l
            [] -> error "no line"
      zenkaku <- maybe (assertFailure "no zenkaku" >> error "unreachable") pure (Map.lookup "gyomatsu-yakumono-zenkaku" builtinAkiSets)
      let lz = firstLine zenkaku (4 * fs)
          lh = firstLine defaultAkiSet (7 * fs `div` 2)
      [bcText c | Box _ c <- take 1 (reverse (lineItems lz))] @?= ["」"]
      [bcText c | Box _ c <- take 1 (reverse (lineItems lh))] @?= ["」"]
      trailingRoom lz @?= fs `div` 2
      trailingRoom lh @?= 0,
    testCase "a set without the space before an opening bracket at the paragraph start" $ do
      let s = akiWith ["paragraph-start"] ["opening"] (Aki.Aki 0 0 0)
      take 1 [() | Box {} <- take 1 (compose (akiEnv s) "「あ」")] @?= [()]
      take 1 [() | Glue {} <- take 1 (compose (akiEnv defaultAkiSet) "「あ」")] @?= [()],
    testCase "the space after a larger closing bracket is in the bracket's size" $ do
      let env = (akiEnv defaultAkiSet) {ceRestyle = \lk -> \case CharStyle _ "big" _ -> lk {lkSize = 2 * fs}; _ -> lk}
          items = fst (composeInlines env [CharStyle sp "big" [sp0 "」"], sp0 "漢"])
      [g | g@Glue {} <- items, itemStretch g < filStretch] @?= [Glue fs 0 fs],
    testCase "[aki] is an empty box of its width, with no break and no aki of the set (golem-layout ADR 0012)" $ do
      let items = fst (composeInlines (akiEnv defaultAkiSet) [sp0 "漢", Aki sp (AkiZw (1 / 5)), sp0 "A"])
          shapeOf = \case
            Box w c -> Left (bcText c, boxKind c, w)
            it -> Right it
      map shapeOf (takeWhile (not . isLineEnd) items)
        @?= [Left ("漢", KindText, fs), Left ("", KindAki, fs `div` 5), Left ("A", KindText, fs `div` 2)]
      length items @?= 6
      let absolute = fst (composeInlines (akiEnv defaultAkiSet) [sp0 "3", Aki sp (AkiAbs 65536), sp0 "kg"])
      [(w, boxKind c) | Box w c <- absolute, boxKind c == KindAki] @?= [(65536, KindAki)]
      [g | g@Glue {} <- absolute, itemStretch g < filStretch] @?= [],
    testCase "a space of no advance is not taken for an [aki] (golem-layout ADR 0012)" $ do
      let zeroSpace env = env {ceAdvance = \lk c -> if c == ' ' then 0 else ceAdvance env lk c}
          base = akiEnv defaultAkiSet
          glueless = map (\case Glue {} -> Glue 0 0 0; it -> it)
      [g | g@Glue {} <- compose (zeroSpace base) "A 漢", itemStretch g < filStretch] @?= [Glue 0 0 0]
      glueless (compose (zeroSpace base) "A 漢") @?= glueless (compose base "A 漢")
      glueless (compose (zeroSpace base) "A 「漢") @?= glueless (compose base "A 「漢"),
    testCase "the first character after an [aki] at the paragraph start is the paragraph's first (golem-layout ADR 0012)" $ do
      let items = fst (composeInlines (akiEnv defaultAkiSet) [Aki sp (AkiZw 1), sp0 "「あ」"])
      case items of
        Box w a : Box _ c : _ -> do
          (w, boxKind a, bcEdgeStart a, bcEdgeEnd a) @?= (fs, KindAki, 0, 0)
          (bcText c, bcEdgeStart c) @?= ("「", 0)
        _ -> assertFailure (show items),
    testCase "an [aki] at the paragraph end is the last box of the line; the bracket gets no line-end space (golem-layout ADR 0012)" $ do
      zenkaku <- maybe (assertFailure "no zenkaku" >> error "unreachable") pure (Map.lookup "gyomatsu-yakumono-zenkaku" builtinAkiSets)
      let items = fst (composeInlines (akiEnv zenkaku) [sp0 "あ」", Aki sp (AkiZw 1)])
      case brLines (breakParagraph defaultParams (const (10 * fs)) items) of
        [l] -> do
          map boxKind (take 1 (reverse [c | Box _ c <- lineItems l])) @?= [KindAki]
          lineEdge l @?= (0, 0)
          -- あ (1 em), 」 (a half em, no space after it) and the [aki] (1 em)
          trailingRoom l @?= 10 * fs - (fs + fs `div` 2 + fs)
        ls -> assertFailure (show ls),
    testCase "an [aki] inside a line breaks as the penalty and the fixed glue did (golem-layout ADR 0012)" $ do
      let asGlue = concatMap $ \case
            Box w c | boxKind c == KindAki -> [Penalty 0 infPenalty NoHyphen, Glue w 0 0]
            it -> [it]
          texts l = T.concat [bcText c | Box _ c <- lineItems l]
          outcome its w = [(texts l, lineRatio l, lineEdge l) | l <- brLines (breakParagraph defaultParams (const w) its)]
          paras =
            [ [sp0 "第一章", Aki sp (AkiZw 1), sp0 "吾輩は猫である。名前はまだ無い。どこで生れたかとんと見当がつかぬ。"],
              [sp0 "重さは3", Aki sp (AkiZw (1 / 4)), sp0 "kgで、長さは12", Aki sp (AkiAbs 65536), sp0 "mmである。何でも薄暗いじめじめした所で泣いていた事だけは記憶している。"]
            ]
      forM_ paras $ \p -> forM_ [5 * fs, 7 * fs, 9 * fs + fs `div` 3, 12 * fs] $ \w -> do
        let its = fst (composeInlines (akiEnv defaultAkiSet) p)
        assertBool "has an [aki]" (not (null [() | Box _ c <- its, boxKind c == KindAki]))
        outcome its w @?= outcome (asGlue its) w
  ]
  where
    sp = mkSpan (FileId 0) 0 0
    orderedAs xs order = [x | x <- order, x `elem` xs]
    isLineEnd = \case
      Penalty _ p _ -> p >= infPenalty
      _ -> False

-- | Code blocks and the character style code (golem-driver ADR 0017).
codeTests :: [TestTree]
codeTests =
  [ testCase "leading spaces are kept: four spaces put the first glyph at 4s" $
      offsets (rows1 "    x") @?= [[(4 * s, "x")]],
    testCase "spaces in a line are kept as many as written" $
      offsets (rows1 "a   b") @?= [[(0, "a"), (4 * s, "b")]],
    testCase "a tab goes to the next stop, every 2s from the text start" $ do
      offsets (rows1 "\tx") @?= [[(2 * s, "x")]]
      offsets (rows1 "ab\tx") @?= [[(0, "ab"), (4 * s, "x")]]
      offsets (rows1 "abcd\tx") @?= [[(0, "abcd"), (6 * s, "x")]]
      -- a Japanese character is not a multiple of s: 2s + 1 em goes to the next stop
      offsets (rowsWith 1000 (atomsOf "漢\tx")) @?= [[(0, "漢"), (4 * s, "x")]],
    testCase "no justification: words keep the advance of a space between them" $
      offsets (rows1 "ab cd") @?= [[(0, "ab"), (3 * s, "cd")]],
    testCase "no aki between Japanese and Latin: the advances add up" $
      [o | (o, _) <- concat (offsets (rows1 "a漢b"))] @?= [0, s, 4 * s],
    testCase "a long word wraps at a cluster boundary, with no hyphen" $
      offsets (rowsWith (10 * s) (atomsOf "abcdefghijklmn")) @?= [[(0, "abcdefghij")], [(2 * s, "klmn")]],
    testCase "a wrapped line continues 2s after the indent of the line" $
      offsets (rowsWith (20 * s) (atomsOf "  abcdefghijklmnopqrstuvwxyz")) @?= [[(0 + 2 * s, "abcdefghijklmnopqr")], [(4 * s, "stuvwxyz")]],
    testCase "without 8s after the indent, the continuation starts at 2s" $
      offsets (rowsWith (16 * s) (atomsOf "          abcdefghijkl")) @?= [[(10 * s, "abcdef")], [(2 * s, "ghijkl")]],
    testCase "a line that fits is not wrapped" $
      length (rowsWith (20 * s) (atomsOf "abc def")) @?= 1,
    testCase "an empty line is one row" $
      rowsWith (20 * s) (atomsOf "") @?= [CodeRow []],
    testCase "the grid: 13Q body, 22H pitch, 11Q code with 0.5zw padding takes 3 lines for 3 rows" $ do
      let q n = n * 65536 * 72 * 10 `div` (254 * 4) -- approximately; only ratios matter
          g = codeGeometry (q 13) (q 22) (q 11) (q 11 `div` 2)
      codeSpan g 3 @?= 3
      codeSpan g 1 @?= 1,
    testCase "the rows are centred in the lines they take" $ do
      let g = codeGeometry 130 220 110 55
      forM_ [1 .. 6] $ \k -> do
        let top = codeRowsTop g k - cgPadding g
            extent = toInteger (k - 1) * cgPitch g + cgSize g
            bottom = toInteger (codeSpan g k) * cgGridPitch g - codeRowsTop g k - extent - cgPadding g
        assertBool (show (k, top, bottom)) (abs (top - bottom) <= 1),
    testCase "a code block breaks between rows; each part takes its own lines" $ do
      let g = CodeGeometry 10 10 10 10 0
          ps = paginate 1 5 [FParagraph (ids 0 3), FCode g (ids 10 5)]
      map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SCode 10 2 2)], [(0, SCode 12 3 3)]],
    testCase "a block whose first row and padding do not fit starts on the next page" $ do
      let g = CodeGeometry 10 10 10 10 3
          ps = paginate 1 5 [FParagraph (ids 0 4), FCode g (ids 10 2)]
      codeSpan g 1 @?= 2
      map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 3)], [(0, SCode 10 2 3)]],
    testCase "the columns of a page break a code block as pages do" $ do
      let g = CodeGeometry 10 10 10 10 0
          ps = paginate 2 3 [FParagraph (ids 0 2), FCode g (ids 10 3)]
      [(poNumber p, poColumn p, poSlots p) | p <- ps] @?= [(1, 0, [(0, SLine 0), (1, SLine 1), (2, SCode 10 1 1)]), (1, 1, [(0, SCode 11 2 2)])],
    testCase "code: breaks only at spaces and after a slash, with no hyphen" $ do
      let env = (defaultComposeEnv fs) {ceLook = look0 {lkCode = True}, cePatterns = Just englishUS}
          its = compose env "modules/golem-driver/Pdf.hs"
      [h | Penalty _ p h <- its, abs p < infPenalty] @?= [NoHyphen, NoHyphen]
      [t | Box _ c <- its, let { t = bcText c }] @?= ["modules/", "golem-driver/", "Pdf.hs"]
      [h | Penalty _ p h <- compose env "manifest.toml", abs p < infPenalty, h /= NoHyphen] @?= [],
    testCase "code: no aki inside, the advances as they are" $ do
      let env = (defaultComposeEnv fs) {ceLook = look0 {lkCode = True}}
          its = compose env "a漢b"
      [w | Glue w _ _ <- takeWhile (not . isFinalPenalty) its] @?= []
      sum [w | Box w _ <- its] @?= fs `div` 2 + fs + fs `div` 2
  ]
  where
    s = 100
    -- every character s wide but Japanese ones, which are 3s
    shapeOf _ t = [(T.singleton c, if c < '\x2000' then s else 3 * s) | c <- T.unpack t]
    atomsOf = codeAtoms shapeOf
    rowsWith = layoutCodeLine s
    rows1 = rowsWith 1000 . atomsOf
    offsets rs = [[(cpOffset p, cpText p) | p <- crPieces r] | r <- rs]
    ids from n = [LineBox i [] [] [] | i <- [from .. from + n - 1]]
    isFinalPenalty = \case
      Penalty _ p _ -> p >= infPenalty
      _ -> False
