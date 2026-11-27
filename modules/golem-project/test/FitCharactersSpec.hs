{- | The key fit-characters of the paragraph styles and its check against
drop-lines (root ADR 0466): how style.toml and @style-def read it, and
G03301.
-}
module FitCharactersSpec (tests) where

import Data.Either (fromLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Project.Style
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

-- | The diagnostics of a style.toml, none when it reads.
diagnosticsOf :: Text -> [Diagnostic]
diagnosticsOf src = fromLeft [] (parseStyle (FileId 0) src)

-- | The codes of the diagnostics of a style.toml.
codesOf :: Text -> [Text]
codesOf src = [c | d <- diagnosticsOf src, let DiagnosticCode c = diagCode d]

-- | The codes of a paragraph style of @style-def with one key, none when it reads.
localCodes :: Text -> LocalValue -> [Text]
localCodes key value = either (map fst) (const []) (localStyleDef ParagraphKind [(key, value)])

-- | A style.toml that reads.
styleOf :: Text -> IO Style
styleOf src = either (assertFailure . show) pure (parseStyle (FileId 0) src)

-- | The styles of a file with these paragraph styles.
localParas :: [(Text, ParaStyleDef)] -> LocalStyles
localParas xs = noLocalStyles {lsParaStyles = Map.fromList xs}

tests :: TestTree
tests =
  testGroup
    "fit-characters (root ADR 0466)"
    [ testCase "root ADR 0465 I6: drop-gap accepts zero and positive dimensions in style.toml and style-def" $ do
        mapM_ (\v -> codesOf ("[paragraph-styles.lead]\ndrop-lines = 3\ndrop-gap = " <> v <> "\n") @?= []) ["\"0pt\"", "\"2pt\"", "\"0.5zw\""]
        localCodes "drop-gap" (LocalString "2pt") @?= [],
      testCase "root ADR 0465 I6: invalid drop-lines and negative drop-gap produce one G03006 each" $ do
        mapM_ (\v -> codesOf ("[paragraph-styles.lead]\ndrop-lines = " <> v <> "\n") @?= ["G03006"]) ["0", "-1", "2.5", "true", "\"3\""]
        codesOf "[paragraph-styles.lead]\ndrop-gap = \"-1pt\"\n" @?= ["G03006"],
      testCase "root ADR 0466 I6: fit-characters of 1 and 4 read in style.toml and @style-def" $ do
        codesOf "[paragraph-styles.title]\nfit-characters = 1\n" @?= []
        codesOf "[paragraph-styles.title]\nfit-characters = 4\n" @?= []
        localCodes "fit-characters" (LocalWord "4") @?= []
        style <- styleOf "[paragraph-styles.title]\nfit-characters = 4\n[paragraph-styles.sub]\nbased-on = \"title\"\n"
        (paraStyle style (Just "title") >>= psFitCharacters) @?= Just 4
        (paraStyle style (Just "sub") >>= fitCharacters) @?= Just 4
        (paraStyle style Nothing >>= psFitCharacters) @?= Nothing,
      testCase "root ADR 0466 I6: fit-characters = 0 is one G03006" $ do
        codesOf "[paragraph-styles.title]\nfit-characters = 0\n" @?= ["G03006"]
        localCodes "fit-characters" (LocalWord "0") @?= ["G03006"],
      testCase "root ADR 0466 I6: each value of fit-characters that is not a natural number greater than 0 is one G03006" $ do
        mapM_
          (\v -> codesOf ("[paragraph-styles.title]\nfit-characters = " <> v <> "\n") @?= ["G03006"])
          ["-1", "\"4\"", "2.5", "true", "[4]"]
        localCodes "fit-characters" (LocalWord "-1") @?= ["G03006"]
        localCodes "fit-characters" (LocalString "x") @?= ["G03006"],
      testCase "root ADR 0466 I6: drop-lines reads as fit-characters does" $ do
        codesOf "[paragraph-styles.lead]\ndrop-lines = 3\n" @?= []
        codesOf "[paragraph-styles.lead]\ndrop-lines = 0\n" @?= ["G03006"],
      testCase "root ADR 0466 I5: a style that takes drop-lines by based-on and writes fit-characters is one G03301, at its table" $ do
        let src = "[paragraph-styles.lead]\ndrop-lines = 3\n[paragraph-styles.title]\nbased-on = \"lead\"\nfit-characters = 4\n"
        case diagnosticsOf src of
          [d] -> do
            diagCode d @?= DiagnosticCode "G03301"
            diagSeverity d @?= Error
            diagMessage d @?= "段落スタイル title は drop-lines と fit-characters の両方を持っています。どちらか一方を書きます"
            -- the name of the table in its header, as the other errors of a table
            spanStart (diagSpan d) @?= offsetOf src "title]"
          ds -> assertFailure (show ds),
      testCase "root ADR 0466 I5: G03301 once for each style that has both, an inherited pair included" $ do
        codesOf "[paragraph-styles.both]\ndrop-lines = 2\nfit-characters = 4\n" @?= ["G03301"]
        codesOf "[paragraph-styles.both]\ndrop-lines = 2\nfit-characters = 4\n[paragraph-styles.child]\nbased-on = \"both\"\n[paragraph-styles.other]\nfit-characters = 3\n[paragraph-styles.lead]\ndrop-lines = 2\n" @?= ["G03301", "G03301"]
        codesOf "[paragraph-styles.fit]\nfit-characters = 4\n[paragraph-styles.lead]\ndrop-lines = 2\n" @?= [],
      testCase "root ADR 0466 I5: a style of @style-def that has both is G03301 of its definition" $ do
        base <- styleOf "[paragraph-styles.lead]\ndrop-lines = 3\n"
        [(c, n) | (c, n, _) <- checkLocalStyles base (localParas [("title", noParaDef {psBasedOn = Just "lead", psFitCharacters = Just 4})])] @?= [("G03301", "title")]
        [(c, n) | (c, n, _) <- checkLocalStyles base (localParas [("title", noParaDef {psFitCharacters = Just 4})])] @?= [],
      testCase "root ADR 0466 I5: a style that has both is set as without fit-characters" $ do
        fitCharacters noParaDef {psDropLines = Just 2, psFitCharacters = Just 4} @?= Nothing
        fitCharacters noParaDef {psFitCharacters = Just 4} @?= Just 4
    ]
