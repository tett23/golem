{-# LANGUAGE OverloadedStrings #-}
-- The input frame of the wasm reactor (Golem.Wasm.Frame.readFiles) with
-- many files: the time of reading it, which is quadratic in the number of
-- files because of the check for duplicates (path `elem` seen).
--   frame-probe N      an input frame of N files named f<i>, 1 byte each
--   frame-probe empty  whether the empty path "" is accepted
import Data.ByteString.Char8 qualified as BC
import Data.Time.Clock (diffUTCTime, getCurrentTime)
import Golem.Wasm.Frame
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["empty"] -> print (readFiles (writeFiles [("", "x")]))
    [n] -> do
      let files = [("f" ++ show i, "x") | i <- [1 .. read n :: Int]]
          frame = writeFiles files
      BC.length frame `seq` pure ()
      t0 <- getCurrentTime
      r <- case readFiles frame of
        Right fs -> pure (length fs)
        Left e -> error (show e)
      t1 <- getCurrentTime
      putStrLn (n ++ " files, " ++ show (BC.length frame) ++ " bytes: " ++ show r ++ " read in " ++ show (diffUTCTime t1 t0))
    _ -> error "frame-probe N | empty"
