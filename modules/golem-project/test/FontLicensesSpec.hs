-- | ja-license and latin-license of the roles of [fonts] (root ADR 0433).
module FontLicensesSpec (tests) where

import Control.Monad (forM_)
import Data.List (subsequences)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Project.Manifest (Targets (..), WebFonts (..), embedsFonts)
import Golem.Project.Style
import Golem.Project.TomlSchema
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "license documents of fonts (root ADR 0433)"
    [ testCase "root ADR 0433 I1: ja-license and latin-license are read as paths from the root" $ do
        let src = "[fonts.body]\nja = \"fonts/a.otf\"\nja-license = \"fonts/OFL.txt\"\nlatin = \"fonts/b.otf\"\nlatin-license = \"fonts/LICENSE.md\"\n"
        fmap (licensesOf "body") (parseStyle (FileId 0) src) @?= Right (Just (Just "fonts/OFL.txt", Just "fonts/LICENSE.md")),
      testCase "root ADR 0433 I1: without ja-license and latin-license, a role has no license document" $
        fmap (licensesOf "body") (parseStyle (FileId 0) "[fonts.body]\nja = \"fonts/a.otf\"\n") @?= Right (Just (Nothing, Nothing)),
      testCase "root ADR 0433 I1: each font file comes with the license of its key, in the order of fontFiles" $ do
        let src = "[fonts.body]\nja = \"fonts/a.otf\"\nja-license = \"fonts/A.txt\"\nlatin = \"fonts/b.otf\"\n\n[fonts.code]\nlatin = \"fonts/c.otf\"\nlatin-license = \"fonts/C.txt\"\nja-license = \"fonts/unused.txt\"\n"
        fmap fontFilesWithLicenses (parseStyle (FileId 0) src)
          @?= Right
            [ FontFile "body" "ja" "fonts/a.otf" (Just "fonts/A.txt"),
              FontFile "body" "latin" "fonts/b.otf" Nothing,
              FontFile "code" "latin" "fonts/c.otf" (Just "fonts/C.txt")
            ]
        fmap (map (\f -> (ffRole f, ffPath f)) . fontFilesWithLicenses) (parseStyle (FileId 0) src) @?= fmap fontFiles (parseStyle (FileId 0) src),
      testCase "root ADR 0433: the schema of [fonts] has ja-license and latin-license" $
        case styleSchema of
          NTable kvs | Just (NNamed _ (NTable keys)) <- lookup "fonts" kvs -> map fst (filter ((`elem` ["ja-license", "latin-license"]) . fst) keys) @?= ["ja-license", "latin-license"]
          _ -> assertFailure "no [fonts] in the schema",
      testCase "root ADR 0448 I1: no [fonts] is no G03282" $
        licenseDiags "" (const True) @?= Right [],
      testCase "root ADR 0448 I1: one font without its license key is one G03282 at the top of style.toml" $
        licenseDiags "[fonts.body]\nja = \"fonts/b.otf\"\n" (const True)
          @?= Right [("G03282", Warning, 0, 0, "フォントのライセンスの文書を指定していません: [fonts.body] の ja-license（fonts/b.otf）")],
      testCase "root ADR 0448 I1: two fonts without their license keys are two G03282, one for each" $
        fmap (map (\(c, _, _, _, m) -> (c, m))) (licenseDiags "[fonts.body]\nja = \"fonts/b.otf\"\nlatin = \"fonts/l.otf\"\n" (const True))
          @?= Right
            [ ("G03282", "フォントのライセンスの文書を指定していません: [fonts.body] の ja-license（fonts/b.otf）"),
              ("G03282", "フォントのライセンスの文書を指定していません: [fonts.body] の latin-license（fonts/l.otf）")
            ],
      testCase "root ADR 0448 I1: a font with its license key, and a font that is not present, have no G03282" $ do
        licenseDiags "[fonts.body]\nja = \"fonts/b.otf\"\nja-license = \"fonts/OFL.txt\"\n" (const True) @?= Right []
        fmap (map (\(_, _, _, _, m) -> m)) (licenseDiags "[fonts.body]\nja = \"fonts/b.otf\"\nlatin = \"fonts/l.otf\"\n" (/= "fonts/b.otf"))
          @?= Right ["フォントのライセンスの文書を指定していません: [fonts.body] の latin-license（fonts/l.otf）"],
      testCase "root ADR 0448 I1: for every set of license keys of two roles, one G03282 for each font without its key" $
        forM_ (subsequences fontsOfTwoRoles) $ \licensed -> do
          let keyOf f@(_, k, _) = if f `elem` licensed then k <> "-license = \"fonts/L.txt\"\n" else ""
              rolesOf r = mconcat [keyOf f | f@(r', _, _) <- fontsOfTwoRoles, r' == r]
              src = "[fonts.body]\nja = \"fonts/a.otf\"\nlatin = \"fonts/b.otf\"\n" <> rolesOf "body" <> "\n[fonts.code]\nlatin = \"fonts/c.otf\"\n" <> rolesOf "code"
              expected = [missingMessage f | f <- fontsOfTwoRoles, f `notElem` licensed]
          (licensed, fmap (map (\(_, _, _, _, m) -> m)) (licenseDiags src (const True))) @?= (licensed, Right expected),
      testCase "root ADR 0448 I2: embedsFonts is true exactly when a built web target has fonts = \"embed\"" $
        forM_ [(hf, ef, h, e) | hf <- [WebFontsGeneric, WebFontsEmbed], ef <- [WebFontsGeneric, WebFontsEmbed], h <- [False, True], e <- [False, True]] $ \(hf, ef, h, e) ->
          ((hf, ef, h, e), embedsFonts (targetsOf hf ef) h e) @?= ((hf, ef, h, e), (h && hf == WebFontsEmbed) || (e && ef == WebFontsEmbed))
    ]
  where
    licenseDiags :: Text -> (FilePath -> Bool) -> Either [Diagnostic] [(Text, Severity, Int, Int, Text)]
    licenseDiags src present =
      fmap
        (map (\d -> let DiagnosticCode c = diagCode d in (c, diagSeverity d, spanStart (diagSpan d), spanEnd (diagSpan d), diagMessage d)) . (\st -> fontLicenseKeyDiagnostics (FileId 0) st present))
        (parseStyle (FileId 0) src)
    fontsOfTwoRoles :: [(Text, Text, Text)]
    fontsOfTwoRoles = [("body", "ja", "fonts/a.otf"), ("body", "latin", "fonts/b.otf"), ("code", "latin", "fonts/c.otf")]
    missingMessage :: (Text, Text, Text) -> Text
    missingMessage (r, k, p) = "フォントのライセンスの文書を指定していません: [fonts." <> r <> "] の " <> k <> "-license（" <> p <> "）"
    targetsOf :: WebFonts -> WebFonts -> Targets
    targetsOf hf ef = Targets {tgPdf = Nothing, tgEpub = Just Nothing, tgHtml = True, tgText = [], tgPdfA = Nothing, tgPdfUa = Nothing, tgPdfScreen = Nothing, tgEpubPageMap = Nothing, tgHtmlFonts = hf, tgEpubFonts = ef}
    licensesOf :: Text -> Style -> Maybe (Maybe FilePath, Maybe FilePath)
    licensesOf role s = (\fr -> (frJaLicense fr, frLatinLicense fr)) <$> Map.lookup role (stFonts s)
