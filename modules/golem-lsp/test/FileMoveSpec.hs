{-# LANGUAGE DataKinds #-}

module FileMoveSpec (fileMoveTests) where

import Control.Concurrent (forkIO)
import Control.Exception (finally)
import Control.Monad (void)
import Data.Aeson (Value (..), object, toJSON, (.=))
import Data.Aeson.Key (fromText)
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Lsp.FileMove.Chapters (ChapterTransfer (..), transferChapters)
import Golem.Lsp.FileRename (planWikiMove)
import Golem.Lsp.Server (runGolemLspWithHandles)
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (canonicalizePath, createDirectoryIfMissing, createFileLink, doesPathExist)
import System.FilePath ((</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertFailure, testCase, (@?=))
import Toml.Syntax (parseRawToml)
import Toml.Syntax.Types (Expr (..), Val (..))

fileMoveTests :: TestTree
fileMoveTests =
  testGroup
    "root ADR 0399"
    [ testCase "root ADR 0399 A1: a single request plans both manifests and returns the open Wiki snapshot" $
        fixture $ \root -> do
          (caps, result) <- session root (request root True)
          look ["capabilities", "experimental", "golem", "planFileMove"] caps @?= Number 1
          case result of
            Left err -> assertFailure (show err)
            Right plan -> do
              look ["complete"] plan @?= Bool True
              let groups = values (look ["groups"] plan)
                  chapters = values (look ["chapters"] plan)
              length groups @?= 3
              map (look ["sourceIndices"]) chapters
                @?= map (jsonArray . map Number) [[0, 0], [0, 1], [1]]
              let docs = values (look ["snapshot", "documents"] plan)
              assertBool "the unsaved Wiki snapshot is retained" $
                any (\doc -> look ["uri"] doc == uri root "notes.md" && look ["version"] doc == Number 12) docs
          doesPathExist (root </> "元 作品" </> "章") >>= (@?= True)
          doesPathExist (root </> "別 作品" </> "新章") >>= (@?= False),
      testCase "root ADR 0399 I5: incomplete inventory returns a structured error" $
        fixture $ \root -> do
          (_, result) <- session root (request root False)
          case result of
            Left (M.TResponseError _ _ (Just payload)) ->
              length (values (look ["issues"] payload)) @?= 1
            other -> assertFailure (show other),
      testCase "root ADR 0399 I2: chapter partition keeps nested table attributes and comments" $ do
        let source = "# manifest\nchapters = [\n  # moving-group\n  [\n    \"sub/a.gm\", # moving-a\n    {file='sub/b.gm', master='special', page-numbering={start=3}},\n  ],\n  # staying\n  \"remain.gm\"\n]\n[metadata]\ntitle=\"Old\"\n"
            dest = "chapters = [\"existing.gm\"] # outside\n[metadata]\ntitle=\"New\"\n"
            move path
              | Just suffix <- T.stripPrefix "sub/" (T.pack path) =
                  Right (Just ("target/new/" <> T.unpack suffix, "new/" <> T.unpack suffix))
              | otherwise = Right Nothing
        case transferChapters move source (Just dest) of
          Right ([a], [b], summary) -> do
            map chapterIndices summary @?= [[0, 0], [0, 1]]
            let oldText = applyEdit source a
                newText = applyEdit dest b
            case (parseRawToml oldText, parseRawToml newText) of
              (Right _, Right _) -> pure ()
              _ -> assertFailure ("invalid modified manifests: " <> show (oldText, newText))
            assertBool "unmoved source commentary stays" ("# manifest" `T.isInfixOf` oldText && "# staying" `T.isInfixOf` oldText)
            assertBool "moved commentary, destination metadata and table attributes survive" $
              all (`T.isInfixOf` newText) ["# moving-group", "# moving-a", "master='special'", "page-numbering={start=3}", "# outside", "existing.gm"]
          other -> assertFailure (show other),
      testCase "root ADR 0399 I2: array-table chapters retain attributes and attached comments" $ do
        let source = "title = 'other key'\n# moving\n[[chapters]]\nfile = 'a.gm' # line note\n[chapters.page-numbering]\nstart = 3\n\n[metadata]\ntitle = 'keep'\n"
            dest = "[[chapters]]\nfile = 'before.gm'\n"
            move _ = Right (Just ("destination/new/a.gm", "new/a.gm"))
        case transferChapters move source (Just dest) of
          Right (a, b, summary) -> do
            map chapterIndices summary @?= [[0]]
            let oldText = foldr (flip applyEdit) source a
                newText = foldr (flip applyEdit) dest b
            assertBool "unrelated keys are untouched" ("title = 'other key'" `T.isInfixOf` oldText && "title = 'keep'" `T.isInfixOf` oldText)
            assertBool "moved array table attributes and comments survive" $
              all (`T.isInfixOf` newText) ["# moving", "# line note", "page-numbering", "start = 3", "before.gm", "new/a.gm"]
            case (parseRawToml oldText, parseRawToml newText) of
              (Right _, Right _) -> pure ()
              _ -> assertFailure (show (oldText, newText))
          other -> assertFailure (show other),
      testCase "root ADR 0399 I1: moving a Wiki source preserves the closest basename target" $ do
        let move = [("p/note.md", "q/note.md")]
            sheets = [("p/note.md", Nothing), ("p/scene.md", Nothing), ("q/scene.md", Nothing)]
        planWikiMove move "p/note.md" sheets "[[scene#Heading|Label]]" @?= Right [(2, 7, "../p/scene.md")],
      testCase "root ADR 0399 I3, I5: a registered workspace without projects can return a complete empty plan" $
        withSystemTempDirectory "golem-move-no-project" $ \tmp -> do
          root <- canonicalizePath tmp
          createDirectoryIfMissing True (root </> "folder")
          TIO.writeFile (root </> "one.txt") "text"
          let params =
                object
                  [ "workspaceUri" .= uri root "",
                    "oldUri" .= uri root "one.txt",
                    "newUri" .= uri root "folder/one.txt",
                    "projects" .= ([] :: [Value]),
                    "wikiSheets" .= ([] :: [Value]),
                    "inventoryComplete" .= True,
                    "documents" .= ([] :: [Value])
                  ]
          (_, result) <- session root params
          case result of
            Left err -> assertFailure (show err)
            Right plan -> do
              look ["complete"] plan @?= Bool True
              look ["groups"] plan @?= jsonArray []
              length (values (look ["snapshot", "directories"] plan)) @?= 2,
      testCase "root ADR 0399 I1, I4: only explicitly listed plot files are edited" $
        fixture $ \root -> do
          let plot = "scene,file\none,章/a.gm\n"
          TIO.writeFile (root </> "元 作品" </> "named-plot.csv") plot
          TIO.writeFile (root </> "元 作品" </> "plot.csv") plot
          let params =
                set "newUri" (uri root "元 作品/新章")
                  $ set "projects" (jsonArray [object ["uri" .= uri root "元 作品", "plotCsv" .= uri root "元 作品/named-plot.csv"], object ["uri" .= uri root "別 作品", "plotCsv" .= Null]])
                  $ request root True
          (_, result) <- session root params
          case result of
            Left err -> assertFailure (show err)
            Right plan -> do
              let edits = concatMap (values . look ["edits"]) (values (look ["groups"] plan))
                  changedDocs = map (look ["textDocument", "uri"]) edits
              assertBool "enabled plot gets a path edit" (uri root "元 作品/named-plot.csv" `elem` changedDocs)
              assertBool "other CSV stays unchanged" (uri root "元 作品/plot.csv" `notElem` changedDocs),
      testCase "root ADR 0399 I6: individual manifest moves cannot create a nested project" $
        fixture $ \root -> do
          createDirectoryIfMissing True (root </> "別 作品" </> "notes")
          let params =
                set "oldUri" (uri root "元 作品/manifest.toml")
                  $ set "newUri" (uri root "別 作品/notes/manifest.toml")
                  $ request root True
          (_, result) <- session root params
          case result of
            Left (M.TResponseError _ _ (Just payload)) ->
              map (look ["uri"]) (values (look ["issues"] payload)) @?= [uri root "元 作品/manifest.toml"]
            other -> assertFailure (show other),
      testCase "root ADR 0399 I1, I5: a nested build directory can contain an Emet reference source" $
        fixture $ \root -> do
          createDirectoryIfMissing True (root </> "元 作品" </> "draft" </> "build")
          TIO.writeFile (root </> "元 作品" </> "a.txt") "asset"
          TIO.writeFile (root </> "元 作品" </> "draft" </> "build" </> "helper.emet") "r = File.read \"a.txt\"\n"
          let params =
                set "oldUri" (uri root "元 作品/a.txt")
                  $ set "newUri" (uri root "別 作品/a.txt")
                  $ request root True
          (_, result) <- session root params
          case result of
            Left (M.TResponseError _ _ (Just payload)) ->
              map (look ["uri"]) (values (look ["issues"] payload)) @?= [uri root "元 作品/draft/build/helper.emet"]
            other -> assertFailure (show other),
      testCase "root ADR 0399 I2: chapter paths containing line breaks are valid TOML strings" $ do
        let source = "chapters=['x.gm']\n"
            target = "folder\nname/x.gm"
        case transferChapters (const (Right (Just (target, target)))) source (Just "chapters=[]\n") of
          Right (_, [edit], _) ->
            case parseRawToml (applyEdit "chapters=[]\n" edit) of
              Right [KeyValExpr _ (ValArray _ [ValString _ path])] -> path @?= T.pack target
              other -> assertFailure (show other)
          other -> assertFailure (show other),
      testCase "root ADR 0399 I1, I5: uppercase Markdown is included in the Wiki index" $
        fixture $ \root -> do
          TIO.writeFile (root </> "UPPER.MD") "[[元 作品/章/a.gm#heading|label]]\n"
          let sheets = values (look ["wikiSheets"] (request root True))
              params = set "wikiSheets" (jsonArray (sheets <> [object ["uri" .= uri root "UPPER.MD", "title" .= Null]])) (request root True)
          (_, result) <- session root params
          case result of
            Left err -> assertFailure (show err)
            Right plan -> do
              let edits = concatMap (values . look ["edits"]) (values (look ["groups"] plan))
              assertBool "uppercase Markdown gets an edit" (uri root "UPPER.MD" `elem` map (look ["textDocument", "uri"]) edits),
      testCase "root ADR 0399 I1, I6: cross-project image reference outside the destination fails with its range" $
        fixture $ \root -> do
          TIO.writeFile (root </> "元 作品" </> "image.svg") "<svg/>"
          TIO.writeFile (root </> "元 作品" </> "章" </> "a.gm") "@figure image.svg\n"
          (_, result) <- session root (request root True)
          case result of
            Left (M.TResponseError _ _ (Just payload)) -> do
              let issues = values (look ["issues"] payload)
              map (look ["uri"]) issues @?= [uri root "元 作品/章/a.gm"]
              map (look ["targetUri"]) issues @?= [uri root "元 作品/image.svg"]
              assertBool "range is attached" (all ((/= Null) . look ["range"]) issues)
            other -> assertFailure (show other),
      testCase "root ADR 0399 I3, I5: an undecodable indexed Emet document causes an error" $
        fixture $ \root -> do
          BS.writeFile (root </> "別 作品" </> "bad.emet") (BS.pack [0xff])
          (_, result) <- session root (request root True)
          case result of
            Left (M.TResponseError _ _ (Just payload)) ->
              map (look ["uri"]) (values (look ["issues"] payload)) @?= [uri root "別 作品/bad.emet"]
            other -> assertFailure (show other),
      testCase "root ADR 0399 I6: symlinks inside the move subtree are rejected" $
        fixture $ \root -> do
          createFileLink (root </> "notes.md") (root </> "元 作品" </> "章" </> "alias.md")
          (_, result) <- session root (request root True)
          case result of
            Left (M.TResponseError _ _ (Just payload)) ->
              map (look ["uri"]) (values (look ["issues"] payload)) @?= [uri root "元 作品/章/alias.md"]
            other -> assertFailure (show other)
    ]

applyEdit :: Text -> (Int, Int, Text) -> Text
applyEdit source (start, end, replacement) =
  let bytes = TE.encodeUtf8 source
   in TE.decodeUtf8 (BS.take start bytes) <> replacement <> TE.decodeUtf8 (BS.drop end bytes)

fixture :: (FilePath -> IO a) -> IO a
fixture action = withSystemTempDirectory "golem-move-protocol" $ \tmp -> do
  root <- canonicalizePath tmp
  createDirectoryIfMissing True (root </> "元 作品" </> "章")
  createDirectoryIfMissing True (root </> "別 作品")
  let metadata = "\n[metadata]\nid=\"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle=\"T\"\nlanguage=\"ja\"\ndate=2026-10-11\n[targets.html]\n"
  mapM_
    (\(p, text) -> TIO.writeFile (root </> p) text)
    [ ("元 作品/manifest.toml", "chapters = [[\"章/a.gm\", { file = \"章/b.gm\", page-numbering = {start = 2} }], \"章/a.gm\"]" <> metadata),
      ("元 作品/章/a.gm", "@import \"章/b.gm\" * as b\n"),
      ("元 作品/章/b.gm", "# 子孫\n"),
      ("別 作品/manifest.toml", "chapters = [\"before.gm\"]" <> metadata),
      ("別 作品/before.gm", "# 既存章\n"),
      ("notes.md", "[[元 作品/章/a.gm]]\n")
    ]
  action root

uri :: FilePath -> FilePath -> Value
uri root rel = let L.Uri u = L.filePathToUri (if null rel then root else root </> rel) in String u

request :: FilePath -> Bool -> Value
request root complete =
  object
    [ "workspaceUri" .= uri root "",
      "oldUri" .= uri root "元 作品/章",
      "newUri" .= uri root "別 作品/新章",
      "projects" .= map (\p -> object ["uri" .= uri root p, "plotCsv" .= Null]) ["元 作品", "別 作品"],
      "wikiSheets" .= map (\p -> object ["uri" .= uri root p, "title" .= Null]) ["notes.md", "元 作品/章/a.gm", "元 作品/章/b.gm", "別 作品/before.gm"],
      "inventoryComplete" .= complete,
      "documents" .= [object ["uri" .= uri root "notes.md", "text" .= String "😀 [[元 作品/章/a.gm#見出し|章]]\n", "version" .= Number 12]]
    ]

session :: FilePath -> Value -> IO (Value, Either (M.TResponseError (M.Method_CustomMethod "golem/planFileMove" :: M.Method M.ClientToServer M.Request)) Value)
session root params = do
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  let config = LT.defaultConfig {LT.messageTimeout = 10, LT.lspConfig = KM.singleton "golem" (object ["fileMove" .= object ["version" .= Number 1, "workspaceUri" .= uri root ""]])}
  flip finally (hClose clientOut >> hClose clientIn) $
    LT.runSessionWithHandles clientOut clientIn config LT.fullLatestClientCaps root $ do
      M.TResponseMessage _ _ initResult <- LT.initializeResponse
      M.TResponseMessage _ _ result <- LT.request (M.SMethod_CustomMethod (Proxy @"golem/planFileMove")) params
      pure (either (const Null) (\(L.InitializeResult caps _) -> object ["capabilities" .= caps]) initResult, result)

set :: Text -> Value -> Value -> Value
set key value (Object fields) = Object (KM.insert (fromText key) value fields)
set _ _ value = value

look :: [Text] -> Value -> Value
look [] value = value
look (key : keys) (Object fields) = maybe Null (look keys) (KM.lookup (fromText key) fields)
look _ _ = Null

values :: Value -> [Value]
values (Array xs) = foldr (:) [] xs
values _ = []

jsonArray :: [Value] -> Value
jsonArray = toJSON
