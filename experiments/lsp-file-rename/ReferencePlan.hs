module ReferencePlan (plan, renamePath) where

import Control.Monad (forM)
import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Parser (parseAst)
import Golem.Parser.AST
import Golem.Project.Imports (importSite, isPath)
import Golem.Project.Paths (normalizeRelative)
import Golem.Syntax
import System.FilePath (splitDirectories, joinPath)

-- A decoded, project-relative mapping. Repeated pairs are the same
-- operation; overlapping pairs must agree on the destination.
renamePath :: [(FilePath, FilePath)] -> FilePath -> Either String FilePath
renamePath pairs written = do
  old <- either (Left . show) Right (normalizeRelative written)
  let components = splitDirectories old
      candidates = nub [joinPath (splitDirectories to <> drop (length parts) components)
                       | (from,to) <- pairs, let parts = splitDirectories from,
                         take (length parts) components == parts]
  case candidates of
    [] -> Right old
    [new] -> Right new
    _ -> Left "conflicting destination"

-- The prototype accepts only .gm import arguments that keep their token
-- kind and need no escape. A complete serializer is an acceptance test.
plan :: [(FilePath, FilePath)] -> Text -> Either String [(LineCol, LineCol, Text)]
plan pairs text = do
  let (ast, _, _) = parseAst (FileId 0) text
      index = mkLineIndex text
      bytes = TE.encodeUtf8 text
      get sp = TE.decodeUtf8 (BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) bytes))
      sites (Located sp (BlockCommand (Located _ "import") args@(arg : _) _)) =
        [(locSpan arg, isPath site) | Right site <- [importSite sp (map locValue args)]]
      sites (Located _ (Attributed cmds _)) = concatMap sites cmds
      sites _ = []
  fmap concat $ forM (concatMap sites (fileBlocks ast)) $ \(sp, target) -> do
    renamed <- renamePath pairs (T.unpack target)
    current <- either (Left . show) Right (normalizeRelative (T.unpack target))
    if current == renamed then pure [] else do
      let raw = get sp
          name = T.pack renamed
          replacement = if "\"" `T.isPrefixOf` raw then "\"" <> name <> "\"" else name
      if T.any (`elem` ("\n\r\t\\" :: String)) name || T.any (== '"') name || (not ("\"" `T.isPrefixOf` raw) && T.any (== ' ') name)
        then Left "unsupported literal spelling"
        else pure [(offsetToUtf16LineCol index (spanStart sp), offsetToUtf16LineCol index (spanEnd sp), replacement)]

