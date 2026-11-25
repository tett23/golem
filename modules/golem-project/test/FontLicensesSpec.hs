-- | ja-license and latin-license of the roles of [fonts] (root ADR 0433).
module FontLicensesSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
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
          _ -> assertFailure "no [fonts] in the schema"
    ]
  where
    licensesOf :: Text -> Style -> Maybe (Maybe FilePath, Maybe FilePath)
    licensesOf role s = (\fr -> (frJaLicense fr, frLatinLicense fr)) <$> Map.lookup role (stFonts s)
