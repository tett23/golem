{-# LANGUAGE GHC2021 #-}

-- Root ADR 0352: finite container and payload-to-job comparison.
module Main where

import Control.Monad (forM_, replicateM)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import System.IO (hPutStrLn, stderr)

main :: IO ()
main = do
  putStrLn "import FigureJobValues\nopen BesideProducer BesideReuse BesideStore BesideFigureTable BesideJobValues\nprivate def kindAt (xs : List Kind) (key : Nat) : Option Kind := xs[key]?\nprivate def placeAt (xs : List (Option (Nat × Bool))) (key : Nat) : Option (Nat × Bool) := (xs[key]?).getD none\nprivate def eligible (value : Nat × Bool) : Bool := value.2\nprivate def initState (key : Nat) (value : Nat × Bool) : Nat := 1000 + key + value.1\nprivate def jobView (jobs : List (ReuseJob Nat)) : List (Nat × (Nat × Nat)) := jobs.map (fun job => (job.owner, (job.fuel, job.state)))"
  let cases = concatMap (\size -> replicateM size [0 .. 5 :: Int]) [0 .. 4]
      bool True = "true"
      bool False = "false"
      kind code = case code of
        0 -> ".paragraph"
        1 -> ".control"
        2 -> ".other"
        _ -> ".figure"
      place key code = if code == 3 then Nothing else Just (100 + 10 * key + code, code /= 4)
      valueText (value, flag) = "(" <> show value <> ", " <> bool flag <> ")"
      option Nothing = "none"
      option (Just value) = "some " <> valueText value
      list values = "[" <> intercalate ", " values <> "]"
      pair (key, value) = "(" <> show key <> ", " <> valueText value <> ")"
      job (key, (remaining, state)) = "(" <> show key <> ", (" <> show remaining <> ", " <> show state <> "))"
  forM_ (zip [0 :: Int ..] cases) $ \(index, codes) -> do
    let count = length codes
        places = [place key code | (key, code) <- zip [0 :: Int ..] codes]
        table = Map.fromList [(key, value) | (key, code) <- zip [0 :: Int ..] codes, code >= 3, Just value <- [place key code]]
        pairs = Map.toList table
        selected test = [(key, (count - key - 1, 1000 + key + value)) | (key, (value, flag)) <- pairs, test flag]
        name = "f" <> show index
    putStrLn ("private def " <> name <> " : List (Nat × (Nat × Bool)) := figurePairs (kindAt " <> list (map kind codes) <> ") (placeAt " <> list (map option places) <> ") 0 " <> show count)
    putStrLn ("example : " <> name <> " = " <> list (map pair pairs) <> " := by decide")
    putStrLn ("example : jobView (valueJobs eligible initState " <> show count <> " " <> name <> ") = " <> list (map job (selected id)) <> " := by decide")
    putStrLn ("example : jobView (valueJobs (fun value => !eligible value) initState " <> show count <> " " <> name <> ") = " <> list (map job (selected not)) <> " := by decide")
  hPutStrLn stderr ("root ADR 0352 I5: " <> show (length cases) <> " figure payload tables, " <> show (3 * length cases) <> " closed payload/job equations")
