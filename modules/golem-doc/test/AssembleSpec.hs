module AssembleSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.Collation
import Golem.Doc.IR
import Golem.Doc.Numerals
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

cfg :: AssembleConfig
cfg = AssembleConfig (Map.fromList [(1, "第{n:kanji}章")]) "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}"

sp :: Int -> Int -> SrcSpan
sp f s = mkSpan (FileId f) s (s + 1)

heading :: Int -> Int -> Int -> HeadingAttrs -> Maybe Text -> Text -> Block
heading f s l a lbl t = Block (sp f s) lbl (Heading l a [Text (sp f s) t])

para :: Int -> Int -> [Inline] -> Block
para f s is = Block (sp f s) Nothing (Paragraph Nothing is)

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
      testCase "labels: cross-file references, duplicates, missing" $ do
        let docs =
              [ Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "intro") "はじめに"],
                Document (FileId 2) [para 2 0 [Ref (sp 2 0) RefNumber "intro", Ref (sp 2 1) RefTitle "intro", Ref (sp 2 2) RefPage "intro"]]
              ]
            (book, ds) = assemble cfg noEval docs
        ds @?= []
        case bookDocs book of
          [_, Document _ [Block _ _ (Paragraph Nothing is)]] -> is @?= [Number (sp 2 0) 1 Nothing, Text (sp 2 1) "はじめに", Ref (sp 2 2) RefPage "intro"]
          other -> assertFailure (show other)
        codes (snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x", heading 1 5 1 noHeadingAttrs (Just "a") "y"]])) @?= ["G0401"]
        codes (snd (assemble cfg noEval [Document (FileId 1) [para 1 0 [Ref (sp 1 0) RefTitle "nope"]]])) @?= ["G0403"],
      testCase "deferred expressions see the chapter count" $ do
        let docs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "a", heading 1 5 1 noHeadingAttrs Nothing "b", para 1 9 [Deferred (sp 1 9) (DeferredExpr undefined)]]]
        case bookDocs (fst (assemble cfg noEval docs)) of
          [Document _ [_, _, Block _ _ (Paragraph Nothing is)]] -> is @?= [Text (sp 1 9) "count=2"]
          other -> assertFailure (show other),
      testCase "figure numbers restart per chapter" $ do
        let fig f s = Block (sp f s) Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing))
            docs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", fig 1 2, fig 1 4, heading 1 6 1 noHeadingAttrs Nothing "二", fig 1 8]]
            (book, ds) = assemble cfg noEval docs
        ds @?= []
        Map.elems (bookFigures book) @?= ["図1-1", "図1-2", "図2-1"]
        codes (snd (assemble cfg noEval [Document (FileId 1) [fig 1 0]])) @?= ["G0404"],
      testCase "only one @toc" $ do
        let toc s = Block (sp 1 s) Nothing (ChannelOutput (TocOutput 2))
        codes (snd (assemble cfg noEval [Document (FileId 1) [toc 0, toc 5]])) @?= ["G0402"],
      testCase "toc entries carry the span of their heading block (golem-driver ADR 0009)" $ do
        let toc = Block (sp 1 0) Nothing (ChannelOutput (TocOutput 2))
            docs = [Document (FileId 1) [toc, heading 1 10 1 noHeadingAttrs Nothing "一", heading 1 20 2 noHeadingAttrs Nothing "節", heading 1 30 1 noHeadingAttrs {haNoToc = True} Nothing "外"]]
            book = fst (assemble cfg noEval docs)
        map teSpan (bookToc book) @?= [sp 1 10, sp 1 20]
        all ((`Map.member` bookHeadings book) . teSpan) (bookToc book) @?= True
        assertBool "notoc" (sp 1 30 `notElem` map teSpan (bookToc book)),
      testCase "index order: kana, voicing, small kana, long vowel, latin before kana" $ do
        let mark s t r = IndexMark (sp 1 s) (IndexEntry [t] [r])
            docs = [Document (FileId 1) [para 1 0 [mark 0 "ガ" "が", mark 1 "カ" "か", mark 2 "パ" "ぱ", mark 3 "ハ" "は", mark 4 "バ" "ば", mark 5 "API" "API", mark 6 "ツ" "つ", mark 7 "ッ" "っ", mark 8 "カ" "か"], Block (sp 1 50) Nothing (ChannelOutput IndexOutput)]]
            book = fst (assemble cfg noEval docs)
        map igTerms (concatMap snd (bookIndexes book)) @?= [["API"], ["カ"], ["ガ"], ["ツ"], ["ッ"], ["ハ"], ["バ"], ["パ"]]
        map (length . igLocations) (concatMap snd (bookIndexes book)) @?= [1, 2, 1, 1, 1, 1, 1, 1]
        compare (collationKey "かー") (collationKey "かあ") @?= EQ,
      testCase "citations are numbered in order of first citation" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) "b", Cite (sp 1 1) "a", Cite (sp 1 2) "b"]]]
        bookBibliographies (fst (assemble cfg noEval docs)) @?= [(Nothing, [("b", 1), ("a", 2)])],
      multipleListTests,
      diagnosticCodes
    ]

