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

-- | A paragraph of so many lines, the separators default and scene, the
-- separator gap of kind blank, a blank line, a page break and a
-- need-lines of two lines.
data Item = P Int | S | T | G | B | E | N
  deriving stock (Eq)

name :: Item -> String
name = \case
  P k -> "P" <> show k
  S -> "S"
  T -> "T"
  G -> "G"
  B -> "B"
  E -> "E"
  N -> "N"

source :: Item -> T.Text
source = \case
  P k -> T.replicate (12 * k) (T.singleton '\12354')
  S -> "---"
  T -> "@separator scene"
  G -> "@separator gap"
  B -> "@blank-line 1"
  E -> "@page-break"
  N -> "@need-lines 2"

-- | The lines an item takes.
linesOf :: Item -> Int
linesOf = \case
  P k -> k
  S -> 1
  T -> 1
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

slot :: (Int, Slotted) -> String
slot (g, s) = show g <> ":" <> case s of
  SLine i -> "L" <> show i
  other -> show other

-- | The id of the first line of each item and its byte offset in the
-- source, each item followed by an empty line.
starts :: [Item] -> [(Int, Int, Item)]
starts items = zip3 (scanl (+) 0 (map linesOf items)) (scanl (+) 0 [BS.length (TE.encodeUtf8 (source i)) + 2 | i <- items]) items

main :: IO ()
main = forM_ inputs $ \(c, capacity, items) -> do
  putStrLn (show c <> " " <> show capacity <> " [" <> unwords (map name items) <> "]")
  let text = T.concat [source i <> "\n\n" | i <- items]
      pitch = 15 * 65536
  result <- layoutMini (style capacity (combos !! c)) text []
  case result of
    Right (_, layout) ->
      forM_ (plPages layout) $ \p ->
        putStrLn ("  " <> unwords ([show (poNumber p), show (poColumn p), if poBlank p then "blank" else "-"] <> map (\(x, s) -> slot (fromIntegral (unSp x `div` pitch), s)) (poSlots p) <> map unmet (poUnmet p)))
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
