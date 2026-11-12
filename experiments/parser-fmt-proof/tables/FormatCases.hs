module Main (main) where

import Control.Monad (replicateM)
import Data.Char (ord)
import Data.List (intercalate)
import qualified Data.Text as T
import Golem.Eval.File (parseCsv, parseTsv)
import Golem.Fmt (formatTable)
import Golem.Parser.Read (checkTableText)
import Golem.Syntax (DiagnosticCode (..), FileId (..), diagCode, diagSpan, spanEnd, spanStart)

main :: IO ()
main = do
  mapM_ checkLength [0 .. 7]
  mapM_ checkParser [("csv", ',', parseCsv), ("tsv", '\t', parseTsv)]
  mapM_ (mapM_ checkSpan . flip replicateM "甲𠮷,\n\r") [0 .. 6]
  where
    checkLength n = mapM_ emit (replicateM n ['\xFEFF', '甲', '𠮷', '\r', '\n'])
    scalars = intercalate "," . map (show . ord)
    emit input = putStrLn (scalars input ++ " => " ++ scalars (T.unpack (formatTable (T.pack input))))
    checkParser (label, separator, parse) =
      mapM_ (mapM_ check . flip replicateM ['\xFEFF', '甲', separator, '\n', '\r', '"']) [0 .. 5]
      where
        check input = do
          let output = case parse (FileId 0) (T.pack input) of
                Left _ -> "-"
                Right rows -> show (map (map (map ord . T.unpack)) rows)
          putStrLn (label ++ " " ++ scalars input ++ " => " ++ output)
    checkSpan input = do
      let render d =
            let DiagnosticCode code = diagCode d
             in unwords [T.unpack code, show (spanStart (diagSpan d)), show (spanEnd (diagSpan d))]
          reports = map render (checkTableText (FileId 9) (T.pack input))
      putStrLn ("span " ++ scalars input ++ " => " ++ intercalate ";" reports)
