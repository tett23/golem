module AssembleSpec (tests) where

import Control.Monad (forM_, replicateM)
import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Assemble.Collation
import Golem.Doc.IR
import Golem.Numerals
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

cfg :: AssembleConfig
cfg = AssembleConfig (Map.fromList [(1, "第{n:kanji}章")]) "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}" "表{chapter}-{n}" Map.empty 16

sp :: Int -> Int -> SrcSpan
sp f s = mkSpan (FileId f) s (s + 1)

heading :: Int -> Int -> Int -> HeadingAttrs -> Maybe Text -> Text -> Block
heading f s l a lbl t = Block (sp f s) lbl Nothing (Heading l a [Text (sp f s) t])

para :: Int -> Int -> [Inline] -> Block
para f s is = Block (sp f s) Nothing Nothing (Paragraph Nothing is)

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
noEval dv _ _ = Right ("count=" <> T.pack (show (dvChapterCount dv)))

codes :: [Diagnostic] -> [Text]
codes = map (\d -> let DiagnosticCode c = diagCode d in c)

tests :: TestTree
tests =
  testGroup
    "assembly, S1 (ADR 0002)"
    [ noticeTests,
      noteNumberTests,
      unwritableTests,
      testCase "J1: chapter-end notes use the primary language subtag" $ do
        let cases = [("", False), ("j", False), ("ja", True), ("JA", True), ("ja-JP", True), ("ja-", True), ("jam", False), ("ja_JP", False), ("en", False), ("en-ja", False)]
        forM_ cases $ \(lang, expected) -> (notesTitle lang == "注") @?= expected,
      testCase "J2: chapter-end notes ignore case" $ do
        let cases = [("", False), ("j", False), ("ja", True), ("JA", True), ("ja-JP", True), ("ja-", True), ("jam", False), ("ja_JP", False), ("en", False), ("en-ja", False)]
        forM_ cases $ \(lang, _) -> notesTitle lang @?= notesTitle (T.toUpper lang),
      testCase "kanji numerals" $ do
        map kanji [1, 10, 12, 120, 1000, 10000, 20005] @?= ["一", "十", "十二", "百二十", "千", "一万", "二万五"]
        kanjiDigits 120 @?= "一二〇",
      testCase "heading numbers across files, @number, @nonumber, section reset" $ do
        let docs =
              [ Document (FileId 1) [heading 1 0 1 noHeadingAttrs {haNoNumber = True} Nothing "まえがき", heading 1 10 1 noHeadingAttrs Nothing "一章", heading 1 20 2 noHeadingAttrs Nothing "節"],
                Document (FileId 2) [heading 2 0 1 noHeadingAttrs {haNumber = Just 5} Nothing "五章", heading 2 10 2 noHeadingAttrs Nothing "節", heading 2 20 1 noHeadingAttrs Nothing "六章"]
              ]
            (book, ds) = assemble cfg noEval docs
            nums = map (hiNumberText . snd) (Map.toAscList (bookHeadings book))
        ds @?= []
        nums @?= [Nothing, Just "第一章", Just "1.1", Just "第五章", Just "5.1", Just "第六章"],
      sixLevelTests,
      testCase "labels: cross-file references, duplicates, missing" $ do
        let docs =
              [ Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "intro") "はじめに"],
                Document (FileId 2) [para 2 0 [Ref (sp 2 0) RefNumber "intro", Ref (sp 2 1) RefTitle "intro", Ref (sp 2 2) RefPage "intro"]]
              ]
            (book, ds) = assemble cfg noEval docs
        ds @?= []
        case bookDocs book of
          [_, Document _ [Block _ _ _ (Paragraph Nothing is)]] -> is @?= [Resolved (sp 2 0) RefNumber "intro" [Number (sp 2 0) 1 Nothing], Resolved (sp 2 1) RefTitle "intro" [Text (sp 2 1) "はじめに"], Ref (sp 2 2) RefPage "intro"]
          other -> assertFailure (show other)
        codes (snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x", heading 1 5 1 noHeadingAttrs (Just "a") "y"]])) @?= ["G04001"]
        codes (snd (assemble cfg noEval [Document (FileId 1) [para 1 0 [Ref (sp 1 0) RefTitle "nope"]]])) @?= ["G04003"],
      testCase "R1 R2: [ref-number] and [ref-title] become Resolved around the text they resolve to, in any place (docs/adr/0215)" $ do
        let title = [Text (sp 1 1) "組版の", Ruby (sp 1 2) () [RubySegment [Text (sp 1 2) "設計"] (Just "せっけい")]]
            h = Block (sp 1 1) (Just "h") Nothing (Heading 1 noHeadingAttrs title)
            fig = Block (sp 1 3) (Just "f") Nothing (FigureBlock (Figure "a.png" Nothing "代替" Nothing Nothing [para 1 3 [Text (sp 1 3) "図の題"]] Nothing False False))
            refs n = [Ref (sp 1 n) RefNumber "h", Ref (sp 1 (n + 1)) RefTitle "h", Ref (sp 1 (n + 2)) RefNumber "f"]
            cell = Block (sp 1 10) Nothing Nothing (TableBlock (plainTable [AlignDefault] [[Text (sp 1 10) "見出し"]] [[refs 11]]))
            noted = para 1 20 [Note (sp 1 20) 1 (noteBody (sp 1 20) (refs 21))]
            docs = [Document (FileId 1) [h, fig, para 1 4 (refs 5), cell, noted]]
            (book, ds) = assemble cfg noEval docs
            resolved n =
              [ Resolved (sp 1 n) RefNumber "h" [Number (sp 1 n) 1 Nothing],
                Resolved (sp 1 (n + 1)) RefTitle "h" [Text (sp 1 (n + 1)) "組版の", Ruby (sp 1 2) () [RubySegment [Text (sp 1 2) "設計"] (Just "せっけい")]],
                Resolved (sp 1 (n + 2)) RefNumber "f" [Text (sp 1 (n + 2)) "1-1"]
              ]
        ds @?= []
        case bookDocs book of
          [Document _ [_, _, Block _ _ _ (Paragraph _ a), Block _ _ _ (TableBlock Table {tableRows = [[b]]}), Block _ _ _ (Paragraph _ [Note _ _ [Block _ _ _ (Paragraph _ c)]])]] -> do
            a @?= resolved 5
            b @?= resolved 11
            c @?= resolved 21
          other -> assertFailure (show other),
      testCase "deferred expressions see the chapter count" $ do
        let docs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "a", heading 1 5 1 noHeadingAttrs Nothing "b", para 1 9 [Deferred (sp 1 9) (DeferredExpr undefined)]]]
        case bookDocs (fst (assemble cfg noEval docs)) of
          [Document _ [_, _, Block _ _ _ (Paragraph Nothing is)]] -> is @?= [Text (sp 1 9) "count=2"]
          other -> assertFailure (show other),
      testCase "figure numbers restart per chapter" $ do
        let fig f s = Block (sp f s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False False))
            docs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", fig 1 2, fig 1 4, heading 1 6 1 noHeadingAttrs Nothing "二", fig 1 8]]
            (book, ds) = assemble cfg noEval docs
        ds @?= []
        Map.elems (bookFigures book) @?= ["図1-1", "図1-2", "図2-1"]
        codes (snd (assemble cfg noEval [Document (FileId 1) [fig 1 0]])) @?= ["G04004"],
      testCase "only one @toc" $ do
        let toc s = Block (sp 1 s) Nothing Nothing (ChannelOutput (TocOutput 2))
        codes (snd (assemble cfg noEval [Document (FileId 1) [toc 0, toc 5]])) @?= ["G04002"],
      testCase "toc entries carry the span of their heading block (golem-driver ADR 0009)" $ do
        let toc = Block (sp 1 0) Nothing Nothing (ChannelOutput (TocOutput 2))
            docs = [Document (FileId 1) [toc, heading 1 10 1 noHeadingAttrs Nothing "一", heading 1 20 2 noHeadingAttrs Nothing "節", heading 1 30 1 noHeadingAttrs {haNoToc = True} Nothing "外"]]
            book = fst (assemble cfg noEval docs)
        map teSpan (bookToc book) @?= [sp 1 10, sp 1 20]
        all ((`Map.member` bookHeadings book) . teSpan) (bookToc book) @?= True
        assertBool "notoc" (sp 1 30 `notElem` map teSpan (bookToc book)),
      testCase "index order: kana, voicing, small kana, long vowel, latin before kana" $ do
        let mark s t r = IndexMark (sp 1 s) (IndexEntry [t] [r] IndexPoint)
            docs = [Document (FileId 1) [para 1 0 [mark 0 "ガ" "が", mark 1 "カ" "か", mark 2 "パ" "ぱ", mark 3 "ハ" "は", mark 4 "バ" "ば", mark 5 "API" "API", mark 6 "ツ" "つ", mark 7 "ッ" "っ", mark 8 "カ" "か"], Block (sp 1 50) Nothing Nothing (ChannelOutput IndexOutput)]]
            book = fst (assemble cfg noEval docs)
        map igTerms (concatMap (concatMap isGroups . snd) (bookIndexes book)) @?= [["API"], ["カ"], ["ガ"], ["ツ"], ["ッ"], ["ハ"], ["バ"], ["パ"]]
        map (length . igLocators) (concatMap (concatMap isGroups . snd) (bookIndexes book)) @?= [1, 2, 1, 1, 1, 1, 1, 1]
        compare (collationKey "かー") (collationKey "かあ") @?= EQ,
      testCase "citations are numbered in order of first citation" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) [citeItem "b"], Cite (sp 1 1) [citeItem "a"], Cite (sp 1 2) [citeItem "b"]]]]
        bookBibliographies (fst (assemble cfg noEval docs)) @?= [(Nothing, [("b", 1), ("a", 2)])],
      multipleListTests,
      channelTests,
      titleCopyTests,
      testCase "tocWithinDepth: every entry without @toc, those within its depth in order with it (golem-epub ADR 0002)" $ do
        let docs d =
              [ Document (FileId 1) ([Block (sp 1 0) Nothing Nothing (ChannelOutput (TocOutput n)) | Just n <- [d]] <> [heading 1 10 1 noHeadingAttrs Nothing "一", heading 1 20 2 noHeadingAttrs Nothing "節", heading 1 30 3 noHeadingAttrs Nothing "項", heading 1 40 1 noHeadingAttrs Nothing "二"])
              ]
            levels d = map teLevel (tocWithinDepth (fst (assemble cfg noEval (docs d))))
        levels Nothing @?= [1, 2, 3, 1]
        levels (Just 1) @?= [1, 1]
        levels (Just 2) @?= [1, 2, 1]
        levels (Just 3) @?= [1, 2, 3, 1],
      diagnosticCodes
    ]

