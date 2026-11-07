-- | The table [vars] of manifest.toml (docs/adr/0185).
module VarsSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (fromGregorian)
import Golem.Project
import Golem.Project.Style (RunningPart (..), RunningRef (..), parseRunningFormat)
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

manifestOf :: Text -> Text
manifestOf extra =
  T.unlines
    [ "chapters = [\"a.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = \"テスト\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      "",
      "[targets.html]",
      "",
      extra
    ]

parsed :: Text -> Either [(Text, Int)] Manifest
parsed src = case parseManifest (FileId 0) src of
  Right m -> Right m
  Left ds -> Left [(c, spanStart (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]

varsOf :: Text -> Either [(Text, Int)] (Map.Map Text ProjectVar)
varsOf = fmap manifestVars . parsed . manifestOf

tests :: TestTree
tests =
  testGroup
    "[vars] (docs/adr/0185)"
    [ testCase "strings, integers, booleans, dates, arrays and tables are read" $
        varsOf "[vars]\nproduct = \"Golem\"\ncount = 3\nminus = -2\nbeta = true\nreleased = 2026-11-06\nlist = [\"a\", 1]\n\n[vars.author]\nshort = \"tett23\"\n"
          @?= Right
            ( Map.fromList
                [ ("product", VarString "Golem"),
                  ("count", VarInteger 3),
                  ("minus", VarInteger (-2)),
                  ("beta", VarBool True),
                  ("released", VarDate (fromGregorian 2026 11 6)),
                  ("list", VarArray [VarString "a", VarInteger 1]),
                  ("author", VarTable (Map.fromList [("short", VarString "tett23")]))
                ]
            ),
      testCase "without [vars] the namespace is empty" $
        varsOf "" @?= Right Map.empty,
      testCase "a float, a time and a date-time are G03109 at the value" $
        mapM_
          ( \v -> do
              let src = manifestOf ("[vars]\nx = " <> v <> "\n")
              parsed src @?= Left [("G03109", offsetOf src ("x = " <> v) + 4)]
          )
          ["1.5", "12:30:00", "2026-11-06T12:30:00", "2026-11-06T12:30:00+09:00"],
      testCase "a float in an array and in a table is G03109 at the value" $ do
        let src = manifestOf "[vars]\nlist = [1, 2.5]\n\n[vars.t]\nratio = 0.5\n"
        parsed src @?= Left [("G03109", offsetOf src "2.5"), ("G03109", offsetOf src "0.5")],
      testCase "a key that is not an identifier is G03110 at the key" $
        mapM_
          ( \k -> do
              let src = manifestOf ("[vars]\n" <> k <> " = 1\n")
              parsed src @?= Left [("G03110", offsetOf src k)]
          )
          ["edition-count", "2nd", "\"日本語\""],
      testCase "a key of a table in [vars] that is not an identifier is G03110" $ do
        let src = manifestOf "[vars.author]\nshort-name = \"x\"\n"
        parsed src @?= Left [("G03110", offsetOf src "short-name")],
      testCase "[vars] that is no table is G03001" $
        either (map fst) (const []) (parsed (manifestOf "vars = 1\n")) @?= ["G03001"],
      testCase "{vars.<name>} of a running head format is read" $ do
        parseRunningFormat "{vars.product}" @?= Right [PartRef (RefProjectVar ["product"]) False]
        parseRunningFormat "{vars.author.short?}" @?= Right [PartRef (RefProjectVar ["author", "short"]) True]
        either (const True) (const False) (parseRunningFormat "{vars}") @? "{vars} is no slot"
    ]
