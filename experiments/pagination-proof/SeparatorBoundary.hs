-- Root ADR 0352: prints the pages, or the diagnostics, golem-typeset's
-- layoutPdf gives for small manuscripts with the separators of root ADR
-- 0398, in the format SeparatorBoundary.lean prints for Separator.lean's
-- flows on Whole.lean's paginate.  check.sh compares the two outputs
-- with diff.  The manuscripts are laid out with the fake fonts of the
-- golem-driver tests (modules/golem-driver/test/Support.hs): a line of
-- the grid holds 12 characters, so a paragraph of 12 k characters takes
-- k lines.
module Main (main) where

import Control.Monad (forM_, replicateM)
import Data.ByteString qualified as BS
import Data.List (intercalate, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..), Unmet (..), Part (..))
import Golem.Length (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), SrcSpan (..))
import Golem.Typeset (PdfLayout (..))
import Support (horizontalStyle, layoutMini, replaceIn)
import System.Environment (getArgs)

-- | A paragraph of so many lines (U uses keeps of one line), the separators default and scene, the
-- separator gap of kind blank, a blank line, a page break, a need-lines
-- of two lines, and, in the manuscripts with blocks, a paragraph of one
-- line in a box, a paragraph of one line with rules before and after,
-- and an item of a list of one line, a book part (markBookParts); in
-- the manuscripts of the holds, a no-break; in the manuscripts with code,
-- a code block of so many rows.
data Item = P Int | U Int | S | T | G | B | E | N | X | R | L | K | C Int
  deriving stock (Eq)

name :: Item -> String
name = \case
  P k -> "P" <> show k
  U k -> "U" <> show k
  S -> "S"
  T -> "T"
  G -> "G"
  B -> "B"
  E -> "E"
  N -> "N"
  X -> "X"
  R -> "R"
  L -> "L"
  K -> "K"
  C k -> "C" <> show k

source :: Item -> T.Text
source = \case
  P k -> T.replicate (12 * k) (T.singleton '\12354')
  U k -> "@style loose\n" <> T.replicate (12 * k) (T.singleton '\12354')
  S -> "---"
  T -> "@separator scene"
  G -> "@separator gap"
  B -> "@blank-line 1"
  E -> "@page-break"
  N -> "@need-lines 2"
  -- the padding of 1zw on both sides leaves 10 characters a line
  X -> "@style boxed\n" <> T.replicate 10 (T.singleton '\12356')
  R -> "@style ruled\n" <> T.replicate 12 (T.singleton '\12358')
  L -> "- " <> T.replicate 10 (T.singleton '\12360')
  K -> "@no-page-break"
  C k -> "```\n" <> T.intercalate "\n" (replicate k "a") <> "\n```"

-- | The lines an item takes.
linesOf :: Item -> Int
linesOf = \case
  P k -> k
  U k -> k
  S -> 1
  T -> 1
  X -> 1
  R -> 1
  L -> 1
  C k -> k
  _ -> 0

-- | The grid lines before and after the separators default and scene.
combos :: [((Int, Int), (Int, Int))]
combos = [((0, 0), (1, 2)), ((1, 1), (2, 0))]

style :: Int -> ((Int, Int), (Int, Int)) -> BS.ByteString
style capacity ((db, da), (sb, sa)) =
  replaceIn "lines = 30" (T.pack ("lines = " <> show capacity)) horizontalStyle
    <> TE.encodeUtf8
      ( T.pack
          ( "\n[separators.default]\nkind = \"text\"\ntext = \"*\"\nspace-before = " <> show db <> "\nspace-after = " <> show da
              <> "\n[separators.scene]\nkind = \"text\"\ntext = \"**\"\nspace-before = " <> show sb <> "\nspace-after = " <> show sa
              <> "\n[separators.gap]\nkind = \"blank\"\nlines = 1\n"
          )
      )

