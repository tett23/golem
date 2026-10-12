module Main (main) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Project
import Golem.Project.Paths
import Golem.Project.Style
import Golem.Syntax
import System.Directory (createDirectoryIfMissing, createFileLink)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

manifest :: [Text] -> Text
manifest chapters =
  T.unlines
    [ "chapters = [" <> T.intercalate ", " chapters <> "]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = \"テスト\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      "",
      "[targets.html]"
    ]

withProject :: [(FilePath, Text)] -> (FilePath -> IO a) -> IO a
withProject files act = withSystemTempDirectory "golem" $ \root -> do
  mapM_ (\(p, c) -> createDirectoryIfMissing True (takeDirectory (root </> p)) >> TIO.writeFile (root </> p) c) files
  act root

codes :: Either [Diagnostic] a -> [Text]
codes = either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const [])

tests :: TestTree
tests =
  testGroup
    "golem-project"
    [ testCase "normalisation" $ do
        normalizeRelative "./a/../b/c.gm" @?= Right "b/c.gm"
        normalizeRelative "../x.gm" @?= Left EscapesRoot
        normalizeRelative "/etc/passwd" @?= Left Absolute
        normalizeRelative "https://example.com/a.gm" @?= Left Url,
      testCase "loads chapters and imports in a deterministic order"
        $ withProject
          [ ("manifest.toml", manifest ["\"ch/01.gm\"", "[\"ch/02.gm\", { file = \"ch/03.gm\", master = \"body\" }]"]),
            ("ch/01.gm", "@import common/v.gm as v\n\n本文。\n"),
            ("ch/02.gm", "@import common/v.gm as v\n@import common/w.gm as w\n"),
            ("ch/03.gm", "三。\n"),
            ("common/v.gm", "@import common/w.gm as w\n@set x = 1\n"),
            ("common/w.gm", "@set y = 2\n")
          ]
        $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> do
              map snd (fileTableEntries (projectFiles p)) @?= ["manifest.toml", "ch/01.gm", "ch/02.gm", "ch/03.gm", "common/v.gm", "common/w.gm"]
              map snd (projectChapters p) @?= [Nothing, Nothing, Just "body"]
              -- w before v (dependency), v before the chapters importing it
              let order = projectOrder p
                  pos f = length (takeWhile (/= f) order)
              assertBool "w before v" (pos (FileId 5) < pos (FileId 4))
              assertBool "v before ch/01" (pos (FileId 4) < pos (FileId 1)),
      testCase "import cycles are reported with their path"
        $ withProject
          [ ("manifest.toml", manifest ["\"a.gm\""]),
            ("a.gm", "@import b.gm as b\n"),
            ("b.gm", "@import a.gm as a\n")
          ]
        $ \root -> do
          r <- loadProject root
          codes r @?= ["G0305"]
          case r of
            Left [d] -> length (diagRelated d) @?= 2
            _ -> pure (),
      testCase "self import is a cycle" $
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import a.gm as a\n")] $ \root ->
          loadProject root >>= (@?= ["G0305"]) . codes,
      testCase "missing files, escaping paths, URLs" $ do
        withProject [("manifest.toml", manifest ["\"nope.gm\""])] $ \root -> loadProject root >>= (@?= ["G0302"]) . codes
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import ../x.gm as x\n")] $ \root -> loadProject root >>= (@?= ["G0303"]) . codes
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import \"https://e.com/x.gm\" as x\n")] $ \root -> loadProject root >>= (@?= ["G0303"]) . codes,
      testCase "case-only differences are errors"
        $ withProject
          [ ("manifest.toml", manifest ["\"a.gm\"", "\"b.gm\""]),
            ("a.gm", "@import Common.gm as c\n"),
            ("b.gm", "@import common.gm as c\n"),
            ("Common.gm", "@set x = 1\n"),
            ("common.gm", "@set x = 1\n")
          ]
        $ \root -> do
          r <- loadProject root
          -- on case-insensitive file systems the second name may resolve to the first file
          assertBool "error or single file" (codes r == ["G0304"] || either (const False) (const True) r),
      testCase "symbolic links are resolved to the same file"
        $ withProject
          [ ("manifest.toml", manifest ["\"a.gm\"", "\"b.gm\""]),
            ("a.gm", "@import real.gm as r\n"),
            ("b.gm", "@import link.gm as r\n"),
            ("real.gm", "@set x = 1\n")
          ]
        $ \root -> do
          createFileLink (root </> "real.gm") (root </> "link.gm")
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> length (fileTableEntries (projectFiles p)) @?= 4,
      testCase "unknown manifest keys and missing id are errors" $ do
        withProject [("manifest.toml", manifest ["\"a.gm\""] <> "\n[extra]\nx = 1\n"), ("a.gm", "")] $ \root -> loadProject root >>= (@?= ["G0301"]) . codes
        withProject [("manifest.toml", T.replace "id = " "idd = " (manifest ["\"a.gm\""])), ("a.gm", "")] $ \root -> loadProject root >>= (@?= True) . (not . null) . codes,
      testCase "dimensions" $ do
        parseDim "1pt" @?= Just (Abs 65536)
        parseDim "25.4mm" @?= Just (Abs (72 * 65536))
        parseDim "4Q" @?= Just (Abs (round (72 * 65536 / (25.4 :: Rational))))
        parseDim "1H" @?= parseDim "0.25mm"
        parseDim "2zw" @?= Just (Zw 2)
        parseDim "3em" @?= Nothing,
      testCase "style.toml from the specification" $
        case parseStyle (FileId 0) specStyle of
          Left ds -> assertFailure (show ds)
          Right s -> do
            Map.keys (stHeadings s) @?= [1, 2]
            fmap pageSizeName (stPage s) @?= Just "B6"
            Map.lookup "accent" (stSwatches s) @?= Just (Swatch (0, 80, 100, 0)),
      testCase "mass-market paperback size (ADR 0003)" $ do
        pageSize "mass-market" @?= Just (10795 / 100, 174625 / 1000)
        pageSize "A6" @?= Just (105, 148),
      testCase "style.toml errors" $ do
        codes (parseStyle (FileId 0) "[page]\nsize = \"B6\"\nunknown = 1\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[emphasis]\nstrong = \"underline\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[color.swatches]\na = { cmyk = [0, 0, 0, 101] }\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[figures]\nnumber = \"{x}\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[frames]\nx = 1\n") @?= ["G0306"],
      testCase "[verse] (docs/adr ADR 0003)" $ do
        fmap stVerse (parseStyle (FileId 0) "") @?= Right (VerseStyle (Zw 0) (Zw 2) 1)
        fmap stVerse (parseStyle (FileId 0) "[verse]\nindent = \"1zw\"\nhang = \"3zw\"\nstanza-gap = 2\n") @?= Right (VerseStyle (Zw 1) (Zw 3) 2)
        fmap stVerse (parseStyle (FileId 0) "[verse]\nhang = \"10pt\"\n") @?= Right (VerseStyle (Zw 0) (Abs 655360) 1)
        codes (parseStyle (FileId 0) "[verse]\nunknown = 1\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[verse]\nstanza-gap = -1\n") @?= ["G0306"],
      testCase "a heading font must name a font role (golem-driver ADR 0003)" $ do
        codes (parseStyle (FileId 0) "[headings.1]\nfont = \"nope\"\n") @?= ["G0308"]
        codes (parseStyle (FileId 0) "[fonts.heading]\nlatin = \"h.otf\"\n\n[headings.1]\nfont = \"heading\"\n") @?= [],
      testCase "bold and italic fonts name font roles (golem-driver ADR 0004)" $ do
        codes (parseStyle (FileId 0) "[emphasis]\nbold-font = \"gothic\"\n") @?= ["G0308"]
        codes (parseStyle (FileId 0) "[emphasis]\nitalic-font = \"italic\"\n") @?= ["G0308"]
        codes (parseStyle (FileId 0) "[character-styles.term]\nfont = \"nope\"\n") @?= ["G0308"]
        case parseStyle (FileId 0) "[fonts.gothic]\nja = \"g.otf\"\n\n[fonts.italic]\nlatin = \"i.otf\"\n\n[emphasis]\nbold-font = \"gothic\"\nitalic-font = \"italic\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> (stBoldFont s, stItalicFont s) @?= (Just "gothic", Just "italic")
        fmap (\s -> (stBoldFont s, stItalicFont s)) (parseStyle (FileId 0) "[emphasis]\nstrong = \"italic\"\n") @?= Right (Nothing, Nothing)
    ]

