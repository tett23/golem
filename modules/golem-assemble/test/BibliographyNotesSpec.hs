module BibliographyNotesSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Golem.Assemble
import Golem.Assemble.BibliographyNoteContext
import Golem.Assemble.BibliographyNotes
import Golem.Assemble.BibliographyStyle
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

sp :: Int -> SrcSpan
sp n = mkSpan (FileId 0) n (n + 1)

mark :: Int -> InlineF r
mark n = Cite (sp n) [CiteYearItem "a" (Just (Locator LocatorPage (LocNumber 2))) [Text (sp n) "see "] [Text (sp n) "!"], citeItem "b"]

paragraph :: Int -> [Inline] -> Block
paragraph n = Block (sp n) (Just "paragraph-label") (Just "fr") . Paragraph (Just "body")

document :: [Inline] -> [Document]
document xs = [Document (FileId 0) [paragraph 0 xs]]

style :: BibliographyStyle Int
style = emptyBibliographyStyle {bsCitationMode = Just "note"}

auto :: Int -> InlineF r
auto n = Note (sp n) 0 Nothing (noteBody (sp n) [mark n])

tests :: TestTree
tests =
  testGroup
    "note preparation before S1"
    [ testCase "root ADR 0470 I5: one multi-item mark creates one unnumbered footnote with exact metadata" $
        prepareBibliographyNotes style (document [Text (sp 1) "before", mark 2, Text (sp 3) "after"]) @?= document [Text (sp 1) "before", auto 2, Text (sp 3) "after"],
      testCase "root ADR 0470 I5: the explicit endnote channel uses the same source span and item payload" $
        prepareBibliographyNotes style {bsNoteChannel = Just "endnote"} (document [mark 2]) @?= document [Endnote (sp 2) 0 Nothing (noteBody (sp 2) [mark 2])],
      testCase "root ADR 0470 I5: all writer note kinds stay opaque with their labels and numbers" $ do
        let body = noteBody (sp 1) [mark 2]
            nodes = [Note (sp 1) 7 (Just "n") body, Sidenote (sp 1) 8 (Just "s") body, Endnote (sp 1) 9 (Just "e") body]
        prepareBibliographyNotes style (document nodes) @?= document nodes,
      testCase "root ADR 0470 I5: a second preparation pass creates no nested notes" $ do
        let once = prepareBibliographyNotes style (document [mark 1, mark 1])
        prepareBibliographyNotes style once @?= once,
      testCase "root ADR 0470 I5: language and character-style wrappers retain their metadata" $ do
        let wrap xs = Lang (sp 1) "fr" [CharStyle (sp 1) "emph" xs]
        prepareBibliographyNotes style (document [wrap [mark 2]]) @?= document [wrap [auto 2]],
      testCase "root ADR 0470 I5: captions cells lists frames headings and ruby bases prepare structurally" $ do
        let block n = Block (sp n) Nothing Nothing
            tree node rubyNode =
              [ Document
                  (FileId 0)
                  [ paragraph 0 [node 1, Kenten (sp 2) Nothing [node 2], Ruby (sp 3) () [RubySegment [rubyNode 3] (Just "じ")]],
                    block 4 (TableBlock (plainTable [AlignDefault] [[node 5]] [[[node 6]]]) {tableCaption = Just [node 4]}),
                    block 7 (CodeBlock (Code Nothing Nothing Nothing (Just [node 7]) False [] False)),
                    block 8 (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [paragraph 8 [node 8]] Nothing False False Nothing)),
                    block 9 (FrameBlock "frame" [paragraph 9 [node 9]]),
                    block 10 (BulletList [ListItem Nothing [paragraph 10 [node 10]]]),
                    block 11 (OrderedList [ListItem (Just 3) [paragraph 11 [node 11]]]),
                    block 12 (DefList [DefGroup [[node 12]] [[paragraph 13 [node 13]]]]),
                    block 14 (Heading 2 noHeadingAttrs [node 14])
                  ]
              ]
        prepareBibliographyNotes style (tree mark mark) @?= tree auto auto,
      testCase "root ADR 0470 I5: ordinary prepared notes share S1 numbering without span rewriting" $ do
        let input = document [Note (sp 0) 17 Nothing (noteBody (sp 0) [Text (sp 0) "writer"]), mark 1, mark 1]
            config = AssembleConfig Map.empty "{n}" Map.empty NumberPerBook [] "{n}" "{n}" Map.empty 16 NumberPerBook
            (book, diagnostics) = assemble config (\_ _ _ -> Right "") (prepareBibliographyNotes style input)
        diagnostics @?= []
        [n | doc <- bookDocs book, (_, n, _) <- documentNotes doc] @?= [1, 2, 3]
        map (nccNumber . ncoContext) (bibliographyNoteCitations (bookDocs book)) @?= [2, 3]
        map ncoSpan (bibliographyNoteCitations (bookDocs book)) @?= [sp 1, sp 1],
      testCase "root ADR 0470 I5: non-note modes leave the entire document unchanged" $
        forM_ [Nothing, Just "numeric", Just "author-year"] $
          \mode -> prepareBibliographyNotes style {bsCitationMode = mode} (document [mark 1]) @?= document [mark 1]
    ]
