{- | Document assembly, S1 (golem-doc ADR 0002): values that depend on the
whole document. Page numbers (S2) remain as 'Ref' 'RefPage'.
-}
module Golem.Doc.Assemble
  ( AssembleConfig (..),
    NoteNumbering (..),
    DocValues (..),
    Book (..),
    HeadingInfo (..),
    LabelTarget (..),
    TocEntry (..),
    IndexGroup (..),
    assemble,
    headingAnchor,
    inlineText,
  )
where

import Control.Monad (when, zipWithM)
import Control.Monad.State.Strict
import Data.Bifunctor (first)
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Collation
import Golem.Doc.IR
import Golem.Doc.Numerals
import Golem.Syntax

data AssembleConfig = AssembleConfig
  { acHeadingFormats :: !(Map Int Text),
    acFigureFormat :: !Text,
    {- | the line of each @number by the span of the block it numbers,
    where G0407 points; a block not in it is pointed at itself
    -} acNumberSites :: !(Map SrcSpan SrcSpan),
    -- | the range over which notes are numbered (golem-driver ADR 0018)
    acNoteNumbering :: !NoteNumbering,
    {- | the chapter of the manifest (from 0) of each document, in the order
    of the documents; a document past its end is a chapter of its own
    -} acChapterOf :: ![Int],
    -- | [code] number: the format of listing numbers (golem-driver ADR 0023)
    acListingFormat :: !Text
  }

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

data IndexGroup = IndexGroup
  { igTerms :: ![Text],
    igReadings :: ![Text],
    igLocations :: ![(FileId, SrcSpan)]
  }
  deriving stock (Eq, Show)

data Book = Book
  { bookDocs :: ![Document],
    bookHeadings :: !(Map SrcSpan HeadingInfo),
    bookFigures :: !(Map SrcSpan Text),
    -- | the listing number of each code block with a caption (golem-driver ADR 0023)
    bookListings :: !(Map SrcSpan Text),
    bookToc :: ![TocEntry],
    bookTocDepth :: !(Maybe Int),
    bookIndex :: ![IndexGroup],
    bookCitations :: ![(Text, Int)],
    bookLabels :: !(Map Text LabelTarget),
    bookReferenced :: !(Set Text)
  }

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
  Tcy _ t -> t
  Number _ n _ -> T.pack (show n)
  _ -> ""

defaultHeadingFormat :: Int -> Text
defaultHeadingFormat = \case
  1 -> "{n}"
  2 -> "{1}.{n}"
  _ -> "{1}.{2}.{n}"

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
    nsDiags :: ![Diagnostic]
  }

