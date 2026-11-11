module FileRenameSpec (fileRenameTests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Lsp.FileRename (planEmetImports, planImports, planManifest, planStyle, renamePath, validateRenames)
import Golem.Lsp.Workspace (openWorkspace, renameWorkspace, updateFile, wsOverlay, wsSourceFiles)
import System.Directory (createDirectory, renameDirectory)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, (@?=))

fileRenameTests :: TestTree
fileRenameTests =
  testGroup
    "Golem ADR 0338"
    [ testCase "R1: a renamed folder changes only complete path components" $ do
        renamePath [("chapters/章", "chapters/節")] "chapters/章/a.gm" @?= Right "chapters/節/a.gm"
        renamePath [("chapters/章", "chapters/節")] "chapters/章外/a.gm" @?= Right "chapters/章外/a.gm",
      testCase "R1: duplicate operations apply once and conflicting nested operations fail" $ do
        renamePath [("chapters", "parts"), ("chapters", "parts")] "chapters/a.gm" @?= Right "parts/a.gm"
        renamePath [("chapters", "parts"), ("chapters/a.gm", "other/a.gm")] "chapters/a.gm" @?= Left "conflicting destination",
      testCase "R2: conflict fails before searching for references" $ do
        validateRenames [("chapters", "parts"), ("chapters/a.gm", "other/a.gm")] @?= Left "conflicting destination"
        validateRenames [("chapters", "parts"), ("chapters/a.gm", "parts/a.gm")] @?= Right [("chapters", "parts"), ("chapters/a.gm", "parts/a.gm")],
      testCase "R2: every import occurrence has its own byte range" $ do
        planImports [("a.gm", "b.gm")] "@import a.gm as first\n@import a.gm as second\n"
          @?= Right [(8, 12, "b.gm"), (30, 34, "b.gm")],
      testCase "R2: quoted import keeps its quoting and escapes the new path" $ do
        planImports [("a.gm", "a name.gm")] "@import \"a.gm\" as first\n"
          @?= Right [(8, 14, "\"a name.gm\"")],
      testCase "R1: an unrelated word in the manuscript stays unchanged" $ do
        planImports [("a.gm", "b.gm")] "a.gm\n@import b.gm as first\n" @?= Right [],
      testCase "R2: figure, table and listing edit only their file arguments" $ do
        let source = "@figure a.png web=\"web.png\"\n@table data.csv\n@listing code.txt\n"
            operations = [("a.png", "b.png"), ("web.png", "screen.png"), ("data.csv", "other.csv"), ("code.txt", "new.txt")]
        case planImports operations source of
          Left err -> fail err
          Right edits -> do
            length edits @?= 4
            foldr (\(start, end, replacement) text -> T.take start text <> replacement <> T.drop end text) source edits
              @?= "@figure b.png web=\"screen.png\"\n@table other.csv\n@listing new.txt\n",
      testCase "R2: Emet import edits only its path literal" $ do
        planEmetImports [("lib/a.emet", "lib/b.emet")] "import \"lib/a.emet\"\n-- lib/a.emet\n"
          @?= Right [(7, 19, "\"lib/b.emet\"")],
      testCase "R2: Emet file requirements and File.read literals both change" $ do
        let source = "r :: <file \"a.tsv\"> String\nr = File.read \"a.tsv\"\n"
        case planEmetImports [("a.tsv", "b.tsv")] source of
          Left err -> fail err
          Right edits -> do
            length edits @?= 2
            foldr (\(start, end, replacement) text -> T.take start text <> replacement <> T.drop end text) source edits
              @?= "r :: <file \"b.tsv\"> String\nr = File.read \"b.tsv\"\n",
      testCase "R2: duplicate manifest chapters edit every value but no unrelated text" $ do
        let source = "chapters = [\"a.gm\", [\"a.gm\"], {file = \"a.gm\", title = \"a.gm\"}]\n"
        case planManifest [("a.gm", "b.gm")] source of
          Left err -> fail err
          Right edits -> do
            length edits @?= 3
            foldr (\(start, end, replacement) text -> T.take start text <> replacement <> T.drop end text) source edits
              @?= "chapters = [\"b.gm\", [\"b.gm\"], {file = \"b.gm\", title = \"a.gm\"}]\n",
      testCase "R2: manifest bibliography, Emet and plugin files retain unrelated names" $ do
        let source = "chapters=[\"a.gm\"]\nbibliography=[\"refs.json\"]\n[functions.requires]\nfile=[\"data.txt\"]\n[plugins.chart]\npath=\"plugin.wasm\"\n[plugins.chart.data]\nsymbols=\"symbols.tsv\"\n[[filters]]\nfunction=\"fn.emet\"\nfilter=\"lookup\"\nfiles=[\"input.json\"]\n"
            operations = [("a.gm", "b.gm"), ("refs.json", "citations.json"), ("data.txt", "new.txt"), ("plugin.wasm", "new.wasm"), ("symbols.tsv", "new.tsv"), ("fn.emet", "new.emet"), ("input.json", "new.json")]
        case planManifest operations source of
          Left err -> fail err
          Right edits -> do
            length edits @?= 7
            T.isInfixOf "filter=\"lookup\"" (foldr (\(start, end, replacement) text -> T.take start text <> replacement <> T.drop end text) source edits) @?= True,
      testCase "R2: style font paths change but font role references remain" $ do
        let source = "[fonts.body]\nja=\"fonts/a.otf\"\nlatin=\"fonts/b.otf\"\n[paragraph-styles.body]\nfont=\"body\"\n"
        case planStyle [("fonts/a.otf", "fonts/new.otf")] source of
          Left err -> fail err
          Right edits -> do
            length edits @?= 1
            foldr (\(start, end, replacement) text -> T.take start text <> replacement <> T.drop end text) source edits
              @?= "[fonts.body]\nja=\"fonts/new.otf\"\nlatin=\"fonts/b.otf\"\n[paragraph-styles.body]\nfont=\"body\"\n",
      testCase "R3: didRename discards old overlays and refreshes the source index" $
        withSystemTempDirectory "golem-rename" $ \root -> do
          createDirectory (root </> "part")
          TIO.writeFile (root </> "manifest.toml") "chapters=[\"part/a.gm\"]\n[metadata]\nid=\"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle=\"T\"\nlanguage=\"ja\"\ndate=2026-10-11\n[targets.html]\n"
          TIO.writeFile (root </> "part/a.gm") "# A\n"
          ws <- openWorkspace root
          edited <- updateFile ws "part/a.gm" "# unsaved\n"
          renameDirectory (root </> "part") (root </> "new")
          renamed <- renameWorkspace edited [("part", "new")]
          Map.member "part/a.gm" (wsOverlay renamed) @?= False
          "new/a.gm" `elem` wsSourceFiles renamed @?= True
    ]
