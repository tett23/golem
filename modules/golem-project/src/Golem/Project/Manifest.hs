-- | manifest.toml (golem-project ADR 0001, specifications.md).
module Golem.Project.Manifest
  ( Manifest (..),
    Metadata (..),
    Creator (..),
    ChapterEntry (..),
    SourceEdit (..),
    Targets (..),
    TextVariant (..),
    PluginDecl (..),
    FilterDecl (..),
    parseManifest,
    chapterFiles,
    applyEdits,
    tomlDiagnostics,
    decodeStrict,
    decodeStrictBy,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Golem.Parser.SourceSettings
import Golem.Syntax
import Toml qualified
import Toml.Schema
import Toml.Schema.FromValue (typeError)
import Toml.Syntax (Position (..))

data Manifest = Manifest
  { manifestMetadata :: !Metadata,
    manifestChapters :: ![ChapterEntry],
    manifestTargets :: !Targets,
    manifestPlugins :: !(Map Text PluginDecl),
    manifestFilters :: ![FilterDecl],
    manifestBibliography :: ![FilePath],
    -- | the [source] table (docs/adr ADR 0013)
    manifestSource :: !SourceSettings
  }
  deriving stock (Eq, Show)

data Metadata = Metadata
  { mdId :: !Text,
    mdTitle :: !Text,
    mdTitleReading :: !(Maybe Text),
    mdLanguage :: !Text,
    mdDate :: !Day,
    mdEdition :: !(Maybe Text),
    mdPublisher :: !(Maybe Text),
    mdCreators :: ![Creator]
  }
  deriving stock (Eq, Show)

data Creator = Creator
  { crName :: !Text,
    crReading :: !(Maybe Text),
    crRole :: !Text
  }
  deriving stock (Eq, Show)

-- | path, master page, and the [source] keys of the entry in order
data ChapterEntry
  = ChapterFile !FilePath !(Maybe Text) ![SourceEdit]
  | ChapterGroup ![ChapterEntry]
  deriving stock (Eq, Show)

{- | A [source] key written in a chapter entry (docs/adr ADR 0013): the
key and the value as written, and how it changes the settings.
-}
data SourceEdit = SourceEdit
  { seKey :: !Text,
    seValue :: !Text,
    seApply :: SourceSettings -> SourceSettings
  }

instance Eq SourceEdit where
  a == b = (seKey a, seValue a) == (seKey b, seValue b)

instance Show SourceEdit where
  show e = "SourceEdit " <> show (seKey e) <> " " <> show (seValue e)

data TextVariant = TextVertical | TextHorizontal
  deriving stock (Eq, Ord, Show)

data Targets = Targets
  { tgPdf :: !(Maybe (Maybe Text)), -- enabled, ISBN
    tgEpub :: !(Maybe (Maybe Text)),
    tgHtml :: !Bool,
    tgText :: ![TextVariant]
  }
  deriving stock (Eq, Show)

data PluginDecl = PluginDecl
  { pdUrl :: !Text,
    pdOverrides :: ![Text]
  }
  deriving stock (Eq, Show)

data FilterDecl = FilterDecl
  { fdPlugin :: !Text,
    fdFilter :: !Text,
    fdFiles :: ![FilePath]
  }
  deriving stock (Eq, Show)

{- | Chapter files in manifest order, flattened, with their master pages
and the [source] keys of their entries.
-}
chapterFiles :: [ChapterEntry] -> [(FilePath, Maybe Text, [SourceEdit])]
chapterFiles = concatMap go
  where
    go (ChapterFile p m es) = [(p, m, es)]
    go (ChapterGroup es) = concatMap go es

instance FromValue Manifest where
  fromValue = parseTableFromValue $ do
    md <- reqKey "metadata"
    chs <- reqKey "chapters"
    tg <- optKey "targets"
    pl <- optKey "plugins"
    fl <- optKey "filters"
    bib <- optKey "bibliography"
    src <- optKey "source"
    pure
      Manifest
        { manifestMetadata = md,
          manifestChapters = chs,
          manifestTargets = fromMaybe defaultTargets tg,
          manifestPlugins = fromMaybe Map.empty pl,
          manifestFilters = fromMaybe [] fl,
          manifestBibliography = maybe [] (map T.unpack) bib,
          manifestSource = applyEdits (maybe [] sourceTableEdits src) defaultSourceSettings
        }

defaultTargets :: Targets
defaultTargets = Targets Nothing Nothing True []

instance FromValue Metadata where
  fromValue = parseTableFromValue $ do
    i <- reqKey "id"
    t <- reqKey "title"
    tr <- optKey "title-reading"
    l <- reqKey "language"
    d <- reqKey "date"
    e <- optKey "edition"
    p <- optKey "publisher"
    cs <- optKey "creators"
    pure (Metadata i t tr l d e p (fromMaybe [] cs))

instance FromValue Creator where
  fromValue = parseTableFromValue (Creator <$> reqKey "name" <*> optKey "reading" <*> reqKey "role")

instance FromValue ChapterEntry where
  fromValue = \case
    Text' _ t -> pure (ChapterFile (T.unpack t) Nothing [])
    List' _ xs -> ChapterGroup <$> traverse fromValue xs
    v@Table' {} -> parseTableFromValue (ChapterFile . T.unpack <$> reqKey "file" <*> optKey "master" <*> sourceEdits) v
    v -> typeError "file path, table or array" v

-- | The [source] table: its keys as edits of the settings (docs/adr ADR 0013).
newtype SourceTable = SourceTable {sourceTableEdits :: [SourceEdit]}

instance FromValue SourceTable where
  fromValue = parseTableFromValue (SourceTable <$> sourceEdits)

{- | The keys of 'sourceKeys' in a table. An invalid value fails; keys left
over are unknown keys and are reported as such.
-}
sourceEdits :: ParseTable l [SourceEdit]
sourceEdits = catMaybes <$> traverse one sourceKeys
  where
    one (k, f) =
      optKey k >>= \case
        Nothing -> pure Nothing
        Just v -> either (fail . T.unpack) (pure . Just . SourceEdit k v) (f v)

-- | The edits applied in order.
applyEdits :: [SourceEdit] -> SourceSettings -> SourceSettings
applyEdits es s = foldl (flip seApply) s es

instance FromValue Targets where
  fromValue = parseTableFromValue $ do
    pdf <- optKey "pdf"
    epub <- optKey "epub"
    html <- optKey "html"
    txt <- optKey "text"
    pure
      Targets
        { tgPdf = fmap isbnOf pdf,
          tgEpub = fmap isbnOf epub,
          tgHtml = isJust (html :: Maybe EmptyTable),
          tgText = maybe [] textVariants txt
        }

newtype IsbnTable = IsbnTable (Maybe Text)

isbnOf :: IsbnTable -> Maybe Text
isbnOf (IsbnTable i) = i

instance FromValue IsbnTable where
  fromValue = parseTableFromValue (IsbnTable <$> optKey "isbn")

data EmptyTable = EmptyTable

instance FromValue EmptyTable where
  fromValue = parseTableFromValue (pure EmptyTable)

newtype TextTable = TextTable [Text]

textVariants :: TextTable -> [TextVariant]
textVariants (TextTable vs) =
  [v | (k, v) <- [("vertical", TextVertical), ("horizontal", TextHorizontal)], k `elem` vs]

instance FromValue TextTable where
  fromValue = parseTableFromValue $ do
    vs <- optKey "variants"
    pure (TextTable (fromMaybe ["vertical", "horizontal"] vs))

instance FromValue PluginDecl where
  fromValue = parseTableFromValue $ do
    u <- reqKey "url"
    o <- optKey "overrides"
    pure (PluginDecl u (fromMaybe [] o))

instance FromValue FilterDecl where
  fromValue = parseTableFromValue $ do
    p <- reqKey "plugin"
    f <- reqKey "filter"
    fs <- reqKey "files"
    pure (FilterDecl p f (map T.unpack fs))

{- | Parses TOML and matches it against a schema. Unknown keys (warnings
in toml-parser) are errors: a misspelt key must not be silently ignored.
-}
decodeStrict :: (FromValue a) => Text -> FileId -> Text -> Either [Diagnostic] a
decodeStrict code = decodeStrictBy code (const code)

{- | 'decodeStrict' whose schema messages take their code from the path of
the value; TOML syntax errors take the first code.
-}
decodeStrictBy :: (FromValue a) => Text -> ([Scope] -> Text) -> FileId -> Text -> Either [Diagnostic] a
decodeStrictBy code codeAt fid src = case Toml.parse src of
  Left msg -> Left [diagnostic code Error (mkSpan fid 0 0) ("TOML の誤りです: " <> T.pack msg)]
  Right tab -> case runMatcher (fromValue (Table' (Position 0 1 1) tab)) of
    Failure es -> Left (tomlDiagnosticsBy codeAt fid src es)
    Success [] a -> Right a
    Success ws _ -> Left (tomlDiagnosticsBy codeAt fid src ws)

parseManifest :: FileId -> Text -> Either [Diagnostic] Manifest
parseManifest fid src = do
  m <- decodeStrict "G0301" fid src
  let t = manifestTargets m
  if tgHtml t || not (null (tgText t)) || isJust (tgPdf t) || isJust (tgEpub t)
    then Right m
    else Left [diagnostic "G0301" Error (mkSpan fid 0 0) "出力ターゲットが一つもありません"]

-- | Converts toml-parser messages to diagnostics at their line.
tomlDiagnostics :: Text -> FileId -> Text -> [MatchMessage Position] -> [Diagnostic]
tomlDiagnostics code = tomlDiagnosticsBy (const code)

-- | 'tomlDiagnostics' with the code taken from the path of each message.
tomlDiagnosticsBy :: ([Scope] -> Text) -> FileId -> Text -> [MatchMessage Position] -> [Diagnostic]
tomlDiagnosticsBy codeAt fid src = map one
  where
    li = mkLineIndex src
    at mpos = case mpos of
      Just (Position _ l c) -> case lineColToOffset li (LineCol (l - 1) (c - 1)) of
        Just off -> mkSpan fid off off
        Nothing -> mkSpan fid 0 0
      Nothing -> mkSpan fid 0 0
    one (MatchMessage loc path msg) =
      diagnostic (codeAt path) Error (at loc) (T.pack (msg <> " (" <> showPath path <> ")"))
    showPath = concatMap $ \case
      ScopeKey k -> "." <> T.unpack k
      ScopeIndex i -> "[" <> show i <> "]"
