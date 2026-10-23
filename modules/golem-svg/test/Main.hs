-- | The SVG subset of golem-pdf ADR 0009: XML, CSS and the drawing.
module Main (main) where

import ActiveSpec qualified
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
import NumberSpec qualified
import SecuritySpec qualified
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
  Left (SvgUnsupported ps) -> spUnsupported ps
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
      testGroup "shapes and what hides them" shapeTests,
      testGroup "transforms" transformTests,
      testGroup "colours" colourTests,
      testGroup "strokes" strokeTests,
      testGroup "the size and the viewBox" sizeTests,
      SecuritySpec.tests,
      ActiveSpec.tests,
      NumberSpec.numberTests,
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
    testGroup
      "documents that are not well formed are refused"
      [ testCase name $ case parseXml doc of
          Left _ -> pure ()
          Right e -> assertFailure ("read as " <> show e)
      | (name, doc) <-
          [ ("an attribute twice", "<svg a=\"1\" a=\"2\"/>"),
            ("an attribute value without quotes", "<svg a=1/>"),
            ("an unknown entity reference", "<svg>&nbsp;</svg>"),
            ("a reference without its semicolon", "<svg>&amp</svg>"),
            ("a character reference to 0", "<svg>&#0;</svg>"),
            ("a character reference to a surrogate", "<svg>&#xD800;</svg>"),
            ("a character reference beyond U+10FFFF", "<svg>&#x110000;</svg>"),
            ("an end tag of another element", "<svg><g></h></svg>"),
            ("something after the root", "<svg/><svg/>"),
            ("a comment that is not closed", "<svg><!-- c</svg>"),
            ("bytes that are not UTF-8", "<svg>\xff</svg>")
          ]
      ],
    testCase "a byte order mark, references in attribute values and the largest character reference are read" $
      case parseXml "\xEF\xBB\xBF<svg a=\"&lt;&#x10FFFF;\"/>" of
        Right e -> map atValue (elAttrs e) @?= ["<\x10FFFF"]
        Left err -> assertFailure (T.unpack err),
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
    testCase "a style sheet: comments, a list of selectors, the universal selector, an id" $
      parseStylesheet "/* a comment */ rect, .a { fill: red } *{stroke:blue;} #x { FILL : #000 }"
        @?= ( [ Rule [Selector (Just "rect") [] Nothing, Selector Nothing ["a"] Nothing] [("fill", "red")],
                Rule [Selector Nothing [] Nothing] [("stroke", "blue")],
                Rule [Selector Nothing [] (Just "x")] [("fill", "#000")]
              ],
              []
            ),
    testCase "problems are at their offset in the text, comments counted" $
      -- "/* xx */ " is 9 characters; the selector starts after it
      snd (parseStylesheet "/* xx */ g rect { fill: red }") @?= [CssProblem 9 "g rect" False],
    testCase "an at-rule with nested blocks is skipped as a whole; the rule after it is read" $
      parseStylesheet "@media print { rect { fill: red } } circle { fill: blue }"
        @?= ([Rule [Selector (Just "circle") [] Nothing] [("fill", "blue")]], [CssProblem 0 "@media" False]),
    testCase "a rule without a block is a problem" $
      snd (parseStylesheet "rect") @?= [CssProblem 0 "CSS の規則" False],
    testCase "a declaration without a colon is a problem at its offset; empty ones are skipped" $
      parseDeclarations "fill: red;; stroke" @?= ([("fill", "red")], [CssProblem 12 "stroke" False]),
    testCase "selects: the type, every class and the id must match" $ do
      selects (Selector (Just "rect") ["a"] Nothing) "rect" ["a", "b"] Nothing @?= True
      selects (Selector (Just "rect") ["a", "c"] Nothing) "rect" ["a", "b"] Nothing @?= False
      selects (Selector (Just "rect") [] Nothing) "circle" [] Nothing @?= False
      selects (Selector Nothing [] (Just "x")) "rect" [] (Just "y") @?= False
      selects (Selector Nothing [] Nothing) "rect" [] Nothing @?= True,
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
    testCase "numbers: a fraction without digits before it, a second point that starts a new number, exponents" $ do
      ops <- drawing "<path d=\"M.5.5L1e1-1E0l+2-.5e1\"/>"
      map snd (paths ops) @?= [[MoveTo (1 / 2, 1 / 2), LineTo (10, -1), LineTo (12, -6)]],
    testCase "the flags of an arc are one digit each, with or without a separator (SVG 1.1 path grammar)" $ do
      compact <- drawing "<path d=\"M0 0A5 5 0 1010 0a5 5 0 0110 0\"/>"
      spaced <- drawing "<path d=\"M0 0A5 5 0 1 0 10 0a5 5 0 0 1 10 0\"/>"
      map snd (paths compact) @?= map snd (paths spaced),
    testCase "an arc flag that is not 0 or 1 is unsupported" $
      map unName (unsupported (svg "<path d=\"M0 0A5 5 0 2 0 10 0\"/>")) @?= ["d"],
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
    testCase "an arc to its own start draws nothing" $ do
      ops <- drawing "<path d=\"M 5 5 A 1 1 0 0 1 5 5 L 6 6\"/>"
      map snd (paths ops) @?= [[MoveTo (5, 5), LineTo (6, 6)]],
    testCase "an arc with a radius of 0 is a straight line" $ do
      ops <- drawing "<path d=\"M 0 0 A 0 5 0 0 1 10 0\"/>"
      map snd (paths ops) @?= [[MoveTo (0, 0), LineTo (10, 0)]],
    testGroup
      "radii too small are scaled up to a half circle; the sweep flag picks its side"
      [ testCase (name <> " passes near " <> show (fromRational (fst mid) :: Double, fromRational (snd mid) :: Double)) $ do
          ops <- drawing ("<path d=\"M 0 0 A " <> radii <> " 0 0 " <> flag <> " 10 0\"/>")
          case map snd (paths ops) of
            [[MoveTo (0, 0), CurveTo _ _ (mx, my), CurveTo _ _ end]] -> do
              -- a radius of 5 from the centre (5, 0): the middle of the arc is 5 above or below it
              assertBool (show (mx, my)) (abs (mx - fst mid) < 1 / 10000 && abs (my - snd mid) < 1 / 10000)
              end @?= (10, 0)
            other -> assertFailure (show other)
      | (name, radii, flag, mid) <-
          [ ("sweep 1", "1 1", "1", (5, -5)),
            ("sweep 0", "1 1", "0", (5, 5)),
            ("negative radii", "-1 -1", "1", (5, -5))
          ]
      ],
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

