{- | Plain-text output, vertical and horizontal variants
(golem-text ADR 0001).
-}
module Golem.Text
  ( TextVariant (..),
    TextLists (..),
    renderText,
  )
where

import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Assemble.ListMarkers
import Golem.Assemble.Numbering (numberSeparator)
import Golem.Bibliography (EntryPart, entryText)
import Golem.Doc.Citation (citationPieces, citationText)
import Golem.Doc.IR
import Golem.Numerals
import Golem.Syntax.Span
import System.FilePath (replaceExtension)

data TextVariant = Vertical | Horizontal
  deriving stock (Eq, Show)

{- | Number notation: kanji in vertical text (tate-chu-yoko does not exist
in plain text), arabic in horizontal text.
-}
renderNumber :: TextVariant -> Text -> Integer -> Maybe NumberStyle -> Text
renderNumber Horizontal _ n _ = T.pack (show n)
renderNumber Vertical def n st = case fromMaybe (verticalStyleOf (verticalNumbersNamed def) n) st of
  StyleKanjiDigits -> kanjiDigits n
  _ -> kanji n

data Ctx = Ctx
  { cVariant :: TextVariant,
    -- | the language of the book, for the separator after a number (golem-html ADR 0002)
    cLanguage :: Text,
    cNumberDefault :: Text,
    cBook :: Book,
    cProfileDev :: Bool,
    -- | the ideographic spaces before the first line of a paragraph of a style, and after a line break (docs/adr ADR 0006, 0049)
    cFirstLine :: Maybe Text -> (Int, Int),
    -- | inside a list item, where paragraphs are not indented
    cInList :: Bool,
    -- | the markers of [lists] (golem-driver ADR 0013)
    cLists :: TextLists,
    -- | the formatted entries of the bibliography by key (golem-doc ADR 0004, 0005)
    cBibliography :: Map Text [EntryPart],
    -- | the depth of the list around (0 outside lists)
    cDepth :: Int,
    -- | whether the captions of tables are after them, [tables] caption-position (docs/adr/0262)
    cTableCaptionBelow :: Bool
  }

{- | The markers of [lists] (golem-driver ADR 0013): the bullets and the
number formats by depth (Nothing: the numbers of a book without them),
and whether a gap is written (Nothing: by the last character).
-}
data TextLists = TextLists
  { tlBullets :: NonEmpty Text,
    tlNumbers :: Maybe (NonEmpty NumberFormat),
    tlGap :: Maybe Bool
  }

{- | One text file per source file, named after the source with a .txt
extension. @firstLine@ gives, for a file, the ideographic spaces that
start the first line of a paragraph of a style and the lines after a
line break (Nothing is body; docs/adr ADR 0006, 0014, 0049). The notes of a chapter of the manifest follow its last file,
after a title (golem-driver ADR 0026). @captionBelow@ puts the captions of
tables after them (docs/adr/0262).
-}
renderText :: Text -> Text -> Bool -> (FileId -> Maybe Text -> (Int, Int)) -> TextLists -> Bool -> Map Text [EntryPart] -> TextVariant -> FileTable -> Book -> [(FilePath, Text)]
renderText lang numberDefault dev firstLine lists captionBelow bib variant ft book =
  [ (replaceExtension (fromMaybe "unknown" (lookupPath fid ft)) "txt", file (ctxOf fid) d (if isLast then chapter else []))
  | chapter <- bookChapters book,
    (isLast, d@(Document fid _)) <- zip (map (== length chapter) [1 ..]) chapter
  ]
  where
    ctxOf fid = Ctx variant lang numberDefault book dev (firstLine fid) False lists bib 0 captionBelow

{- | The blocks of a file, an empty line between two; blank lines add
their empty lines between two blocks, and nothing before the first
block, after a break or after the last block (docs/adr ADR 0046).
-}
topText :: Ctx -> [Block] -> Text
topText c = T.concat . go False Nothing
  where
    -- whether a block was written, and the empty lines pending after a block (Nothing after a break)
    go _ _ [] = []
    go written _ (Block _ _ _ (ForcedBreak _) : rest) = go written Nothing rest
    go written blanks (Block _ _ _ (BlankLines n) : rest) = go written ((+ toInteger n) <$> blanks) rest
    go written blanks (b : rest) =
      let t = block c 0 b
          sep = if written then "\n\n" <> T.replicate (fromInteger (fromMaybe 0 blanks)) "\n" else ""
       in if T.null t then go written blanks rest else sep : t : go True (Just 0) rest