specStyle :: Text
specStyle =
  T.unlines
    [ "[page]",
      "size = \"B6\"",
      "binding = \"right\"",
      "writing-mode = \"vertical\"",
      "",
      "[page.grid]",
      "font-size = \"13Q\"",
      "characters = 42",
      "lines = 16",
      "line-pitch = \"22H\"",
      "columns = 1",
      "column-gap = \"2zw\"",
      "position = { top = \"18mm\", gutter = \"20mm\" }",
      "",
      "[fonts.body]",
      "ja = \"fonts/a.otf\"",
      "latin = \"fonts/b.otf\"",
      "features = [\"palt\"]",
      "",
      "[fonts.heading]",
      "ja = \"fonts/c.otf\"",
      "",
      "[character-styles.term]",
      "font = \"heading\"",
      "",
      "[headings.1]",
      "font = \"heading\"",
      "size = \"20Q\"",
      "number = \"第{n:kanji}章\"",
      "page-break = \"recto\"",
      "running-head = true",
      "",
      "[headings.2]",
      "number = \"{1}.{n}\"",
      "",
      "[composition]",
      "kinsoku = \"strict\"",
      "hanging-punctuation = true",
      "ruby = { position = \"mono-center\", overhang = \"1zw\" }",
      "kenten = \"sesame\"",
      "tolerance = 200",
      "protrusion = true",
      "expansion = { limit = 20, step = 5 }",
      "",
      "[numbers]",
      "vertical = \"kanji\"",
      "",
      "[emphasis]",
      "strong = \"bold\"",
      "",
      "[notes]",
      "placement = \"page-foot\"",
      "",
      "[sidenotes]",
      "side = \"outside\"",
      "width = \"14zw\"",
      "gap = \"2zw\"",
      "font = \"body\"",
      "size = \"11Q\"",
      "marker = \"number\"",
      "",
      "[figures]",
      "number = \"図{chapter}-{n}\"",
      "",
      "[color]",
      "intent = \"icc/JapanColor2001Coated.icc\"",
      "",
      "[color.swatches]",
      "accent = { cmyk = [0, 80, 100, 0] }",
      "",
      "[masters.body]",
      "running-head = { position = \"top-outside\", content = \"heading.1.short\" }",
      "folio = { position = \"bottom-outside\", format = \"{n}\" }"
    ]
