module Main (main) where

import Control.Monad (void)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Parser.SourceSettings
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

-- | The manifest with a [source] table (and other text) after it.
manifestWith :: [Text] -> Text -> Text
manifestWith chapters extra = manifest chapters <> "\n" <> extra

-- | The separator of each file of the project, by path.
separators :: Project -> [(FilePath, ParagraphSeparator)]
separators p =
  [ (path, ssParagraphSeparator s)
  | (fid, s) <- Map.toList (projectSourceSettings p),
    Just path <- [lookupPath fid (projectFiles p)]
  ]

sourceTests :: TestTree
sourceTests =
  testGroup
    "[source] (docs/adr ADR 0013)"
    [ testCase "without [source] the settings are the default" $
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> do
              manifestSource (projectManifest p) @?= defaultSourceSettings
              separators p @?= [("a.gm", BlankLineSeparated)],
      testCase "paragraph-separator = \"line\" is read" $
        withProject [("manifest.toml", manifestWith ["\"a.gm\""] "[source]\nparagraph-separator = \"line\"\n"), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> ssParagraphSeparator (manifestSource (projectManifest p)) @?= LineSeparated,
      testCase "an invalid value and an unknown key are G0301" $ do
        withProject [("manifest.toml", manifestWith ["\"a.gm\""] "[source]\nparagraph-separator = \"lines\"\n"), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G0301"]) . codes
        withProject [("manifest.toml", manifestWith ["\"a.gm\""] "[source]\nparagraph-separators = \"line\"\n"), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G0301"]) . codes
        withProject [("manifest.toml", manifest ["{ file = \"a.gm\", paragraph-separator = \"lines\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G0301"]) . codes
        withProject [("manifest.toml", manifest ["{ file = \"a.gm\", unknown = \"x\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G0301"]) . codes,
      testCase "a chapter entry overrides [source]; imported files take [source]"
        $ withProject
          [ ("manifest.toml", manifestWith ["\"a.gm\"", "{ file = \"b.gm\", paragraph-separator = \"blank-line\" }"] "[source]\nparagraph-separator = \"line\"\n"),
            ("a.gm", "@import c.gm as c\n"),
            ("b.gm", "@import c.gm as c\n"),
            ("c.gm", "@set x = 1\n")
          ]
        $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> do
              separators p @?= [("a.gm", LineSeparated), ("b.gm", BlankLineSeparated), ("c.gm", LineSeparated)]
              map (\(_, m, es) -> (m, length es)) (chapterFiles (manifestChapters (projectManifest p))) @?= [(Nothing, 0), (Nothing, 1)],
      testCase "the same file twice with different settings is G0301" $ do
        withProject [("manifest.toml", manifest ["\"a.gm\"", "{ file = \"a.gm\", paragraph-separator = \"line\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G0301"]) . codes
        withProject [("manifest.toml", manifest ["\"a.gm\"", "{ file = \"a.gm\", paragraph-separator = \"blank-line\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= []) . codes
    ]

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
      sourceTests,
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
            fmap pageSizeSpec (stPage s) @?= Just (NamedSize "B6")
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
      testCase "the sidenote font and size are the paragraph style sidenote (golem-driver ADR 0011)" $ do
        let retired = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
            hasIt ms = assertBool (show ms) (not (null ms) && all (\m -> "G0306" `T.isPrefixOf` m) ms && any ("[paragraph-styles.sidenote]" `T.isInfixOf`) ms)
        hasIt (retired (parseStyle (FileId 0) "[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\nsize = \"8pt\"\n"))
        hasIt (retired (parseStyle (FileId 0) "[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\nfont = \"note\"\n"))
        case parseStyle (FileId 0) "[fonts.note]\nlatin = \"n.otf\"\n\n[paragraph-styles.sidenote]\nfont = \"note\"\nsize = \"8pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (paraStyle s (Just "sidenote") >>= psFont) @?= Just "note"
            (paraStyle s (Just "sidenote") >>= psSize) @?= Just (Abs (8 * 65536))
        codes (parseStyle (FileId 0) "[paragraph-styles.sidenote]\nfont = \"nope\"\n") @?= ["G0308"],
      testCase "a caption style (golem-driver ADR 0010)" $ do
        case parseStyle (FileId 0) "[fonts.caption]\nlatin = \"c.otf\"\n\n[paragraph-styles.caption]\nfont = \"caption\"\nsize = \"8pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (paraStyle s (Just "caption") >>= psFont) @?= Just "caption"
            (paraStyle s (Just "caption") >>= psSize) @?= Just (Abs (8 * 65536))
        codes (parseStyle (FileId 0) "[figures]\ncaption = \"x\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[figures.caption]\nfont = \"body\"\n") @?= ["G0306"],
      testCase "explicit-hyphen-penalty (golem-layout ADR 0008)" $ do
        fmap (compExplicitHyphenPenalty . stComposition) (parseStyle (FileId 0) "") @?= Right 50
        fmap (compExplicitHyphenPenalty . stComposition) (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = 100\n") @?= Right 100
        fmap (compExplicitHyphenPenalty . stComposition) (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = -9999\n") @?= Right (-9999)
        codes (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = -10000\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = 10001\n") @?= ["G0306"],
      testCase "[composition.ruby] (golem-layout ADR 0009)" $ do
        let rubyOf = fmap (compRuby . stComposition) . parseStyle (FileId 0)
        rubyOf "" @?= Right (RubyStyleDef "center" "1:2:1" "1:2:1" (Zw 0.5) "kana")
        rubyOf "[composition.ruby]\nmono-align = \"start\"\ngroup-align = \"0:1:0\"\nbase-spacing = \"center\"\noverhang = \"1zw\"\noverhang-onto = \"none\"\n"
          @?= Right (RubyStyleDef "start" "0:1:0" "center" (Zw 1) "none")
        rubyOf "[composition.ruby]\ngroup-align = \"center\"\n" @?= Right (RubyStyleDef "center" "center" "1:2:1" (Zw 0.5) "kana")
        codes (parseStyle (FileId 0) "[composition.ruby]\ngroup-align = \"justify\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[composition.ruby]\nmono-align = \"1:2:1\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[composition.ruby]\noverhang = \"-1zw\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[composition.ruby]\nposition = \"mono-center\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[composition]\nruby = { position = \"mono-center\", overhang = \"1zw\" }\n") @?= ["G0306"],
      testCase "[toc] leader (golem-driver ADR 0009)" $ do
        fmap stTocLeader (parseStyle (FileId 0) "[toc]\nleader = \"none\"\n") @?= Right "none"
        fmap stTocLeader (parseStyle (FileId 0) "") @?= Right "dots"
        codes (parseStyle (FileId 0) "[toc]\nleader = \"dash\"\n") @?= ["G0306"]
        codes (parseStyle (FileId 0) "[toc]\nfont = \"body\"\n") @?= ["G0306"],
      testCase "a heading font must name a font role (golem-driver ADR 0003)" $ do
        codes (parseStyle (FileId 0) "[headings.1]\nfont = \"nope\"\n") @?= ["G0308"]
        codes (parseStyle (FileId 0) "[fonts.heading]\nlatin = \"h.otf\"\n\n[headings.1]\nfont = \"heading\"\n") @?= [],
      testCase "loadStyle does not look for the files it names (ADR 0004)" $
        void (loadStyle (FileId 0) (Just "[fonts.body]\nja = \"fonts/none.otf\"\n\n[color]\nintent = \"icc/none.icc\"\n")) @?= Right (),
      testCase "fontFiles lists roles by name, Japanese before Latin (ADR 0004)" $
        fmap fontFiles (loadStyle (FileId 0) (Just "[fonts.mono]\nlatin = \"m.otf\"\n\n[fonts.body]\nja = \"b.otf\"\nlatin = \"l.otf\"\n"))
          @?= Right [("body", "b.otf"), ("body", "l.otf"), ("mono", "m.otf")],
      testCase "character style fonts name font roles (golem-driver ADR 0004)" $
        codes (parseStyle (FileId 0) "[character-styles.term]\nfont = \"nope\"\n") @?= ["G0308"],
      styleTests,
      localStyleTests,
      testCase "[page] bleed (golem-pdf ADR 0004)" $ do
        fmap (fmap pageBleed . stPage) (parseStyle (FileId 0) "[page]\nsize = \"A6\"\nbleed = \"3mm\"\n") @?= Right (Just 557314)
        fmap (fmap pageBleed . stPage) (parseStyle (FileId 0) "[page]\nsize = \"A6\"\n") @?= Right (Just 0)
        codes (parseStyle (FileId 0) "[page]\nsize = \"A6\"\nbleed = \"1zw\"\n") @?= ["G0306"],
      testGroup "page size by dimensions (ADR 0005)" pageSizeTests,
      testCase "marks is not a key of the manifest (golem-pdf ADR 0004)" $
        withProject [("manifest.toml", manifest ["\"a.gm\""] <> "\n[targets.pdf]\nmarks = \"japanese\"\n"), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G0301"]) . codes
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
      "kenten = \"sesame\"",
      "tolerance = 200",
      "protrusion = true",
      "expansion = { limit = 20, step = 5 }",
      "",
      "[composition.ruby]",
      "mono-align = \"center\"",
      "group-align = \"1:2:1\"",
      "base-spacing = \"1:2:1\"",
      "overhang = \"0.5zw\"",
      "overhang-onto = \"kana\"",
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
      "marker = \"number\"",
      "",
      "[paragraph-styles.sidenote]",
      "font = \"body\"",
      "size = \"11Q\"",
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

-- | Styles defined in a file (docs/adr ADR 0014).
localStyleTests :: TestTree
localStyleTests =
  testGroup
    "styles defined in a file (docs/adr ADR 0014)"
    [ testCase "localStyleDef maps words and strings to TOML values" $ do
        localStyleDef ParagraphKind [("based-on", LocalWord "body"), ("indent", LocalWord "2zw"), ("line-breaks", LocalWord "keep"), ("space-between", LocalWord "1")]
          @?= Right (Right noParaDef {psBasedOn = Just "body", psIndent = Just (Zw 2), psLineBreaks = Just KeepLines, psSpaceBetween = Just 1})
        localStyleDef CharacterKind [("synthetic-bold", LocalWord "true")] @?= Right (Left noCharDef {csSyntheticBold = Just True})
        let bad k xs = assertBool (show xs) (isLeftE (localStyleDef k xs))
        bad CharacterKind [("synthetic-bold", LocalString "true")]
        bad ParagraphKind [("space-between", LocalString "1")]
        bad CharacterKind [("colour", LocalWord "x")]
        bad ParagraphKind [("line-breaks", LocalWord "x")]
        bad ParagraphKind [("space-between", LocalWord "-1")],
      testCase "every key of charStyleKeys and paraStyleKeys is known" $ do
        let valueOf = \case
              "synthetic-bold" -> "true"
              "synthetic-italic" -> "true"
              "line-breaks" -> "keep"
              "space-between" -> "1"
              "size" -> "1zw"
              "indent" -> "1zw"
              "first-line-indent" -> "1zw"
              _ -> "x"
            known k key = not (isLeftE (localStyleDef k [(key, LocalWord (valueOf key))]))
        assertBool "char" (all (known CharacterKind) charStyleKeys)
        assertBool "para" (all (known ParagraphKind) paraStyleKeys)
        assertBool "a made-up key is unknown" (not (known ParagraphKind "colour")),
      testCase "a local style inherits a style.toml style through based-on" $ do
        base <- styleOf "[paragraph-styles.quote]\nindent = \"3zw\"\nspace-between = 2\n"
        let s = withLocalStyles base (localPara [("letter", noParaDef {psBasedOn = Just "quote"})])
        fmap psIndent (paraStyle s (Just "letter")) @?= Just (Just (Zw 3))
        fmap psSpaceBetween (paraStyle s (Just "letter")) @?= Just (Just 2),
      testCase "checkLocalStyles reports the errors of style.toml's checks" $ do
        base <- styleOf "[page]\nsize = \"A6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 20\nlines = 10\nline-pitch = \"20H\"\nposition = { top = \"10mm\", gutter = \"10mm\" }\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
        let chk ls = [(c, n) | (c, n, _) <- checkLocalStyles base ls]
        chk (localPara [("Letter", noParaDef)]) @?= [("G0306", "Letter")]
        chk (localPara [("a", noParaDef {psBasedOn = Just "nope"})]) @?= [("G0313", "a")]
        assertBool "cycle" (("G0313", "a") `elem` chk (localPara [("a", noParaDef {psBasedOn = Just "b"}), ("b", noParaDef {psBasedOn = Just "a"})]))
        chk (localChar [("t", noCharDef {csFont = Just "nope"})]) @?= [("G0308", "t")]
        chk (localChar [("t", noCharDef {csColor = Just "nope"})]) @?= [("G0313", "t")]
        chk (localChar [("t", noCharDef {csColor = Just "accent"})]) @?= []
        chk (localPara [("a", noParaDef {psSize = Just (Zw 2)})]) @?= [("G0311", "a")]
        chk (localPara [("a", noParaDef {psIndent = Just (Zw 1), psFirstLineIndent = Just (Zw (-2))})]) @?= [("G0312", "a")],
      testCase "checkLocalStyles leaves out the errors style.toml has by itself" $ do
        let base = defaultStyle {stParaStyles = Map.insert "q" noParaDef {psBasedOn = Just "nope"} (stParaStyles defaultStyle)}
        [c | (c, _, _) <- checkLocalStyles base (localPara [("letter", noParaDef)])] @?= [],
      testCase "an override changes only the keys it writes, in its file" $ do
        base <- styleOf "[fonts.heading]\nlatin = \"h.otf\"\n\n[paragraph-styles.quote]\nfont = \"heading\"\n"
        let s = withLocalStyles base (localPara [("quote", noParaDef {psIndent = Just (Zw 1)})])
        fmap psFont (paraStyle s (Just "quote")) @?= Just (Just "heading")
        fmap psIndent (paraStyle s (Just "quote")) @?= Just (Just (Zw 1))
        fmap psIndent (paraStyle base (Just "quote")) @?= Just (Just (Zw 0)),
      testCase "overriding body changes the styles based on it" $ do
        base <- styleOf "[paragraph-styles.quote]\nspace-between = 1\n"
        let s = withLocalStyles base (localPara [("body", noParaDef {psIndent = Just (Zw 1)})])
        fmap psIndent (paraStyle s (Just "quote")) @?= Just (Just (Zw 1)),
      testCase "based-on cycles through overrides are G0313" $ do
        let chk b ls = [(c, n) | (c, n, _) <- checkLocalStyles b ls]
        base <- styleOf "[paragraph-styles.quote]\nindent = \"1zw\"\n"
        assertBool "self" (("G0313", "quote") `elem` chk base (localPara [("quote", noParaDef {psBasedOn = Just "quote"})]))
        ab <- styleOf "[paragraph-styles.a]\nbased-on = \"b\"\n\n[paragraph-styles.b]\nindent = \"1zw\"\n"
        assertBool "through style.toml" (("G0313", "b") `elem` chk ab (localPara [("b", noParaDef {psBasedOn = Just "a"})]))
        assertBool "body" (("G0313", "body") `elem` chk base (localPara [("body", noParaDef {psBasedOn = Just "quote"})])),
      testCase "an override of body can make a style.toml style hang out (G0312)" $ do
        base <- styleOf "[paragraph-styles.quote]\nspace-between = 1\n"
        assertBool "quote" (("G0312", "quote") `elem` [(c, n) | (c, n, _) <- checkLocalStyles base (localPara [("body", noParaDef {psFirstLineIndent = Just (Zw (-1))})])]),
      testCase "a table written twice in style.toml is a TOML error (G0306)" $
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"1zw\"\n\n[paragraph-styles.quote]\nindent = \"2zw\"\n") @?= ["G0306"]
    ]
  where
    styleOf t = either (\ds -> assertFailure (show ds) >> pure defaultStyle) pure (parseStyle (FileId 0) t)
    localPara xs = noLocalStyles {lsParaStyles = Map.fromList xs}
    localChar xs = noLocalStyles {lsCharStyles = Map.fromList xs}
    isLeftE = either (const True) (const False)

pageSizeTests :: [TestTree]
pageSizeTests =
  [ testCase "width and height are dimensions" $ do
      trim "{ width = \"148mm\", height = \"210mm\" }" @?= Right (Just (abs' "148mm", abs' "210mm"))
      trim "{ width = \"396pt\", height = \"612pt\" }" @?= Right (Just (396 * 65536, 612 * 65536))
      trim "{ width = \"100mm\", height = \"600Q\" }" @?= Right (Just (abs' "100mm", abs' "600Q"))
      trim "{ width = \"210mm\", height = \"148mm\" }" @?= Right (Just (abs' "210mm", abs' "148mm")),
    testCase "a page given by dimensions is the same as the named size" $
      trim "{ width = \"107.95mm\", height = \"174.625mm\" }" @?= trim "\"mass-market\"",
    testCase "the named sizes are the table in sp" $
      sequence_
        [ trim ("\"" <> n <> "\"") @?= Right (Just (mm w, mm h))
        | n <- ["A4", "A5", "A6", "B5", "B6", "四六判", "mass-market"],
          Just (w, h) <- [pageSize n]
        ],
    testCase "菊判 and 新書判" $ do
      trim "\"菊判\"" @?= trim "{ width = \"150mm\", height = \"220mm\" }"
      trim "\"新書判\"" @?= trim "{ width = \"103mm\", height = \"182mm\" }"
      assertBool "菊判" (isRight (trim "\"菊判\""))
      assertBool "新書判" (isRight (trim "\"新書判\"")),
    testCase "errors are G0317" $ do
      g0317 "\"148mm x 210mm\"" "未知の判型です: 148mm x 210mm。表にない判型は size = { width = \"…\", height = \"…\" } で書きます"
      g0317 "\"A3\"" "未知の判型です: A3"
      g0317 "\"菊版\"" "未知の判型です: 菊版"
      g0317 "\"新書版\"" "未知の判型です: 新書版"
      g0317 "{ width = \"148mm\" }" "判型の width と height はどちらも必須です"
      g0317 "{ width = \"148mm\", height = \"210mm\", depth = \"1mm\" }" "depth"
      g0317 "{ width = \"10zw\", height = \"210mm\" }" "判型には zw を使えません"
      g0317 "{ width = \"0mm\", height = \"210mm\" }" "判型の幅と高さは 0 より大きい寸法です"
      g0317 "{ width = \"148\", height = \"210mm\" }" "dimension",
    testCase "G0317 is at the value of size" $
      case parseStyle (FileId 0) "[page]\nsize = \"A3\"\n" of
        Left [d] -> spanStart (diagSpan d) @?= 14
        r -> assertFailure (show r)
  ]
  where
    src v = "[page]\nsize = " <> v <> "\n"
    trim v = fmap (fmap pageTrimSize . stPage) (parseStyle (FileId 0) (src v))
    abs' t = case parseDim t of
      Just (Abs x) -> x
      d -> error (show d)
    mm x = round (x * 72 * 65536 / (254 / 10) :: Rational)
    isRight = either (const False) (const True)
    g0317 v needle = case parseStyle (FileId 0) (src v) of
      Left ds -> do
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G0317"]
        assertBool (show (map diagMessage ds)) (any ((needle `T.isInfixOf`) . diagMessage) ds)
      Right _ -> assertFailure ("not an error: " <> T.unpack v)
