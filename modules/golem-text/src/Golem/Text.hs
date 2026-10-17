{- | Plain-text output, vertical and horizontal variants
(golem-text ADR 0001).
-}
module Golem.Text
  ( TextVariant (..),
    TextLists (..),
    renderText,
    renderNumber,
  )
where

import Data.List.NonEmpty (NonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (EntryPart, entryText)
import Golem.Doc.IR
import Golem.Doc.ListMarkers
import Golem.Doc.Numbering (numberSeparator)
import Golem.Doc.Numerals
import Golem.Syntax.Span
import System.FilePath (replaceExtension)

data TextVariant = Vertical | Horizontal
  deriving stock (Eq, Show)

{- | Number notation: kanji in vertical text (tate-chu-yoko does not exist
in plain text), arabic in horizontal text.
-}
renderNumber :: TextVariant -> Text -> Integer -> Maybe NumberStyle -> Text
renderNumber Horizontal _ n _ = T.pack (show n)
renderNumber Vertical def n st = case fromMaybe (styleOf def) st of
  StyleKanjiDigits -> kanjiDigits n
  _ -> kanji n
  where
    styleOf = \case
      "kanji-digits" -> StyleKanjiDigits
      "tcy" -> StyleTcy
      _ -> StyleKanji

data Ctx = Ctx
  { cVariant :: TextVariant,
    -- | the language of the book, for the separator after a number (golem-html ADR 0002)
    cLanguage :: Text,
    cNumberDefault :: Text,
    cBook :: Book,
    cProfileDev :: Bool,
    -- | the ideographic spaces before the first line of a paragraph of a style (docs/adr ADR 0006)
    cFirstLine :: Maybe Text -> Int,
    -- | inside a list item, where paragraphs are not indented
    cInList :: Bool,
    -- | the markers of [lists] (golem-driver ADR 0013)
    cLists :: TextLists,
    -- | the formatted entries of the bibliography by key (golem-doc ADR 0004, 0005)
    cBibliography :: Map Text [EntryPart],
    -- | the depth of the list around (0 outside lists)
    cDepth :: Int
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
start the lines of a paragraph of a style (Nothing is body; docs/adr ADR
0006, 0014). The notes of a chapter of the manifest follow its last file,
after a title (golem-driver ADR 0026).
-}
renderText :: Text -> Text -> Bool -> (FileId -> Maybe Text -> Int) -> TextLists -> Map Text [EntryPart] -> TextVariant -> FileTable -> Book -> [(FilePath, Text)]
renderText lang numberDefault dev firstLine lists bib variant ft book =
  [ (replaceExtension (fromMaybe "unknown" (lookupPath fid ft)) "txt", file (ctxOf fid) d (if isLast then chapter else []))
  | chapter <- bookChapters book,
    (isLast, d@(Document fid _)) <- zip (map (== length chapter) [1 ..]) chapter
  ]
  where
    ctxOf fid = Ctx variant lang numberDefault book dev (firstLine fid) False lists bib 0

-- | A file and, after it, the notes of the documents of its chapter.
file :: Ctx -> Document -> [Document] -> Text
file c (Document _ bs) chapter =
  let body = T.intercalate "\n\n" (filter (not . T.null) (map (block c 0) bs))
      notes = [(n, xs) | Document _ cbs <- chapter, Note _ n xs <- concatMap blockInlines cbs]
      noteMark n = (if cVariant c == Vertical then "※" else "*") <> T.pack (show n)
      noteText = T.intercalate "\n" (notesTitle (cLanguage c) : [noteMark n <> " " <> inlines c xs | (n, xs) <- notes])
      full
        | null notes = body
        | T.null body = noteText
        | otherwise = body <> "\n\n" <> noteText
   in if T.null full then "" else full <> "\n"

indentBy :: Int -> Text
indentBy n = T.replicate n "　"

block :: Ctx -> Int -> Block -> Text
block c ind (Block sp _ body) = case body of
  -- a line break is a newline and the nesting indent (docs/adr ADR 0005); each line starts with the first-line indent (docs/adr ADR 0006)
  Paragraph st is ->
    let lead = indentBy ind <> (if cInList c then "" else indentBy (cFirstLine c st))
     in lead <> T.intercalate ("\n" <> lead) (map (inlines c) (splitLines is)) <> sidenotes is
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
  Table _ h rows -> T.intercalate "\n" (map (T.intercalate "\t" . map (inlines c)) (h : rows))
  -- the caption, the file name, the diff marks and the callouts (golem-driver ADR 0023)
  CodeBlock code ->
    let num = Map.lookup sp (bookListings (cBook c))
        caption = [maybe "" (<> "　") num <> inlines c is | Just is <- [codeCaption code]]
        mark l = case clDiff l of
          Just DiffAdded -> "+"
          Just DiffRemoved -> "-"
          Just DiffContext -> " "
          Nothing -> ""
        line l = mark l <> clText l <> T.concat [" " <> circled n | n <- clCallouts l]
     in T.intercalate "\n" (caption <> maybe [] pure (codeFile code) <> map line (codeLines code))
  FigureBlock f ->
    let num = Map.lookup sp (bookFigures (cBook c))
        cap = T.intercalate "" [inlines c is | Block _ _ (Paragraph _ is) <- figCaption f]
     in "［" <> T.strip (numbered num <> cap) <> "］"
  ChannelOutput (TocOutput d) ->
    T.intercalate "\n" [numbered (teNumber e) <> inlines c (teTitle e) | e <- bookToc (cBook c), teLevel e <= d]
  ChannelOutput IndexOutput -> ""
  -- plain text has no pages (docs/adr ADR 0017)
  ForcedBreak _ -> ""
  ChannelOutput BibliographyOutput ->
    -- the entry, or the key that has none (golem-doc ADR 0004, 0005)
    T.intercalate "\n" ["[" <> T.pack (show n) <> "] " <> maybe k entryText (Map.lookup k (cBibliography c)) | (k, n) <- bookCitations (cBook c)]
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
      (Block _ _ (Paragraph Nothing is) : rest) | not (any isLineBreak is) -> T.intercalate "\n" (inlines c is : map (block inItem i) rest)
      _ -> T.intercalate "\n" (map (block inItem i) bs)
    sidenotes is =
      T.concat ["\n※" <> T.pack (show n) <> " " <> inlines c xs | Sidenote _ n xs <- is]

isLineBreak :: InlineF r -> Bool
isLineBreak = \case
  LineBreak _ -> True
  _ -> False

-- | The inlines of a paragraph split at its line breaks.
splitLines :: [InlineF r] -> [[InlineF r]]
splitLines is = case break isLineBreak is of
  (l, []) -> [l]
  (l, _ : rest) -> l : splitLines rest

blockInlines :: Block -> [Inline]
blockInlines (Block _ _ body) = case body of
  Paragraph _ is -> deep is
  Heading _ _ is -> deep is
  BulletList items -> concatMap (concatMap blockInlines . itemBlocks) items
  OrderedList items -> concatMap (concatMap blockInlines . itemBlocks) items
  DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap deep ts <> concatMap (concatMap blockInlines) ds) gs
  Table _ h rows -> concatMap deep h <> concatMap (concatMap deep) rows
  FigureBlock f -> concatMap blockInlines (figCaption f)
  _ -> []
  where
    deep = concatMap (\i -> i : nested i)
    nested = \case
      Kenten _ _ xs -> deep xs
      Color _ _ xs -> deep xs
      CharStyle _ _ xs -> deep xs
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
  Cite _ k -> case lookup k (bookCitations (cBook c)) of
    Just n -> "[" <> T.pack (show n) <> "]"
    Nothing -> ""
  ProofComment _ t -> if cProfileDev c then "【校正：" <> t <> "】" else ""
  LineBreak _ -> "\n"
  -- the whole part of an amount in zw as ideographic spaces; less than one, and absolute amounts, are nothing (docs/adr ADR 0019)
  Aki _ (AkiZw r) -> T.replicate (fromInteger (max 0 (floor r))) "\x3000"
  Aki _ (AkiAbs _) -> ""

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
