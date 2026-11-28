module Main (main) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Bibliography (EntryPart (..))
import Golem.Doc.IR
import Golem.Syntax
import Golem.TestSupport.PackageDirectory (enterPackageDirectory)
import Golem.Text
import Test.Tasty
import Test.Tasty.HUnit
import TextOutputSpec (textOutputTests)

main :: IO ()
main = enterPackageDirectory >> defaultMain tests

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
          { bookDocs = [Document fid [Block (mkSpan fid i (i + 1)) Nothing Nothing b | (i, b) <- zip [0 ..] bodies]],
            bookHeadings = Map.empty,
            bookFigures = Map.empty,
            bookListings = Map.fromList [(mkSpan fid i (i + 1), t) | (i, t) <- Map.toList listings],
            bookTables = Map.empty,
            bookToc = [],
            bookTocDepth = Nothing,
            bookIndexes = [],
            -- the bibliography is the block at offset 0 (golem-doc ADR 0008)
            bookBibliographies = [(Just (fid, mkSpan fid 0 1), cites)],
            bookBibliographyEntries = Map.empty,
            bookCitationPieces = Map.empty,
            bookCiteMarks = Map.empty,
            bookLabels = Map.empty,
            bookReferenced = Set.empty,
            bookChapterOf = [],
            bookChannels = [],
            bookChannelDecls = Map.empty,
            bookTitleSeparators = Map.empty,
            bookTitleFormats = Map.empty,
            bookImages = Map.empty,
            bookSeparators = Map.empty
          }
   in renderText "ja" "kanji" False (const (const (0, 0))) lists False bib Horizontal ft book

sp :: Int -> SrcSpan
sp s = mkSpan (FileId 0) s (s + 1)

heading :: Int -> HeadingAttrs -> Text -> Block
heading s a t = Block (sp s) Nothing Nothing (Heading 1 a [Text (sp s) t])

figure :: Int -> Text -> Block
figure s cap = Block (sp s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "" Nothing Nothing [Block (sp (s + 1)) Nothing Nothing (Paragraph Nothing [Text (sp (s + 1)) cap])] Nothing False False Nothing))

toc :: Int -> Block
toc s = Block (sp s) Nothing Nothing (ChannelOutput (TocOutput 1))

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
noEval _ _ _ = Right ""

-- | The plain text of one file in a book of the language, with the number format of headings.
render :: Text -> Text -> [Block] -> [Text]
render = renderVariant Horizontal

renderVariant :: TextVariant -> Text -> Text -> [Block] -> [Text]
renderVariant variant lang format bs =
  let cfg = AssembleConfig (Map.fromList [(1, format)]) "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}" "表{chapter}-{n}" Map.empty 16 NumberPerChapter
      (book, _) = assemble cfg noEval [Document (FileId 0) bs]
      (_, ft) = registerFile "a.gm" emptyFileTable
   in concatMap (T.lines . snd) (renderText lang "kanji" False (const (const (0, 0))) lists False Map.empty variant ft book)

tests :: TestTree
tests =
  testGroup
    "golem-text"
    [ testCase "root ADR 0470 I2: bibliography styles retain their text in plain output" $
        renderBibliography (Map.fromList [("k", [EntryStyled "italic" [EntryText "Title"], EntryText ". ", EntryStyled "bold" [EntryUrl "https://example.org"]])]) [("k", 1)]
          @?= [("a.txt", "[1] Title. https://example.org\n")],
      testCase "root ADR 0478 I2, I4: rational text is normalized and integer vertical TCY stays kanji" $ do
        let values = [Tcy (sp 0) (TcyNumber (1 % 10)), Text (sp 0) " ", Tcy (sp 0) (TcyNumber 1)]
            bodies = [Block (sp 0) Nothing Nothing (Paragraph Nothing values)]
        renderVariant Horizontal "ja" "{title}" bodies @?= ["0.1 1"]
        renderVariant Vertical "ja" "{title}" bodies @?= ["0.1 一"],
      testCase "root ADR 0478 I3: repeating fraction text uses 17 significant digits" $
        render "ja" "{title}" [Block (sp 0) Nothing Nothing (Paragraph Nothing [Number (sp 0) (1 % 3) Nothing])] @?= ["0.33333333333333333"],
      testCase "@bibliography lists the entries, or the key without one (golem-doc ADR 0004)" $
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
            render "ja" "{n}" [heading 0 noHeadingAttrs "A", figure 5 "キャプション"] @?= ["1\x3000\&A", "", "［図1-1\x3000キャプション］"],
          testCase "the caption of a code block (golem-driver ADR 0042)" $ do
            let listing s cap = Block (sp s) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp s) cap]) False [CodeLine "x" Nothing Nothing False [] Nothing] False))
            render "en" "{n}" [heading 0 noHeadingAttrs "A", listing 5 "設定の読み込み"] @?= ["1 A", "", "リスト1-1 設定の読み込み", "x"]
            render "ja" "{n}" [heading 0 noHeadingAttrs "A", listing 5 "設定の読み込み"] @?= ["1\x3000\&A", "", "リスト1-1\x3000設定の読み込み", "x"]
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
                    [ CodeLine "main = do" (Just 1) (Just DiffContext) True [] Nothing,
                      CodeLine "  old" Nothing (Just DiffRemoved) False [] Nothing,
                      CodeLine "  new" (Just 2) (Just DiffAdded) False [1, 2] Nothing,
                      CodeLine "" (Just 3) (Just DiffContext) False [] Nothing
                    ],
                  codeNoNumber = False
                }
        renderBlocks Map.empty [] (Map.fromList [(0, "リスト1-1")]) [CodeBlock code]
          @?= [("a.txt", "リスト1-1　設定の読み込み\nsrc/Main.hs\n main = do\n-  old\n+  new ① ②\n \n")],
      testCase "a code block with none of them is its text (golem-driver ADR 0023)" $
        renderBlocks Map.empty [] Map.empty [CodeBlock (Code Nothing Nothing Nothing Nothing False [CodeLine "a <1>" (Just 1) Nothing False [] Nothing, CodeLine "b" (Just 2) Nothing False [] Nothing] False)]
          @?= [("a.txt", "a <1>\nb\n")],
      testCase "root ADR 0438 I6: the paragraphs of @frame are paragraphs at the place of the command" $ do
        let p s t = Block (sp s) Nothing Nothing (Paragraph Nothing [Text (sp s) t])
        renderBlocks Map.empty [] Map.empty [Paragraph Nothing [Text (sp 0) "前"], FrameBlock "quote" [p 10 "枠の一", p 11 "枠の二"], Paragraph Nothing [Text (sp 2) "後"]]
          @?= [("a.txt", "前\n\n枠の一\n\n枠の二\n\n後\n")],
      testCase "root ADR 0438 I6: an empty @frame writes nothing" $
        renderBlocks Map.empty [] Map.empty [Paragraph Nothing [Text (sp 0) "前"], FrameBlock "quote" [], Paragraph Nothing [Text (sp 2) "後"]]
          @?= [("a.txt", "前\n\n後\n")],
      textOutputTests
    ]
