module Main (main) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Syntax
import Golem.Text
import Test.Tasty
import Test.Tasty.HUnit
import TextOutputSpec (textOutputTests)

main :: IO ()
main = defaultMain tests

lists :: TextLists
lists = TextLists ("・" :| []) Nothing Nothing

-- | One file, a.gm, whose only block is @bibliography, citing @cites@.
renderBibliography :: Map Text [EntryPart] -> [(Text, Int)] -> [(FilePath, Text)]
renderBibliography bib cites = renderBlocks bib cites Map.empty [ChannelOutput BibliographyOutput]

-- | One file, a.gm, of blocks at offsets 0, 1, ... with the listing numbers by offset.
renderBlocks :: Map Text [EntryPart] -> [(Text, Int)] -> Map Int Text -> [BlockBody] -> [(FilePath, Text)]
renderBlocks bib cites listings bodies =
  let (fid, ft) = registerFile "a.gm" emptyFileTable
      book =
        Book
          { bookDocs = [Document fid [Block (mkSpan fid i (i + 1)) Nothing b | (i, b) <- zip [0 ..] bodies]],
            bookHeadings = Map.empty,
            bookFigures = Map.empty,
            bookListings = Map.fromList [(mkSpan fid i (i + 1), t) | (i, t) <- Map.toList listings],
            bookToc = [],
            bookTocDepth = Nothing,
            bookIndexes = [],
            -- the bibliography is the block at offset 0 (golem-doc ADR 0008)
            bookBibliographies = [(Just (fid, mkSpan fid 0 1), cites)],
            bookCiteMarks = Map.empty,
            bookLabels = Map.empty,
            bookReferenced = Set.empty,
            bookChapterOf = []
          }
   in renderText "ja" "kanji" False (const (const 0)) lists bib Horizontal ft book

sp :: Int -> SrcSpan
sp s = mkSpan (FileId 0) s (s + 1)

heading :: Int -> HeadingAttrs -> Text -> Block
heading s a t = Block (sp s) Nothing (Heading 1 a [Text (sp s) t])

figure :: Int -> Text -> Block
figure s cap = Block (sp s) Nothing (FigureBlock (Figure "a.png" Nothing "" Nothing Nothing [Block (sp (s + 1)) Nothing (Paragraph Nothing [Text (sp (s + 1)) cap])] Nothing False))

toc :: Int -> Block
toc s = Block (sp s) Nothing (ChannelOutput (TocOutput 1))

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
noEval _ _ _ = Right ""

-- | The plain text of one file in a book of the language, with the number format of headings.
render :: Text -> Text -> [Block] -> [Text]
render lang format bs =
  let cfg = AssembleConfig (Map.fromList [(1, format)]) "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}"
      (book, _) = assemble cfg noEval [Document (FileId 0) bs]
      (_, ft) = registerFile "a.gm" emptyFileTable
   in concatMap (T.lines . snd) (renderText lang "kanji" False (const (const 0)) lists Map.empty Horizontal ft book)

tests :: TestTree
tests =
  testGroup
    "golem-text"
    [ testCase "@bibliography lists the entries, or the key without one (golem-doc ADR 0004)" $
        renderBibliography (Map.fromList [("jlreq", [EntryText "日本語組版処理の要件、W3C、2020。"])]) [("jlreq", 1), ("missing", 2)]
          @?= [("a.txt", "[1] 日本語組版処理の要件、W3C、2020。\n[2] missing\n")],
      testCase "@bibliography writes the URL and the date of access as text (golem-doc ADR 0005)" $
        renderBibliography (Map.fromList [("jlreq", [EntryText "「日本語組版処理の要件」、W3C、2020、", EntryUrl "https://www.w3.org/TR/jlreq/", EntryText "（2026年10月16日閲覧）。"])]) [("jlreq", 1)]
          @?= [("a.txt", "[1] 「日本語組版処理の要件」、W3C、2020、https://www.w3.org/TR/jlreq/（2026年10月16日閲覧）。\n")],
      testGroup
        "the separator after a number (golem-html ADR 0002)"
        [ testCase "a space in an English book" $
            render "en" "{n}" [heading 0 noHeadingAttrs "Introduction"] @?= ["1 Introduction"],
          testCase "an ideographic space in a Japanese book" $
            render "ja" "第{n:kanji}章" [heading 0 noHeadingAttrs "海"] @?= ["第一章\x3000海"],
          testCase "nothing more after a number format that ends with a space" $
            render "en" "Chapter {n}: " [heading 0 noHeadingAttrs "Introduction"] @?= ["Chapter 1: Introduction"],
          testCase "no separator on an unnumbered heading" $
            render "en" "{n}" [heading 0 noHeadingAttrs {haNoNumber = True} "Preface"] @?= ["Preface"],
          testCase "the table of contents" $ do
            render "en" "{n}" [toc 0, heading 5 noHeadingAttrs "Introduction"] @?= ["1 Introduction", "", "1 Introduction"]
            render "ja" "第{n:kanji}章" [toc 0, heading 5 noHeadingAttrs "海"] @?= ["第一章\x3000海", "", "第一章\x3000海"],
          testCase "captions" $ do
            render "en" "{n}" [heading 0 noHeadingAttrs "A", figure 5 "Cap"] @?= ["1 A", "", "［図1-1 Cap］"]
            render "ja" "{n}" [heading 0 noHeadingAttrs "A", figure 5 "キャプション"] @?= ["1\x3000\&A", "", "［図1-1\x3000キャプション］"]
        ],
      testCase "a code block: the caption, the file, the diff marks and the callouts (golem-driver ADR 0023)" $ do
        let sp0 = mkSpan (FileId 0) 0 0
            code =
              Code
                { codeLang = Just "haskell",
                  codeNumbers = Just True,
                  codeFile = Just "src/Main.hs",
                  codeCaption = Just [Text sp0 "設定の読み込み"],
                  codeDiff = True,
                  codeLines =
                    [ CodeLine "main = do" (Just 1) (Just DiffContext) True [],
                      CodeLine "  old" Nothing (Just DiffRemoved) False [],
                      CodeLine "  new" (Just 2) (Just DiffAdded) False [1, 2],
                      CodeLine "" (Just 3) (Just DiffContext) False []
                    ]
                }
        renderBlocks Map.empty [] (Map.fromList [(0, "リスト1-1")]) [CodeBlock code]
          @?= [("a.txt", "リスト1-1　設定の読み込み\nsrc/Main.hs\n main = do\n-  old\n+  new ① ②\n \n")],
      testCase "a code block with none of them is its text (golem-driver ADR 0023)" $
        renderBlocks Map.empty [] Map.empty [CodeBlock (Code Nothing Nothing Nothing Nothing False [CodeLine "a <1>" (Just 1) Nothing False [], CodeLine "b" (Just 2) Nothing False []])]
          @?= [("a.txt", "a <1>\nb\n")],
      textOutputTests
    ]