-- | One or two leading items, one to three items with a visible
-- separator, then no paragraph or a last paragraph of one or two lines.
manuscripts :: [[Item]]
manuscripts =
  [ lead <> middle <> lastItem
  | lead <- [[], [P 1]],
    n <- [1, 2, 3],
    middle <- replicateM n [S, T, G, B, E, N, P 1],
    any (`elem` [S, T]) middle,
    lastItem <- [[], [P 1], [P 2]]
  ]

inputs :: [(Int, Int, [Item])]
inputs = [(c, capacity, items) | c <- [0 .. length combos - 1], capacity <- [1, 2, 3], items <- manuscripts]

-- | A visible separator, a blank line or a second separator, a paragraph
-- of one to three lines and a no-break, then what the no-break keeps the
-- paragraph with: a paragraph, or a paragraph with a no-break and a
-- paragraph after it (root ADR 0398 I7: the hold goes with what a
-- no-break after the whole next block keeps).
holdManuscripts :: [[Item]]
holdManuscripts =
  [ lead <> [s] <> pre <> [P a, K] <> after
  | lead <- [[], [P 1]],
    s <- [S, T],
    pre <- [[], [S], [B]],
    a <- [1, 2, 3],
    after <- [[P 1], [P 2], [P 3], [P 1, K, P 1], [P 2, K, P 2]]
  ]

holdInputs :: [(Int, Int, [Item])]
holdInputs = [(c, capacity, items) | c <- [0 .. length combos - 1], capacity <- [2, 3, 4, 5], items <- holdManuscripts]

-- | A first part of one line is legal here.  Unlike the default keeps
-- of two lines, these inputs distinguish a separator's keep of one
-- line from an incorrect keep of two lines.
splitInputs :: [(Int, Int, [Item])]
splitInputs =
  [(c, capacity, lead <> [s, U k])
  | c <- [0 .. length combos - 1], capacity <- [1 .. 6],
    lead <- [[], [P 1], [P 2]], s <- [S, T], k <- [2 .. 5]]

splitStyle :: BS.ByteString
splitStyle = "\n[paragraph-styles.loose]\nkeep-first-lines = 1\nkeep-last-lines = 1\n"

-- | The styles of the box, of the rules and of the swatch of the box: a
-- padding of 1zw takes a grid line before and after the box
-- (boxLinesAround), and the rules take one grid line inside the column,
-- one at its start or end, and two when the rule after of one ruled
-- paragraph and the rule before of the next share their area (RuleArea.hs).
blockStyle :: BS.ByteString
blockStyle =
  "\n[color.swatches]\npale = { cmyk = [8, 0, 0, 0] }\n[paragraph-styles.boxed]\nbackground = \"pale\"\npadding = \"1zw\"\n"
    <> "[paragraph-styles.ruled]\nrule-before = { weight = \"1pt\", space-before = \"10pt\", space-after = \"5pt\" }\n"
    <> "rule-after = { weight = \"1pt\", space-before = \"10pt\", space-after = \"5pt\" }\n"

-- | One or two leading items, one to three items with a visible separator,
-- then no paragraph, a paragraph of one line, a box, a ruled paragraph or
-- an item of a list; with a box, a ruled paragraph or an item of a list.
blockManuscripts :: [[Item]]
blockManuscripts =
  [ lead <> middle <> lastItem
  | lead <- [[], [P 1]],
    n <- [1, 2, 3],
    middle <- replicateM n [S, T, X, R, L, N, P 1],
    any (`elem` [S, T]) middle,
    lastItem <- [[], [P 1], [X], [R], [L]],
    any (`elem` [X, R, L]) (middle <> lastItem)
  ]

blockInputs :: [(Int, Int, [Item])]
blockInputs = [(c, capacity, items) | c <- [0 .. length combos - 1], capacity <- [3, 4], items <- blockManuscripts]

