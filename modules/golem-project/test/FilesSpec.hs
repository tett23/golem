{- | How the files of a project are read (docs/adr/0199): from the disk,
or from a table of paths and bytes.
-}
module FilesSpec (tests) where

import Data.ByteString qualified as BS
import Data.List (intercalate, isPrefixOf)
import Data.Map.Strict qualified as Map
import Golem.Project.Files
import Golem.Project.Paths
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.Directory (createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

tests :: TestTree
tests =
  testGroup
    "Files (docs/adr/0199)"
    [ testCase "memoryFiles resolves the errors of normalizeRelative as they are" $ do
        let files = memoryFiles (Map.fromList [("a.gm", "a"), ("dir/b.gm", "b")])
        r1 <- filesResolve files "/a.gm"
        r1 @?= Left Absolute
        r2 <- filesResolve files "https://example.com/a.gm"
        r2 @?= Left Url
        r3 <- filesResolve files "../a.gm"
        r3 @?= Left EscapesRoot
        r4 <- filesResolve files "dir/../../a.gm"
        r4 @?= Left EscapesRoot,
      testCase "memoryFiles: a path the table does not have is Missing; the others are normalised" $ do
        let files = memoryFiles (Map.fromList [("a.gm", "a"), ("dir/b.gm", "b")])
        missing <- filesResolve files "c.gm"
        missing @?= Left Missing
        dir <- filesResolve files "dir"
        dir @?= Left Missing
        found <- filesResolve files "./dir/x/../b.gm"
        found @?= Right "dir/b.gm"
        bytes <- filesRead files "dir/b.gm"
        bytes @?= "b"
        size <- filesSize files "dir/b.gm"
        size @?= 1,
      testProperty "diskFiles and memoryFiles resolve and read every path alike in a tree without links" sameAsDisk
    ]

-- | The names of the generated trees and paths: lower case only, so that a file system that ignores case gives the same.
segment :: Gen FilePath
segment = Gen.element ["a", "b", "c.gm", "d.toml"]

-- | A tree of files: paths of one to three segments, no file inside another file.
tree :: Gen (Map.Map FilePath BS.ByteString)
tree = do
  paths <- Gen.list (Range.linear 0 12) (intercalate "/" <$> Gen.list (Range.linear 1 3) segment)
  let ok p kept = not (any (\q -> (q <> "/") `isPrefixOf` p || (p <> "/") `isPrefixOf` q || q == p) kept)
      chosen = foldl (\kept p -> if ok p kept then kept <> [p] else kept) [] paths
  contents <- mapM (const (Gen.bytes (Range.linear 0 64))) chosen
  pure (Map.fromList (zip chosen contents))

-- | A path as a project may write it: segments with . and .., absolute, or a URL.
query :: [FilePath] -> Gen FilePath
query known = do
  let piece = Gen.frequency [(5, segment), (1, pure "."), (1, pure "..")]
  written <- intercalate "/" <$> Gen.list (Range.linear 1 4) piece
  Gen.frequency
    [ (6, pure written),
      (3, if null known then pure written else Gen.element known),
      (1, pure ("/" <> written)),
      (1, pure ("https://" <> written))
    ]

sameAsDisk :: Property
sameAsDisk = property $ do
  files <- forAll tree
  paths <- forAll (Gen.list (Range.linear 1 20) (query (Map.keys files)))
  results <- evalIO $ withSystemTempDirectory "golem-files" $ \root -> do
    mapM_ (\(p, b) -> createDirectoryIfMissing True (takeDirectory (root </> p)) >> BS.writeFile (root </> p) b) (Map.toList files)
    let disk = diskFiles root
        memory = memoryFiles files
    mapM
      ( \p -> do
          d <- filesResolve disk p
          m <- filesResolve memory p
          dr <- either (const (pure Nothing)) (fmap Just . filesRead disk) d
          mr <- either (const (pure Nothing)) (fmap Just . filesRead memory) m
          ds <- either (const (pure Nothing)) (fmap Just . filesSize disk) d
          ms <- either (const (pure Nothing)) (fmap Just . filesSize memory) m
          pure (p, (d, dr, ds), (m, mr, ms))
      )
      paths
  mapM_ (\(p, d, m) -> annotate p >> d === m) results
