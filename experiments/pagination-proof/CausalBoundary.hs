-- Root ADR 0352: prints the pages, or the diagnostics, golem-typeset's
-- layoutPdf gives for small manuscripts of a wrapped figure followed by
-- paragraphs, in the free placement, where causalFreeFlow (Flow.hs) places
-- the paragraphs beside the figure with jobsFrom, paragraphs and the parts
-- of paragraph, and, with a no-break after a paragraph, tries what follows
-- it with probeNext and probeChain.  CausalBoundary.lean prints the same for the copies of
-- those loops in Physical.lean; check.sh compares the two with diff.  The
-- manuscripts are laid out with the fake fonts of the golem-driver tests
-- (modules/golem-driver/test/Support.hs): a character is 1zw (10pt), a
-- line of the column holds 12, and the tiny image of 2 by 3 pixels is
-- wrapped at the start of the lines.
module Main (main) where

import Control.Monad (forM_, replicateM)
import Data.ByteString qualified as BS
import Data.List (intercalate, sort)
import Data.Text qualified as T
import Golem.Layout.Paginate (PageOutAt (..), Part (..), Slotted (..), Unmet (..))
import Golem.Length (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.Typeset (PdfLayout (..))
import Support (horizontalStyle, layoutMini, replaceIn)

-- | A paragraph of so many characters, or a no-break.
data Item = P Int | K

name :: Item -> String
name = \case
  P n -> show n
  K -> "K"

-- | One to three paragraphs; then two or three paragraphs with a no-break
-- after one of them or more.
manuscripts :: [[Item]]
manuscripts =
  [map P ns | n <- [1, 2, 3], ns <- replicateM n [5, 12, 25]]
    <> [ concat (zipWith (\held size -> [K | held] <> [P size]) (False : holds) ns)
       | n <- [2, 3],
         ns <- replicateM n [5, 12, 25],
         holds <- replicateM (n - 1) [False, True],
         or holds
       ]

-- | The width of the figure in zw, the lines of the column and the
-- items after the figure.
inputs :: [(Int, Int, [Item])]
inputs = [(width, capacity, items) | width <- [2, 3], capacity <- [3, 4, 5, 6], items <- manuscripts]

-- | The characters of the paragraphs, a different one for each.
letters :: [Char]
letters = "\12354\12356\12358"

-- | The source of the items, each paragraph of its own character.
sources :: [Char] -> [Item] -> [T.Text]
sources cs = \case
  [] -> []
  K : rest -> "@no-page-break\n\n" : sources cs rest
  P n : rest -> T.replicate n (T.take 1 (T.pack cs)) <> "\n\n" : sources (drop 1 cs) rest

slot :: (Sp, Slotted) -> String
slot (x, s) = show (unSp x) <> ":" <> case s of
  SLine i -> "L" <> show i
  other -> show other

unmet :: Unmet -> String
unmet = \case
  UnmetNoBreak _ -> "!nobreak"
  UnmetKeepNext _ -> "!keepnext"
  UnmetNeedLines _ n -> "!need" <> show n
  ShortPart FirstPart i w g -> "!first" <> show i <> ":" <> show w <> ":" <> show g
  ShortPart LastPart i w g -> "!last" <> show i <> ":" <> show w <> ":" <> show g
  other -> "!" <> show other

main :: IO ()
main = do
  image <- BS.readFile "modules/golem-pdf/test/fixtures/tiny.jpg"
  forM_ inputs $ \(width, capacity, items) -> do
    putStrLn (show width <> " " <> show capacity <> " [" <> unwords (map name items) <> "]")
    let style =
          replaceIn "lines = 30" (T.pack ("lines = " <> show capacity)) $
            replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" horizontalStyle
        figure = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=" <> T.pack (show width) <> "zw\n\n"
        text = figure <> T.concat (sources letters items)
    result <- layoutMini style text [("images/tiny.jpg", image)]
    case result of
      Right (_, layout) ->
        forM_ (plPages layout) $ \p ->
          putStrLn ("  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map slot (poSlots p) <> map unmet (poUnmet p)))
      Left ds -> putStrLn ("  error " <> intercalate " " (sort [let DiagnosticCode t = diagCode d in T.unpack t | d <- ds]))
