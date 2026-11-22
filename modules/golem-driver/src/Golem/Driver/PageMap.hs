-- | Fixed-page positions resolved against the current manuscript (root ADR 0386).
module Golem.Driver.PageMap
  ( PageMap (..),
    FixedPage (..),
    PageMapError (..),
    decodePageMap,
    resolvePageMap,
    resolvePageMapWithAst,
  )
where

import Control.Monad (unless)
import Data.Aeson qualified as J
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Assemble (Book (..))
import Golem.Doc.IR
import Golem.Driver.PageMap.Alignment (sourceOffset)
import Golem.Html (pagePath)
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Numeric (showHex)

data PageMap = PageMap
  { pmSources :: !(Map FilePath Text),
    pmPages :: ![FixedPage]
  }
  deriving stock (Eq, Show)

data FixedPage = FixedPage
  { fpPage :: !Int,
    fpLabel :: !Text,
    fpPosition :: !(Maybe (FilePath, Int, Int))
  }
  deriving stock (Eq, Show)

data PageMapError
  = PageMapJson !Text
  | PageMapSchema !Text
  | PageMapStale !Text
  | PageMapPosition !Text
  deriving stock (Eq, Show)

instance J.FromJSON PageMap where
  parseJSON = J.withObject "page map" $ \o -> do
    unless (all ((`elem` ["sources", "pages"]) . Key.toText) (KeyMap.keys o)) (fail "unknown page-map field")
    sources <- o J..: "sources"
    unless (all validHash (Map.elems sources)) (fail "source hashes must have 64 lowercase hexadecimal digits")
    PageMap sources <$> o J..: "pages"
    where
      validHash hash = T.length hash == 64 && T.all (\c -> ('0' <= c && c <= '9') || c `elem` ("abcdef" :: String)) hash

instance J.FromJSON FixedPage where
  parseJSON = J.withObject "fixed page" $ \o -> do
    unless (all ((`elem` ["page", "label", "file", "line", "character"]) . Key.toText) (KeyMap.keys o)) (fail "unknown fixed-page field")
    number <- o J..: "page"
    label <- o J..: "label"
    file <- o J..:? "file"
    line <- o J..:? "line"
    character <- o J..:? "character"
    unless (number > 0 && not (T.null (T.strip label)) && firstUnwritable label == Nothing) (fail "page must be positive and label must be nonempty")
    position <- case (file, line, character) of
      (Nothing, Nothing, Nothing) -> pure Nothing
      (Just f, Just l, Just c) | l >= 0 && c >= 0 -> pure (Just (f, l, c))
      _ -> fail "file, line and character must be supplied together"
    pure (FixedPage number label position)

decodePageMap :: BL.ByteString -> Either PageMapError PageMap
decodePageMap bytes = do
  value <- either (Left . PageMapJson . T.pack) Right (J.eitherDecode bytes)
  either (Left . PageMapSchema . T.pack) Right (parseEither J.parseJSON value)

-- | Each returned link has an anchor in body text; unmapped pages are omitted.
resolvePageMap :: Map FileId (FilePath, Text) -> FileTable -> Book -> PageMap -> Either PageMapError (Map SrcSpan [(Int, Text, Text)], [(Text, FilePath, Text)])
resolvePageMap sources = resolvePageMapWithAst (Map.mapWithKey (\fid (_, source) -> let (ast, _, _) = parseAst fid source in ast) sources) sources

