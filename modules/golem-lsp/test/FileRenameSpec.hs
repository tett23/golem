module FileRenameSpec (fileRenameTests) where

import Control.Concurrent (forkIO)
import Control.Monad (void)
import Control.Monad.IO.Class (liftIO)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Lsp.FileRename (planEmetImports, planImports, planManifest, planPlotCsv, planStyle, planWiki, renamePath, validateRenames)
import Golem.Lsp.Server (runGolemLspWithHandles, safeRenamePair)
import Golem.Lsp.Workspace (openWorkspace, renameWorkspace, updateFile, wsOverlay, wsSourceFiles)
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (createDirectory, createFileLink, renameDirectory, renameFile)
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
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
      testCase "R4: Aleph plot edits only file cells and keeps CSV quoting" $ do
        let source = "scene,file,memo\none,\"chapters/a,1.gm\",\"chapters/a,1.gm\"\ntwo,chapters/a.gm,note\n"
        case planPlotCsv [("chapters", "parts")] source of
          Left err -> fail err
          Right edits -> do
            length edits @?= 2
            foldr (\(start, end, replacement) text -> T.take start text <> replacement <> T.drop end text) source edits
              @?= "scene,file,memo\none,\"parts/a,1.gm\",\"chapters/a,1.gm\"\ntwo,parts/a.gm,note\n",
      testCase "R1: Wiki links follow a moved target and preserve heading and label" $ do
        let sheets = [("notes/a.md", Nothing), ("notes/target.md", Nothing)]
        planWiki [("notes/target.md", "notes/new.md")] "notes/a.md" sheets "[[target#Heading|Label]]\n"
          @?= Right [(2, 8, "new")],
      testCase "R1: moving a Wiki source rebases a relative path but not a title" $ do
        let sheets = [("notes/a.md", Nothing), ("notes/target.md", Nothing), ("chapters/other.md", Just "Target")]
        planWiki [("notes/a.md", "chapters/a.md")] "notes/a.md" sheets "[[target.md]] [[Target]]\n"
          @?= Right [(2, 11, "../notes/target.md")],
      testCase "R4: Wiki parser ignores code spans, fences and an ambiguous name" $ do
        let sheets = [("notes/a.md", Nothing), ("one/target.md", Nothing), ("two/target.md", Nothing)]
        planWiki [("one/target.md", "one/new.md")] "notes/a.md" sheets "`[[target]]`\n```\n[[target]]\n```\n[[target]]\n"
          @?= Right [],
      testCase "R2: Wiki byte ranges account for non-ASCII text and paired backticks" $ do
        let sheets = [("notes/a.md", Nothing), ("notes/target.md", Nothing)]
        planWiki [("notes/target.md", "notes/new.md")] "notes/a.md" sheets "章\n``[[target]]`` [[target]]\n"
          @?= Right [(21, 27, "new")],
      testCase "R1: Wiki names compare in NFC without changing their byte range" $ do
        let sheets = [("notes/a.md", Nothing), ("notes/Café.md", Nothing)]
        planWiki [("notes/Café.md", "notes/new.md")] "notes/a.md" sheets "[[Café]]\n"
          @?= Right [(2, 8, "new")],
      testCase "R1: a renamed Wiki name uses a path when the new name is ambiguous" $ do
        let sheets = [("src/a.md", Nothing), ("one/target.md", Nothing), ("two/new.md", Nothing)]
        planWiki [("one/target.md", "one/new.md")] "src/a.md" sheets "[[target]]\n"
          @?= Right [(2, 8, "../one/new.md")],
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
          "new/a.gm" `elem` wsSourceFiles renamed @?= True,
      testCase "R1: a symlink outside the project yields no rename edits" $
        withSystemTempDirectory "golem-rename-root" $ \root ->
          withSystemTempDirectory "golem-rename-outside" $ \outside -> do
            TIO.writeFile (root </> "a.gm") "# A\n"
            TIO.writeFile (outside </> "a.gm") "# Outside\n"
            createFileLink (outside </> "a.gm") (root </> "link.gm")
            safeRenamePair root ("a.gm", "b.gm") >>= (@?= True)
            safeRenamePair root ("link.gm", "new.gm") >>= (@?= False),
      testCase "R2: willRename returns old URI edits without renaming files" $
        withSystemTempDirectory "golem-rename-protocol" $ \root -> do
          TIO.writeFile (root </> "manifest.toml") "chapters=[\"a.gm\"]\n[metadata]\nid=\"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle=\"T\"\nlanguage=\"ja\"\ndate=2026-10-11\n[targets.html]\n"
          TIO.writeFile (root </> "a.gm") "@import \"旧 章.gm\" as old\n"
          TIO.writeFile (root </> "旧 章.gm") "# Old\n"
          (serverIn, clientOut) <- createPipe
          (clientIn, serverOut) <- createPipe
          void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
          (edits, noSecondEdit) <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig {LT.messageTimeout = 10} LT.fullLatestClientCaps root $ do
            let L.Uri old = L.filePathToUri (root </> "旧 章.gm")
                L.Uri new = L.filePathToUri (root </> "新 章.gm")
                files = L.RenameFilesParams [L.FileRename old new]
            M.TResponseMessage _ _ result <- LT.request M.SMethod_WorkspaceWillRenameFiles files
            let before = case result of
              Right (L.InL (L.WorkspaceEdit _ (Just changes) _)) ->
                [(L.uriToFilePath uri, version, length replacements) | L.InL (L.TextDocumentEdit (L.OptionalVersionedTextDocumentIdentifier uri version) replacements) <- changes]
              _ -> []
            liftIO $ do
              TIO.writeFile (root </> "a.gm") "@import \"新 章.gm\" as old\n"
              renameFile (root </> "旧 章.gm") (root </> "新 章.gm")
            LT.sendNotification M.SMethod_WorkspaceDidRenameFiles files
            M.TResponseMessage _ _ second <- LT.request M.SMethod_WorkspaceWillRenameFiles files
            pure (before, case second of Right (L.InR L.Null) -> True; _ -> False)
          hClose clientOut
          edits @?= [(Just (root </> "a.gm"), L.InR L.Null, 1)]
          noSecondEdit @?= True
    ]
