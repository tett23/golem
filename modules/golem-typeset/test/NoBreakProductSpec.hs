{- | S1 of the ranges that do not break (root ADR 0305) checked in the
composition environment of the product (root ADR 0436): the environment of
'composeEnv' from a style.toml, its page geometry, the fonts loaded by the
font provider and the look of the paragraph style body, for four
properties of fonts: the pair kerning of Source Sans Pro, the ligatures of
Source Serif Variable, and the proportional advances of Noto Serif JP set
horizontally (palt) and vertically (vpal).

The predicate of S1 is that of the tests of golem-layout (root ADR 0314),
copied: the items of a run with its ranges off, the soft hyphens touching
a range taken out and the boxes around them joined, are those of the run
with its ranges on.
-}
module NoBreakProductSpec (noBreakProductTests) where

import Control.Applicative ((<|>))
import Data.ByteString qualified as BS
import Data.List (mapAccumL, nub, zip4)
import Data.Ratio ((%))
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR qualified as IR
import Golem.Font (Direction (..), Font, ShapeRequest (..), fontUnitsPerEm, loadFont, shapeRequest, shapeUnits)
import Golem.Layout.Japanese (ComposeEnv (..), composeInlines)
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project.Files (Files (..))
import Golem.Project.Style (parseStyle)
import Golem.Syntax (FileId (..), mkSpan, spanStart)
import Golem.TestSupport.Enum (Violation (..))
import Golem.Typeset (FontProvider (..), LoadedFonts (..), Shaping (..), normalTexts, shapingForFonts)
import Golem.Typeset.FontProvider (golemFontProvider)
import Golem.Typeset.Internal (composeEnv, emptyAssumed, paraLook)
import Test.Tasty
import Test.Tasty.HUnit

-- * The environments

-- | The fonts of the tests, read at their places in the repository.
sourceSans, sourceSerif, notoSerif :: FilePath
sourceSans = "../golem-font/test/fonts/SourceSansPro-Regular.otf"
sourceSerif = "../golem-font/test/fonts/SourceSerifVariable-Roman.ttf"
notoSerif = "../golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"

-- | The files of the disk at the paths as written, from the directory of the package.
relativeFiles :: Files
relativeFiles =
  Files
    { filesResolve = pure . Right,
      filesRead = BS.readFile,
      filesSize = fmap (toInteger . BS.length) . BS.readFile
    }

-- | A page, horizontal or vertical.
pageOf :: Bool -> Text
pageOf vertical =
  T.concat
    [ "[page]\nsize = \"A5\"\n",
      if vertical then "binding = \"right\"\nwriting-mode = \"vertical\"\n" else "binding = \"left\"\nwriting-mode = \"horizontal\"\n",
      "\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 20\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"20mm\" }\n"
    ]

-- | The body role in one font for both scripts, with more keys.
roleOf :: FilePath -> Text -> Text
roleOf path more = "\n[fonts.body]\nja = \"" <> T.pack path <> "\"\nlatin = \"" <> T.pack path <> "\"\n" <> more

-- | The keys of the paragraph style body.
bodyOf :: Text -> Text
bodyOf keys = "\n[paragraph-styles.body]\n" <> keys

-- | The role and the paragraph style body that turn palt (vpal) on, punctuation too (root ADR 0378).
proportional :: Text
proportional = "punctuation-proportional = true\n" <> bodyOf "proportional-metrics = true\n"

-- | An environment of the product and what it was made of.
data Setup = Setup
  { suEnv :: ComposeEnv,
    suFonts :: LoadedFonts,
    suFont :: Font,
    suVertical :: Bool
  }

{- | The environment of a style.toml of a page and the body role in a font
with more keys after those of the role: 'composeEnv' of the style,
the page geometry of it, the fonts the provider loads, no assumed page
numbers and the look of the paragraph style body. Each character is at
the start of the span of its text and its place in it, as the product
places it in its source, so that the 'bcAt' of a box names the part of
its first character.
-}
setupOf :: Bool -> FilePath -> Text -> IO Setup
setupOf vertical path keys = do
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) (pageOf vertical <> roleOf path keys))
  geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False style)
  fonts <- loadFonts golemFontProvider relativeFiles (FileId 0) style [] >>= either (assertFailure . show) pure
  font <- BS.readFile path >>= loadFont >>= either (assertFailure . show) pure
  let look = fst (paraLook style geom Nothing)
      env = (composeEnv "ja" style geom fonts emptyAssumed look) {ceSourceAt = \s _ k -> spanStart s + k}
  pure (Setup env fonts font vertical)

