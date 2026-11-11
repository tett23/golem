module Main (main) where
import Data.Text qualified as T
import Golem.Project.Style (parseDim)
import Names
import System.Exit (exitFailure)

main :: IO ()
main = do
  let config="[values.length]\nindent=\"1zw\"\n[values.aki]\nhalf=\"二分\"\n[values.count]\nrows=2\n"
      checked src kind ref = readNames src >>= lookupName kind ref
      probes =
        [ ("320 I1 preserve relative unit", checked config "length" "indent" == Right (Length (maybe (error "literal") id (parseDim "1zw"))))
        , ("320 I1 preserve aki ratio", checked config "aki" "half" == Right (Aki (1/2)))
        , ("320 I1 count", checked config "count" "rows" == Right (Count 2))
        , ("320 I1 unknown name", checked config "count" "absent" == Left "G03257")
        , ("320 I1 wrong kind", checked config "count" "indent" == Left "G03258")
        , ("320 I3 duplicate across tables", readNames (config <> "[values.count2]\n") /= Left "G03254" && readNames (T.replace "rows=2" "half=2" config) == Left "G03254")
        , ("320 I3 invalid identifier", readNames "[values.length]\nBad=\"1zw\"\n" == Left "G03255")
        , ("320 I3 invalid value", readNames "[values.count]\nrows=-1\n" == Left "G03256")
        , ("320 I3 forbid alias", readNames "[values.length]\na=\"b\"\n" == Left "G03256")
        ]
  mapM_ print probes
  print (length (filter snd probes),length probes)
  if all snd probes then pure () else exitFailure
