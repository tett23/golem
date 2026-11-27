-- | The text frames of the pages (root ADR 0438).
module FramesSpec (framesTests, frameDef, layoutCodes, ptSp, spPt) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver (BuildOptions (..), defaultOptions, manuscriptLines)
import Golem.Layout.KnuthPlass (Line (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..), columnsFor)
import Golem.Length (Sp (..), Unit (..), toSp)
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.Typeset (PdfLayout (..), PlacedFrame (..), SetLine (..))
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A frame of style.toml: its name and its keys.
frameDef :: T.Text -> T.Text -> BS.ByteString
frameDef name keys = TE.encodeUtf8 ("\n[frames." <> name <> "]\n" <> keys)

-- | A rectangle of the frame keys, in pt.
rectKeys :: Integer -> Integer -> Integer -> Integer -> T.Text
rectKeys x y w h = T.pack (concat ["x = \"", show x, "pt\"\ny = \"", show y, "pt\"\nwidth = \"", show w, "pt\"\nheight = \"", show h, "pt\"\n"])

-- | horizontalStyle with frames, and a master page body that puts some of them.
framesStyle :: [BS.ByteString] -> [BS.ByteString] -> BS.ByteString
framesStyle defs masterFrames =
  horizontalStyle
    <> mconcat defs
    <> (if null masterFrames then "" else "\n[masters.body]\nframes = [" <> BS.intercalate ", " ["\"" <> n <> "\"" | n <- masterFrames] <> "]\n")

ptSp :: Integer -> Sp
ptSp n = toSp Pt (fromInteger n)

-- | The frames of each page of a layout.
framesOn :: PdfLayout -> [(Int, PlacedFrame)]
framesOn pl = [(n, f) | (n, fs) <- Map.toList (plFrames pl), f <- fs]

-- | The pages of a layout, in order.
pageNumbers :: PdfLayout -> [Int]
pageNumbers pl = Map.keys (Map.fromList [(poNumber p, ()) | p <- plPages pl])

-- | The rectangle of the lines of a frame of a page with its text, or nothing.
frameText :: PlacedFrame -> T.Text
frameText f = T.concat [setLineText sl | (_, sl) <- pfrLines f]

-- | Whether a rectangle is inside another, the edges included.
inside :: Rect -> Rect -> Bool
inside (Rect x y w h) (Rect bx by bw bh) = x >= bx && y >= by && x + w <= bx + bw && y + h <= by + bh

-- | The rectangle on page n of a frame at x and y from the top left, from the left on every page.
fromTopLeft :: PageGeometry -> Sp -> Sp -> Sp -> Sp -> Rect
fromTopLeft geom x y w h = Rect x (snd (pgPageSize geom) - y - h) w h

-- | The codes of the errors of a layout.
layoutCodes :: Either [Diagnostic] a -> [T.Text]
layoutCodes = either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const [])

-- | The page of each frame of a name.
pagesOfFrame :: T.Text -> PdfLayout -> [Int]
pagesOfFrame name pl = [n | (n, f) <- framesOn pl, pfrName f == name]

-- | The text of the body of a layout and where it is: each line's page, column, slot and text.
bodyLines :: PdfLayout -> [(Int, Int, Sp, T.Text)]
bodyLines pl = [(poNumber p, poColumn p, slot, setLineText sl) | p <- plPages pl, (slot, s) <- poSlots p, lid <- lineIdsOf s, Just sl <- [Map.lookup lid (plLines pl)]]

-- | The lines of a slot of the body.
lineIdsOf :: Slotted -> [Int]
lineIdsOf = \case
  SLine l -> [l]
  _ -> []

-- | Two frames the tests use: quote and note, rectangles of two lines of six characters.
twoFrames :: [BS.ByteString]
twoFrames = [frameDef "quote" (rectKeys 20 20 100 25), frameDef "note" (rectKeys 20 80 100 25)]

