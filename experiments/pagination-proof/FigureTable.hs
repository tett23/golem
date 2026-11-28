{-# LANGUAGE GHC2021 #-}

-- Root ADR 0352: finite container API comparison, not a proof of Data.Map.
module Main where

import Control.Monad (forM_, replicateM)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  putStrLn "import FigureTable\nopen BesideProducer BesideReuse BesideStore BesideFigureTable\nprivate def kindAt (xs : List Kind) (key : Nat) : Option Kind := xs[key]?\nprivate def placeAt (xs : List (Option Bool)) (key : Nat) : Option Bool := (xs[key]?).getD none\nprivate def stateAt (_ : Nat) : Unit := ()\nprivate def jobView (jobs : List (ReuseJob Unit)) : List (Nat × Nat) := jobs.map (fun job => (job.owner, job.fuel))"
  let cases = concatMap (\size -> replicateM size [0 .. 5 :: Int]) [0 .. 4]
      bool True = "true"
      bool False = "false"
      kind code = case code of
        0 -> ".paragraph"
        1 -> ".control"
        2 -> ".other"
        _ -> ".figure"
      place code = if code == 3 then Nothing else Just (code /= 4)
      option Nothing = "none"
      option (Just value) = "some " <> bool value
      list values = "[" <> intercalate ", " values <> "]"
      pair (key, value) = "(" <> show key <> ", " <> bool value <> ")"
      job (key, remaining) = "(" <> show key <> ", " <> show remaining <> ")"
  forM_ (zip [0 :: Int ..] cases) $ \(index, codes) -> do
    let count = length codes
        table = Map.fromList [(key, value) | (key, code) <- zip [0 :: Int ..] codes, code >= 3, Just value <- [place code]]
        pairs = Map.toList table
        selected test = [(key, count - key - 1) | (key, value) <- pairs, test value]
        name = "f" <> show index
    putStrLn ("private def " <> name <> " : List (Nat × Bool) := figurePairs (kindAt " <> list (map kind codes) <> ") (placeAt " <> list (map (option . place) codes) <> ") 0 " <> show count)
    putStrLn ("example : " <> name <> " = " <> list (map pair pairs) <> " := by decide")
    putStrLn ("example : jobView (tableJobs (fromPairs " <> name <> ") id stateAt " <> show count <> " 0 " <> show count <> ") = " <> list (map job (selected id)) <> " := by decide")
    putStrLn ("example : jobView (tableJobs (fromPairs " <> name <> ") not stateAt " <> show count <> " 0 " <> show count <> ") = " <> list (map job (selected not)) <> " := by decide")
  hPutStrLn stderr ("root ADR 0352 I5: " <> show (length cases) <> " figure tables, " <> show (3 * length cases) <> " closed container/job equations")
