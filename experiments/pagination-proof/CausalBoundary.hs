-- Root ADR 0352: prints the pages, or the diagnostics, golem-typeset's
-- layoutPdf gives for small manuscripts of a wrapped figure followed by
-- paragraphs and stanzas, in the free placement, where causalFreeFlow
-- (Flow.hs) places the paragraphs beside the figure with jobsFrom,
-- paragraphs and the parts of paragraph, the stanzas with stanza,
-- tryVerses and accept, and, with a no-break after a paragraph or a stanza,
-- tries what follows it with probeNext and probeChain.  A stanza is a
-- paragraph of the style poem, which keeps its lines (line-breaks =
-- "keep"), each verse line a unit.  CausalBoundary.lean prints the same for the copies of
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

-- | A paragraph of so many characters, a no-break, or a stanza of verse
-- lines of so many characters each.
data Item = P Int | K | V [Int]

name :: Item -> String
name = \case
  P n -> show n
  K -> "K"
  V ns -> "V" <> intercalate "," (map show ns)

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
    <> stanzas

-- | A stanza of one to four verse lines alone; a stanza of two or three
-- before or after a paragraph, with or without a no-break between them;
-- and two stanzas of two verse lines.
stanzas :: [[Item]]
stanzas =
  [[V ns] | n <- [1, 2, 3], ns <- replicateM n [5, 12, 25]]
    <> [[V ns] | ns <- replicateM 4 [5, 25]]
    <> [ items
       | n <- [2, 3],
         ns <- replicateM n [5, 25],
         size <- [5, 12],
         items <- [[P size, V ns], [V ns, P size], [P size, K, V ns], [V ns, K, P size]]
       ]
    <> [[V as, V bs] | as <- replicateM 2 [5, 25], bs <- replicateM 2 [5, 25]]

-- | The width of the figure in zw, the lines of the column and the
-- items after the figure.
inputs :: [(Int, Int, [Item])]
inputs = [(width, capacity, items) | width <- [2, 3], capacity <- [3, 4, 5, 6], items <- manuscripts]

-- | The characters of the paragraphs and stanzas, a different one for each.
letters :: [Char]
letters = "\12354\12356\12358\12360"

-- | The source of the items, each paragraph of its own character.
sources :: [Char] -> [Item] -> [T.Text]
sources cs = \case
  [] -> []
  K : rest -> "@no-page-break\n\n" : sources cs rest
  P n : rest -> T.replicate n (T.take 1 (T.pack cs)) <> "\n\n" : sources (drop 1 cs) rest
  V ns : rest -> "@style poem\n" <> T.concat [T.replicate n (T.take 1 (T.pack cs)) <> "\n" | n <- ns] <> "\n" : sources (drop 1 cs) rest

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
              <> "\n[paragraph-styles.poem]\nline-breaks = \"keep\"\n"
        figure = "@nonumber\n@figure images/tiny.jpg alt=\"t\" wrap=start width=" <> T.pack (show width) <> "zw\n\n"
        text = figure <> T.concat (sources letters items)
    result <- layoutMini style text [("images/tiny.jpg", image)]
    case result of
      Right (_, layout) ->
        forM_ (plPages layout) $ \p ->
          putStrLn ("  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map slot (poSlots p) <> map unmet (poUnmet p)))
      Left ds -> putStrLn ("  error " <> intercalate " " (sort [let DiagnosticCode t = diagCode d in T.unpack t | d <- ds]))
