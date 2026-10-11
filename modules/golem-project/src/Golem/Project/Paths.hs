-- | Project-relative path normalisation (golem-project ADR 0001).
module Golem.Project.Paths
  ( normalizeRelative,
    PathError (..),
    resolveInRoot,
  )
where

import Data.List (intercalate, isInfixOf, isPrefixOf)
import System.Directory (canonicalizePath, doesFileExist)
import System.FilePath (makeRelative, splitDirectories, (</>))

data PathError
  = Absolute
  | Url
  | EscapesRoot
  | Missing
  deriving stock (Eq, Show)

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
resolveInRoot root p = case normalizeRelative p of
  Left e -> pure (Left e)
  Right rel -> do
    exists <- doesFileExist (root </> rel)
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
