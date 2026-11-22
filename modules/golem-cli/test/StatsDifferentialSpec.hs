{- | The counts of golem-unicode against those of libgrapheme 3.0.0, the C
of the manuscript statistics (docs/adr ADR 0411 I4), before the C is
removed.
-}
module StatsDifferentialSpec (statsDifferentialTests) where

import Control.Monad (replicateM)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Foreign.C.String (CString)
import Foreign.C.Types (CSize (..))
import Golem.Unicode.Category (isLetterOrNumber)
import Golem.Unicode.Grapheme (graphemeClusters)
import Golem.Unicode.Word (wordSegments)
import Test.Tasty
import Test.Tasty.HUnit

foreign import ccall unsafe "golem_stats_characters" cCharacters :: CString -> CSize -> IO CSize

foreign import ccall unsafe "golem_stats_words" cWords :: CString -> CSize -> IO CSize

statsDifferentialTests :: TestTree
statsDifferentialTests =
  testCase "root ADR 0411 I4: golem-unicode counts as libgrapheme 3.0.0 for every sequence of up to four of the fifteen characters" $ do
    let inputs = [T.pack s | n <- [0 .. 4], s <- replicateM n alphabet]
    results <- mapM (\t -> (,) t <$> cCounts t) inputs
    length results @?= 54241
    let failures = [(t, c, hsCounts t) | (t, c) <- results, hsCounts t /= c]
    case failures of
      [] -> pure ()
      _ -> assertFailure (show (length failures) <> " sequences differ (text, C, Haskell):\n" <> unlines (map show (take 10 failures)))
  where
    alphabet = "a' あア漢\x0301\x200D\x1F468\x1F1EF\x1F1F5\r\n1."

cCounts :: Text -> IO (Int, Int)
cCounts t = BS.useAsCStringLen (TE.encodeUtf8 t) $ \(ptr, len) -> do
  g <- cCharacters ptr (fromIntegral len)
  w <- cWords ptr (fromIntegral len)
  pure (fromIntegral g, fromIntegral w)

hsCounts :: Text -> (Int, Int)
hsCounts t = (length (graphemeClusters t), length (filter (T.any isLetterOrNumber) (wordSegments t)))
