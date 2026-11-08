{- | The geometric properties of what the roadmap checked by eye, read from
the composed result of the specimens and the current inputs of the visual
regression test (docs/adr/0233). Each property is a function that returns
its violations; each test sees it hold on the inputs, and fail on an input
that breaks it, so that a property that cannot fail checks nothing (the
test design of docs/adr/0233).
-}
module SpecimenGeometrySpec (specimenGeometryTests) where

import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (PageOut (..), Slotted (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), columnsFor, pageGeometry, typeAreaFor)
import Golem.Length (Sp (..))
import Golem.Preflight.View (ImageView (..), LineView (..), PageView (..), RuleView (..), View (..))
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax (FileId (..), Profile (..), isError)
import Golem.Typeset (PdfInput (..), PdfLayout (..), SetLine (..), layoutPdf)
import Support
import System.Directory (copyFile, createDirectoryIfMissing)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

specimenGeometryTests :: TestTree
specimenGeometryTests =
  testGroup
    "the geometry of the specimens of the visual checks (docs/adr/0233)"
    [ testCase "I3: a rule of a table crosses no line of its cells (golem-driver ADR 0031)" $ do
        forM_ [elementsOfStyle, complexVertical] $ \input -> withInput input $ \dir -> do
          v <- viewOf dir
          assertNone (inputName input) (tableRulesCrossCells v)
        -- broken: no leading, so that the space c between the ink and a rule is 0
        v <- miniView (replaceIn "line-pitch = \"15pt\"" "line-pitch = \"10pt\"" horizontalStyle) ("前。\n\n" <> smallTable <> "\n後。\n")
        assertSome "a table without leading" (tableRulesCrossCells v),
      testCase "I3: no two rules of a table at the same place, empty header rows too (golem-driver ADR 0031)" $ do
        withInput elementsOfStyle $ \dir -> do
          v <- viewOf dir
          assertBool "The Elements of Style has tables with an empty header row" (any (not . null . rulesOfKind "表の罫線") (vwPages v))
          assertNone "The Elements of Style" (doubleTableRules v)
        -- broken: the rules of each page drawn twice
        v <- miniView horizontalStyle ("前。\n\n| | |\n|---|---|\n| 行 | 1 |\n\n後。\n")
        assertNone "an empty header row" (doubleTableRules v)
        assertSome "the rules drawn twice" (doubleTableRules (mapPages (\p -> p {pvRules = pvRules p <> pvRules p}) v)),
      testCase "I3: a table is two pitches or more from the lines of text before and after it (golem-driver ADR 0031)" $ do
        forM_ [elementsOfStyle, complexVertical] $ \input -> withInput input $ \dir -> do
          (geom, v) <- (,) <$> geometryOf dir <*> viewOf dir
          assertNone (inputName input) (tableSpaces geom v)
        -- broken: the lines of the tables moved a pitch towards the line before them
        (geom, v) <- miniGeometryView horizontalStyle ("前。\n\n" <> smallTable <> "\n後。\n")
        assertNone "a small table" (tableSpaces geom v)
        let towards p l = if lvKind l == "表の行" then l {lvRect = (lvRect l) {rectY = rectY (lvRect l) + p}} else l
        assertSome "the table a pitch nearer" (tableSpaces geom (mapPages (\pg -> pg {pvLines = map (towards (pgLinePitch geom)) (pvLines pg)}) v)),
      testCase "I3: a paragraph rule is between the grid lines and inside the type area (golem-driver ADR 0027)" $ do
        forM_ [specimensHorizontal, specimensVertical] $ \input -> withInput input $ \dir -> do
          (geom, v) <- (,) <$> geometryOf dir <*> viewOf dir
          assertBool (inputName input <> " has paragraph rules") (any (not . null . rulesOfKind "段落の罫線") (vwPages v))
          assertNone (inputName input) (paragraphRulesOffGrid geom v)
        -- broken: a rule that starts a character before the column, into the margin
        let ruled indent = horizontalStyle <> "\n[paragraph-styles.sec]\nrule-before = { weight = \"0.5pt\", space-before = \"2pt\", space-after = \"2pt\"" <> indent <> " }\n"
            source = "前。\n\n@style sec\n  節。\n"
        (geom, v) <- miniGeometryView (ruled "") source
        assertNone "a paragraph rule" (paragraphRulesOffGrid geom v)
        (geom', v') <- miniGeometryView (ruled ", start-indent = \"-1zw\"") source
        assertSome "a rule a character out of the column" (paragraphRulesOffGrid geom' v'),
      testCase "I3: a footnote is at the foot of the column of its mark, as wide as the column (docs/adr/0018)" $ do
        forM_ [specimensHorizontal, specimensVertical] $ \input -> withInput input $ \dir -> do
          (geom, pl) <- layoutOf dir
          v <- viewOf dir
          assertBool (inputName input <> " has footnotes in its second columns") (any (\p -> poColumn p == 1 && not (null (poFootnotes p))) (plPages pl))
          assertNone (inputName input) (notesAwayFromMarks pl)
          assertNone (inputName input) (noteLinesOutOfColumns geom pl v)
          -- broken: the footnotes of each first column set in the column after it
          let moved = pl {plPages = shiftNotes (plPages pl)}
          assertSome (inputName input <> ", the notes moved a column") (notesAwayFromMarks moved),
      testCase "I3: a figure fitted to the column is inside the type area, and a turned figure turns with its caption (golem-driver ADR 0034)" $ do
        forM_ [specimensHorizontal, specimensVertical] $ \input -> withInput input $ \dir -> do
          (geom, v) <- (,) <$> geometryOf dir <*> viewOf dir
          assertBool (inputName input <> " has a turned figure") (any (any ivTurned . pvImages) (vwPages v))
          assertNone (inputName input) (figuresOutOfTypeArea geom v)
          assertNone (inputName input) (captionsNotTurned geom v)
          -- broken: the figures a point out of the type area, and the captions not turned
          let out i = i {ivRect = (ivRect i) {rectX = rectX (ivRect i) - Sp 65536}}
          assertSome (inputName input <> ", a figure out of the type area") (figuresOutOfTypeArea geom (mapPages (\p -> p {pvImages = map out (pvImages p)}) v))
          let unturned l = if lvKind l == "キャプションの行" then l {lvRect = (lvRect l) {rectW = rectH (lvRect l), rectH = rectW (lvRect l)}} else l
          assertSome (inputName input <> ", a caption not turned") (captionsNotTurned geom (mapPages (\p -> p {pvLines = map unturned (pvLines p)}) v)),
      testCase "I3: the text of the tenth item of a numbered list and after starts where that of the first nine does (golem-driver ADR 0013)" $ do
        forM_ [specimensHorizontal, specimensVertical] $ \input -> withInput input $ \dir -> do
          (_, pl) <- layoutOf dir
          let starts = numberedStarts pl
          assertBool (inputName input <> " has a numbered list of 12 items") (any ((>= 12) . length) starts)
          assertNone (inputName input) (unevenStarts starts)
        let nine = T.concat ["+ 項目" <> T.pack (show i) <> "。\n" | i <- [1 .. 9 :: Int]]
        (_, pl) <- layoutOk horizontalStyle (nine <> "+ 項目10。\n+ 項目11。\n") []
        map (map fst) (numberedStarts pl) @?= [map (T.pack . show) [1 .. 11 :: Int]]
        assertNone "a list of eleven items" (unevenStarts (numberedStarts pl))
        {- broken: the items from 100 (@number starts a list of its own)
        after a list of nine, taken as one list; the marker of three digits
        is wider than that of one with the fake fonts, so their text starts
        further -}
        (_, pl') <- layoutOk horizontalStyle (nine <> "@number 100\n+ 項目100。\n+ 項目101。\n") []
        let lists = numberedStarts pl'
        length lists @?= 2
        assertNone "two lists" (unevenStarts lists)
        assertSome "the two lists as one" (unevenStarts [concat lists])
    ]

-- ------------------------------------------------------------------ inputs

-- | An input: its name, its directory in the fixtures and the fonts it needs copied in (as file in fonts/, from).
data Input = Input {inputName :: String, inputDir :: FilePath, inputFonts :: [(FilePath, FilePath)]}

-- | The fonts of the specimens and the complex books, as fonts/ja.otf and fonts/latin.otf.
jaLatin :: [(FilePath, FilePath)]
jaLatin = [("ja.otf", "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"), ("latin.otf", "../golem-font/test/fonts/SourceSansPro-Regular.otf")]

specimensHorizontal, specimensVertical, complexVertical, elementsOfStyle :: Input
specimensHorizontal = Input "specimens-horizontal" "specimens/horizontal" jaLatin
specimensVertical = Input "specimens-vertical" "specimens/vertical" jaLatin
complexVertical = Input "complex-vertical" "complex-vertical" jaLatin
elementsOfStyle = Input "pd-elements-of-style" "pd/elements-of-style" [("SourceSerifVariable-Roman.ttf", "test/fixtures/tempest/fonts/SourceSerifVariable-Roman.ttf")]

-- | A copy of an input in a temporary directory, with its fonts.
withInput :: Input -> (FilePath -> IO a) -> IO a
withInput input act = withSystemTempDirectory "golem-specimen" $ \tmp -> do
  copyTree ("test/fixtures" </> inputDir input) tmp
  createDirectoryIfMissing True (tmp </> "fonts")
  forM_ (inputFonts input) $ \(to, from) -> copyFile from (tmp </> "fonts" </> to)
  act tmp

-- | The view of golem preflight of a project, with the real fonts.
viewOf :: FilePath -> IO View
viewOf dir = do
  p <- preflight (defaultPreflightOptions dir) {poFonts = realProvider}
  maybe (assertFailure (show (filter isError (prDiagnostics p)))) pure (prView p)

-- | The page geometry of a project.
geometryOf :: FilePath -> IO PageGeometry
geometryOf dir = fst <$> layoutOf dir

-- | The layout of a project with the real fonts, as the PDF is set from it.
layoutOf :: FilePath -> IO (PageGeometry, PdfLayout)
layoutOf dir = do
  ev <- evaluateProject Prod dir
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, pageGeometry (FileId 0) False (evStyle e)) of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> assertFailure (show errs)
      (Just book, Right geom) ->
        loadFonts realProvider (diskFiles dir) (evStyleFile e) (evStyle e) [] >>= \case
          Left ds -> assertFailure (show ds)
          Right fonts -> do
            (_, _, bib) <- loadBibliography (diskFiles dir) (projectManifest (evProject e))
            let (vars, _) = runningVars e
                inp = PdfInput (diskFiles dir) (evProject e) (evStyle e) book False [] bib Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) vars (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)
            layoutPdf inp geom fonts >>= either (assertFailure . show) (pure . (geom,))
      (_, Left ds) -> assertFailure (show ds)
      (Nothing, _) -> assertFailure "no book"