-- | A file and, after it, the notes of the documents of its chapter.
file :: Ctx -> Document -> [Document] -> Text
file c (Document _ bs) chapter =
  let body = topText c bs
      notes = [(n, noteParagraphs nb) | Document _ cbs <- chapter, Note _ n nb <- concatMap blockInlines cbs]
      noteMark n = (if cVariant c == Vertical then "※" else "*") <> T.pack (show n)
      -- the first paragraph after the mark, each other on a line of its own (docs/adr/0263)
      noteText = T.intercalate "\n" (notesTitle (cLanguage c) : [noteMark n <> " " <> T.intercalate "\n" (map (inlines c) ps) | (n, ps) <- notes])
      full
        | null notes = body
        | T.null body = noteText
        | otherwise = body <> "\n\n" <> noteText
   in if T.null full then "" else full <> "\n"

indentBy :: Int -> Text
indentBy n = T.replicate n "　"

block :: Ctx -> Int -> Block -> Text
block c ind (Block sp _ _ body) = case body of
  -- a line break is a newline and the nesting indent (docs/adr ADR 0005); the first line starts
  -- with the first indent, each line after a line break with the second (docs/adr ADR 0006, 0049)
  Paragraph st is ->
    let (first, rest) = if cInList c then (0, 0) else cFirstLine c st
        lead n = indentBy ind <> indentBy n
     in lead first <> T.intercalate ("\n" <> lead rest) (map (inlines c) (splitAtLineBreaks is)) <> sidenotes is
  Heading _ _ is ->
    let num = Map.lookup sp (bookHeadings (cBook c)) >>= hiNumberText
     in numbered num <> inlines c is
  BulletList items -> T.intercalate "\n" [indentBy ind <> spaced (atDepth (tlBullets (cLists c)) depth) <> itemText (ind + 1) it | it <- items]
  OrderedList items ->
    T.intercalate "\n" [indentBy ind <> marker n <> itemText (ind + 1) it | (n, it) <- zip (itemNumbers items) items]
  DefList gs ->
    T.intercalate
      "\n"
      [ T.intercalate "\n" (map ((indentBy ind <>) . inlines c) ts <> [T.intercalate "\n" (map (block c (ind + 1)) d) | d <- ds])
      | DefGroup ts ds <- gs
      ]
  -- the caption a line before or after the rows, as that of a code block (docs/adr/0262)
  TableBlock t ->
    let caption = [numbered (Map.lookup sp (bookTables (cBook c))) <> inlines c is | Just is <- [tableCaption t]]
        rows = map (T.intercalate "\t" . map (inlines c)) (tableHeader t : tableRows t)
     in T.intercalate "\n" (if cTableCaptionBelow c then rows <> caption else caption <> rows)
  -- the caption, the file name, the diff marks and the callouts (golem-driver ADR 0023)
  CodeBlock code ->
    let num = Map.lookup sp (bookListings (cBook c))
        -- the separator of the language (golem-driver ADR 0042)
        caption = [numbered num <> inlines c is | Just is <- [codeCaption code]]
        mark l = case clDiff l of
          Just DiffAdded -> "+"
          Just DiffRemoved -> "-"
          Just DiffContext -> " "
          Nothing -> ""
        line l = mark l <> clText l <> T.concat [" " <> circled n | n <- clCallouts l]
     in T.intercalate "\n" (caption <> maybe [] pure (codeFile code) <> map line (codeLines code))
  FigureBlock f ->
    let num = Map.lookup sp (bookFigures (cBook c))
        cap = T.intercalate "" [inlines c is | Block _ _ _ (Paragraph _ is) <- figCaption f]
        line = T.strip (numbered num <> cap)
     in -- no line without a number and a caption (docs/adr/0200)
        if T.null line then "" else "［" <> line <> "］"
  ChannelOutput (TocOutput d) ->
    T.intercalate "\n" [numbered (teNumber e) <> inlines c (teTitle e) | e <- bookToc (cBook c), teLevel e <= d]
  ChannelOutput IndexOutput -> ""
  -- the body of each entry of a channel of a plugin on a line (golem-doc ADR 0007)
  ChannelOutput (CustomOutput _ _) -> T.intercalate "\n" [inlines c (ceBody e) | e <- channelAt (cBook c) sp]
  -- plain text has no pages (docs/adr ADR 0017)
  ForcedBreak _ -> ""
  PageControl _ -> ""
  -- placed by topText (docs/adr ADR 0046)
  BlankLines _ -> ""
  ChannelOutput BibliographyOutput ->
    -- the entry, or the key that has none (golem-doc ADR 0004, 0005)
    T.intercalate "\n" ["[" <> T.pack (show n) <> "] " <> maybe k entryText (Map.lookup k (cBibliography c)) | (k, n) <- bibliographyAt (cBook c) sp]
  where
    -- a number and the separator of the language (golem-html ADR 0002)
    numbered = maybe "" (\n -> n <> numberSeparator (cLanguage c) n)
    -- the markers of [lists] by depth; without numbers, those of a book without [lists] (golem-driver ADR 0013)
    depth = cDepth c + 1
    marker n = case tlNumbers (cLists c) of
      Nothing -> if cVariant c == Vertical then kanji n <> "、" else T.pack (show n) <> ". "
      Just fmts ->
        let NumberFormat pre st suf = atDepth fmts depth
            num = case st of
              NsBook -> renderNumber (cVariant c) (cNumberDefault c) n Nothing
              _ -> fromMaybe (T.pack (show n)) (formatListNumber st n)
         in spaced (pre <> num <> suf)
    spaced m =
      let gap = fromMaybe (not (endsWithSpacedPunctuation m)) (tlGap (cLists c))
       in if gap then m <> (if cVariant c == Vertical then "　" else " ") else m
    inItem = c {cInList = True, cDepth = depth}
    itemText i (ListItem _ bs) = case bs of
      (Block _ _ _ (Paragraph Nothing is) : rest) | not (any isLineBreak is) -> T.intercalate "\n" (inlines c is : map (block inItem i) rest)
      _ -> T.intercalate "\n" (map (block inItem i) bs)
    sidenotes is =
      T.concat ["\n※" <> T.pack (show n) <> " " <> T.intercalate "\n" (map (inlines c) (noteParagraphs nb)) | Sidenote _ n nb <- is]