framesTests :: [TestTree]
framesTests =
  [ testCase "root ADR 0438 I6: HTML has the paragraphs of @frame in an aside and not the text of the frames of a master page" $ do
      (page, _) <- htmlMini (framesStyle (frameDef "title" (rectKeys 20 20 100 25 <> "text = \"飾りの文\"\n") : twoFrames) ["title"]) "前。\n\n@frame quote\n  引用の文。\n\n後。\n"
      assertBool "the aside" ("<aside class=\"frame frame-quote\">" `T.isInfixOf` page && "引用の文。" `T.isInfixOf` page)
      assertBool "no text of the master page" (not ("飾りの文" `T.isInfixOf` page)),
    testCase "root ADR 0438 I7: the body of a manuscript with text only in frames has no characters" $
      withSystemTempDirectory "golem-frames" $ \tmp -> do
        writeProject tmp miniManifest (framesStyle (frameDef "title" (rectKeys 20 20 100 25 <> "text = \"飾りの文\"\n") : twoFrames) ["title"]) "@frame quote\n  引用の文。\n" []
        r <- manuscriptLines (defaultOptions tmp) {optFonts = fakeProvider}
        either (assertFailure . show . snd) (\(ls, _) -> T.concat ls @?= "") r,
    testCase "root ADR 0438 I10: @frame of a name [frames] does not have is G03289 alone" $ do
      (codes, _) <- buildMini fakeProvider False (framesStyle twoFrames []) "前。\n\n@frame missing\n  引用。\n" []
      codes @?= [DiagnosticCode "G03289"],
    testCase "root ADR 0438: @frame without one name is G02255 alone, and a block of its body that is no paragraph G02256 alone" $ do
      (noName, _) <- buildMini fakeProvider False (framesStyle twoFrames []) "前。\n\n@frame\n  引用。\n" []
      noName @?= [DiagnosticCode "G02255"]
      (twoNames, _) <- buildMini fakeProvider False (framesStyle twoFrames []) "前。\n\n@frame quote note\n  引用。\n" []
      twoNames @?= [DiagnosticCode "G02255"]
      (list, _) <- buildMini fakeProvider False (framesStyle twoFrames []) "前。\n\n@frame quote\n  - 項目\n" []
      list @?= [DiagnosticCode "G02256"],
    testCase "root ADR 0438 I1: a frame of a master page is at the same place on every page" $ do
      (geom, pl) <- layoutOk (framesStyle [frameDef "title" (rectKeys 20 20 100 25 <> "text = \"扉の飾りの文\"\n")] ["title"]) (longPara 80) []
      let pages = pageNumbers pl
          expected = fromTopLeft geom (ptSp 20) (ptSp 20) (ptSp 100) (ptSp 25)
      assertBool "several pages" (length pages > 1)
      map fst (framesOn pl) @?= pages
      forM_ (framesOn pl) $ \(n, f) -> do
        (n, frameText f) @?= (n, "扉の飾りの文")
        forM_ (pfrLines f) $ \(r, _) -> assertBool (show (n, r, expected)) (r `inside` expected),
    testCase "root ADR 0438 I1, I9: a frame from the inside is mirrored, as far from the spine on both pages" $ do
      (geom, pl) <- layoutOk (framesStyle [frameDef "title" (rectKeys 20 20 100 25 <> "x-from = \"inside\"\ntext = \"扉の飾りの文\"\n")] ["title"]) (longPara 80) []
      let pw = fst (pgPageSize geom)
          spineDistance n r = if odd n then rectX r else pw - rectX r - rectW r
      forM_ (framesOn pl) $ \(n, f) -> forM_ (pfrLines f) $ \(r, _) -> do
        (n, spineDistance n r) @?= (n, ptSp 20)
        assertBool (show (n, r)) (r `inside` (if odd n then fromTopLeft geom (ptSp 20) (ptSp 20) (ptSp 100) (ptSp 25) else fromTopLeft geom (pw - ptSp 120) (ptSp 20) (ptSp 100) (ptSp 25))),
    testCase "root ADR 0438 I1, I9: a frame from the outside is mirrored, as far from the fore-edge on both pages" $ do
      (geom, pl) <- layoutOk (framesStyle [frameDef "title" (rectKeys 20 20 100 25 <> "x-from = \"outside\"\ntext = \"扉の飾りの文\"\n")] ["title"]) (longPara 80) []
      let pw = fst (pgPageSize geom)
          foreEdgeDistance n r = if odd n then pw - rectX r - rectW r else rectX r
      assertBool "two pages or more" (length (framesOn pl) > 1)
      forM_ (framesOn pl) $ \(n, f) -> forM_ (pfrLines f) $ \(r, _) -> (n, foreEdgeDistance n r) @?= (n, ptSp 20),
    testCase "root ADR 0438 I2: the characters of a frame of a circle are inside the circle" $ do
      -- a circle of radius 50pt centred at (100pt, 100pt), four cubic curves
      let circle = "M 150 100 C 150 127.6142 127.6142 150 100 150 C 72.3858 150 50 127.6142 50 100 C 50 72.3858 72.3858 50 100 50 C 127.6142 50 150 72.3858 150 100 Z"
          keys = "path = \"" <> circle <> "\"\nunit = \"pt\"\ntext = \"" <> T.replicate 3 "円の中に組む文" <> "\"\n"
      (geom, pl) <- layoutOk (framesStyle [frameDef "round" keys] ["round"]) "本文。\n" []
      let ph = snd (pgPageSize geom)
          r2 = (50 * 65536) ^ (2 :: Int) :: Integer
          inCircle (x, y) = let dx = unSp x - 100 * 65536; dy = unSp y - (unSp ph - 100 * 65536) in dx * dx + dy * dy <= r2 + r2 `div` 1000
      case framesOn pl of
        [(_, f)] -> do
          assertBool "lines" (length (pfrLines f) >= 3)
          forM_ (pfrLines f) $ \(Rect x y w h, _) -> forM_ [(x, y), (x + w, y), (x, y + h), (x + w, y + h)] $ \c -> assertBool (show c) (inCircle c)
        other -> assertFailure (show (length other)),
    testCase "root ADR 0438 I3: a frame of no wrap leaves the body as without its @frame" $ do
      let style = framesStyle twoFrames []
          body = longPara 30
      (_, without) <- layoutOk style (body <> longPara 30) []
      (_, with) <- layoutOk style (body <> "@frame quote\n  引用の一。\n\n" <> longPara 30) []
      bodyLines with @?= bodyLines without
      pagesOfFrame "quote" with @?= [1],
    testCase "root ADR 0438 I3: a frame of a master page of no wrap leaves the body as a master page without it" $ do
      (_, without) <- layoutOk (framesStyle [frameDef "title" (rectKeys 20 100 200 60 <> "text = \"重なる文\"\n")] []) (longPara 50) []
      (_, with) <- layoutOk (framesStyle [frameDef "title" (rectKeys 20 100 200 60 <> "text = \"重なる文\"\n")] ["title"]) (longPara 50) []
      bodyLines with @?= bodyLines without
      assertBool "frames" (not (null (framesOn with))),
    testCase "root ADR 0438 I1: @frame quote with two paragraphs puts both in the frame on its page" $ do
      (_, pl) <- layoutOk (framesStyle twoFrames []) "前の段落。\n\n@frame quote\n:::\n一つめ。\n\n二つめ。\n:::\n\n後の段落。\n" []
      map (frameText . snd) (framesOn pl) @?= ["一つめ。二つめ。"],
    testCase "root ADR 0438 I1: a @frame right after the last line of a page goes on that page" $ do
      -- 36 paragraphs of ten characters fill the 30 grid lines of page 1 with two lines each? no: 12 characters a line, so one line each
      (_, pl) <- layoutOk (framesStyle twoFrames []) (fillers 30 <> "@frame quote\n  引用。\n\n" <> fillers 3) []
      pagesOfFrame "quote" pl @?= [1],
    testCase "root ADR 0438 I1: a @frame before which no block has lines goes on the page of the first line after it" $ do
      (_, pl) <- layoutOk (framesStyle twoFrames []) ("@frame quote\n  引用。\n\n" <> fillers 3) []
      pagesOfFrame "quote" pl @?= [1],
    testCase "root ADR 0438 I1: a @frame after a figure after a paragraph goes on the page of the last line of the paragraph" $ do
      img <- tinyImage
      (_, pl) <- layoutOk (figStyle (framesStyle twoFrames [])) (fillers 30 <> "@figure images/tiny.jpg alt=\"t\"\n  図。\n\n@frame quote\n  引用。\n\n" <> fillers 3) img
      pagesOfFrame "quote" pl @?= [1],
    testCase "root ADR 0438 I1: two @frame in a row both go on the page of the paragraph before them" $ do
      (_, pl) <- layoutOk (framesStyle twoFrames []) (fillers 30 <> "@frame quote\n  引用。\n\n@frame note\n  注記。\n\n" <> fillers 3) []
      (pagesOfFrame "quote" pl, pagesOfFrame "note" pl) @?= ([1], [1]),
    testCase "root ADR 0438 I5: content that just fits a frame is set" $ do
      (_, pl) <- layoutOk (framesStyle [frameDef "box" (rectKeys 20 20 100 25 <> "text = \"あいうえおかきくけこさしすせそたちつてと\"\n")] ["box"]) "本文。\n" []
      map (length . pfrLines . snd) (framesOn pl) @?= [2],
    testCase "root ADR 0438 I5, I10: content a line more than a frame holds is G07139 alone, once for the frame of a master page" $ do
      r <- layoutMini (framesStyle [frameDef "box" (rectKeys 20 20 100 25 <> "text = \"あいうえおかきくけこさしすせそたちつてとな\"\n")] ["box"]) (longPara 80) []
      layoutCodes r @?= ["G07139"],
    testCase "root ADR 0438 I5: a @frame that does not fit is G07139, and the other frames and pages are set" $ do
      r <- layoutMini (framesStyle [frameDef "box" (rectKeys 20 20 100 25), frameDef "big" (rectKeys 20 100 100 25)] []) ("前。\n\n@frame box\n  " <> T.replicate 21 "あ" <> "\n\n" <> fillers 40 <> "@frame big\n  " <> T.replicate 21 "い" <> "\n\n") []
      layoutCodes r @?= ["G07139", "G07139"],
    testCase "root ADR 0438 I8, I10: the same frame twice on a page is G07140 alone" $ do
      r <- layoutMini (framesStyle twoFrames []) "前。\n\n@frame quote\n  一。\n\n@frame quote\n  二。\n\n後。\n" []
      layoutCodes r @?= ["G07140"],
    testCase "root ADR 0438 I8, I10: a @frame of the frame of the master page of its page is G07140" $ do
      r <- layoutMini (framesStyle twoFrames ["quote"]) "前。\n\n@frame quote\n  一。\n\n後。\n" []
      layoutCodes r @?= ["G07140"],
    testCase "root ADR 0438 I10: a @frame of a frame of wrap around is G07137 alone" $ do
      r <- layoutMini (framesStyle [frameDef "side" (rectKeys 20 20 100 25 <> "wrap = \"around\"\n")] []) "前。\n\n@frame side\n  一。\n\n後。\n" []
      layoutCodes r @?= ["G07137"],
    testCase "root ADR 0438 I4: a frame of wrap around at the end edge of the column shortens the lines under it" $ do
      (geom, pl) <- layoutOk (aroundStyle 1 4) (longPara 60) []
      shortened <- checkAround geom pl (ptSp 40)
      assertBool "some lines are shortened" (shortened > 0),
    testCase "root ADR 0438 I4: a frame of wrap around over the margin shortens the lines by its overlap with the column only" $ do
      (geom, pl) <- layoutOk (aroundStyle 1 4) (longPara 60) []
      _ <- checkAround geom pl (ptSp 40)
      -- 4 characters of the column under the frame: 8 characters are left on the shortened lines
      assertBool "lines of 8 characters" (any (\(_, _, _, t) -> T.length t == 8) (bodyLines pl)),
    testCase "root ADR 0438 I4: a frame of wrap around over two columns shortens the lines of each column by its overlap" $ do
      (geom, pl) <- layoutOk (aroundStyle 2 3) (longPara 120) []
      shortened <- checkAround geom pl (ptSp 30)
      assertBool "some lines are shortened" (shortened > 0),
    testCase "root ADR 0438 I4, I10: a frame of wrap around that touches neither edge of a column is G07136 alone" $ do
      r <- layoutMini (horizontalStyle <> frameDef "side" "x = \"30mm\"\ny = \"150pt\"\nwidth = \"20pt\"\nheight = \"40pt\"\nwrap = \"around\"\nx-from = \"inside\"\n" <> "\n[masters.body]\nframes = [\"side\"]\n") (longPara 60) []
      layoutCodes r @?= ["G07136"],
    testCase "root ADR 0438 I10: a frame of wrap around that leaves 7 characters on a line is G07138 alone" $ do
      r <- layoutMini (aroundStyle 1 5) (longPara 60) []
      layoutCodes r @?= ["G07138"]
  ]

