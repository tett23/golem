{- | Untrusted projects: what a manuscript repository must not be able to do
to the machine that builds it, or to the readers of its HTML (docs/adr ADR
0035, and the security audit of 2026-10-17 that it follows).
-}
module SecuritySpec (securityTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing, createDirectoryLink, doesFileExist)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A one-chapter project with the source, the style and the files.
project :: FilePath -> BS.ByteString -> BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> IO ()
project tmp manifestHead style source files = do
  BS.writeFile (tmp </> "manifest.toml") (manifestHead <> miniManifest <> "\n[targets.html]\n[targets.text]\n")
  BS.writeFile (tmp </> "style.toml") style
  BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 source)
  forM_ files $ \(to, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> to)) >> BS.writeFile (tmp </> to) bytes

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
      testCase "build as a symbolic link out of the project is G08013, and nothing there is removed" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
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
      localOption (mkTimeout 30000000) $ testCase "a year of 1e1000000000 in CSL-JSON does not stop the build" $ withSystemTempDirectory "golem-sec" $ \tmp -> do
        project tmp "bibliography = [\"refs.json\"]\n" horizontalStyle "本文[cite a][cite b]。\n" [("refs.json", "[{\"id\": \"a\", \"title\": \"T\", \"issued\": {\"date-parts\": [[1e1000000000]]}}, {\"id\": \"b\", \"title\": \"U\", \"issued\": {\"date-parts\": [[1e-1000000000]]}}]")]
        r <- build (defaultOptions tmp) {optTargets = Just [TargetText]}
        map diagCode (filter isError (brDiagnostics r)) @?= []
    ]