-- | The numbers of headings of levels 4 to 6 (docs/adr/0188).
sixLevelTests :: TestTree
sixLevelTests =
  testGroup
    "headings of six levels (docs/adr/0188)"
    [ testCase "levels 1 to 6 by the default formats" $
        numbersOf Map.empty [1, 2, 3, 4, 5, 6] @?= [Just "1", Just "1.1", Just "1.1.1", Just "1.1.1.1", Just "1.1.1.1.1", Just "1.1.1.1.1.1"],
      testCase "a level 4 after a level 2 counts the deeper levels from 0" $
        numbersOf Map.empty [1, 2, 3, 4, 5, 2, 4, 6] @?= [Just "1", Just "1.1", Just "1.1.1", Just "1.1.1.1", Just "1.1.1.1.1", Just "1.2", Just "1.2.0.1", Just "1.2.0.1.0.1"],
      testCase "[headings.4] number = \"{1}-{3}-{n}\" writes as written" $
        numbersOf (Map.fromList [(4, "{1}-{3}-{n}")]) [1, 2, 3, 3, 4, 4] @?= [Just "1", Just "1.1", Just "1.1.1", Just "1.1.2", Just "1-2-1", Just "1-2-2"],
      testCase "a level 6 right after a level 3 is numbered, the levels 4 and 5 being 0" $
        numbersOf Map.empty [1, 2, 3, 6] @?= [Just "1", Just "1.1", Just "1.1.1", Just "1.1.1.0.0.1"]
    ]
  where
    numbersOf fmts ls =
      let c = AssembleConfig fmts "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}" "表{chapter}-{n}" Map.empty 16
          docs = [Document (FileId 1) [heading 1 (i * 10) l noHeadingAttrs Nothing "見出し" | (i, l) <- zip [0 ..] ls]]
          (book, ds) = assemble c noEval docs
       in if null ds then map (hiNumberText . snd) (Map.toAscList (bookHeadings book)) else error (show ds)

