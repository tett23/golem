-- | Path component matching for file and folder rename operations (Golem ADR 0338).
module Golem.Lsp.FileRename (renamePath, validateRenames, planImports, planEmetImports, planManifest, planStyle, planPlotCsv, planWiki) where

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
import Data.Text.Normalize (NormalizationMode (NFC), normalize)
import Golem.Emet (parseModule)
import Golem.Emet.Syntax (Decl (DImport), Loc (..), Module (..))
import Golem.Emet.Syntax qualified as E
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Project.Manifest (positionSpan, readTomlTable)
import Golem.Project.Paths (normalizeRelative)
import Golem.Syntax (FileId (..), SrcSpan (..))
import System.FilePath (joinPath, splitDirectories, takeBaseName, takeDirectory, takeExtension, (</>))
import Toml.Semantics (Table' (..), Value' (..))
import Toml.Syntax (Position)

data CsvCell = CsvCell !Int !Int !Text !Bool

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
  let bytes = TE.encodeUtf8 source
      imports = case parseModule (FileId 0) source of
        Right (Module decls) -> [(path, locStart loc, locEnd loc) | DImport _ path loc <- decls] <> concatMap (declSites bytes) decls
        Left _ -> []
  concat
    <$> forM
      imports
      ( \(path, start, end) -> do
          original <- either (Left . show) Right (normalizeRelative (T.unpack path))
          destination <- renamePath operations (T.unpack path)
          pure (if destination == original then [] else [(start, end, quoted (T.pack destination))])
      )

declSites :: BS.ByteString -> E.Decl -> [(Text, Int, Int)]
declSites bytes = \case
  E.DSig sig -> signatureSites bytes sig
  E.DEq equation -> equationSites bytes equation
  E.DData _ _ _ _ constructors -> concatMap constructorSites constructors
  E.DType _ _ _ _ typeExpr -> typeSites bytes typeExpr
  E.DImport {} -> []
  where
    constructorSites (E.ConPos _ _ types) = concatMap (typeSites bytes) types
    constructorSites (E.ConRec _ _ fields) = concatMap (typeSites bytes . snd) fields

signatureSites :: BS.ByteString -> E.Signature -> [(Text, Int, Int)]
signatureSites bytes sig = maybe [] (rowSites bytes) (E.sigRow sig) <> typeSites bytes (E.sigType sig)

equationSites :: BS.ByteString -> E.Equation -> [(Text, Int, Int)]
equationSites bytes equation = rhsSites bytes (E.eqRhs equation) <> concatMap (whereSites bytes) (E.eqWheres equation)

whereSites :: BS.ByteString -> E.Where -> [(Text, Int, Int)]
whereSites bytes (E.Where _ bindings) = concatMap bindingSites bindings
  where
    bindingSites (E.BSig sig) = signatureSites bytes sig
    bindingSites (E.BEq equation) = equationSites bytes equation

rhsSites :: BS.ByteString -> E.Rhs -> [(Text, Int, Int)]
rhsSites bytes = \case
  E.Plain expr -> exprSites bytes expr
  E.Guarded branches -> concatMap branchSites branches
  where
    branchSites (guarded, wheres) =
      (case E.guardCond guarded of E.GExpr expr -> exprSites bytes expr; E.GOtherwise _ -> [])
        <> exprSites bytes (E.guardBody guarded)
        <> concatMap (whereSites bytes) wheres

typeSites :: BS.ByteString -> E.TypeE -> [(Text, Int, Int)]
typeSites bytes = \case
  E.TCon _ _ args -> concatMap (typeSites bytes) args
  E.TFun before row after -> typeSites bytes before <> maybe [] (rowSites bytes) row <> typeSites bytes after
  E.TTuple _ types -> concatMap (typeSites bytes) types
  E.TNamed _ _ ty defaultValue -> typeSites bytes ty <> maybe [] (exprSites bytes) defaultValue
  E.TVar {} -> []

rowSites :: BS.ByteString -> E.RowE -> [(Text, Int, Int)]
rowSites bytes row =
  [ (path, start, end)
  | requirement <- E.rowReqs row,
    E.reqKind requirement == "file",
    [path] <- [E.reqArgs requirement],
    let Loc from to = E.reqLoc requirement,
    let raw = BS.take (to - from) (BS.drop from bytes),
    Just quoteStart <- [BS.elemIndex 34 raw],
    let start = from + quoteStart,
    Just lengthOfString <- [tomlStringLength (BS.drop start bytes)],
    let end = start + lengthOfString
  ]

