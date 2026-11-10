{- | The boxes of paragraph styles through the driver (docs/adr/0271): the
CSS of div.box-<name>, with the radius of the corners that are rounded
only, and a book with boxes built to PDF and HTML. No punctuation hangs
inside a box (docs/adr/0279): H1 to H3.
-}
module BoxesSpec (boxesTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Length (Sp (..))
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The swatches of the tests.
swatches :: T.Text
swatches = "[color.swatches]\npale = { cmyk = [8, 0, 0, 0] }\nblue = { cmyk = [100, 60, 0, 0] }\n\n"

-- | The rule of div.box-<name> in the style.css of a book of the style given (a paragraph of the style written), if any.
ruleOf :: T.Text -> T.Text -> IO (Maybe T.Text)
ruleOf name toml = withSystemTempDirectory "golem-boxes-css" $ \tmp -> do
  writeProject tmp (miniManifest <> "\n[targets.html]\n") (horizontalStyle <> fakeBody <> "\n" <> TE.encodeUtf8 toml) ("@style " <> name <> "\n本文。\n") fakeFontFiles
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider}
  filter isError (brDiagnostics r) @?= []
  css <- TIO.readFile (tmp </> "build/html/style.css")
  pure
    ( case filter (T.isPrefixOf ("div.box-" <> name <> " {")) (T.lines css) of
        l : _ -> Just l
        [] -> Nothing
    )

-- | The declarations of a rule.
declsOf :: T.Text -> T.Text -> IO (Maybe [T.Text])
declsOf name toml = fmap (map T.strip . filter (not . T.null . T.strip) . T.splitOn ";" . T.dropEnd 1 . T.drop 1 . T.dropWhile (/= '{')) <$> ruleOf name toml

radii :: Maybe [T.Text] -> [T.Text]
radii = maybe [] (filter ("-radius" `T.isInfixOf`))

boxesTests :: TestTree
boxesTests =
  testGroup
    "the boxes of paragraph styles through the driver (docs/adr/0271)"
    $ [ testCase "HTML: the declarations of the box; a style without one has none" $ do
          d <- declsOf "column" (swatches <> "[paragraph-styles.column]\nbackground = \"pale\"\npadding = \"1zw\"\nborder = \"blue\"\nborder-width = \"0.5pt\"\nborder-style = \"dashed\"\nborder-sides = [\"before\", \"start\"]\nindent = \"2zw\"\n")
          d
            @?= Just
              [ "background-color: rgb(235, 255, 255)",
                "padding: 1em",
                "border-block-start: 0.5pt dashed rgb(0, 102, 255)",
                "border-inline-start: 0.5pt dashed rgb(0, 102, 255)",
                "margin-inline-start: 2em"
              ]
          none <- declsOf "plain" (swatches <> "[paragraph-styles.plain]\nindent = \"1zw\"\n")
          none @?= Nothing,
        testCase "HTML: the radius of the corners rounded only: every corner of a box without a border, those of two sides drawn, none of a radius of 0" $ do
          bg <- declsOf "a" (swatches <> "[paragraph-styles.a]\nbackground = \"pale\"\nborder-radius = \"2mm\"\nborder-sides = [\"start\"]\n")
          radii bg @?= ["border-start-start-radius: 5.6693pt", "border-start-end-radius: 5.6693pt", "border-end-start-radius: 5.6693pt", "border-end-end-radius: 5.6693pt"]
          one <- declsOf "a" (swatches <> "[paragraph-styles.a]\nborder = \"blue\"\nborder-radius = \"2mm\"\nborder-sides = [\"start\"]\n")
          radii one @?= []
          two <- declsOf "a" (swatches <> "[paragraph-styles.a]\nborder = \"blue\"\nborder-radius = \"1zw\"\nborder-sides = [\"before\", \"start\", \"end\"]\n")
          radii two @?= ["border-start-start-radius: 1em", "border-start-end-radius: 1em"]
          zero <- declsOf "a" (swatches <> "[paragraph-styles.a]\nbackground = \"pale\"\nborder-radius = \"0pt\"\n")
          radii zero @?= [],
        testCase "PDF and HTML: a book of two boxed paragraphs and a box of one side builds, the paragraphs of one box in one div" $
          withSystemTempDirectory "golem-boxes" $ \tmp -> do
            let style = horizontalStyle <> fakeBody <> "\n" <> encode swatches <> "[paragraph-styles.column]\nbackground = \"pale\"\nborder-radius = \"1zw\"\n\n[paragraph-styles.title]\nbackground = \"pale\"\nborder-radius = \"1zw\"\n\n[paragraph-styles.caution]\nborder = \"blue\"\nborder-width = \"2pt\"\nborder-sides = [\"start\"]\nindent = \"1zw\"\n"
                source = "前。\n\n@style title\n題。\n\n@style column\n本文。\n\n@style caution\n注意。\n\n後。\n"
            writeProject tmp (miniManifest <> "\n[targets.html]\n") style source fakeFontFiles
            r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf, TargetHtml], optFonts = fakeProvider}
            filter isError (brDiagnostics r) @?= []
            page <- TIO.readFile (tmp </> "build/html/a.xhtml")
            assertBool (T.unpack page) ("<div class=\"box box-title\">\n<p class=\"ps-title\">題。</p>\n<p class=\"ps-column\">本文。</p>\n</div>\n<div class=\"box box-caution\">\n<p class=\"ps-caution\">注意。</p>\n</div>" `T.isInfixOf` page),
        testCase "B1, B5: PDF: a box of @style-def is drawn as one of style.toml, and not without the keys" $ do
          let keys = [("background", "\"pale\"", "pale"), ("border", "\"blue\"", "blue"), ("border-width", "\"2pt\"", "2pt"), ("border-style", "\"dashed\"", "dashed"), ("border-sides", "[\"before\", \"start\"]", "before,start"), ("border-radius", "\"1zw\"", "1zw"), ("padding", "\"1zw\"", "1zw")]
              base = horizontalStyle <> encode swatches
              source = "前。\n\n@style column\n本文。\n\n後。\n"
              draw style src = miniPdf fakeProvider True style src [] >>= pageContents
          toml <- draw (base <> "[paragraph-styles.column]\n" <> encode (T.concat [k <> " = " <> v <> "\n" | (k, v, _) <- keys])) source
          local <- draw base ("@style-def paragraph column" <> T.concat [" " <> k <> "=" <> v | (k, _, v) <- keys] <> "\n\n" <> source)
          plain <- draw base ("@style-def paragraph column\n\n" <> source)
          assertBool "the box changes the page" (toml /= plain)
          local @?= toml
      ]
      <> hangingTests
  where
    encode = TE.encodeUtf8