{- | The copies of a title (the table of contents, [ref-title]) have no
index marks and no channel items, at any depth; the heading keeps them
(docs/adr/0145).
-}
titleCopyTests :: TestTree
titleCopyTests =
  testGroup
    "the copies of a title drop the anchor inlines (docs/adr/0145)"
    [ testCase "the toc entry and the label's title of a heading: no marks at any depth; the heading keeps them" $ do
        let mark = IndexMark (sp 1 3) (IndexEntry ["組"] ["くみ"] IndexPoint)
            itm = ChannelItem (sp 1 4) (ChannelItemData "glossary" (Just "k") (Just "か") [Text (sp 1 4) "組版"])
            title = [CharStyle (sp 1 2) "strong" [mark, Text (sp 1 2) "と"], itm, Kenten (sp 1 5) Nothing [itm], Text (sp 1 6) "の章"]
            h = Block (sp 1 1) (Just "h") Nothing (Heading 1 noHeadingAttrs title)
            docs = [Document (FileId 1) [Block (sp 1 0) Nothing Nothing (ChannelOutput (TocOutput 2)), h, para 1 7 [Ref (sp 1 8) RefTitle "h"]]]
            book = fst (assemble cfg noEval docs)
            stripped = [CharStyle (sp 1 2) "strong" [Text (sp 1 2) "と"], Kenten (sp 1 5) Nothing [], Text (sp 1 6) "の章"]
        map teTitle (bookToc book) @?= [stripped]
        case bookDocs book of
          [Document _ [_, Block _ _ _ (Heading _ _ is), Block _ _ _ (Paragraph _ copied)]] -> do
            is @?= title
            copied @?= [Resolved (sp 1 8) RefTitle "h" [CharStyle (sp 1 2) "strong" [Text (sp 1 2) "と"], Kenten (sp 1 5) Nothing [], Text (sp 1 8) "の章"]]
          other -> assertFailure (show other),
      testCase "the label's title of a captioned code block has no marks" $ do
        let mark = IndexMark (sp 1 3) (IndexEntry ["組"] ["くみ"] IndexPoint)
            code = Block (sp 1 1) (Just "c") Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 2) "例", mark]) False [] False))
            docs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", code, para 1 7 [Ref (sp 1 8) RefTitle "c"]]]
        case bookDocs (fst (assemble cfg noEval docs)) of
          [Document _ [_, _, Block _ _ _ (Paragraph _ copied)]] -> copied @?= [Resolved (sp 1 8) RefTitle "c" [Text (sp 1 8) "例"]]
          other -> assertFailure (show other),
      -- docs/adr ADR 0187
      testCase "a language span in a title stays in the toc entry and the copy of [ref-title]" $ do
        let title = [Lang (sp 1 2) "en" [Text (sp 1 2) "Tokyo"], Text (sp 1 3) "の話"]
            h = Block (sp 1 1) (Just "h") Nothing (Heading 1 noHeadingAttrs title)
            docs = [Document (FileId 1) [Block (sp 1 0) Nothing Nothing (ChannelOutput (TocOutput 2)), h, para 1 7 [Ref (sp 1 8) RefTitle "h"]]]
            book = fst (assemble cfg noEval docs)
        map teTitle (bookToc book) @?= [title]
        case bookDocs book of
          [Document _ [_, _, Block _ _ _ (Paragraph _ copied)]] -> copied @?= [Resolved (sp 1 8) RefTitle "h" [Lang (sp 1 2) "en" [Text (sp 1 2) "Tokyo"], Text (sp 1 8) "の話"]]
          other -> assertFailure (show other),
      testCase "the language of a heading wraps the whole title of the toc entry and of the copy of [ref-title]" $ do
        let h = Block (sp 1 1) (Just "h") (Just "en") (Heading 1 noHeadingAttrs [Text (sp 1 2) "Tokyo"])
            docs = [Document (FileId 1) [Block (sp 1 0) Nothing Nothing (ChannelOutput (TocOutput 2)), h, para 1 7 [Ref (sp 1 8) RefTitle "h"]]]
            book = fst (assemble cfg noEval docs)
        map teTitle (bookToc book) @?= [[Lang (sp 1 1) "en" [Text (sp 1 2) "Tokyo"]]]
        case bookDocs book of
          [Document _ [_, _, Block _ _ _ (Paragraph _ copied)]] -> copied @?= [Resolved (sp 1 8) RefTitle "h" [Lang (sp 1 1) "en" [Text (sp 1 2) "Tokyo"]]]
          other -> assertFailure (show other),
      testCase "the body of a note is in the language of the place of its mark" $ do
        let note n = Note (sp 1 n) n (noteBody (sp 1 n) [Text (sp 1 n) "注"])
            docs =
              Document
                (FileId 1)
                [ para 1 0 [note 1, Lang (sp 1 2) "fr" [note 2]],
                  Block (sp 1 3) Nothing (Just "en") (BulletList [ListItem Nothing [para 1 4 [note 3, Lang (sp 1 5) "de" [note 4]]]])
                ]
        [body | (_, _, body) <- documentNotes docs]
          @?= [ [[Text (sp 1 1) "注"]],
                [[Lang (sp 1 2) "fr" [Text (sp 1 2) "注"]]],
                [[Lang (sp 1 3) "en" [Text (sp 1 3) "注"]]],
                [[Lang (sp 1 4) "de" [Text (sp 1 4) "注"]]]
              ]
    ]

-- | The channels of plugins (golem-doc ADR 0007).
channelTests :: TestTree
channelTests =
  testGroup
    "the channels of plugins (golem-doc ADR 0007)"
    [ testCase "three items of one key are one entry: the body of the first, three locations" $ do
        let docs = [Document (FileId 1) [para 1 0 [item 1 0 "glossary" (Just "k") (Just "か") "一", item 1 1 "glossary" (Just "k") (Just "か") "二"], para 1 5 [item 1 5 "glossary" (Just "k") (Just "か") "三"], list 1 9 "glossary"]]
        entries (fst (assemble ccfg noEval docs)) @?= [((FileId 1, sp 1 9), "glossary", [(Just "k", ["一"], [(FileId 1, sp 1 0), (FileId 1, sp 1 1), (FileId 1, sp 1 5)])])],
      testCase "two items without a key are two entries" $ do
        let docs = [Document (FileId 1) [para 1 0 [item 1 0 "people" Nothing Nothing "甲", item 1 1 "people" Nothing Nothing "甲"], list 1 9 "people"]]
        map (\(_, _, es) -> length es) (entries (fst (assemble ccfg noEval docs))) @?= [2],
      testCase "the reading order is that of the index" $ do
        let docs = [Document (FileId 1) [para 1 0 [item 1 0 "glossary" (Just "1") (Just "かんじ") "漢字", item 1 1 "glossary" (Just "2") (Just "かな") "かな", item 1 2 "glossary" (Just "3") (Just "カナ") "カナ"], list 1 9 "glossary"]]
            bodies = [b | (_, _, es) <- entries (fst (assemble ccfg noEval docs)), (_, b, _) <- es]
            expected = map snd (sortOn fst [(collationKey r, [t]) | (r, t) <- [("かんじ", "漢字"), ("かな", "かな"), ("カナ", "カナ")]])
        bodies @?= expected
        bodies @?= [["かな"], ["カナ"], ["漢字"]],
      testCase "the document order follows the first locations across files" $ do
        let docs =
              [ Document (FileId 1) [para 1 0 [item 1 0 "people" (Just "b") Nothing "乙"]],
                Document (FileId 2) [para 2 0 [item 2 0 "people" (Just "a") Nothing "甲", item 2 1 "people" (Just "b") Nothing "乙"], list 2 9 "people"]
              ]
        [k | (_, _, es) <- entries (fst (assemble ccfg noEval docs)), (k, _, _) <- es] @?= [Just "b", Just "a"],
      testCase "one @channel at the end of each chapter lists the items of its chapter" $ do
        let docs =
              [ Document (FileId 1) [para 1 0 [item 1 0 "people" (Just "a") Nothing "甲"], list 1 9 "people"],
                Document (FileId 2) [para 2 0 [item 2 0 "people" (Just "b") Nothing "乙"], list 2 9 "people"]
              ]
        [(at, [k | (k, _, _) <- es]) | (at, _, es) <- entries (fst (assemble ccfg noEval docs))]
          @?= [((FileId 1, sp 1 9), [Just "a"]), ((FileId 2, sp 2 9), [Just "b"])],
      testCase "the lists of one channel do not take the items of another" $ do
        let docs = [Document (FileId 1) [para 1 0 [item 1 0 "people" (Just "a") Nothing "甲", item 1 1 "glossary" (Just "g") (Just "が") "語"], list 1 8 "glossary", list 1 9 "people"]]
        [(c, [k | (k, _, _) <- es]) | (_, c, es) <- entries (fst (assemble ccfg noEval docs))] @?= [("glossary", [Just "g"]), ("people", [Just "a"])]
    ]
  where
    ccfg = cfg {acChannels = Map.fromList [(channelName d, d) | d <- [ChannelDecl "glossary" OrderReading False, ChannelDecl "people" OrderDocument True]]}
    item f s c k r t = ChannelItem (sp f s) (ChannelItemData c k r [Text (sp f s) t])
    list f s c = Block (sp f s) Nothing Nothing (ChannelOutput (CustomOutput c Nothing))
    entries book = [(at, c, [(ceKey e, [t | Text _ t <- ceBody e], ceLocations e) | e <- es]) | (at, c, es) <- bookChannels book]

