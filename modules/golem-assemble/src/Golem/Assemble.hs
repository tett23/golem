{- | Document assembly, S1 (golem-doc ADR 0002): values that depend on the
whole document. Page numbers (S2) remain as 'Ref' 'RefPage'.
-}
module Golem.Assemble
  ( AssembleConfig (..),
    NoteNumbering (..),
    DocValues (..),
    Book (..),
    HeadingInfo (..),
    LabelTarget (..),
    TocEntry (..),
    IndexGroup (..),
    IndexLocator (..),
    IndexSection (..),
    ChannelEntry (..),
    ListAt,
    assemble,
    citeNumber,
    tocWithinDepth,
    bibliographyAt,
    indexAt,
    channelAt,
    indexGroups,
    indexReferences,
    bookChapters,
    notesTitle,
    documentNotes,
    headingAnchor,
    inlineText,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (unless, when, zipWithM)
import Control.Monad.State.Strict
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Function (on)
import Data.Graph (SCC (..), stronglyConnComp)
import Data.List (groupBy, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing, listToMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.Collation
import Golem.Doc.IR
import Golem.Numerals.Format (Unwritable (..), formatNumber, formatUsesChapter)
import Golem.Syntax

data AssembleConfig = AssembleConfig
  { acHeadingFormats :: !(Map Int Text),
    acFigureFormat :: !Text,
    {- | the line of each @number by the span of the block it numbers,
    where G04007 points; a block not in it is pointed at itself
    -} acNumberSites :: !(Map SrcSpan SrcSpan),
    -- | the range over which notes are numbered (golem-driver ADR 0018)
    acNoteNumbering :: !NoteNumbering,
    {- | the chapter of the manifest (from 0) of each document, in the order
    of the documents; a document past its end is a chapter of its own
    -} acChapterOf :: ![Int],
    -- | [code] number: the format of listing numbers (golem-driver ADR 0023)
    acListingFormat :: !Text,
    -- | [tables] number: the format of table numbers (docs/adr/0262)
    acTableFormat :: !Text,
    -- | the channels the plugins declare, by name (golem-doc ADR 0007)
    acChannels :: !(Map Text ChannelDecl),
    {- | the lines of a page, @[page.grid].lines@: a run of blank lines of
    as many lines or more is dropped (docs/adr ADR 0047)
    -} acPageLines :: !Int
  }

{- | An entry of a list of a channel of a plugin (golem-doc ADR 0007): the
key of its items, the body of the first of them, and where they are, in
document order.
-}
data ChannelEntry = ChannelEntry
  { ceKey :: !(Maybe Text),
    ceBody :: ![Inline],
    ceLocations :: ![(FileId, SrcSpan)]
  }
  deriving stock (Eq, Show)

{- | The range over which footnotes and sidenotes are numbered from 1
(golem-driver ADR 0018): a file, a chapter of the manifest, or the book.
-}
data NoteNumbering = NumberPerFile | NumberPerChapter | NumberPerBook
  deriving stock (Eq, Show)

-- | The values of the @doc@ namespace.
newtype DocValues = DocValues {dvChapterCount :: Integer}

data HeadingInfo = HeadingInfo
  { hiLevel :: !Int,
    hiNumbers :: !(Maybe [Integer]),
    hiNumberText :: !(Maybe Text),
    hiTitle :: ![Inline],
    hiAnchor :: !Text,
    hiFile :: !FileId
  }
  deriving stock (Eq, Show)

data LabelTarget = LabelTarget
  { ltSpan :: !SrcSpan,
    ltNumber :: !(Maybe Inline),
    ltTitle :: ![Inline],
    ltAnchor :: !Text,
    ltFile :: !FileId
  }
  deriving stock (Eq, Show)

data TocEntry = TocEntry
  { teLevel :: !Int,
    teNumber :: !(Maybe Text),
    teTitle :: ![Inline],
    teAnchor :: !Text,
    teFile :: !FileId,
    -- | the span of the heading block, the key of 'bookHeadings' (golem-driver ADR 0009)
    teSpan :: !SrcSpan
  }
  deriving stock (Eq, Show)

{- | Where an entry of the index points (docs/adr/0265): the page of a
mark, or the pages from the begin mark of a range to its end mark.
-}
data IndexLocator
  = AtMark !(FileId, SrcSpan)
  | Between !(FileId, SrcSpan) !(FileId, SrcSpan)
  deriving stock (Eq, Show)

{- | An entry of the index (docs/adr/0265): its terms and readings, where
it points in document order of the first mark of each, and its cross
references, each once, in the collation order of their targets.
-}
data IndexGroup = IndexGroup
  { igTerms :: ![Text],
    igReadings :: ![Text],
    igLocators :: ![IndexLocator],
    igSee :: ![(SeeKind, [Text])]
  }
  deriving stock (Eq, Show)

{- | The entries of the index under one heading, in collation order
(docs/adr/0265). The assembly makes the headings for every book; a book
without them leaves them out of its outputs.
-}
data IndexSection = IndexSection
  { isHeading :: !Text,
    isGroups :: ![IndexGroup]
  }
  deriving stock (Eq, Show)

data Book = Book
  { bookDocs :: ![Document],
    bookHeadings :: !(Map SrcSpan HeadingInfo),
    bookFigures :: !(Map SrcSpan Text),
    -- | the listing number of each code block with a caption (golem-driver ADR 0023)
    bookListings :: !(Map SrcSpan Text),
    -- | the table number of each table with a caption (docs/adr/0262)
    bookTables :: !(Map SrcSpan Text),
    bookToc :: ![TocEntry],
    bookTocDepth :: !(Maybe Int),
    {- | each @index with the entries of its range under their headings, in
    document order (golem-doc ADR 0008, docs/adr/0265)
    -} bookIndexes :: ![(ListAt, [IndexSection])],
    {- | each @bibliography with the numbers of the citations of its range,
    in document order; without @bibliography, one list without a place over
    the whole book (golem-doc ADR 0008)
    -} bookBibliographies :: ![(Maybe ListAt, [(Text, Int)])],
    -- | the list and the number of each citation mark, by its file and span
    bookCiteMarks :: !(Map (FileId, SrcSpan) (Maybe ListAt, Int)),
    bookLabels :: !(Map Text LabelTarget),
    bookReferenced :: !(Set Text),
    {- | the chapter of the manifest of each document, in the order of
    'bookDocs' (golem-driver ADR 0018, 0026); a document past its end is a
    chapter of its own
    -} bookChapterOf :: ![Int],
    {- | each @channel in document order: its place, its channel and its
    entries (golem-doc ADR 0007)
    -} bookChannels :: ![(ListAt, Text, [ChannelEntry])],
    -- | the channels the plugins declare, by name
    bookChannelDecls :: !(Map Text ChannelDecl),
    {- | the images plugins made for figures, by the source of the figure
    (docs/adr/0123); the outputs read them instead of a file of the project
    -} bookImages :: !(Map Text ByteString)
  }

{- | The place of a list of a channel: the file and the span of its block
(golem-doc ADR 0008).
-}
type ListAt = (FileId, SrcSpan)

{- | The number of a citation mark: its number in the list it belongs to
(golem-doc ADR 0008). The key decides it, so two marks a plugin puts out
at one span keep their own numbers.
-}
citeNumber :: Book -> SrcSpan -> Text -> Maybe Int
citeNumber book sp k = do
  (at, _) <- Map.lookup (spanFile sp, sp) (bookCiteMarks book)
  lookup at (bookBibliographies book) >>= lookup k

{- | The entries of the table of contents within the depth of @toc, in
order; every entry without @toc (golem-epub ADR 0002). The EPUB
navigation document and the HTML index page use it.
-}
tocWithinDepth :: Book -> [TocEntry]
tocWithinDepth book = [e | e <- bookToc book, maybe True (teLevel e <=) (bookTocDepth book)]

-- | The citations of the @bibliography at a block span.
bibliographyAt :: Book -> SrcSpan -> [(Text, Int)]
bibliographyAt book sp = fromMaybe [] (lookup (Just (spanFile sp, sp)) (bookBibliographies book))

-- | The entries of the @channel at a block span (golem-doc ADR 0007).
channelAt :: Book -> SrcSpan -> [ChannelEntry]
channelAt book sp = concat [es | (at, _, es) <- bookChannels book, at == (spanFile sp, sp)]

-- | The entries of the @index at a block span under their headings.
indexAt :: Book -> SrcSpan -> [IndexSection]
indexAt book sp = fromMaybe [] (lookup (spanFile sp, sp) (bookIndexes book))

{- | The documents of the book by chapter of the manifest, in order
(golem-driver ADR 0026).
-}
bookChapters :: Book -> [[Document]]
bookChapters book = map (map snd) (groupOn fst (zip chapterKeys (bookDocs book)))
  where
    chapterKeys = map Just (bookChapterOf book) <> map (const Nothing) [length (bookChapterOf book) ..]
    groupOn _ [] = []
    groupOn f (x : xs) = case f x of
      Nothing -> [x] : groupOn f xs
      k -> let (same, rest) = span ((== k) . f) xs in (x : same) : groupOn f rest

{- | The title of the list of notes at the end of a chapter (golem-driver
ADR 0026): 注 in a book whose primary language subtag is ja, Notes otherwise.
-}
notesTitle :: Text -> Text
notesTitle lang = if T.toLower (T.takeWhile (/= '-') lang) == "ja" then "注" else "Notes"

{- | The inlines of a block, the notes among them, in order, through lists,
definition lists, tables and captions (golem-driver ADR 0018, 0026), each
with the language of its place: that of the innermost language span or
block around it (docs/adr ADR 0187).
-}
blockNotes :: Maybe Text -> Block -> [(Maybe Text, Inline)]
blockNotes outer (Block _ _ blang body) = case body of
  Paragraph _ is -> deep l is
  Heading _ _ is -> deep l is
  BulletList items -> concatMap (concatMap (blockNotes l) . itemBlocks) items
  OrderedList items -> concatMap (concatMap (blockNotes l) . itemBlocks) items
  DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap (deep l) ts <> concatMap (concatMap (blockNotes l)) ds) gs
  TableBlock t -> concatMap (deep l) (tableHeader t) <> concatMap (concatMap (deep l)) (tableRows t)
  FigureBlock f -> concatMap (blockNotes l) (figCaption f)
  _ -> []
  where
    l = blang <|> outer
    deep at = concatMap (\i -> (at, i) : nested at i)
    nested at = \case
      Kenten _ _ xs -> deep at xs
      Color _ _ xs -> deep at xs
      CharStyle _ _ xs -> deep at xs
      Lang _ t xs -> deep (Just t) xs
      -- the title a [ref-title] copies may hold notes (docs/adr/0215)
      Resolved _ _ _ xs -> deep at xs
      _ -> []

{- | The notes of a document in order: their spans, numbers and bodies
(golem-driver ADR 0026). A body is in a language span of the language of
the place of its mark, if that has one (docs/adr ADR 0187).
-}
documentNotes :: Document -> [(SrcSpan, Int, [[Inline]])]
documentNotes (Document _ bs) = [(sp, n, [inLang sp (pl <|> l) is | Block _ _ pl (Paragraph _ is) <- body]) | (l, Note sp n body) <- concatMap (blockNotes Nothing) bs]

{- | The paragraphs of the body of a note with their inlines changed in
an applicative (docs/adr/0263); the other blocks as they are.
-}
traverseNoteBody :: (Applicative f) => ([Inline] -> f [Inline]) -> [Block] -> f [Block]
traverseNoteBody f = traverse $ \case
  b@(Block _ _ _ (Paragraph st is)) -> (\is' -> b {blockBody = Paragraph st is'}) <$> f is
  b -> pure b

