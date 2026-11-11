{- | The schema of the preflight rules (docs/adr ADR 0169): every key of
the schema is one the decoder reads, the unknown keys keep their code and
position, an error of a value does not hide an unknown key, and every
value of an enumeration is read.
-}
module RulesSchemaSpec (tests) where

import Data.List (isPrefixOf)
import Data.Text (Text)
import Golem.Preflight.Rules
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Toml.Schema (FromValue (..), MatchMessage (..), Matcher, Result (..), Value, Value' (..), runMatcher, table)

-- | Every key of a schema with the keys to it and its node; the schema of the rules has no named tables.
keyPaths :: Node -> [([Text], Node)]
keyPaths = go []
  where
    go pre = \case
      NTable kvs -> concat [(pre <> [k], n) : go (pre <> [k]) n | (k, n) <- kvs]
      NArray n -> go pre n
      NEither ns -> concatMap (go pre) ns
      _ -> []

-- | A TOML document with the value at the keys.
docWith :: [Text] -> Value -> Value
docWith ks leaf = foldr (\k v -> Table (table [(k, v)])) leaf ks

sample :: Node -> Value
sample = \case
  NValue l -> leaf l
  NTable _ -> Table (table [])
  NArray (NValue l) -> List [leaf l]
  NArray _ -> List []
  NEither (n : _) -> sample n
  _ -> Text "x"
  where
    leaf = \case
      LString -> Text "x"
      LDimension -> Text "1pt"
      -- 0 skips a tier of resolution, so that warning-below is never below error-below
      LInteger -> Integer 0
      LBoolean -> Bool False
      LFalse -> Bool False
      LEnum (v : _) -> Text v
      LEnum [] -> Text "x"
      LRef _ -> Text "x"

enumValues :: Node -> [Value]
enumValues = \case
  NValue (LEnum vs) -> map Text vs
  NEither ns -> concatMap enumValues ns
  NArray n -> [List [v] | v <- enumValues n]
  _ -> []

decodeRules :: Value -> Result (MatchMessage ()) RulesFile
decodeRules v = runMatcher (fromValue v :: Matcher () RulesFile)

unexpected :: MatchMessage () -> Bool
unexpected = isPrefixOf "unexpected key: " . matchMessage

-- | The code, message and line (from 0) of each diagnostic.
errorsOf :: Text -> [(Text, Text, Int)]
errorsOf src =
  either
    (\ds -> [(c, diagMessage d, lcLine (offsetToLineCol (mkLineIndex src) (spanStart (diagSpan d)))) | d <- ds, let DiagnosticCode c = diagCode d])
    (const [])
    (parseRules (FileId 0) src)

tests :: TestTree
tests =
  testGroup
    "the schema of the rules (docs/adr ADR 0169)"
    [ testCase "every key of the schema is read by the decoder" $ do
        let paths = keyPaths rulesSchema
        assertBool "the schema has keys" (length paths > 30)
        mapM_
          ( \(ks, node) -> case decodeRules (docWith ks (if ks == ["page-count", "multiple-of"] then Integer 1 else sample node)) of
              Success ws _ -> assertBool (show (ks, ws)) (not (any unexpected ws))
              Failure es -> assertFailure ("the sample does not read: " <> show (ks, es))
          )
          paths,
      testCase "every value of an enumeration is read at its key" $
        mapM_
          (\(ks, node) -> mapM_ (\v -> case decodeRules (docWith ks v) of Success [] _ -> pure (); Success ws _ -> assertFailure (show (ks, v, ws)); Failure es -> assertFailure (show (ks, v, es))) (enumValues node))
          (keyPaths rulesSchema),
      testCase "the enumerations of severity, based-on and allowed" $ do
        map fst levelValues @?= ["error", "warning", "off"]
        map fst builtinRules @?= ["basic", "print", "screen", "none"]
        fontFormatValues @?= ["cff", "cff2", "truetype"]
        colorSpaceValues @?= ["cmyk", "gray", "rgb"],
      testCase "an unknown key of a check: G09001 at the key, with its path" $
        errorsOf "[bleed-size]\nseverity = \"error\"\nmaximum = \"3mm\"\n" @?= [("G09001", "知らないキーです: bleed-size.maximum", 2)],
      testCase "the retired image-unplaceable is an unknown key (golem-pdf ADR 0008)" $
        errorsOf "[image-unplaceable]\nseverity = \"off\"\n" @?= [("G09001", "知らないキーです: image-unplaceable", 0)],
      testCase "an error of a value and an unknown key are both reported, in the order of their positions" $
        errorsOf "[bleed-size]\nmin = \"1zw\"\nmaximum = \"3mm\"\n"
          @?= [ ("G09001", "min の値が正しくありません: 1zw（zw は使えません。3mm や 0.25pt のように書きます） (bleed-size.min)", 1),
                ("G09001", "知らないキーです: bleed-size.maximum", 2)
              ],
      testCase "a severity outside its values keeps its message" $
        errorsOf "[pdf-x]\nseverity = \"notice\"\n" @?= [("G09001", "severity の値が正しくありません: notice（error、warning、off のどれかにします） (pdf-x.severity)", 1)],
      testCase "a based-on outside its values keeps its message" $
        errorsOf "based-on = \"strict\"\n" @?= [("G09001", "based-on の値が正しくありません: strict（basic、print、screen、none のどれかにします） (based-on)", 0)],
      testCase "an allowed outside its values keeps its message" $
        errorsOf "[font-formats]\nallowed = [\"otf\"]\n" @?= [("G09001", "allowed の値が正しくありません: otf（cff、cff2、truetype のどれかにします） (font-formats.allowed)", 1)]
    ]