-- | Several @index and @bibliography in a book (golem-doc ADR 0008).
multipleListTests :: TestTree
multipleListTests =
  testGroup
    "several @index and @bibliography (golem-doc ADR 0008)"
    [ testCase "one @bibliography lists every citation wherever it is" $ do
        let cites = para 1 10 [Cite (sp 1 10) "b", Cite (sp 1 11) "a", Cite (sp 1 12) "b"]
            more = para 1 20 [Cite (sp 1 20) "c"]
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
              [ Document (FileId 1) [para 1 0 [Cite (sp 1 0) "A", Cite (sp 1 1) "B"], bib 1 5],
                Document (FileId 2) [para 2 0 [Cite (sp 2 0) "B", Cite (sp 2 1) "C"], bib 2 5]
              ]
            book = fst (assemble cfg noEval docs)
        bookBibliographies book
          @?= [ (Just (FileId 1, sp 1 5), [("A", 1), ("B", 2)]),
                (Just (FileId 2, sp 2 5), [("B", 1), ("C", 2)])
              ]
        Map.lookup (FileId 2, sp 2 0) (bookCiteMarks book) @?= Just (Just (FileId 2, sp 2 5), 1)
        Map.lookup (FileId 1, sp 1 1) (bookCiteMarks book) @?= Just (Just (FileId 1, sp 1 5), 2),
      testCase "citations after the last @bibliography go to the last one" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) "A"], bib 1 5, para 1 6 [Cite (sp 1 6) "B"], bib 1 10, para 1 12 [Cite (sp 1 12) "C", Cite (sp 1 13) "B"]]]
            book = fst (assemble cfg noEval docs)
        map snd (bookBibliographies book) @?= [[("A", 1)], [("B", 1), ("C", 2)]]
        Map.lookup (FileId 1, sp 1 12) (bookCiteMarks book) @?= Just (Just (FileId 1, sp 1 10), 2),
      testCase "a citation in a footnote is at the paragraph of the note" $ do
        let docs = [Document (FileId 1) [para 1 0 [Text (sp 1 0) "a", Note (sp 1 1) 1 [Cite (sp 1 2) "N"]], bib 1 5, para 1 6 [Cite (sp 1 6) "M"], bib 1 10]]
            book = fst (assemble cfg noEval docs)
        map snd (bookBibliographies book) @?= [[("N", 1)], [("M", 1)]],
      testCase "each @index has the marks of its own range" $ do
        let mark f s t = IndexMark (sp f s) (IndexEntry [t] [t])
            idx f s = Block (sp f s) Nothing (ChannelOutput IndexOutput)
            docs =
              [ Document (FileId 1) [para 1 0 [mark 1 0 "か", mark 1 1 "あ"], idx 1 5],
                Document (FileId 2) [para 2 0 [mark 2 0 "か"], idx 2 5, para 2 6 [mark 2 6 "さ"]]
              ]
            book = fst (assemble cfg noEval docs)
        [(at, [(igTerms g, igLocations g) | g <- gs]) | (at, gs) <- bookIndexes book]
          @?= [ ((FileId 1, sp 1 5), [(["あ"], [(FileId 1, sp 1 1)]), (["か"], [(FileId 1, sp 1 0)])]),
                ((FileId 2, sp 2 5), [(["か"], [(FileId 2, sp 2 0)]), (["さ"], [(FileId 2, sp 2 6)])])
              ],
      testCase "without @bibliography, one list without a place numbers the whole book" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) "b"]], Document (FileId 2) [para 2 0 [Cite (sp 2 0) "a", Cite (sp 2 1) "b"]]]
            book = fst (assemble cfg noEval docs)
        bookBibliographies book @?= [(Nothing, [("b", 1), ("a", 2)])]
        Map.lookup (FileId 2, sp 2 1) (bookCiteMarks book) @?= Just (Nothing, 1),
      testCase "two @toc are still G0402" $ do
        let toc s = Block (sp 1 s) Nothing (ChannelOutput (TocOutput 2))
        codes (snd (assemble cfg noEval [Document (FileId 1) [toc 0, bib 1 2, bib 1 3, toc 5]])) @?= ["G0402"]
    ]
  where
    bib f s = Block (sp f s) Nothing (ChannelOutput BibliographyOutput)