headingAnchor :: Maybe Text -> SrcSpan -> Text
headingAnchor (Just l) _ = l
headingAnchor Nothing (SrcSpan (FileId f) s _) = "h-" <> T.pack (show f) <> "-" <> T.pack (show s)

-- | The plain text of inlines (used for titles in plain contexts).
inlineText :: InlineF r -> Text
inlineText = \case
  Text _ t -> t
  Ruby _ _ segs -> foldMap (foldMap inlineText . rsBase) segs
  Kenten _ _ xs -> foldMap inlineText xs
  Color _ _ xs -> foldMap inlineText xs
  CharStyle _ _ xs -> foldMap inlineText xs
  Link _ _ xs -> foldMap inlineText xs
  Lang _ _ xs -> foldMap inlineText xs
  Resolved _ _ _ xs -> foldMap inlineText xs
  Tcy _ t -> t
  Number _ n _ -> T.pack (show n)
  _ -> ""

-- | @{n}@, @{1}.{n}@, ... @{1}.{2}.{3}.{4}.{5}.{n}@ by the level (docs/adr/0188).
defaultHeadingFormat :: Int -> Text
defaultHeadingFormat l = T.intercalate "." ([T.pack ("{" <> show k <> "}") | k <- [1 .. min 5 (l - 1)]] <> ["{n}"])

