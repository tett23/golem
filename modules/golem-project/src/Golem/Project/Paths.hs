-- | Project-relative path normalisation (golem-project ADR 0001).
module Golem.Project.Paths
  ( normalizeRelative,
    PathError (..),
    resolveInRoot,
    resolveEntryInRoot,
    pathErrorMessage,
  )
where

import Data.List (intercalate, isInfixOf, isPrefixOf)
import System.Directory (canonicalizePath, doesFileExist, doesPathExist)
import System.FilePath (makeRelative, splitDirectories, (</>))

data PathError
  = Absolute
  | Url
  | EscapesRoot
  | Missing
  deriving stock (Eq, Show)

-- | The wording of a path error, shared by every diagnostic about a path.
pathErrorMessage :: PathError -> String
pathErrorMessage = \case
  Absolute -> "絶対パスは使えません"
  Url -> "URL は使えません"
  EscapesRoot -> "プロジェクトルートの外を指しています"
  Missing -> "ファイルがありません"

{- | Resolves @.@ and @..@ lexically. Absolute paths, URLs and paths that
climb out of the root are errors.
-}
normalizeRelative :: FilePath -> Either PathError FilePath
normalizeRelative p
  | "://" `isInfixOf` p = Left Url
  | "/" `isPrefixOf` p = Left Absolute
  | otherwise = intercalate "/" . reverse <$> go [] (splitDirectories p)
  where
    go acc [] = Right acc
    go acc ("." : rest) = go acc rest
    go (_ : acc) (".." : rest) = go acc rest
    go [] (".." : _) = Left EscapesRoot
    go acc (seg : rest) = go (seg : acc) rest

{- | Normalises, checks existence and resolves symbolic links. The result is
relative to the canonical root and must stay inside it.
-}
resolveInRoot :: FilePath -> FilePath -> IO (Either PathError FilePath)
resolveInRoot = resolveExisting doesFileExist

-- | For completion, directories as well as files must be inside the root.
resolveEntryInRoot :: FilePath -> FilePath -> IO (Either PathError FilePath)
resolveEntryInRoot = resolveExisting doesPathExist

resolveExisting :: (FilePath -> IO Bool) -> FilePath -> FilePath -> IO (Either PathError FilePath)
resolveExisting existsAt root p = case normalizeRelative p of
  Left e -> pure (Left e)
  Right rel -> do
    exists <- existsAt (root </> rel)
    if not exists
      then pure (Left Missing)
      else do
        croot <- canonicalizePath root
        real <- canonicalizePath (root </> rel)
        let relReal = makeRelative croot real
        pure $
          if relReal == real || ".." `isPrefixOf` relReal
            then Left EscapesRoot
            else Right (intercalate "/" (splitDirectories relReal))
