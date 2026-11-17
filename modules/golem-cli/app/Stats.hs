-- | Manuscript volume in the master flow (Golem ADR 0355).
module Stats (printStats) where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Foreign.C.String (CString)
import Foreign.C.Types (CSize (..))

foreign import ccall unsafe "golem_stats_characters" countCharacters :: CString -> CSize -> IO CSize

foreign import ccall unsafe "golem_stats_words" countWords :: CString -> CSize -> IO CSize

printStats :: Integer -> Integer -> ([Text], Integer) -> IO ()
printStats columns rows (logicalLines, actualLines) = do
  counts <- mapM count logicalLines
  let characters = sum (map fst counts)
      wordsInBody = sum (map snd counts)
      gridLines = sum [max 1 (ceilingOf n columns) | (n, _) <- counts]
  putStrLn ("本文文字数: " <> show characters)
  putStrLn ("ワード数: " <> show wordsInBody)
  putStrLn ("組版後の行数: " <> show actualLines)
  putStrLn ("換算ページ数: " <> show (ceilingOf gridLines rows) <> " (" <> show columns <> "字 × " <> show rows <> "行)")
  where
    ceilingOf n d = (n + d - 1) `div` d
    count t = BS.useAsCStringLen (TE.encodeUtf8 t) $ \(ptr, len) -> do
      chars <- countCharacters ptr (fromIntegral len)
      ws <- countWords ptr (fromIntegral len)
      pure (toInteger chars, toInteger ws)