{- | A property of the fonts: its name, its setup, the setup of a role
without it, the input of the table of root ADR 0436 that shows it, and
whether it shows in the advances of the words of a setup, against those of
the setup without it.
-}
data Property = Property
  { prName :: String,
    prSetup :: IO Setup,
    prWithout :: IO Setup,
    prInput :: Input,
    prShows :: Setup -> Setup -> Bool
  }

-- | The advance of a word in the look of the paragraph, in em.
wordOf :: Setup -> Text -> Rational
wordOf su = ceWordAdvance (suEnv su) (ceLook (suEnv su))

{- | The four properties of the fonts (root ADR 0436): AV shorter than A
and V, fi other than f and i, and 「あ narrower than in the role without
palt (vpal). Without the ligatures, the kerning is off too: f and i kern
in Source Serif Variable as well.
-}
properties :: [Property]
properties =
  [ Property "the pair kerning of Source Sans Pro" (setupOf False sourceSans "") (setupOf False sourceSans (bodyOf "kerning = \"none\"\n")) (inRange ["A", "V"]) $ \su _ ->
      wordOf su "AV" < wordOf su "A" + wordOf su "V",
    Property "the ligatures of Source Serif Variable" (setupOf False sourceSerif "") (setupOf False sourceSerif ("features = [\"-liga\"]\n" <> bodyOf "kerning = \"none\"\n")) (inRange ["f", "i"]) $ \su _ ->
      wordOf su "fi" /= wordOf su "f" + wordOf su "i",
    Property "the proportional advances of Noto Serif JP set horizontally (palt)" (setupOf False notoSerif proportional) (setupOf False notoSerif "") (inRange ["「", "あ", "」"]) narrower,
    Property "the proportional advances of Noto Serif JP set vertically (vpal)" (setupOf True notoSerif proportional) (setupOf True notoSerif "") (inRange ["「", "あ", "」"]) narrower
  ]
  where
    inRange ts = Input [(PText t, True) | t <- ts]
    narrower su plain = wordOf su "「あ" < wordOf plain "「あ"

-- * The runs of the check

-- | A part of a run: text, a mono ruby of two bases, code, or a forced break.
data Part = PText !Text | PRuby2 | PCode2 | PBreak
  deriving stock (Eq, Show)

-- | The 13 parts of root ADR 0314.
nbParts :: [Part]
nbParts = map PText ["漢", "あ", "。", "「", "a", "table", "hyphenation", "lime-tree", " ", "\xAD"] <> [PRuby2, PCode2, PBreak]

-- | A run: the parts with whether each is in a range.
newtype Input = Input [(Part, Bool)]
  deriving stock (Eq, Show)

runOf :: Input -> [(Part, Bool)]
runOf (Input r) = r

{- | The 1814 inputs of root ADR 0314: the runs of 0 to 2 of the 13 parts
(703) and of 0 to 3 of A, V, f, i and a soft hyphen (1111), each part in a
range or not.
-}
probeInputs :: [Input]
probeInputs =
  let atoms = [(PText t, b) | t <- ["A", "V", "f", "i", "\xAD"], b <- [False, True]]
      original = [(p, b) | p <- nbParts, b <- [False, True]]
      originalRuns = [] : [[a] | a <- original] ++ [[a, b] | a <- original, b <- original]
      latinRuns = [] : [[a] | a <- atoms] ++ [[a, b] | a <- atoms, b <- atoms] ++ [[a, b, c] | a <- atoms, b <- atoms, c <- atoms]
   in map Input (originalRuns ++ latinRuns)

-- | The characters of the inputs, the bases of the ruby but not its readings.
probeChars :: [Char]
probeChars = nub (concatMap chars nbParts <> "AVfi")
  where
    chars = \case
      PText t -> T.unpack t
      PRuby2 -> "漢字"
      PCode2 -> "a/b"
      PBreak -> ""

-- | The characters of a part: a ruby of two bases has two, code three.
partLength :: Part -> Int
partLength = \case
  PText t -> T.length t
  PRuby2 -> 2
  PCode2 -> 3
  PBreak -> 1

