-- | manifest.toml (golem-project ADR 0001, specifications.md).
module Golem.Project.Manifest
  ( Manifest (..),
    Metadata (..),
    Creator (..),
    Role (..),
    roleWord,
    marcRelator,
    inMetadata,
    Printing (..),
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

import Control.Monad (zipWithM_)
import Data.Char (isDigit)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Golem.Parser.SourceSettings
import Golem.Project.TomlMessage (pathText, schemaMessage, semanticMessage, syntaxMessage)
import Golem.Syntax
import Toml qualified
import Toml.Schema
import Toml.Schema.FromValue (typeError)
import Toml.Schema.Matcher (inIndex)
import Toml.Semantics
  ( SemanticError (..),
    semantics,
    valueAnn,
  )
import Toml.Syntax (Located (..), Position (..), parseRawToml)
import Prelude hiding (fail)

data Manifest = Manifest
  { manifestMetadata :: !Metadata,
    manifestChapters :: ![ChapterEntry],
    manifestTargets :: !Targets,
    manifestPlugins :: !(Map Text PluginDecl),
    manifestFilters :: ![FilterDecl],
    manifestBibliography :: ![FilePath],
    -- | the [source] table (docs/adr ADR 0013)
    manifestSource :: !SourceSettings,
    -- | [diagnostics] silence-notices: codes of notices not shown (golem-syntax ADR 0002)
    manifestSilencedNotices :: !(Set DiagnosticCode)
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
    mdCreators :: ![Creator],
    -- | the publisher person of the colophon, not in the metadata of the outputs (docs/adr ADR 0033)
    mdPublisherPerson :: !(Maybe Text),
    -- | the secondary contributors (docs/adr ADR 0033)
    mdContributors :: ![Creator],
    -- | the history of editions and printings, the last the current one (docs/adr ADR 0033)
    mdPrintings :: ![Printing]
  }
  deriving stock (Eq, Show)

-- | A creator or a contributor (docs/adr ADR 0033).
data Creator = Creator
  { crName :: !Text,
    crReading :: !(Maybe Text),
    crRole :: !Role
  }
  deriving stock (Eq, Show)

-- | The roles of creators and contributors, a closed vocabulary (docs/adr ADR 0033).
data Role
  = Author
  | Translator
  | Editor
  | Illustrator
  | BookDesigner
  | CoverDesigner
  | Typesetter
  | Printer
  | Binder
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The word of a role that manifest.toml takes.
roleWord :: Role -> Text
roleWord = \case
  Author -> "author"
  Translator -> "translator"
  Editor -> "editor"
  Illustrator -> "illustrator"
  BookDesigner -> "book-designer"
  CoverDesigner -> "cover-designer"
  Typesetter -> "typesetter"
  Printer -> "printer"
  Binder -> "binder"

-- | The MARC relator code of a role, for the outputs that need it.
marcRelator :: Role -> Text
marcRelator = \case
  Author -> "aut"
  Translator -> "trl"
  Editor -> "edt"
  Illustrator -> "ill"
  BookDesigner -> "bkd"
  CoverDesigner -> "cov"
  Typesetter -> "cmt"
  Printer -> "prt"
  Binder -> "bnd"

-- | Whether a role is written in the metadata of EPUB and XMP: not the printer and the binder.
inMetadata :: Role -> Bool
inMetadata = \case
  Printer -> False
  Binder -> False
  _ -> True

-- | One edition and printing and its date (docs/adr ADR 0033).
data Printing = Printing
  { prEdition :: !Int,
    prNumber :: !Int,
    prDate :: !Day
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
    dg <- optKey "diagnostics"
    pure
      Manifest
        { manifestMetadata = md,
          manifestChapters = chs,
          manifestTargets = fromMaybe defaultTargets tg,
          manifestPlugins = fromMaybe Map.empty pl,
          manifestFilters = fromMaybe [] fl,
          manifestBibliography = maybe [] (map T.unpack) bib,
          manifestSource = applyEdits (maybe [] sourceTableEdits src) defaultSourceSettings,
          manifestSilencedNotices = maybe Set.empty silenced dg
        }

-- | The [diagnostics] table (golem-syntax ADR 0002).
newtype DiagnosticsTable = DiagnosticsTable {silenced :: Set DiagnosticCode}

instance FromValue DiagnosticsTable where
  fromValue = parseTableFromValue (DiagnosticsTable . fromMaybe Set.empty <$> optKeyOf "silence-notices" silenceList)

{- | The codes of silence-notices. An element that is not the code of a
notice is reported at the element; the scope of the element makes it G0324
('manifestCode'). Every such element is reported, not only the first.
-}
silenceList :: Value' l -> Matcher l (Set DiagnosticCode)
silenceList = \case
  List' _ xs -> Set.fromList . catMaybes <$> traverse (\(i, x) -> inIndex i (element x)) (zip [0 ..] xs)
  v -> typeError "array" v
  where
    element = \case
      Text' l t
        | not (isCodeShape t) -> warnAt l ("診断のコードは G と 4 桁の数字で書きます: " <> T.unpack t) >> pure Nothing
        | DiagnosticCode t `notElem` noticeCodes -> warnAt l ("抑制できるのはお知らせのコードだけです: " <> T.unpack t) >> pure Nothing
        | otherwise -> pure (Just (DiagnosticCode t))
      v -> warnAt (Toml.valueAnn v) "診断のコードは文字列で書きます" >> pure Nothing
    isCodeShape t = T.length t == 5 && T.take 1 t == "G" && T.all isDigit (T.drop 1 t)

{- | The code of a schema message of the manifest: G0324 for an element of
silence-notices, G0301 otherwise.
-}
manifestCode :: [Scope] -> Text
manifestCode = \case
  [ScopeKey "diagnostics", ScopeKey "silence-notices", ScopeIndex _] -> "G0324"
  _ -> "G0301"

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
    pp <- optKeyOf "publisher-person" publisherPerson
    co <- optKey "contributors"
    ps <- optKeyOf "printings" printings
    pure (Metadata i t tr l d e p (fromMaybe [] cs) pp (fromMaybe [] co) (fromMaybe [] ps))
    where
      publisherPerson = \case
        Text' l v
          | T.null v -> failAt l "publisher-person に空の文字列は書けません"
          | T.any (`elem` ("\n\r" :: String)) v -> failAt l "publisher-person に改行は書けません"
          | otherwise -> pure v
        v -> typeError "string" v

instance FromValue Creator where
  fromValue = parseTableFromValue (Creator <$> reqKeyOf "name" name <*> optKey "reading" <*> reqKeyOf "role" role)
    where
      name = \case
        Text' l v | T.null v -> failAt l "name に空の文字列は書けません"
        v -> fromValue v
      role = \case
        Text' l v
          | Just r <- lookup v [(roleWord r, r) | r <- [minBound .. maxBound]] -> pure r
          | Just r <- lookup v [(marcRelator r, r) | r <- [minBound .. maxBound]] ->
              failAt l (T.unpack ("役割は語で書きます。\"" <> v <> "\" は \"" <> roleWord r <> "\" です"))
          | v == "publisher" -> failAt l "発行所は [metadata] の publisher に、発行人は publisher-person に書きます"
          | otherwise -> failAt l (T.unpack ("役割は " <> T.intercalate "、" (map roleWord [minBound .. maxBound]) <> " のどれかです: " <> v))
        v -> typeError "string" v

{- | The printings: editions and printings from 1, increasing strictly in
(edition, printing), dates not going back (docs/adr ADR 0033).
-}
printings :: Value' l -> Matcher l [Printing]
printings = \case
  List' _ xs -> do
    ps <- traverse (\(i, x) -> inIndex i ((valueAnn x,) <$> fromValue x)) (zip [0 ..] xs)
    zipWithM_ ordered ps (drop 1 ps)
    pure (map snd ps)
  v -> typeError "array" v
  where
    ordered (_, a) (l, b)
      | (prEdition b, prNumber b) <= (prEdition a, prNumber a) = failAt l "printings は版と刷の順に、同じ版と刷を二度書かずに並べます"
      | prDate b < prDate a = failAt l "printings の date が前の項目の date より前です"
      | otherwise = pure ()

instance FromValue Printing where
  fromValue = parseTableFromValue (Printing <$> reqKeyOf "edition" atLeastOne <*> reqKeyOf "printing" atLeastOne <*> reqKey "date")
    where
      atLeastOne = \case
        Integer' l n | n < 1 -> failAt l "版と刷の番号は 1 以上の整数です"
        v -> fromValue v

instance FromValue ChapterEntry where
  fromValue = \case
    Text' _ t -> pure (ChapterFile (T.unpack t) Nothing [])
    List' _ xs -> ChapterGroup <$> traverse fromValue xs
    v@Table' {} -> parseTableFromValue (ChapterFile . T.unpack <$> reqKey "file" <*> optKey "master" <*> sourceEdits) v
    v -> failAt (valueAnn v) "章は、ファイルのパス、表、配列のどれかで書きます"

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
    -- an invalid value is at the value (golem-project ADR 0008)
    one (k, f) =
      optKeyOf k $ \val ->
        fromValue val >>= \v -> either (failAt (valueAnn val) . T.unpack) (pure . SourceEdit k v) (f v)

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
decodeStrictBy code codeAt fid src = case parseToml src of
  Left (ErrSyntax (Located pos msg)) -> Left [diagnostic code Error (positionSpan fid src (Just pos)) ("TOML の誤りです: " <> syntaxMessage msg)]
  Left (ErrSemantics (SemanticError pos key kind)) -> Left [diagnostic code Error (positionSpan fid src (Just pos)) ("TOML の誤りです: " <> semanticMessage kind key)]
  Right tab -> case runMatcher (fromValue (Table' (Position 0 1 1) tab)) of
    Failure es -> Left (tomlDiagnosticsBy codeAt fid src es)
    Success [] a -> Right a
    Success ws _ -> Left (tomlDiagnosticsBy codeAt fid src ws)

-- | The errors of reading TOML before the schema (Toml.parse' of toml-parser, which the package does not export).
data TomlError
  = ErrSyntax (Located String)
  | ErrSemantics (SemanticError Position)

{- | 'Toml.parse' without folding the error into a string: the syntax
errors keep their position (golem-project ADR 0007).
-}
parseToml :: Text -> Either TomlError (Table' Position)
parseToml src = do
  exprs <- either (Left . ErrSyntax) Right (parseRawToml src)
  either (Left . ErrSemantics) Right (semantics exprs)

-- | The span of a position of toml-parser; the start of the file without one.
positionSpan :: FileId -> Text -> Maybe Position -> SrcSpan
positionSpan fid src = \case
  Just (Position _ l c)
    | Just off <- lineColToOffset (mkLineIndex src) (LineCol (l - 1) (c - 1)) -> mkSpan fid off off
  _ -> mkSpan fid 0 0

{- | Reads manifest.toml. A string with a character that cannot be written
to the output is G0328 before the schema (docs/adr ADR 0042).
-}
parseManifest :: FileId -> Text -> Either [Diagnostic] Manifest
parseManifest fid src = do
  case either (const []) (unwritableStrings fid src) (parseToml src) of
    [] -> Right ()
    ds -> Left ds
  m <- decodeStrictBy "G0301" manifestCode fid src
  let t = manifestTargets m
  if tgHtml t || not (null (tgText t)) || isJust (tgPdf t) || isJust (tgEpub t)
    then Right m
    else Left [diagnostic "G0301" Error (mkSpan fid 0 0) "出力ターゲットが一つもありません"]

{- | G0328 at each string of a TOML table with a character that cannot be
written to the output (docs/adr ADR 0042), in the order of the file: one
for each string, naming its first such character.
-}
unwritableStrings :: FileId -> Text -> Table' Position -> [Diagnostic]
unwritableStrings fid src = map snd . Map.toAscList . Map.fromList . inTable []
  where
    inTable path (MkTable kvs) = concat [value (path <> [ScopeKey k]) v | (k, (_, v)) <- Map.toList kvs]
    value path = \case
      Text' pos t
        | Just c <- firstUnwritable t ->
            let sp = positionSpan fid src (Just pos)
             in [(spanStart sp, diagnostic "G0328" Error sp (pathText path <> " に出力に書けない文字（" <> codePointText c <> "）があります"))]
      List' _ vs -> concat (zipWith (\i v -> value (path <> [ScopeIndex i]) v) [0 ..] vs)
      Table' _ t -> inTable path t
      _ -> []

-- | Converts toml-parser messages to diagnostics at their line.
tomlDiagnostics :: Text -> FileId -> Text -> [MatchMessage Position] -> [Diagnostic]
tomlDiagnostics code = tomlDiagnosticsBy (const code)

-- | 'tomlDiagnostics' with the code taken from the path of each message.
tomlDiagnosticsBy :: ([Scope] -> Text) -> FileId -> Text -> [MatchMessage Position] -> [Diagnostic]
tomlDiagnosticsBy codeAt fid src = map one
  where
    one (MatchMessage loc path msg) =
      diagnostic (codeAt path) Error (positionSpan fid src loc) (schemaMessage path msg)