colourTests :: [TestTree]
colourTests =
  [ testCase (T.unpack v <> " is " <> show c) $ do
      ops <- drawing ("<rect fill=\"" <> v <> "\" width=\"1\" height=\"1\"/>")
      fillOf ops @?= [c]
  | (v, c) <-
      [ ("#abc", Just (Color 170 187 204)),
        ("#AbCdEf", Just (Color 171 205 239)),
        ("rgb(255, 0, 10)", Just (Color 255 0 10)),
        ("rgb(1 2 3)", Just (Color 1 2 3)),
        -- 50% of 255 is 127.5, rounded half to even
        ("rgb(100%, 50%, 0%)", Just (Color 255 128 0)),
        ("rgb(300, 0, 0)", Just (Color 255 0 0)),
        ("RED", Just (Color 255 0 0)),
        ("none", Nothing),
        ("transparent", Nothing)
      ]
  ]
    <> [ testCase "currentColor is the color property" $ do
           ops <- drawing "<g color=\"#010203\"><rect fill=\"currentColor\" width=\"1\" height=\"1\"/></g>"
           fillOf ops @?= [Just (Color 1 2 3)],
         testCase "the fill is black when nothing says otherwise" $ do
           ops <- drawing "<rect width=\"1\" height=\"1\"/>"
           fillOf ops @?= [Just (Color 0 0 0)]
       ]
    <> [ testCase (T.unpack v <> " is unsupported") $
           map unName (unsupported (svg ("<rect fill=\"" <> v <> "\" width=\"1\" height=\"1\"/>"))) @?= ["fill"]
       | v <- ["#12", "#12345", "#ggg", "rgb(1, 2)", "nocolour"]
       ]

