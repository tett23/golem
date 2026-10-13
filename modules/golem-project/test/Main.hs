module Main (main) where

import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
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
      indentTests,
      testCase "a caption style (golem-driver ADR 0010)" $ do
        case parseStyle (FileId 0) "[fonts.caption]\nlatin = \"c.otf\"\n\n[paragraph-styles.caption]\nfont = \"caption\"\nsize = \"8pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (paraStyle s (Just "caption") >>= psFont) @?= Just "caption"
            (paraStyle s (Just "caption") >>= psSize) @?= Just (Abs (8 * 65536))
        codes (parseStyle (FileId 0) "[figures]\ncaption = \"x\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[figures.caption]\nfont = \"body\"\n") @?= ["G0306"],
      testCase "a heading font must name a font role (golem-driver ADR 0003)" $ do
        codes (parseStyle (FileId 0) "[headings.1]\nfont = \"nope\"\n") @?= ["G0308"]
        codes (parseStyle (FileId 0) "[fonts.heading]\nlatin = \"h.otf\"\n\n[headings.1]\nfont = \"heading\"\n") @?= [],
      testCase "character style fonts name font roles (golem-driver ADR 0004)" $
        codes (parseStyle (FileId 0) "[character-styles.term]\nfont = \"nope\"\n") @?= ["G0308"],
      styleTests
    ]

-- | Character and paragraph styles (docs/adr ADR 0005).
styleTests :: TestTree
styleTests =
  testGroup
    "character and paragraph styles (docs/adr ADR 0005)"
    [ testCase "the built-in styles" $ do
        s <- parsed ""
        (charStyle s "strong" >>= csSyntheticBold) @?= Just True
        (charStyle s "italic" >>= csSyntheticItalic) @?= Just True
        (charStyle s "bold" >>= csSyntheticBold) @?= Just True
        charStyle s "nope" @?= Nothing
        (paraStyle s (Just "verse") >>= psLineBreaks) @?= Just KeepLines
        (paraStyle s (Just "verse") >>= psSpaceBetween) @?= Just 1
        (paraStyle s Nothing >>= psLineBreaks) @?= Just JoinLines
        (paraStyle s Nothing >>= psSpaceBetween) @?= Just 0
        paraStyle s (Just "nope") @?= Nothing
        noBase (paraStyle s (Just "caption")) @?= noBase (paraStyle s Nothing)
        noBase (paraStyle s (Just "sidenote")) @?= noBase (paraStyle s Nothing)
        Map.keys (stParaStyles s) @?= ["body", "caption", "sidenote", "verse"]
        Map.keys (stCharStyles s) @?= ["bold", "italic", "strong"],
      testCase "a user definition overrides the keys it writes" $ do
        s <- parsed "[paragraph-styles.caption]\nsize = \"0.8zw\"\n"
        (paraStyle s (Just "caption") >>= psSize) @?= Just (Zw (4 / 5))
        (paraStyle s (Just "caption") >>= psLineBreaks) @?= Just JoinLines
        t <- parsed "[character-styles.strong]\nbased-on = \"italic\"\n"
        (charStyle t "strong" >>= csSyntheticItalic) @?= Just True
        (charStyle t "strong" >>= csSyntheticBold) @?= Nothing
        u <- parsed "[fonts.gothic]\nja = \"g.otf\"\n\n[character-styles.bold]\nfont = \"gothic\"\n"
        (charStyle u "bold" >>= csFont) @?= Just "gothic"
        (charStyle u "bold" >>= csSyntheticBold) @?= Just True
        (charStyle u "strong" >>= csFont) @?= Just "gothic",
      testCase "a new paragraph style is based on body" $ do
        s <- parsed "[fonts.heading]\nlatin = \"h.otf\"\n\n[paragraph-styles.quote]\nfont = \"heading\"\nspace-between = 2\n"
        (paraStyle s (Just "quote") >>= psFont) @?= Just "heading"
        (paraStyle s (Just "quote") >>= psSpaceBetween) @?= Just 2
        (paraStyle s (Just "quote") >>= psLineBreaks) @?= Just JoinLines
        t <- parsed "[character-styles.term]\ncolor = \"accent\"\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
        (charStyle t "term" >>= csColor) @?= Just "accent",
      testCase "references between styles (G0313)" $ do
        codes (parseStyle (FileId 0) "[character-styles.a]\nbased-on = \"nope\"\n") @?= ["G0313"]
        codes (parseStyle (FileId 0) "[character-styles.a]\nbased-on = \"b\"\n\n[character-styles.b]\nbased-on = \"a\"\n") @?= ["G0313"]
        codes (parseStyle (FileId 0) "[paragraph-styles.a]\nbased-on = \"a\"\n") @?= ["G0313"]
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nbased-on = \"verse\"\n") @?= ["G0313"]
        codes (parseStyle (FileId 0) "[character-styles.term]\ncolor = \"accent\"\n") @?= ["G0313"],
      testCase "a paragraph style larger than the grid (G0311)" $ do
        let grid = "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n"
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.big]\nsize = \"2zw\"\n")) @?= ["G0311"]
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.small]\nsize = \"0.9zw\"\n")) @?= []
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.big]\nsize = \"14Q\"\n")) @?= ["G0311"],
      testCase "a paragraph style font must name a font role (G0308)" $
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nfont = \"nope\"\n") @?= ["G0308"],
      testCase "names and values (G0306)" $ do
        codes (parseStyle (FileId 0) "[character-styles.Term]\nsize = \"1zw\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nline-breaks = \"x\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nspace-between = -1\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nleading = 1\n") @?= ["G0306"],
      testCase "retired keys name what replaces them" $ do
        messages (parseStyle (FileId 0) "[emphasis]\nstrong = \"bold\"\n") `hasAll` ["G0306", "character-styles"]
        messages (parseStyle (FileId 0) "[verse]\nstanza-gap = 1\n") `hasAll` ["G0306", "paragraph-styles.verse"]
    ]
  where
    parsed src = either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) src)
    noBase = fmap (\d -> d {psBasedOn = Nothing})
    messages = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
    hasAll ms needles = assertBool (show ms) (not (null ms) && all (\n -> any (n `T.isInfixOf`) ms) needles)

