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
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Assemble.ListMarkers
import Golem.Assemble.Numbering (numberedTitleText)
import Golem.Bibliography (EntryPart, entryText)
import Golem.Doc.Citation (citationText)
import Golem.Doc.IR
import Golem.Numerals
import Golem.Numerals.Number (renderIRNumber)
import Golem.Syntax.Span
import System.FilePath (replaceExtension)

data TextVariant = Vertical | Horizontal
  deriving stock (Eq, Show)

{- | Number notation: kanji in vertical text (tate-chu-yoko does not exist
in plain text), arabic in horizontal text.
-}
renderNumber :: TextVariant -> Text -> Rational -> Maybe NumberStyle -> Text
renderNumber _ _ q _ | denominator q /= 1 = renderIRNumber q
renderNumber Horizontal _ n _ = renderIRNumber n
renderNumber Vertical def n st = case fromMaybe (verticalStyleOf (verticalNumbersNamed def) (numerator n)) st of
  StyleKanjiDigits -> kanjiDigits (numerator n)
  _ -> kanji (numerator n)

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
topText c = T.concat . go False Nothing Nothing
  where
    -- whether a block was written, explicit blank lines, and a visible separator's trailing space
    go _ _ _ [] = []
    go written _ _ (Block _ _ _ (ForcedBreak _) : rest) = go written Nothing Nothing rest
    go written blanks after (Block _ _ _ (BlankLines n) : rest) = go written ((+ toInteger n) <$> blanks) after rest
    go written blanks after (b@(Block sp _ _ (Separator name)) : rest) =
      let appearance = Map.lookup (sp, name) (bookSeparators (cBook c))
          before = case appearance of
            Just (SeparatorTextAppearance n _ _ _ _) -> n
            Just (SeparatorRuleAppearance n _ _ _ _ _ _) -> n
            Nothing -> 0
          trailing = case appearance of
            Just (SeparatorTextAppearance _ n _ _ _) -> n
            Just (SeparatorRuleAppearance _ n _ _ _ _ _) -> n
            Nothing -> 0
          gap = max (toInteger before) (max (fromMaybe 0 blanks) (fromMaybe 0 after))
          sep = if written then "\n" <> T.replicate (fromInteger gap) "\n" else ""
       in sep : block c 0 b : go True (Just 0) (Just (toInteger trailing)) rest
    go written blanks after (b : rest) =
      let t = block c 0 b
          sep =
            if written
              then case after of
                Just n -> "\n" <> T.replicate (fromInteger (max n (fromMaybe 0 blanks))) "\n"
                Nothing -> "\n\n" <> T.replicate (fromInteger (fromMaybe 0 blanks)) "\n"
              else ""
       in if T.null t then go written blanks after rest else sep : t : go True (Just 0) Nothing rest