{- | The styles of the tests of docs/adr/0279, the horizontal (12
characters a line) and the vertical (42) one, each with its measure.
-}
hangingStyles :: [(String, BS.ByteString, Int)]
hangingStyles = [("horizontal", horizontalStyle, 12), ("vertical", pdfStyle, 42)]

{- | A book of a measure of n characters: boxed paragraphs whose full
stops and commas fall one character past the line or end it exactly, a
closing bracket past the line, a box of padding 0
with a border, two paragraphs of one box, a box of a stanza, a box long
enough to be split across pages, and the same text without a box. The
characters of the boxed paragraphs are か, き, く, け and こ; those of the
paragraph without a box are あ.
-}
hangingBook :: Int -> T.Text
hangingBook n =
  let r k c = T.replicate k (T.singleton c)
      inner = n - 1
   in T.unlines
        [ "@style column",
          r inner 'か' <> "。" <> r inner 'か' <> "、" <> r 3 'か',
          "",
          "@style framed",
          r (n - 1) 'か' <> "。" <> r n 'か' <> "」" <> r 2 'か',
          "",
          "@style framed",
          r n 'き' <> "。" <> r n 'き' <> "、" <> r 2 'き',
          "",
          "@style column",
          r inner 'こ' <> "、" <> r 2 'こ',
          "",
          "@style column",
          r inner 'こ' <> "。" <> r 2 'こ',
          "",
          "@style stanza",
          r inner 'く' <> "。" <> r 1 'く',
          r inner 'く' <> "、" <> r 1 'く',
          "",
          "@style column",
          T.concat (replicate 40 (r inner 'け' <> "。")),
          "",
          r n 'あ' <> "。" <> r 3 'あ'
        ]

-- | The style of a book of docs/adr/0279: the composition and the boxed paragraph styles.
hangingStyle :: BS.ByteString -> Bool -> Bool -> BS.ByteString
hangingStyle base hanging protrusion =
  base
    <> TE.encodeUtf8
      ( "\n[composition]\nhanging-punctuation = "
          <> bool hanging
          <> "\nprotrusion = "
          <> bool protrusion
          <> "\n\n"
          <> swatches
          <> "[paragraph-styles.column]\nbackground = \"pale\"\n\n[paragraph-styles.framed]\nborder = \"blue\"\npadding = \"0pt\"\n\n[paragraph-styles.stanza]\nbackground = \"pale\"\nline-breaks = \"keep\"\n"
      )
  where
    bool b = if b then "true" else "false"

-- | The lines of a layout, each its text, the line and its indent.
linesOf :: PdfLayout -> [(T.Text, (Line, Sp))]
linesOf pl = [(T.concat [bcText c | Box _ c <- lineItems (slLine sl)], (slLine sl, slIndent sl)) | sl <- Map.elems (plLines pl)]

-- | The lines of the boxed paragraphs of 'hangingBook'.
boxedLines :: PdfLayout -> [(T.Text, (Line, Sp))]
boxedLines = filter (T.any (`elem` ("かきくけこ" :: String)) . fst) . linesOf

-- | The boxes of full stops and commas in the lines of the boxed paragraphs that protrude at their ends.
hangingBoxes :: PdfLayout -> [(T.Text, Sp)]
hangingBoxes pl = [(t, bcProtrudeEnd c) | (t, (l, _)) <- boxedLines pl, Box _ c <- lineItems l, bcText c `elem` ["。", "、"], bcProtrudeEnd c /= 0]

hangingTests :: [TestTree]
hangingTests =
  [ testCase (name <> ": H1, H2: no punctuation hangs inside a box; its lines are those of a book without hanging-punctuation (docs/adr/0279)") $
      forM_ [False, True] $ \protrusion -> do
        (_, on) <- layoutOk (hangingStyle base True protrusion) (hangingBook n) []
        (_, off) <- layoutOk (hangingStyle base False protrusion) (hangingBook n) []
        assertBool "the box split across pages has lines" (length (boxedLines on) > 40)
        take 3 (hangingBoxes on) @?= []
        map snd (boxedLines on) @?= map snd (boxedLines off)
  | (name, base, n) <- hangingStyles
  ]
    <> [ testCase (name <> ": H3: a full stop of a paragraph without a box still hangs (docs/adr/0279)") $ do
           (_, on) <- layoutOk (hangingStyle base True False) (hangingBook n) []
           let plain = [l | (t, (l, _)) <- linesOf on, T.any (== 'あ') t]
           assertBool (show (map lineProtrusion plain)) (any ((> 0) . snd . lineProtrusion) plain)
       | (name, base, n) <- hangingStyles
       ]
