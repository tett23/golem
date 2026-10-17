-- | The SVG subset of golem-pdf ADR 0009: XML, CSS and the drawing.
module Main (main) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (isLeft)
import Data.List (isSuffixOf, sort)
import Data.List.NonEmpty qualified as NE
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Svg
import Golem.Svg.Css
import Golem.Svg.Xml
import System.Directory (listDirectory)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

main :: IO ()
main = do
  outlined <- figures "../../manual-dev/images"
  sources <- figures "../../manual-dev/images/src"
  defaultMain (tests outlined sources)
  where
    figures dir = map (dir </>) . sort . filter (".svg" `isSuffixOf`) <$> listDirectory dir

svg :: Text -> BS.ByteString
svg body = TE.encodeUtf8 ("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"50\">" <> body <> "</svg>")

drawing :: Text -> IO [DrawOp]
drawing body = either (assertFailure . show) (pure . svgDrawing) (readSvg (svg body))

unsupported :: BS.ByteString -> [Unsupported]
unsupported b = case readSvg b of
  Left (SvgUnsupported us) -> NE.toList us
  _ -> []

-- | The paths of a drawing, groups flattened.
paths :: [DrawOp] -> [(Paint, [Segment])]
paths = concatMap $ \case
  DPath p s -> [(p, s)]
  DGroup _ _ ops -> paths ops

groups :: [DrawOp] -> [Matrix]
groups = concatMap $ \case
  DPath _ _ -> []
  DGroup m _ ops -> m : groups ops

tests :: [FilePath] -> [FilePath] -> TestTree
tests outlined sources =
  testGroup
    "golem-svg (golem-pdf ADR 0009)"
    [ testGroup "XML" xmlTests,
      testGroup "CSS" cssTests,
      testGroup "drawing" drawingTests,
      testGroup
        "the figures of the developer manual"
        ( [ testCase ("the outlined " <> f <> " has nothing unsupported") $ do
              b <- BS.readFile f
              either (assertFailure . show) (const (pure ())) (readSvg b)
          | f <- outlined
          ]
            <> [ testCase ("the source " <> f <> " has only text and @font-face unsupported") $ do
                   b <- BS.readFile f
                   let us = unsupported b
                   assertBool "something unsupported" (not (null us))
                   [unName u | u <- us, not (unText u)] @?= []
               | f <- sources
               ]
        )
    ]

xmlTests :: [TestTree]
xmlTests =
  [ testCase "elements, attributes, namespaces, CDATA, character and entity references" $ do
      let doc = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!-- c --><s:svg xmlns:s=\"http://www.w3.org/2000/svg\" a='1'><s:desc>&lt;&#65;&#x42;&amp;<![CDATA[<x>]]></s:desc><?pi x?></s:svg>"
      case parseXml doc of
        Right e -> do
          (elNs e, elName e) @?= ("http://www.w3.org/2000/svg", "svg")
          [(atName a, atValue a) | a <- elAttrs e] @?= [("a", "1")]
          case elChildren e of
            [NElement d] -> [t | NText t _ <- elChildren d] @?= ["<AB&<x>"]
            other -> assertFailure (show other)
        Left err -> assertFailure (T.unpack err),
    testCase "positions are lines and columns from 1" $
      case parseXml "<svg xmlns=\"http://www.w3.org/2000/svg\">\n  <rect x=\"1\"/>\n</svg>" of
        Right e -> case [c | NElement c <- elChildren e] of
          [r] -> (elPos r, map atPos (elAttrs r)) @?= (Pos 2 3, [Pos 2 9])
          other -> assertFailure (show other)
        Left err -> assertFailure (T.unpack err),
    testCase "a document that is not well formed, an internal subset and Shift_JIS are refused" $ do
      assertBool "not well formed" (isLeft (parseXml "<svg><g></svg>"))
      assertBool "internal subset" (isLeft (parseXml "<!DOCTYPE svg [<!ENTITY a \"b\">]><svg/>"))
      assertBool "Shift_JIS" (isLeft (parseXml "<?xml version=\"1.0\" encoding=\"Shift_JIS\"?><svg/>"))
      case readSvg "<svg><g></svg>" of
        Left (SvgMalformed _) -> pure ()
        other -> assertFailure (show other),
    testCase "Inkscape's elements and attributes are skipped" $ do
      let doc =
            "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:sodipodi=\"http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd\" xmlns:inkscape=\"http://www.inkscape.org/namespaces/inkscape\" width=\"10\" height=\"10\">"
              <> "<sodipodi:namedview pagecolor=\"#fff\"><inkscape:page/></sodipodi:namedview><g inkscape:label=\"L\" inkscape:groupmode=\"layer\"><rect width=\"1\" height=\"1\" sodipodi:nodetypes=\"cccc\"/></g></svg>"
      case readSvg doc of
        Right s -> length (paths (svgDrawing s)) @?= 1
        Left e -> assertFailure (show e)
  ]