-- | The view of a one-chapter project with the fake fonts.
miniView :: BS.ByteString -> T.Text -> IO View
miniView style source = snd <$> miniGeometryView style source

-- | The geometry and the view of a one-chapter project with the fake fonts.
miniGeometryView :: BS.ByteString -> T.Text -> IO (PageGeometry, View)
miniGeometryView style source = withSystemTempDirectory "golem-specimen" $ \tmp -> do
  writeProject tmp miniManifest style source []
  p <- preflight (defaultPreflightOptions tmp) {poFonts = fakeProvider}
  v <- maybe (assertFailure (show (filter isError (prDiagnostics p)))) pure (prView p)
  ev <- evaluateProject Prod tmp
  geom <- case ev of
    Right e | Right g <- pageGeometry (FileId 0) False (evStyle e) -> pure g
    _ -> assertFailure "no geometry"
  pure (geom, v)

smallTable :: T.Text
smallTable = "| 項目 | 値 |\n|---|---|\n| 幅 | 広い |\n| 高さ | 低い |\n"

-- ------------------------------------------------------------------ the properties

-- | The rules of a table that cross the face of a line of a cell.
tableRulesCrossCells :: View -> [String]
tableRulesCrossCells v =
  [ show (pvIndex p, rvRect r, lvRect l)
  | p <- vwPages v,
    r <- rulesOfKind "表の罫線" p,
    l <- linesOfKind "表の行" p,
    overlaps (rvRect r) (lvRect l)
  ]

