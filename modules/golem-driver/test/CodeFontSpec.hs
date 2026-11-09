{- | Inline code with Japanese characters, composed with a real Japanese
font (golem-layout ADR 0034): each character its own box, and the boxes
of a run as wide together as the run shaped whole (C7), so that the long
Japanese message of G03029 of the user manual's appendix E fits its lines
without G07105. The fonts are those of the specimens (Noto Serif JP and
Source Sans Pro), not those of the manuals, which the repository does not
hold.
-}
module CodeFontSpec (codeFontTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Data.List (groupBy)
import Golem.Layout.CharClass (CharClass (..))
import Golem.Layout.Japanese (BoxKind (..), boxKind, lookClass)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.Length (Sp (..))
import Golem.Syntax (Diagnostic (..))
import Golem.Typeset (PdfLayout (..), SetLine (..), Shaped (..), shapingOf)
import SpecimenGeometrySpec (jaLatin, layoutAndFontsOf)
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

codeFontTests :: TestTree
codeFontTests =
  testGroup
    "inline code of Japanese characters with a real font (golem-layout ADR 0034)"
    [ testCase "the full message of G03029 of appendix E fits lines of 38 characters without G07105, broken between its Japanese characters" $
        withBook $ \dir -> do
          r <- build (defaultOptions dir) {optTargets = Just [TargetPdf], optFonts = realProvider}
          [(diagCode d, diagMessage d) | d <- brDiagnostics r] @?= []
          (_, pl, _) <- layoutAndFontsOf dir
          let texts = [T.concat [bcText c | Box _ c <- lineItems (slLine sl)] | sl <- Map.elems (plLines pl)]
          assertBool (show texts) (length texts > 1)
          T.concat texts @?= T.filter (/= ' ') g03029,
      testCase "C7: the boxes of a run of Japanese characters of code add up to the advance of the run shaped whole, to a rounding of 1 sp a box" $
        withBook $ \dir -> do
          (_, pl, fonts) <- layoutAndFontsOf dir
          let boxes = [(w, c) | sl <- Map.elems (plLines pl), Box w c <- lineItems (slLine sl)]
              japanese (_, c) = lkCode (bcLook c) && boxKind c == KindText && maybe False ((/= Western) . lookClass (bcLook c) . fst) (T.uncons (bcText c))
              -- the runs of Japanese boxes of code that follow one another in the text, across the lines
              runs = filter (all japanese) (groupBy (\a b -> japanese a == japanese b) boxes)
              -- the widths of the boxes without the padding of the code at its first and last box (golem-driver ADR 0029)
              widthOf run = sum [unSp w - unSp (bcPadStart c) - unSp (bcPadEnd c) | (w, c) <- run]
              whole run = case run of
                (_, c) : _ ->
                  let look = bcLook c
                      txt = T.concat [bcText d | (_, d) <- run]
                   in floor (toRational (unSp (lkSize look)) * sum [shAdvance g | g <- lfShape fonts (shapingOf False look (T.head txt)) txt]) :: Integer
                [] -> 0
          assertBool "runs of Japanese code" (any ((> 1) . length) runs)
          forM_ runs $ \run ->
            assertBool (T.unpack (T.concat [bcText c | (_, c) <- run]) <> ": " <> show (widthOf run, whole run)) (abs (widthOf run - whole run) <= toInteger (length run))
    ]

-- | The full message of G03029 of the user manual's appendix E, the values written as ….
g03029 :: T.Text
g03029 = "[hidden-folio] の gutter（…）が size（…）の半分（…）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（gutter を … 以上にするか、size を … 以下にします）"

-- | A horizontal book of 38 characters a line, 13Q, its body and code in the fonts of the specimens, one paragraph of the message as code.
withBook :: (FilePath -> IO a) -> IO a
withBook act = withSystemTempDirectory "golem-code-font" $ \tmp -> do
  BS.writeFile (tmp </> "manifest.toml") miniManifest
  BS.writeFile
    (tmp </> "style.toml")
    ( "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 38\nlines = 30\nline-pitch = \"22H\"\ncolumns = 1\nposition = { top = \"18mm\", gutter = \"15mm\" }\n"
        <> "\n[fonts.body]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n"
        <> "\n[fonts.code]\nja = \"fonts/ja.otf\"\nlatin = \"fonts/latin.otf\"\n"
    )
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 ("[code: " <> T.replace "[" "\\[" (T.replace "]" "\\]" g03029) <> "]\n"))
  createDirectoryIfMissing True (tmp </> "fonts")
  forM_ jaLatin $ \(to, from) -> copyFile from (tmp </> "fonts" </> to)
  act tmp