strokeOf :: Text -> IO [Maybe Stroke]
strokeOf attrs = map (paStroke . fst) . paths <$> drawing ("<path d=\"M0 0 L1 1\" " <> attrs <> "/>")

strokeTests :: [TestTree]
strokeTests =
  [ testCase "a stroke has width 1, butt caps, miter joins, miter limit 4 and no dash by default" $ do
      ss <- strokeOf "stroke=\"#000\""
      ss @?= [Just (Stroke (Color 0 0 0) 1 CapButt JoinMiter 4 [] 0)],
    testCase "caps, joins, the miter limit, the dash array and its offset are read" $ do
      ss <- strokeOf "stroke=\"#000\" stroke-width=\"2px\" stroke-linecap=\"square\" stroke-linejoin=\"bevel\" stroke-miterlimit=\"10\" stroke-dasharray=\"1, 2\" stroke-dashoffset=\"3\""
      ss @?= [Just (Stroke (Color 0 0 0) 2 CapSquare JoinBevel 10 [1, 2] 3)],
    testCase "round caps and round joins" $ do
      ss <- strokeOf "stroke=\"#000\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
      map (fmap (\st -> (stCap st, stJoin st))) ss @?= [Just (CapRound, JoinRound)],
    testCase "a dash array of odd length is repeated to even length" $ do
      ss <- strokeOf "stroke=\"#000\" stroke-dasharray=\"1 2 3\""
      map (fmap stDash) ss @?= [Just [1, 2, 3, 1, 2, 3]],
    testCase "a dash array of zeros is a solid line" $ do
      ss <- strokeOf "stroke=\"#000\" stroke-dasharray=\"0 0\""
      map (fmap stDash) ss @?= [Just []],
    testCase "a stroke of width 0 is no stroke" $ do
      ss <- strokeOf "stroke=\"#000\" stroke-width=\"0\""
      ss @?= [Nothing],
    testCase "a miter limit of 1 is read; one under 1 is unsupported" $ do
      ss <- strokeOf "stroke=\"#000\" stroke-miterlimit=\"1\""
      map (fmap stMiterLimit) ss @?= [Just 1]
      map unName (unsupported (svg "<path d=\"M0 0 L1 1\" stroke=\"#000\" stroke-miterlimit=\"0.5\"/>")) @?= ["stroke-miterlimit"],
    testCase "opacity 1 is read; opacity 0.99 is unsupported" $ do
      ops <- drawing "<rect opacity=\"1\" fill-opacity=\"1\" stroke-opacity=\"1\" width=\"1\" height=\"1\"/>"
      length (paths ops) @?= 1
      map unName (unsupported (svg "<rect fill-opacity=\"0.99\" width=\"1\" height=\"1\"/>")) @?= ["fill-opacity"],
    testCase "a negative dash is unsupported" $
      map unName (unsupported (svg "<path d=\"M0 0 L1 1\" stroke=\"#000\" stroke-dasharray=\"1 -2\"/>")) @?= ["stroke-dasharray"]
  ]

-- | The size of a root with these attributes, and the matrices of its groups.
rootOf :: Text -> IO ((Rational, Rational), [Matrix])
rootOf attrs = case readSvg (TE.encodeUtf8 ("<svg xmlns=\"http://www.w3.org/2000/svg\" " <> attrs <> "><rect width=\"1\" height=\"1\"/></svg>")) of
  Right s -> pure (svgSize s, groups (svgDrawing s))
  Left e -> assertFailure (show e)

