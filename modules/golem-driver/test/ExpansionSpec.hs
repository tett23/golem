{- | The horizontal scaling of the expanded lines does not outlive them
in the PDF (golem-pdf ADR 0015). A small horizontal book with
@expansion@ is built with real fonts; its content streams are read with
'glyphsOf' (q and Q save and restore the scaling), and each glyph must
be drawn with the scaling of its own text object: that of its Tz, or
100 for a text object without one (I1 of the ADR). The glyphs the ADR
names, the line-end hyphen, the Japanese characters, the last line of
the paragraph and the folio, are found after a scaled line on the same
page, so that the check sees each of them.
-}
module ExpansionSpec (expansionTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isAscii, isLetter)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), placeLine)
import Golem.Layout.Look (Look (..))
import Golem.Typeset (LoadedFonts (..), PdfLayout (..), SetLine (..), Shaped (..), Shaping (..))
import SpecimenGeometrySpec (jaLatin, layoutAndFontsOf)
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import TateChuYokoSpec (Glyph (..), fontEncodings, glyphsOf, pdfOf)
import Test.Tasty hiding (after)
import Test.Tasty.HUnit

expansionTests :: TestTree
expansionTests =
  testGroup
    "the horizontal scaling of expanded lines in the PDF (golem-pdf ADR 0015)"
    [ testCase "I1: the glyphs after an expanded line (the last line, a line-end hyphen, Japanese, the folio) are drawn with 100" $
        withBook $ \dir -> do
          (_, pl, fonts) <- layoutAndFontsOf dir
          pdf <- pdfOf dir
          encodings <- fontEncodings pdf
          contents <- pageContents pdf
          look <- case [bcLook c | sl <- Map.elems (plLines pl), (Box _ c, _) <- placeLine (slLine sl), not (T.null (bcText c)), T.all (\ch -> isAscii ch && isLetter ch) (bcText c)] of
            l : _ -> pure l
            [] -> assertFailure "no Latin box"
          let glyphCodes ch = [lfCode fonts (shFace g) (shGlyph g) | g <- lfShape fonts (Shaping (lkFace look) False [] False) (T.singleton ch)]
              pages = [(gs, ownScales c) | c <- contents, let gs = glyphsOf encodings c]
          assertBool "a page" (not (null pages))
          forM_ (zip [1 :: Int ..] pages) $ \(n, (gs, own)) -> do
            length own @?= length gs
            -- I1: the scaling in force is that of the glyph's own text object
            let wrong = [(gCode g, gY g, gScale g, o) | (g, o) <- zip gs own, gScale g /= o]
            assertBool ("page " <> show n <> ": glyphs drawn with another scaling: " <> show (take 10 wrong)) (null wrong)
          -- the glyphs the ADR names are there, after an expanded line on its page
          let after = concat [dropWhile ((== 1000) . snd) (zip gs own) | (gs, own) <- pages]
              scaledYs = [gY g | (g, o) <- after, o /= 1000]
              unscaled = [g | (g, o) <- after, o == 1000]
              lowest = minimum (map gY unscaled)
          assertBool "an expanded line" (not (null scaledYs))
          assertBool "the line-end hyphen of an expanded line" (any (\g -> gCode g `elem` glyphCodes '-' && gY g `elem` scaledYs) unscaled)
          assertBool "Japanese" (any (\g -> gCode g `elem` glyphCodes '和') unscaled)
          assertBool "the folio" (any (\g -> gCode g `elem` glyphCodes '1' && gY g == lowest) unscaled)
          assertBool "the last line" (any (\g -> gY g < minimum scaledYs && gY g > lowest) unscaled)
    ]

{- | The scaling of each glyph's own text object, in the order of
'glyphsOf': that of its Tz, or 100 (1000 permille) without one.
-}
ownScales :: BS.ByteString -> [Rational]
ownScales = go 1000 Nothing . BC.words
  where
    go _ _ [] = []
    go own prev (w : ws) = case w of
      "BT" -> go 1000 Nothing ws
      "Tz" | Just z <- prev -> go (ptToRational z * 10) Nothing ws
      "Tm" -> case ws of
        (_ : "Tj" : rest) -> own : go own Nothing rest
        _ -> go own Nothing ws
      _ -> go own (Just w) ws

-- | A horizontal book of narrow lines with expansion, a folio, a hyphenated paragraph with Japanese.
withBook :: (FilePath -> IO a) -> IO a
withBook act = withSystemTempDirectory "golem-expansion" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile
    (tmp </> "style.toml")
    ( horizontalStyle
        <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n"
        <> "\n[composition]\nexpansion = { limit = 20, step = 5 }\n"
        <> "\n[masters.body]\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n"
    )
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  createDirectoryIfMissing True (tmp </> "fonts")
  forM_ jaLatin $ \(to, from) -> copyFile from (tmp </> "fonts" </> to)
  act tmp
  where
    source =
      T.unlines
        [ "The typographer considered the extraordinary characteristics of the manuscript, \
          \and the compositor adjusted the justification of every paragraph with 和文 and \
          \with considerable patience before the end."
        ]