-- | Several @index and @bibliography in a book (golem-doc ADR 0008).
multipleListTests :: TestTree
multipleListTests =
  testGroup
    "several @index and @bibliography (golem-doc ADR 0008)"
    [ testCase "one @bibliography lists every citation wherever it is" $ do
        let cites = para 1 10 [Cite (sp 1 10) [citeItem "b"], Cite (sp 1 11) [citeItem "a"], Cite (sp 1 12) [citeItem "b"]]
            more = para 1 20 [Cite (sp 1 20) [citeItem "c"]]
        mapM_
          ( \bs -> do
              let book = fst (assemble cfg noEval [Document (FileId 1) bs])
              bookBibliographies book @?= [(Just (FileId 1, sp 1 0), [("b", 1), ("a", 2), ("c", 3)])]
          )
          [ [bib 1 0, cites, more],
            [cites, bib 1 0, more],
            [cites, more, bib 1 0]
          ],
      testCase "a @bibliography at the end of each chapter numbers its own citations" $ do
        let docs =
              [ Document (FileId 1) [para 1 0 [Cite (sp 1 0) [citeItem "A"], Cite (sp 1 1) [citeItem "B"]], bib 1 5],
                Document (FileId 2) [para 2 0 [Cite (sp 2 0) [citeItem "B"], Cite (sp 2 1) [citeItem "C"]], bib 2 5]
              ]
            book = fst (assemble cfg noEval docs)
        bookBibliographies book
          @?= [ (Just (FileId 1, sp 1 5), [("A", 1), ("B", 2)]),
                (Just (FileId 2, sp 2 5), [("B", 1), ("C", 2)])
              ]
        Map.lookup (FileId 2, sp 2 0) (bookCiteMarks book) @?= Just (Just (FileId 2, sp 2 5), 1)
        Map.lookup (FileId 1, sp 1 1) (bookCiteMarks book) @?= Just (Just (FileId 1, sp 1 5), 2),
      testCase "citations after the last @bibliography go to the last one" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) [citeItem "A"]], bib 1 5, para 1 6 [Cite (sp 1 6) [citeItem "B"]], bib 1 10, para 1 12 [Cite (sp 1 12) [citeItem "C"], Cite (sp 1 13) [citeItem "B"]]]]
            book = fst (assemble cfg noEval docs)
        map snd (bookBibliographies book) @?= [[("A", 1)], [("B", 1), ("C", 2)]]
        Map.lookup (FileId 1, sp 1 12) (bookCiteMarks book) @?= Just (Just (FileId 1, sp 1 10), 2),
      testCase "I5: the numbers of a list follow the keys of its marks in document order, each mark in the order written (docs/adr/0266)" $ do
        let keys = ["a", "b", "c", "d"]
            marks = [ks | n <- [1 .. 3], ks <- replicateM n keys, length (nub ks) == length ks]
            pairs = [(m1, m2) | m1 <- marks, m2 <- take 40 marks]
        forM_ pairs $ \(m1, m2) -> do
          let cite f s ks = Cite (sp f s) (map citeItem ks)
              docs = [Document (FileId 1) [para 1 0 [cite 1 0 m1, cite 1 1 m2], bib 1 5]]
              book = fst (assemble cfg noEval docs)
          map snd (bookBibliographies book) @?= [zip (nub (m1 <> m2)) [1 ..]]
        -- two lists: a mark of several keys belongs whole to the list of its place
        let docs =
              [ Document (FileId 1) [para 1 0 [Cite (sp 1 0) (map citeItem ["c", "a"])], bib 1 5, para 1 6 [Cite (sp 1 6) (map citeItem ["b", "c"])], bib 1 10]
              ]
            book = fst (assemble cfg noEval docs)
        map snd (bookBibliographies book) @?= [[("c", 1), ("a", 2)], [("b", 1), ("c", 2)]]
        citeNumber book (sp 1 6) "c" @?= Just 2
        citeNumber book (sp 1 0) "a" @?= Just 2,
      testCase "a citation in a footnote is at the paragraph of the note" $ do
        let docs = [Document (FileId 1) [para 1 0 [Text (sp 1 0) "a", Note (sp 1 1) 1 (noteBody (sp 1 1) [Cite (sp 1 2) [citeItem "N"]])], bib 1 5, para 1 6 [Cite (sp 1 6) [citeItem "M"]], bib 1 10]]
            book = fst (assemble cfg noEval docs)
        map snd (bookBibliographies book) @?= [[("N", 1)], [("M", 1)]],
      testCase "each @index has the marks of its own range" $ do
        let mark f s t = IndexMark (sp f s) (IndexEntry [t] [t] IndexPoint)
            idx f s = Block (sp f s) Nothing Nothing (ChannelOutput IndexOutput)
            docs =
              [ Document (FileId 1) [para 1 0 [mark 1 0 "か", mark 1 1 "あ"], idx 1 5],
                Document (FileId 2) [para 2 0 [mark 2 0 "か"], idx 2 5, para 2 6 [mark 2 6 "さ"]]
              ]
            book = fst (assemble cfg noEval docs)
        [(at, [(igTerms g, igLocators g) | g <- concatMap isGroups ss]) | (at, ss) <- bookIndexes book]
          @?= [ ((FileId 1, sp 1 5), [(["あ"], [AtMark (FileId 1, sp 1 1)]), (["か"], [AtMark (FileId 1, sp 1 0)])]),
                ((FileId 2, sp 2 5), [(["か"], [AtMark (FileId 2, sp 2 0)]), (["さ"], [AtMark (FileId 2, sp 2 6)])])
              ],
      testCase "without @bibliography, one list without a place numbers the whole book" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) [citeItem "b"]]], Document (FileId 2) [para 2 0 [Cite (sp 2 0) [citeItem "a"], Cite (sp 2 1) [citeItem "b"]]]]
            book = fst (assemble cfg noEval docs)
        bookBibliographies book @?= [(Nothing, [("b", 1), ("a", 2)])]
        Map.lookup (FileId 2, sp 2 1) (bookCiteMarks book) @?= Just (Nothing, 1),
      testCase "two @toc are still G04002" $ do
        let toc s = Block (sp 1 s) Nothing Nothing (ChannelOutput (TocOutput 2))
        codes (snd (assemble cfg noEval [Document (FileId 1) [toc 0, bib 1 2, bib 1 3, toc 5]])) @?= ["G04002"]
    ]
  where
    bib f s = Block (sp f s) Nothing Nothing (ChannelOutput BibliographyOutput)