sizeTests :: [TestTree]
sizeTests =
  [ testCase ("the root length " <> T.unpack v <> " is 96 px") $ do
      (size, _) <- rootOf ("width=\"" <> v <> "\" height=\"" <> v <> "\"")
      size @?= (96, 96)
  | v <- ["96", "96px", "72pt", "6pc", "25.4mm", "2.54cm", "1in"]
  ]
    <> [ testCase "20mm by 10mm with the viewBox 0 0 200 100 scales by 0.378 px per unit" $ do
           -- 20 mm = 20 * 96 / 25.4 px = 9600 / 127 px; over 200 units, 48 / 127 each
           r <- rootOf "width=\"20mm\" height=\"10mm\" viewBox=\"0 0 200 100\""
           r @?= ((9600 / 127, 4800 / 127), [Matrix (48 / 127) 0 0 (48 / 127) 0 0]),
         testCase "a square viewBox in a wide root is centred (xMidYMid meet)" $ do
           r <- rootOf "width=\"200\" height=\"100\" viewBox=\"0 0 100 100\""
           r @?= ((200, 100), [Matrix 1 0 0 1 50 0]),
         testCase "xMaxYMax meet puts the viewBox at the right" $ do
           r <- rootOf "width=\"200\" height=\"100\" viewBox=\"0 0 100 100\" preserveAspectRatio=\"xMaxYMax meet\""
           r @?= ((200, 100), [Matrix 1 0 0 1 100 0]),
         testCase "xMinYMin slice fills the root and clips it" $
           case readSvg "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\" viewBox=\"10 0 100 100\" preserveAspectRatio=\"xMinYMin slice\"><rect width=\"1\" height=\"1\"/></svg>" of
             Right s -> [(m, c) | DGroup m c _ <- svgDrawing s] @?= [(Matrix 2 0 0 2 (-20) 0, Just (ClipRect 0 0 200 100))]
             Left e -> assertFailure (show e),
         testCase "none stretches the viewBox to the root" $ do
           r <- rootOf "width=\"200\" height=\"100\" viewBox=\"0 0 100 100\" preserveAspectRatio=\"none\""
           r @?= ((200, 100), [Matrix 2 0 0 1 0 0]),
         testCase "a width alone takes the height from the ratio of the viewBox" $ do
           (size, _) <- rootOf "width=\"50\" viewBox=\"0 0 100 20\""
           size @?= (50, 10),
         testCase "a viewBox alone is the size" $ do
           (size, _) <- rootOf "viewBox=\"0 0 30 40\""
           size @?= (30, 40),
         testCase "a viewBox of width 0 is unsupported" $
           map unName (unsupported "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1\" height=\"1\" viewBox=\"0 0 0 1\"/>") @?= ["viewBox"]
       ]

-- | The segments of the paths of a drawing.
segmentsOf :: Text -> IO [[Segment]]
segmentsOf body = map snd . paths <$> drawing body

