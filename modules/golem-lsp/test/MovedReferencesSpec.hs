{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}

-- | root ADR 0426: plan reference edits after moves made outside the editor.
module MovedReferencesSpec (movedReferencesTests) where

import Control.Concurrent (forkIO)
import Control.Exception (finally)
import Control.Monad (forM, forM_, unless, void)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key (fromText)
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Foldable (toList)
import Data.List (isPrefixOf, sortOn, tails)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (Down (..))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features qualified as F
import Golem.Lsp.FileMove (planFileMove, planMovedReferences)
import Golem.Lsp.Server (runGolemLspWithHandles)
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import System.Directory (canonicalizePath, createDirectoryIfMissing, createFileLink, doesDirectoryExist, listDirectory, pathIsSymbolicLink, removeDirectory, renamePath)
import System.FilePath (makeRelative, takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (Assertion, assertBool, assertFailure, testCase, (@?=))
import Toml.Syntax (parseRawToml)
import Toml.Syntax.Types (Expr (..), Val (..))

-- A workspace before the move. Paths are relative to the workspace root.
data Fixture = Fixture
  { fxFiles :: [(FilePath, Text)],
    fxDirs :: [FilePath],
    fxProjects :: [FilePath],
    fxSheets :: [FilePath],
    fxOpen :: [(FilePath, Text)],
    fxLinks :: [(FilePath, FilePath)]
  }

-- The outcome of one procedure: the relativized plan and the final files.
-- Open documents are kept apart from the disk under the key "open:" <> path.
data Outcome = Outcome
  { outPlan :: Either Value Value,
    outTree :: Map.Map FilePath Text
  }

type Move = (FilePath, FilePath)

movedReferencesTests :: TestTree
movedReferencesTests =
  testGroup
    "root ADR 0426"
    [ testCase "root ADR 0426 I1, I5: the capability is advertised and the request answers over LSP" $
        let fx = single [("p/img.svg", "<svg/>"), ("p/a.gm", "@figure img.svg\n")] ["p/fig"]
         in withTree fx $ \root -> do
              moveOnDisk root ("p/img.svg", "p/fig/img.svg")
              (caps, result) <- session root (movedRequest root fx [("p/img.svg", "p/fig/img.svg")])
              look ["capabilities", "experimental", "golem", "planMovedReferences"] caps @?= Number 1
              look ["capabilities", "experimental", "golem", "planFileMove"] caps @?= Number 1
              case result of
                Left err -> assertFailure (show err)
                Right plan -> do
                  look ["complete"] plan @?= Bool True
                  map (look ["textDocument", "uri"]) (planEdits plan) @?= [uri root "p/a.gm"],
      testGroup "root ADR 0426 boundary table" boundaryTests,
      testGroup "root ADR 0426 I4: requests failing a check return an error and no edits" errorTests,
      testGroup "root ADR 0426 exhaustive enumeration" enumerationTests
    ]

-- Boundary table rows -------------------------------------------------------

boundaryTests :: [TestTree]
boundaryTests =
  [ testCase "root ADR 0426 I1, I6: moving a file nobody references returns empty groups" $ do
      (_, b) <- equivalent (single [("p/a.gm", "# A\n"), ("p/lone.svg", "<svg/>")] ["p/fig"]) ("p/lone.svg", "p/fig/lone.svg") []
      fmap (look ["groups"]) (outPlan b) @?= Right (Array mempty),
    testCase "root ADR 0426 I1, I2: moving one image to another folder edits the manuscript path" $ do
      (_, b) <- equivalent (single [("p/a.gm", "@figure img.svg\n"), ("p/img.svg", "<svg/>")] ["p/fig"]) ("p/img.svg", "p/fig/img.svg") []
      Map.lookup "p/a.gm" (outTree b) @?= Just "@figure fig/img.svg\n"
      -- the snapshot lists the directories as they are on the disk now
      lookup (String "@p/fig") (snapshotDirectories b) @?= Just [String "@p/fig/img.svg"]
      fmap (String "@p/img.svg" `elem`) (lookup (String "@p") (snapshotDirectories b)) @?= Just False,
    testCase "root ADR 0426 I3: moving two referenced images at once edits both references" $ do
      let fx = single [("p/a.gm", "@figure x.svg\n@figure y.svg\n"), ("p/x.svg", "<svg/>"), ("p/y.svg", "<svg/>")] ["p/fig"]
      b <- viaMoved fx [("p/x.svg", "p/fig/x.svg"), ("p/y.svg", "p/fig/y.svg")] []
      succeeded b
      Map.lookup "p/a.gm" (outTree b) @?= Just "@figure fig/x.svg\n@figure fig/y.svg\n",
    testCase "root ADR 0426 I3: a chapter and the image it uses move together to another project" $ do
      let fx =
            twoProjects
              [ ("p1/manifest.toml", manifest ["c1.gm", "c2.gm"]),
                ("p1/c1.gm", "@figure fig/img.svg\n"),
                ("p1/c2.gm", "# two\n"),
                ("p1/fig/img.svg", "<svg/>"),
                ("p2/manifest.toml", manifest ["before.gm"]),
                ("p2/before.gm", "# before\n")
              ]
          chapterMove = ("p1/c1.gm", "p2/c1.gm")
          moves = [chapterMove, ("p1/fig/img.svg", "p2/img.svg")]
      -- one move at a time is refused before the move: the image would stay behind
      (a, _) <- equivalent fx chapterMove []
      assertBool "planFileMove alone refuses the chapter" (either (const True) (const False) (outPlan a))
      b <- viaMoved fx moves []
      succeeded b
      Map.lookup "p2/c1.gm" (outTree b) @?= Just "@figure img.svg\n"
      chaptersIn b "p1/manifest.toml" @?= Just ["c2.gm"]
      chaptersIn b "p2/manifest.toml" @?= Just ["before.gm", "c1.gm"]
      map (look ["newUri"]) (planChapters b) @?= [String "@p2/c1.gm"],
    testCase "root ADR 0426 I3: two chapters moving to another project append in moves order with one edit per manifest" $ do
      let fx =
            twoProjects
              [ ("p1/manifest.toml", manifest ["c1.gm", "c2.gm", "c3.gm"]),
                ("p1/c1.gm", "# one\n"),
                ("p1/c2.gm", "# two\n"),
                ("p1/c3.gm", "# three\n"),
                ("p2/manifest.toml", manifest ["before.gm"]),
                ("p2/before.gm", "# before\n")
              ]
          moves = [("p1/c2.gm", "p2/c2.gm"), ("p1/c1.gm", "p2/c1.gm")]
      b <- viaMoved fx moves []
      succeeded b
      chaptersIn b "p1/manifest.toml" @?= Just ["c3.gm"]
      chaptersIn b "p2/manifest.toml" @?= Just ["before.gm", "c2.gm", "c1.gm"]
      let manifests = [u | e <- either (const []) planEdits (outPlan b), let u = look ["textDocument", "uri"] e, u `elem` [String "@p1/manifest.toml", String "@p2/manifest.toml"]]
      sortOn show manifests @?= [String "@p1/manifest.toml", String "@p2/manifest.toml"]
      [length (values (look ["edits"] e)) | e <- either (const []) planEdits (outPlan b), look ["textDocument", "uri"] e `elem` manifests] @?= [1, 1]
      map (look ["oldUri"]) (planChapters b) @?= [String "@p1/c2.gm", String "@p1/c1.gm"]
      map (look ["sourceIndices"]) (planChapters b) @?= [indices [1], indices [0]],
    testCase "root ADR 0426 I1, I2: moving a chapter to another folder of its project edits the manifest path" $ do
      let fx = single [("p/manifest.toml", manifest ["a.gm"]), ("p/a.gm", "# A\n")] ["p/part"]
      (_, b) <- equivalent fx ("p/a.gm", "p/part/a.gm") []
      chaptersIn b "p/manifest.toml" @?= Just ["part/a.gm"],
    testCase "root ADR 0426 I1, I2: moving a manuscript with an import edits that import at the new URI" $ do
      let fx = Fixture [("notes/x.gm", "@import \"sub/y.gm\" * as y\n"), ("notes/sub/y.gm", "# Y\n")] [] [] [] [] []
      (_, b) <- equivalent fx ("notes/x.gm", "x.gm") []
      Map.lookup "x.gm" (outTree b) @?= Just "@import \"notes/sub/y.gm\" * as y\n"
      either (const []) (map (look ["textDocument", "uri"]) . planEdits) (outPlan b) @?= [String "@x.gm"],
    testCase "root ADR 0426 I1, I2: moving a folder of manuscripts edits references under it" $ do
      let fx = single [("p/manifest.toml", manifest ["a.gm", "d1/b.gm"]), ("p/a.gm", "@import \"d1/b.gm\" * as b\n"), ("p/d1/b.gm", "# B\n")] []
      (_, b) <- equivalent fx ("p/d1", "p/d3") []
      Map.lookup "p/a.gm" (outTree b) @?= Just "@import \"d3/b.gm\" * as b\n"
      chaptersIn b "p/manifest.toml" @?= Just ["a.gm", "d3/b.gm"],
    testCase "root ADR 0426 I1, I2: moving a chapter to another project edits both manifests and returns the same chapters" $ do
      let fx =
            twoProjects
              [ ("p1/manifest.toml", manifest ["c1.gm", "c2.gm"]),
                ("p1/c1.gm", "# one\n"),
                ("p1/c2.gm", "# two\n"),
                ("p2/manifest.toml", manifest ["before.gm"]),
                ("p2/before.gm", "# before\n")
              ]
      (_, b) <- equivalent fx ("p1/c1.gm", "p2/c1.gm") []
      chaptersIn b "p1/manifest.toml" @?= Just ["c2.gm"]
      chaptersIn b "p2/manifest.toml" @?= Just ["before.gm", "c1.gm"],
    testCase "root ADR 0426 I1, I2: moving a whole project keeps membership and returns the moved projectUri" $ do
      let fx =
            Fixture
              [ ("p/manifest.toml", manifest ["a.gm"]),
                ("p/a.gm", "# A\n"),
                ("p/note.md", "[[../top.md]]\n"),
                ("top.md", "[[p/a.gm]]\n")
              ]
              ["shelf"]
              ["p"]
              ["p/note.md", "top.md", "p/a.gm"]
              []
              []
      (_, b) <- equivalent fx ("p", "shelf/p") []
      Map.lookup "top.md" (outTree b) @?= Just "[[shelf/p/a.gm]]\n"
      Map.lookup "shelf/p/note.md" (outTree b) @?= Just "[[../../top.md]]\n"
      let projectUris = either (const []) (map (look ["projectUri"]) . values . look ["groups"]) (outPlan b)
      assertBool ("a group belongs to the moved project: " <> show projectUris) (String "@shelf/p" `elem` projectUris)
      assertBool "no group keeps the old project URI" (String "@p" `notElem` projectUris),
    testCase "root ADR 0426 I1, I2: a rename changing only case edits to the new name" $ do
      (_, b) <- equivalent (single [("p/a.gm", "@figure img.svg\n"), ("p/img.svg", "<svg/>")] []) ("p/img.svg", "p/IMG.svg") []
      Map.lookup "p/a.gm" (outTree b) @?= Just "@figure IMG.svg\n",
    testCase "root ADR 0426 I1, I2: a source folder emptied and deleted after the move is rebuilt" $ do
      let fx = single [("p/a.gm", "@figure old/img.svg\n"), ("p/old/img.svg", "<svg/>")] []
      (_, b) <- equivalent fx ("p/old/img.svg", "p/img.svg") ["p/old"]
      Map.lookup "p/a.gm" (outTree b) @?= Just "@figure img.svg\n"
      lookup (String "@p/old") (snapshotDirectories b) @?= Nothing,
    testCase "root ADR 0426 I1, I2: moving a Markdown sheet a Wiki link points to edits the link" $ do
      let fx = Fixture [("index.md", "[[notes/scene.md]]\n"), ("notes/scene.md", "# scene\n")] ["archive"] [] ["index.md", "notes/scene.md"] [] []
      (_, b) <- equivalent fx ("notes/scene.md", "archive/scene.md") []
      Map.lookup "index.md" (outTree b) @?= Just "[[archive/scene.md]]\n",
    testCase "root ADR 0426 I1: a dangling reference in the project fails both requests" $ do
      (a, b) <- equivalent (single [("p/a.gm", "@figure missing.svg\n"), ("p/img.svg", "<svg/>")] ["p/fig"]) ("p/img.svg", "p/fig/img.svg") []
      failed (outPlan a)
      failed (outPlan b),
    testCase "root ADR 0426 I1, I2: an open document differing from the disk is edited by its text" $ do
      let fx = (single [("p/a.gm", "@figure other.svg\n"), ("p/img.svg", "<svg/>"), ("p/other.svg", "<svg/>")] ["p/fig"]) {fxOpen = [("p/a.gm", "😀 unsaved\n@figure img.svg\n")]}
      (_, b) <- equivalent fx ("p/img.svg", "p/fig/img.svg") []
      Map.lookup "open:p/a.gm" (outTree b) @?= Just "😀 unsaved\n@figure fig/img.svg\n"
      Map.lookup "p/a.gm" (outTree b) @?= Just "@figure other.svg\n"
  ]

-- I4 error rows -------------------------------------------------------------

errorTests :: [TestTree]
errorTests =
  [ rejects "moves is empty" base [] [] [],
    rejects "chained moves (a to b, b to c)" base [("p/x.svg", "p/y.svg"), ("p/y.svg", "p/z.svg")] [("p/x.svg", "p/z.svg")] ["p/y.svg"],
    rejects "nested moves (a folder and a file in it)" (single [("p/a.gm", "# A\n"), ("p/d/x.svg", "<svg/>")] ["p/e"]) [("p/d", "p/e/d"), ("p/d/x.svg", "p/x.svg")] [("p/d", "p/e/d")] ["p/d/x.svg"],
    rejects "the source still has a file" base [("p/x.svg", "p/fig/x.svg")] [] ["p/x.svg"],
    rejects "the destination has no file" base [("p/gone.svg", "p/fig/gone.svg")] [] ["p/fig/gone.svg"],
    testCase "root ADR 0426 I4, I5: rejects a destination that is a symbolic link" $
      withTree base $ \root -> do
        createFileLink (root </> "p" </> "x.svg") (root </> "p" </> "fig" </> "link.svg")
        expectError root [("p/link.svg", "p/fig/link.svg")] (Just "p/fig/link.svg"),
    testCase "root ADR 0426 I4, I5: rejects a destination containing a symbolic link" $
      withTree base $ \root -> do
        createDirectoryIfMissing True (root </> "p" </> "fig" </> "set")
        createFileLink (root </> "p" </> "x.svg") (root </> "p" </> "fig" </> "set" </> "link.svg")
        expectError root [("p/set", "p/fig/set")] (Just "p/fig/set/link.svg"),
    testCase "root ADR 0426 I4, I5: rejects a destination outside the workspace" $
      withSystemTempDirectory "golem-moved-outside" $ \outsideTmp -> withTree base $ \root -> do
        outside <- canonicalizePath outsideTmp
        renamePath (root </> "p" </> "x.svg") (outside </> "x.svg")
        expectError root [("p/x.svg", outside </> "x.svg")] (Just (outside </> "x.svg")),
    testCase "root ADR 0426 I4, I5: rejects an incomplete inventory" $
      withTree base $ \root -> do
        moveOnDisk root ("p/x.svg", "p/fig/x.svg")
        let params = set "inventoryComplete" (Bool False) (movedRequest root base [("p/x.svg", "p/fig/x.svg")])
        before <- snapshot root Map.empty
        result <- planMovedReferences F.Utf8 (Just root) params
        after <- snapshot root Map.empty
        before @?= after
        failed (relativize root result),
    testCase "root ADR 0426 I4: rejects a workspace not registered at initialize" $
      withTree base $ \root -> do
        moveOnDisk root ("p/x.svg", "p/fig/x.svg")
        result <- planMovedReferences F.Utf8 (Just (root </> "p")) (movedRequest root base [("p/x.svg", "p/fig/x.svg")])
        failed (relativize root result)
  ]
  where
    base = single [("p/a.gm", "@figure x.svg\n"), ("p/x.svg", "<svg/>")] ["p/fig"]
    rejects name fx moves done expected = testCase ("root ADR 0426 I4, I5: rejects " <> name) $
      withTree fx $ \root -> do
        mapM_ (moveOnDisk root) done
        expectError root moves (case expected of [] -> Nothing; e : _ -> Just e)
    expectError root moves expected = do
      before <- snapshot root Map.empty
      result <- planMovedReferences F.Utf8 (Just root) (movedRequest root base moves)
      after <- snapshot root Map.empty
      before @?= after
      case relativize root result of
        Left payload -> do
          let issues = values (look ["issues"] payload)
          length issues @?= 1
          forM_ issues $ \issue -> assertBool "the issue has a reason" (look ["reason"] issue /= Null)
          forM_ expected $ \e -> map (look ["uri"]) issues @?= [relUri root e]
        Right plan -> assertFailure ("expected an error, got " <> show plan)

-- Exhaustive enumeration ----------------------------------------------------

-- Three manuscripts a, b, c in a project p with two folders d1 and d2. Every
-- import graph without self references, each single move and each pair of
-- independent moves among the candidates.
enumerationTests :: [TestTree]
enumerationTests =
  [ testCase ("root ADR 0426 I1, I2, I3, I5: import graph " <> show graph) (checkGraph graph)
  | graph <- graphs
  ]
  where
    graphs = map (\bits -> [edge | (edge, True) <- zip edges bits]) (mapM (const [False, True]) edges)
    edges = [(x, y) | x <- names, y <- names, x /= y]

names :: [Char]
names = "abc"

location :: Char -> FilePath
location 'a' = "p/a.gm"
location 'b' = "p/d1/b.gm"
location _ = "p/d2/c.gm"

candidates :: [Move]
candidates =
  [ ("p/a.gm", "p/d1/a.gm"),
    ("p/a.gm", "p/e.gm"),
    ("p/d1/b.gm", "p/b.gm"),
    ("p/d1/b.gm", "p/d2/b.gm"),
    ("p/d2/c.gm", "p/c.gm"),
    ("p/d2/c.gm", "p/d1/c.gm"),
    ("p/d1", "p/d3"),
    ("p/d1", "p/d2/d1"),
    ("p/d2", "p/d4"),
    ("p/d2", "p/d1/d2")
  ]

independentPairs :: [(Move, Move)]
independentPairs = [(m, n) | (m : rest) <- tails candidates, n <- rest, independent m n]
  where
    independent (o1, n1) (o2, n2) = and [not (related x y) | x <- [o1, n1], y <- [o2, n2]]
    related x y = x == y || (x <> "/") `isPrefixOf` y || (y <> "/") `isPrefixOf` x

graphFixture :: [(Char, Char)] -> Fixture
graphFixture graph =
  single
    ( ("p/manifest.toml", manifest ["a.gm", "d1/b.gm"])
        : [(location x, T.concat [importLine y | (x', y) <- graph, x' == x] <> "# " <> T.singleton x <> "\n") | x <- names]
    )
    []
  where
    importLine y = "@import \"" <> T.pack (makeRelative "p" (location y)) <> "\" * as m" <> T.singleton y <> "\n"

checkGraph :: [(Char, Char)] -> Assertion
checkGraph graph = do
  let fx = graphFixture graph
  forM_ candidates $ \m -> do
    (a, b) <- equivalent fx m []
    succeeded a
    succeeded b
  forM_ independentPairs $ \(m, n) -> do
    let moves = [m, n]
    b <- viaMoved fx moves []
    succeeded b
    -- I3: every import resolves to the moved target, other text unchanged
    forM_ names $ \x -> do
      let path = forward moves (location x)
      text <- maybe (assertFailure ("missing " <> path) >> pure "") pure (Map.lookup path (outTree b))
      let (spellings, rest) = imports text
          (_, original) = imports (fromMaybe "" (lookup (location x) (fxFiles fx)))
      rest @?= original
      [(alias, "p" </> T.unpack s) | (alias, s) <- spellings]
        @?= [(T.singleton y, forward moves (location y)) | (x', y) <- graph, x' == x]
    chaptersIn b "p/manifest.toml"
      @?= Just [T.pack (makeRelative "p" (forward moves (location c))) | c <- "ab"]

-- Split the import lines into (alias, path) and the text with the paths blanked.
imports :: Text -> ([(Text, Text)], Text)
imports text = (mapMaybe spelling ls, T.unlines (map blank ls))
  where
    ls = T.lines text
    spelling line = do
      afterKeyword <- T.stripPrefix "@import \"" line
      let (path, rest) = T.breakOn "\"" afterKeyword
      alias <- T.stripPrefix "\" * as m" rest
      pure (alias, path)
    blank line = case spelling line of
      Just (alias, _) -> "@import _ * as m" <> alias
      Nothing -> line

-- Procedures ----------------------------------------------------------------

-- Run both procedures for one move and check I1, I2 and I5.
equivalent :: Fixture -> Move -> [FilePath] -> IO (Outcome, Outcome)
equivalent fx move cleanup = do
  a <- viaFileMove fx move cleanup
  b <- viaMoved fx [move] cleanup
  case (outPlan a, outPlan b) of
    (Left _, Left _) -> pure ()
    (Right planA, Right planB) -> do
      outTree b @?= outTree a
      look ["chapters"] planB @?= look ["chapters"] planA
      groupUris planB @?= map (mapUris [move]) (groupUris planA)
      forM_ (planEdits planB) $ \e -> assertBool "only TextDocumentEdit" (look ["textDocument"] e /= Null)
    other -> assertFailure ("I1: one request failed alone: " <> show other)
  pure (a, b)
  where
    groupUris plan = [(look ["projectUri"] g, map (look ["textDocument", "uri"]) (values (look ["edits"] g))) | g <- values (look ["groups"] plan)]
    mapUris moves (p, us) = (relMap moves p, map (relMap moves) us)

-- Apply planFileMove's edits before the move, then move.
viaFileMove :: Fixture -> Move -> [FilePath] -> IO Outcome
viaFileMove fx move cleanup = withTree fx $ \root -> do
  result <- relativize root <$> planFileMove F.Utf8 (Just root) (fileMoveRequest root fx move)
  overlay <- either (const (pure (Map.fromList (fxOpen fx)))) (applyPlan root (Map.fromList (fxOpen fx))) result
  moveOnDisk root move
  mapM_ (removeDirectory . (root </>)) cleanup
  tree <- snapshot root (Map.mapKeys (forward [move]) overlay)
  pure (Outcome result tree)

-- Move, then apply planMovedReferences' edits.
viaMoved :: Fixture -> [Move] -> [FilePath] -> IO Outcome
viaMoved fx moves cleanup = withTree fx $ \root -> do
  mapM_ (moveOnDisk root) moves
  mapM_ (removeDirectory . (root </>)) cleanup
  before <- snapshot root Map.empty
  result <- relativize root <$> planMovedReferences F.Utf8 (Just root) (movedRequest root fx moves)
  after <- snapshot root Map.empty
  -- I5: the request does not change the disk
  after @?= before
  let opened = Map.mapKeys (forward moves) (Map.fromList (fxOpen fx))
  overlay <- either (const (pure opened)) (applyPlan root opened) result
  tree <- snapshot root overlay
  pure (Outcome result tree)

fileMoveRequest :: FilePath -> Fixture -> Move -> Value
fileMoveRequest root fx (old, new) =
  object
    [ "workspaceUri" .= uri root "",
      "oldUri" .= uri root old,
      "newUri" .= uri root new,
      "projects" .= [object ["uri" .= uri root p, "plotCsv" .= Null] | p <- fxProjects fx],
      "wikiSheets" .= [object ["uri" .= uri root s, "title" .= Null] | s <- fxSheets fx],
      "documents" .= [object ["uri" .= uri root p, "text" .= t, "version" .= Number 7] | (p, t) <- fxOpen fx],
      "inventoryComplete" .= True
    ]

movedRequest :: FilePath -> Fixture -> [Move] -> Value
movedRequest root fx moves =
  object
    [ "workspaceUri" .= uri root "",
      "moves" .= [object ["oldUri" .= uri root o, "newUri" .= uri root n] | (o, n) <- moves],
      "projects" .= [object ["uri" .= uri root (forward moves p), "plotCsv" .= Null] | p <- fxProjects fx],
      "wikiSheets" .= [object ["uri" .= uri root (forward moves s), "title" .= Null] | s <- fxSheets fx],
      "documents" .= [object ["uri" .= uri root (forward moves p), "text" .= t, "version" .= Number 7] | (p, t) <- fxOpen fx],
      "inventoryComplete" .= True
    ]

forward :: [Move] -> FilePath -> FilePath
forward moves p = case [n <> drop (length o) p | (o, n) <- moves, o == p || (o <> "/") `isPrefixOf` p] of
  q : _ -> q
  [] -> p

relMap :: [Move] -> Value -> Value
relMap moves (String s) | Just rel <- T.stripPrefix "@" s = String ("@" <> T.pack (forward moves (T.unpack rel)))
relMap _ v = v

-- Fixtures and the disk -----------------------------------------------------

single :: [(FilePath, Text)] -> [FilePath] -> Fixture
single files dirs = Fixture files dirs ["p" | any (("p/" `isPrefixOf`) . fst) files] [] [] []

twoProjects :: [(FilePath, Text)] -> Fixture
twoProjects files = Fixture files [] ["p1", "p2"] [] [] []

metadata :: Text
metadata = "\n[metadata]\nid=\"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle=\"T\"\nlanguage=\"ja\"\ndate=2026-10-11\n[targets.html]\n"

manifest :: [Text] -> Text
manifest chapters = "chapters = [" <> T.intercalate ", " (map quote chapters) <> "]" <> metadata
  where
    quote c = "\"" <> c <> "\""

-- The chapter paths of a manifest in the final tree, if its metadata survived.
chaptersIn :: Outcome -> FilePath -> Maybe [Text]
chaptersIn o path = do
  text <- Map.lookup path (outTree o)
  unless (metadata `T.isSuffixOf` text) Nothing
  case parseRawToml text of
    Right (KeyValExpr _ (ValArray _ vals) : _) -> traverse (\case ValString _ t -> Just t; _ -> Nothing) vals
    _ -> Nothing

withTree :: Fixture -> (FilePath -> IO a) -> IO a
withTree fx action = withSystemTempDirectory "golem-moved-references" $ \tmp -> do
  root <- canonicalizePath tmp
  let files = ensureManifests fx
  forM_ (fxDirs fx) $ \d -> createDirectoryIfMissing True (root </> d)
  forM_ files $ \(p, t) -> do
    createDirectoryIfMissing True (takeDirectory (root </> p))
    BS.writeFile (root </> p) (TE.encodeUtf8 t)
  forM_ (fxLinks fx) $ \(target, link) -> createFileLink (root </> target) (root </> link)
  action root

-- A project listed in the fixture always has a manifest.
ensureManifests :: Fixture -> [(FilePath, Text)]
ensureManifests fx = fxFiles fx <> [(p </> "manifest.toml", manifest []) | p <- fxProjects fx, (p </> "manifest.toml") `notElem` map fst (fxFiles fx)]

moveOnDisk :: FilePath -> Move -> IO ()
moveOnDisk root (old, new) = do
  createDirectoryIfMissing True (takeDirectory (root </> new))
  renamePath (root </> old) (root </> new)

snapshot :: FilePath -> Map.Map FilePath Text -> IO (Map.Map FilePath Text)
snapshot root overlay = do
  files <- walk ""
  pure (Map.fromList (files <> [("open:" <> p, t) | (p, t) <- Map.toList overlay]))
  where
    walk rel = do
      entries <- listDirectory (root </> rel)
      concat
        <$> forM
          entries
          ( \name -> do
              let path = if null rel then name else rel </> name
              link <- pathIsSymbolicLink (root </> path)
              dir <- doesDirectoryExist (root </> path)
              if link
                then pure [("link:" <> path, "")]
                else if dir then walk path else (\bytes -> [(path, TE.decodeUtf8 bytes)]) <$> BS.readFile (root </> path)
          )

-- Apply every TextDocumentEdit of a plan to the disk or to the open overlay.
applyPlan :: FilePath -> Map.Map FilePath Text -> Value -> IO (Map.Map FilePath Text)
applyPlan root overlay plan = foldl (\acc e -> acc >>= applyOne e) (pure overlay) (planEdits plan)
  where
    applyOne e opened = do
      let target = case look ["textDocument", "uri"] e of
            String t -> t
            other -> T.pack (show other)
          rel = T.unpack (T.drop 1 target)
          edits = values (look ["edits"] e)
      case Map.lookup rel opened of
        Just text -> pure (Map.insert rel (applyEdits text edits) opened)
        Nothing -> do
          text <- TE.decodeUtf8 <$> BS.readFile (root </> rel)
          BS.writeFile (root </> rel) (TE.encodeUtf8 (applyEdits text edits))
          pure opened

applyEdits :: Text -> [Value] -> Text
applyEdits text edits = TE.decodeUtf8 (foldl apply bytes (sortOn (Down . fst) spans))
  where
    bytes = TE.encodeUtf8 text
    starts = scanl (+) 0 (map ((+ 1) . BS.length) (BS.split 10 bytes))
    offset p = (starts !! int (look ["line"] p)) + int (look ["character"] p)
    spans = [((offset (look ["range", "start"] e), offset (look ["range", "end"] e)), newText e) | e <- edits]
    newText e = case look ["newText"] e of
      String t -> TE.encodeUtf8 t
      _ -> ""
    apply acc ((s, en), t) = BS.take s acc <> t <> BS.drop en acc
    int (Number n) = floor n :: Int
    int _ = 0

planEdits :: Value -> [Value]
planEdits plan = concatMap (values . look ["edits"]) (values (look ["groups"] plan))

snapshotDirectories :: Outcome -> [(Value, [Value])]
snapshotDirectories =
  either (const []) (map (\d -> (look ["uri"] d, map (look ["uri"]) (values (look ["entries"] d)))) . values . look ["snapshot", "directories"]) . outPlan

planChapters :: Outcome -> [Value]
planChapters = either (const []) (values . look ["chapters"]) . outPlan

succeeded :: Outcome -> Assertion
succeeded o = case outPlan o of
  Left e -> assertFailure ("expected a plan, got " <> show e)
  Right _ -> pure ()

failed :: Either Value Value -> Assertion
failed (Left _) = pure ()
failed (Right plan) = assertFailure ("expected an error, got " <> show plan)

indices :: [Int] -> Value
indices = Array . foldMap (pure . Number . fromIntegral)

-- Replace every file URI under the root with "@" <> its relative path.
relativize :: FilePath -> Either Value Value -> Either Value Value
relativize root = either (Left . go) (Right . go)
  where
    go (String s)
      | "file://" `T.isPrefixOf` s, Just p <- L.uriToFilePath (L.Uri s) = String (relativePath p)
      | otherwise = String s
    go (Array xs) = Array (fmap go xs)
    go (Object o) = Object (fmap go o)
    go v = v
    relativePath p
      | p == root = "@"
      | (root <> "/") `isPrefixOf` p = "@" <> T.pack (makeRelative root p)
      | otherwise = T.pack p

relUri :: FilePath -> FilePath -> Value
relUri root rel = case relativize root (Right (uri root rel)) of
  Right v -> v
  Left v -> v

uri :: FilePath -> FilePath -> Value
uri root rel = let L.Uri u = L.filePathToUri (if null rel then root else root </> rel) in String u

session :: FilePath -> Value -> IO (Value, Either (M.TResponseError (M.Method_CustomMethod "golem/planMovedReferences" :: M.Method M.ClientToServer M.Request)) Value)
session root params = do
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  let config = LT.defaultConfig {LT.messageTimeout = 10, LT.lspConfig = KM.singleton "golem" (object ["fileMove" .= object ["version" .= Number 1, "workspaceUri" .= uri root ""]])}
  flip finally (hClose clientOut >> hClose clientIn) $
    LT.runSessionWithHandles clientOut clientIn config LT.fullLatestClientCaps root $ do
      M.TResponseMessage _ _ initResult <- LT.initializeResponse
      M.TResponseMessage _ _ result <- LT.request (M.SMethod_CustomMethod (Proxy @"golem/planMovedReferences")) params
      pure (either (const Null) (\(L.InitializeResult caps _) -> object ["capabilities" .= caps]) initResult, result)

set :: Text -> Value -> Value -> Value
set key value (Object fields) = Object (KM.insert (fromText key) value fields)
set _ _ value = value

look :: [Text] -> Value -> Value
look [] value = value
look (key : keys) (Object fields) = maybe Null (look keys) (KM.lookup (fromText key) fields)
look _ _ = Null

values :: Value -> [Value]
values (Array xs) = toList xs
values _ = []