-- | A file and, after it, the notes of the documents of its chapter.
file :: Ctx -> Document -> [Document] -> Text
file c (Document _ bs) chapter =
  let body = topText c bs
      notes = [(n, paragraphs) | d <- chapter, (_, n, paragraphs) <- documentNotes d]
      noteMark n = (if cVariant c == Vertical then "※" else "*") <> T.pack (show n)
      -- the first paragraph after the mark, each other on a line of its own (docs/adr/0263)
      listText title ns = T.intercalate "\n" (title : [noteMark n <> " " <> T.intercalate "\n" (map (inlines c) ps) | (n, ps) <- ns])
      -- the endnotes after the notes, under a title of their own (root ADR 0412)
      endnotes = [(n, paragraphs) | d <- chapter, (_, n, paragraphs) <- documentEndnotes d]
      lists = [listText (notesTitle (cLanguage c)) notes | not (null notes)] <> [listText (endnotesTitle (cLanguage c)) endnotes | not (null endnotes)]
      noteText = T.intercalate "\n\n" lists
      full
        | null lists = body
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
    let (first, rest) = if cInList c then (0, 0) else cFirstLine c (styleRefNameOf st)
        lead n = indentBy ind <> indentBy n
     in lead first <> T.intercalate ("\n" <> lead rest) (map (inlines c) (splitAtLineBreaks is)) <> sidenotes is
  Heading l _ is ->
    let num = Map.lookup sp (bookHeadings (cBook c)) >>= hiNumberText
     in numbered sp (Just l) (inlines c is) num
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
    let caption = [numbered sp Nothing (inlines c is) (Map.lookup sp (bookTables (cBook c))) | Just is <- [tableCaption t]]
        rows = map (T.intercalate "\t" . map (inlines c)) (tableHeader t : tableRows t)
     in T.intercalate "\n" (if cTableCaptionBelow c then rows <> caption else caption <> rows) <> sidenotes (fromMaybe [] (tableCaption t) <> concat (tableHeader t) <> concat (concat (tableRows t)))
  -- the caption, the file name, the diff marks and the callouts (golem-driver ADR 0023)
  CodeBlock code ->
    let num = Map.lookup sp (bookListings (cBook c))
        -- the separator of the language (golem-driver ADR 0042)
        caption = [numbered sp Nothing (inlines c is) num | Just is <- [codeCaption code]]
        mark l = case clDiff l of
          Just DiffAdded -> "+"
          Just DiffRemoved -> "-"
          Just DiffContext -> " "
          Nothing -> ""
        line l = mark l <> clText l <> T.concat [" " <> circled n | n <- clCallouts l]
     in T.intercalate "\n" (caption <> maybe [] pure (codeFile code) <> map line (codeLines code)) <> sidenotes (fromMaybe [] (codeCaption code))
  FigureBlock f ->
    let num = Map.lookup sp (bookFigures (cBook c))
        cap = T.intercalate "" [inlines c is | Block _ _ _ (Paragraph _ is) <- figCaption f]
        line = T.strip (numbered sp Nothing cap num)
     in -- no line without a number and a caption (docs/adr/0200)
        if T.null line then "" else "［" <> line <> "］"
  ChannelOutput (TocOutput d) ->
    T.intercalate "\n" [numbered (teSpan e) (Just (teLevel e)) (inlines c (teTitle e)) (teNumber e) | e <- bookToc (cBook c), teLevel e <= d]
  ChannelOutput IndexOutput -> ""
  -- the body of each entry of a channel of a plugin on a line (golem-doc ADR 0007)
  ChannelOutput (CustomOutput _ _) -> T.intercalate "\n" [inlines c (ceBody e) | e <- channelAt (cBook c) sp]
  -- plain text has no pages (docs/adr ADR 0017)
  ForcedBreak _ -> ""
  PageControl _ -> ""
  -- placed by topText (docs/adr ADR 0046)
  BlankLines _ -> ""
  Separator name -> case Map.lookup (sp, name) (bookSeparators (cBook c)) of
    Just (SeparatorTextAppearance _ _ _ content _) -> content
    Just SeparatorRuleAppearance {} -> "---"
    Nothing -> ""
  -- the paragraphs of a text frame at the place of the command, an empty line between two (root ADR 0438)
  FrameBlock _ bs -> T.intercalate "\n\n" (filter (not . T.null) (map (block c ind) bs))
  ChannelOutput BibliographyOutput ->
    -- the entry, or the key that has none (golem-doc ADR 0004, 0005)
    T.intercalate "\n" ["[" <> T.pack (show n) <> "] " <> maybe k entryText (Map.lookup k (bibliographyEntriesFor (cBook c) (Just (spanFile sp, sp)) (cBibliography c))) | (k, n) <- bibliographyAt (cBook c) sp]
  where
    -- a title with its number and the separator of the language (golem-html ADR 0002), or by the format of its level (root ADR 0463)
    numbered site level title = maybe title (\n -> let key = (spanFile site, level) in numberedTitleText (cLanguage c) (Map.lookup key (bookTitleSeparators (cBook c))) (Map.lookup key (bookTitleFormats (cBook c))) n title)
    -- the markers of [lists] by depth; without numbers, those of a book without [lists] (golem-driver ADR 0013)
    depth = cDepth c + 1
    marker n = case tlNumbers (cLists c) of
      Nothing -> if cVariant c == Vertical then kanji n <> "、" else T.pack (show n) <> ". "
      Just fmts ->
        let NumberFormat pre st suf = atDepth fmts depth
            num = case st of
              NsBook -> renderNumber (cVariant c) (cNumberDefault c) (fromInteger n) Nothing
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
      T.concat ["\n※" <> T.pack (show n) <> " " <> T.intercalate "\n" (map (inlines c) (noteParagraphs nb)) | (_, _, n, nb) <- inlineSidenotes is]

inlines :: Ctx -> [InlineF r] -> Text
inlines c = T.concat . map (inline c)

inline :: Ctx -> InlineF r -> Text
inline c = \case
  Text _ t -> t
  Ruby _ _ segs -> ruby c segs
  Kenten _ _ xs -> inlines c xs
  Color _ _ xs -> inlines c xs
  CharStyle _ _ xs -> inlines c xs
  Tcy _ (TcyLiteral t) -> t
  Tcy _ (TcyNumber q) -> renderNumber (cVariant c) (cNumberDefault c) q (Just StyleTcy)
  Warichu _ t -> t
  Upright _ t -> t
  Number _ n st -> renderNumber (cVariant c) (cNumberDefault c) n st
  Ref _ RefPage l -> case Map.lookup l (bookLabels (cBook c)) of
    -- a note has no title: its number, as [ref-number] gives it (root ADR 0422)
    Just t@LabelTarget {ltNote = Just _} -> inlines c (maybe [] pure (ltNumber t))
    Just t -> "「" <> inlines c (ltTitle t) <> "」"
    Nothing -> ""
  Ref {} -> ""
  Deferred {} -> ""
  Note _ n _ _ -> (if cVariant c == Vertical then "※" else "*") <> T.pack (show n)
  Sidenote _ n _ _ -> "※" <> T.pack (show n)
  -- the mark of an endnote is that of a note (root ADR 0412)
  Endnote _ n _ _ -> (if cVariant c == Vertical then "※" else "*") <> T.pack (show n)
  IndexMark {} -> ""
  ChannelItem {} -> ""
  -- the mark of the default style; nothing when a number is not known (docs/adr/0266)
  Cite sp is -> case traverse (\i -> (,) i . Just <$> citeNumber (cBook c) sp (citKey i)) is of
    Just ns -> citationText (citationPiecesFor (cBook c) sp ns)
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
ruby c segs
  | any (isJust . rsOtherReading) segs =
      T.concat [inlines c (rsBase seg) <> maybe "" (\t -> "（" <> t <> "）") (rsReading seg) <> maybe "" (\t -> "（" <> t <> "）") (rsOtherReading seg) | seg <- segs]
ruby c segments = go segments
  where
    go [] = ""
    go segs@(RubySegment _ (Just _) : _) =
      let (withR, rest) = span (\(RubySegment _ r) -> isJust r) segs
       in T.concat [inlines c b | RubySegment b _ <- withR] <> "（" <> T.concat [r | RubySegment _ (Just r) <- withR] <> "）" <> go rest
    go (RubySegment b Nothing : rest) = inlines c b <> go rest