{- | horizontalStyle (or two columns of 11 characters 2zw apart) with a
frame of wrap around on the master page, from the outside: it covers the
last n characters of the column on the odd pages, the first n on the
even ones, the margin beyond them to the fore-edge, from 150pt to 210pt
down the page.
-}
aroundStyle :: Int -> Int -> BS.ByteString
aroundStyle columns n =
  let base = if columns == 1 then horizontalStyle else replaceIn "columns = 1" ("columns = " <> T.pack (show columns) <> "\ncolumn-gap = \"2zw\"") (replaceIn "characters = 12" "characters = 11" horizontalStyle)
      -- A5, 20mm from the spine to the type area of 120pt (or of 240pt, two columns of 11 characters 2zw apart)
      areaWidth = if columns == 1 then 120 else 240
      width = toSp Mm 148 - toSp Mm 20 - ptSp (areaWidth - 10 * toInteger n)
   in base <> frameDef "side" ("x = \"0pt\"\ny = \"150pt\"\nwidth = \"" <> T.pack (spPt width) <> "\"\nheight = \"60pt\"\nwrap = \"around\"\nx-from = \"outside\"\n") <> "\n[masters.body]\nframes = [\"side\"]\n"

-- | A length in sp written exactly in pt: sp / 65536 = sp * 5^16 / 10^16.
spPt :: Sp -> String
spPt (Sp n) =
  let digits = show (n * 5 ^ (16 :: Int))
      padded = replicate (17 - length digits) '0' <> digits
      (whole, frac) = splitAt (length padded - 16) padded
   in whole <> "." <> frac <> "pt"