-- | The diagnostics of document assembly (golem-doc ADR 0003).
diagnosticCodes :: TestTree
diagnosticCodes =
  testGroup
    "diagnostic codes (golem-doc ADR 0003)"
    [ testCase "G0401: every later duplicate, related to the first definition" $ do
        let ds = snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x", heading 1 5 1 noHeadingAttrs (Just "a") "y", heading 1 9 1 noHeadingAttrs (Just "a") "z"]])
        map summary ds
          @?= [ ("G0401", Error, sp 1 5, "ラベルが重複しています: a", [(sp 1 0, "最初の定義")]),
                ("G0401", Error, sp 1 9, "ラベルが重複しています: a", [(sp 1 0, "最初の定義")])
              ]
        let cross = snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x"], Document (FileId 2) [heading 2 0 1 noHeadingAttrs (Just "a") "y"]])
        map summary cross @?= [("G0401", Error, sp 2 0, "ラベルが重複しています: a", [(sp 1 0, "最初の定義")])],
      testCase "G0402: every later @toc, related to the first" $ do
        let toc s = Block (sp 1 s) Nothing (ChannelOutput (TocOutput 2))
            ds = snd (assemble cfg noEval [Document (FileId 1) [toc 0, toc 5, toc 9]])
        map summary ds
          @?= [ ("G0402", Error, sp 1 5, "@toc は文書に一つだけ置けます", [(sp 1 0, "最初の @toc")]),
                ("G0402", Error, sp 1 9, "@toc は文書に一つだけ置けます", [(sp 1 0, "最初の @toc")])
              ],
      testCase "G0403: references of every kind to a missing label, also inside a list item" $ do
        let refs = [Ref (sp 1 1) RefNumber "nope", Ref (sp 1 2) RefTitle "nope", Ref (sp 1 3) RefPage "nope"]
            listed = Block (sp 1 4) Nothing (BulletList [ListItem Nothing [para 1 5 [Ref (sp 1 6) RefNumber "gone"]]])
            (book, ds) = assemble cfg noEval [Document (FileId 1) [para 1 0 refs, listed]]
        map summary ds
          @?= [ ("G0403", Error, sp 1 1, "存在しないラベルへの参照です: nope", []),
                ("G0403", Error, sp 1 2, "存在しないラベルへの参照です: nope", []),
                ("G0403", Error, sp 1 3, "存在しないラベルへの参照です: nope", []),
                ("G0403", Error, sp 1 6, "存在しないラベルへの参照です: gone", [])
              ]
        case bookDocs book of
          [Document _ (Block _ _ (Paragraph Nothing is) : _)] -> is @?= []
          other -> assertFailure (show other),
      testCase "G0404: figures outside a chapter, before the first and after a @nonumber chapter" $ do
        let fig s = Block (sp 1 s) Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing))
            docs = [Document (FileId 1) [fig 0, heading 1 2 1 noHeadingAttrs Nothing "一", fig 4, heading 1 6 1 noHeadingAttrs {haNoNumber = True} Nothing "あとがき", fig 8]]
            msg = "章の外にある図版とコードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります"
        map summary (snd (assemble cfg noEval docs))
          @?= [("G0404", Error, sp 1 0, msg, []), ("G0404", Error, sp 1 8, msg, [])]
        snd (assemble cfg {acFigureFormat = "{n}"} noEval docs) @?= [],
      testCase "listing numbers: per chapter, apart from figures, only with a caption (golem-driver ADR 0023)" $ do
        let fig s = Block (sp 1 s) Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing))
            code s cap = Block (sp 1 s) Nothing (CodeBlock (Code Nothing Nothing Nothing cap False [CodeLine "x" (Just 1) Nothing False []]))
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
      testCase "G0404: a captioned code block outside a chapter; not with a format without {chapter} (golem-driver ADR 0023)" $ do
        let code = Block (sp 1 0) Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp 1 0) "a"]) False []))
            plain = Block (sp 1 1) Nothing (CodeBlock (Code Nothing Nothing Nothing Nothing False []))
        map summary (snd (assemble cfg noEval [Document (FileId 1) [code, plain]]))
          @?= [("G0404", Error, sp 1 0, "章の外にある図版とコードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります", [])]
        snd (assemble cfg {acListingFormat = "リスト{n}"} noEval [Document (FileId 1) [code]]) @?= []
        Map.elems (bookListings (fst (assemble cfg {acListingFormat = "リスト{n}"} noEval [Document (FileId 1) [code]]))) @?= ["リスト1"],
      testCase "references to a captioned code block; ref-number to one without a caption is G0405 (golem-driver ADR 0023)" $ do
        let code s lbl cap = Block (sp 1 s) (Just lbl) (CodeBlock (Code Nothing Nothing Nothing cap False []))
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
          [Document _ [_, _, _, Block _ _ (Paragraph Nothing is)]] -> is @?= [Text (sp 1 4) "1-1", Text (sp 1 5) "設定"]
          other -> assertFailure (show other)
        map summary (snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一", code 2 "b" Nothing, para 1 3 [Ref (sp 1 4) RefNumber "b"]]]))
          @?= [("G0405", Error, sp 1 4, "番号を持たない要素への参照です: b", [])],
      testCase "G0405: ref-number to an unnumbered heading; ref-title to it is fine" $ do
        let h = heading 1 0 1 noHeadingAttrs {haNoNumber = True} (Just "pre") "まえがき"
            (book, ds) = assemble cfg noEval [Document (FileId 1) [h, para 1 5 [Ref (sp 1 6) RefNumber "pre"]]]
        map summary ds @?= [("G0405", Error, sp 1 6, "番号を持たない要素への参照です: pre", [])]
        case bookDocs book of
          [Document _ [_, Block _ _ (Paragraph Nothing is)]] -> is @?= []
          other -> assertFailure (show other)
        snd (assemble cfg noEval [Document (FileId 1) [h, para 1 5 [Ref (sp 1 6) RefTitle "pre"]]]) @?= [],
      testCase "G0406: ref-title to an element without a title" $ do
        let p = Block (sp 1 0) (Just "p") (Paragraph Nothing [Text (sp 1 0) "本文"])
            (book, ds) = assemble cfg noEval [Document (FileId 1) [p, para 1 5 [Ref (sp 1 6) RefTitle "p"]]]
        map summary ds @?= [("G0406", Error, sp 1 6, "題を持たない要素への参照です: p", [])]
        case bookDocs book of
          [Document _ [_, Block _ _ (Paragraph Nothing is)]] -> is @?= []
          other -> assertFailure (show other)
        snd (assemble cfg noEval [Document (FileId 1) [p, para 1 5 [Ref (sp 1 6) RefPage "p"]]]) @?= []
        let h = heading 1 0 1 noHeadingAttrs (Just "h") "一"
            f = Block (sp 1 2) (Just "f") (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing))
        snd (assemble cfg noEval [Document (FileId 1) [h, f, para 1 5 [Ref (sp 1 6) RefTitle "h", Ref (sp 1 7) RefTitle "f"]]]) @?= []
    ]

