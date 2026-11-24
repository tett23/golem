{- | Untrusted projects: what a manuscript repository must not be able to do
to the machine that builds it, or to the readers of its HTML (docs/adr ADR
0035, and the security audit of 2026-10-17 that it follows).
-}
module SecuritySpec (securityTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (isPrefixOf, isSuffixOf, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing, createDirectoryLink, createFileLink, doesDirectoryExist, doesFileExist, listDirectory, pathIsSymbolicLink, removePathForcibly)
import System.FilePath (makeRelative, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A one-chapter project with the source, the style and the files.
project :: FilePath -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO ()
project tmp manifestHead style source files = do
  BS.writeFile (tmp </> "manifest.toml") (manifestHead <> miniManifest <> "\n[targets.html]\n[targets.text]\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  writeFiles tmp files

-- | A directory outside the project with a file in each target directory.
victim :: FilePath -> IO FilePath
victim tmp = do
  let v = tmp </> "victim"
  forM_ ["html", "text", "epub", "pdf"] $ \d -> do
    createDirectoryIfMissing True (v </> d)
    BS.writeFile (v </> d </> "precious.txt") "keep me"
  pure v

-- | The target folders under build, as root ADR 0429 names them.
targetDirs :: [(Target, FilePath)]
targetDirs = [(TargetHtml, "html"), (TargetEpub, "epub"), (TargetText, "text"), (TargetPdf, "pdf")]

{- | The files under a path with their contents, without .DS_Store (root ADR
0429): a file is itself, a folder (or a link to one) its files, and a
missing path nothing.
-}
snapshot :: FilePath -> IO [(FilePath, BS.ByteString)]
snapshot top = sort <$> go top
  where
    go p = do
      isDir <- doesDirectoryExist p
      isFile <- doesFileExist p
      if isDir
        then concat <$> (listDirectory p >>= mapM (go . (p </>)) . filter (/= ".DS_Store"))
        else
          if isFile
            then (\b -> [(makeRelative top p, b)]) <$> BS.readFile p
            else pure []

-- | The snapshot of every target folder of a project.
snapshotTargets :: FilePath -> IO [(FilePath, [(FilePath, BS.ByteString)])]
snapshotTargets root = mapM (\(_, d) -> (,) d <$> snapshot (root </> "build" </> d)) targetDirs

-- | The relative paths of the files in a folder, without .DS_Store.
filesIn :: FilePath -> IO [FilePath]
filesIn dir = map fst <$> snapshot dir

-- | The files a build returned under a folder, relative to it.
writtenIn :: BuildResult -> FilePath -> [FilePath]
writtenIn r dir = sort [makeRelative dir p | p <- brWritten r, (dir <> "/") `isPrefixOf` p]

-- | Leaves a file the next build does not write in each target folder.
leaveOldFiles :: FilePath -> IO ()
leaveOldFiles root = forM_ targetDirs $ \(_, d) -> do
  createDirectoryIfMissing True (root </> "build" </> d)
  BS.writeFile (root </> "build" </> d </> "old.txt") "previous build"

securityTests :: TestTree
securityTests =
  testGroup
    "untrusted projects (docs/adr ADR 0035)"
    [ -- docs/adr ADR 0042: the same manuscript is refused for every target
      testCase "U+0001 in the text stops the text and the PDF builds with G02089" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" (withBodyFont horizontalStyle) "前\SOH後\n" (bodyFontFiles horizontalStyle)
        forM_ [TargetText, TargetPdf] $ \t -> do
          r <- build (defaultOptions tmp) {optTargets = Just [t], optFonts = fakeProvider}
          (map diagCode (filter isError (brDiagnostics r)), brWritten r) @?= ([DiagnosticCode "G02089"], []),
      testCase "Golem ADR 0329 O2: build as a symbolic link out of the project is G08013, and nothing there is removed" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        v <- victim tmp
        let root = tmp </> "p"
        createDirectoryIfMissing True root
        project root "" horizontalStyle "本文。\n" []
        createDirectoryLink v (root </> "build")
        r <- build (defaultOptions root) {optTargets = Just [TargetHtml, TargetText]}
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08013"]
        brWritten r @?= []
        forM_ ["html", "text", "epub", "pdf"] $ \d ->
          doesFileExist (v </> d </> "precious.txt") >>= assertBool ("kept " <> d)
        doesFileExist (v </> "html" </> "a.html") >>= assertBool "nothing written there" . not,
      testCase "build/html as a symbolic link is G08013 too" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        v <- victim tmp
        let root = tmp </> "p"
        createDirectoryIfMissing True (root </> "build")
        project root "" horizontalStyle "本文。\n" []
        createDirectoryLink (v </> "html") (root </> "build" </> "html")
        r <- build (defaultOptions root) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08013"]
        doesFileExist (v </> "html" </> "precious.txt") >>= assertBool "kept",
      -- docs/adr ADR 0076: the folder of every target, not only build and build/html
      testGroup "the folder of each target written as a symbolic link is G08013 (docs/adr ADR 0076)" $
        [ testCase dir $ withSystemTempDirectory "golem-sec" $ \tmp -> do
            v <- victim tmp
            let root = tmp </> "p"
            createDirectoryIfMissing True (root </> "build")
            project root "" (withBodyFont horizontalStyle) "本文。\n" (bodyFontFiles horizontalStyle)
            createDirectoryLink (v </> dir) (root </> "build" </> dir)
            r <- build (defaultOptions root) {optTargets = Just [target], optFonts = fakeProvider}
            map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08013"]
            brWritten r @?= []
            doesFileExist (v </> dir </> "precious.txt") >>= assertBool "kept"
        | (target, dir) <- [(TargetEpub, "epub"), (TargetText, "text"), (TargetPdf, "pdf")]
        ],
      testCase "Golem ADR 0329 O1: build/html as a regular file is G08104" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        createDirectoryIfMissing True (tmp </> "build")
        project tmp "" horizontalStyle "本文。\n" []
        BS.writeFile (tmp </> "build" </> "html") "not a folder"
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08104"]
        brWritten r @?= []
        BS.readFile (tmp </> "build" </> "html") >>= (@?= "not a folder"),
      testCase "Golem ADR 0329 O1 and O2: a regular build parent reports only G08104" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" horizontalStyle "本文。\n" []
        BS.writeFile (tmp </> "build") "keep build"
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08104"]
        brWritten r @?= []
        BS.readFile (tmp </> "build") >>= (@?= "keep build"),
      testCase "Golem ADR 0329 O1: a broken output link remains G08013" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" horizontalStyle "本文。\n" []
        createDirectoryIfMissing True (tmp </> "build")
        createDirectoryLink (tmp </> "missing") (tmp </> "build/html")
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08013"]
        brWritten r @?= []
        pathIsSymbolicLink (tmp </> "build/html") >>= (@?= True),
      testCase "Golem ADR 0329 O3 and O4: build removes selected regular .DS_Store files" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" horizontalStyle "本文。\n" []
        createDirectoryIfMissing True (tmp </> "build/html")
        createDirectoryIfMissing True (tmp </> "build/pdf")
        forM_ [tmp, tmp </> "build", tmp </> "build/html", tmp </> "build/pdf"] $ \dir -> BS.writeFile (dir </> ".DS_Store") "finder"
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        forM_ [tmp, tmp </> "build", tmp </> "build/html"] $ \dir -> doesFileExist (dir </> ".DS_Store") >>= (@?= False)
        BS.readFile (tmp </> "build/pdf/.DS_Store") >>= (@?= "finder")
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        doesFileExist (tmp </> ".DS_Store") >>= (@?= False),
      testCase "Golem ADR 0329 O4: a .DS_Store link and its target remain" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        let root = tmp </> "project"
            outside = tmp </> "outside"
        createDirectoryIfMissing True root
        createDirectoryIfMissing True outside
        project root "" horizontalStyle "本文。\n" []
        BS.writeFile (outside </> "precious") "keep me"
        createFileLink (outside </> "precious") (root </> ".DS_Store")
        _ <- build (defaultOptions root) {optTargets = Just [TargetHtml]}
        pathIsSymbolicLink (root </> ".DS_Store") >>= (@?= True)
        BS.readFile (outside </> "precious") >>= (@?= "keep me"),
      testCase "Golem ADR 0329 O4: Finder cleanup stays in real visible project folders" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        let root = tmp </> "project"
            outside = tmp </> "outside"
        createDirectoryIfMissing True (root </> ".hidden")
        createDirectoryIfMissing True (root </> "directory/.DS_Store")
        createDirectoryIfMissing True outside
        createDirectoryLink outside (root </> "link")
        BS.writeFile (root </> ".hidden/.DS_Store") "hidden"
        BS.writeFile (outside </> ".DS_Store") "outside"
        cleanFinderInfo root [".hidden", "directory", "link", "../outside"]
        BS.readFile (root </> ".hidden/.DS_Store") >>= (@?= "hidden")
        BS.readFile (outside </> ".DS_Store") >>= (@?= "outside")
        doesDirectoryExist (root </> "directory/.DS_Store") >>= (@?= True),
      testCase "build/html as a symbolic link to a folder inside the project is G08013 (docs/adr ADR 0076)" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        createDirectoryIfMissing True (tmp </> "build")
        project tmp "" horizontalStyle "本文。\n" []
        createDirectoryIfMissing True (tmp </> "inside")
        BS.writeFile (tmp </> "inside" </> "precious.txt") "keep me"
        createDirectoryLink (tmp </> "inside") (tmp </> "build" </> "html")
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08013"]
        brWritten r @?= []
        doesFileExist (tmp </> "inside" </> "precious.txt") >>= assertBool "kept",
      testCase "build/pdf as a symbolic link does not stop a build of HTML only (docs/adr ADR 0076)" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        v <- victim tmp
        let root = tmp </> "p"
        createDirectoryIfMissing True (root </> "build")
        project root "" horizontalStyle "本文。\n" []
        createDirectoryLink (v </> "pdf") (root </> "build" </> "pdf")
        r <- build (defaultOptions root) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        assertBool (show (brWritten r)) (any ((root </> "build" </> "html") `isPrefixOf`) (brWritten r) && not (null (brWritten r)))
        doesFileExist (root </> "build" </> "html" </> "a.html") >>= assertBool "written in build/html"
        doesFileExist (v </> "pdf" </> "precious.txt") >>= assertBool "kept",
      testCase "Golem ADR 0326 B1 and B4: prod clears stale PDF and dev keeps it" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" (withBodyFont horizontalStyle) "@figure images/bad.png alt=\"t\"\n" (bodyFontFiles horizontalStyle <> [("images/bad.png", "\x89PNG\r\n\x1a\n")])
        let pdfDir = tmp </> "build/pdf"
            oldPdf = pdfDir </> "book.pdf"
            oldPages = pdfDir </> "pages.json"
        createDirectoryIfMissing True pdfDir
        BS.writeFile oldPdf "previous pdf"
        BS.writeFile oldPages "previous pages"
        dev <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = Dev}
        assertBool "dev build failed" (any isError (brDiagnostics dev))
        BS.readFile oldPdf >>= (@?= "previous pdf")
        BS.readFile oldPages >>= (@?= "previous pages")
        prod <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = Prod}
        assertBool "prod build failed" (any isError (brDiagnostics prod))
        doesFileExist oldPdf >>= (@?= False)
        doesFileExist oldPages >>= (@?= False),
      testCase "Golem ADR 0326 B3: prod failure keeps a linked PDF directory's target" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        let root = tmp </> "project"
            outside = tmp </> "outside"
        createDirectoryIfMissing True (root </> "build")
        createDirectoryIfMissing True outside
        project root "" (withBodyFont horizontalStyle) "@figure images/bad.png alt=\"t\"\n" (bodyFontFiles horizontalStyle <> [("images/bad.png", "\x89PNG\r\n\x1a\n")])
        BS.writeFile (outside </> "precious.pdf") "keep me"
        createDirectoryLink outside (root </> "build/pdf")
        r <- build (defaultOptions root) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = Prod}
        assertBool "prod build failed" (any isError (brDiagnostics r))
        BS.readFile (outside </> "precious.pdf") >>= (@?= "keep me"),
      testCase "Golem ADR 0326 B2: check and HTML-only builds keep the old PDF" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" (withBodyFont horizontalStyle) "@figure images/bad.png alt=\"t\"\n" (bodyFontFiles horizontalStyle <> [("images/bad.png", "\x89PNG\r\n\x1a\n")])
        let pdfDir = tmp </> "build/pdf"
            oldPdf = pdfDir </> "book.pdf"
        createDirectoryIfMissing True pdfDir
        BS.writeFile oldPdf "previous pdf"
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = Prod, optCheckOnly = True}
        BS.readFile oldPdf >>= (@?= "previous pdf")
        _ <- build (defaultOptions tmp) {optTargets = Just [TargetHtml], optFonts = fakeProvider, optProfile = Prod}
        BS.readFile oldPdf >>= (@?= "previous pdf"),
      -- root ADR 0429: the folder of each target written is cleared before it is written
      testGroup "root ADR 0429 I1: each written target folder holds only the files the build returned" $
        [ testCase ("root ADR 0429 I1: " <> d <> " after a previous build") $ withSystemTempDirectory "golem-sec" $ \tmp -> do
            project tmp "" (withBodyFont horizontalStyle) "本文。\n" (bodyFontFiles horizontalStyle)
            leaveOldFiles tmp
            r <- build (defaultOptions tmp) {optTargets = Just [target], optFonts = fakeProvider}
            map diagCode (filter isError (brDiagnostics r)) @?= []
            let dir = tmp </> "build" </> d
            got <- filesIn dir
            got @?= writtenIn r dir
            assertBool (show got) ("old.txt" `notElem` got)
            fixed got
        | (target, d, fixed) <-
            [ (TargetHtml, "html", \got -> assertBool (show got) (all (`elem` got) ["a.html", "index.html", "style.css"])),
              (TargetEpub, "epub", (@?= ["book.epub"])),
              (TargetText, "text", (@?= ["horizontal/a.txt", "vertical/a.txt"])),
              (TargetPdf, "pdf", \got -> (length got, "pages.json" `elem` got, length (filter (".pdf" `isSuffixOf`) got)) @?= (2, True, 1))
            ]
        ],
      testCase "root ADR 0429 I1: an HTML page of a removed chapter is removed" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" horizontalStyle "本文。\n" []
        createDirectoryIfMissing True (tmp </> "build/html")
        BS.writeFile (tmp </> "build/html/old.html") "a chapter removed since"
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        got <- filesIn (tmp </> "build/html")
        got @?= writtenIn r (tmp </> "build/html")
        assertBool (show got) ("old.html" `notElem` got),
      testCase "root ADR 0429 I1: the text variant no longer made is removed" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" horizontalStyle "本文。\n" []
        first <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        map diagCode (filter isError (brDiagnostics first)) @?= []
        doesDirectoryExist (tmp </> "build/text/vertical") >>= assertBool "the first build writes the vertical text"
        manifest <- BS.readFile (tmp </> "manifest.toml")
        BS.writeFile (tmp </> "manifest.toml") (manifest <> "variants = [\"horizontal\"]\n")
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        doesDirectoryExist (tmp </> "build/text/vertical") >>= (@?= False)
        got <- filesIn (tmp </> "build/text")
        got @?= writtenIn r (tmp </> "build/text")
        got @?= ["horizontal/a.txt"],
      testCase "root ADR 0429 I1: a build with no previous output holds only the files it returned" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" (withBodyFont horizontalStyle) "本文。\n" (bodyFontFiles horizontalStyle)
        r <- build (defaultOptions tmp) {optTargets = Just (map fst targetDirs), optFonts = fakeProvider}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        forM_ targetDirs $ \(_, d) -> do
          let dir = tmp </> "build" </> d
          got <- filesIn dir
          assertBool d (not (null got))
          got @?= writtenIn r dir,
      testCase "root ADR 0429 I2: a build of HTML only leaves the other target folders as they were" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "" horizontalStyle "本文。\n" []
        leaveOldFiles tmp
        BS.writeFile (tmp </> "build/pdf/book.pdf") "previous pdf"
        BS.writeFile (tmp </> "build/epub/book.epub") "previous epub"
        before <- snapshotTargets tmp
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        afterBuild <- snapshotTargets tmp
        filter ((/= "html") . fst) afterBuild @?= filter ((/= "html") . fst) before,
      testGroup "root ADR 0429 I3: an unsafe output path writes no target folder" $
        [ testCase ("root ADR 0429 I3: " <> name) $ withSystemTempDirectory "golem-sec" $ \tmp -> do
            v <- victim tmp
            let root = tmp </> "p"
            createDirectoryIfMissing True root
            project root "" (withBodyFont horizontalStyle) "本文。\n" (bodyFontFiles horizontalStyle)
            leaveOldFiles root
            setUp v root
            before <- snapshotTargets root
            victimBefore <- snapshot v
            r <- build (defaultOptions root) {optTargets = Just targets, optFonts = fakeProvider, optProfile = profile}
            assertBool (show (brDiagnostics r)) (DiagnosticCode code `elem` map diagCode (filter isError (brDiagnostics r)))
            brWritten r @?= []
            afterBuild <- snapshotTargets root
            snapshot v >>= (@?= victimBefore)
            if profile == Prod
              then do
                lookup "pdf" afterBuild @?= Just []
                filter ((/= "pdf") . fst) afterBuild @?= filter ((/= "pdf") . fst) before
              else afterBuild @?= before
        | (name, profile, targets, code, setUp) <-
            [ ("dev, build/epub a symbolic link, HTML and EPUB", Dev, [TargetHtml, TargetEpub], "G08013", \v root -> removeAndLink (v </> "epub") (root </> "build/epub")),
              ("dev, build/text a regular file, HTML and text", Dev, [TargetHtml, TargetText], "G08104", \_ root -> removeAndWrite (root </> "build/text")),
              ("prod, build/html a symbolic link, every target", Prod, map fst targetDirs, "G08013", \v root -> removeAndLink (v </> "html") (root </> "build/html")),
              ("dev, build itself a symbolic link", Dev, map fst targetDirs, "G08013", \v root -> removeAndLink v (root </> "build"))
            ]
        ],
      testCase "a figure path with a quote stays inside the src attribute" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        img <- tinyImage
        let name = "q\" onerror=\"alert(1).jpg"
        project tmp "" horizontalStyle "# 章\n\n@figure \"q\\\" onerror=\\\"alert(1).jpg\" alt=\"t\"\n" [(name, bytes) | (_, bytes) <- img]
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        page <- TIO.readFile (tmp </> "build/html/a.html")
        assertBool (T.unpack page) ("<img src=\"q&quot; onerror=&quot;alert(1).jpg\"" `T.isInfixOf` page)
        assertBool (T.unpack page) (not ("onerror=\"" `T.isInfixOf` page)),
      testCase "a font role with a quote stays inside the CSS strings" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        let style = horizontalStyle <> "\n[fonts.\"x\\\" } body { color: red } x { a: \\\"\"]\nlatin = \"fonts/a\\\").otf\"\n"
        -- the fonts embedded, so that the CSS names the role (docs/adr/0423)
        project tmp "" style "本文。\n" [("fonts/a\").otf", "font")]
        embedFonts tmp
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        css <- TIO.readFile (tmp </> "build/html/style.css")
        assertBool (T.unpack css) ("font-family: \"golem-x\\\" } body { color: red } x { a: \\\"-latin\"; src: url(\"fonts/a\\\").otf\");" `T.isInfixOf` css)
        assertBool (T.unpack css) (not ("\n body { color: red }" `T.isInfixOf` css)),
      localOption hangTimeout $ testCase "a year of 1e1000000000 in CSL-JSON does not stop the build" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "bibliography = [\"refs.json\"]\n" horizontalStyle "本文[cite a][cite b]。\n" [("refs.json", "[{\"id\": \"a\", \"title\": \"T\", \"issued\": {\"date-parts\": [[1e1000000000]]}}, {\"id\": \"b\", \"title\": \"U\", \"issued\": {\"date-parts\": [[1e-1000000000]]}}]")]
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
    ]

-- | Replaces a path with a symbolic link to a folder.
removeAndLink :: FilePath -> FilePath -> IO ()
removeAndLink target link = removePathForcibly link >> createDirectoryLink target link

-- | Replaces a path with a regular file.
removeAndWrite :: FilePath -> IO ()
removeAndWrite p = removePathForcibly p >> BS.writeFile p "not a folder"
