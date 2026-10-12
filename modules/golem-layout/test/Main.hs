module Main (main) where

import Data.List (subsequences)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.IR
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Paginate
import Golem.Layout.Sidenotes
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
box w = Box w (BoxContent "x" False 0 0 0)

-- | Words of the given widths separated by interword glue.
paragraph :: [Sp] -> [Item]
paragraph ws = concat [box w : [Glue 6 3 2 | i < length ws - 1] | (i, w) <- zip [0 :: Int ..] ws] <> finish

refBox :: Text -> Sp -> Item
refBox t w = Box w (BoxContent t False 0 0 0)

knuthPlassWords, knuthPlassLog :: FilePath
knuthPlassWords = "test/data/knuth-plass/frog-king.words"
knuthPlassLog = "test/data/knuth-plass/frog-king.log"

-- | The \hsize values of frog-king.tex, in points.
referenceHsizes :: [Integer]
referenceHsizes = [160, 200, 240, 300]

{- | A hand-written trace: the first run fails the first pass and takes a
detour (@@2 is not on the chosen path); the second ends in the first pass.
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

-- | Total demerits of a break sequence, computed directly from the rules.
bruteDemerits :: Params -> (Int -> Sp) -> [Item] -> [Int] -> Maybe Integer
bruteDemerits ps lw items brks = go 0 2 False (-1) brks 0
  where
    n = length items
    at = (items !!)
    afterBrk i = let s = dropWhile isDiscard [i + 1 .. n - 1] in case s of (j : _) -> j; [] -> n
    isDiscard j = case at j of
      Box {} -> False
      Penalty _ p _ -> p > negate infPenalty
      Glue {} -> True
    go _ _ _ _ [] acc = Just acc
    go line prevFit prevFlag prev (b : rest) acc =
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
          (pen, flag) = case at b of Penalty _ p f -> (p, f); _ -> (0, False)
          d =
            lineDemerits ps bad pen
              + (if prevFlag && flag then toInteger (pDoubleHyphenDemerits ps) else 0)
              + (if abs (fit - prevFit) > 1 then toInteger (pAdjDemerits ps) else 0)
       in if over || bad > pTolerance ps then Nothing else go (line + 1) fit flag b rest (acc + d)

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

sp0 :: Text -> Inline
sp0 = Text (mkSpan (FileId 0) 0 0)

compose :: ComposeEnv -> Text -> [Item]
compose env t = fst (composeInlines env [sp0 t])

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
    [ testGroup
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
                end = length items - 1
                candidates = [s <> [end] | s <- subsequences (filter (/= end) (legal items))]
                best = minimum' [d | c <- candidates, Just d <- [bruteDemerits noPretol (const target) items c]]
            case best of
              Nothing -> brPass r === 4
              Just d -> do
                brPass r === 2
                brDemerits r === d,
          testCase "every line fits its own target length (L*(i))" $ do
            let items = paragraph (replicate 20 30)
                lw :: Int -> Sp
                lw i = if i < 3 then 100 else 160
                r = breakParagraph defaultParams lw items
            assertBool "not overfull" (not (any lineOverfull (brLines r)))
            mapM_ (\(i, l) -> lineTarget l @?= lw i) (zip [0 ..] (brLines r))
            assertBool "short lines first" (all (\l -> sum [w | Box w _ <- lineItems l] <= 100) (take 3 (brLines r))),
          testCase "equal demerits: the earlier break wins" $ do
            -- A(10) | B(0) | C(10): breaking after A or after B both give two exact lines
            let items = [box 10, Penalty 0 0 False, box 0, Penalty 0 0 False, box 10] <> finish
                r = breakParagraph defaultParams (const 10) items
            brPositions r @?= [1, length items - 1],
          testCase "an unbreakable word reaches the fourth pass and is overfull" $ do
            let items = paragraph [50, 500, 50]
                r = breakParagraph defaultParams {pEmergencyStretch = 20} (const 100) items
            brPass r @?= 4
            assertBool "overfull" (any lineOverfull (brLines r)),
          testCase "a penalty inside a line takes no width; at the line end it does" $ do
            let items = [box 30, Penalty 5 50 True, box 30, Glue 6 3 2, box 30, Penalty 5 50 True, box 30] <> finish
                r = breakParagraph defaultParams (const 1000) items
            case brLines r of
              [l] -> [x | (Box {}, x) <- placeLine l] @?= [0, 30, 66, 96]
              ls -> assertFailure (show (length ls))
            let r2 = breakParagraph noPretol (const 70) ([box 30, Glue 6 3 2, box 30, Penalty 5 50 True, box 30] <> finish)
            case brLines r2 of
              (l : _) -> case reverse (lineItems l) of
                (Penalty 5 _ True : _) -> pure ()
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
                          trBreaks = [TexBreak 1 1 400, TexBreak 3 2 100],
                          trTotalDemerits = 500,
                          trGlueSet = [negate (32768 / 65536), 21845 / 65536]
                        },
                      TexRun
                        { trHsize = 200 * 65536,
                          trPass = 1,
                          trBreaks = [TexBreak 3 2 100],
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
              paragraphItems (Words (6, 3, 2) 20 0 [("a", 10), ("b", 12)])
                @?= [refBox "" 20, refBox "a" 10, Glue 6 3 2, refBox "b" 12] <> finish,
            testCase "the data has every \\hsize of frog-king.tex, from both passes" $ do
              runs <- parseTrace <$> TIO.readFile knuthPlassLog
              map trHsize runs @?= map (* 65536) referenceHsizes
              assertBool "a run that ends in the first pass" (any ((== 1) . trPass) runs)
              assertBool "a run that reaches the second pass" (any ((== 2) . trPass) runs),
            testCase "the words add up to the paragraph TeX set in one box" $ do
              ws <- readWords knuthPlassWords
              let (sp, _, _) = wSpace ws
                  n = toInteger (length (wBoxes ws))
              sum (map snd (wBoxes ws)) + (n - 1) * sp @?= wWhole ws
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
            length [() | Penalty _ 50 True <- compose env "hyphenation"] @?= 2
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
            [bcText c | Box _ c <- compose (defaultComposeEnv fs) "“Mercy on us!”—“We split!”]"] @?= ["“Mercy", "on", "us!”—“We", "split!”]"]
            -- in Japanese text they stay punctuation
            [bcText c | Box _ c <- compose (defaultComposeEnv fs) "彼は“あ”と"] @?= ["彼", "は", "“", "あ", "”", "と"],
          testCase "a quarter em between Japanese and Latin text" $ do
            let items = compose (defaultComposeEnv fs) "日本Golem語"
            [w | Glue w _ _ <- items, w > 0, w < filStretch] @?= [fs `div` 4, fs `div` 4],
          testCase "ruby wider than its base overhangs, then widens the base" $ do
            let seg base r = RubySegment [Text (mkSpan (FileId 0) 0 0) base] (Just r)
                rubyW e segs = [w | Box w c <- fst (composeInlines e [Ruby (mkSpan (FileId 0) 0 0) () segs]), boxKind c == KindRuby]
                env = (defaultComposeEnv fs) {ceRubyOverhang = fs `div` 2}
            rubyW env [seg "字" "じ"] @?= [fs] -- fits
            rubyW env [seg "字" "あいう"] @?= [fs] -- 1.5em reading: overhang absorbs it
            rubyW env [seg "字" "あいうえおか"] @?= [fs * 2] -- 3em: one em overhangs, the base widens
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
            let items = [Box w (BoxContent "w" True 0 0 0) | w <- ws] `interleave` Glue 6 3 2 <> finish
                r = breakParagraph defaultParams {pExpansion = Just (20, 5)} (const 150) items
            mapM_ (\l -> assert (abs (lineExpansion l) <= 20 && lineExpansion l `mod` 5 == 0)) (brLines r),
          testCase "expansion lowers the spread of adjustment ratios" $ do
            let ws = [23, 41, 37, 19, 52, 33, 28, 45, 31, 26, 39, 22, 48, 35, 29, 41]
                items = [Box (w * 100) (BoxContent "w" True 0 0 0) | w <- ws] `interleave` Glue 600 300 200 <> finish
                variance ps =
                  let rs = map glueRatio (init (brLines (breakParagraph ps (const 15000) items)))
                      m = sum rs / fromIntegral (length rs)
                   in sum [(r - m) ^ (2 :: Int) | r <- rs] / fromIntegral (length rs)
            assertBool "smaller" (variance defaultParams {pExpansion = Just (20, 5)} < variance defaultParams)
        ],
      testGroup
        "pagination (ADR 0003)"
        [ testCase "no orphan: a paragraph's first line is not left alone at the page end" $ do
            let ps = paginate 5 [FParagraph (lines' 0 4), FParagraph (lines' 10 3)]
            slots ps @?= [[0, 1, 2, 3], [10, 11, 12]],
          testCase "no widow: the last line is not sent alone to the next page" $ do
            let ps = paginate 5 [FParagraph (lines' 0 6)]
            slots ps @?= [[0, 1, 2, 3], [4, 5]],
          testCase "headings and definition terms stay with what follows" $ do
            let ps = paginate 5 [FParagraph (lines' 0 3), FHeading 2 "節" False (lines' 20 1), FParagraph (lines' 30 3)]
            slots ps @?= [[0, 1, 2], [20, 30, 31, 32]]
            let qs = paginate 5 [FParagraph (lines' 0 4), FDefTerm (lines' 20 1), FParagraph (lines' 30 2)]
            slots qs @?= [[0, 1, 2, 3], [20, 30, 31]],
          testCase "a recto heading starts on an odd page after a blank page" $ do
            let ps = paginate 5 [FParagraph (lines' 0 3), FHeading 1 "章" True (lines' 20 1)]
            map poBlank ps @?= [False, True, False]
            map poNumber ps @?= [1, 2, 3]
            poRunningHead (last ps) @?= Just "章",
          testCase "a figure that does not fit goes to the next page; text moves up" $ do
            let ps = paginate 5 [FParagraph (lines' 0 3), FFigure 99 3 ["fig"], FParagraph (lines' 10 2)]
            map poSlots ps @?= [[(0, SLine 0), (1, SLine 1), (2, SLine 2), (3, SLine 10), (4, SLine 11)], [(0, SFigure 99)]],
          testCase "footnotes sit on the page of their marker and continue when too long" $ do
            let withNote i n = LineBox i [NoteBody (100 + i) n] []
                ps = paginate 6 [FParagraph [LineBox 0 [] [], withNote 1 2, LineBox 2 [] [], withNote 3 1, LineBox 4 [] []]]
            map poFootnotes ps @?= [[(101, 0, 2)], [(103, 0, 1)]]
            let long = paginate 4 [FParagraph [withNote 0 5, LineBox 1 [] []]]
            map poFootnotes long @?= [[(100, 0, 2)], [(100, 2, 2)], [(100, 4, 1)]],
          testCase "page references converge when the page count gains a digit" $ do
            -- the reference sits before the label; at three digits the reference line wraps
            let layout assumed =
                  let refWidthLines = if Map.findWithDefault 1 "end" assumed >= 100 then 2 else 1
                   in paginate 5 (FParagraph (lines' 0 refWidthLines) : [FParagraph (lines' (1000 + i * 10) 2) | i <- [0 .. 196]] <> [FParagraph [LineBox 9999 [] ["end"]]])
            case resolvePageRefs layout of
              Right ps -> Map.lookup "end" (labelPages ps) @?= Just (toInteger (poNumber (last ps)))
              Left ls -> assertFailure (show ls),
          testCase "references that never settle are an error" $ do
            let layout assumed = paginate 5 (replicate (fromInteger (if Map.findWithDefault 1 "x" assumed < 10 then 9 else 1)) (FParagraph (lines' 0 5)) <> [FParagraph [LineBox 1 [] ["x"]]])
            resolvePageRefs layout @?= Left ["x"]
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
          testCase "a wrapped figure that does not fit the page goes to the next page" $ do
            let ps = paginate 5 [FParagraph (lines' 0 3), FWrapped 7 3 [] (lines' 50 3)]
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
          testCase "too many notes, or one taller than the column, are errors" $ do
            placeSidenotes 30 2 [(0, 10), (0, 10), (0, 10)] @?= Left (DoesNotFit 2)
            placeSidenotes 30 2 [(0, 40)] @?= Left (TooTall 0)
        ]
    ]
  where
    minimum' [] = Nothing
    minimum' xs = Just (minimum xs)
    interleave xs g = concat [x : [g | i < length xs - 1] | (i, x) <- zip [0 :: Int ..] xs]
    head' (x : _) = x
    head' [] = ""
    last' xs = if null xs then "" else last xs
    lines' base n = [LineBox (base + i) [] [] | i <- [0 .. n - 1]]
    slots = map (\p -> [i | (_, SLine i) <- poSlots p] <> [i | (_, SFigure i) <- poSlots p])
