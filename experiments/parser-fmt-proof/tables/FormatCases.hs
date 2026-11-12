module Main (main) where

import Control.Monad (replicateM)
import Data.Char (ord)
import Data.List (intercalate)
import qualified Data.Text as T
import Golem.Eval.File (parseCsv, parseTsv)
import Golem.Fmt (formatTable)
import Golem.Syntax (FileId (..))

main :: IO ()
main = do
  mapM_ checkLength [0 .. 7]
  mapM_ checkParser [("csv", ',', parseCsv), ("tsv", '\t', parseTsv)]
  where
    checkLength n = mapM_ emit (replicateM n ['\xFEFF', '甲', '𠮷', '\r', '\n'])
    scalars = intercalate "," . map (show . ord)
    emit input = putStrLn (scalars input ++ " => " ++ scalars (T.unpack (formatTable (T.pack input))))
    checkParser (label, separator, parse) =
      mapM_ (mapM_ check . flip replicateM ['甲', separator, '\n', '\r', '"']) [0 .. 5]
      where
        check input = do
          let output = case parse (FileId 0) (T.pack input) of
                Left _ -> "-"
                Right rows -> show (map (map (map ord . T.unpack)) rows)
          putStrLn (label ++ " " ++ scalars input ++ " => " ++ output)
