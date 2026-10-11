module Golem.Syntax.Span
  ( FileId (..),
    SrcSpan (..),
    mkSpan,
    spanLength,
    spanContains,
    FileTable,
    emptyFileTable,
    registerFile,
    lookupPath,
    lookupFileId,
    fileTableEntries,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map

{- | Identifies a source file. Ids are assigned in a deterministic order
(manifest order, then first reference), never per run.
-}
newtype FileId = FileId Int
  deriving stock (Eq, Ord, Show)

-- | A half-open byte range in the UTF-8 encoding of a file.
data SrcSpan = SrcSpan
  { spanFile :: !FileId,
    spanStart :: !Int,
    spanEnd :: !Int
  }
  deriving stock (Eq, Ord, Show)

mkSpan :: FileId -> Int -> Int -> SrcSpan
mkSpan f s e
  | s < 0 || e < s = error ("mkSpan: invalid range " <> show (s, e))
  | otherwise = SrcSpan f s e

spanLength :: SrcSpan -> Int
spanLength sp = spanEnd sp - spanStart sp

-- | Whether the first span contains the second one.
spanContains :: SrcSpan -> SrcSpan -> Bool
spanContains outer inner =
  spanFile outer == spanFile inner
    && spanStart outer <= spanStart inner
    && spanEnd inner <= spanEnd outer

{- | Bidirectional mapping between file ids and normalised paths
relative to the project root.
-}
data FileTable = FileTable
  { ftNext :: !Int,
    ftByPath :: !(Map FilePath FileId),
    ftById :: !(Map FileId FilePath)
  }
  deriving stock (Eq, Show)

emptyFileTable :: FileTable
emptyFileTable = FileTable 0 Map.empty Map.empty

-- | Registers a path, returning the existing id if already present.
registerFile :: FilePath -> FileTable -> (FileId, FileTable)
registerFile path ft = case Map.lookup path (ftByPath ft) of
  Just fid -> (fid, ft)
  Nothing ->
    let fid = FileId (ftNext ft)
     in ( fid,
          FileTable
            { ftNext = ftNext ft + 1,
              ftByPath = Map.insert path fid (ftByPath ft),
              ftById = Map.insert fid path (ftById ft)
            }
        )

lookupPath :: FileId -> FileTable -> Maybe FilePath
lookupPath fid = Map.lookup fid . ftById

lookupFileId :: FilePath -> FileTable -> Maybe FileId
lookupFileId p = Map.lookup p . ftByPath

-- | Entries in id order.
fileTableEntries :: FileTable -> [(FileId, FilePath)]
fileTableEntries = Map.toAscList . ftById