blockInlines :: Block -> [Inline]
blockInlines (Block _ _ _ body) = case body of
  Paragraph _ is -> deep is
  Heading _ _ is -> deep is
  BulletList items -> concatMap (concatMap blockInlines . itemBlocks) items
  OrderedList items -> concatMap (concatMap blockInlines . itemBlocks) items
  DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap deep ts <> concatMap (concatMap blockInlines) ds) gs
  TableBlock t -> concatMap deep (tableHeader t) <> concatMap (concatMap deep) (tableRows t)
  FigureBlock f -> concatMap blockInlines (figCaption f)
  _ -> []
  where
    deep = concatMap (\i -> i : nested i)
    nested = \case
      Kenten _ _ xs -> deep xs
      Color _ _ xs -> deep xs
      CharStyle _ _ xs -> deep xs
      Link _ _ xs -> deep xs
      Lang _ _ xs -> deep xs
      Resolved _ _ _ xs -> deep xs
      _ -> []

inlines :: Ctx -> [InlineF r] -> Text
inlines c = T.concat . map (inline c)

inline :: Ctx -> InlineF r -> Text
inline c = \case
  Text _ t -> t
  Ruby _ _ segs -> ruby c segs
  Kenten _ _ xs -> inlines c xs
  Color _ _ xs -> inlines c xs
  CharStyle _ _ xs -> inlines c xs
  Tcy _ t -> t
  Number _ n st -> renderNumber (cVariant c) (cNumberDefault c) n st
  Ref _ RefPage l -> case Map.lookup l (bookLabels (cBook c)) of
    Just t -> "「" <> inlines c (ltTitle t) <> "」"
    Nothing -> ""
  Ref {} -> ""
  Deferred {} -> ""
  Note _ n _ -> (if cVariant c == Vertical then "※" else "*") <> T.pack (show n)
  Sidenote _ n _ -> "※" <> T.pack (show n)
  IndexMark {} -> ""
  ChannelItem {} -> ""
  -- the mark of the default style; nothing when a number is not known (docs/adr/0266)
  Cite sp is -> case traverse (\i -> (,) i . Just <$> citeNumber (cBook c) sp (citKey i)) is of
    Just ns -> citationText (citationPieces ns)
    Nothing -> ""
  ProofComment _ t -> if cProfileDev c then "【校正：" <> t <> "】" else ""
  LineBreak _ -> "\n"
  -- the whole part of an amount in zw as ideographic spaces; less than one, and absolute amounts, are nothing (docs/adr ADR 0019)
  Aki _ (AkiZw r) -> T.replicate (fromInteger (max 0 (floor r))) "\x3000"
  Aki _ (AkiAbs _) -> ""
  -- the text and the URL in full-width parentheses, as ruby; the URL alone when it is the text (docs/adr ADR 0182)
  Link _ u xs ->
    let t = inlines c xs
     in if t == u then u else t <> "（" <> u <> "）"
  -- the characters of a language span as they are (docs/adr ADR 0187)
  Lang _ _ xs -> inlines c xs
  -- the text the reference resolved to (docs/adr/0215)
  Resolved _ _ _ xs -> inlines c xs

{- | Ruby as 「対象（読み）」. Consecutive segments with readings are joined;
segments without a reading are written as they are.
-}
ruby :: Ctx -> [RubySegment] -> Text
ruby c = go
  where
    go [] = ""
    go segs@(RubySegment _ (Just _) : _) =
      let (withR, rest) = span (\(RubySegment _ r) -> isJust r) segs
       in T.concat [inlines c b | RubySegment b _ <- withR] <> "（" <> T.concat [r | RubySegment _ (Just r) <- withR] <> "）" <> go rest
    go (RubySegment b Nothing : rest) = inlines c b <> go rest
