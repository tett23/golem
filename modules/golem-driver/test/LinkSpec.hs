-- | The link annotations of the PDF (docs/adr ADR 0182).
module LinkSpec (linkTests, annotations) where

import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), placeLine)
import Golem.Layout.Look (Look (..))
import Golem.LayoutSpec (Rect (..), columnsFor)
import Golem.Length (Sp (..))
import Golem.Pdf (spToPt)
import Golem.Project.Style (dimToSp, parseDim)
import Golem.Syntax
import Support
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

{- | The URI and the rectangle (x0, y0, x1, y1 in pt) of each link
annotation of a PDF, in the order written.
-}
annotations :: BS.ByteString -> [(BS.ByteString, [Double])]
annotations pdf = case BS.breakSubstring needle pdf of
  (_, rest)
    | BS.null rest -> []
    | otherwise ->
        let r1 = BS.drop (BS.length needle) rest
            (uri, r2) = BS.breakSubstring ") >>" r1
            r3 = BS.drop 7 (snd (BS.breakSubstring "/Rect [" r2))
            nums = fst (BS.breakSubstring "]" r3)
         in (uri, map (read . BC.unpack) (BC.words nums)) : annotations r2
  where
    needle = "<< /A << /S /URI /URI ("

-- | The number of annotations each page refers to, the pages that have some.
annotsPerPage :: BS.ByteString -> [Int]
annotsPerPage pdf = case BS.breakSubstring "/Annots [" pdf of
  (_, rest)
    | BS.null rest -> []
    | otherwise ->
        let body = fst (BS.breakSubstring "]" (BS.drop 9 rest))
         in length (BC.words body) `div` 3 : annotsPerPage (BS.drop 9 rest)

{- | The runs of boxes of a link on each line of a layout, in the order of
the lines: the start of the first box and the end of the last, from the
line start.
-}
linkRuns :: PdfLayout -> [(Sp, Sp)]
linkRuns pl =
  [ (slIndent sl + minimum (map fst bs), slIndent sl + maximum (map snd bs))
  | sl <- Map.elems (plLines pl),
    let bs = [(off, off + w) | (Box w c, off) <- placeLine (slLine sl), isJust (lkLink (bcLook c))],
    not (null bs)
  ]

toPt :: Sp -> Double
toPt = read . T.unpack . spToPt

near :: Double -> Double -> Assertion
near a b = assertBool (show (a, b)) (abs (a - b) < 0.01)

-- | The glyphs drawn on the pages of a PDF.
glyphs :: BS.ByteString -> IO [Drawn]
glyphs pdf = concatMap drawnGlyphs <$> pageContents pdf

