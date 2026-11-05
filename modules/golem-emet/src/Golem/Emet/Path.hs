{- | The paths of .emet, from the root of the project: those of @import@
(docs/adr/0160) and those of the requirement @file@ (docs/adr/0161). The
check is lexical, as golem-emet touches no file system; the driver
resolves the links of the files it reads.
-}
module Golem.Emet.Path
  ( normalizePath,
  )
where

import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.Text (Text)
import System.FilePath (splitDirectories)

{- | A path from the root of the project with @.@ and @..@ resolved:
absolute paths, URLs and paths that climb out of the root are errors
(G03003), with the words of the message.
-}
normalizePath :: FilePath -> Either Text FilePath
normalizePath p
  | "://" `isInfixOf` p = Left "URL は使えません"
  | "/" `isPrefixOf` p = Left "絶対パスは使えません"
  | otherwise = intercalate "/" . reverse <$> go [] (splitDirectories p)
  where
    go acc [] = Right acc
    go acc ("." : rest) = go acc rest
    go (_ : acc) (".." : rest) = go acc rest
    go [] (".." : _) = Left "プロジェクトルートの外を指しています"
    go acc (seg : rest) = go (seg : acc) rest
