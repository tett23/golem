-- | The pure memoisation of golem-driver (docs/adr ADR 0034, docs/adr/0253).
module MemoSpec (memoTests) where

import Control.Exception (evaluate)
import Control.Monad (forM_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Typeset (Shaping (..))
import Golem.Typeset.Memo
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog (testProperty)

-- | A function that counts how often it is evaluated (in the tests only).
counted :: IORef Int -> (Int -> Int) -> Int -> Int
counted ref f n = unsafePerformIO (atomicModifyIORef' ref (\c -> (c + 1, ())) >> pure (f n))
{-# NOINLINE counted #-}

-- | The roles of the fonts, in the order of the provider's table.
roles :: [Text]
roles = ["body", "ruby", "見出し"]

-- the boundaries of docs/adr/0253: the roles, the features, vertical and dual
shapings :: [Shaping]
shapings =
  [ Shaping role vertical extra dual
  | role <- ["body", "見出し", "", "none", T.replicate 40 "x"],
    vertical <- [False, True],
    extra <- [[], ["palt"], ["-liga", "+kern", "vpal"], ["", ""], ["kern=0"], ["パルト"]],
    dual <- [False, True]
  ]

texts :: [Text]
texts = ["", "a", "あ", "ab", "「、", "e\x0301", "葛\xE0100", T.singleton '\x10FFFF', "\x1F600\xFE0F", T.replicate 200 "組版"]

-- | The key of one digit back to the number.
one :: [Int] -> Int
one = \case
  (n : _) -> n
  [] -> 0

inRange :: [Int] -> Bool
inRange = all (\d -> d >= 0 && d < digitLimit)

-- | An OpenType tag of four ASCII characters, alone or after + or -.
genTag :: Gen Text
genTag = do
  tag <- Gen.text (Range.singleton 4) Gen.ascii
  sign <- Gen.element ["", "+", "-"]
  pure (sign <> tag)

genShaping :: Gen Shaping -> Gen (Shaping, Text)
genShaping g = (,) <$> g <*> Gen.text (Range.linear 0 30) Gen.unicode

-- | A shaping in a role of the table, with tags as its features (I3).
genInTable :: Gen Shaping
genInTable = Shaping <$> Gen.element roles <*> Gen.bool <*> Gen.list (Range.linear 0 4) genTag <*> Gen.bool

-- | Any shaping: any role, any features.
genAny :: Gen Shaping
genAny =
  Shaping
    <$> Gen.choice [Gen.element roles, Gen.text (Range.linear 0 8) Gen.unicode]
    <*> Gen.bool
    <*> Gen.list (Range.linear 0 4) (Gen.choice [genTag, Gen.text (Range.linear 0 6) Gen.unicode])
    <*> Gen.bool

memoTests :: TestTree
memoTests =
  testGroup
    "pure memoisation (docs/adr ADR 0034)"
    [ testCase "a memoised function gives the values of the function" $ do
        let f n = n * n - 7 * n + 3
            g = memoWith (: []) one f
        forM_ ([0 .. 5000] <> [digitLimit - 1, digitLimit - 4096]) $ \n -> g n @?= f n,
      testCase "a key outside the digits is computed, not remembered" $ do
        let f n = n + 1
            g = memoWith (: []) one f
        mapM_ (\n -> g n @?= f n) [-1, digitLimit, maxBound],
      testCase "the second look-up of a key does not evaluate the function again" $ do
        ref <- newIORef 0
        let g = memoWith (: []) one (counted ref (* 2))
        xs <- mapM (evaluate . g) [1, 2, 3, 1, 2, 3, 1]
        xs @?= [2, 4, 6, 2, 4, 6, 2]
        readIORef ref >>= (@?= 3),
      testCase "a key outside the digits is evaluated at every look-up" $ do
        ref <- newIORef 0
        let g = memoWith (: []) one (counted ref (* 2))
        mapM_ (evaluate . g) [-1, -1, -1]
        readIORef ref >>= (@?= 3),
      testCase "the values of keys never looked up are not evaluated" $ do
        let g = memoWith (: []) one (\n -> if n == 42 then 1 else error ("evaluated " <> show n))
        g (42 :: Int) @?= (1 :: Int),
      testCase "a text key of several digits" $ do
        let g = memoWith textDigits (T.pack . map toEnum . drop 1) T.length
        forM_ texts $ \t -> g t @?= T.length t,
      testGroup
        "the key of a shaping and a text (docs/adr/0253)"
        [ testCase "one character in the role body without features is four digits" $
            shapingTextKey roles (Shaping "body" False [] False, "あ") @?= [0, 0, 1, 0x3042],
          testCase "the role's number and the two bits are the first digit" $
            map (\(r, v, d) -> take 1 (shapingTextKey roles (Shaping r v [] d, "a"))) [("body", True, False), ("ruby", False, True), ("見出し", True, True)]
              @?= [[2], [5], [11]],
          testCase "a role outside the table has the number after the last and its name" $
            shapingTextKey roles (Shaping "none" False [] False, "a") @?= [12, 4, 110, 111, 110, 101, 0, 1, 97],
          testCase "a tag is two digits, the sign above the first fourteen bits" $
            map (\f -> drop 2 (shapingTextKey roles (Shaping "body" False [f] False, ""))) ["palt", "+kern", "-vpal"]
              @?= [[112 * 128 + 97, 108 * 128 + 116, 0], [1 * 16384 + 107 * 128 + 101, 114 * 128 + 110, 0], [2 * 16384 + 118 * 128 + 112, 97 * 128 + 108, 0]],
          testCase "the boundaries: every key is decoded to itself" $
            forM_ shapings $ \s -> forM_ texts $ \t ->
              fromShapingTextKey roles (shapingTextKey roles (s, t)) @?= (s, t),
          testCase "the boundaries: different shapings and texts have different keys" $ do
            let keys = [shapingTextKey roles (s, t) | s <- shapings, t <- texts]
            length (nub keys) @?= length keys,
          testCase "the boundaries: a key is in the digits unless a feature is not a tag" $
            forM_ shapings $ \s -> forM_ texts $ \t ->
              (shExtra s, inRange (shapingTextKey roles (s, t))) @?= (shExtra s, all isTag (shExtra s)),
          testProperty "I2: a key is decoded to its shaping and text" . property $ do
            k <- forAll (genShaping genAny)
            fromShapingTextKey roles (shapingTextKey roles k) === k,
          testProperty "I2: different shapings and texts have different keys" . property $ do
            a <- forAll (genShaping genAny)
            b <- forAll (genShaping genAny)
            (a /= b) ==> (shapingTextKey roles a /= shapingTextKey roles b),
          testProperty "I3: a key of a role of the table, tags and code points is in the digits" . property $ do
            k <- forAll (genShaping genInTable)
            assert (inRange (shapingTextKey roles k))
        ]
    ]
  where
    isTag f = case T.unpack f of
      [_, _, _, _] -> T.all (< '\x80') f
      [s, _, _, _, _] -> s `elem` ("+-" :: String) && T.all (< '\x80') f
      _ -> False

infixr 0 ==>

(==>) :: (MonadTest m) => Bool -> Bool -> m ()
p ==> q = if p then assert q else success
