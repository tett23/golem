-- Root ADR 0352: prints the pages, or the diagnostics, golem-typeset's
-- layoutPdf gives for small manuscripts of a wrapped figure followed by
-- paragraphs and stanzas, in the free placement, where causalFreeFlow
-- (Flow.hs) places the paragraphs beside the figure with jobsFrom,
-- paragraphs and the parts of paragraph, the stanzas with stanza,
-- tryVerses and accept, and, with a no-break after a paragraph or a stanza,
-- tries what follows it with probeNext and probeChain.  A stanza is a
-- paragraph of the style poem, which keeps its lines (line-breaks =
-- "keep"), each verse line a unit; a stanza of the style poemk and a
-- paragraph of the style held keep with the next 3 lines (keep-with-next =
-- 3), which keepPhysicalNext waits for.  With keep-parts = "page", wrapped
-- figures in list items go through itemJobs and retainPhysicalPart.
-- CausalBoundary.lean prints the same for the copies of
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
import Golem.Project.Style (KeepParts (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.Typeset (PdfLayout (..))
import Support (horizontalStyle, layoutMini, replaceIn)

-- | A paragraph of so many characters, a no-break, a stanza of verse
-- lines of so many characters each, or a list item of a paragraph of so
-- many characters followed by wrapped figures, each with the paragraphs of
-- the item after it.  Q and H are the paragraph and the stanza that keep
-- with the next 3 lines.
data Item = P Int | K | V [Int] | I Int [[Int]] | Q Int | H [Int]

name :: Item -> String
name = \case
  P n -> show n
  K -> "K"
  V ns -> "V" <> intercalate "," (map show ns)
  Q n -> "Q" <> show n
  H ns -> "H" <> intercalate "," (map show ns)
  I n fs -> "I" <> show n <> concat ["/" <> intercalate "," (map show ps) | ps <- fs]

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
    <> holding

-- | A stanza or a paragraph that keeps with the next 3 lines, before a
-- stanza of four verse lines, some of which tryVerses may not try, or
-- before a paragraph.
holding :: [[Item]]
holding =
  [[held, V bs] | held <- heads, bs <- replicateM 4 [5, 25]]
    <> [[held, P n] | held <- heads, n <- [5, 12, 25]]
  where
    heads = [H as | as <- replicateM 2 [5, 25]] <> [Q n | n <- [5, 12]]

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

-- | The list items, kept on a page: an item with a figure and one or two
-- paragraphs after it, an item with two figures, two items, and an item
-- after or before a paragraph.
lists :: [[Item]]
lists =
  [[I a [ps]] | a <- [3, 15], n <- [1, 2], ps <- replicateM n [5, 12, 25]]
    <> [[I 3 (map pure pq)] | pq <- replicateM 2 [5, 25]]
    <> [[I 3 [[p]] | p <- pq] | pq <- replicateM 2 [5, 25]]
    <> [items | n <- [5, 25], p <- [5, 12, 25], items <- [[P n, I 3 [[p]]], [I 3 [[p]], P n]]]

-- | The width of the figure in zw, the lines of the column, whether a list
-- item is kept on a page, and the items, after a wrapped figure when not.
inputs :: [(Int, Int, Bool, [Item])]
inputs =
  [(width, capacity, False, items) | width <- [2, 3], capacity <- [3, 4, 5, 6], items <- manuscripts]
    <> [(width, capacity, True, items) | width <- [2, 3], capacity <- [3, 4, 5, 6], items <- lists]

-- | The wrapped figure of `width` zw, indented by `indent`.
figureOf :: Int -> T.Text -> T.Text
figureOf width indent = indent <> "@nonumber\n" <> indent <> "@figure images/tiny.jpg alt=\"t\" wrap=start width=" <> T.pack (show width) <> "zw\n\n"

-- | The characters of the paragraphs and stanzas, a different one for each.
letters :: [Char]
letters = "\12354\12356\12358\12360\12362\12363\12365\12367\12369\12371\12373\12375"

-- | The source of the items, each paragraph of its own character; `width`
-- is that of the figures of the list items.
sources :: Int -> [Char] -> [Item] -> [T.Text]
sources width cs = \case
  [] -> []
  K : rest -> "@no-page-break\n\n" : sources width cs rest
  P n : rest -> T.replicate n (T.take 1 (T.pack cs)) <> "\n\n" : sources width (drop 1 cs) rest
  V ns : rest -> "@style poem\n" <> T.concat [T.replicate n (T.take 1 (T.pack cs)) <> "\n" | n <- ns] <> "\n" : sources width (drop 1 cs) rest
  H ns : rest -> "@style poemk\n" <> T.concat [T.replicate n (T.take 1 (T.pack cs)) <> "\n" | n <- ns] <> "\n" : sources width (drop 1 cs) rest
  Q n : rest -> "@style held\n" <> T.replicate n (T.take 1 (T.pack cs)) <> "\n\n" : sources width (drop 1 cs) rest
  I n fs : rest ->
    let letter k = T.take 1 (T.drop k (T.pack cs))
        paragraphs = scanl (+) 1 (map length fs)
     in "- " <> T.replicate n (letter 0) <> "\n\n"
          <> T.concat [figureOf width "  " <> T.concat ["  " <> T.replicate p (letter k) <> "\n\n" | (k, p) <- zip [start ..] ps] | (start, ps) <- zip paragraphs fs]
          : sources width (drop (1 + sum (map length fs)) cs) rest

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
  SplitBookPart _ _ KeepPage -> "!splitpage"
  other -> "!" <> show other

main :: IO ()
main = do
  image <- BS.readFile "modules/golem-pdf/test/fixtures/tiny.jpg"
  forM_ inputs $ \(width, capacity, retaining, items) -> do
    putStrLn (show width <> " " <> show capacity <> (if retaining then " page" else "") <> " [" <> unwords (map name items) <> "]")
    let style =
          replaceIn "lines = 30" (T.pack ("lines = " <> show capacity)) $
            replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" horizontalStyle
              <> "\n[paragraph-styles.poem]\nline-breaks = \"keep\"\n"
              <> "\n[paragraph-styles.poemk]\nline-breaks = \"keep\"\nkeep-with-next = 3\n"
              <> "\n[paragraph-styles.held]\nkeep-with-next = 3\n"
              <> (if retaining then "\n[composition]\nkeep-parts = \"page\"\n" else "")
        text = (if retaining then "" else figureOf width "") <> T.concat (sources width letters items)
    result <- layoutMini style text [("images/tiny.jpg", image)]
    case result of
      Right (_, layout) ->
        forM_ (plPages layout) $ \p ->
          putStrLn ("  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map slot (poSlots p) <> map unmet (poUnmet p)))
      Left ds -> putStrLn ("  error " <> intercalate " " (sort [let DiagnosticCode t = diagCode d in T.unpack t | d <- ds]))