exprSites :: BS.ByteString -> E.Expr -> [(Text, Int, Int)]
exprSites bytes expr = case expr of
  E.EApp function argument -> fileRead function argument <> exprSites bytes function <> exprSites bytes argument
  E.EBin _ _ left right -> exprSites bytes left <> exprSites bytes right
  E.ENeg _ inner -> exprSites bytes inner
  E.ECase _ subject alternatives -> exprSites bytes subject <> concatMap alternativeSites alternatives
  E.ETernary _ condition left right -> exprSites bytes condition <> exprSites bytes left <> exprSites bytes right
  E.ERecord _ _ fields -> concatMap (exprSites bytes . (\(_, _, value) -> value)) fields
  E.EParen _ inner -> exprSites bytes inner
  E.EList _ items -> concatMap (exprSites bytes) items
  E.ETuple _ items -> concatMap (exprSites bytes) items
  _ -> []
  where
    fileRead function argument = case (unparen function, unparen argument) of
      (E.EVar _ (E.QName (Just "File") "read"), E.EStr (Loc start end) path) -> [(path, start, end)]
      _ -> []
    unparen (E.EParen _ inner) = unparen inner
    unparen inner = inner
    alternativeSites alt = rhsSites bytes (E.altRhs alt) <> concatMap (whereSites bytes) (E.altWheres alt)

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

{- | Aleph's plot.csv uses its file column as a project-root-relative path.
Only an explicitly enabled plot file is passed to this function.
-}
planPlotCsv :: [(FilePath, FilePath)] -> Text -> Either String [(Int, Int, Text)]
planPlotCsv operations source = do
  rows <- csvRows (TE.encodeUtf8 source)
  case rows of
    [] -> Right []
    header : body -> case [index | (index, CsvCell _ _ name _) <- zip [0 ..] header, T.strip name == "file"] of
      [] -> Right []
      [column] -> sortOn (\(start, _, _) -> start) . concat <$> traverse (oneCell column) body
      _ -> Left "duplicate plot file column"
  where
    oneCell column cells = case drop column cells of
      CsvCell start end raw wasQuoted : _
        | let written = T.strip raw,
          not (T.null written),
          Right original <- normalizeRelative (T.unpack written) -> do
            destination <- renamePath operations (T.unpack written)
            let value = T.pack destination
                replacement = if wasQuoted || T.any (`elem` (",\"\n\r" :: String)) value then "\"" <> T.replace "\"" "\"\"" value <> "\"" else value
            pure (if destination == original then [] else [(start, end, replacement)])
      _ -> Right []

csvRows :: BS.ByteString -> Either String [[CsvCell]]
csvRows bytes = rows 0
  where
    lengthOfInput = BS.length bytes
    byte i = BS.index bytes i
    rows i
      | i >= lengthOfInput = Right []
      | otherwise = do
          (cells, next) <- row i
          (cells :) <$> rows next
    row i = do
      (cell, end) <- field i
      if end >= lengthOfInput
        then Right ([cell], end)
        else case byte end of
          44 -> do
            (rest, next) <- row (end + 1)
            Right (cell : rest, next)
          10 -> Right ([cell], end + 1)
          13 -> Right ([cell], end + if end + 1 < lengthOfInput && byte (end + 1) == 10 then 2 else 1)
          _ -> Left "invalid plot CSV delimiter"
    field start
      | start < lengthOfInput && byte start == 34 = do
          end <- quotedEnd (start + 1)
          let raw = BS.take (end - start - 2) (BS.drop (start + 1) bytes)
          Right (CsvCell start end (T.replace "\"\"" "\"" (TE.decodeUtf8 raw)) True, end)
      | otherwise =
          let end = start + BS.length (BS.takeWhile (\b -> b /= 44 && b /= 10 && b /= 13) (BS.drop start bytes))
           in Right (CsvCell start end (TE.decodeUtf8 (BS.take (end - start) (BS.drop start bytes))) False, end)
    quotedEnd i
      | i >= lengthOfInput = Left "unclosed plot CSV quote"
      | byte i /= 34 = quotedEnd (i + 1)
      | i + 1 < lengthOfInput && byte (i + 1) == 34 = quotedEnd (i + 2)
      | otherwise = Right (i + 1)

-- | Rewrite the target of Aleph Wiki links using its complete sheet list.
-- Paths in this function are relative to Aleph's workspace, not Golem's root.
planWiki :: [(FilePath, FilePath)] -> FilePath -> [(FilePath, Maybe Text)] -> Text -> Either String [(Int, Int, Text)]
planWiki operations sourcePath sheets source = do
  newSource <- renamePath operations sourcePath
  let movedSheets = [(either (const path) id (renamePath operations path), title) | (path, title) <- sheets]
  concat <$> traverse (oneLink newSource movedSheets) (wikiLinks source)
  where
    oneLink newSource movedSheets (start, end, written) =
      case wikiResolve sourcePath sheets written of
        Nothing -> Right []
        Just (oldTarget, byPath, relative) -> do
          newTarget <- renamePath operations oldTarget
          let replacement
                | not byPath = T.pack (takeBaseName newTarget)
                | otherwise =
                    let base = if relative then takeDirectory newSource else "."
                        rel = wikiRelative base newTarget
                     in T.pack (if takeExtension (T.unpack written) == "" && takeExtension rel == ".md" then dropExtension rel else rel)
              resolvesSame = case wikiResolve newSource movedSheets written of
                Just (path, _, _) -> path == newTarget
                Nothing -> False
          pure (if resolvesSame || replacement == written then [] else [(start, end, replacement)])
    dropExtension path = take (length path - length (takeExtension path)) path

