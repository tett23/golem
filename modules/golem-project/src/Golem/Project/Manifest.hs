-- | manifest.toml (golem-project ADR 0001, specifications.md).
module Golem.Project.Manifest
  ( Manifest (..),
    Metadata (..),
    Creator (..),
    Role (..),
    roleWord,
    marcRelator,
    inMetadata,
    runningMetadata,
    Printing (..),
    ChapterEntry (..),
    PageNumbering (..),
    sameNumbering,
    chapterNumberings,
    SourceEdit (..),
    Targets (..),
    PdfAPart (..),
    PdfUaPart (..),
    TextVariant (..),
    PluginDecl (..),
    PluginSource (..),
    FilterDecl (..),
    FilterSource (..),
    ProjectVar (..),
    parseManifest,
    manifestValueSpan,
    chapterFiles,
    applyEdits,
    decodeStrict,
    decodeStrictBy,
    decodeStrictWith,
    decodeStrictTableWith,
    naturalOf,
    naturalIntOf,
    maxNaturalInt,
    readTomlTable,
    positionSpan,
  )
where

import Control.Monad (zipWithM_)
import Data.Char (isAsciiLower, isAsciiUpper, isDigit)
import Data.Int (Int32)
import Data.List (isPrefixOf, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time.Calendar (Day)
import Golem.Assemble.Formats (Notation, notationName, notationNamed, notations)
import Golem.Parser.SourceSettings
import Golem.Project.TomlMessage (pathText, schemaMessage, semanticMessage, syntaxMessage)
import Golem.Project.TomlSchema (Node, unknownKeys)
import Golem.Syntax
import Numeric.Natural (Natural)
import Toml qualified
import Toml.Schema
import Toml.Schema.FromValue (typeError)
import Toml.Schema.Matcher (inIndex, inKey)
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
    -- | whether [source] writes paragraph-separator; without it G03120 (docs/adr/0193)
    manifestParagraphSeparatorWritten :: !Bool,
    -- | [diagnostics] silence-notices: codes of notices not shown (golem-syntax ADR 0002)
    manifestSilencedNotices :: !(Set DiagnosticCode),
    -- | [diagnostics] silence-info: codes of infos not shown, even with --verbose (docs/adr 0104)
    manifestSilencedInfo :: !(Set DiagnosticCode),
    {- | [functions.requires] file: the files the functions may read, as
    written, relative to the root; Nothing without the key (docs/adr/0161)
    -} manifestRequiredFiles :: !(Maybe [FilePath]),
    -- | [vars]: the variables of the whole project, read through the namespace vars (docs/adr/0185)
    manifestVars :: !(Map Text ProjectVar)
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

{- | The text of the keys of [metadata] a running head can show
(golem-driver ADR 0022): the keys of @meta@ but creators, an array.
-}
runningMetadata :: Metadata -> Map Text Text
runningMetadata md =
  Map.fromList $
    [ ("id", mdId md),
      ("title", mdTitle md),
      ("language", mdLanguage md),
      ("date", T.pack (show (mdDate md)))
    ]
      <> [("title_reading", r) | Just r <- [mdTitleReading md]]
      <> [("edition", e) | Just e <- [mdEdition md]]
      <> [("publisher", p) | Just p <- [mdPublisher md]]

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
  { prEdition :: !Natural,
    prNumber :: !Natural,
    prDate :: !Day
  }
  deriving stock (Eq, Show)

-- | path, master page, the [source] keys of the entry in order, and the section it starts (docs/adr/0260)
data ChapterEntry
  = ChapterFile !FilePath !(Maybe Text) ![SourceEdit] !(Maybe PageNumbering)
  | ChapterGroup ![ChapterEntry]
  deriving stock (Eq, Show)

{- | The page-numbering of a chapter entry (docs/adr/0260): the section
the file starts. Its notation is Nothing without a style and for arabic,
a number of no notation; its start is Nothing to count on from the page
before. The spans are of the value of page-numbering and of its style
(that of page-numbering without one), where G07109 and G07110 point.
-}
data PageNumbering = PageNumbering
  { pnNotation :: !(Maybe Notation),
    pnStart :: !(Maybe Integer),
    pnSpan :: !SrcSpan,
    pnStyleSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

-- | Whether two page-numbering are the same, wherever they are written (G03123).
sameNumbering :: Maybe PageNumbering -> Maybe PageNumbering -> Bool
sameNumbering a b = fmap key a == fmap key b
  where
    key n = (fmap notationName (pnNotation n), pnStart n)

-- | The page-numbering of the chapter files, in the order of 'chapterFiles' (docs/adr/0260).
chapterNumberings :: [ChapterEntry] -> [Maybe PageNumbering]
chapterNumberings = concatMap go
  where
    go (ChapterFile _ _ _ n) = [n]
    go (ChapterGroup es) = concatMap go es

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
    tgText :: ![TextVariant],
    -- | [targets.pdf] pdfa: the PDF/A the PDF declares (docs/adr ADR 0183)
    tgPdfA :: !(Maybe PdfAPart),
    -- | [targets.pdf] pdfua: the PDF/UA the PDF declares (docs/adr ADR 0183)
    tgPdfUa :: !(Maybe PdfUaPart)
  }
  deriving stock (Eq, Show)

-- | The parts and levels of PDF/A a book can declare: pdfa = "2a" (docs/adr ADR 0183).
data PdfAPart = PdfA2a
  deriving stock (Eq, Show)

-- | The parts of PDF/UA a book can declare: pdfua = "1" (docs/adr ADR 0183).
data PdfUaPart = PdfUa1
  deriving stock (Eq, Show)

data PluginDecl = PluginDecl
  { pdSource :: !PluginSource,
    pdOverrides :: ![Text],
    -- | the data the project passes to the plugin: names and project-relative paths (docs/adr/0105)
    pdData :: !(Map Text FilePath)
  }
  deriving stock (Eq, Show)

{- | Where a plugin comes from: an artifact fetched from its URL and fixed
in plugins.lock (golem-plugin ADR 0002), or a .wasm of the project, fixed
by the repository like the manuscripts (docs/adr/0109).
-}
data PluginSource
  = PluginUrl !Text
  | -- | relative to the root of the project
    PluginPath !FilePath
  deriving stock (Eq, Show)

{- | A filter of [[filters]]: of a plugin, or a function of a .emet
(docs/adr/0162), its name, and the files it applies to. The filters apply
in the order of the manifest, of plugins and of .emet alike.
-}
data FilterDecl = FilterDecl
  { fdSource :: !FilterSource,
    fdFilter :: !Text,
    fdFiles :: ![FilePath]
  }
  deriving stock (Eq, Show)

{- | A value of [vars] (docs/adr/0185): the TOML values a variable of the
project takes. A float, a time and a date-time are G03109; a key that is
not an identifier of expressions is G03110.
-}
data ProjectVar
  = VarString !Text
  | VarInteger !Integer
  | VarBool !Bool
  | -- | a local date, which the expressions read as a string, as meta.date
    VarDate !Day
  | VarArray ![ProjectVar]
  | VarTable !(Map Text ProjectVar)
  deriving stock (Eq, Show)

-- | Where a filter is: a plugin by its name, or a .emet by its path from the root.
data FilterSource = FilterPlugin !Text | FilterFunction !FilePath
  deriving stock (Eq, Show)

{- | Chapter files in manifest order, flattened, with their master pages
and the [source] keys of their entries.
-}
chapterFiles :: [ChapterEntry] -> [(FilePath, Maybe Text, [SourceEdit])]
chapterFiles = concatMap go
  where
    go (ChapterFile p m es _) = [(p, m, es)]
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
    fns <- optKey "functions"
    vs <- optKeyOf "vars" varsTable
    pure
      Manifest
        { manifestMetadata = md,
          manifestChapters = chs,
          manifestTargets = fromMaybe defaultTargets tg,
          manifestPlugins = fromMaybe Map.empty pl,
          manifestFilters = fromMaybe [] fl,
          manifestBibliography = maybe [] (map T.unpack) bib,
          manifestSource = applyEdits (maybe [] sourceTableEdits src) defaultSourceSettings,
          manifestParagraphSeparatorWritten = any ((== "paragraph-separator") . seKey) (maybe [] sourceTableEdits src),
          manifestSilencedNotices = maybe Set.empty silenced dg,
          manifestSilencedInfo = maybe Set.empty silencedInfo dg,
          manifestRequiredFiles = fns >>= \(FunctionsTable fs) -> fs,
          manifestVars = fromMaybe Map.empty vs
        }

{- | [vars] (docs/adr/0185): a table of the values of 'ProjectVar'. The
values and keys it does not take are reported before the schema
('varsDiagnostics'); here they are left out.
-}
varsTable :: Value' l -> Matcher l (Map Text ProjectVar)
varsTable = \case
  Table' _ t -> pure (tableVars t)
  v -> typeError "table" v
  where
    tableVars (MkTable kvs) = Map.fromList [(k, x) | (k, (_, v)) <- Map.toList kvs, Just x <- [varOf v]]
    varOf = \case
      Text' _ t -> Just (VarString t)
      Integer' _ i -> Just (VarInteger i)
      Bool' _ b -> Just (VarBool b)
      Day' _ d -> Just (VarDate d)
      List' _ xs -> VarArray <$> traverse varOf xs
      Table' _ t -> Just (VarTable (tableVars t))
      _ -> Nothing

{- | G03110 at each key of [vars] and of its tables that is not an
identifier of expressions, and G03109 at each value that is a float, a
time or a date-time, in arrays and tables too (docs/adr/0185); in the
order of the file.
-}
varsDiagnostics :: FileId -> Text -> Table' Position -> [Diagnostic]
varsDiagnostics fid src (MkTable top) = case Map.lookup "vars" top of
  Just (_, Table' _ t) -> map snd (sortOn fst (inTable ["vars"] t))
  _ -> []
  where
    at pos = positionSpan fid src (Just pos)
    one code pos msg = let sp = at pos in [(spanStart sp, diagnostic code Error sp msg)]
    inTable path (MkTable kvs) =
      concat
        [ [ d
          | not (isIdentifier k),
            d <- one "G03110" kpos (T.intercalate "." path <> " のキー " <> k <> " は式の名前の形（英字か _ で始まり、英数字と _ が続く）で書きます")
          ]
            <> value (path <> [k]) v
        | (k, (kpos, v)) <- Map.toList kvs
        ]
    value path = \case
      Double' pos _ -> unsupported path pos "浮動小数点数"
      TimeOfDay' pos _ -> unsupported path pos "時刻"
      LocalTime' pos _ -> unsupported path pos "日時"
      ZonedTime' pos _ -> unsupported path pos "日時"
      List' _ xs -> concatMap (value path) xs
      Table' _ t -> inTable path t
      _ -> []
    unsupported path pos what =
      one "G03109" pos (T.intercalate "." path <> " に" <> what <> "は書けません。[vars] の値は文字列、整数、真偽値、日付、配列、表のどれかです")
    isIdentifier k = case T.uncons k of
      Just (c, r) -> (isAsciiAlpha c || c == '_') && T.all (\x -> isAsciiAlpha x || isDigit x || x == '_') r
      Nothing -> False
    isAsciiAlpha c = isAsciiLower c || isAsciiUpper c

{- | Where the page-numbering of each chapter file is written
(docs/adr/0260), in the order of 'chapterFiles': for an entry with one,
the span of its value, and its style and its start as written with their
spans.
-}
data NumberingSite = NumberingSite
  { nsSpan :: !SrcSpan,
    nsStyle :: !(Maybe (SrcSpan, Value' Position)),
    nsStart :: !(Maybe (SrcSpan, Value' Position))
  }

numberingSites :: FileId -> Text -> Table' Position -> [Maybe NumberingSite]
numberingSites fid src (MkTable top) = case Map.lookup "chapters" top of
  Just (_, List' _ xs) -> concatMap entry xs
  _ -> []
  where
    at = positionSpan fid src . Just
    entry = \case
      Text' {} -> [Nothing]
      List' _ xs -> concatMap entry xs
      Table' _ (MkTable kvs) -> [site <$> lookupValue "page-numbering" kvs]
      _ -> []
    lookupValue k kvs = snd <$> Map.lookup k kvs
    site v = case v of
      Table' _ (MkTable kvs) -> NumberingSite (at (valueAnn v)) (valued <$> lookupValue "style" kvs) (valued <$> lookupValue "start" kvs)
      _ -> NumberingSite (at (valueAnn v)) Nothing Nothing
    valued x = (at (valueAnn x), x)

{- | G03121 at a style of page-numbering that is no name of a notation, and
G03122 at a start of 0 (docs/adr/0260), in the order of the chapters.
-}
numberingDiagnostics :: [Maybe NumberingSite] -> [Diagnostic]
numberingDiagnostics sites =
  concat
    [ [ diagnostic "G03121" Error sp ("page-numbering の style " <> name <> " は数の表記の名前ではありません（書ける名前: " <> T.intercalate "、" (map notationName notations) <> "）")
      | Just (sp, Text' _ name) <- [nsStyle s],
        Nothing <- [notationNamed name]
      ]
        <> [diagnostic "G03122" Error sp "page-numbering の start には 1 以上の整数を書きます" | Just (sp, Integer' _ 0) <- [nsStart s]]
    | Just s <- sites
    ]

-- | The chapters with the spans of their page-numbering and its style (docs/adr/0260).
withNumberingSpans :: [Maybe NumberingSite] -> [ChapterEntry] -> [ChapterEntry]
withNumberingSpans sites0 = snd . go sites0
  where
    go sites = \case
      [] -> (sites, [])
      e : es ->
        let (sites', e') = one sites e
            (sites'', es') = go sites' es
         in (sites'', e' : es')
    one sites = \case
      ChapterFile p m ed n -> case sites of
        s : rest -> (rest, ChapterFile p m ed (fill s <$> n))
        [] -> ([], ChapterFile p m ed n)
      ChapterGroup es -> ChapterGroup <$> go sites es
    fill s n = case s of
      Just site -> n {pnSpan = nsSpan site, pnStyleSpan = maybe (nsSpan site) fst (nsStyle site)}
      Nothing -> n

{- | The table [functions] (docs/adr/0161): [functions.requires], whose keys
are the kinds of requirements and whose values are the requirements of
each kind. v1 has the kind file, the paths of the files. Every other key
of [functions.requires] is G03101 at the key ('manifestCode').
-}
newtype FunctionsTable = FunctionsTable (Maybe [FilePath])

instance FromValue FunctionsTable where
  fromValue = parseTableFromValue (FunctionsTable . (>>= id) <$> optKeyOf "requires" requires)
    where
      requires = \case
        Table' _ (MkTable kvs) -> do
          mapM_ (\(k, (pos, _)) -> inKey k (warnAt pos ("[functions.requires] に知らない要求の種類があります: " <> T.unpack k <> "（使える種類: file）"))) [kv | kv@(k, _) <- Map.toList kvs, k /= "file"]
          case Map.lookup "file" kvs of
            Nothing -> pure Nothing
            Just (_, v) -> Just . map T.unpack <$> inKey "file" (fromValue v)
        v -> typeError "table" v

-- | The [diagnostics] table (golem-syntax ADR 0002, docs/adr 0104).
data DiagnosticsTable = DiagnosticsTable {silenced :: Set DiagnosticCode, silencedInfo :: Set DiagnosticCode}

instance FromValue DiagnosticsTable where
  fromValue = parseTableFromValue (DiagnosticsTable <$> codes "silence-notices" noticeSilence <*> codes "silence-info" infoSilence)
    where
      codes key sl = fromMaybe Set.empty <$> optKeyOf key (silenceList sl)

{- | A list of silenced codes: the codes it accepts, the message of a code
it does not, and the codes of the other list with the hint that names it
(docs/adr 0104).
-}
data SilenceList = SilenceList
  { slAccepts :: [DiagnosticCode],
    slRefusal :: String,
    slOther :: [DiagnosticCode],
    slOtherHint :: String
  }

noticeSilence :: SilenceList
noticeSilence = SilenceList noticeCodes "抑制できるのはお知らせのコードだけです: " infoCodes "（情報のコードは silence-info に書きます）"

infoSilence :: SilenceList
infoSilence = SilenceList infoCodes "silence-info に書けるのは情報のコードだけです: " noticeCodes "（お知らせのコードは silence-notices に書きます）"

{- | The codes of silence-notices or silence-info. An element that is not a
code the list accepts is reported at the element; the scope of the element
makes it G03024 ('manifestCode'). Every such element is reported, not only
the first.
-}
silenceList :: SilenceList -> Value' l -> Matcher l (Set DiagnosticCode)
silenceList sl = \case
  List' _ xs -> Set.fromList . catMaybes <$> traverse (\(i, x) -> inIndex i (element x)) (zip [0 ..] xs)
  v -> typeError "array" v
  where
    element = \case
      Text' l t
        | not (isCodeShape t) -> warnAt l ("診断のコードは大文字の " <> T.unpack codeShapeWording <> "を続けて書きます: " <> T.unpack t) >> pure Nothing
        | DiagnosticCode t `notElem` slAccepts sl ->
            warnAt l (slRefusal sl <> T.unpack t <> (if DiagnosticCode t `elem` slOther sl then slOtherHint sl else "")) >> pure Nothing
        | otherwise -> pure (Just (DiagnosticCode t))
      v -> warnAt (Toml.valueAnn v) "診断のコードは文字列で書きます" >> pure Nothing

{- | The code of a schema message of the manifest: G03024 for an element of
silence-notices or silence-info, G03101 for an unknown kind of
[functions.requires] (docs/adr/0161), G03001 otherwise.
-}
manifestCode :: [Scope] -> Text
manifestCode = \case
  [ScopeKey "functions", ScopeKey "requires", ScopeKey k] | k /= "file" -> "G03101"
  [ScopeKey "diagnostics", ScopeKey "silence-notices", ScopeIndex _] -> "G03024"
  [ScopeKey "diagnostics", ScopeKey "silence-info", ScopeIndex _] -> "G03024"
  _ -> "G03001"

defaultTargets :: Targets
defaultTargets = Targets Nothing Nothing True [] Nothing Nothing

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
      atLeastOne v =
        naturalIntOf v >>= \n ->
          if n < 1 then failAt (valueAnn v) "版と刷の番号は 1 以上の整数です" else pure n

instance FromValue ChapterEntry where
  fromValue = \case
    Text' _ t -> pure (ChapterFile (T.unpack t) Nothing [] Nothing)
    List' _ xs -> ChapterGroup <$> traverse fromValue xs
    v@Table' {} -> parseTableFromValue (ChapterFile . T.unpack <$> reqKey "file" <*> optKey "master" <*> sourceEdits <*> optKeyOf "page-numbering" pageNumbering) v
    v -> failAt (valueAnn v) "章は、ファイルのパス、表、配列のどれかで書きます"

{- | The value of page-numbering (docs/adr/0260): a table of style and
start. A style that is no notation and a start of 0 are reported before
the schema (G03121, G03122, 'numberingDiagnostics'); here they are taken
as no notation and as written. A negative start is G02103, a start that is
no integer and an unknown key G03001. The spans are filled in by
'parseManifest'.
-}
pageNumbering :: Value' l -> Matcher l PageNumbering
pageNumbering = parseTableFromValue $ do
  st <- optKey "style"
  start <- optKeyOf "start" naturalOf
  pure (PageNumbering (st >>= notationNamed >>= \n -> if notationName n == "arabic" then Nothing else Just n) (toInteger <$> start) noSpan noSpan)
  where
    noSpan = mkSpan (FileId 0) 0 0

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
        { tgPdf = fmap ptIsbn pdf,
          tgEpub = fmap isbnOf epub,
          tgHtml = isJust (html :: Maybe EmptyTable),
          tgText = maybe [] textVariants txt,
          tgPdfA = pdf >>= ptPdfA,
          tgPdfUa = pdf >>= ptPdfUa
        }

-- | [targets.pdf]: the ISBN, and the PDF/A and PDF/UA it declares (docs/adr ADR 0183).
data PdfTable = PdfTable
  { ptIsbn :: Maybe Text,
    ptPdfA :: Maybe PdfAPart,
    ptPdfUa :: Maybe PdfUaPart
  }

{- | pdfa takes "2a" alone and pdfua "1" alone; any other value, and a
value that is not a string, is G03001 at the value (docs/adr ADR 0183).
The values are strings so that parts and levels can be added later.
-}
instance FromValue PdfTable where
  fromValue = parseTableFromValue (PdfTable <$> optKey "isbn" <*> optKeyOf "pdfa" pdfa <*> optKeyOf "pdfua" pdfua)
    where
      pdfa = \case
        Text' _ "2a" -> pure PdfA2a
        Text' l v -> failAt l (T.unpack ("pdfa に書けるのは \"2a\" だけです: " <> v))
        v -> typeError "string" v
      pdfua = \case
        Text' _ "1" -> pure PdfUa1
        Text' l v -> failAt l (T.unpack ("pdfua に書けるのは \"1\" だけです: " <> v))
        v -> typeError "string" v

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

-- | url or path, exactly one of them (docs/adr/0109).
instance FromValue PluginDecl where
  fromValue v = do
    (u, p, o, d) <- parseTableFromValue ((,,,) <$> optKey "url" <*> optKey "path" <*> optKey "overrides" <*> optKey "data") v
    src <- case (u, p) of
      (Just x, Nothing) -> pure (PluginUrl x)
      (Nothing, Just x) -> pure (PluginPath (T.unpack x))
      (Just _, Just _) -> failAt (valueAnn v) "プラグインには url と path のどちらか一方だけを書きます"
      (Nothing, Nothing) -> failAt (valueAnn v) "プラグインには url か path のどちらかを書きます"
    pure (PluginDecl src (fromMaybe [] o) (maybe Map.empty (Map.map T.unpack) d))

instance FromValue FilterDecl where
  fromValue v = do
    (p, fn, f, fs) <- parseTableFromValue ((,,,) <$> optKey "plugin" <*> optKey "function" <*> reqKey "filter" <*> reqKey "files") v
    -- plugin or function, one of them (docs/adr/0162)
    src <- case (p, fn) of
      (Just x, Nothing) -> pure (FilterPlugin x)
      (Nothing, Just x) -> pure (FilterFunction (T.unpack x))
      (Just _, Just _) -> failAt (valueAnn v) "フィルタには plugin と function のどちらか一方だけを書きます"
      (Nothing, Nothing) -> failAt (valueAnn v) "フィルタには plugin か function のどちらかを書きます"
    pure (FilterDecl src f (map T.unpack fs))

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

{- | 'decodeStrictBy' whose unknown keys are those the schema does not
know (docs/adr ADR 0169): the warnings of toml-parser for the keys left in
a table are dropped, and the keys the schema does not know are added to
the errors of the values, or to the other warnings. So an error of a value
does not hide an unknown key. The messages are in the order of their
positions in the file.
-}
decodeStrictWith :: (FromValue a) => Node -> Text -> ([Scope] -> Text) -> FileId -> Text -> Either [Diagnostic] a
decodeStrictWith schema code codeAt fid src = case parseToml src of
  Left (ErrSyntax (Located pos msg)) -> Left [diagnostic code Error (positionSpan fid src (Just pos)) ("TOML の誤りです: " <> syntaxMessage msg)]
  Left (ErrSemantics (SemanticError pos key kind)) -> Left [diagnostic code Error (positionSpan fid src (Just pos)) ("TOML の誤りです: " <> semanticMessage kind key)]
  Right tab -> decodeStrictTableWith schema codeAt fid src tab

-- | Decode an already parsed table after a caller has resolved its values.
-- The annotations retain the original source positions (ADR 0320).
decodeStrictTableWith :: (FromValue a) => Node -> ([Scope] -> Text) -> FileId -> Text -> Table' Position -> Either [Diagnostic] a
decodeStrictTableWith schema codeAt fid src tab =
  let unknown = unknownKeys schema tab
      report = Left . tomlDiagnosticsBy codeAt fid src . sortOn (fmap (\(Position _ l c) -> (l, c)) . matchAnn)
   in case runMatcher (fromValue (Table' (Position 0 1 1) tab)) of
        Failure es -> report (es <> unknown)
        Success ws a -> case filter (not . isPrefixOf "unexpected key: " . matchMessage) ws <> unknown of
          [] -> Right a
          ms -> report ms

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

-- | The tables of a TOML text before any schema; Nothing for an error of TOML.
readTomlTable :: Text -> Maybe (Table' Position)
readTomlTable = either (const Nothing) Just . parseToml

-- | The span of a position of toml-parser; the start of the file without one.
positionSpan :: FileId -> Text -> Maybe Position -> SrcSpan
positionSpan fid src = \case
  Just (Position _ l c)
    | Just off <- lineColToOffset (mkLineIndex src) (LineCol (l - 1) (c - 1)) -> mkSpan fid off off
  _ -> mkSpan fid 0 0

{- | Reads manifest.toml. A string with a character that cannot be written
to the output is G03028 before the schema (docs/adr ADR 0042).
-}
parseManifest :: FileId -> Text -> Either [Diagnostic] Manifest
parseManifest fid src = do
  case either (const []) (unwritableStrings fid src) (parseToml src) of
    [] -> Right ()
    ds -> Left ds
  -- G03109 and G03110 of [vars], G03121 and G03122 of page-numbering, with the errors of the schema (docs/adr/0185, docs/adr/0260)
  let raw = either (const Nothing) Just (parseToml src)
      sites = maybe [] (numberingSites fid src) raw
      varsDiags = maybe [] (varsDiagnostics fid src) raw <> numberingDiagnostics sites
  m0 <- case decodeStrictBy "G03001" manifestCode fid src of
    Left ds -> Left (varsDiags <> ds)
    Right _ | not (null varsDiags) -> Left varsDiags
    Right m -> Right m
  let m = m0 {manifestChapters = withNumberingSpans sites (manifestChapters m0)}
      t = manifestTargets m
  if tgHtml t || not (null (tgText t)) || isJust (tgPdf t) || isJust (tgEpub t)
    then Right m
    else Left [diagnostic "G03001" Error (mkSpan fid 0 0) "出力ターゲットが一つもありません"]

{- | The span of a value of manifest.toml by the keys of its tables and its
key, such as @["targets", "pdf", "pdfa"]@: at the start of the value, as
the schema messages are (docs/adr ADR 0183). Nothing when the key is not
there or the TOML does not read.
-}
manifestValueSpan :: FileId -> Text -> [Text] -> Maybe SrcSpan
manifestValueSpan fid src keys = case parseToml src of
  Left _ -> Nothing
  Right tab -> positionSpan fid src . Just <$> go tab keys
  where
    go (MkTable kvs) = \case
      [k] -> valueAnn . snd <$> Map.lookup k kvs
      k : rest -> case snd <$> Map.lookup k kvs of
        Just (Table' _ t) -> go t rest
        _ -> Nothing
      [] -> Nothing

{- | G03028 at each string of a TOML table with a character that cannot be
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
             in [(spanStart sp, diagnostic "G03028" Error sp (pathText path <> " に出力に書けない文字（" <> codePointText c <> "）があります"))]
      List' _ vs -> concat (zipWith (\i v -> value (path <> [ScopeIndex i]) v) [0 ..] vs)
      Table' _ t -> inTable path t
      _ -> []

{- | Converts toml-parser messages to diagnostics at their line, with the
code taken from the path of each message.
-}
tomlDiagnosticsBy :: ([Scope] -> Text) -> FileId -> Text -> [MatchMessage Position] -> [Diagnostic]
tomlDiagnosticsBy codeAt fid src = map one
  where
    one (MatchMessage loc path msg) =
      diagnostic (if msg == naturalOutOfRange then "G02103" else codeAt path) Error (positionSpan fid src loc) (schemaMessage path msg)

{- | The message of toml-parser for a negative number read as a natural
number. It is G02103 in every file of settings, the code of a negative
number at a place that takes a natural number (docs/adr ADR 0102).
-}
naturalOutOfRange :: String
naturalOutOfRange = "integer out of range for Natural"

-- | A key that takes a natural number, read as toml-parser reads a 'Natural' (docs/adr ADR 0102).
naturalOf :: Value' l -> Matcher l Natural
naturalOf = fromValue

{- | A natural number that the layout uses as an 'Int' (docs/adr ADR
0102): the field is a 'Natural', and the upper bound is checked here, where
the value has its position; one past the range of 'Int' is the message of
toml-parser for it. The bound is 2^31 - 1, the 'Int' of wasm32, on every
target, so that the native builds and golem.wasm take the same values
(docs/adr ADR 0247).
-}
naturalIntOf :: Value' l -> Matcher l Natural
naturalIntOf v =
  naturalOf v >>= \n ->
    if n > maxNaturalInt then failAt (valueAnn v) "integer out of range for Int" else pure n

-- | The largest natural number used as an 'Int': 2^31 - 1 on every target (docs/adr ADR 0247).
maxNaturalInt :: Natural
maxNaturalInt = fromIntegral (maxBound :: Int32)