-- | Two rules of a table that overlap on a page.
doubleTableRules :: View -> [String]
doubleTableRules v =
  [ show (pvIndex p, rvRect a, rvRect b)
  | p <- vwPages v,
    let rs = zip [0 :: Int ..] (rulesOfKind "表の罫線" p),
    (i, a) <- rs,
    (j, b) <- rs,
    i < j,
    overlaps (rvRect a) (rvRect b) || rvRect a == rvRect b
  ]

{- | A line of a table next to a line of text with less than two pitches
between them, in the order of the lines of a column: the space of a line
before and after the table.
-}
tableSpaces :: PageGeometry -> View -> [String]
tableSpaces geom v =
  [ show (pvIndex p, lvKind a, lvRect a, lvKind b, lvRect b)
  | p <- vwPages v,
    col <- columnsFor geom (pvIndex p),
    let ls = sortOn (negate . progression) [l | l <- pvLines p, lvKind l `elem` ["本文の行", "表の行"], inside (centre (lvRect l)) col],
    (a, b) <- zip ls (drop 1 ls),
    lvKind a /= lvKind b,
    progression a - progression b < 2 * pgLinePitch geom - tolerance
  ]
  where
    vertical = pgVertical geom
    -- how far along the block direction a line is: its top, or its right side
    progression l = let r = lvRect l in if vertical then rectX r + rectW r else rectY r + rectH r

