-- | Path component matching for file and folder rename operations (Golem ADR 0338).
module Golem.Lsp.FileRename (renamePath, validateRenames, planImports, planEmetImports, planManifest, planStyle) where

import Control.Monad (forM)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum)
import Data.List
  ( nub,
    sortOn,
  )
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet (parseModule)
import Golem.Emet.Syntax (Decl (DImport), Loc (..), Module (..))
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Project.Manifest (positionSpan, readTomlTable)
import Golem.Project.Paths (normalizeRelative)
import Golem.Syntax (FileId (..), SrcSpan (..))
import System.FilePath (joinPath, splitDirectories)
import Toml.Semantics (Table' (..), Value' (..))
import Toml.Syntax (Position)

{- | Apply all operations against the same pre-rename path. Duplicate pairs
have no extra effect; overlapping pairs must agree on the destination.
-}
renamePath :: [(FilePath, FilePath)] -> FilePath -> Either String FilePath
renamePath pairs written = do
  path <- normalized written
  operations <- traverse (\(from, to) -> (,) <$> normalized from <*> normalized to) pairs
  let components = splitDirectories path
      destinations =
        nub
          [ joinPath (splitDirectories to <> drop (length prefix) components)
          | (from, to) <- operations,
            let prefix = splitDirectories from,
            take (length prefix) components == prefix
          ]
  case destinations of
    [] -> Right path
    [destination] -> Right destination
    _ -> Left "conflicting destination"
  where
    normalized = either (Left . show) Right . normalizeRelative

{- | Check the full operation before reading any document. For a nested
operation, the destination must agree with its parent's mapping.
-}
validateRenames :: [(FilePath, FilePath)] -> Either String [(FilePath, FilePath)]
validateRenames pairs = do
  normalized <- traverse (\(from, to) -> (,) <$> path from <*> path to) pairs
  let unique = nub normalized
  mapped <- traverse (renamePath unique . fst) unique
  if mapped == map snd unique then Right unique else Left "conflicting destination"
  where
    path = either (Left . show) Right . normalizeRelative

{- | The byte range and replacement of each literal @import path. A caller
converts ranges to the client's negotiated position encoding.
-}
planImports :: [(FilePath, FilePath)] -> Text -> Either String [(Int, Int, Text)]
planImports operations source = do
  let (ast, _, _) = parseAst (FileId 0) source
      bytes = TE.encodeUtf8 source
      raw sp = TE.decodeUtf8 (BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) bytes))
      sites (A.Located _ (A.BlockCommand (A.Located _ name) args body)) = commandSites name args <> concatMap sites body
      sites (A.Located _ (A.Attributed commands inner)) = concatMap sites commands <> maybe [] sites inner
      sites (A.Located _ (A.BulletList items)) = concatMap (concatMap sites) items
      sites (A.Located _ (A.OrderedList items)) = concatMap (concatMap sites) items
      sites (A.Located _ (A.DefList groups)) = concatMap (concatMap (concatMap sites) . A.dgDefs) groups
      sites _ = []
      commandSites name args = case (name, args) of
        ("import", arg : _) -> [(A.locSpan arg, path) | Just path <- [importPath (map A.locValue args)]]
        ("figure", _) -> take 1 (mapMaybe positional args) <> mapMaybe (keyword "web") args
        ("table", _) -> take 1 (mapMaybe positional args) <> mapMaybe (keyword "src") args
        ("listing", _) -> take 1 (mapMaybe positional args) <> mapMaybe (keyword "src") args
        _ -> []
      positional (A.Located sp (A.Positional value)) = (sp,) <$> literal value
      positional _ = Nothing
      keyword wanted (A.Located sp (A.Keyword (A.Located _ key) value))
        | key == wanted,
          Just path <- literal value,
          let token = BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) bytes),
          Just equals <- BS.elemIndex 61 token =
            let suffix = BS.drop (equals + 1) token
                spaces = BS.length (BS.takeWhile (== 32) suffix)
             in Just (sp {spanStart = spanStart sp + equals + 1 + spaces}, path)
      keyword _ _ = Nothing
  concat
    <$> forM
      (concatMap sites (A.fileBlocks ast))
      ( \(sp, written) -> do
          original <- either (Left . show) Right (normalizeRelative (T.unpack written))
          destination <- renamePath operations (T.unpack written)
          let oldToken = raw sp
              newText = T.pack destination
              replacement =
                if T.isPrefixOf "\"" oldToken || not (T.all bareChar newText)
                  then quoted newText
                  else newText
          pure (if destination == original then [] else [(spanStart sp, spanEnd sp, replacement)])
      )
  where
    bareChar c = isAlphaNum c || c `elem` ("./_-" :: String)
    importPath [A.Positional (A.Word path), A.Positional (A.Word "as"), A.Positional (A.Word _)] = Just path
    importPath [A.Positional (A.StringLit path), A.Positional (A.Word "as"), A.Positional (A.Word _)] = Just path
    importPath _ = Nothing
    literal (A.Word path) = Just path
    literal (A.StringLit path) = Just path
    literal _ = Nothing