-- | The diagnostics of document assembly (golem-doc ADR 0003).
diagnosticCodes :: TestTree
diagnosticCodes =
  testGroup
    "diagnostic codes (golem-doc ADR 0003)"
    [ testCase "G04001: every later duplicate, related to the first definition" $ do
        let ds = snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x", heading 1 5 1 noHeadingAttrs (Just "a") "y", heading 1 9 1 noHeadingAttrs (Just "a") "z"]])
        map summary ds
          @?= [ ("G04001", Error, sp 1 5, "ラベルが重複しています: a", [(sp 1 0, "最初の定義")]),
                ("G04001", Error, sp 1 9, "ラベルが重複しています: a", [(sp 1 0, "最初の定義")])
              ]
        let cross = snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x"], Document (FileId 2) [heading 2 0 1 noHeadingAttrs (Just "a") "y"]])
        map summary cross @?= [("G04001", Error, sp 2 0, "ラベルが重複しています: a", [(sp 1 0, "最初の定義")])],
      testCase "G04002: every later @toc, related to the first" $ do
        let toc s = Block (sp 1 s) Nothing Nothing (ChannelOutput (TocOutput 2))
            ds = snd (assemble cfg noEval [Document (FileId 1) [toc 0, toc 5, toc 9]])
        map summary ds
          @?= [ ("G04002", Error, sp 1 5, "@toc は文書に一つだけ置けます", [(sp 1 0, "最初の @toc")]),
                ("G04002", Error, sp 1 9, "@toc は文書に一つだけ置けます", [(sp 1 0, "最初の @toc")])
              ],
      testCase "G04003: references of every kind to a missing label, also inside a list item" $ do
        let refs = [Ref (sp 1 1) RefNumber "nope", Ref (sp 1 2) RefTitle "nope", Ref (sp 1 3) RefPage "nope"]
            listed = Block (sp 1 4) Nothing Nothing (BulletList [ListItem Nothing [para 1 5 [Ref (sp 1 6) RefNumber "gone"]]])
            (book, ds) = assemble cfg noEval [Document (FileId 1) [para 1 0 refs, listed]]
        map summary ds
          @?= [ ("G04003", Error, sp 1 1, "存在しないラベルへの参照です: nope", []),
                ("G04003", Error, sp 1 2, "存在しないラベルへの参照です: nope", []),
                ("G04003", Error, sp 1 3, "存在しないラベルへの参照です: nope", []),
                ("G04003", Error, sp 1 6, "存在しないラベルへの参照です: gone", [])
              ]
        case bookDocs book of
          [Document _ (Block _ _ _ (Paragraph Nothing is) : _)] -> is @?= []
          other -> assertFailure (show other),
      testCase "G04004: figures outside a chapter, before the first and after a @nonumber chapter" $ do
        let fig s = Block (sp 1 s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False False))
            docs = [Document (FileId 1) [fig 0, heading 1 2 1 noHeadingAttrs Nothing "一", fig 4, heading 1 6 1 noHeadingAttrs {haNoNumber = True} Nothing "あとがき", fig 8]]
            msg = "章の外にある図版、表、コードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります。番号を振らないなら @nonumber を付けます"
        map summary (snd (assemble cfg noEval docs))
          @?= [("G04004", Error, sp 1 0, msg, []), ("G04004", Error, sp 1 8, msg, [])]
        snd (assemble cfg {acFigureFormat = "{n}"} noEval docs) @?= [],
      -- docs/adr/0200
      testCase "@nonumber figures and code blocks outside a chapter: no G04004, not in bookFigures nor bookListings" $ do
        let fig s nn = Block (sp 1 s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False nn))
            code s nn = Block (sp 1 s) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 s) "a"]) False [] nn))
            (book, ds) = assemble cfg noEval [Document (FileId 1) [fig 0 True, code 1 True, heading 1 2 1 noHeadingAttrs {haNoNumber = True} Nothing "あとがき", fig 3 True, code 4 True]]
        ds @?= []
        bookFigures book @?= Map.empty
        bookListings book @?= Map.empty,
      testCase "@nonumber figures and code blocks in a chapter take no number" $ do
        let fig s nn = Block (sp 1 s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False nn))
            code s nn = Block (sp 1 s) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 s) "a"]) False [] nn))
            (book, ds) = assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", fig 1 False, fig 2 True, fig 3 False, code 4 False, code 5 True, code 6 False]]
        ds @?= []
        Map.toAscList (bookFigures book) @?= [(sp 1 1, "図1-1"), (sp 1 3, "図1-2")]
        Map.toAscList (bookListings book) @?= [(sp 1 4, "リスト1-1"), (sp 1 6, "リスト1-2")],
      testCase "ref-number to a @nonumber figure or code block is G04005; ref-title gives the alt text and the caption" $ do
        let fig = Block (sp 1 1) (Just "f") Nothing (FigureBlock (Figure "a.png" Nothing "代替" Nothing Nothing [] Nothing False True))
            code = Block (sp 1 2) (Just "c") Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 2) "設定"]) False [] True))
            docs refs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", fig, code, para 1 3 refs]]
        map summary (snd (assemble cfg noEval (docs [Ref (sp 1 4) RefNumber "f", Ref (sp 1 5) RefNumber "c"])))
          @?= [("G04005", Error, sp 1 4, "番号を持たない要素への参照です: f", []), ("G04005", Error, sp 1 5, "番号を持たない要素への参照です: c", [])]
        let (book, ds) = assemble cfg noEval (docs [Ref (sp 1 4) RefTitle "f", Ref (sp 1 5) RefTitle "c"])
        ds @?= []
        case bookDocs book of
          [Document _ [_, _, _, Block _ _ _ (Paragraph Nothing is)]] -> is @?= [Resolved (sp 1 4) RefTitle "f" [Text (sp 1 4) "代替"], Resolved (sp 1 5) RefTitle "c" [Text (sp 1 5) "設定"]]
          other -> assertFailure (show other),
      testCase "listing numbers: per chapter, apart from figures, only with a caption (golem-driver ADR 0023)" $ do
        let fig s = Block (sp 1 s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False False))
            code s cap = Block (sp 1 s) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing cap False [CodeLine "x" (Just 1) Nothing False [] Nothing] False))
            capt t = Just [Text (sp 1 0) t]
            docs =
              [ Document
                  (FileId 1)
                  [heading 1 0 1 noHeadingAttrs Nothing "一", fig 1, code 2 (capt "a"), code 3 Nothing, code 4 (capt "b"), heading 1 5 1 noHeadingAttrs Nothing "二", code 6 (capt "c")]
              ]
            (book, ds) = assemble cfg noEval docs
        ds @?= []
        Map.toAscList (bookListings book) @?= [(sp 1 2, "リスト1-1"), (sp 1 4, "リスト1-2"), (sp 1 6, "リスト2-1")]
        Map.elems (bookFigures book) @?= ["図1-1"],
      testCase "G04004: a captioned code block outside a chapter; not with a format without {chapter} (golem-driver ADR 0023)" $ do
        let code = Block (sp 1 0) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 0) "a"]) False [] False))
            plain = Block (sp 1 1) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing Nothing False [] False))
        map summary (snd (assemble cfg noEval [Document (FileId 1) [code, plain]]))
          @?= [("G04004", Error, sp 1 0, "章の外にある図版、表、コードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります。番号を振らないなら @nonumber を付けます", [])]
        snd (assemble cfg {acListingFormat = "リスト{n}"} noEval [Document (FileId 1) [code]]) @?= []
        Map.elems (bookListings (fst (assemble cfg {acListingFormat = "リスト{n}"} noEval [Document (FileId 1) [code]]))) @?= ["リスト1"],
      testCase "references to a captioned code block; ref-number to one without a caption is G04005 (golem-driver ADR 0023)" $ do
        let code s lbl cap = Block (sp 1 s) (Just lbl) Nothing (CodeBlock (Code Nothing Nothing Nothing cap False [] False))
            docs =
              [ Document
                  (FileId 1)
                  [ heading 1 0 1 noHeadingAttrs Nothing "一",
                    code 1 "a" (Just [Text (sp 1 1) "設定"]),
                    code 2 "b" Nothing,
                    para 1 3 [Ref (sp 1 4) RefNumber "a", Ref (sp 1 5) RefTitle "a"]
                  ]
              ]
            (book, ds) = assemble cfg noEval docs
        ds @?= []
        case bookDocs book of
          [Document _ [_, _, _, Block _ _ _ (Paragraph Nothing is)]] -> is @?= [Resolved (sp 1 4) RefNumber "a" [Text (sp 1 4) "1-1"], Resolved (sp 1 5) RefTitle "a" [Text (sp 1 5) "設定"]]
          other -> assertFailure (show other)
        map summary (snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", code 2 "b" Nothing, para 1 3 [Ref (sp 1 4) RefNumber "b"]]]))
          @?= [("G04005", Error, sp 1 4, "番号を持たない要素への参照です: b", [])],
      testCase "G04005: ref-number to an unnumbered heading; ref-title to it is fine" $ do
        let h = heading 1 0 1 noHeadingAttrs {haNoNumber = True} (Just "pre") "まえがき"
            (book, ds) = assemble cfg noEval [Document (FileId 1) [h, para 1 5 [Ref (sp 1 6) RefNumber "pre"]]]
        map summary ds @?= [("G04005", Error, sp 1 6, "番号を持たない要素への参照です: pre", [])]
        case bookDocs book of
          [Document _ [_, Block _ _ _ (Paragraph Nothing is)]] -> is @?= []
          other -> assertFailure (show other)
        snd (assemble cfg noEval [Document (FileId 1) [h, para 1 5 [Ref (sp 1 6) RefTitle "pre"]]]) @?= [],
      testCase "G04006: ref-title to an element without a title" $ do
        let p = Block (sp 1 0) (Just "p") Nothing (Paragraph Nothing [Text (sp 1 0) "本文"])
            (book, ds) = assemble cfg noEval [Document (FileId 1) [p, para 1 5 [Ref (sp 1 6) RefTitle "p"]]]
        map summary ds @?= [("G04006", Error, sp 1 6, "題を持たない要素への参照です: p", [])]
        case bookDocs book of
          [Document _ [_, Block _ _ _ (Paragraph Nothing is)]] -> is @?= []
          other -> assertFailure (show other)
        snd (assemble cfg noEval [Document (FileId 1) [p, para 1 5 [Ref (sp 1 6) RefPage "p"]]]) @?= []
        let h = heading 1 0 1 noHeadingAttrs (Just "h") "一"
            f = Block (sp 1 2) (Just "f") Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False False))
        snd (assemble cfg noEval [Document (FileId 1) [h, f, para 1 5 [Ref (sp 1 6) RefTitle "h", Ref (sp 1 7) RefTitle "f"]]]) @?= []
    ]