fillOf :: [DrawOp] -> [Maybe Color]
fillOf = map (paFill . fst) . paths

cssTests :: [TestTree]
cssTests =
  [ testCase "presentation attributes, specificity, order and the style attribute" $ do
      let sheet = "<style>rect { fill: #0000ff } .proc { fill: #00ff00 } rect.proc { stroke: #000 } .late { fill: #ff00ff } </style>"
      ops <- drawing (sheet <> "<rect class=\"proc\" fill=\"#ff0000\" width=\"1\" height=\"1\"/><rect fill=\"#ff0000\" width=\"1\" height=\"1\"/><rect class=\"proc\" style=\"fill:#ffffff\" width=\"1\" height=\"1\"/><rect class=\"proc late\" width=\"1\" height=\"1\"/>")
      fillOf ops @?= [Just (Color 0 255 0), Just (Color 0 0 255), Just (Color 255 255 255), Just (Color 255 0 255)]
      map (fmap stColor . paStroke . fst) (paths ops) @?= [Just (Color 0 0 0), Nothing, Just (Color 0 0 0), Just (Color 0 0 0)],
    testCase "inherited properties come from the parent" $ do
      ops <- drawing "<g fill=\"red\" stroke=\"#123\" stroke-width=\"3\"><g><rect width=\"1\" height=\"1\"/></g></g>"
      fillOf ops @?= [Just (Color 255 0 0)]
      map (fmap stWidth . paStroke . fst) (paths ops) @?= [Just 3],
    testCase "specificity: an id over classes over types" $ do
      specificity (Selector (Just "rect") ["a", "b"] Nothing) @?= (0, 2, 1)
      specificity (Selector Nothing [] (Just "x")) @?= (1, 0, 0),
    testCase "a descendant combinator, !important, @font-face and @media are unsupported" $ do
      let names t = map unName (unsupported (svg ("<style>" <> t <> "</style><rect width=\"1\" height=\"1\"/>")))
      names "g rect { fill: red }" @?= ["g rect"]
      names "rect { fill: red !important }" @?= ["!important"]
      names "@font-face { font-family: a; src: url(a.otf) }" @?= ["@font-face"]
      names "@media print { rect { fill: red } }" @?= ["@media"]
      map unText (unsupported (svg "<style>@font-face { font-family: a }</style>")) @?= [True]
  ]

