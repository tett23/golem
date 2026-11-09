{- | The ranges, the references and the section headings of the index
(docs/adr/0265): I1, I2, I3, I5 and I6, and G04101 to G04104.
-}
module IndexSpec (tests) where

import Control.Monad (forM_)
import Data.Char (chr, ord)
import Data.List (sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Assemble.Collation
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

cfg :: AssembleConfig
cfg = AssembleConfig Map.empty "図{n}" Map.empty NumberPerFile [] "リスト{n}" "表{n}" Map.empty 16

sp :: Int -> SrcSpan
sp s = mkSpan (FileId 1) s (s + 1)

at :: Int -> (FileId, SrcSpan)
at s = (FileId 1, sp s)

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
noEval _ _ _ = Right ""

codes :: [Diagnostic] -> [Text]
codes = map (\d -> let DiagnosticCode c = diagCode d in c)

-- | The code and the start of each diagnostic.
sited :: [Diagnostic] -> [(Text, Int)]
sited ds = [(c, spanStart (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]

-- | A mark of one level at a place.
mark :: Int -> Text -> Text -> IndexKind -> Inline
mark s t r = IndexMark (sp s) . IndexEntry [t] [r]

-- | A mark of two levels at a place.
mark2 :: Int -> (Text, Text) -> (Text, Text) -> IndexKind -> Inline
mark2 s (t, sub) (r, rsub) = IndexMark (sp s) . IndexEntry [t, sub] [r, rsub]

-- | One file of the marks, one paragraph each, and @index after them at 1000.
bookOf :: [Inline] -> (Book, [Diagnostic])
bookOf = assemble cfg noEval . docsOf

docsOf :: [Inline] -> [Document]
docsOf ms = [Document (FileId 1) ([Block (spanOf m) Nothing Nothing (Paragraph Nothing [m]) | m <- ms] <> [Block (sp 1000) Nothing Nothing (ChannelOutput IndexOutput)])]
  where
    spanOf = \case
      IndexMark s _ -> s
      _ -> sp 0

sectionsOf :: Book -> [IndexSection]
sectionsOf = concatMap snd . bookIndexes

groupsOf :: Book -> [IndexGroup]
groupsOf = concatMap isGroups . sectionsOf

data Sym = P | B | E
  deriving stock (Eq, Show)

-- | Every sequence of the three marks up to five long.
sequences :: [[Sym]]
sequences = concat [sequence (replicate n [P, B, E]) | n <- [0 .. 5]]

{- | The pairs of a sequence read as brackets, B as ( and E as ): the
places of the points, of the pairs, and the unpaired begins and ends.
-}
naive :: [Sym] -> ([IndexLocator], Int, Int)
naive syms = go (zip [0 ..] syms) [] [] 0
  where
    go [] open acc ends = (map snd (sortOn fst acc), length open, ends)
    go ((i, s) : rest) open acc ends = case s of
      P -> go rest open ((i, AtMark (at i)) : acc) ends
      B -> go rest (i : open) acc ends
      E -> case open of
        b : open' -> go rest open' ((b, Between (at b) (at i)) : acc) ends
        [] -> go rest open acc (ends + 1)

kindOf :: Sym -> IndexKind
kindOf = \case
  P -> IndexPoint
  B -> IndexRangeBegin
  E -> IndexRangeEnd

-- | The kana of the rows of the gojuon, each with its row (I2).
kanaRows :: [(Char, Text)]
kanaRows =
  [ (c, row)
  | (row, cs) <-
      [ ("あ", "ぁあぃいぅうぇえぉおゔ"),
        ("か", "かがきぎくぐけげこごゕゖ"),
        ("さ", "さざしじすずせぜそぞ"),
        ("た", "ただちぢっつづてでとど"),
        ("な", "なにぬねの"),
        ("は", "はばぱひびぴふぶぷへべぺほぼぽ"),
        ("ま", "まみむめも"),
        ("や", "ゃやゅゆょよ"),
        ("ら", "らりるれろ"),
        ("わ", "ゎわゐゑをん")
      ],
    c <- T.unpack cs
  ]

tests :: TestTree
tests =
  testGroup
    "the ranges, the references and the headings of the index (docs/adr/0265)"
    [ testCase "I3: the pairs of every sequence of points, begins and ends up to five are those of brackets" $
        forM_ sequences $ \syms -> do
          let (book, ds) = bookOf [mark i "語" "ご" (kindOf s) | (i, s) <- zip [0 ..] syms]
              (locs, begins, ends) = naive syms
          map igLocators (groupsOf book) @?= [locs | not (null locs)]
          sort (codes ds) @?= replicate begins "G04103" <> replicate ends "G04104",
      testCase "I3: the unpaired marks are reported at themselves" $ do
        sited (snd (bookOf [mark 0 "語" "ご" IndexRangeEnd, mark 1 "語" "ご" IndexRangeBegin, mark 2 "語" "ご" IndexRangeBegin, mark 3 "語" "ご" IndexRangeEnd]))
          @?= [("G04103", 1), ("G04104", 0)],
      testCase "I3: marks of other terms or readings do not pair" $ do
        codes (snd (bookOf [mark 0 "語" "ご" IndexRangeBegin, mark 1 "語" "かたり" IndexRangeEnd])) @?= ["G04103", "G04104"]
        codes (snd (bookOf [mark 0 "語" "ご" IndexRangeBegin, mark 1 "言" "ご" IndexRangeEnd])) @?= ["G04103", "G04104"],
      testCase "I3: a range across two @index is unpaired in both" $ do
        let doc = Document (FileId 1) [Block (sp 0) Nothing Nothing (Paragraph Nothing [mark 0 "語" "ご" IndexRangeBegin]), Block (sp 5) Nothing Nothing (ChannelOutput IndexOutput), Block (sp 6) Nothing Nothing (Paragraph Nothing [mark 6 "語" "ご" IndexRangeEnd]), Block (sp 9) Nothing Nothing (ChannelOutput IndexOutput)]
        sited (snd (assemble cfg noEval [doc])) @?= [("G04103", 0), ("G04104", 6)],
      testCase "I2: every hiragana and katakana is under the row of its clear kana" $ do
        forM_ kanaRows $ \(c, row) -> do
          indexHeading (T.singleton c) @?= row
          indexHeading (T.singleton (chr (ord c + 0x60))) @?= row
        length kanaRows @?= ord 'ゖ' - ord 'ぁ' + 1,
      testCase "I2: the first character alone decides; symbols, digits, Latin letters and the rest" $ do
        map indexHeading ["お", "か", "ん", "ゔ", "ー", "ガイド", "っぽ", "", "1", "#", "api", "API", "Zeta", "漢字", "ａ"]
          @?= ["あ", "か", "わ", "あ", "記号と数字", "か", "た", "記号と数字", "記号と数字", "記号と数字", "A", "A", "Z", "その他", "その他"],
      testCase "I1: the headings split the entries in order, each once, none empty" $ do
        let readings = ["お", "か", "ん", "ゔ", "ー", "1", "a", "B", "漢", "がっこう", "あい", "カタカナ", "ゆ", "わ"]
            ms = [mark i (T.pack (show i)) r IndexPoint | (i, r) <- zip [0 ..] readings]
            (book, ds) = bookOf ms
            secs = sectionsOf book
        ds @?= []
        concatMap isGroups secs @?= indexGroups (docsOf ms)
        map igReadings (concatMap isGroups secs) @?= map pure (sortOn collationKey readings)
        map isHeading secs @?= ["記号と数字", "A", "B", "あ", "か", "や", "わ", "その他"]
        and (zipWith (/=) (map isHeading secs) (drop 1 (map isHeading secs))) @?= True
        all (not . null . isGroups) secs @?= True,
      testCase "I1: no entry, no heading; one heading" $ do
        sectionsOf (fst (bookOf [])) @?= []
        map isHeading (sectionsOf (fst (bookOf [mark 0 "語" "ご" IndexPoint, mark 1 "碁" "ご" IndexPoint]))) @?= ["か"],
      testCase "I5: an automatic reference reads を見よ only for an entry without pages" $ do
        let (book, ds) = bookOf [mark 0 "組版" "くみはん" IndexPoint, mark 1 "タイプセッティング" "たいぷせってぃんぐ" (IndexSee SeeAuto ["組版"]), mark 2 "印刷" "いんさつ" IndexPoint, mark 3 "組版" "くみはん" (IndexSee SeeAuto ["印刷"])]
        ds @?= []
        [(igTerms g, null (igLocators g), indexReferences (not (null (igLocators g))) (igSee g)) | g <- groupsOf book]
          @?= [ (["印刷"], False, ""),
                (["組版"], False, "（印刷をも見よ）"),
                (["タイプセッティング"], True, "（組版を見よ）")
              ],
      testCase "I5: the explicit kinds keep their form; を見よ before をも見よ; the targets in collation order, each once" $ do
        indexReferences True [(SeeOnly, ["組版"])] @?= "（組版を見よ）"
        indexReferences False [(SeeAlso, ["組版"])] @?= "（組版をも見よ）"
        indexReferences False [(SeeAlso, ["印刷"]), (SeeOnly, ["組版"]), (SeeAuto, ["版面"])] @?= "（組版、版面を見よ）（印刷をも見よ）"
        indexReferences True [(SeeAuto, ["組版", "和文組版"])] @?= "（組版：和文組版をも見よ）"
        let (book, _) = bookOf [mark 0 "組版" "くみはん" IndexPoint, mark 1 "印刷" "いんさつ" IndexPoint, mark 2 "語" "ご" (IndexSee SeeAuto ["組版"]), mark 3 "語" "ご" (IndexSee SeeAuto ["印刷"]), mark 4 "語" "ご" (IndexSee SeeAuto ["組版"])]
        [igSee g | g <- groupsOf book, igTerms g == ["語"]] @?= [[(SeeAuto, ["印刷"]), (SeeAuto, ["組版"])]],
      testCase "I6: G04101 at each reference to terms no entry of the list has; readings are not compared" $ do
        sited (snd (bookOf [mark 0 "組版" "くみはん" IndexPoint, mark 1 "語" "ご" (IndexSee SeeAuto ["印刷"]), mark 2 "語" "ご" (IndexSee SeeAuto ["組版"])])) @?= [("G04101", 1)]
        codes (snd (bookOf [mark 0 "組版" "そばん" IndexPoint, mark 1 "語" "ご" (IndexSee SeeAuto ["組版"])])) @?= []
        codes (snd (bookOf [mark2 0 ("組版", "和文") ("くみはん", "わぶん") IndexPoint, mark 1 "語" "ご" (IndexSee SeeAuto ["組版", "和文"]), mark 2 "語" "ご" (IndexSee SeeAuto ["組版"])])) @?= []
        codes (snd (bookOf [mark 0 "組版" "くみはん" IndexPoint, mark 1 "語" "ご" (IndexSee SeeAuto ["組版", "和文"])])) @?= ["G04101"],
      testCase "I6: a reference to an entry of another @index is G04101" $ do
        let doc = Document (FileId 1) [Block (sp 0) Nothing Nothing (Paragraph Nothing [mark 0 "組版" "くみはん" IndexPoint]), Block (sp 5) Nothing Nothing (ChannelOutput IndexOutput), Block (sp 6) Nothing Nothing (Paragraph Nothing [mark 6 "語" "ご" (IndexSee SeeAuto ["組版"])]), Block (sp 9) Nothing Nothing (ChannelOutput IndexOutput)]
        sited (snd (assemble cfg noEval [doc])) @?= [("G04101", 6)],
      testCase "G04102: a reference of an entry without pages to itself, at the mark" $
        sited (snd (bookOf [mark 0 "語" "ご" (IndexSee SeeAuto ["語"])])) @?= [("G04102", 0)],
      testCase "G04102: a cycle of two entries without pages, at its first mark" $ do
        sited (snd (bookOf [mark 0 "甲" "こう" (IndexSee SeeAuto ["乙"]), mark 1 "乙" "おつ" (IndexSee SeeOnly ["甲"])])) @?= [("G04102", 0)]
        sited (snd (bookOf [mark 0 "丙" "へい" IndexPoint, mark 1 "乙" "おつ" (IndexSee SeeAuto ["甲"]), mark 2 "甲" "こう" (IndexSee SeeAuto ["乙"])])) @?= [("G04102", 1)],
      testCase "G04102: no cycle with an entry of pages, an をも見よ, or a main entry of sub-entries" $ do
        codes (snd (bookOf [mark 0 "甲" "こう" (IndexSee SeeAuto ["乙"]), mark 1 "乙" "おつ" (IndexSee SeeAuto ["甲"]), mark 2 "乙" "おつ" IndexPoint])) @?= []
        codes (snd (bookOf [mark 0 "甲" "こう" (IndexSee SeeAlso ["乙"]), mark 1 "乙" "おつ" (IndexSee SeeAuto ["甲"])])) @?= []
        codes (snd (bookOf [mark 0 "甲" "こう" (IndexSee SeeAuto ["乙"]), mark 1 "乙" "おつ" (IndexSee SeeAuto ["甲"]), mark2 2 ("乙", "丁") ("おつ", "てい") IndexPoint])) @?= [],
      testCase "a reference makes no page and keeps its entry; ranges in the order of their begins" $ do
        let (book, ds) = bookOf [mark 0 "組版" "くみはん" IndexRangeBegin, mark 1 "組版" "くみはん" IndexPoint, mark 2 "組版" "くみはん" IndexRangeEnd, mark 3 "印刷" "いんさつ" (IndexSee SeeAuto ["組版"])]
        ds @?= []
        [(igTerms g, igLocators g) | g <- groupsOf book] @?= [(["印刷"], []), (["組版"], [Between (at 0) (at 2), AtMark (at 1)])]
    ]