-- | Emet's parsed import declarations carry the path literal's byte range.
planEmetImports :: [(FilePath, FilePath)] -> Text -> Either String [(Int, Int, Text)]
planEmetImports operations source = do
  let imports = case parseModule (FileId 0) source of
        Right (Module decls) -> [(path, loc) | DImport _ path loc <- decls]
        Left _ -> []
  concat
    <$> forM
      imports
      ( \(path, Loc start end) -> do
          original <- either (Left . show) Right (normalizeRelative (T.unpack path))
          destination <- renamePath operations (T.unpack path)
          pure (if destination == original then [] else [(start, end, quoted (T.pack destination))])
      )

quoted :: Text -> Text
quoted value = "\"" <> T.concatMap quoteChar value <> "\""
  where
    quoteChar '\\' = "\\\\"
    quoteChar '"' = "\\\""
    quoteChar c = T.singleton c

{- | The individual chapter path values of manifest.toml, including nested
arrays and table entries. A token range is found from each TOML value's
parser position, so repeated values remain separate edits.
-}
planManifest :: [(FilePath, FilePath)] -> Text -> Either String [(Int, Int, Text)]
planManifest = planToml manifestPaths

planStyle :: [(FilePath, FilePath)] -> Text -> Either String [(Int, Int, Text)]
planStyle = planToml stylePaths

planToml :: (Table' Position -> [(Position, Text)]) -> [(FilePath, FilePath)] -> Text -> Either String [(Int, Int, Text)]
planToml sites operations source = do
  table <- maybe (Left "invalid manifest TOML") Right (readTomlTable source)
  let bytes = TE.encodeUtf8 source
  sortOn (\(start, _, _) -> start) . concat
    <$> forM
      (sites table)
      ( \(pos, written) -> do
          original <- either (Left . show) Right (normalizeRelative (T.unpack written))
          destination <- renamePath operations (T.unpack written)
          if destination == original
            then pure []
            else do
              let start = spanStart (positionSpan (FileId 0) source (Just pos))
              end <- maybe (Left "invalid chapter path token") (Right . (+ start)) (tomlStringLength (BS.drop start bytes))
              let value = T.pack destination
              if T.any (`elem` ("\n\r\t" :: String)) value
                then Left "unsupported chapter path"
                else pure [(start, end, quoted value)]
      )

manifestPaths :: Table' Position -> [(Position, Text)]
manifestPaths top =
  maybe [] chapterEntries (lookupValue "chapters" top)
    <> maybe [] textValues (lookupValue "bibliography" top)
    <> maybe [] (\functions -> maybe [] (\requires -> maybe [] textValues (lookupValue "file" requires)) (asTable =<< lookupValue "requires" functions)) (asTable =<< lookupValue "functions" top)
    <> maybe [] pluginPaths (asTable =<< lookupValue "plugins" top)
    <> maybe [] filterPaths (lookupValue "filters" top)
  where
    chapterEntries (Text' pos path) = [(pos, path)]
    chapterEntries (List' _ items) = concatMap chapterEntries items
    chapterEntries (Table' _ fields) = maybe [] textValues (lookupValue "file" fields)
    chapterEntries _ = []
    textValues (Text' pos path) = [(pos, path)]
    textValues (List' _ items) = concatMap textValues items
    textValues _ = []
    pluginPaths (MkTable plugins) = concatMap (\(_, plugin) -> maybe [] pluginFields (asTable plugin)) (Map.elems plugins)
    pluginFields fields =
      maybe [] textValues (lookupValue "path" fields)
        <> maybe [] (\(MkTable values) -> concatMap (textValues . snd) (Map.elems values)) (asTable =<< lookupValue "data" fields)
    filterPaths (List' _ items) = concatMap oneFilter items
    filterPaths _ = []
    oneFilter (Table' _ fields) = maybe [] textValues (lookupValue "function" fields) <> maybe [] textValues (lookupValue "files" fields)
    oneFilter _ = []
    asTable (Table' _ fields) = Just fields
    asTable _ = Nothing

lookupValue :: Text -> Table' Position -> Maybe (Value' Position)
lookupValue key (MkTable fields) = snd <$> Map.lookup key fields

stylePaths :: Table' Position -> [(Position, Text)]
stylePaths top = maybe [] fontPaths (asTable =<< lookupValue "fonts" top)
  where
    fontPaths (MkTable roles) = concatMap rolePaths (Map.elems roles)
    rolePaths (_, Table' _ fields) = maybe [] one (lookupValue "ja" fields) <> maybe [] one (lookupValue "latin" fields)
    rolePaths _ = []
    one (Text' pos path) = [(pos, path)]
    one _ = []
    asTable (Table' _ fields) = Just fields
    asTable _ = Nothing

-- | The byte length of a TOML basic or literal string at the given offset.
tomlStringLength :: BS.ByteString -> Maybe Int
tomlStringLength bytes = do
  (quote, _) <- BS.uncons bytes
  if quote /= 34 && quote /= 39
    then Nothing
    else do
      let triple = BS.take 3 bytes == BS.replicate 3 quote
          opening = if triple then 3 else 1
          closing = opening
          len = BS.length bytes
          seek i escaped
            | i >= len = Nothing
            | quote == 34 && not escaped && BS.index bytes i == 92 = seek (i + 1) True
            | escaped = seek (i + 1) False
            | BS.take closing (BS.drop i bytes) == BS.replicate closing quote = Just (i + closing)
            | otherwise = seek (i + 1) False
      seek opening False
