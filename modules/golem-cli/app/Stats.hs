{- | Manuscript volume in the master flow (Golem ADR 0355). The grapheme
clusters and the word segments come from golem-unicode (UAX #29, Unicode
17.0.0; docs/adr/0411); a segment with a letter or a number (L* or N*) is
a word.
-}
module Stats (printStats) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Unicode.Category (isLetterOrNumber)
import Golem.Unicode.Grapheme (graphemeClusters)
import Golem.Unicode.Word (wordSegments)

printStats :: Integer -> Integer -> ([Text], Integer) -> IO ()
printStats columns rows (logicalLines, actualLines) = do
  let counts = map count logicalLines
      characters = sum (map fst counts)
      wordsInBody = sum (map snd counts)
      gridLines = sum [max 1 (ceilingOf n columns) | (n, _) <- counts]
  putStrLn ("本文文字数: " <> show characters)
  putStrLn ("ワード数: " <> show wordsInBody)
  putStrLn ("組版後の行数: " <> show actualLines)
  putStrLn ("換算ページ数: " <> show (ceilingOf gridLines rows) <> " (" <> show columns <> "字 × " <> show rows <> "行)")
  where
    ceilingOf n d = (n + d - 1) `div` d
    count :: Text -> (Integer, Integer)
    count t =
      ( toInteger (length (graphemeClusters t)),
        toInteger (length (filter (T.any isLetterOrNumber) (wordSegments t)))
      )