wikiResolve :: FilePath -> [(FilePath, Maybe Text)] -> Text -> Maybe (FilePath, Bool, Bool)
wikiResolve source sheets written
  | T.any (== '/') written || hasKnownExtension text =
      let withExt = if hasKnownExtension text then text else text <> ".md"
          relative = wikiPath (takeDirectory source </> withExt)
          rooted = wikiPath withExt
          present path = lookup (nfc (T.pack path)) [(nfc (T.pack candidate), candidate) | (candidate, _) <- sheets]
       in case relative of
            Just path | Just actual <- present path -> Just (actual, True, True)
            _ -> case rooted of
              Just path | Just actual <- present path -> Just (actual, True, False)
              _ -> Nothing
  | otherwise =
      let byName = [path | (path, _) <- sheets, nfc (T.pack (takeBaseName path)) == nfc written]
          byTitle = [path | (path, Just title) <- sheets, nfc title == nfc written]
          candidates = if null byName then byTitle else byName
          ranked = sortOn (\path -> (if null byName then 0 :: Int else kindRank path, wikiDistance source path)) candidates
       in case ranked of
            [] -> Nothing
            [best] -> Just (best, False, False)
            best : second : _
              | (if null byName then 0 else kindRank best, wikiDistance source best)
                  == (if null byName then 0 else kindRank second, wikiDistance source second) -> Nothing
              | otherwise -> Just (best, False, False)
  where
    text = T.unpack written
    nfc = normalize NFC
    hasKnownExtension path = takeExtension path `elem` [".md", ".gm", ".emet", ".txt", ".toml", ".csv", ".tsv", ".svg", ".mmd", ".json", ".jsonc", ".json5", ".jsonl", ".png", ".jpg", ".jpeg", ".gif", ".webp"]
    kindRank path | takeExtension path == ".md" = 0
    kindRank path | takeExtension path == ".gm" = 1
    kindRank _ = 2

wikiDistance :: FilePath -> FilePath -> Int
wikiDistance source target =
  let a = splitDirectories (takeDirectory source)
      b = splitDirectories (takeDirectory target)
      shared = length (takeWhile id (zipWith (==) a b))
   in length a + length b - 2 * shared

wikiRelative :: FilePath -> FilePath -> FilePath
wikiRelative base target =
  let a = if base == "." then [] else splitDirectories base
      b = splitDirectories target
      shared = length (takeWhile id (zipWith (==) a b))
   in joinPath (replicate (length a - shared) ".." <> drop shared b)

wikiPath :: FilePath -> Maybe FilePath
wikiPath path = joinPath . reverse <$> foldl step (Just []) (splitDirectories path)
  where
    step Nothing _ = Nothing
    step acc "." = acc
    step acc "" = acc
    step (Just (_ : rest)) ".." = Just rest
    step (Just []) ".." = Nothing
    step (Just parts) part = Just (part : parts)

-- | Byte ranges of link targets, excluding headings and labels. Fenced and
-- inline code, escaped opens, and malformed links are not references.
wikiLinks :: Text -> [(Int, Int, Text)]
wikiLinks source = reverse (third (foldl line (False, 0, []) (T.splitOn "\n" source)))
  where
    third (_, _, found) = found
    line (fenced, base, found) content
      | let stripped = T.stripStart content,
        "```" `T.isPrefixOf` stripped || "~~~" `T.isPrefixOf` stripped = (not fenced, next, found)
      | fenced = (fenced, next, found)
      | otherwise = (False, next, reverse (scan base content 0) <> found)
      where
        next = base + BS.length (TE.encodeUtf8 content) + 1
    scan base content index
      | index >= T.length content = []
      | T.index content index == '\\' = scan base content (index + 2)
      | T.index content index == '`' =
          let ticks = T.takeWhile (== '`') (T.drop index content)
              rest = T.drop (index + T.length ticks) content
              (before, after) = T.breakOn ticks rest
           in scan base content (if T.null after then index + T.length ticks else index + 2 * T.length ticks + T.length before)
      | "[[" `T.isPrefixOf` T.drop index content =
          let innerStart = index + 2
              (inner, close) = T.breakOn "]]" (T.drop innerStart content)
              beforeLabel = fst (T.breakOn "|" inner)
              beforeHeading = fst (T.breakOn "#" beforeLabel)
              target = T.strip beforeHeading
              lead = T.length beforeHeading - T.length (T.stripStart beforeHeading)
              start = innerStart + lead
              byteAt offset = base + BS.length (TE.encodeUtf8 (T.take offset content))
              next = innerStart + T.length inner + 2
           in if T.null close || T.any (`elem` ("[]" :: String)) inner
                then scan base content (index + 2)
                else (if T.null target then [] else [(byteAt start, byteAt (start + T.length target), target)]) <> scan base content next
      | otherwise = scan base content (index + 1)
