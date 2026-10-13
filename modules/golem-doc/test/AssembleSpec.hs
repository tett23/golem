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
cfg = AssembleConfig (Map.fromList [(1, "第{n:kanji}章")]) "図{chapter}-{n}"

sp :: Int -> Int -> SrcSpan
sp f s = mkSpan (FileId f) s (s + 1)

heading :: Int -> Int -> Int -> HeadingAttrs -> Maybe Text -> Text -> Block
heading f s l a lbl t = Block (sp f s) lbl (Heading l a [Text (sp f s) t])

para :: Int -> Int -> [Inline] -> Block
para f s is = Block (sp f s) Nothing (Paragraph is)

noEval :: DocValues -> DeferredExpr -> Either Diagnostic Text
noEval dv _ = Right ("count=" <> T.pack (show (dvChapterCount dv)))

codes :: [Diagnostic] -> [Text]
codes = map (\d -> let DiagnosticCode c = diagCode d in c)

tests :: TestTree
tests =
  testGroup
    "assembly, S1 (ADR 0002)"
    [ testCase "kanji numerals" $ do
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
          [_, Document _ [Block _ _ (Paragraph is)]] -> is @?= [Number (sp 2 0) 1 Nothing, Text (sp 2 1) "はじめに", Ref (sp 2 2) RefPage "intro"]
          other -> assertFailure (show other)
        codes (snd (assemble cfg noEval [Document (FileId 1) [heading 1 0 1 noHeadingAttrs (Just "a") "x", heading 1 5 1 noHeadingAttrs (Just "a") "y"]])) @?= ["G0401"]
        codes (snd (assemble cfg noEval [Document (FileId 1) [para 1 0 [Ref (sp 1 0) RefTitle "nope"]]])) @?= ["G0403"],
      testCase "deferred expressions see the chapter count" $ do
        let docs = [Document (FileId 1) [heading 1 0 1 noHeadingAttrs Nothing "a", heading 1 5 1 noHeadingAttrs Nothing "b", para 1 9 [Deferred (sp 1 9) (DeferredExpr undefined)]]]
        case bookDocs (fst (assemble cfg noEval docs)) of
          [Document _ [_, _, Block _ _ (Paragraph is)]] -> is @?= [Text (sp 1 9) "count=2"]
          other -> assertFailure (show other),
      testCase "figure numbers restart per chapter" $ do
        let fig f s = Block (sp f s) Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing []))
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
            docs = [Document (FileId 1) [para 1 0 [mark 0 "ガ" "が", mark 1 "カ" "か", mark 2 "パ" "ぱ", mark 3 "ハ" "は", mark 4 "バ" "ば", mark 5 "API" "API", mark 6 "ツ" "つ", mark 7 "ッ" "っ", mark 8 "カ" "か"]]]
            book = fst (assemble cfg noEval docs)
        map igTerms (bookIndex book) @?= [["API"], ["カ"], ["ガ"], ["ツ"], ["ッ"], ["ハ"], ["バ"], ["パ"]]
        map (length . igLocations) (bookIndex book) @?= [1, 2, 1, 1, 1, 1, 1, 1]
        compare (collationKey "かー") (collationKey "かあ") @?= EQ,
      testCase "citations are numbered in order of first citation" $ do
        let docs = [Document (FileId 1) [para 1 0 [Cite (sp 1 0) "b", Cite (sp 1 1) "a", Cite (sp 1 2) "b"]]]
        bookCitations (fst (assemble cfg noEval docs)) @?= [("b", 1), ("a", 2)]
    ]
