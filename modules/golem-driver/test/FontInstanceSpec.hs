{- | The instance of a variable font that a role names, in the PDF (Golem
ADR 0358): the roles are shaped at their coordinates, the PDF embeds each
instance as a font of its own with no variation data, and an instance or an
axis that the font does not have, or a value outside its axis, stops the
PDF (G08110, G08111, G08112).
-}
module FontInstanceSpec (tests) where

import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (nub, sort)
import Golem.Driver
import Golem.Project.Files (diskFiles)
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import Golem.Typeset (Shaped (..), Shaping (..))
import Golem.Typeset.FontProvider (golemFontProvider)
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "the instance of a variable font (Golem ADR 0358)"
    [ testCase "ADR 0358: a role at a named instance shapes wider than the default, and an axis overrides the instance" $ do
        serif <- serifBytes
        withSystemTempDirectory "golem-instance" $ \tmp -> do
          writeFiles tmp [("fonts/serif.ttf", serif)]
          let style = "[fonts.body]\nlatin = \"fonts/serif.ttf\"\n\n[fonts.bold]\nlatin = \"fonts/serif.ttf\"\ninstance = \"Bold\"\n\n[fonts.medium]\nlatin = \"fonts/serif.ttf\"\ninstance = \"Bold\"\naxes = { wght = 500 }\n\n[fonts.black]\nlatin = \"fonts/serif.ttf\"\naxes = { wght = 900 }\n\n[character-styles.b]\nfont = \"bold\"\n\n[character-styles.m]\nfont = \"medium\"\n\n[character-styles.k]\nfont = \"black\"\n"
          st <- either (assertFailure . show) pure (parseStyle (FileId 0) style)
          fonts <- loadFonts golemFontProvider (diskFiles tmp) (FileId 0) st [] >>= either (assertFailure . show) pure
          let width role = sum (map shAdvance (lfShape fonts (Shaping role False [] False) "Hamburgefonstiv"))
              face role = nub (map shFace (lfShape fonts (Shaping role False [] False) "Ham"))
          assertBool "bold is wider than body" (width "bold" > width "body")
          assertBool "black is wider than bold" (width "black" > width "bold")
          assertBool "medium (500) lies between body and bold" (width "body" < width "medium" && width "medium" < width "bold")
          -- four coordinates of one file: four faces
          length (nub (concatMap face ["body", "bold", "medium", "black"])) @?= 4,
      testCase "ADR 0358: the same coordinates by a name and by an axis are one face" $ do
        serif <- serifBytes
        withSystemTempDirectory "golem-instance" $ \tmp -> do
          writeFiles tmp [("fonts/serif.ttf", serif)]
          let style = "[fonts.body]\nlatin = \"fonts/serif.ttf\"\ninstance = \"Bold\"\n\n[fonts.heading]\nlatin = \"fonts/serif.ttf\"\naxes = { wght = 700 }\n\n[character-styles.h]\nfont = \"heading\"\n"
          st <- either (assertFailure . show) pure (parseStyle (FileId 0) style)
          fonts <- loadFonts golemFontProvider (diskFiles tmp) (FileId 0) st [] >>= either (assertFailure . show) pure
          let face role = nub (map shFace (lfShape fonts (Shaping role False [] False) "Ham"))
          face "body" @?= face "heading",
      testCase "ADR 0358: the PDF embeds each instance once, fixed, under its own name" $ do
        serif <- serifBytes
        let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/serif.ttf\"\n\n[fonts.bold]\nlatin = \"fonts/serif.ttf\"\ninstance = \"Bold\"\n\n[character-styles.b]\nfont = \"bold\"\n"
        pdf <- miniPdf realProvider False style "Plain [style b: bold] text.\n" [("fonts/serif.ttf", serif)]
        let names = sort [BC.takeWhile (\c -> c /= '/' && c /= ' ' && c /= '\n') (BS.drop 1 (BC.dropWhile (/= '+') rest)) | rest <- drop 1 (splitOn "/BaseFont /" pdf)]
        length (nub names) @?= 2
        assertBool (show names) ("SourceSerifVariable-Roman" `elem` names)
        programs <- filter isSfnt <$> inflateAll pdf
        assertBool "two programs" (length programs >= 2)
        sequence_ [assertBool (show t) (not (hasTable t p)) | p <- programs, t <- ["fvar", "gvar", "HVAR", "MVAR", "avar"]],
      testCase "ADR 0358: the same book gives the same PDF" $ do
        serif <- serifBytes
        let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/serif.ttf\"\ninstance = \"Semibold\"\naxes = { wght = 612.5 }\n"
        a <- miniPdf realProvider False style "Some text.\n" [("fonts/serif.ttf", serif)]
        b <- miniPdf realProvider True style "Some text.\n" [("fonts/serif.ttf", serif)]
        a @?= b,
      testCase "G08110, G08111, G08112: an unknown instance, an unknown axis and a value outside the axis stop the PDF, in golem build and golem check, but not HTML" $ do
        serif <- serifBytes
        let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/serif.ttf\"\ninstance = \"Heavy\"\naxes = { wdth = 90, wght = 1000 }\n"
            files = [("fonts/serif.ttf", serif)]
            expected =
              [ ("G08110", "可変フォントに名前付きインスタンスがありません: [fonts.body] の instance = \"Heavy\"（fonts/serif.ttf）"),
                ("G08111", "フォントにない軸です: [fonts.body] の axes の wdth（fonts/serif.ttf）"),
                ("G08112", "軸の値がフォントの範囲の外にあります: [fonts.body] の axes の wght = 1000（fonts/serif.ttf の wght は 200 から 900）")
              ]
        b <- buildMarksFilesWith "本文。\n" (\o -> o {optFonts = golemFontProvider}) (Just style) files
        [(c, diagMessage d) | d <- bErrors b, DiagnosticCode c <- [diagCode d]] @?= expected
        map (whereIs b) (bErrors b) @?= replicate 3 (Just "style.toml", 0)
        bPdf b @?= Nothing
        c <- buildMarksFilesWith "本文。\n" (\o -> o {optFonts = golemFontProvider, optCheckOnly = True}) (Just style) files
        codesOf (bErrors c) @?= ["G08110", "G08111", "G08112"]
        h <- buildMarksFilesWith "本文。\n" (\o -> o {optFonts = golemFontProvider, optTargets = Just [TargetHtml]}) (Just style) files
        codesOf (bErrors h) @?= [],
      testCase "G08110, G08111: a font that is not variable has no instance and no axis; each role and face is reported" $ do
        (sans, serif) <- realLatinFonts
        let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/sans.otf\"\ninstance = \"Bold\"\naxes = { wght = 700 }\n\n[fonts.heading]\nja = \"fonts/serif.ttf\"\nlatin = \"fonts/sans.otf\"\naxes = { wght = 700 }\n\n[character-styles.h]\nfont = \"heading\"\n"
        b <- buildMarksFilesWith "本文。[style h: 見出し]\n" (\o -> o {optFonts = golemFontProvider}) (Just style) [("fonts/sans.otf", sans), ("fonts/serif.ttf", serif)]
        [(c, diagMessage d) | d <- bErrors b, DiagnosticCode c <- [diagCode d]]
          @?= [ ("G08110", "可変フォントに名前付きインスタンスがありません: [fonts.body] の instance = \"Bold\"（fonts/sans.otf）"),
                ("G08111", "フォントにない軸です: [fonts.body] の axes の wght（fonts/sans.otf）"),
                ("G08111", "フォントにない軸です: [fonts.heading] の axes の wght（fonts/sans.otf）")
              ],
      testCase "G08112 and G08019 are both reported for a CFF2 font with a value outside its axis" $ do
        cff2 <- BS.readFile "../golem-font/test/fonts/SourceSerif4Variable-Roman.otf"
        let style = horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/v.otf\"\naxes = { wght = 10 }\n"
        b <- buildMarksFilesWith "本文。\n" (\o -> o {optFonts = golemFontProvider}) (Just style) [("fonts/v.otf", cff2)]
        codesOf (bErrors b) @?= ["G08019", "G08112"],
      testCase "ADR 0358: golem preflight reports G08112 too" $ do
        serif <- serifBytes
        withSystemTempDirectory "golem-instance" $ \tmp -> do
          BS.writeFile (tmp </> "manifest.toml") miniManifest
          BS.writeFile (tmp </> "style.toml") (horizontalStyle <> "\n[fonts.body]\nlatin = \"fonts/serif.ttf\"\naxes = { wght = 901 }\n")
          BS.writeFile (tmp </> "a.gm") "Text.\n"
          createDirectoryIfMissing True (tmp </> "fonts")
          BS.writeFile (tmp </> "fonts/serif.ttf") serif
          p <- preflight (defaultPreflightOptions tmp)
          assertBool (show (map diagCode (prDiagnostics p))) (DiagnosticCode "G08112" `elem` map diagCode (prDiagnostics p))
    ]
  where
    serifBytes = BS.readFile "test/fixtures/tempest/fonts/SourceSerifVariable-Roman.ttf"
    splitOn sep s = case BS.breakSubstring sep s of
      (a, rest) | BS.null rest -> [a]
      (a, rest) -> a : splitOn sep (BS.drop (BS.length sep) rest)
    isSfnt p = BS.take 4 p `elem` ["\0\1\0\0", "true"]

-- | Whether an sfnt font has a table.
hasTable :: BS.ByteString -> BS.ByteString -> Bool
hasTable tag font = tag `elem` [BS.take 4 (BS.drop (12 + 16 * i) font) | i <- [0 .. numTables - 1]]
  where
    numTables = fromIntegral (BS.index font 4) * 256 + fromIntegral (BS.index font 5) :: Int