summary :: Diagnostic -> (Text, Severity, SrcSpan, Text, [(SrcSpan, Text)])
summary d = let DiagnosticCode c = diagCode d in (c, diagSeverity d, diagSpan d, diagMessage d, diagRelated d)

-- | The notices of the assembly (golem-syntax ADR 0002).
noticeTests :: TestTree
noticeTests =
  testGroup
    "notices (golem-syntax ADR 0002)"
    [ testCase "G04007: @number on the first item of a list equal to 1" $ do
        let ds = notices [Document (FileId 1) [olist 1 0 [Just 1, Nothing]]]
        ds @?= [("G04007", "@number 1 は自動で振られる番号と同じです", sp 1 0)],
      testCase "G04007: @number 3 on the third item, which continues the list before it" $ do
        notices [Document (FileId 1) [olist 1 0 [Nothing, Nothing], olist 1 10 [Just 3]]] @?= [("G04007", "@number 3 は自動で振られる番号と同じです", sp 1 10)]
        notices [Document (FileId 1) [olist 1 0 [Nothing, Nothing], olist 1 10 [Just 5]]] @?= []
        -- a list after a paragraph starts from 1
        notices [Document (FileId 1) [olist 1 0 [Nothing, Nothing], para 1 5 [], olist 1 10 [Just 3]]] @?= [],
      testCase "G04007 points at the @number line when its span is known" $ do
        let c = cfg {acNumberSites = Map.fromList [(sp 1 10, mkSpan (FileId 1) 6 9)]}
            (_, ds) = assemble c noEval [Document (FileId 1) [olist 1 0 [Nothing, Nothing], olist 1 10 [Just 3]]]
        [(diagCode d, diagSeverity d, diagSpan d) | d <- ds] @?= [(DiagnosticCode "G04007", Notice, mkSpan (FileId 1) 6 9)],
      testCase "G04007: a heading whose @number is the automatic number" $ do
        notices [Document (FileId 1) [heading 1 0 1 noHeadingAttrs {haNumber = Just 1} Nothing "一"]] @?= [("G04007", "@number 1 は自動で振られる番号と同じです", sp 1 0)]
        notices [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", heading 1 5 1 noHeadingAttrs {haNumber = Just 5} Nothing "五"]] @?= []
        -- @nonumber takes no number: the heading after it is 2 by itself
        notices
          [ Document
              (FileId 1)
              [ heading 1 0 1 noHeadingAttrs Nothing "一",
                heading 1 5 1 noHeadingAttrs {haNoNumber = True} Nothing "間",
                heading 1 10 1 noHeadingAttrs {haNumber = Just 2} Nothing "二"
              ]
          ]
          @?= [("G04007", "@number 2 は自動で振られる番号と同じです", sp 1 10)]
        -- across files
        notices [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一"], Document (FileId 2) [heading 2 0 1 noHeadingAttrs {haNumber = Just 2} Nothing "二"]] @?= [("G04007", "@number 2 は自動で振られる番号と同じです", sp 2 0)],
      testCase "G04008: page breaks at the end of the last file" $ do
        notices [Document (FileId 1) [para 1 0 [], brk 1 5 BreakPage]] @?= [("G04008", "本の最後の改ページは効果がありません", sp 1 5)]
        notices [Document (FileId 1) [para 1 0 [], brk 1 5 BreakPage], Document (FileId 2) [para 2 0 []]] @?= []
        notices [Document (FileId 1) [para 1 0 [], brk 1 5 BreakPage, brk 1 10 BreakColumn]]
          @?= [("G04008", "本の最後の改ページは効果がありません", sp 1 5), ("G04008", "本の最後の改ページは効果がありません", sp 1 10)]
        notices [Document (FileId 1) [brk 1 0 BreakPage, para 1 5 []]] @?= [],
      testCase "G04009: blank lines at the end of the book are dropped (docs/adr ADR 0046)" $ do
        let g04009 f s = ("G04009", "本の最後の @blank-line は効果がありません", sp f s)
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 1]] @?= [g04009 1 5]
        books [Document (FileId 1) [para 1 0 [], blank 1 5 1]] @?= [[para 1 0 []]]
        -- with only breaks after it
        filter (\(c, _, _) -> c == "G04009") (notices [Document (FileId 1) [para 1 0 [], blank 1 5 1, brk 1 10 BreakPage]]) @?= [g04009 1 5]
        -- across the files, the blank lines of the end of the book
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 2], Document (FileId 2) [blank 2 0 1, ctl 2 5 (NeedLines 3)]] @?= [g04009 1 5, g04009 2 0]
        -- a blank line at the end of a file comes before the first block of the next file
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 1], Document (FileId 2) [para 2 0 []]] @?= []
        books [Document (FileId 1) [para 1 0 [], blank 1 5 1], Document (FileId 2) [para 2 0 []]] @?= [[para 1 0 [], blank 1 5 1], [para 2 0 []]],
      testCase "G04010: blank lines right before a page or column break are dropped (docs/adr ADR 0046)" $ do
        let page s = ("G04010", "@blank-line の直後に @page-break があります", sp 1 s)
            column s = ("G04010", "@blank-line の直後に @column-break があります", sp 1 s)
        warnings [Document (FileId 1) [para 1 0 [], blank 1 5 1, brk 1 10 BreakPage, para 1 15 []]] @?= [page 5]
        books [Document (FileId 1) [para 1 0 [], blank 1 5 1, brk 1 10 BreakPage, para 1 15 []]] @?= [[para 1 0 [], brk 1 10 BreakPage, para 1 15 []]]
        warnings [Document (FileId 1) [blank 1 0 1, brk 1 5 BreakPage, para 1 10 []]] @?= [page 0]
        warnings [Document (FileId 1) [para 1 0 [], blank 1 5 1, ctl 1 10 (NeedLines 3), brk 1 15 BreakColumn, para 1 20 []]] @?= [column 5]
        warnings [Document (FileId 1) [para 1 0 [], blank 1 5 1, blank 1 10 2, brk 1 15 BreakRecto, para 1 20 []]] @?= [page 5, page 10]
        -- across the files
        let twoFiles = [Document (FileId 1) [para 1 0 [], blank 1 5 1], Document (FileId 2) [brk 2 0 BreakPage, para 2 5 []]]
        warnings twoFiles @?= [page 5]
        books twoFiles @?= [[para 1 0 []], [brk 2 0 BreakPage, para 2 5 []]]
        -- a blank line after a break is no error
        warnings [Document (FileId 1) [brk 1 0 BreakPage, blank 1 5 1, para 1 10 []]] @?= []
        books [Document (FileId 1) [brk 1 0 BreakPage, blank 1 5 1, para 1 10 []]] @?= [[brk 1 0 BreakPage, blank 1 5 1, para 1 10 []]],
      testCase "G04011: blank lines of as many lines as a page or more are dropped (docs/adr ADR 0047)" $ do
        let g04011 f s n = ("G04011", "@blank-line の行数 " <> T.pack (show (n :: Int)) <> " がページの行数 16 以上なので捨てます", sp f s)
            only c = filter (\(c', _, _) -> c' == c)
        -- fewer lines than a page stay
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 15, para 1 10 []]] @?= []
        books [Document (FileId 1) [para 1 0 [], blank 1 5 15, para 1 10 []]] @?= [[para 1 0 [], blank 1 5 15, para 1 10 []]]
        -- as many lines as a page are dropped
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 16, para 1 10 []]] @?= [g04011 1 5 16]
        books [Document (FileId 1) [para 1 0 [], blank 1 5 16, para 1 10 []]] @?= [[para 1 0 [], para 1 10 []]]
        -- blank lines written in a row count by their sum, each with a notice
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 10, blank 1 10 6, para 1 15 []]] @?= [g04011 1 5 16, g04011 1 10 16]
        books [Document (FileId 1) [para 1 0 [], blank 1 5 10, blank 1 10 6, para 1 15 []]] @?= [[para 1 0 [], para 1 15 []]]
        -- controls of page breaks between them keep the run
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 10, ctl 1 10 (NeedLines 3), blank 1 15 6, para 1 20 []]] @?= [g04011 1 5 16, g04011 1 15 16]
        books [Document (FileId 1) [para 1 0 [], blank 1 5 10, ctl 1 10 (NeedLines 3), blank 1 15 6, para 1 20 []]] @?= [[para 1 0 [], ctl 1 10 (NeedLines 3), para 1 20 []]]
        -- a paragraph between them breaks the run
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 10, para 1 10 [], blank 1 15 6, para 1 20 []]] @?= []
        books [Document (FileId 1) [para 1 0 [], blank 1 5 10, para 1 10 [], blank 1 15 6, para 1 20 []]] @?= [[para 1 0 [], blank 1 5 10, para 1 10 [], blank 1 15 6, para 1 20 []]]
        -- G04010 comes first, and the blank line has no G04011
        let beforeBreak = [Document (FileId 1) [para 1 0 [], blank 1 5 20, brk 1 10 BreakPage, para 1 15 []]]
        only "G04011" (notices beforeBreak) @?= []
        warnings beforeBreak @?= [("G04010", "@blank-line の直後に @page-break があります", sp 1 5)]
        -- G04009 comes first, and the blank line has no G04011
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 20]] @?= [("G04009", "本の最後の @blank-line は効果がありません", sp 1 5)]
        -- across the files, by the sum
        let twoFiles = [Document (FileId 1) [para 1 0 [], blank 1 5 10], Document (FileId 2) [blank 2 0 6, para 2 5 []]]
        notices twoFiles @?= [g04011 1 5 16, g04011 2 0 16]
        books twoFiles @?= [[para 1 0 []], [para 2 5 []]]
    ]
  where
    notices docs = [(c, diagMessage d, diagSpan d) | d <- snd (assemble cfg noEval docs), diagSeverity d == Notice, let DiagnosticCode c = diagCode d]
    warnings docs = [(c, diagMessage d, diagSpan d) | d <- snd (assemble cfg noEval docs), diagSeverity d == Warning, let DiagnosticCode c = diagCode d]
    books docs = map docBlocks (bookDocs (fst (assemble cfg noEval docs)))
    blank f s n = Block (sp f s) Nothing Nothing (BlankLines n)
    ctl f s c = Block (sp f s) Nothing Nothing (PageControl c)
    olist f s ns = Block (sp f s) Nothing Nothing (OrderedList [ListItem n [para f (s + 1) []] | n <- ns])
    brk f s k = Block (sp f s) Nothing Nothing (ForcedBreak k)