{- | A paragraph rule outside the type area, or across the face of a line,
or a line of text off the grid lines (the face of grid line k is k pitches
from the start of its column).
-}
paragraphRulesOffGrid :: PageGeometry -> View -> [String]
paragraphRulesOffGrid geom v =
  [ "out of the type area: " <> show (pvIndex p, rvRect r)
  | p <- vwPages v,
    r <- rulesOfKind "段落の罫線" p,
    not (within (rvRect r) (typeAreaFor geom (pvIndex p)))
  ]
    <> [ "across a line: " <> show (pvIndex p, rvRect r, lvRect l)
       | p <- vwPages v,
         r <- rulesOfKind "段落の罫線" p,
         l <- pvLines p,
         lvKind l `elem` ["本文の行", "見出しの行"],
         overlaps (rvRect r) (lvRect l)
       ]
    <> [ "off the grid: " <> show (pvIndex p, lvRect l)
       | p <- vwPages v,
         col <- columnsFor geom (pvIndex p),
         l <- linesOfKind "本文の行" p,
         inside (centre (lvRect l)) col,
         faceSize (lvRect l) == pgFontSize geom,
         let off = fromStart col (lvRect l) `mod` unSp (pgLinePitch geom),
         min off (unSp (pgLinePitch geom) - off) > unSp tolerance
       ]
  where
    vertical = pgVertical geom
    faceSize r = if vertical then rectW r else rectH r
    -- from the start of the column to the near side of the face of a line
    fromStart col r
      | vertical = unSp ((rectX col + rectW col) - (rectX r + rectW r))
      | otherwise = unSp ((rectY col + rectH col) - (rectY r + rectH r))

-- | A note whose body starts in another column than the line of its mark.
notesAwayFromMarks :: PdfLayout -> [String]
notesAwayFromMarks pl =
  [ show (nid, poNumber p, poColumn p)
  | p <- plPages pl,
    (nid, 0, _) <- poFootnotes p,
    nid `notElem` marked p
  ]
  where
    marked p = [n | (_, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)], (n, _) <- slNotes sl]

