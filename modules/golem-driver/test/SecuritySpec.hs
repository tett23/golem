{- | Untrusted projects: what a manuscript repository must not be able to do
to the machine that builds it, or to the readers of its HTML (docs/adr ADR
0035, and the security audit of 2026-10-17 that it follows).
-}
module SecuritySpec (securityTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (isPrefixOf)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing, createDirectoryLink, createFileLink, doesFileExist, pathIsSymbolicLink)
import System.FilePath ((</>))
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
        doesFileExist (v </> "html" </> "a.xhtml") >>= assertBool "nothing written there" . not,
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
        doesFileExist (root </> "build" </> "html" </> "a.xhtml") >>= assertBool "written in build/html"
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
        map diagCode (filter isError (brDiagnostics dev)) @?= [DiagnosticCode "G08010"]
        BS.readFile oldPdf >>= (@?= "previous pdf")
        BS.readFile oldPages >>= (@?= "previous pages")
        prod <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optProfile = Prod}
        map diagCode (filter isError (brDiagnostics prod)) @?= [DiagnosticCode "G08010"]
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
        map diagCode (filter isError (brDiagnostics r)) @?= [DiagnosticCode "G08010"]
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
      testCase "a figure path with a quote stays inside the src attribute" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        img <- tinyImage
        let name = "q\" onerror=\"alert(1).jpg"
        project tmp "" horizontalStyle "# 章\n\n@figure \"q\\\" onerror=\\\"alert(1).jpg\" alt=\"t\"\n" [(name, bytes) | (_, bytes) <- img]
        r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
        page <- TIO.readFile (tmp </> "build/html/a.xhtml")
        assertBool (T.unpack page) ("<img src=\"q&quot; onerror=&quot;alert(1).jpg\"" `T.isInfixOf` page)
        assertBool (T.unpack page) (not ("onerror=\"" `T.isInfixOf` page)),
      testCase "a font role with a quote stays inside the CSS strings" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        let style = horizontalStyle <> "\n[fonts.\"x\\\" } body { color: red } x { a: \\\"\"]\nlatin = \"fonts/a\\\").otf\"\n"
        project tmp "" style "本文。\n" [("fonts/a\").otf", "font")]
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
