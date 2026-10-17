-- | The pure memoisation of golem-driver (docs/adr ADR 0034).
module MemoSpec (memoTests) where

import Control.Exception (evaluate)
import Control.Monad (forM_)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Text qualified as T
import Golem.Driver.Memo
import Golem.Driver.Pdf (Shaping (..))
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty
import Test.Tasty.HUnit

-- | A function that counts how often it is evaluated (in the tests only).
counted :: IORef Int -> (Int -> Int) -> Int -> Int
counted ref f n = unsafePerformIO (atomicModifyIORef' ref (\c -> (c + 1, ())) >> pure (f n))
{-# NOINLINE counted #-}

shapings :: [Shaping]
shapings =
  [ Shaping role vertical extra
  | role <- ["", "body", "見出し", "ruby", T.replicate 40 "x"],
    vertical <- [False, True],
    extra <- [[], ["palt"], ["-liga", "kern"], ["", ""]]
  ]

texts :: [T.Text]
texts = ["", "a", "あ", "ab", "「、", T.singleton '\x10FFFF', "\x1F600\xFE0F"]

-- | The key of one digit back to the number.
one :: [Int] -> Int
one = \case
  (n : _) -> n
  [] -> 0

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
      testCase "the key of a shaping and a text is decoded to itself" $
        forM_ shapings $ \s -> forM_ texts $ \t ->
          fromShapingTextKey (shapingTextKey (s, t)) @?= (s, t),
      testCase "different shapings and texts have different keys" $ do
        let keys = [shapingTextKey (s, t) | s <- shapings, t <- texts]
            distinct = foldr (\k acc -> if k `elem` acc then acc else k : acc) [] keys
        length distinct @?= length keys
    ]
