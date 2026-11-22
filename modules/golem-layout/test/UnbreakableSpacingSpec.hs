{- | The spacing that the adjustment of a line does not widen (root ADR
0362): between two inseparable characters, two Arabic digits in
horizontal writing, a prefixed abbreviation and a numeral, and a numeral
and a postfixed abbreviation, the glue keeps its width and its shrink
and has no stretch, in every aki set, built in or not.

The boundaries are found apart from the implementation: every input is
a run of characters each set in a box of its own, so that the k-th
boundary is the glue between the k-th box and the next, and whether it
is protected is decided by 'charClass' and the reference lists of
"LineBreakInvariants".
-}
module UnbreakableSpacingSpec
  ( unbreakableSpacingTests,
  )
where

import Control.Monad (replicateM)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Aki qualified as A
import Golem.Layout.CharClass
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Length qualified as L
import LineBreakEnum (Setting (..), composeEnv)
import LineBreakInvariants (refArabicDigit, refNumeral, refPostfixed, refPrefixed)
import Test.Tasty
import Test.Tasty.HUnit

unbreakableSpacingTests :: TestTree
unbreakableSpacingTests =
  testGroup
    "spacing the adjustment of a line does not widen (root ADR 0362)"
    [ testCase "ADR 0362 I1: inv1_unbreakable_spacing_case_1: the two boundaries inside １２３ do not stretch" $ do
        mapM_
          ( \(name, set) -> do
              let r = run False set "１２３"
              assertEqual name [True, True] (map fst (bounds r))
              mapM_ (assertEqual name [0, 0] . protectedAmounts r) (lines' r)
              assertEqual name [0, 0] [unSp (itemStretch g) | (True, gs) <- bounds r, g <- gs]
          )
          sets,
      testCase "ADR 0362 I1: inv1_unbreakable_spacing_case_2: a single digit has no protected boundary" $
        mapM_
          (\(name, set) -> assertEqual name [] [b | b@(True, _) <- bounds (run False set "１")])
          sets,
      testCase "ADR 0362 I1: inv1_unbreakable_spacing_property: the protected boundaries of every input stretch by 0 in total, whatever the space to spread" $ do
        let runs = [run v set t | v <- [False, True], (_, set) <- sets, t <- inputs]
            checked = [r | r <- runs, separate r]
            protected = [r | r <- checked, any fst (bounds r)]
        -- the inputs are not vacuous: most are set a character in a box, many have a protected boundary
        assertBool "most inputs are set one character in a box" (length checked * 2 > length runs)
        assertBool "some inputs have a protected boundary" (length protected > 100)
        mapM_
          ( \r ->
              mapM_
                ( \l ->
                    assertEqual
                      (show (rText r, rVertical r, lineTarget l, lineAdjustOrder l))
                      0
                      (sum (protectedAmounts r l))
                )
                (lines' r)
          )
          checked
        -- the glue of a protected boundary keeps the width and the shrink of the set, in a set of its own too
        assertEqual
          "the glue of the protected boundaries in the custom set"
          [(unSp fs `div` 4, 0, unSp fs `div` 4)]
          ( unique
              [ (unSp (itemWidth g), unSp (itemStretch g), unSp (itemShrink g))
              | r <- checked,
                rSet r == custom,
                (True, gs) <- bounds r,
                g <- gs
              ]
          )
        -- the other glue still stretches: the adjustment has somewhere to go
        assertBool
          "the unprotected boundaries of the custom set stretch"
          (and [itemStretch g > 0 | r <- checked, rSet r == custom, (False, gs) <- bounds r, g <- gs]),
      testCase "ADR 0362: outside a run of digits the set applies" $ do
        let stretches v t = [unSp (itemStretch g) | (_, gs) <- bounds (run v custom t), g <- gs]
        stretches False "１漢" @?= [unSp fs `div` 2],
      -- two full-width digits in vertical writing are no pair of B2, so the
      -- glue between them stretches as the set says (root ADR 0396)
      testCase "root ADR 0396 I2: two full-width digits in vertical writing stretch as the set says" $ do
        let stretches t = [unSp (itemStretch g) | (_, gs) <- bounds (run True custom t), g <- gs]
        stretches "１２" @?= [unSp fs `div` 2]
        mapM_
          ( \(name, set) -> do
              let (w, y, z) = digitsAki set
              assertBool (name <> ": the set stretches between two digits") (y > 0)
              assertEqual name [(False, [(w, y, z)])] [(b, map glueOf gs) | (b, gs) <- bounds (run True set "１１")]
          )
          sets,
      testCase "root ADR 0396 I3: two full-width digits in horizontal writing do not stretch, and keep the width and the shrink of the set" $
        mapM_
          ( \(name, set) -> do
              let (w, _, z) = digitsAki set
              assertEqual name [(True, [(w, 0, z)])] [(b, map glueOf gs) | (b, gs) <- bounds (run False set "１１")]
          )
          sets
    ]
  where
    glueOf g = (unSp (itemWidth g), unSp (itemStretch g), unSp (itemShrink g))
    -- the width, the stretch and the shrink the set gives between two full-width digits
    digitsAki set =
      let A.Aki n o m = A.akiBetween set (A.AkiChar (charClass '１')) (A.AkiChar (charClass '１'))
          size = L.zwToSp fs
       in (unSp (size o), unSp (size m - size o), unSp (size o - size n))

-- * the inputs

-- | Characters of every kind of the protected boundaries, and some of none.
alphabet :: [Char]
alphabet = "１２〇三￥％℃€№′…‥あ漢、（5A"

-- | Every run of one to three characters of 'alphabet'.
inputs :: [Text]
inputs = [T.pack s | n <- [1 .. 3], s <- replicateM n alphabet]

{- | The aki sets: the built-in ones, and one of its own where every pair
of positions has an optimum of a quarter em, a minimum of 0 and a maximum
of three quarters.
-}
sets :: [(String, A.AkiSet)]
sets = [(T.unpack n, s) | (n, s) <- Map.toList A.builtinAkiSets] <> [("custom", custom)]

custom :: A.AkiSet
custom = A.withAkiRule positions positions (A.Aki 0 (1 / 4) (3 / 4)) A.defaultAkiSet
  where
    positions = map A.AkiChar [minBound .. maxBound]

-- * the runs

data Run = Run
  { rText :: Text,
    rVertical :: Bool,
    rSet :: A.AkiSet,
    -- | the items up to the last box: no glue to fill the line
    rItems :: [Item]
  }

run :: Bool -> A.AkiSet -> Text -> Run
run vertical set t =
  let env = (composeEnv vertical (Setting True False False Nothing)) {ceAkiSet = set}
      its = fst (composeInlines env [IR.Text sp t])
      lastBox = last (0 : [i | (i, Box {}) <- zip [0 :: Int ..] its])
   in Run t vertical set (take (lastBox + 1) its)

-- | Whether each character of the run is set in a box of its own.
separate :: Run -> Bool
separate r = [bcText c | Box _ c <- rItems r] == map T.singleton (T.unpack (rText r))

{- | Each boundary between two boxes: whether it is protected, by the
reference, and the glue between the two boxes.
-}
bounds :: Run -> [(Bool, [Item])]
bounds r =
  [ (protects (rVertical r) a b, gap k)
  | separate r,
    (k, (a, b)) <- zip [0 ..] (zip cs (drop 1 cs))
  ]
  where
    cs = T.unpack (rText r)
    boxes = [i | (i, Box {}) <- zip [0 :: Int ..] (rItems r)]
    gap k = [g | g@Glue {} <- take (boxes !! (k + 1) - boxes !! k - 1) (drop (boxes !! k + 1) (rItems r))]

-- | The boundaries of root ADR 0362, by 'charClass' and the reference lists.
protects :: Bool -> Char -> Char -> Bool
protects vertical a b =
  (charClass a == Inseparable && charClass b == Inseparable)
    || (not vertical && refArabicDigit a && refArabicDigit b)
    || (refPrefixed a && refNumeral b)
    || (refNumeral a && refPostfixed b)

{- | The run set as one line, from its natural width to 8 em wider, in
half ems, its glue adjusted uniformly and in stages, with no stretch
limit.
-}
lines' :: Run -> [Line]
lines' r =
  [ Line (rItems r) 0 (natural + fromIntegral (unSp fs * j `div` 2)) 0 (0, 0) 0 (0, 0) Nothing order
  | j <- [0 .. 16],
    order <- orders
  ]
  where
    natural = sum (map itemWidth (rItems r))
    orders =
      [ AdjustUniform,
        AdjustStaged [] [],
        AdjustStaged [] [[BetweenCharactersGlue], [JapaneseWesternGlue]],
        AdjustStaged [] [[JapaneseWesternGlue, BetweenCharactersGlue, BracketsGlue, CommaGlue, FullStopGlue, MiddleDotGlue]]
      ]

-- | What the adjustment adds to the glue of each protected boundary of a line.
protectedAmounts :: Run -> Line -> [Rational]
protectedAmounts r l =
  let amounts = glueAmounts l
      -- the index of each glue among the glue of the line, by boundary
      glueIx = scanl (+) 0 (map (length . snd) (bounds r))
      lead = length [() | Glue {} <- takeWhile (not . isBox) (rItems r)]
   in [ sum (take (length gs) (drop (lead + i) amounts))
      | ((True, gs), i) <- zip (bounds r) glueIx
      ]
  where
    isBox = \case
      Box {} -> True
      _ -> False

unique :: (Ord a) => [a] -> [a]
unique = Map.keys . Map.fromList . map (,())