linkTests :: [TestTree]
linkTests =
  [ testCase "horizontal: a link on one line is one annotation, from the start of its text to the end, the face of the line" $ do
      let src = "あ[link \"https://example.com/\": いう]え\n"
      (geom, pl) <- layoutOk horizontalStyle src []
      pdf <- miniPdf fakeProvider True horizontalStyle src []
      ds <- glyphs pdf
      case (annotations pdf, linkRuns pl, columnsFor geom 1) of
        ([(u, [x0, y0, x1, y1])], [(s0, e0)], col : _) -> do
          u @?= "https://example.com/"
          near x0 (toPt (rectX col + s0))
          near (x1 - x0) (toPt (e0 - s0))
          near (x1 - x0) 20
          near (y1 - y0) 10
          case [d | d <- ds, dGlyph d == fromEnum 'い'] of
            (d : _) -> near y0 (read (BC.unpack (dY d)) - 1.2)
            [] -> assertFailure "no い"
        other -> assertFailure (show other)
      annotsPerPage pdf @?= [1],
    testCase "a link over two lines is an annotation on each line, of the run of the line" $ do
      let src = T.replicate 6 "あ" <> "[link \"https://example.com/\": " <> T.replicate 10 "い" <> "]\n"
      (geom, pl) <- layoutOk horizontalStyle src []
      pdf <- miniPdf fakeProvider True horizontalStyle src []
      let as = annotations pdf
      linkRuns pl @?= [(60 * pt, 120 * pt), (0, 40 * pt)]
      map fst as @?= replicate 2 "https://example.com/"
      case columnsFor geom 1 of
        col : _ -> case [(x0, x1 - x0) | (_, [x0, _, x1, _]) <- as] of
          [(a, aw), (b, bw)] -> near a (toPt (rectX col + 60 * pt)) >> near aw 60 >> near b (toPt (rectX col)) >> near bw 40
          other -> assertFailure (show other)
        [] -> assertFailure "no column"
      annotsPerPage pdf @?= [2],
    testCase "a link over two pages: an annotation on each line, on its page" $ do
      -- 30 lines of 12 characters a page
      let src = "[link \"https://example.com/\": " <> T.replicate 400 "い" <> "]\n"
      (_, pl) <- layoutOk horizontalStyle src []
      pdf <- miniPdf fakeProvider True horizontalStyle src []
      length (linkRuns pl) @?= 34
      length (annotations pdf) @?= 34
      annotsPerPage pdf @?= [30, 4],
    testCase "vertical: a tall rectangle centred on the line, as wide as the size" $ do
      let src = "あ[link \"https://example.com/\": いう]え\n"
          s13 = toPt (maybe 0 (dimToSp 0) (parseDim "13Q"))
      pdf <- miniPdf fakeProvider True pdfStyle src []
      ds <- glyphs pdf
      case annotations pdf of
        [(_, [x0, y0, x1, y1])] -> do
          near (x1 - x0) s13
          near (y1 - y0) (2 * s13)
          case [d | d <- ds, dGlyph d == fromEnum 'い'] of
            (d : _) -> near ((x0 + x1) / 2) (read (BC.unpack (dX d)))
            [] -> assertFailure "no い"
        other -> assertFailure (show other),
    testCase "ruby inside a link: the rectangle is the face of the line of the bases, without the reading" $ do
      pdf <- miniPdf fakeProvider True horizontalStyle "あ[link \"https://example.com/\": [ruby: 漢字|かんじ]]い\n" []
      ds <- glyphs pdf
      case annotations pdf of
        [(_, [x0, y0, x1, y1])] -> do
          near (x1 - x0) 20
          near (y1 - y0) 10
          let readings = [read (BC.unpack (dY d)) :: Double | d <- ds, dSize d == "5"]
          assertBool (show readings) (not (null readings) && all (>= y1) readings)
        other -> assertFailure (show other),
    testCase "a long URL breaks after its slashes, draws no hyphen at a line end, and is not broken at a hyphen" $ do
      let u = "https://example.com/a-very-long-path/with-hyphens/"
      (_, pl) <- layoutOk horizontalStyle ("[link \"" <> u <> "\"]\n") []
      pdf <- miniPdf fakeProvider True horizontalStyle ("[link \"" <> u <> "\"]\n") []
      ds <- glyphs pdf
      let texts' = [T.concat [bcText c | Box _ c <- lineItemsOf sl] | sl <- Map.elems (plLines pl)]
          lineItemsOf sl = map fst (placeLine (slLine sl))
      assertBool (show texts') (length texts' > 1)
      T.concat texts' @?= u
      assertBool (show texts') (not (any ("-" `T.isSuffixOf`) texts') && not (any ("-" `T.isPrefixOf`) texts'))
      length [() | d <- ds, dGlyph d `elem` map fromEnum ("-\x2010" :: String)] @?= T.count "-" u
      length (annotations pdf) @?= length texts',
    testCase "a link in a heading: the copies in the table of contents and [ref-title] hold no link" $ do
      pdf <- miniPdf fakeProvider True horizontalStyle "@toc\n\n@label c\n# 章[link \"https://example.com/\": 題]\n\n本文[ref-title c]。\n" []
      map fst (annotations pdf) @?= ["https://example.com/"],
    testCase "[style url: ...] in the text is no link" $ do
      pdf <- miniPdf fakeProvider True horizontalStyle "[style url: https://example.com/]\n" []
      annotations pdf @?= []
      assertBool "no Annots" (not ("/Annots" `BS.isInfixOf` pdf)),
    testCase "the URL of an entry of the bibliography of http or https is a link; another is not" $
      withSystemTempDirectory "golem-link" $ \tmp -> do
        writeProject tmp ("bibliography = [\"refs.json\"]\n" <> miniManifest) horizontalStyle "本文[cite jlreq][cite js]。\n\n@bibliography\n" [("refs.json", refs)]
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
        pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
          [p] -> BS.readFile p
          _ -> assertFailure "no PDF"
        assertBool "the URL is a link" (not (null (annotations pdf)))
        map fst (annotations pdf) @?= map (const "https://www.w3.org/TR/jlreq/") (annotations pdf),
    testCase "a book with links: the same bytes twice, in parallel and not, and qpdf accepts it" $ do
      let src = "本文[link \"https://ja.wikipedia.org/wiki/組版\": 組版]と[link \"https://example.com/?a=1&b=(2)\"]。\n"
      a <- miniPdf fakeProvider True horizontalStyle src []
      b <- miniPdf fakeProvider False horizontalStyle src []
      c <- miniPdf fakeProvider True horizontalStyle src []
      a @?= b
      a @?= c
      assertBool "the URL in ASCII" ("/URI (https://ja.wikipedia.org/wiki/%E7%B5%84%E7%89%88)" `BS.isInfixOf` a)
      qpdfCheck a,
    testCase "a book without links has no annotation" $ do
      pdf <- miniPdf fakeProvider True horizontalStyle "本文。\n" []
      assertBool "no Annots" (not ("/Annots" `BS.isInfixOf` pdf))
  ]
  where
    refs = TE.encodeUtf8 "[{\"id\": \"jlreq\", \"type\": \"webpage\", \"title\": \"日本語組版処理の要件\", \"URL\": \"https://www.w3.org/TR/jlreq/\"}, {\"id\": \"js\", \"title\": \"Script\", \"URL\": \"javascript:alert(1)\"}]"
