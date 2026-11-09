{- | The boxes of paragraph styles through the driver (docs/adr/0271): the
CSS of div.box-<name>, with the radius of the corners that are rounded
only, and a book with boxes built to PDF and HTML.
-}
module BoxesSpec (boxesTests) where

import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The swatches of the tests.
swatches :: T.Text
swatches = "[color.swatches]\npale = { cmyk = [8, 0, 0, 0] }\nblue = { cmyk = [100, 60, 0, 0] }\n\n"

-- | The rule of div.box-<name> in the style.css of a book of the style given (a paragraph of the style written), if any.
ruleOf :: T.Text -> T.Text -> IO (Maybe T.Text)
ruleOf name toml = withSystemTempDirectory "golem-boxes-css" $ \tmp -> do
  writeProject tmp (miniManifest <> "\n[targets.html]\n") (horizontalStyle <> fakeBody <> "\n" <> TE.encodeUtf8 toml) ("@style " <> name <> "\n本文。\n") fakeFontFiles
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider}
  filter isError (brDiagnostics r) @?= []
  css <- TIO.readFile (tmp </> "build/html/style.css")
  pure
    ( case filter (T.isPrefixOf ("div.box-" <> name <> " {")) (T.lines css) of
        l : _ -> Just l
        [] -> Nothing
    )

-- | The declarations of a rule.
declsOf :: T.Text -> T.Text -> IO (Maybe [T.Text])
declsOf name toml = fmap (map T.strip . filter (not . T.null . T.strip) . T.splitOn ";" . T.dropEnd 1 . T.drop 1 . T.dropWhile (/= '{')) <$> ruleOf name toml

radii :: Maybe [T.Text] -> [T.Text]
radii = maybe [] (filter ("-radius" `T.isInfixOf`))

boxesTests :: TestTree
boxesTests =
  testGroup
    "the boxes of paragraph styles through the driver (docs/adr/0271)"
    [ testCase "HTML: the declarations of the box; a style without one has none" $ do
        d <- declsOf "column" (swatches <> "[paragraph-styles.column]\nbackground = \"pale\"\npadding = \"1zw\"\nborder = \"blue\"\nborder-width = \"0.5pt\"\nborder-style = \"dashed\"\nborder-sides = [\"before\", \"start\"]\nindent = \"2zw\"\n")
        d
          @?= Just
            [ "background-color: rgb(235, 255, 255)",
              "padding: 1em",
              "border-block-start: 0.5pt dashed rgb(0, 102, 255)",
              "border-inline-start: 0.5pt dashed rgb(0, 102, 255)",
              "margin-inline-start: 2em"
            ]
        none <- declsOf "plain" (swatches <> "[paragraph-styles.plain]\nindent = \"1zw\"\n")
        none @?= Nothing,
      testCase "HTML: the radius of the corners rounded only: every corner of a box without a border, those of two sides drawn, none of a radius of 0" $ do
        bg <- declsOf "a" (swatches <> "[paragraph-styles.a]\nbackground = \"pale\"\nborder-radius = \"2mm\"\nborder-sides = [\"start\"]\n")
        radii bg @?= ["border-start-start-radius: 5.6693pt", "border-start-end-radius: 5.6693pt", "border-end-start-radius: 5.6693pt", "border-end-end-radius: 5.6693pt"]
        one <- declsOf "a" (swatches <> "[paragraph-styles.a]\nborder = \"blue\"\nborder-radius = \"2mm\"\nborder-sides = [\"start\"]\n")
        radii one @?= []
        two <- declsOf "a" (swatches <> "[paragraph-styles.a]\nborder = \"blue\"\nborder-radius = \"1zw\"\nborder-sides = [\"before\", \"start\", \"end\"]\n")
        radii two @?= ["border-start-start-radius: 1em", "border-start-end-radius: 1em"]
        zero <- declsOf "a" (swatches <> "[paragraph-styles.a]\nbackground = \"pale\"\nborder-radius = \"0pt\"\n")
        radii zero @?= [],
      testCase "PDF and HTML: a book of two boxed paragraphs and a box of one side builds, the paragraphs of one box in one div" $
        withSystemTempDirectory "golem-boxes" $ \tmp -> do
          let style = horizontalStyle <> fakeBody <> "\n" <> encode swatches <> "[paragraph-styles.column]\nbackground = \"pale\"\nborder-radius = \"1zw\"\n\n[paragraph-styles.title]\nbackground = \"pale\"\nborder-radius = \"1zw\"\n\n[paragraph-styles.caution]\nborder = \"blue\"\nborder-width = \"2pt\"\nborder-sides = [\"start\"]\nindent = \"1zw\"\n"
              source = "前。\n\n@style title\n題。\n\n@style column\n本文。\n\n@style caution\n注意。\n\n後。\n"
          writeProject tmp (miniManifest <> "\n[targets.html]\n") style source fakeFontFiles
          r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf, TargetHtml], optFonts = fakeProvider}
          filter isError (brDiagnostics r) @?= []
          page <- TIO.readFile (tmp </> "build/html/a.xhtml")
          assertBool (T.unpack page) ("<div class=\"box box-title\">\n<p class=\"ps-title\">題。</p>\n<p class=\"ps-column\">本文。</p>\n</div>\n<div class=\"box box-caution\">\n<p class=\"ps-caution\">注意。</p>\n</div>" `T.isInfixOf` page)
    ]
  where
    encode = TE.encodeUtf8