-- | The levels of headings (docs/adr/0188).
headingLevels :: Int
headingLevels = 6

-- ------------------------------------------------------------------ numbering

data NumSt = NumSt
  { nsCounters :: ![Integer], -- current numbers by level (1-based index)
    nsChapter :: !(Maybe Integer),
    nsFigure :: !Integer,
    nsHeadings :: !(Map SrcSpan HeadingInfo),
    nsFigures :: !(Map SrcSpan (Maybe Integer, Integer)),
    -- | the counter of code blocks with a caption, apart from figures (golem-driver ADR 0023)
    nsListing :: !Integer,
    nsListings :: !(Map SrcSpan (Maybe Integer, Integer)),
    -- | the counter of tables with a caption, apart from figures and code blocks (docs/adr/0262)
    nsTable :: !Integer,
    nsTables :: !(Map SrcSpan (Maybe Integer, Integer)),
    nsDiags :: ![Diagnostic]
  }

numberDocs :: AssembleConfig -> [Document] -> NumSt
numberDocs cfg docs = execState (mapM_ doc docs) (NumSt (replicate headingLevels 0) Nothing 0 Map.empty Map.empty 0 Map.empty 0 Map.empty [])
  where
    doc (Document fid bs) = mapM_ (blk fid) bs
    blk fid (Block sp lbl lang b) = case b of
      Heading l a is -> do
        st <- get
        let cs = nsCounters st
            (cs', nums)
              | haNoNumber a = (cs, Nothing)
              | otherwise =
                  let cur = cs !! (l - 1)
                      n = maybe (cur + 1) toInteger (haNumber a)
                      upd = take (l - 1) cs <> [n] <> replicate (headingLevels - l) 0
                   in (upd, Just (take l upd))
            fmt = fromMaybe (defaultHeadingFormat l) (Map.lookup l (acHeadingFormats cfg))
            numWritten = (\ns -> formatNumber fmt ns (Just (head' ns))) <$> nums
            -- G04012: a number the format cannot write leaves the heading without its number text (docs/adr/0213)
            numText = numWritten >>= either (const Nothing) Just
            unwritable = [unwritableNumber "G04012" ("[headings." <> T.pack (show l) <> "]") fmt sp u | Just (Left u) <- [numWritten]]
            chapter = if l == 1 then head' <$> nums else nsChapter st
            figureReset = if l == 1 then 0 else nsFigure st
            -- the title of the copies, without the anchors of lists (docs/adr/0145)
            -- the language of the heading wraps the whole title of the copies (docs/adr ADR 0187)
            info = HeadingInfo l nums numText (inLang sp lang (withoutAnchors (fromMaybe is (haTocTitle a)))) (headingAnchor lbl sp) fid
            -- G04007: @number equal to the number it would get without it (golem-syntax ADR 0002)
            redundant = [redundantNumber cfg sp n | not (haNoNumber a), Just n <- [toInteger <$> haNumber a], n == cs !! (l - 1) + 1]
        put
          st
            { nsDiags = nsDiags st <> redundant <> unwritable,
              nsCounters = cs',
              nsChapter = if l == 1 then chapter else nsChapter st,
              nsFigure = figureReset,
              nsListing = if l == 1 then 0 else nsListing st,
              nsTable = if l == 1 then 0 else nsTable st,
              nsHeadings = Map.insert sp info (nsHeadings st)
            }
      -- a figure with @nonumber takes no number and uses none up (docs/adr/0200)
      FigureBlock f -> do
        unless (figNoNumber f) $ do
          st <- get
          let n = nsFigure st + 1
          put st {nsFigure = n, nsFigures = Map.insert sp (nsChapter st, n) (nsFigures st)}
        mapM_ (blk fid) (figCaption f)
      -- a code block with a caption has a listing number (golem-driver ADR 0023), unless it has @nonumber (docs/adr/0200)
      CodeBlock Code {codeCaption = Just _, codeNoNumber = False} -> do
        st <- get
        let n = nsListing st + 1
        put st {nsListing = n, nsListings = Map.insert sp (nsChapter st, n) (nsListings st)}
      -- a table with a caption has a table number, unless it has @nonumber (docs/adr/0262)
      TableBlock Table {tableCaption = Just _, tableNoNumber = False} -> do
        st <- get
        let n = nsTable st + 1
        put st {nsTable = n, nsTables = Map.insert sp (nsChapter st, n) (nsTables st)}
      BulletList items -> mapM_ (mapM_ (blk fid) . itemBlocks) items
      OrderedList items -> mapM_ (mapM_ (blk fid) . itemBlocks) items
      DefList gs -> mapM_ (mapM_ (mapM_ (blk fid)) . dgDefs) gs
      _ -> pure ()
    head' = \case
      (x : _) -> x
      [] -> 0

-- ------------------------------------------------------------------ assembly

assemble ::
  AssembleConfig ->
  -- | evaluates a deferred expression of the inline at the span
  (DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text) ->
  [Document] ->
  (Book, [Diagnostic])
assemble cfg evalDeferred docs0 =
  let (docs, blankDiags) = droppedBlankLines (acPageLines cfg) docs0
      ns = numberDocs cfg docs
      figureWritten = Map.map (\(ch, n) -> formatNumber (acFigureFormat cfg) [n] ch) (nsFigures ns)
      listingWritten = Map.map (\(ch, n) -> formatNumber (acListingFormat cfg) [n] ch) (nsListings ns)
      tableWritten = Map.map (\(ch, n) -> formatNumber (acTableFormat cfg) [n] ch) (nsTables ns)
      -- G04013, G04014 and G04100: a number the format cannot write leaves the block without its number text (docs/adr/0213, docs/adr/0262)
      unwritableErrors =
        [unwritableNumber "G04013" "[figures]" (acFigureFormat cfg) sp u | (sp, Left u) <- Map.toList figureWritten]
          <> [unwritableNumber "G04014" "[code]" (acListingFormat cfg) sp u | (sp, Left u) <- Map.toList listingWritten]
          <> [unwritableNumber "G04100" "[tables]" (acTableFormat cfg) sp u | (sp, Left u) <- Map.toList tableWritten]
      -- G04004 for figures, tables and code blocks (golem-driver ADR 0023, docs/adr/0262)
      outside fmt numbered =
        [ diagnostic "G04004" Error sp "章の外にある図版、表、コードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります。番号を振らないなら @nonumber を付けます"
        | formatUsesChapter fmt,
          (sp, (Nothing, _)) <- Map.toList numbered
        ]
      figureErrors = outside (acFigureFormat cfg) (nsFigures ns) <> outside (acListingFormat cfg) (nsListings ns) <> outside (acTableFormat cfg) (nsTables ns)
      (labels, labelDiags) = collectLabels ns docs
      chapterCount = toInteger (length [() | HeadingInfo {hiLevel = 1, hiNumbers = Just _} <- Map.elems (nsHeadings ns)])
      dv = DocValues chapterCount
      (docs', (refd, resolveDiags)) = runState (mapM (resolveDoc labels dv evalDeferred) docs) (Set.empty, [])
      tocs = [(d, sp) | Document _ bs <- docs, Block sp _ _ (ChannelOutput (TocOutput d)) <- allBlocks bs]
      tocDiags = case tocs of
        ((_, firstToc) : rest) ->
          [ (diagnostic "G04002" Error sp "@toc は文書に一つだけ置けます") {diagRelated = [(firstToc, "最初の @toc")]}
          | (_, sp) <- rest
          ]
        [] -> []
      toc =
        [ TocEntry (hiLevel h) (hiNumberText h) (hiTitle h) (hiAnchor h) (hiFile h) sp
        | Document _ bs <- docs,
          Block sp _ _ (Heading _ a _) <- allBlocks bs,
          not (haNoToc a),
          Just h <- [Map.lookup sp (nsHeadings ns)]
        ]
      (bibliographies, citeMarks) = numberCitations docs
      (indexes, indexDiags) = indexLists docs
   in ( Book
          { bookDocs = renumberNotes cfg docs',
            bookHeadings = nsHeadings ns,
            bookFigures = Map.mapMaybe (either (const Nothing) Just) figureWritten,
            bookListings = Map.mapMaybe (either (const Nothing) Just) listingWritten,
            bookTables = Map.mapMaybe (either (const Nothing) Just) tableWritten,
            bookToc = toc,
            bookTocDepth = case tocs of
              ((d, _) : _) -> Just d
              [] -> Nothing,
            bookIndexes = indexes,
            bookBibliographies = bibliographies,
            bookCiteMarks = citeMarks,
            bookLabels = labels,
            bookReferenced = refd,
            bookChapterOf = acChapterOf cfg,
            bookChannels = channelLists (acChannels cfg) docs',
            bookChannelDecls = acChannels cfg,
            bookImages = Map.empty
          },
        sortDiagnostics (nsDiags ns <> figureErrors <> unwritableErrors <> labelDiags <> resolveDiags <> tocDiags <> listNumberNotices cfg docs <> trailingBreaks docs <> blankDiags <> indexDiags)
      )

{- | G04012, G04013 and G04014 (docs/adr/0213): the first slot of the
number format of a block, from the left, whose notation cannot write its
number, at the block, whatever the target.
-}
unwritableNumber :: Text -> Text -> Text -> SrcSpan -> Unwritable -> Diagnostic
unwritableNumber code key fmt sp u =
  diagnostic code Error sp (key <> " の number " <> fmt <> " の {" <> uwSlot u <> "} では、" <> T.pack (show (uwNumber u)) <> " を表せません")

-- | G04007 at the @number line of the block (golem-syntax ADR 0002).
redundantNumber :: AssembleConfig -> SrcSpan -> Integer -> Diagnostic
redundantNumber cfg sp n =
  notice "G04007" (Map.findWithDefault sp sp (acNumberSites cfg)) ("@number " <> T.pack (show n) <> " は自動で振られる番号と同じです")

{- | G04007 for the items of numbered lists. An attribute before an item
makes a list of its own, which without the attribute would continue the
list right before it; so a list right after a numbered list counts on from
the last number of that list.
-}
listNumberNotices :: AssembleConfig -> [Document] -> [Diagnostic]
listNumberNotices cfg = concatMap (blocks . docBlocks)
  where
    blocks = snd . foldl step (Nothing, [])
    step (prev, acc) (Block sp _ _ body) = case body of
      OrderedList items ->
        let start = maybe 1 (+ 1) prev
            nums = numbersFrom start items
            autos = start : map (+ 1) nums
            found =
              [ redundantNumber cfg (if i == 0 then sp else itemSpan sp it) n
              | (i, it, auto) <- zip3 [0 :: Int ..] items autos,
                Just n <- [toInteger <$> itemNumber it],
                n == auto
              ]
         in (lastMaybe nums, acc <> found <> concatMap (blocks . itemBlocks) items)
      _ -> (Nothing, acc <> concatMap blocks (inner body))
    inner = \case
      BulletList items -> map itemBlocks items
      DefList gs -> concatMap dgDefs gs
      FigureBlock f -> [figCaption f]
      _ -> []
    numbersFrom _ [] = []
    numbersFrom next (ListItem n _ : rest) = let k = maybe next toInteger n in k : numbersFrom (k + 1) rest
    itemSpan sp it = case itemBlocks it of
      (Block bsp _ _ _ : _) -> bsp
      [] -> sp
    lastMaybe = \case
      [] -> Nothing
      xs -> Just (last xs)

{- | G04008 for the page and column breaks at the end of the last file: the
book drops them (golem-syntax ADR 0002). The breaks at the end of another
file act on the next file.
-}
trailingBreaks :: [Document] -> [Diagnostic]
trailingBreaks docs = case reverse docs of
  (Document _ bs : _) ->
    [ notice "G04008" sp "本の最後の改ページは効果がありません"
    | Block sp _ _ _ <- reverse (takeWhile isBreak (reverse bs))
    ]
  [] -> []
  where
    isBreak b = case blockBody b of
      ForcedBreak _ -> True
      _ -> False

{- | The blank lines that have no effect (docs/adr ADR 0046), dropped from
every output: G04009 for those at the end of the book, with only breaks,
controls of page breaks and other blank lines after them; G04010 for those
right before a page or column break, past the controls and other blank
lines, across the files too. The blocks stay in their files. Then G04011
for the runs of the blank lines that remain, with only controls of page
breaks between them, whose sum is the lines of a page or more (docs/adr
ADR 0047).
-}
droppedBlankLines :: Int -> [Document] -> ([Document], [Diagnostic])
droppedBlankLines pageLines docs0 =
  let (docs, ineffective) = ineffectiveBlankLines docs0
      (docs', tooLong) = blankLinesOverPage pageLines docs
   in (docs', ineffective <> tooLong)

{- | G04011 for each blank line of a run, with only controls of page breaks
between them and across the files, whose lines add up to the lines of a
page or more (docs/adr ADR 0047). The PDF drops such a run at the top of
a column, so every output drops it.
-}
blankLinesOverPage :: Int -> [Document] -> ([Document], [Diagnostic])
blankLinesOverPage pageLines docs =
  let flat = [(i, b) | (i, Document _ bs) <- zip [0 :: Int ..] docs, b <- bs]
      runs = blankRuns flat
      verdicts =
        [ ((i, sp), notice "G04011" sp ("@blank-line の行数 " <> T.pack (show total) <> " がページの行数 " <> T.pack (show pageLines) <> " 以上なので捨てます"))
        | run <- runs,
          let total = sum [toInteger n | (_, _, n) <- run],
          total >= toInteger pageLines,
          (i, sp, _) <- run
        ]
      dropped = Set.fromList (map fst verdicts)
      keep i b = case b of
        Block sp _ _ (BlankLines _) -> Set.notMember (i, sp) dropped
        _ -> True
   in ( [Document f [b | b <- bs, keep i b] | (i, Document f bs) <- zip [0 ..] docs],
        map snd verdicts
      )
  where
    -- the blank lines of each run, in order: controls of page breaks join, any other block parts
    blankRuns = filter (not . null) . go []
      where
        go acc [] = [reverse acc]
        go acc ((i, b) : rest) = case blockBody b of
          BlankLines n -> go ((i, blockSpan b, n) : acc) rest
          PageControl _ -> go acc rest
          _ -> reverse acc : go [] rest

ineffectiveBlankLines :: [Document] -> ([Document], [Diagnostic])
ineffectiveBlankLines docs =
  let flat = [(i, b) | (i, Document _ bs) <- zip [0 :: Int ..] docs, b <- bs]
      tails' = drop 1 (scanr (:) [] (map snd flat))
      verdicts =
        [ (key, diags)
        | ((i, Block sp _ _ (BlankLines _)), after) <- zip flat tails',
          let key = (i, sp)
              rest = dropWhile soft after
              atEnd = all quiet after
              end = [notice "G04009" sp "本の最後の @blank-line は効果がありません" | atEnd]
              brk = case rest of
                Block _ _ _ (ForcedBreak k) : _ -> [diagnostic "G04010" Warning sp ("@blank-line の直後に " <> breakName k <> " があります")]
                _ -> []
              diags = end <> brk,
          not (null diags)
        ]
      dropped = Set.fromList (map fst verdicts)
      keep i b = case b of
        Block sp _ _ (BlankLines _) -> Set.notMember (i, sp) dropped
        _ -> True
   in ( [Document f [b | b <- bs, keep i b] | (i, Document f bs) <- zip [0 ..] docs],
        concatMap snd verdicts
      )
  where
    soft b = case blockBody b of
      PageControl _ -> True
      BlankLines _ -> True
      _ -> False
    quiet b = case blockBody b of
      ForcedBreak _ -> True
      _ -> soft b
    breakName = \case
      BreakColumn -> "@column-break"
      _ -> "@page-break"

-- | Every block in document order, descending into containers.
allBlocks :: [Block] -> [Block]
allBlocks = concatMap go
  where
    go b@(Block _ _ _ body) =
      b : case body of
        BulletList items -> allBlocks (concatMap itemBlocks items)
        OrderedList items -> allBlocks (concatMap itemBlocks items)
        DefList gs -> allBlocks (concat (concatMap dgDefs gs))
        FigureBlock f -> allBlocks (figCaption f)
        _ -> []

collectLabels :: NumSt -> [Document] -> (Map Text LabelTarget, [Diagnostic])
collectLabels ns docs = foldl add (Map.empty, []) targets
  where
    targets =
      [ (l, LabelTarget sp num title (headingAnchor (Just l) sp) fid)
      | Document fid bs <- docs,
        Block sp (Just l) _ body <- allBlocks bs,
        let (num, title) = describe sp body
      ]
    describe sp = \case
      Heading _ _ is -> case Map.lookup sp (nsHeadings ns) of
        Just HeadingInfo {hiNumbers = Just [n], hiTitle = t} -> (Just (Number sp n Nothing), t)
        Just HeadingInfo {hiNumbers = Just nums, hiTitle = t} -> (Just (Text sp (T.intercalate "." (map (T.pack . show) nums))), t)
        Just h -> (Nothing, hiTitle h)
        Nothing -> (Nothing, withoutAnchors is)
      FigureBlock f -> case Map.lookup sp (nsFigures ns) of
        Just (ch, n) -> (Just (Text sp (maybe "" (\c -> T.pack (show c) <> "-") ch <> T.pack (show n))), [Text sp (figAlt f)])
        Nothing -> (Nothing, [Text sp (figAlt f)])
      -- the number and the caption of a code block (golem-driver ADR 0023)
      CodeBlock c -> case Map.lookup sp (nsListings ns) of
        Just (ch, n) -> (Just (Text sp (maybe "" (\x -> T.pack (show x) <> "-") ch <> T.pack (show n))), withoutAnchors (fromMaybe [] (codeCaption c)))
        Nothing -> (Nothing, withoutAnchors (fromMaybe [] (codeCaption c)))
      -- the number and the caption of a table (docs/adr/0262)
      TableBlock t -> case Map.lookup sp (nsTables ns) of
        Just (ch, n) -> (Just (Text sp (maybe "" (\x -> T.pack (show x) <> "-") ch <> T.pack (show n))), withoutAnchors (fromMaybe [] (tableCaption t)))
        Nothing -> (Nothing, withoutAnchors (fromMaybe [] (tableCaption t)))
      _ -> (Nothing, [])
    add (m, ds) (l, t) = case Map.lookup l m of
      Just prev ->
        ( m,
          ds
            <> [ (diagnostic "G04001" Error (ltSpan t) ("ラベルが重複しています: " <> l))
                   { diagRelated = [(ltSpan prev, "最初の定義")]
                   }
               ]
        )
      Nothing -> (Map.insert l t m, ds)

type R = State (Set Text, [Diagnostic])

resolveDoc :: Map Text LabelTarget -> DocValues -> (DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text) -> Document -> R Document
resolveDoc labels dv evalDeferred (Document fid bs) = Document fid <$> mapM blk bs
  where
    blk (Block sp l lang body) =
      Block sp l lang <$> case body of
        Paragraph st is -> Paragraph st <$> inls is
        Heading lv a is -> pure (Heading lv a is)
        BulletList items -> BulletList <$> mapM item items
        OrderedList items -> OrderedList <$> mapM item items
        DefList gs -> DefList <$> mapM (\(DefGroup ts ds) -> DefGroup <$> mapM inls ts <*> mapM (mapM blk) ds) gs
        TableBlock t -> (\cap h rows -> TableBlock t {tableCaption = cap, tableHeader = h, tableRows = rows}) <$> traverse inls (tableCaption t) <*> mapM inls (tableHeader t) <*> mapM (mapM inls) (tableRows t)
        FigureBlock f -> (\c -> FigureBlock f {figCaption = c}) <$> mapM blk (figCaption f)
        CodeBlock c -> (\cap -> CodeBlock c {codeCaption = cap}) <$> traverse inls (codeCaption c)
        other -> pure other
    item (ListItem n bs') = ListItem n <$> mapM blk bs'
    inls is = concat <$> mapM inl is
    baseRefs :: InlineNoRuby -> R [InlineNoRuby]
    baseRefs = \case
      Ref sp kind target | kind == RefNumber || kind == RefTitle -> do
        refs <- inl (Ref sp kind target)
        pure [Resolved pos k name (concatMap baseOnly xs) | Resolved pos k name xs <- refs]
      Kenten sp style xs -> pure . Kenten sp style <$> baseList xs
      Color sp color xs -> pure . Color sp color <$> baseList xs
      CharStyle sp style xs -> pure . CharStyle sp style <$> baseList xs
      Lang sp lang xs -> pure . Lang sp lang <$> baseList xs
      Link sp target xs -> pure . Link sp target <$> baseList xs
      other -> pure [other]
    baseList xs = concat <$> mapM baseRefs xs
    -- A title can contain ruby itself. Only its base fits inside another ruby.
    baseOnly = \case
      Ruby _ _ segs -> concatMap rsBase segs
      Kenten sp style xs -> [Kenten sp style (concatMap baseOnly xs)]
      Color sp color xs -> [Color sp color (concatMap baseOnly xs)]
      CharStyle sp style xs -> [CharStyle sp style (concatMap baseOnly xs)]
      Lang sp lang xs -> [Lang sp lang (concatMap baseOnly xs)]
      Link sp target xs -> [Link sp target (concatMap baseOnly xs)]
      Resolved sp kind target xs -> [Resolved sp kind target (concatMap baseOnly xs)]
      other -> maybe [] pure (noRuby other)
    inl :: Inline -> R [Inline]
    inl = \case
      Ref sp k l -> do
        modify' (first (Set.insert l))
        case (Map.lookup l labels, k) of
          (Nothing, _) -> do
            modify' (\(s, ds) -> (s, ds <> [diagnostic "G04003" Error sp ("存在しないラベルへの参照です: " <> l)]))
            pure []
          -- the text of the number or the title, in the reference it resolves (docs/adr/0215)
          (Just t, RefNumber) -> case ltNumber t of
            Just n -> pure [Resolved sp RefNumber l [relocate sp n]]
            Nothing -> do
              modify' (\(s, ds) -> (s, ds <> [diagnostic "G04005" Error sp ("番号を持たない要素への参照です: " <> l)]))
              pure []
          (Just t, RefTitle) -> case ltTitle t of
            [] -> do
              modify' (\(s, ds) -> (s, ds <> [diagnostic "G04006" Error sp ("題を持たない要素への参照です: " <> l)]))
              pure []
            title -> pure [Resolved sp RefTitle l (map (relocate sp) title)]
          (Just _, RefPage) -> pure [Ref sp k l]
      Ruby sp annotation segments -> do
        resolved <- mapM (\segment -> (\xs -> segment {rsBase = xs}) <$> baseList (rsBase segment)) segments
        pure [Ruby sp annotation resolved]
      Deferred sp e -> case evalDeferred dv sp e of
        Left d -> modify' (\(s, ds) -> (s, ds <> [d])) >> pure []
        Right t -> pure [Text sp t]
      Kenten sp s xs -> pure . Kenten sp s <$> inls xs
      Color sp c xs -> pure . Color sp c <$> inls xs
      CharStyle sp c xs -> pure . CharStyle sp c <$> inls xs
      Lang sp t xs -> pure . Lang sp t <$> inls xs
      Resolved sp k l xs -> pure . Resolved sp k l <$> inls xs
      Note sp n body -> pure . Note sp n <$> traverseNoteBody inls body
      -- the body of an item resolves like the text around it (golem-doc ADR 0007)
      ChannelItem sp c -> (\b -> [ChannelItem sp c {ciBody = b}]) <$> inls (ciBody c)
      Sidenote sp n body -> pure . Sidenote sp n <$> traverseNoteBody inls body
      other -> pure [other]

{- | The notes and the sidenotes numbered again over the range of
'acNoteNumbering', in the order of the documents and of the notes in them
(golem-driver ADR 0018). Footnotes and sidenotes count apart. S0 numbered
both per file.
-}
renumberNotes :: AssembleConfig -> [Document] -> [Document]
renumberNotes cfg docs = evalState (zipWithM doc restarts docs) (0, 0)
  where
    chapters = map Just (acChapterOf cfg) <> repeat Nothing
    restarts = zipWith3 restart [0 :: Int ..] chapters (Nothing : chapters)
    restart i ch prev = case acNoteNumbering cfg of
      NumberPerFile -> True
      NumberPerBook -> i == 0
      NumberPerChapter -> i == 0 || isNothing ch || ch /= prev
    doc fresh (Document fid bs) = do
      when fresh (put (0, 0))
      Document fid <$> mapM blk bs
    blk (Block sp l lang body) =
      Block sp l lang <$> case body of
        Paragraph st is -> Paragraph st <$> inls is
        Heading lv a is -> Heading lv a <$> inls is
        BulletList items -> BulletList <$> mapM item items
        OrderedList items -> OrderedList <$> mapM item items
        DefList gs -> DefList <$> mapM (\(DefGroup ts ds) -> DefGroup <$> mapM inls ts <*> mapM (mapM blk) ds) gs
        TableBlock t -> (\h rows -> TableBlock t {tableHeader = h, tableRows = rows}) <$> mapM inls (tableHeader t) <*> mapM (mapM inls) (tableRows t)
        FigureBlock f -> (\c -> FigureBlock f {figCaption = c}) <$> mapM blk (figCaption f)
        other -> pure other
    item (ListItem n bs) = ListItem n <$> mapM blk bs
    inls = mapM inl
    inl :: Inline -> State (Int, Int) Inline
    inl = \case
      Note sp _ xs -> do
        (n, m) <- get
        put (n + 1, m)
        Note sp (n + 1) <$> traverseNoteBody inls xs
      Sidenote sp _ xs -> do
        (n, m) <- get
        put (n, m + 1)
        Sidenote sp (m + 1) <$> traverseNoteBody inls xs
      Kenten sp s xs -> Kenten sp s <$> inls xs
      Color sp c xs -> Color sp c <$> inls xs
      CharStyle sp c xs -> CharStyle sp c <$> inls xs
      Lang sp t xs -> Lang sp t <$> inls xs
      Resolved sp k l xs -> Resolved sp k l <$> inls xs
      other -> pure other

-- | Give copied inlines the span of the reference that produced them.
relocate :: SrcSpan -> Inline -> Inline
relocate sp = \case
  Text _ t -> Text sp t
  Number _ n s -> Number sp n s
  other -> other

{- | The items of a channel split among its lists (golem-doc ADR 0008): an
item goes to the first list after it, and the items after the last list
to the last list. The blocks are in document order; an item is at the
block that holds it. Without a list, one range without a place.
-}
scopes :: (BlockBody -> Bool) -> (FileId -> Inline -> [a]) -> [Document] -> [(Maybe ListAt, [a])]
scopes isList itemOf docs = close (foldl step ([], []) events)
  where
    events =
      [ ev
      | Document fid bs <- docs,
        Block sp _ _ body <- allBlocks bs,
        ev <- if isList body then [Left (fid, sp)] else map Right (concatMap (itemOf fid) (bodyInlines body))
      ]
    -- the lists so far (reversed) and the items waiting for a list (reversed)
    step (done, pending) = \case
      Left at -> ((Just at, reverse pending) : done, [])
      Right x -> (done, x : pending)
    close (done, pending) = case done of
      [] -> [(Nothing, reverse pending)]
      ((at, xs) : rest) -> reverse ((at, xs <> reverse pending) : rest)

{- | The citations numbered from 1 in each @bibliography, in the order of
first citation in its range, and the list and number of each mark
(golem-doc ADR 0008).
-}
numberCitations :: [Document] -> ([(Maybe ListAt, [(Text, Int)])], Map (FileId, SrcSpan) (Maybe ListAt, Int))
numberCitations docs =
  -- the keys of a mark in the order written (docs/adr/0266)
  let lists = scopes isBibliography (\fid -> \case Cite sp is -> [((fid, sp), citKey i) | i <- is]; _ -> []) docs
      numbered = [(at, zip (dedupe (map snd marks)) [1 ..]) | (at, marks) <- lists]
      -- a mark of several keys: the number of its first key
      marksOf = Map.fromListWith (\_ earlier -> earlier) [(m, (at, n)) | ((at, marks), (_, nums)) <- zip lists numbered, (m, k) <- marks, Just n <- [lookup k nums]]
   in (numbered, marksOf)
  where
    isBibliography = \case
      ChannelOutput BibliographyOutput -> True
      _ -> False
    dedupe = go Set.empty
    go _ [] = []
    go seen (x : xs)
      | x `Set.member` seen = go seen xs
      | otherwise = x : go (Set.insert x seen) xs

{- | Each @channel with the entries of its range (golem-doc ADR 0007): the
items of one channel split among its lists as the items of @index
(golem-doc ADR 0008), made one entry per key, and ordered by the order
the channel declares.
-}
channelLists :: Map Text ChannelDecl -> [Document] -> [(ListAt, Text, [ChannelEntry])]
channelLists decls docs =
  [ (at, name, maybe [] (entriesOf name) (lookup (Just at) (scoped name)))
  | (at, name) <- lists
  ]
  where
    lists = [((fid, sp), n) | Document fid bs <- docs, Block sp _ _ (ChannelOutput (CustomOutput n _)) <- allBlocks bs]
    scoped name =
      scopes
        (\case ChannelOutput (CustomOutput n _) -> n == name; _ -> False)
        (\fid -> \case ChannelItem sp c | ciChannel c == name -> [((fid, sp), c)]; _ -> [])
        docs
    entriesOf name items =
      let order = maybe OrderDocument channelOrder (Map.lookup name decls)
          grouped = groupItems (zip [0 :: Int ..] items)
       in map snd $ case order of
            OrderDocument -> grouped
            OrderReading -> sortOn (\((i, c), _) -> (fmap collationKey (ciReading c), fmap T.unpack (ciKey c), i)) grouped
    -- one entry per key, at its first item; an item without a key is an entry of its own
    groupItems = foldl collect []
    collect acc (i, (loc, c)) = case ciKey c of
      Just k | any (\((_, c0), _) -> ciKey c0 == Just k) acc -> [if ciKey c0 == Just k then (f, e {ceLocations = ceLocations e <> [loc]}) else (f, e) | (f@(_, c0), e) <- acc]
      _ -> acc <> [((i, c), ChannelEntry (ciKey c) (ciBody c) [loc])]

{- | Each @index with the entries of the marks of its range under their
headings (golem-doc ADR 0008, docs/adr/0265), and G04101 to G04104 of the
marks of every range, those of a book without @index included.
-}
indexLists :: [Document] -> ([(ListAt, [IndexSection])], [Diagnostic])
indexLists docs =
  let built = [(at, groupMarks marks) | (at, marks) <- scopes isIndex (\fid -> \case IndexMark sp e -> [((fid, sp), e)]; _ -> []) docs]
   in ([(at, indexSections gs) | (Just at, (gs, _)) <- built], concat [ds | (_, (_, ds)) <- built])
  where
    isIndex = \case
      ChannelOutput IndexOutput -> True
      _ -> False

{- | The entries of every index mark of the documents, whatever list they
belong to: the marks of the pages of G07021 (docs/adr/0265).
-}
indexGroups :: [Document] -> [IndexGroup]
indexGroups docs = fst (groupMarks [((fid, sp), e) | Document fid bs <- docs, Block _ _ _ body <- allBlocks bs, IndexMark sp e <- bodyInlines body])

-- | The entries in order under their headings, a heading for each run of entries of one (docs/adr/0265).
indexSections :: [IndexGroup] -> [IndexSection]
indexSections gs =
  [ IndexSection h (map snd run)
  | run@((h, _) : _) <- groupBy ((==) `on` fst) [(indexHeading (fromMaybe "" (listToMaybe (igReadings g))), g) | g <- gs]
  ]

-- | What the marks of one entry make (docs/adr/0265), before they are put in order.
data Collected = Collected
  { -- | the locators by the place of their first mark
    coLocators :: ![(Int, IndexLocator)],
    -- | the begins not closed yet, the last first
    coOpen :: ![(Int, (FileId, SrcSpan))],
    coUnpairedEnds :: ![(FileId, SrcSpan)],
    -- | each reference with the place of its mark
    coSee :: ![(Int, (FileId, SrcSpan), (SeeKind, [Text]))]
  }

{- | Index marks grouped by their terms and readings, in collation order
(docs/adr/0265): the ends of ranges paired as brackets in document order;
an entry of no locator and no reference (of unpaired ends alone) is left
out. G04101 to G04104 of the marks.
-}
groupMarks :: [((FileId, SrcSpan), IndexEntry)] -> ([IndexGroup], [Diagnostic])
groupMarks marks =
  let collected = Map.toList (foldl collect Map.empty (zip [0 :: Int ..] marks))
      sorted = sortOn (\((ts, rs), _) -> (map collationKey rs, map T.unpack ts)) collected
      kept = [(k, c) | (k, c) <- sorted, not (null (coLocators c)) || not (null (coSee c))]
      terms = [ts | ((ts, _), _) <- kept]
      -- an entry, or a main entry its sub-entries show
      items = Set.fromList (terms <> [[t] | t : _ : _ <- terms])
      rank target = fromMaybe maxBound (listToMaybe [i | (i, ts) <- zip [0 :: Int ..] terms, ts == target || [take 1 ts] == [target] && length target == 1])
      groups =
        [ IndexGroup ts rs (map snd (sortOn fst (coLocators c))) (sortOn (\(k, t) -> (rank t, map T.unpack t, k)) (nub [r | (_, _, r) <- coSee c]))
        | ((ts, rs), c) <- kept
        ]
      unpaired =
        [diagnostic "G04103" Error sp ("索引の範囲の始めに、対になる終わりがありません: " <> T.intercalate "/" ts) | ((ts, _), c) <- sorted, (_, (_, sp)) <- coOpen c]
          <> [diagnostic "G04104" Error sp ("索引の範囲の終わりに、対になる始めがありません: " <> T.intercalate "/" ts) | ((ts, _), c) <- sorted, (_, sp) <- coUnpairedEnds c]
      missing =
        [ diagnostic "G04101" Error sp ("索引の参照先の項目がありません: " <> T.intercalate "/" t)
        | (_, c) <- kept,
          (_, (_, sp), (_, t)) <- coSee c,
          not (Set.member t items)
        ]
   in (groups, unpaired <> missing <> seeCycles kept)
  where
    collect acc (i, (loc, IndexEntry ts rs k)) =
      let c0 = Map.findWithDefault (Collected [] [] [] []) (ts, rs) acc
          c = case k of
            IndexPoint -> c0 {coLocators = coLocators c0 <> [(i, AtMark loc)]}
            IndexRangeBegin -> c0 {coOpen = (i, loc) : coOpen c0}
            IndexRangeEnd -> case coOpen c0 of
              (b, bl) : open -> c0 {coLocators = coLocators c0 <> [(b, Between bl loc)], coOpen = open}
              [] -> c0 {coUnpairedEnds = coUnpairedEnds c0 <> [loc]}
            IndexSee sk target -> c0 {coSee = coSee c0 <> [(i, loc, (sk, target))]}
       in Map.insert (ts, rs) c acc

{- | G04102 (docs/adr/0265): the cycles of the references that read
を見よ between entries without pages, a main entry of sub-entries not
counted; one for each cycle, at the first of its marks in document order.
-}
seeCycles :: [(([Text], [Text]), Collected)] -> [Diagnostic]
seeCycles kept =
  [ diagnostic "G04102" Error sp ("索引の「を見よ」の参照が輪になります: " <> T.intercalate ", " [T.intercalate "/" ts | ((ts, _), _) <- members])
  | CyclicSCC vs <- stronglyConnComp [(v, fst v, [fst w | (_, _, w) <- edgesOf v]) | v <- vertices],
    let members = sortOn (\(k, _) -> position k) vs
        inside = Set.fromList (map fst vs),
    (_, sp) : _ <- [map snd (sortOn fst [(i, loc) | v <- vs, (i, loc, w) <- edgesOf v, Set.member (fst w) inside])]
  ]
  where
    indexed = zip [0 :: Int ..] kept
    position k = fromMaybe maxBound (lookup k [(k', i) | (i, (k', _)) <- indexed])
    mains = Set.fromList [t | ((t : _ : _, _), _) <- kept]
    vertices = [(k, c) | (k@(ts, _), c) <- kept, null (coLocators c), not (isMain ts)]
    isMain = \case
      [t] -> Set.member t mains
      _ -> False
    edgesOf (_, c) =
      [ (i, loc, w)
      | (i, loc, (sk, target)) <- coSee c,
        sk == SeeOnly || sk == SeeAuto,
        w@((ts, _), _) <- vertices,
        ts == target
      ]

{- | The cross references of an entry as written after its pages
(docs/adr/0265): the targets of see in one pair of brackets before those of
see also in another, each once, the levels joined by ：. An automatic
reference is see when the entry has no pages and see also when it has.
-}
indexReferences :: Bool -> [(SeeKind, [Text])] -> Text
indexReferences hasPages sees =
  let only = nub [t | (k, t) <- sees, k == SeeOnly || (k == SeeAuto && not hasPages)]
      also = nub [t | (k, t) <- sees, k == SeeAlso || (k == SeeAuto && hasPages)]
      paren word ts = if null ts then "" else "（" <> T.intercalate "、" (map (T.intercalate "：") ts) <> word <> "）"
   in paren "を見よ" only <> paren "をも見よ" also

-- | Inlines of a block body, descending into inline containers.
bodyInlines :: BlockBody -> [Inline]
bodyInlines body = concatMap flatten $ case body of
  Paragraph _ is -> is
  Heading _ _ is -> is
  DefList gs -> concat (concatMap dgTerms gs)
  TableBlock t -> fromMaybe [] (tableCaption t) <> concat (tableHeader t) <> concat (concat (tableRows t))
  CodeBlock c -> fromMaybe [] (codeCaption c)
  _ -> []
  where
    flatten i =
      i : case i of
        Kenten _ _ xs -> concatMap flatten xs
        Color _ _ xs -> concatMap flatten xs
        CharStyle _ _ xs -> concatMap flatten xs
        Link _ _ xs -> concatMap flatten xs
        Lang _ _ xs -> concatMap flatten xs
        Resolved _ _ _ xs -> concatMap flatten xs
        Note _ _ bs -> concatMap flatten (concat (noteParagraphs bs))
        Sidenote _ _ bs -> concatMap flatten (concat (noteParagraphs bs))
        _ -> []

{- | Inlines in a language span of the language of their block, if it has
one (docs/adr ADR 0187): the title of a heading as it is copied.
-}
inLang :: SrcSpan -> Maybe Text -> [Inline] -> [Inline]
inLang sp = \case
  Just t -> \is -> [Lang sp t is]
  Nothing -> id