-- | Paragraph indents (docs/adr ADR 0006).
indentTests :: TestTree
indentTests =
  testGroup
    "paragraph indents (docs/adr ADR 0006)"
    [ testCase "the defaults of body and verse" $ do
        s <- parsed ""
        indents (paraStyle s Nothing) @?= Just (Zw 0, Zw 0)
        indents (paraStyle s (Just "verse")) @?= Just (Zw 2, Zw (-2)),
      testCase "a key not written is inherited" $ do
        s <- parsed "[paragraph-styles.quote]\nindent = \"2zw\"\n"
        indents (paraStyle s (Just "quote")) @?= Just (Zw 2, Zw 0),
      testCase "signed dimensions" $ do
        parseSignedDim "-1.5zw" @?= Just (Zw (-(3 / 2)))
        fmap (\case Abs x -> x < 0; Zw _ -> False) (parseSignedDim "-3mm") @?= Just True
        parseSignedDim "2zw" @?= Just (Zw 2)
        parseSignedDim "--1zw" @?= Nothing
        parseSignedDim "-zw" @?= Nothing,
      testCase "a first line outside the type area (G0312)" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"-1zw\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"1zw\"\nfirst-line-indent = \"-2zw\"\n") @?= ["G0312"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"2zw\"\nfirst-line-indent = \"-2zw\"\n") @?= []
        let grid = "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n"
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.quote]\nindent = \"1mm\"\nfirst-line-indent = \"-1zw\"\n")) @?= ["G0312"]
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.quote]\nindent = \"4mm\"\nfirst-line-indent = \"-1zw\"\n")) @?= [],
      testCase "[verse] is retired" $
        messages (parseStyle (FileId 0) "[verse]\nindent = \"0zw\"\n") `hasAll` ["G0306", "[paragraph-styles.verse]"]
    ]
  where
    indents = fmap (\d -> (fromMaybe (Zw 99) (psIndent d), fromMaybe (Zw 99) (psFirstLineIndent d)))
    parsed src = either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) src)
    messages = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
    hasAll ms needles = assertBool (show ms) (not (null ms) && all (\n -> any (n `T.isInfixOf`) ms) needles)

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
      "color = \"accent\"",
      "",
      "[paragraph-styles.quote]",
      "font = \"heading\"",
      "size = \"0.9zw\"",
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