-- | Where each part of an input starts, and where the last one ends.
partStarts :: Input -> [Int]
partStarts i = scanl (+) 0 (map (partLength . fst) (runOf i))

{- | The inlines of an input: each run of parts all in a range or all out
of one in the style given for a range and as they are for the rest,
consecutive text parts one text, each text at the place of its first
character.
-}
inlinesWith :: Text -> Input -> [IR.Inline]
inlinesWith style i = concatMap group (runs (zip (partStarts i) (runOf i)))
  where
    at o n = mkSpan (FileId 0) o (o + n)
    none = mkSpan (FileId 0) 0 0
    runs = \case
      [] -> []
      (o, (p, b)) : rest -> let (same, rest') = span ((== b) . snd . snd) rest in (b, (o, p) : [(o', p') | (o', (p', _)) <- same]) : runs rest'
    group (inRange, ps) = let xs = inlinesOf ps in if inRange then [IR.CharStyle none style xs] else xs
    inlinesOf = \case
      [] -> []
      ps@((o, PText _) : _) ->
        let (ts, rest) = span (isText . snd) ps
            t = T.concat [x | (_, PText x) <- ts]
         in IR.Text (at o (T.length t)) t : inlinesOf rest
      (o, PRuby2) : rest -> IR.Ruby (at o 2) () [IR.RubySegment [IR.Text (at o 1) "漢"] (Just "かん"), IR.RubySegment [IR.Text (at (o + 1) 1) "字"] (Just "じ")] : inlinesOf rest
      (o, PCode2) : rest -> IR.CharStyle (at o 3) "code" [IR.Text (at o 3) "a/b"] : inlinesOf rest
      (o, PBreak) : rest -> IR.LineBreak (at o 1) : inlinesOf rest
    isText = \case
      PText _ -> True
      _ -> False

-- * The predicate of S1, of the tests of golem-layout (root ADR 0314)

{- | The characters of an input, by their number ('partStarts'): whether
each is of a range, whether it is a soft hyphen, and the text inline it is
in.
-}
data Chars = Chars
  { chInRange :: Int -> Bool,
    chShy :: Int -> Bool,
    chText :: Int -> Int
  }

charsOf :: Input -> Chars
charsOf i =
  Chars
    { chInRange = maybe False (snd . snd) . partAt,
      chShy = maybe False ((== PText "\xAD") . fst . snd) . partAt,
      chText = \o -> maybe (if o < 0 then -1 else -2) fst (partAt o)
    }
  where
    starts = partStarts i
    parts = zip (texts (runOf i)) (runOf i)
    texts = snd . mapAccumL (\(prev, n) (p, b) -> let n' = if isText p && prev == Just b then n else n + 1 in ((if isText p then Just b else Nothing, n'), n')) (Nothing, 0 :: Int)
    isText = \case
      PText _ -> True
      _ -> False
    partAt o = case [x | (x, s, e) <- zip3 parts starts (drop 1 starts), s <= o, o < e] of
      x : _ -> Just x
      [] -> Nothing

-- | The soft hyphens right before the character numbered o, nearest first, and the character before them.
shysBefore :: Chars -> Int -> Maybe ([Int], Int)
shysBefore ch o = case takeWhile (\k -> k >= 0 && chShy ch k) [o - 1, o - 2 ..] of
  [] -> Nothing
  ss -> Just (ss, minimum ss - 1)

-- | Whether soft hyphens touch a range (root ADR 0305).
touchesRange :: Chars -> ([Int], Int) -> Int -> Bool
touchesRange ch (ss, before) o = any (chInRange ch) ss || (before >= 0 && chInRange ch before) || chInRange ch o

nextBoxAt :: [Item] -> Maybe Int
nextBoxAt = \case
  Box _ c : _ -> Just (bcAt c)
  _ : rest -> nextBoxAt rest
  [] -> Nothing

isShyPenalty :: Item -> Bool
isShyPenalty = \case
  Penalty _ _ (SoftHyphen _) -> True
  _ -> False

shysOf :: Chars -> [Item] -> Either String (([Int], Int), Int)
shysOf ch rest = case nextBoxAt rest of
  Nothing -> Left "a soft hyphen penalty has no box after it"
  Just o -> maybe (Left ("a soft hyphen penalty is not after a soft hyphen: the box after it starts at character " <> show o)) (\s -> Right (s, o)) (shysBefore ch o)

-- | An amount in zw at a size of type, in sp, rounded once, half to even (as golem-length).
zwToSp :: Sp -> Rational -> Sp
zwToSp (Sp size) r = Sp (round (r * fromInteger size))

{- | The first step of S1: the penalty of each soft hyphen touching a range
taken out, and where the soft hyphen and the characters around it are of
one text, the boxes around it one box, as wide as both and the kerning
between them by the advances of the words.
-}
dropTouching :: ComposeEnv -> Chars -> [Item] -> Either String [Item]
dropTouching measures ch = go []
  where
    go acc = \case
      [] -> Right (reverse acc)
      x : rest
        | isShyPenalty x -> do
            (sh@(ss, before), o) <- shysOf ch rest
            if not (touchesRange ch sh o)
              then go (x : acc) rest
              else
                if all ((== chText ch o) . chText ch) (before : ss)
                  then case (acc, rest) of
                    (Box w1 c1 : acc', Box w2 c2 : rest') -> go (Box (joined w1 w2 c1 c2) c1 {bcText = bcText c1 <> bcText c2} : acc') rest'
                    _ -> Left "the boxes around a soft hyphen of one text are not next to its penalty"
                  else go acc rest
        | otherwise -> go (x : acc) rest
    joined w1 w2 c1 c2 =
      let lk = bcLook c1
          adv t = zwToSp (lkSize lk) (ceWordAdvance measures lk t)
       in w1 + w2 + adv (bcText c1 <> bcText c2) - adv (bcText c1) - adv (bcText c2)

-- | The second step of S1: each break inside a range held by a penalty of 10000.
holdInside :: Chars -> [Item] -> [Item]
holdInside ch xs =
  concat
    [ case x of
        Penalty w p h | p < infPenalty && p > negate infPenalty && inside -> [Penalty w infPenalty h]
        Glue {} | ab && inside -> [Penalty 0 infPenalty NoHyphen, x]
        _ -> [x]
    | (x, b, a, ab) <- zip4 xs befores afters afterBox,
      let inside = b == Just True && a == Just True
    ]
  where
    marks = [case x of Box _ c | not (T.null (bcText c)) -> Just (chInRange ch (bcAt c)); _ -> Nothing | x <- xs]
    befores = scanl (flip (<|>)) Nothing marks
    afters = drop 1 (scanr (<|>) Nothing marks)
    afterBox = False : [case x of Box {} -> True; _ -> False | x <- xs]

-- | S1 (root ADR 0305): the items of an input are those of it with its ranges off, 'dropTouching' and then 'holdInside'.
s1With :: ComposeEnv -> Input -> [Item] -> [Item] -> [Violation]
s1With measures i its off = case dropTouching measures ch off of
  Left e -> [Violation "S1" ("the predicate cannot read the items: " <> e)]
  Right off' ->
    let want = holdInside ch off'
     in [Violation "S1" ("the items are " <> show (map itemKey its) <> ", not " <> show (map itemKey want)) | map itemKey its /= map itemKey want]
  where
    ch = charsOf i

-- | The values of an item that the predicate compares.
itemKey :: Item -> (Int, Sp, Sp, Sp, Text, Int, Int)
itemKey = \case
  Box w c -> (0, w, 0, 0, bcText c, 0, 0)
  Glue w y z _ _ -> (1, w, y, z, "", 0, 0)
  Penalty w p h -> (2, w, 0, 0, "", p, hyphenKind h)
  where
    hyphenKind = \case
      NoHyphen -> 0
      PatternHyphen _ -> 1
      ExplicitHyphen -> 2
      WrapMark _ -> 3
      SoftHyphen _ -> 4

-- | The violations of S1 of an input in an environment.
s1Of :: ComposeEnv -> Input -> [Violation]
s1Of env i =
  let compose s = fst (composeInlines env (inlinesWith s i))
   in s1With env i (compose "no-break") (compose "nb-off")

-- | The inputs that break S1, with their violations.
s1Failures :: ComposeEnv -> [String]
s1Failures env = [show i <> ": " <> show (map violationDetail vs) | i <- probeInputs, let vs = s1Of env i, not (null vs)]

-- * The advances of the characters

{- | The looks the characters of the inputs are set in: that of the
paragraph, in a range, in code, and in code in a range.
-}
looksOf :: ComposeEnv -> [Look]
looksOf env =
  let lk = ceLook env
      styled n l = ceRestyle env l (IR.CharStyle (mkSpan (FileId 0) 0 0) n [])
   in [lk, styled "no-break" lk, styled "code" lk, styled "code" (styled "no-break" lk)]

{- | The advance of a character by golem-font's 'shapeUnits' alone, in em:
the character shaped with the features of its role and then those the
shaping of the look adds, in the direction of the shaping.
-}
unitsAdvance :: Setup -> Look -> Char -> Rational
unitsAdvance su lk c =
  let s = shapingForFonts (suFonts su) (suVertical su) lk c
      features = normalTexts (lfRoleFeatures (suFonts su) (shRole s) <> shExtra s)
      dir = if shVertical s then Vertical else Horizontal
      request = (shapeRequest (T.singleton c)) {srDirection = dir, srFeatures = features}
      units = sum [if dir == Vertical then negate ya else xa | (_, _, (xa, ya, _, _)) <- shapeUnits (suFont su) request]
   in toInteger units % toInteger (fontUnitsPerEm (suFont su))

-- | The characters whose 'ceAdvance' is not that of 'shapeUnits'.
advanceFailures :: Setup -> [String]
advanceFailures su =
  [ show c <> " in " <> show (lkFace lk) <> ": " <> show a <> ", not " <> show b
  | lk <- looksOf (suEnv su),
    c <- probeChars,
    let a = ceAdvance (suEnv su) lk c
        b = unitsAdvance su lk c,
    a /= b
  ]

-- * The tests

noBreakProductTests :: TestTree
noBreakProductTests =
  testGroup
    "S1 of the ranges that do not break in the composition environment of the product (root ADR 0436)"
    [ testGroup "root ADR 0436 I1" ([i1 p | p <- properties] <> i1Edges),
      testGroup "root ADR 0436 I2" (concat [i2 p | p <- properties]),
      testGroup "root ADR 0436 I3" ([i3 p | p <- properties] <> [i3Palt False "palt", i3Palt True "vpal"])
    ]
  where
    i1 p = testCase ("root ADR 0436 I1: S1 holds for the 1814 inputs of root ADR 0314 in " <> prName p) $ do
      su <- prSetup p
      length probeInputs @?= 1814
      take 1 (s1Failures (suEnv su)) @?= []
    i1Edges =
      [ testCase ("root ADR 0436 I1: S1 holds for the empty run and a soft hyphen right outside a range in " <> prName p) $ do
          su <- prSetup p
          s1Of (suEnv su) (Input []) @?= []
          s1Of (suEnv su) (Input [(PText "a", False), (PText "\xAD", False), (PText "a", True)]) @?= []
          s1Of (suEnv su) (Input [(PText "a", True), (PText "\xAD", False), (PText "a", False)]) @?= []
      | p <- properties
      ]
    i2 p =
      [ testCase ("root ADR 0436 I1, I2: " <> prName p <> " shows in the advance of the word, and S1 holds for it") $ do
          su <- prSetup p
          without <- prWithout p
          assertBool (prName p <> " does not show in the advance of the word") (prShows p su without)
          s1Of (suEnv su) (prInput p) @?= [],
        testCase ("root ADR 0436 I2: a predicate test, the role without " <> prName p <> " does not show it") $ do
          without <- prWithout p
          assertBool (prName p <> " shows without it") (not (prShows p without without))
      ]
    i3 p = testCase ("root ADR 0436 I3: the advance of each character is that of shapeUnits with the same features, in " <> prName p) $ do
      su <- prSetup p
      take 1 (advanceFailures su) @?= []
    -- 「 alone in the role of palt (vpal): shaped with it, as shapeUnits with it
    i3Palt vertical tag = testCase ("root ADR 0436 I3: 「 alone in the role of " <> T.unpack tag <> " has the advance of shapeUnits with " <> T.unpack tag) $ do
      su <- setupOf vertical notoSerif proportional
      let lk = ceLook (suEnv su)
          s = shapingForFonts (suFonts su) vertical lk '「'
      assertBool (T.unpack tag <> " is not among the features of 「: " <> show (shExtra s)) (tag `elem` shExtra s)
      ceAdvance (suEnv su) lk '「' @?= unitsAdvance su lk '「'
