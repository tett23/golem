{- | How the files of a project are read (docs/adr/0199): from the disk
under a root, or from a table of paths and bytes, so that the same build
reads either. Writing (build/) is not here.
-}
module Golem.Project.Files
  ( Files (..),
    diskFiles,
    memoryFiles,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Golem.Project.Paths (PathError (..), normalizeRelative, resolveInRoot)
import System.Directory (getFileSize)
import System.FilePath ((</>))
import System.IO.Error (doesNotExistErrorType, mkIOError)

-- | A record of functions, not a class (docs/adr/0199).
data Files = Files
  { -- | resolves a path by the rules of 'resolveInRoot'; the result is relative to the root
    filesResolve :: FilePath -> IO (Either PathError FilePath),
    -- | the bytes of a resolved path
    filesRead :: FilePath -> IO ByteString,
    -- | the size of a resolved path in bytes (for G02088)
    filesSize :: FilePath -> IO Integer
  }

-- | The files under a root on the disk: what Golem has always read.
diskFiles :: FilePath -> Files
diskFiles root =
  Files
    { filesResolve = resolveInRoot root,
      filesRead = \rel -> BS.readFile (root </> rel),
      filesSize = \rel -> getFileSize (root </> rel)
    }

{- | The files of a table whose keys are paths from the root, normalised
('normalizeRelative'). A path is normalised and looked up; one the table
does not have is 'Missing'. There are no symbolic links, so nothing is
canonicalised.
-}
memoryFiles :: Map FilePath ByteString -> Files
memoryFiles table =
  Files
    { filesResolve = \p -> pure (normalizeRelative p >>= \rel -> if Map.member rel table then Right rel else Left Missing),
      filesRead = \rel -> maybe (ioError (missing rel)) pure (Map.lookup rel table),
      filesSize = \rel -> maybe (ioError (missing rel)) (pure . toInteger . BS.length) (Map.lookup rel table)
    }
  where
    missing rel = mkIOError doesNotExistErrorType "memoryFiles" Nothing (Just rel)