-- | One or two leading items, one to three items with a visible
-- separator and a code block of one or three rows, then no paragraph, a
-- paragraph of one line or a code block.  golem-typeset numbers the rows
-- of a code block by the counter of the lines (numberCode, Flow.hs:3866).
codeManuscripts :: [[Item]]
codeManuscripts =
  [ lead <> middle <> lastItem
  | lead <- [[], [P 1]],
    n <- [1, 2, 3],
    middle <- replicateM n [S, T, C 1, C 3, P 1],
    any (`elem` [S, T]) middle,
    lastItem <- [[], [P 1], [C 1], [C 3]],
    any isCode (middle <> lastItem)
  ]
  where
    isCode = \case
      C _ -> True
      _ -> False

codeInputs :: [(Int, Int, [Item])]
codeInputs = [(c, capacity, items) | c <- [0 .. length combos - 1], capacity <- [3, 4], items <- codeManuscripts]

-- | A slot; the slot of a part of a code block by the ids of its rows,
-- and, in the free placement, its grid lines.
slot :: Bool -> (Int, Slotted) -> String
slot free (g, s) = show g <> ":" <> case s of
  SLine i -> "L" <> show i
  SCode first count grid -> "SCode " <> intercalate "," (map show [first .. first + count - 1]) <> (if free then " " <> show grid else "")
  other -> show other

-- | The id of the first line of each item and its byte offset in the
-- source, each item followed by an empty line.
starts :: [Item] -> [(Int, Int, Item)]
starts items = zip3 (scanl (+) 0 (map linesOf items)) (scanl (+) 0 [BS.length (TE.encodeUtf8 (source i)) + 2 | i <- items]) items

-- | With the argument @free@, the page grid alignment is free
-- (@alignment = "free"@), and golem-typeset paginates with
-- paginatePhysical; the slots are then printed at their offsets in sp.
-- With @blocks@ first, the manuscripts with blocks are laid out, with
-- @holds@ first, those of the holds, with @code@ first, those with code
-- blocks.
main :: IO ()
main = do
  args <- getArgs
  let (set, extra) = case args of
        "blocks" : _ -> (blockInputs, blockStyle)
        "holds" : _ -> (holdInputs, "")
        "code" : _ -> (codeInputs, "")
        "split" : _ -> (splitInputs, splitStyle)
        _ -> (inputs, "")
  forM_ set (run (drop 1 args == ["free"] || args == ["free"]) extra)

run :: Bool -> BS.ByteString -> (Int, Int, [Item]) -> IO ()
run free extra (c, capacity, items) = do
  putStrLn (show c <> " " <> show capacity <> " [" <> unwords (map name items) <> "]")
  let text = T.concat [source i <> "\n\n" | i <- items]
      pitch = 15 * 65536
  let aligned = if free then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" else id
  result <- layoutMini (aligned (style capacity (combos !! c) <> extra)) text []
  case result of
    Right (_, layout) ->
      forM_ (plPages layout) $ \p ->
        putStrLn ("  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map (\(x, s) -> slot free (fromIntegral (if free then unSp x else unSp x `div` pitch), s)) (poSlots p) <> map unmet (poUnmet p)))
    Left ds ->
      let at d = case [(ident, item) | (ident, offset, item) <- starts items, offset == spanStart (diagSpan d)] of
            [(ident, item)] | item `elem` [S, T] -> show ident
            _ -> "@" <> show (spanStart (diagSpan d))
          code d = let DiagnosticCode t = diagCode d in T.unpack t
       in putStrLn ("  error " <> intercalate " " (sort [code d <> ":" <> at d | d <- ds]))
  where
    unmet = \case
      UnmetNeedLines _ n -> "!need" <> show n
      UnmetNoBreak _ -> "!nobreak"
      UnmetKeepNext _ -> "!keepnext"
      DroppedBlank _ -> "!dropped"
      ShortPart FirstPart i w g -> "!first" <> show i <> ":" <> show w <> ":" <> show g
      ShortPart LastPart i w g -> "!last" <> show i <> ":" <> show w <> ":" <> show g
      other -> "!" <> show other
