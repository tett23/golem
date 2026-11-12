module Main (main) where

import Control.Monad (replicateM)
import Data.Char (ord)
import Data.List (intercalate)
import qualified Data.Text as T
import Golem.Fmt (formatTable)

main :: IO ()
main = mapM_ checkLength [0 .. 7]
  where
    checkLength n = mapM_ emit (replicateM n ['\xFEFF', '甲', '𠮷', '\r', '\n'])
    scalars = intercalate "," . map (show . ord)
    emit input = putStrLn (scalars input ++ " => " ++ scalars (T.unpack (formatTable (T.pack input))))