-- | Renumbering notes in S1 (golem-driver ADR 0018).
noteNumberTests :: TestTree
noteNumberTests =
  testGroup
    "note numbers (golem-driver ADR 0018)"
    [ testCase "per file" $ numbers NumberPerFile three @?= [1, 2, 1, 2, 1, 2],
      testCase "per chapter of the manifest" $ numbers NumberPerChapter three @?= [1, 2, 3, 4, 1, 2],
      testCase "through the book" $ numbers NumberPerBook three @?= [1 .. 6],
      testCase "footnotes and sidenotes count apart" $ do
        let mixed =
              [ Document (FileId 1) [para 1 0 [note 1 1 1, side 1 2 1, note 1 3 2]],
                Document (FileId 2) [para 2 0 [side 2 1 1, note 2 2 1]]
              ]
        marks NumberPerBook [0, 0] mixed @?= [("n", 1), ("s", 1), ("n", 2), ("s", 2), ("n", 3)]
        marks NumberPerFile [0, 0] mixed @?= [("n", 1), ("s", 1), ("n", 2), ("s", 1), ("n", 1)],
      testCase "the span and the body stay" $ do
        let out = allNotes NumberPerBook [0, 0, 1] three
        [(s', b) | Note s' _ b <- out] @?= [(s', b) | Note s' _ b <- allNotes NumberPerFile [0, 0, 1] three]
        [s' | Note s' _ _ <- out] @?= [sp f s | f <- [1, 2, 3], s <- [1, 2]]
        [b | Note _ _ b <- out] @?= [noteBody (sp f s) [Text (sp f s) "注"] | f <- [1, 2, 3], s <- [1, 2]],
      testCase "notes inside containers and list items are renumbered" $ do
        let docs =
              [ Document (FileId 1) [para 1 0 [note 1 1 1]],
                Document (FileId 2) [Block (sp 2 0) Nothing Nothing (BulletList [ListItem Nothing [para 2 1 [Kenten (sp 2 2) (Just "sesame") [note 2 3 1]]]])]
              ]
        numbersOf NumberPerBook [0, 0] docs @?= [1, 2]
    ]
  where
    note f s n = Note (sp f s) n (noteBody (sp f s) [Text (sp f s) "注"])
    side f s n = Sidenote (sp f s) n (noteBody (sp f s) [Text (sp f s) "傍"])
    three = [Document (FileId f) [para f 0 [note f 1 1, note f 2 2]] | f <- [1, 2, 3]]
    numbers m = numbersOf m [0, 0, 1]
    numbersOf m ch docs = [n | Note _ n _ <- allNotes m ch docs]
    allNotes m ch docs = [i | (k, i) <- collect m ch docs, k == "n"]
    marks m ch docs = [(k, numOf i) | (k, i) <- collect m ch docs]
    numOf = \case
      Note _ n _ -> n
      Sidenote _ n _ -> n
      _ -> 0
    collect m ch docs =
      let book = fst (assemble cfg {acNoteNumbering = m, acChapterOf = ch} noEval docs)
       in concatMap (\(Document _ bs) -> concatMap notesOf bs) (bookDocs book)
    notesOf (Block _ _ _ body) = case body of
      Paragraph _ is -> concatMap inl is
      BulletList items -> concatMap (concatMap notesOf . itemBlocks) items
      _ -> []
    inl i = case i of
      Note {} -> [("n" :: Text, i)]
      Sidenote {} -> [("s", i)]
      Kenten _ _ xs -> concatMap inl xs
      _ -> []

-- | Numbers the formats of headings, figures and code blocks cannot write (docs/adr/0213).
unwritableTests :: TestTree
unwritableTests =
  testGroup
    "numbers the number formats cannot write (docs/adr/0213)"
    [ testCase "N1, N3: the 51st heading of {n:circled} is G04012 at the heading and has no number text" $ do
        let c = cfg {acHeadingFormats = Map.fromList [(1, "{n:circled}")]}
            docs = [Document (FileId 1) [heading 1 i 1 noHeadingAttrs Nothing "章" | i <- [0 .. 50]]]
            (book, ds) = assemble c noEval docs
        map summary ds @?= [("G04012", Error, sp 1 50, "[headings.1] の number {n:circled} の {n:circled} では、51 を表せません", [])]
        hiNumberText <$> Map.lookup (sp 1 50) (bookHeadings book) @?= Just Nothing
        hiNumberText <$> Map.lookup (sp 1 49) (bookHeadings book) @?= Just (Just "㊿"),
      testCase "N1: a heading of @number 0 in {n:circled} is G04012" $ do
        let c = cfg {acHeadingFormats = Map.fromList [(1, "{n:circled}")]}
        map summary (snd (assemble c noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs {haNumber = Just 0} Nothing "零"]]))
          @?= [("G04012", Error, sp 1 0, "[headings.1] の number {n:circled} の {n:circled} では、0 を表せません", [])],
      testCase "N1, N3: {1:upper-roman} of a level 2 heading with level 1 skipped is G04012 for the first slot" $ do
        let c = cfg {acHeadingFormats = Map.fromList [(2, "{1:upper-roman}-{n:circled}")]}
        map summary (snd (assemble c noEval [Document (FileId 1) [heading 1 0 2 noHeadingAttrs {haNumber = Just 51} Nothing "節"]]))
          @?= [("G04012", Error, sp 1 0, "[headings.2] の number {1:upper-roman}-{n:circled} の {1:upper-roman} では、0 を表せません", [])],
      testCase "N1: the 8th figure of {n:note-symbols} is G04013 at the figure" $ do
        let fig s' = Block (sp 1 s') Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False False))
            (book, ds) = assemble cfg {acFigureFormat = "図{n:note-symbols}"} noEval [Document (FileId 1) (heading 1 0 1 noHeadingAttrs Nothing "一" : map fig [1 .. 8])]
        map summary ds @?= [("G04013", Error, sp 1 8, "[figures] の number 図{n:note-symbols} の {n:note-symbols} では、8 を表せません", [])]
        Map.lookup (sp 1 8) (bookFigures book) @?= Nothing
        Map.lookup (sp 1 7) (bookFigures book) @?= Just "図#",
      testCase "N1: a code block of {chapter:iroha} in the 48th chapter is G04014 at the code block" $ do
        let code = Block (sp 1 1) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 1) "a"]) False [] False))
            (book, ds) = assemble cfg {acListingFormat = "リスト{chapter:iroha}-{n}"} noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs {haNumber = Just 48} Nothing "章", code]]
        map summary ds @?= [("G04014", Error, sp 1 1, "[code] の number リスト{chapter:iroha}-{n} の {chapter:iroha} では、48 を表せません", [])]
        bookListings book @?= Map.empty,
      testCase "N2: the 50th heading of {n:circled} and a @nonumber heading report nothing" $ do
        let c = cfg {acHeadingFormats = Map.fromList [(1, "{n:circled}")]}
            docs = [Document (FileId 1) ([heading 1 i 1 noHeadingAttrs Nothing "章" | i <- [0 .. 49]] <> [heading 1 50 1 noHeadingAttrs {haNoNumber = True} Nothing "付録"])]
        snd (assemble c noEval docs) @?= []
    ]