{- | The lines of the footnotes of a column that are not in the column
(from its line start, as wide as its measure), after its text, as many
as the layout gives it.
-}
noteLinesOutOfColumns :: PageGeometry -> PdfLayout -> View -> [String]
noteLinesOutOfColumns geom pl v =
  [ show (n, c, length here, expected, map lvRect here)
  | p <- plPages pl,
    let n = poNumber p
        c = poColumn p
        col = columnsFor geom n !! c
        expected = sum [k | (_, _, k) <- poFootnotes p],
    pv <- take 1 [x | x <- vwPages v, pvIndex x == n],
    let here = [l | l <- linesOfKind "脚注の行" pv, inColumn col (lvRect l)]
        texts = [l | l <- linesOfKind "本文の行" pv, inside (centre (lvRect l)) col],
    length here /= expected || or [not (follows l t) | l <- here, t <- texts]
  ]
    <> [ "a note line in no column: " <> show (pvIndex pv, lvRect l)
       | pv <- vwPages v,
         l <- linesOfKind "脚注の行" pv,
         not (any (`inColumn` lvRect l) (columnsFor geom (pvIndex pv)))
       ]
  where
    vertical = pgVertical geom
    {- a line of the column: from its line start, across the measure, past
    its line end by a hanging character at most (an em of the line) -}
    inColumn col r
      | vertical =
          inside (centre r) col
            && abs ((rectY r + rectH r) - (rectY col + rectH col)) <= tolerance
            && rectY r >= rectY col - rectW r - tolerance
      | otherwise =
          inside (centre r) col
            && abs (rectX r - rectX col) <= tolerance
            && rectX r + rectW r <= rectX col + rectW col + rectH r + tolerance
    -- the note line l is after the text line t in the block direction
    follows l t
      | vertical = rectX (lvRect l) + rectW (lvRect l) <= rectX (lvRect t)
      | otherwise = rectY (lvRect l) + rectH (lvRect l) <= rectY (lvRect t)

-- | The footnotes of each first column moved to the column after it.
shiftNotes :: [PageOut] -> [PageOut]
shiftNotes ps =
  [ case poColumn p of
      0 -> p {poFootnotes = []}
      _ -> p {poFootnotes = poFootnotes p <> concat [poFootnotes q | q <- ps, poNumber q == poNumber p, poColumn q == poColumn p - 1]}
  | p <- ps
  ]

-- | A figure not inside the type area of its page.
figuresOutOfTypeArea :: PageGeometry -> View -> [String]
figuresOutOfTypeArea geom v =
  [show (pvIndex p, ivRect i) | p <- vwPages v, i <- pvImages p, not (within (ivRect i) (typeAreaFor geom (pvIndex p)))]

{- | A caption line on the page of a turned figure that runs along the lines
of the page: a turned caption runs across them, as its figure turns.
-}
captionsNotTurned :: PageGeometry -> View -> [String]
captionsNotTurned geom v =
  [ show (pvIndex p, lvRect l)
  | p <- vwPages v,
    any ivTurned (pvImages p),
    l <- linesOfKind "キャプションの行" p,
    let r = lvRect l
        along = if pgVertical geom then rectH r else rectW r
        across = if pgVertical geom then rectW r else rectH r,
    along >= across
  ]