shapeTests :: [TestTree]
shapeTests =
  [ testCase "corner radii larger than half the rect are cut to half its width and height" $ do
      big <- segmentsOf "<rect width=\"4\" height=\"2\" rx=\"10\"/>"
      cut <- segmentsOf "<rect width=\"4\" height=\"2\" rx=\"2\" ry=\"1\"/>"
      big @?= cut,
    testCase "ry alone is also rx" $ do
      alone <- segmentsOf "<rect width=\"4\" height=\"4\" ry=\"1\"/>"
      both <- segmentsOf "<rect width=\"4\" height=\"4\" rx=\"1\" ry=\"1\"/>"
      alone @?= both,
    testCase "a rect, a circle and an ellipse of no size draw nothing" $
      segmentsOf "<rect width=\"0\" height=\"1\"/><circle r=\"0\"/><ellipse rx=\"0\" ry=\"1\"/>" >>= (@?= []),
    testCase "a polygon is closed, a polyline is not" $
      segmentsOf "<polygon points=\"0,0 1,0 1,1\"/><polyline points=\"0 0, 1 0\" fill=\"none\" stroke=\"#000\"/>"
        >>= (@?= [[MoveTo (0, 0), LineTo (1, 0), LineTo (1, 1), ClosePath], [MoveTo (0, 0), LineTo (1, 0)]]),
    testCase "points of an odd count are unsupported" $
      map unName (unsupported (svg "<polygon points=\"0 0 1\"/>")) @?= ["points"],
    testCase "display none hides an element and its children, which cannot show again" $
      segmentsOf "<g display=\"none\"><rect width=\"1\" height=\"1\" display=\"inline\"/></g><rect style=\"display:none\" width=\"1\" height=\"1\"/>" >>= (@?= []),
    testCase "marker-mid goes on the inner vertices, scaled by the stroke width" $ do
      ops <- drawing "<defs><marker id=\"m\" markerWidth=\"2\" markerHeight=\"2\" orient=\"auto\"><path d=\"M0 0 L1 1\"/></marker></defs><path d=\"M0 0 L10 0 L20 0\" stroke=\"#000\" stroke-width=\"2\" marker-mid=\"url(#m)\"/>"
      -- the tangent at (10, 0) is (1, 0); markerUnits strokeWidth scales by 2
      [(m, c) | DGroup m c _ <- ops] @?= [(Matrix 2 0 0 2 10 0, Just (ClipRect 0 0 2 2))],
    testCase "a fixed orient in degrees turns the marker; userSpaceOnUse does not scale it" $ do
      ops <- drawing "<defs><marker id=\"m\" markerUnits=\"userSpaceOnUse\" orient=\"90deg\"><path d=\"M0 0 L1 1\"/></marker></defs><path d=\"M0 0 L10 0\" stroke=\"#000\" stroke-width=\"2\" marker-end=\"url(#m)\"/>"
      -- cos 90 = 0 and sin 90 = 1 exactly; markerWidth and markerHeight are 3 by default
      [(m, c) | DGroup m c _ <- ops] @?= [(Matrix 0 1 (-1) 0 10 0, Just (ClipRect 0 0 3 3))],
    testCase "visibility hidden hides an element, but a child may be visible again" $
      segmentsOf "<g visibility=\"hidden\"><rect width=\"1\" height=\"1\"/><rect visibility=\"visible\" x=\"2\" width=\"1\" height=\"1\"/></g>"
        >>= (@?= [[MoveTo (2, 0), LineTo (3, 0), LineTo (3, 1), LineTo (2, 1), ClosePath]])
  ]

transformTests :: [TestTree]
transformTests =
  [ testCase (T.unpack t) $ do
      ops <- drawing ("<path transform=\"" <> t <> "\" d=\"M0 0 L1 1\"/>")
      groups ops @?= [m]
  | (t, m) <-
      [ ("translate(5)", Matrix 1 0 0 1 5 0),
        ("translate(1, 2)", Matrix 1 0 0 1 1 2),
        ("scale(2)", Matrix 2 0 0 2 0 0),
        ("scale(2 3)", Matrix 2 0 0 3 0 0),
        ("matrix(1,2,3,4,5,6)", Matrix 1 2 3 4 5 6),
        -- exact at multiples of 90 degrees: cos 90 = 0, sin 90 = 1
        ("rotate(90)", Matrix 0 1 (-1) 0 0 0),
        ("rotate(-90)", Matrix 0 (-1) 1 0 0 0),
        ("rotate(450)", Matrix 0 1 (-1) 0 0 0),
        -- about (10, 0): the origin goes to (10, -10)
        ("rotate(90 10 0)", Matrix 0 1 (-1) 0 10 (-10)),
        -- the first applies last: a point is scaled, then moved
        ("translate(1,2) scale(2)", Matrix 2 0 0 2 1 2),
        ("scale(2) translate(1,2)", Matrix 2 0 0 2 2 4)
      ]
  ]
    <> [ testCase (T.unpack t <> " is unsupported") $
           map unName (unsupported (svg ("<path transform=\"" <> t <> "\" d=\"M0 0 L1 1\"/>"))) @?= ["transform"]
       | t <- ["rotate(1 2)", "skew(10)", "translate(1,2", "matrix(1 2 3)"]
       ]