summary :: Diagnostic -> (Text, Severity, SrcSpan, Text, [(SrcSpan, Text)])
summary d = let DiagnosticCode c = diagCode d in (c, diagSeverity d, diagSpan d, diagMessage d, diagRelated d)

-- | The notices of the assembly (golem-syntax ADR 0002).
noticeTests :: TestTree
noticeTests =
  testGroup
    "notices (golem-syntax ADR 0002)"
    [ testCase "G0407: @number on the first item of a list equal to 1" $ do
        let ds = notices [Document (FileId 1) [olist 1 0 [Just 1, Nothing]]]
        ds @?= [("G0407", "@number 1 は自動で振られる番号と同じです", sp 1 0)],
      testCase "G0407: @number 3 on the third item, which continues the list before it" $ do
        notices [Document (FileId 1) [olist 1 0 [Nothing, Nothing], olist 1 10 [Just 3]]] @?= [("G0407", "@number 3 は自動で振られる番号と同じです", sp 1 10)]
        notices [Document (FileId 1) [olist 1 0 [Nothing, Nothing], olist 1 10 [Just 5]]] @?= []
        -- a list after a paragraph starts from 1
        notices [Document (FileId 1) [olist 1 0 [Nothing, Nothing], para 1 5 [], olist 1 10 [Just 3]]] @?= [],
      testCase "G0407 points at the @number line when its span is known" $ do
        let c = cfg {acNumberSites = Map.fromList [(sp 1 10, mkSpan (FileId 1) 6 9)]}
            (_, ds) = assemble c noEval [Document (FileId 1) [olist 1 0 [Nothing, Nothing], olist 1 10 [Just 3]]]
        [(diagCode d, diagSeverity d, diagSpan d) | d <- ds] @?= [(DiagnosticCode "G0407", Notice, mkSpan (FileId 1) 6 9)],
      testCase "G0407: a heading whose @number is the automatic number" $ do
        notices [Document (FileId 1) [heading 1 0 1 noHeadingAttrs {haNumber = Just 1} Nothing "一"]] @?= [("G0407", "@number 1 は自動で振られる番号と同じです", sp 1 0)]
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
          @?= [("G0407", "@number 2 は自動で振られる番号と同じです", sp 1 10)]
        -- across files
        notices [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "一"], Document (FileId 2) [heading 2 0 1 noHeadingAttrs {haNumber = Just 2} Nothing "二"]] @?= [("G0407", "@number 2 は自動で振られる番号と同じです", sp 2 0)],
      testCase "G0408: page breaks at the end of the last file" $ do
        notices [Document (FileId 1) [para 1 0 [], brk 1 5 BreakPage]] @?= [("G0408", "本の最後の改ページは効果がありません", sp 1 5)]
        notices [Document (FileId 1) [para 1 0 [], brk 1 5 BreakPage], Document (FileId 2) [para 2 0 []]] @?= []
        notices [Document (FileId 1) [para 1 0 [], brk 1 5 BreakPage, brk 1 10 BreakColumn]]
          @?= [("G0408", "本の最後の改ページは効果がありません", sp 1 5), ("G0408", "本の最後の改ページは効果がありません", sp 1 10)]
        notices [Document (FileId 1) [brk 1 0 BreakPage, para 1 5 []]] @?= [],
      testCase "G0409: blank lines at the end of the book are dropped (docs/adr ADR 0046)" $ do
        let g0409 f s = ("G0409", "本の最後の @blank-line は効果がありません", sp f s)
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 1]] @?= [g0409 1 5]
        books [Document (FileId 1) [para 1 0 [], blank 1 5 1]] @?= [[para 1 0 []]]
        -- with only breaks after it
        filter (\(c, _, _) -> c == "G0409") (notices [Document (FileId 1) [para 1 0 [], blank 1 5 1, brk 1 10 BreakPage]]) @?= [g0409 1 5]
        -- across the files, the blank lines of the end of the book
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 2], Document (FileId 2) [blank 2 0 1, ctl 2 5 (NeedLines 3)]] @?= [g0409 1 5, g0409 2 0]
        -- a blank line at the end of a file comes before the first block of the next file
        notices [Document (FileId 1) [para 1 0 [], blank 1 5 1], Document (FileId 2) [para 2 0 []]] @?= []
        books [Document (FileId 1) [para 1 0 [], blank 1 5 1], Document (FileId 2) [para 2 0 []]] @?= [[para 1 0 [], blank 1 5 1], [para 2 0 []]],
      testCase "G0410: blank lines right before a page or column break are dropped (docs/adr ADR 0046)" $ do
        let page s = ("G0410", "@blank-line の直後に @page-break があります", sp 1 s)
            column s = ("G0410", "@blank-line の直後に @column-break があります", sp 1 s)
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
        books [Document (FileId 1) [brk 1 0 BreakPage, blank 1 5 1, para 1 10 []]] @?= [[brk 1 0 BreakPage, blank 1 5 1, para 1 10 []]]
    ]
  where
    notices docs = [(c, diagMessage d, diagSpan d) | d <- snd (assemble cfg noEval docs), diagSeverity d == Notice, let DiagnosticCode c = diagCode d]
    warnings docs = [(c, diagMessage d, diagSpan d) | d <- snd (assemble cfg noEval docs), diagSeverity d == Warning, let DiagnosticCode c = diagCode d]
    books docs = map docBlocks (bookDocs (fst (assemble cfg noEval docs)))
    blank f s n = Block (sp f s) Nothing (BlankLines n)
    ctl f s c = Block (sp f s) Nothing (PageControl c)
    olist f s ns = Block (sp f s) Nothing (OrderedList [ListItem n [para f (s + 1) []] | n <- ns])
    brk f s k = Block (sp f s) Nothing (ForcedBreak k)

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
        [b | Note _ _ b <- out] @?= [[Text (sp f s) "注"] | f <- [1, 2, 3], s <- [1, 2]],
      testCase "notes inside containers and list items are renumbered" $ do
        let docs =
              [ Document (FileId 1) [para 1 0 [note 1 1 1]],
                Document (FileId 2) [Block (sp 2 0) Nothing (BulletList [ListItem Nothing [para 2 1 [Kenten (sp 2 2) (Just "sesame") [note 2 3 1]]]])]
              ]
        numbersOf NumberPerBook [0, 0] docs @?= [1, 2]
    ]
  where
    note f s n = Note (sp f s) n [Text (sp f s) "注"]
    side f s n = Sidenote (sp f s) n [Text (sp f s) "傍"]
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
       in concatMap (\(Document _ bs) -> concatMap blockNotes bs) (bookDocs book)
    blockNotes (Block _ _ body) = case body of
      Paragraph _ is -> concatMap inl is
      BulletList items -> concatMap (concatMap blockNotes . itemBlocks) items
      _ -> []
    inl i = case i of
      Note {} -> [("n" :: Text, i)]
      Sidenote {} -> [("s", i)]
      Kenten _ _ xs -> concatMap inl xs
      _ -> []