drawingTests :: [TestTree]
drawingTests =
  [ testCase "a rect, a line and a path with relative commands" $ do
      ops <- drawing "<rect x=\"1\" y=\"2\" width=\"3\" height=\"4\"/><line x1=\"0\" y1=\"0\" x2=\"5\" y2=\"5\" stroke=\"#000\"/><path d=\"m 10 10 l 5 0 h 5 v 5 H 0 V 1 z\"/>"
      map snd (paths ops)
        @?= [ [MoveTo (1, 2), LineTo (4, 2), LineTo (4, 6), LineTo (1, 6), ClosePath],
              [MoveTo (0, 0), LineTo (5, 5)],
              [MoveTo (10, 10), LineTo (15, 10), LineTo (20, 10), LineTo (20, 15), LineTo (0, 15), LineTo (0, 1), ClosePath]
            ],
    testCase "curves: C, S, Q and T, relative and absolute" $ do
      ops <- drawing "<path d=\"M0 0 C 1 1 2 1 3 0 S 5 -1 6 0 q 1 1 2 0 t 2 0\"/>"
      case map snd (paths ops) of
        [MoveTo (0, 0) : CurveTo (1, 1) (2, 1) (3, 0) : CurveTo (4, -1) (5, -1) (6, 0) : rest] -> do
          length rest @?= 2
          [p | CurveTo _ _ p <- rest] @?= [(8, 0), (10, 0)]
        other -> assertFailure (show other),
    testCase "a circle is four curves, closed" $ do
      ops <- drawing "<circle cx=\"10\" cy=\"10\" r=\"5\"/>"
      case map snd (paths ops) of
        [MoveTo (15, 10) : rest] -> (length [() | CurveTo {} <- rest], last rest) @?= (4, ClosePath)
        other -> assertFailure (show other),
    testCase "an arc ends where it says and is cut into spans of 90 degrees or less" $ do
      ops <- drawing "<path d=\"M 0 0 A 10 10 0 0 1 20 0 a 10 5 0 1 0 0 10\"/>"
      case map snd (paths ops) of
        [MoveTo (0, 0) : rest] -> do
          let ends = [p | CurveTo _ _ p <- rest]
          -- two half turns: two spans each
          length ends @?= 2 + 2
          (ends !! 1, last ends) @?= ((20, 0), (20, 10))
        other -> assertFailure (show other),
    goldenVsString "rotate(30) and an arc" "test/golden/rotate-arc.txt" $ do
      let doc = svg "<g transform=\"rotate(30) translate(1,2)\"><path d=\"M0 0 A 5 3 20 0 1 7 4\"/></g>"
      pure (BL.fromStrict (TE.encodeUtf8 (T.pack (either show (show . svgDrawing) (readSvg doc)) <> "\n"))),
    testCase "the same input gives the same drawing" $ do
      let doc = svg "<g transform=\"rotate(17 3 4) skewX(10)\"><path d=\"M0 0 A 5 3 20 1 1 7 4 Z\" stroke=\"blue\" stroke-dasharray=\"1 2 3\"/></g>"
      readSvg doc @?= readSvg doc,
    testCase "a marker with auto-start-reverse is reversed at the start and along the path at the end" $ do
      ops <- drawing "<defs><marker id=\"a\" viewBox=\"0 0 10 10\" refX=\"10\" refY=\"5\" markerWidth=\"9\" markerHeight=\"9\" orient=\"auto-start-reverse\"><path d=\"M0,0 L10,5 L0,10 z\"/></marker></defs><path d=\"M 10 10 L 30 10\" stroke=\"#000\" marker-start=\"url(#a)\" marker-end=\"url(#a)\"/>"
      case [m | DGroup m (Just _) _ <- ops] of
        [Matrix a b _ _ e f, Matrix a' b' _ _ e' f'] -> do
          -- the viewBox of 10 in 9: refX 10, refY 5 are at 9, 4.5 from the vertex
          ((a, b), (e, f)) @?= ((-1, 0), (19, 29 / 2))
          ((a', b'), (e', f')) @?= ((1, 0), (21, 11 / 2))
        other -> assertFailure (show other),
    testCase "unsupported elements and values are all collected, with lines and columns" $ do
      let us = unsupported (svg "\n<linearGradient id=\"g\"/>\n<use href=\"#g\"/>\n<rect width=\"1\" height=\"1\" opacity=\"0.5\"/>")
      [(unName u, unLine u) | u <- us] @?= [("linearGradient", 2), ("use", 3), ("opacity", 4)]
      map unText us @?= [False, False, False],
    testCase "text, tspan and textPath are text" $ do
      let us = unsupported (svg "<text>a<tspan>b</tspan></text><textPath/>")
      [(unName u, unText u) | u <- us] @?= [("text", True), ("textPath", True)],
    testCase "outlined text: font properties on a path and a g are read" $ do
      ops <- drawing "<g style=\"font-family:Noto Sans JP;font-size:12px;text-anchor:middle\" aria-label=\"文字\"><path style=\"font-family:Noto Sans JP;font-size:12px;text-anchor:middle;dominant-baseline:central\" d=\"M0 0 L1 1\"/></g>"
      length (paths ops) @?= 1,
    testCase "the viewBox maps to the width and the height" $
      case readSvg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"20mm\" height=\"10mm\" viewBox=\"0 0 200 100\"><rect width=\"1\" height=\"1\"/></svg>" of
        Right s -> do
          let (w, h) = svgSize s
          w / h @?= 2
          length (groups (svgDrawing s)) @?= 1
        Left e -> assertFailure (show e),
    testCase "an SVG without a size is malformed" $
      case readSvg "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"1\" height=\"1\"/></svg>" of
        Left (SvgMalformed _) -> pure ()
        other -> assertFailure (show other)
  ]