numberDocs :: AssembleConfig -> [Document] -> NumSt
numberDocs cfg docs = execState (mapM_ doc docs) (NumSt [0, 0, 0] Nothing 0 Map.empty Map.empty 0 Map.empty [])
  where
    doc (Document fid bs) = mapM_ (blk fid) bs
    blk fid (Block sp lbl b) = case b of
      Heading l a is -> do
        st <- get
        let cs = nsCounters st
            (cs', nums)
              | haNoNumber a = (cs, Nothing)
              | otherwise =
                  let cur = cs !! (l - 1)
                      n = fromMaybe (cur + 1) (haNumber a)
                      upd = take (l - 1) cs <> [n] <> replicate (3 - l) 0
                   in (upd, Just (take l upd))
            fmt = fromMaybe (defaultHeadingFormat l) (Map.lookup l (acHeadingFormats cfg))
            numText = (\ns -> formatNumber fmt ns (Just (head' ns))) <$> nums
            chapter = if l == 1 then head' <$> nums else nsChapter st
            figureReset = if l == 1 then 0 else nsFigure st
            info = HeadingInfo l nums numText (fromMaybe is (haTocTitle a)) (headingAnchor lbl sp) fid
            -- G0407: @number equal to the number it would get without it (golem-syntax ADR 0002)
            redundant = [redundantNumber cfg sp n | not (haNoNumber a), Just n <- [haNumber a], n == cs !! (l - 1) + 1]
        put
          st
            { nsDiags = nsDiags st <> redundant,
              nsCounters = cs',
              nsChapter = if l == 1 then chapter else nsChapter st,
              nsFigure = figureReset,
              nsListing = if l == 1 then 0 else nsListing st,
              nsHeadings = Map.insert sp info (nsHeadings st)
            }
      FigureBlock f -> do
        st <- get
        let n = nsFigure st + 1
        put st {nsFigure = n, nsFigures = Map.insert sp (nsChapter st, n) (nsFigures st)}
        mapM_ (blk fid) (figCaption f)
      -- a code block with a caption has a listing number (golem-driver ADR 0023)
      CodeBlock Code {codeCaption = Just _} -> do
        st <- get
        let n = nsListing st + 1
        put st {nsListing = n, nsListings = Map.insert sp (nsChapter st, n) (nsListings st)}
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
assemble cfg evalDeferred docs =
  let ns = numberDocs cfg docs
      figureText sp = case Map.lookup sp (nsFigures ns) of
        Just (ch, n) -> Just (formatNumber (acFigureFormat cfg) [n] ch)
        Nothing -> Nothing
      listingText sp = case Map.lookup sp (nsListings ns) of
        Just (ch, n) -> Just (formatNumber (acListingFormat cfg) [n] ch)
        Nothing -> Nothing
      -- G0404 for figures and code blocks (golem-driver ADR 0023)
      outside fmt numbered =
        [ diagnostic "G0404" Error sp "章の外にある図版とコードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります"
        | "{chapter}" `T.isInfixOf` fmt,
          (sp, (Nothing, _)) <- Map.toList numbered
        ]
      figureErrors = outside (acFigureFormat cfg) (nsFigures ns) <> outside (acListingFormat cfg) (nsListings ns)
      (labels, labelDiags) = collectLabels ns docs
      chapterCount = toInteger (length [() | HeadingInfo {hiLevel = 1, hiNumbers = Just _} <- Map.elems (nsHeadings ns)])
      dv = DocValues chapterCount
      (docs', (refd, resolveDiags)) = runState (mapM (resolveDoc labels dv evalDeferred) docs) (Set.empty, [])
      tocs = [(d, sp) | Document _ bs <- docs, Block sp _ (ChannelOutput (TocOutput d)) <- allBlocks bs]
      tocDiags = case tocs of
        ((_, firstToc) : rest) ->
          [ (diagnostic "G0402" Error sp "@toc は文書に一つだけ置けます") {diagRelated = [(firstToc, "最初の @toc")]}
          | (_, sp) <- rest
          ]
        [] -> []
      toc =
        [ TocEntry (hiLevel h) (hiNumberText h) (hiTitle h) (hiAnchor h) (hiFile h) sp
        | Document _ bs <- docs,
          Block sp _ (Heading _ a _) <- allBlocks bs,
          not (haNoToc a),
          Just h <- [Map.lookup sp (nsHeadings ns)]
        ]
      citations = numberCitations docs
   in ( Book
          { bookDocs = renumberNotes cfg docs',
            bookHeadings = nsHeadings ns,
            bookFigures = Map.mapMaybeWithKey (\sp _ -> figureText sp) (nsFigures ns),
            bookListings = Map.mapMaybeWithKey (\sp _ -> listingText sp) (nsListings ns),
            bookToc = toc,
            bookTocDepth = case tocs of
              ((d, _) : _) -> Just d
              [] -> Nothing,
            bookIndex = indexGroups docs,
            bookCitations = citations,
            bookLabels = labels,
            bookReferenced = refd
          },
        sortDiagnostics (nsDiags ns <> figureErrors <> labelDiags <> resolveDiags <> tocDiags <> listNumberNotices cfg docs <> trailingBreaks docs)
      )

-- | G0407 at the @number line of the block (golem-syntax ADR 0002).
redundantNumber :: AssembleConfig -> SrcSpan -> Integer -> Diagnostic
redundantNumber cfg sp n =
  notice "G0407" (Map.findWithDefault sp sp (acNumberSites cfg)) ("@number " <> T.pack (show n) <> " は自動で振られる番号と同じです")

{- | G0407 for the items of numbered lists. An attribute before an item
makes a list of its own, which without the attribute would continue the
list right before it; so a list right after a numbered list counts on from
the last number of that list.
-}
listNumberNotices :: AssembleConfig -> [Document] -> [Diagnostic]
listNumberNotices cfg = concatMap (blocks . docBlocks)
  where
    blocks = snd . foldl step (Nothing, [])
    step (prev, acc) (Block sp _ body) = case body of
      OrderedList items ->
        let start = maybe 1 (+ 1) prev
            nums = numbersFrom start items
            autos = start : map (+ 1) nums
            found =
              [ redundantNumber cfg (if i == 0 then sp else itemSpan sp it) n
              | (i, it, auto) <- zip3 [0 :: Int ..] items autos,
                Just n <- [itemNumber it],
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
    numbersFrom next (ListItem n _ : rest) = let k = fromMaybe next n in k : numbersFrom (k + 1) rest
    itemSpan sp it = case itemBlocks it of
      (Block bsp _ _ : _) -> bsp
      [] -> sp
    lastMaybe = \case
      [] -> Nothing
      xs -> Just (last xs)

{- | G0408 for the page and column breaks at the end of the last file: the
book drops them (golem-syntax ADR 0002). The breaks at the end of another
file act on the next file.
-}
trailingBreaks :: [Document] -> [Diagnostic]
trailingBreaks docs = case reverse docs of
  (Document _ bs : _) ->
    [ notice "G0408" sp "本の最後の改ページは効果がありません"
    | Block sp _ _ <- reverse (takeWhile isBreak (reverse bs))
    ]
  [] -> []
  where
    isBreak b = case blockBody b of
      ForcedBreak _ -> True
      _ -> False

-- | Every block in document order, descending into containers.
allBlocks :: [Block] -> [Block]
allBlocks = concatMap go
  where
    go b@(Block _ _ body) =
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
        Block sp (Just l) body <- allBlocks bs,
        let (num, title) = describe sp body
      ]
    describe sp = \case
      Heading _ _ is -> case Map.lookup sp (nsHeadings ns) of
        Just HeadingInfo {hiNumbers = Just [n], hiTitle = t} -> (Just (Number sp n Nothing), t)
        Just HeadingInfo {hiNumbers = Just nums, hiTitle = t} -> (Just (Text sp (T.intercalate "." (map (T.pack . show) nums))), t)
        Just h -> (Nothing, hiTitle h)
        Nothing -> (Nothing, is)
      FigureBlock f -> case Map.lookup sp (nsFigures ns) of
        Just (ch, n) -> (Just (Text sp (maybe "" (\c -> T.pack (show c) <> "-") ch <> T.pack (show n))), [Text sp (figAlt f)])
        Nothing -> (Nothing, [Text sp (figAlt f)])
      -- the number and the caption of a code block (golem-driver ADR 0023)
      CodeBlock c -> case Map.lookup sp (nsListings ns) of
        Just (ch, n) -> (Just (Text sp (maybe "" (\x -> T.pack (show x) <> "-") ch <> T.pack (show n))), fromMaybe [] (codeCaption c))
        Nothing -> (Nothing, fromMaybe [] (codeCaption c))
      _ -> (Nothing, [])
    add (m, ds) (l, t) = case Map.lookup l m of
      Just prev ->
        ( m,
          ds
            <> [ (diagnostic "G0401" Error (ltSpan t) ("ラベルが重複しています: " <> l))
                   { diagRelated = [(ltSpan prev, "最初の定義")]
                   }
               ]
        )
      Nothing -> (Map.insert l t m, ds)

type R = State (Set Text, [Diagnostic])

resolveDoc :: Map Text LabelTarget -> DocValues -> (DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text) -> Document -> R Document
resolveDoc labels dv evalDeferred (Document fid bs) = Document fid <$> mapM blk bs
  where
    blk (Block sp l body) =
      Block sp l <$> case body of
        Paragraph st is -> Paragraph st <$> inls is
        Heading lv a is -> pure (Heading lv a is)
        BulletList items -> BulletList <$> mapM item items
        OrderedList items -> OrderedList <$> mapM item items
        DefList gs -> DefList <$> mapM (\(DefGroup ts ds) -> DefGroup <$> mapM inls ts <*> mapM (mapM blk) ds) gs
        Table al h rows -> Table al <$> mapM inls h <*> mapM (mapM inls) rows
        FigureBlock f -> (\c -> FigureBlock f {figCaption = c}) <$> mapM blk (figCaption f)
        CodeBlock c -> (\cap -> CodeBlock c {codeCaption = cap}) <$> traverse inls (codeCaption c)
        other -> pure other
    item (ListItem n bs') = ListItem n <$> mapM blk bs'
    inls is = concat <$> mapM inl is
    inl :: Inline -> R [Inline]
    inl = \case
      Ref sp k l -> do
        modify' (first (Set.insert l))
        case (Map.lookup l labels, k) of
          (Nothing, _) -> do
            modify' (\(s, ds) -> (s, ds <> [diagnostic "G0403" Error sp ("存在しないラベルへの参照です: " <> l)]))
            pure []
          (Just t, RefNumber) -> case ltNumber t of
            Just n -> pure [relocate sp n]
            Nothing -> do
              modify' (\(s, ds) -> (s, ds <> [diagnostic "G0405" Error sp ("番号を持たない要素への参照です: " <> l)]))
              pure []
          (Just t, RefTitle) -> case ltTitle t of
            [] -> do
              modify' (\(s, ds) -> (s, ds <> [diagnostic "G0406" Error sp ("題を持たない要素への参照です: " <> l)]))
              pure []
            title -> pure (map (relocate sp) title)
          (Just _, RefPage) -> pure [Ref sp k l]
      Deferred sp e -> case evalDeferred dv sp e of
        Left d -> modify' (\(s, ds) -> (s, ds <> [d])) >> pure []
        Right t -> pure [Text sp t]
      Kenten sp s xs -> pure . Kenten sp s <$> inls xs
      Color sp c xs -> pure . Color sp c <$> inls xs
      CharStyle sp c xs -> pure . CharStyle sp c <$> inls xs
      Note sp n xs -> pure . Note sp n <$> inls xs
      Sidenote sp n xs -> pure . Sidenote sp n <$> inls xs
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
    blk (Block sp l body) =
      Block sp l <$> case body of
        Paragraph st is -> Paragraph st <$> inls is
        Heading lv a is -> Heading lv a <$> inls is
        BulletList items -> BulletList <$> mapM item items
        OrderedList items -> OrderedList <$> mapM item items
        DefList gs -> DefList <$> mapM (\(DefGroup ts ds) -> DefGroup <$> mapM inls ts <*> mapM (mapM blk) ds) gs
        Table al h rows -> Table al <$> mapM inls h <*> mapM (mapM inls) rows
        FigureBlock f -> (\c -> FigureBlock f {figCaption = c}) <$> mapM blk (figCaption f)
        other -> pure other
    item (ListItem n bs) = ListItem n <$> mapM blk bs
    inls = mapM inl
    inl :: Inline -> State (Int, Int) Inline
    inl = \case
      Note sp _ xs -> do
        (n, m) <- get
        put (n + 1, m)
        Note sp (n + 1) <$> inls xs
      Sidenote sp _ xs -> do
        (n, m) <- get
        put (n, m + 1)
        Sidenote sp (m + 1) <$> inls xs
      Kenten sp s xs -> Kenten sp s <$> inls xs
      Color sp c xs -> Color sp c <$> inls xs
      CharStyle sp c xs -> CharStyle sp c <$> inls xs
      other -> pure other

-- | Give copied inlines the span of the reference that produced them.
relocate :: SrcSpan -> Inline -> Inline
relocate sp = \case
  Text _ t -> Text sp t
  Number _ n s -> Number sp n s
  other -> other

numberCitations :: [Document] -> [(Text, Int)]
numberCitations docs = zip (dedupe [k | Document _ bs <- docs, Block _ _ body <- allBlocks bs, Cite _ k <- bodyInlines body]) [1 ..]
  where
    dedupe = go Set.empty
    go _ [] = []
    go seen (x : xs)
      | x `Set.member` seen = go seen xs
      | otherwise = x : go (Set.insert x seen) xs

indexGroups :: [Document] -> [IndexGroup]
indexGroups docs =
  let marks = [((ieTerms e, ieReadings e), (fid, sp)) | Document fid bs <- docs, Block _ _ body <- allBlocks bs, IndexMark sp e <- bodyInlines body]
      grouped = Map.toList (Map.fromListWith (flip (<>)) [(k, [loc]) | (k, loc) <- marks])
      sorted = sortOn (\((ts, rs), _) -> (map collationKey rs, map T.unpack ts)) grouped
   in [IndexGroup ts rs locs | ((ts, rs), locs) <- sorted]

-- | Inlines of a block body, descending into inline containers.
bodyInlines :: BlockBody -> [Inline]
bodyInlines body = concatMap flatten $ case body of
  Paragraph _ is -> is
  Heading _ _ is -> is
  DefList gs -> concat (concatMap dgTerms gs)
  Table _ h rows -> concat h <> concat (concat rows)
  CodeBlock c -> fromMaybe [] (codeCaption c)
  _ -> []
  where
    flatten i =
      i : case i of
        Kenten _ _ xs -> concatMap flatten xs
        Color _ _ xs -> concatMap flatten xs
        CharStyle _ _ xs -> concatMap flatten xs
        Note _ _ xs -> concatMap flatten xs
        Sidenote _ _ xs -> concatMap flatten xs
        _ -> []