-- | Reuse the project's original AST so that merged text keeps source positions.
resolvePageMapWithAst :: Map FileId A.File -> Map FileId (FilePath, Text) -> FileTable -> Book -> PageMap -> Either PageMapError (Map SrcSpan [(Int, Text, Text)], [(Text, FilePath, Text)])
resolvePageMapWithAst asts sources files book mapping = do
  let required = [path | (path, _) <- Map.elems sources]
  unless (all (`Map.member` pmSources mapping) required) (Left (PageMapSchema "source hashes must cover every manuscript document"))
  mapM_ verifySource (Map.toList (pmSources mapping))
  unless (strictlyIncreasing (map fpPage (pmPages mapping))) (Left (PageMapSchema "page numbers must be strictly increasing"))
  resolved <- catMaybes <$> traverse resolve (pmPages mapping)
  let order = [(bodyOrder, offset) | (_, _, _, offset, _, bodyOrder) <- resolved]
  unless (and (zipWith (<=) order (drop 1 order))) (Left (PageMapPosition "page positions must follow manuscript order"))
  pure
    ( Map.fromListWith (flip (<>)) [(sp, [(offset, ident, label)]) | (label, _, sp, offset, ident, _) <- resolved],
      [(label, pagePath files fid, ident) | (label, fid, _, _, ident, _) <- resolved]
    )
  where
    byPath = Map.fromList [(path, (fid, source)) | (fid, (path, source)) <- Map.toList sources]
    verifySource (path, expected) = case Map.lookup path byPath of
      Nothing -> Left (PageMapStale ("source is not part of the manuscript: " <> T.pack path))
      Just (_, source) ->
        unless (hex (sha256 (TE.encodeUtf8 (source))) == expected) (Left (PageMapStale ("source has changed: " <> T.pack path)))
    resolve page = case fpPosition page of
      Nothing -> pure Nothing
      Just (path, line, character) -> do
        unless (Map.member path (pmSources mapping)) (Left (PageMapSchema ("source hash is missing: " <> T.pack path)))
        (fid, source) <- maybe (Left (PageMapPosition ("unknown source: " <> T.pack path))) Right (Map.lookup path byPath)
        off <- maybe (Left (PageMapPosition ("invalid source position: " <> T.pack path))) Right (utf16LineColToOffset (mkLineIndex (source)) (LineCol line character))
        let candidates = [(order, destination, sp, text) | (order, (destination, sp, text)) <- zip [0 :: Int ..] (bodyTexts book), spanFile sp == fid, spanStart sp <= off, off < spanEnd sp]
        case candidates of
          [(bodyOrder, destination, sp, text)] -> case Map.lookup fid asts >>= \ast -> sourceOffset ast source sp text off of
            Nothing -> pure Nothing
            Just offset ->
              let ident = "GolemFixedPage-" <> T.pack (show (fpPage page))
               in pure (Just (fpLabel page, destination, sp, offset, ident, bodyOrder))
          _ -> pure Nothing
    strictlyIncreasing xs = and (zipWith (<) xs (drop 1 xs))

hex :: BS.ByteString -> Text
hex = T.pack . concatMap (\byte -> let encoded = showHex byte "" in replicate (2 - length encoded) '0' <> encoded) . BS.unpack

bodyTexts :: Book -> [(FileId, SrcSpan, Text)]
bodyTexts book = [(destination, sp, text) | Document destination blocks <- bookDocs book, (sp, text) <- concatMap blockTexts blocks]
  where
    blockTexts (Block _ _ _ body) = case body of
      Paragraph _ xs -> concatMap inlineTexts xs
      Heading _ _ xs -> concatMap inlineTexts xs
      BulletList items -> concatMap (concatMap blockTexts . itemBlocks) items
      OrderedList items -> concatMap (concatMap blockTexts . itemBlocks) items
      DefList groups -> concat [concatMap (concatMap inlineTexts) terms <> concatMap (concatMap blockTexts) defs | DefGroup terms defs <- groups]
      TableBlock table -> concatMap (concatMap inlineTexts) (tableHeader table <> concat (tableRows table))
      FigureBlock figure -> concatMap blockTexts (figCaption figure)
      _ -> []
    inlineTexts :: InlineF r -> [(SrcSpan, Text)]
    inlineTexts = \case
      Text sp text -> [(sp, text)]
      Tcy sp _ -> [(sp, "")]
      Number sp _ _ -> [(sp, "")]
      Ref sp _ _ -> [(sp, "")]
      Cite sp _ -> [(sp, "")]
      ChannelItem sp _ -> [(sp, "")]
      Ruby _ _ segments -> concatMap (concatMap inlineTexts . rsBase) segments
      Kenten _ _ xs -> concatMap inlineTexts xs
      Color _ _ xs -> concatMap inlineTexts xs
      CharStyle _ _ xs -> concatMap inlineTexts xs
      Lang _ _ xs -> concatMap inlineTexts xs
      Link _ _ xs -> concatMap inlineTexts xs
      Resolved _ _ _ xs -> concatMap inlineTexts xs
      _ -> []
