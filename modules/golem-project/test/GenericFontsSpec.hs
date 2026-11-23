-- | fonts of [targets.html] and [targets.epub], and generic-family of the roles (root ADR 0423).
module GenericFontsSpec (tests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Project.Manifest
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "fonts and generic-family (root ADR 0423)"
    [ testCase "root ADR 0423 I8: without fonts, HTML and EPUB name generic families" $
        fmap webFonts (parse "[targets.html]\n\n[targets.epub]\n") @?= Right (WebFontsGeneric, WebFontsGeneric),
      testCase "root ADR 0423 I5: fonts = \"embed\" and \"generic\" are read for each target" $ do
        fmap webFonts (parse "[targets.html]\nfonts = \"embed\"\n\n[targets.epub]\nfonts = \"generic\"\n") @?= Right (WebFontsEmbed, WebFontsGeneric)
        fmap webFonts (parse "[targets.html]\nfonts = \"generic\"\n\n[targets.epub]\nfonts = \"embed\"\n") @?= Right (WebFontsGeneric, WebFontsEmbed),
      testCase "root ADR 0423 I7: a value of fonts that is neither generic nor embed is one G03280 at the value" $
        mapM_
          ( \(table, v) -> do
              let src = manifestText ("[targets." <> table <> "]\nfonts = " <> v <> "\n")
              (table, v, either (Left . map (\d -> (code d, spanStart (diagSpan d)))) (const (Right ())) (parseManifest (FileId 0) src))
                @?= (table, v, Left [("G03280", offsetOf ("fonts = " <> v) src + 8)])
          )
          [(t, v) | t <- ["html", "epub"], v <- ["\"serif\"", "\"Embed\"", "\"\"", "true", "1"]],
      testCase "root ADR 0423: the language server completes the values of fonts" $ do
        manifestChoiceValues ["targets", "html", "fonts"] False @?= ["generic", "embed"]
        manifestChoiceValues ["targets", "epub", "fonts"] False @?= ["generic", "embed"],
      testCase "root ADR 0423 I2: generic-family is read for each of its values and is Nothing when not written" $ do
        mapM_
          (\(v, g) -> fmap (genericOf "body") (parseStyle (FileId 0) ("[fonts.body]\nja = \"a.otf\"\ngeneric-family = \"" <> v <> "\"\n")) @?= Right (Just g))
          [("serif", GenericSerif), ("sans-serif", GenericSansSerif), ("monospace", GenericMonospace)]
        fmap (genericOf "body") (parseStyle (FileId 0) "[fonts.body]\nja = \"a.otf\"\n") @?= Right Nothing,
      testCase "root ADR 0423: a role may name only generic-family, with no file" $
        fmap (genericOf "heading") (parseStyle (FileId 0) "[fonts.heading]\ngeneric-family = \"sans-serif\"\n") @?= Right (Just GenericSansSerif),
      testCase "root ADR 0423 I7: a generic-family that is no generic family is one G03281" $
        mapM_
          (\v -> (v, styleCodes (parseStyle (FileId 0) ("[fonts.body]\nja = \"a.otf\"\ngeneric-family = " <> v <> "\n"))) @?= (v, ["G03281"]))
          ["\"mincho\"", "\"system-ui\"", "\"Serif\"", "\"\"", "true", "1"],
      testCase "root ADR 0423 I7: G03281 is at the value of generic-family" $ do
        let src = "[fonts.body]\nja = \"a.otf\"\ngeneric-family = \"mincho\"\n"
        either (map (spanStart . diagSpan)) (const []) (parseStyle (FileId 0) src) @?= [offsetOf "\"mincho\"" src]
    ]
  where
    parse extra = parseManifest (FileId 0) (manifestText extra)
    webFonts m = let t = manifestTargets m in (tgHtmlFonts t, tgEpubFonts t)
    genericOf role s = Map.lookup role (stFonts s) >>= frGenericFamily
    code d = let DiagnosticCode c = diagCode d in c
    styleCodes = either (map code) (const [])

-- | The UTF-8 offset of the first occurrence of a text.
offsetOf :: Text -> Text -> Int
offsetOf needle src = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

-- | A manifest of one chapter with these targets.
manifestText :: Text -> Text
manifestText targets =
  T.unlines
    [ "chapters = [\"a.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = \"テスト\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      ""
    ]
    <> targets