{- | The lines of the body under a frame of wrap around (root ADR 0438 I4):
on each page, the bounding rectangle of the frame of 'aroundStyle' (150pt
to 210pt down the page); each line whose em box crosses it in its rows,
in a column the frame overlaps by @overlap@, is at most the measure less
the overlap long, and starts after the overlap when the frame covers the
start of its column. The number of the lines shortened.
-}
checkAround :: PageGeometry -> PdfLayout -> Sp -> IO Int
checkAround geom pl overlap = do
  let ph = snd (pgPageSize geom)
      (top, bottom) = (ph - ptSp 150, ph - ptSp 210)
      size = pgFontSize geom
      under =
        [ (n, sl, startSide)
        | p <- plPages pl,
          let n = poNumber p,
          -- the frame from the outside: the right end of the column on odd pages, the left on even ones
          let startSide = even n,
          poColumn p == (if startSide then 0 else length (columnsFor geom n) - 1),
          col <- take 1 (drop (poColumn p) (columnsFor geom n)),
          (slot, SLine lid) <- poSlots p,
          let baseline = rectY col + rectH col - slot - sum (take 1 (pgLineGrid geom))
              emTop = baseline + size - zwToSpTest size
              emBottom = emTop - size,
          emTop > bottom && emBottom < top,
          Just sl <- [Map.lookup lid (plLines pl)]
        ]
      measure = sum (map rectW (take 1 (columnsFor geom 1)))
  forM_ under $ \(n, sl, startSide) -> do
    assertBool (show (n, setLineText sl)) (lineTarget (slLine sl) <= measure - overlap)
    assertBool (show (n, slIndent sl)) (not startSide || slIndent sl >= overlap)
  pure (length under)
  where
    zwToSpTest s = Sp (unSp s * 12 `div` 100)