{- | The numbered lists of a layout, each the numbers of its items and
where the text of their first lines starts from the line start of the
column. A list is the first lines of items at one indent whose numbers
follow each other by one; a line at that indent or less without a
number ends it, and so does a number that does not follow (@number
starts a list of its own).
-}
numberedStarts :: PdfLayout -> [[(T.Text, Sp)]]
numberedStarts pl = go Nothing (Map.elems (plLines pl))
  where
    go cur [] = close cur
    go cur (sl : rest) = case (numbered sl, cur) of
      (Just item, Just (i, items@(prev : _)))
        | slIndent sl == i,
          Just a <- valueOf (fst prev),
          valueOf (fst item) == Just (a + 1) ->
            go (Just (i, item : items)) rest
      (Just item, _) -> close cur <> go (Just (slIndent sl, [item])) rest
      (Nothing, Just (i, _))
        | slIndent sl <= i -> close cur <> go Nothing rest
      (Nothing, _) -> go cur rest
    close = maybe [] (\(_, items) -> [reverse items])
    {- the first line of an item with a number: its marker is boxes of the
    number and its punctuation, then an empty box (golem-driver ADR 0013) -}
    numbered sl =
      let (marker, rest) = break isEnd (lineItems (slLine sl))
          texts = [bcText c | Box _ c <- marker]
       in case (texts, rest) of
            (_ : _ : _, end : _)
              | length texts == length marker,
                Just _ <- valueOf (T.concat (init texts)),
                last texts `elem` [".", "、"] ->
                  Just (T.concat (init texts), slIndent sl + sum (map width marker) + width end)
            _ -> Nothing
    isEnd = \case
      Box _ c -> T.null (bcText c)
      _ -> False
    width = \case
      Box w _ -> w
      _ -> 0

-- | The value of a number in digits, or in kanji below a hundred (一 to 九十九).
valueOf :: T.Text -> Maybe Int
valueOf t
  | not (T.null t), T.all isDigit t = Just (read (T.unpack t))
  | otherwise = case T.unpack t of
      [d] | Just n <- digit d -> Just n
      ['十'] -> Just 10
      ['十', d] | Just n <- digit d -> Just (10 + n)
      [a, '十'] | Just m <- digit a -> Just (10 * m)
      [a, '十', d] | Just m <- digit a, Just n <- digit d -> Just (10 * m + n)
      _ -> Nothing
  where
    digit c = lookup c (zip "一二三四五六七八九" [1 ..])

-- | A list whose items do not all start their text at one place.
unevenStarts :: [[(T.Text, Sp)]] -> [String]
unevenStarts lists = [show l | l <- lists, length (foldr (\(_, s) acc -> if s `elem` acc then acc else s : acc) [] l) > 1]

-- ------------------------------------------------------------------ helpers

rulesOfKind :: T.Text -> PageView -> [RuleView]
rulesOfKind k = filter ((== k) . rvKind) . pvRules

linesOfKind :: T.Text -> PageView -> [LineView]
linesOfKind k = filter ((== k) . lvKind) . pvLines

mapPages :: (PageView -> PageView) -> View -> View
mapPages f v = v {vwPages = map f (vwPages v)}

-- | Two rectangles that share more than an edge.
overlaps :: Rect -> Rect -> Bool
overlaps a b =
  rectX a < rectX b + rectW b
    && rectX b < rectX a + rectW a
    && rectY a < rectY b + rectH b
    && rectY b < rectY a + rectH a

-- | A rectangle inside another, within the tolerance.
within :: Rect -> Rect -> Bool
within a b =
  rectX a >= rectX b - tolerance
    && rectY a >= rectY b - tolerance
    && rectX a + rectW a <= rectX b + rectW b + tolerance
    && rectY a + rectH a <= rectY b + rectH b + tolerance

centre :: Rect -> (Sp, Sp)
centre r = (rectX r + Sp (unSp (rectW r) `div` 2), rectY r + Sp (unSp (rectH r) `div` 2))

inside :: (Sp, Sp) -> Rect -> Bool
inside (x, y) r = x >= rectX r && x <= rectX r + rectW r && y >= rectY r && y <= rectY r + rectH r

-- | A hundredth of a point: the rounding of the geometry.
tolerance :: Sp
tolerance = Sp 656

assertNone :: String -> [String] -> Assertion
assertNone what found = unless (null found) (assertFailure (what <> ": " <> unlines found))

assertSome :: String -> [String] -> Assertion
assertSome what found = assertBool (what <> ": the property finds nothing") (not (null found))

