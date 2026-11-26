{- | The blocks that cannot be shortened, the headings and the paragraphs
beside wrapped figures around the frames of wrap around (root ADR 0456).
-}
module AroundBlocksSpec (aroundBlocksTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import FramesSpec (frameDef, layoutCodes, ptSp, spPt)
import Golem.Layout.KnuthPlass (Line (..))
import Golem.Layout.Paginate (HeadingBlock (..), PageOutAt (..), Slotted (..), TableSegmentAt (..))
import Golem.Layout.Wrap (Exclusion (..), Wrap (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), columnsFor)
import Golem.Length (Sp (..), Unit (..), toSp)
import Golem.Typeset (PdfLayout (..), PlacedFigure (..), SetLine (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

{- | horizontalStyle of @chars@ characters a line (10pt each) with a frame
of wrap around on the master page, from the outside: it covers the last
@n@ characters of the column on the odd pages, the first on the even
ones, the margin beyond them to the fore-edge, from @y0@ to @y1@ pt down
the page. With @free@, the lines are placed without the grid.
-}
aroundAt :: Bool -> Integer -> Integer -> Integer -> Integer -> BS.ByteString
aroundAt free chars n y0 y1 =
  let base = replaceIn "characters = 12" ("characters = " <> T.pack (show chars)) horizontalStyle
      placed = if free then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base
      width = toSp Mm 148 - toSp Mm 20 - ptSp (10 * chars - 10 * n)
      keys = "x = \"0pt\"\ny = \"" <> T.pack (show y0) <> "pt\"\nwidth = \"" <> T.pack (spPt width) <> "\"\nheight = \"" <> T.pack (show (y1 - y0)) <> "pt\"\nwrap = \"around\"\nx-from = \"outside\"\n"
   in figStyle (placed <> frameDef "side" keys <> "\n[masters.body]\nframes = [\"side\"]\n")

-- | The style of 'aroundAt' without the frame on the master page.
withoutFrame :: Bool -> Integer -> BS.ByteString
withoutFrame free chars =
  let base = replaceIn "characters = 12" ("characters = " <> T.pack (show chars)) horizontalStyle
   in figStyle (if free then replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" base else base)

-- | The frame of 'aroundAt' across the lines of a column: from its start edge, the top.
frameAcross :: PageGeometry -> Rect -> Integer -> Integer -> (Sp, Sp)
frameAcross geom col y0 y1 =
  let colTop = rectY col + rectH col
      ph = snd (pgPageSize geom)
   in (colTop - (ph - ptSp y0), colTop - (ph - ptSp y1))

-- | The first column of page 1.
firstColumn :: PageGeometry -> Rect
firstColumn geom = case columnsFor geom 1 of
  col : _ -> col
  [] -> Rect 0 0 0 0

-- | The column of a page of a layout.
columnOf :: PageGeometry -> PageOutAt Sp -> Rect
columnOf geom p = case drop (poColumn p) (columnsFor geom (poNumber p)) of
  col : _ -> col
  [] -> Rect 0 0 0 0

-- | The em box across the lines of a line on the grid at a slot, in the size of the line.
emAcross :: PageGeometry -> Sp -> Sp -> (Sp, Sp)
emAcross geom slot size =
  let base = slot + sum (take 1 (pgLineGrid geom))
      descent = Sp (unSp size * 12 `div` 100)
   in (base + descent - size, base + descent)

-- | Whether a range across the lines crosses another.
crosses :: (Sp, Sp) -> (Sp, Sp) -> Bool
crosses (a, b) (f0, f1) = a < f1 && b > f0

{- | What of the pages of a layout overlaps the frame of 'aroundAt' over
@n@ characters from @y0@ to @y1@ (root ADR 0456 I1): the lines of tables,
the code blocks and the figures whose ranges cross it, and the lines of
paragraphs and headings that cross it across the lines and are not
shortened out of it along them.
-}
overFrame :: PageGeometry -> PdfLayout -> Integer -> Integer -> Integer -> [String]
overFrame geom pl n y0 y1 =
  [ show (poNumber p) <> ": " <> what
  | p <- plPages pl,
    not (poBlank p),
    let col = columnOf geom p
        frame = frameAcross geom col y0 y1
        measure = rectW col
        cut = ptSp (10 * n)
        atEnd = odd (poNumber p)
        pitch = pgLinePitch geom
        face = pgFontSize geom
        -- along the lines, whether a range from the start of the column meets the frame
        alongMeets (a, b) = if atEnd then b > measure - cut else a < cut
        shortened sl = if atEnd then slIndent sl + lineTarget (slLine sl) <= measure - cut else slIndent sl >= cut
        figureAlong pf = case pfWrap pf of
          Just WrapStart -> (0, pfAlong pf)
          Just WrapEnd -> (measure - pfAlong pf, measure)
          Nothing -> (0, measure),
    what <-
      [ "table line " <> show lid
      | (slot, SLine lid) <- poSlots p,
        Map.member lid (plTableLines pl),
        Just sl <- [Map.lookup lid (plLines pl)],
        emAcross geom slot (slSize sl) `crosses` frame
      ]
        <> [ "code " <> show lid
           | (slot, SCode lid _ k) <- poSlots p,
             let top = slot - Sp (unSp (pitch - face) `div` 2),
             (top, top + fromIntegral k * pitch) `crosses` frame
           ]
        <> [ "figure " <> show fid
           | (slot, s) <- poSlots p,
             fid <- case s of SFigure f -> [f]; SWrapped f -> [f]; _ -> [],
             Just pf <- [Map.lookup fid (plFigures pl)],
             (slot, slot + pfAcross pf) `crosses` frame,
             alongMeets (figureAlong pf)
           ]
        <> [ "line " <> T.unpack (setLineText sl)
           | (slot, SLine lid) <- poSlots p,
             Map.notMember lid (plTableLines pl),
             Just sl <- [Map.lookup lid (plLines pl)],
             emAcross geom slot (slSize sl) `crosses` frame,
             not (shortened sl)
           ]
        <> [ "heading line " <> T.unpack (setLineText sl)
           | (slot, SHeading lid count) <- poSlots p,
             Just hb <- [Map.lookup lid (plHeadings pl)],
             j <- [0 .. count - 1],
             let top = slot + hbOffset hb + fromIntegral j * hbPitch hb,
             Just sl <- [Map.lookup (lid + j) (plLines pl)],
             (top, top + slSize sl) `crosses` frame,
             not (shortened sl)
           ]
  ]

-- | A table of a header row and n body rows of short cells.
table :: Int -> T.Text
table rows = "| 列一 | 列二 |\n|---|---|\n" <> T.concat ["| 行 | " <> T.pack (show k) <> " |\n" | k <- [1 .. rows]] <> "\n"

-- | A code block of n rows.
code :: Int -> T.Text
code rows = "```\n" <> T.concat ["row " <> T.pack (show k) <> "\n" | k <- [1 .. rows]] <> "```\n\n"

-- | The slots of the lines of a table on the pages, in order: page, slot and id.
tableSlots :: PdfLayout -> [(Int, Sp, Int)]
tableSlots pl = [(poNumber p, slot, lid) | p <- plPages pl, (slot, SLine lid) <- poSlots p, Map.member lid (plTableLines pl)]

-- | The frame from 150pt to 210pt down the page: the grid lines 6 to 10 of the column.
top0, bottom0 :: Integer
top0 = 150
bottom0 = 210

aroundBlocksTests :: [TestTree]
aroundBlocksTests =
  [ testCase "root ADR 0456 I1, I3: a table at the frame starts at the first grid line whose line misses it" $ do
      (geom, pl) <- layoutOk (aroundAt False 12 4 top0 bottom0) (fillers 6 <> table 4) []
      overFrame geom pl 4 top0 bottom0 @?= []
      case tableSlots pl of
        (1, slot, _) : _ -> do
          let frame = frameAcross geom (firstColumn geom) top0 bottom0
          assertBool "the first line misses the frame" (not (emAcross geom slot (pgFontSize geom) `crosses` frame))
          assertBool "the grid line before crosses it" (emAcross geom (slot - pgLinePitch geom) (pgFontSize geom) `crosses` frame)
        other -> assertFailure (show other),
    testCase "root ADR 0456 I1, I3: a table that reaches the frame from a row goes on past it without its header row again" $ do
      (geom, pl) <- layoutOk (aroundAt False 12 4 top0 bottom0) (fillers 3 <> table 10) []
      overFrame geom pl 4 top0 bottom0 @?= []
      let segments = [(poNumber p, ts) | p <- plPages pl, poNumber p == 1, ts <- poTables p]
      case segments of
        [(_, first), (_, second)] -> do
          assertBool "the header row in the part before" (isJust (tsHeaderEnd first))
          tsHeaderEnd second @?= Nothing
          assertBool "the part after the frame starts after the part before" (tsFirst second > tsLast first)
        other -> assertFailure (show other)
      let headerIds = take 1 [lid | (1, _, lid) <- tableSlots pl]
      length [() | (1, _, lid) <- tableSlots pl, lid `elem` headerIds] @?= 1,
    testCase "root ADR 0456 I1: a table whose header row alone fits before the frame goes past it with the header row" $ do
      (geom, pl) <- layoutOk (aroundAt False 12 4 top0 bottom0) (fillers 4 <> table 3) []
      overFrame geom pl 4 top0 bottom0 @?= []
      let frame = frameAcross geom (firstColumn geom) top0 bottom0
      case tableSlots pl of
        (1, slot, _) : _ -> assertBool "the header row after the frame" (fst (emAcross geom slot (pgFontSize geom)) >= snd frame)
        other -> assertFailure (show other),
    testCase "root ADR 0456 I1, I3: a code block that reaches the frame is broken before it and goes on past it" $ do
      (geom, pl) <- layoutOk (aroundAt False 12 4 top0 bottom0) (fillers 3 <> code 10) []
      overFrame geom pl 4 top0 bottom0 @?= []
      length [() | p <- plPages pl, poNumber p == 1, (_, SCode {}) <- poSlots p] @?= 2,
    testCase "root ADR 0456 I1, I3: a figure at the frame goes past it" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk (aroundAt False 12 4 top0 bottom0) (fillers 6 <> "@figure images/tiny.jpg alt=\"t\" width=4zw\n  図。\n\n" <> fillers 3) img
      overFrame geom pl 4 top0 bottom0 @?= []
      (_, _, gp, slot) <- theFigure pl
      poNumber gp @?= 1
      let frame = frameAcross geom (firstColumn geom) top0 bottom0
          at k = emAcross geom (fromIntegral k * pgLinePitch geom) (pgFontSize geom)
      assertBool "the first grid line after the frame" (not (at slot `crosses` frame) && at (slot - 1) `crosses` frame),
    testCase "root ADR 0456 I1, I3: a wrapped figure on the side of the frame goes past it" $ do
      img <- tinyImage
      (geom, pl) <- layoutOk (aroundAt False 24 4 top0 bottom0) (fillers 6 <> wrapped "end" "6zw" <> longPara 4) img
      overFrame geom pl 4 top0 bottom0 @?= [],
    testCase "root ADR 0456 I1, I2: a wrapped figure on the side away from the frame stays, and its side lines lose both" $ do
      img <- tinyImage
      let source = fillers 5 <> wrapped "start" "6zw" <> longPara 6
      (geom, pl) <- layoutOk (aroundAt False 24 4 top0 bottom0) source img
      (_, plain) <- layoutOk (withoutFrame False 24) source img
      overFrame geom pl 4 top0 bottom0 @?= []
      (_, pf, gp, slot) <- theFigure pl
      (_, _, _, slotPlain) <- theFigure plain
      slot @?= slotPlain
      p <- case [q | q <- plPages pl, poNumber q == poNumber gp, poColumn q == poColumn gp] of
        q : _ -> pure q
        [] -> assertFailure "no page"
      let col = columnOf geom p
          frame = frameAcross geom col top0 bottom0
          measure = rectW col
          width = maybe 0 exWidth (pfExclusion pf)
          exclusionEnd = fromIntegral (slot + maybe 0 exLines (pfExclusion pf)) * pgLinePitch geom
          beside = [(s, sl) | (s, SLine lid) <- poSlots p, s >= fromIntegral slot * pgLinePitch geom, s < exclusionEnd, Just sl <- [Map.lookup lid (plLines pl)]]
          underFrame = [sl | (s, sl) <- beside, emAcross geom s (slSize sl) `crosses` frame]
      assertBool "side lines under the frame" (not (null underFrame))
      forM_ underFrame $ \sl -> do
        assertBool (show (slIndent sl)) (slIndent sl >= width)
        slIndent sl + lineTarget (slLine sl) @?= measure - ptSp 40,
    testCase "root ADR 0456 I1: a heading at the frame has its lines shortened" $ do
      (geom, pl) <- layoutOk (aroundAt False 12 4 top0 bottom0) (fillers 7 <> "## 見出しの文字を長く書く\n\n" <> longPara 3) []
      overFrame geom pl 4 top0 bottom0 @?= []
      assertBool "a heading on page 1" (not (null [() | p <- plPages pl, poNumber p == 1, (_, SHeading {}) <- poSlots p])),
    testCase "root ADR 0456 I3: a table on a page of free placement starts at the end edge of the frame" $ do
      (geom, pl) <- layoutOk (aroundAt True 12 4 top0 bottom0) (fillers 6 <> table 4) []
      case tableSlots pl of
        (1, slot, _) : _ -> slot @?= snd (frameAcross geom (firstColumn geom) top0 bottom0)
        other -> assertFailure (show other),
    testCase "root ADR 0456 I4: without a frame of wrap around, the blocks are where they are with a frame of no wrap" $ do
      img <- tinyImage
      let source = fillers 6 <> table 4 <> code 6 <> "@figure images/tiny.jpg alt=\"t\" width=4zw\n  図。\n\n" <> "## 見出し\n\n" <> longPara 6
          noWrap = replaceIn "wrap = \"around\"\n" "" (aroundAt False 12 4 top0 bottom0)
      (_, with) <- layoutOk noWrap source img
      (_, without) <- layoutOk (withoutFrame False 12) source img
      map poSlots (plPages with) @?= map poSlots (plPages without),
    testCase "root ADR 0456 I5: a table that ends before the frame does not move" $ do
      let source = fillers 1 <> table 2 <> longPara 6
      (_, with) <- layoutOk (aroundAt False 12 4 top0 bottom0) source []
      (_, without) <- layoutOk (withoutFrame False 12) source []
      take 3 (tableSlots with) @?= take 3 (tableSlots without),
    testCase "root ADR 0456 I6: a wrapped figure whose exclusion alone leaves fewer than 8 characters is G07022 alone" $ do
      img <- tinyImage
      r <- layoutMini (aroundAt False 12 4 top0 bottom0) (fillers 5 <> wrapped "start" "5zw" <> longPara 4) img
      layoutCodes r @?= ["G07022"],
    testCase "root ADR 0456 I6: side lines that the frame leaves fewer than 8 characters with the exclusion are G07138 once for their paragraph" $ do
      img <- tinyImage
      r <- layoutMini (aroundAt False 24 8 top0 bottom0) (fillers 5 <> wrapped "start" "8zw" <> longPara 6) img
      layoutCodes r @?= ["G07138"],
    testCase "root ADR 0456 I7: a figure that fits an empty column but no place off the frame is G07142 alone" $ do
      img <- tinyImage
      r <- layoutMini (aroundAt False 12 4 top0 330) (longPara 3 <> "@figure images/tiny.jpg alt=\"t\" width=12zw\n\n" <> longPara 3 <> table 3) img
      layoutCodes r @?= ["G07142"]
  ]
