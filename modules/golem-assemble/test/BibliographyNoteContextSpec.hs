module BibliographyNoteContextSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Assemble (AssembleConfig (..), Book (..), NoteChannelKind (..), NoteNumbering (..), assemble, resolvedNoteCitationPieces)
import Golem.Assemble.BibliographyNoteContext
import Golem.Doc.Citation (CitePiece (..))
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = mkSpan (FileId 1) 10 20

item :: CiteItem r
item = CiteItem "a" Nothing [] []

citation :: InlineF r
citation = Cite sp [item]

paragraph :: [Inline] -> Block
paragraph xs = Block sp Nothing Nothing (Paragraph Nothing xs)

notes :: [Inline] -> [Document]
notes xs = [Document (FileId 1) [paragraph xs]]

note :: NoteChannelKind -> Int -> [Inline] -> Inline
note channel n xs = constructor sp n Nothing (noteBody sp xs)
  where
    constructor = case channel of
      FootnoteChannel -> Note
      SidenoteChannel -> Sidenote
      EndnoteChannel -> Endnote

tests :: TestTree
tests =
  testGroup
    "S1 note citation context"
    [ testCase "root ADR 0470 I5: repeated source documents retain separate reset note contexts" $
        forM_ [(prefixCount, sameChapter) | prefixCount <- [0, 1], sameChapter <- [False, True]] $ \(prefixCount, sameChapter) -> do
          let numbering = if sameChapter then NumberPerFile else NumberPerChapter
              chapterOf = if sameChapter then replicate (prefixCount + 2) 0 else [0 .. prefixCount + 1]
              config = AssembleConfig Map.empty "{n}" Map.empty numbering chapterOf "{n}" "{n}" Map.empty 16 numbering
              documents = replicate prefixCount (Document (FileId 2) []) <> notes [note FootnoteChannel 0 [citation]] <> notes [note FootnoteChannel 0 [citation]]
              (book, diagnostics) = assemble config (\_ _ _ -> Right "") documents
              occurrences = bibliographyNoteCitations (bookDocs book)
          diagnostics @?= []
          map (nccNumber . ncoContext) occurrences @?= [1, 1]
          Set.size (Set.fromList (map ncoContext occurrences)) @?= 2
          map ncoContext occurrences @?= [NoteCitationContextInDocument sp FootnoteChannel 1 0 k | k <- [prefixCount, prefixCount + 1]],
      testCase "root ADR 0470 I5: document-scoped lookups retain legacy keys without bypassing an exact mismatched payload" $ do
        let config = AssembleConfig Map.empty "{n}" Map.empty NumberPerChapter [] "{n}" "{n}" Map.empty 16 NumberPerChapter
            (book, _) = assemble config (\_ _ _ -> Right "") (notes [note FootnoteChannel 1 [citation]])
            legacy = NoteCitationContext sp FootnoteChannel 1 0
            scoped = NoteCitationContextInDocument sp FootnoteChannel 1 0 2
            table = Map.singleton legacy (sp, [item], [CiteText "LEGACY"])
        resolvedNoteCitationPieces book {bookNoteCitationPieces = table} scoped sp [item] @?= Just [CiteText "LEGACY"]
        resolvedNoteCitationPieces book {bookNoteCitationPieces = Map.insert scoped (sp, [citeItem "different"], [CiteText "WRONG"]) table} scoped sp [item] @?= Nothing,
      testCase "root ADR 0470 I5: real S1 numbering distinguishes shared spans and per-file resets" $ do
        let cfg = AssembleConfig Map.empty "{n}" Map.empty NumberPerFile [] "{n}" "{n}" Map.empty 16 NumberPerChapter
            other = mkSpan (FileId 2) 10 20
            documents = notes [note FootnoteChannel 0 [citation], note FootnoteChannel 0 [citation]] <> [Document (FileId 2) [paragraph [Note other 0 Nothing (noteBody other [Cite other [item]])]]]
            (book, _) = assemble cfg (\_ _ _ -> Right "") documents
            occurrences = bibliographyNoteCitations (bookDocs book)
        map (nccNumber . ncoContext) occurrences @?= [1, 2, 1]
        map (nccNoteSpan . ncoContext) occurrences @?= [sp, sp, other],
      testCase "root ADR 0470 I5: identical spans and items in separate notes retain their S1 identities" $ do
        let occurrences = bibliographyNoteCitations (notes [note FootnoteChannel 1 [citation], note FootnoteChannel 2 [citation]])
        map ncoContext occurrences @?= [NoteCitationContext sp FootnoteChannel 1 0, NoteCitationContext sp FootnoteChannel 2 0]
        map ncoItems occurrences @?= replicate 2 [item],
      testCase "root ADR 0470 I5: identical marks in one note retain each written occurrence" $ do
        let occurrences = bibliographyNoteCitations (notes [note FootnoteChannel 1 [citation, Text sp " / ", citation, citation]])
        map (nccOccurrence . ncoContext) occurrences @?= [0, 1, 2]
        map ncoSpan occurrences @?= replicate 3 sp,
      testCase "root ADR 0470 I5: footnotes sidenotes and endnotes retain distinct contexts" $ do
        let channels = [FootnoteChannel, SidenoteChannel, EndnoteChannel]
        map (nccChannel . ncoContext) (bibliographyNoteCitations (notes [note channel 1 [citation] | channel <- channels])) @?= channels,
      testCase "root ADR 0470 I5: citations outside a note are absent from the note inventory" $ do
        bibliographyNoteCitations [] @?= []
        bibliographyNoteCitations (notes [citation, Ruby sp () [RubySegment [citation] (Just "じ")]]) @?= [],
      testCase "root ADR 0470 I5: note citations in ruby bases and inline containers preserve item payloads" $
        forM_ [FootnoteChannel, SidenoteChannel, EndnoteChannel] $ \channel -> do
          let wrapped = Lang sp "ja" [CharStyle sp "strong" [Ruby sp () [RubySegment [citation] (Just "じ")]]]
              occurrences = bibliographyNoteCitations (notes [note channel 7 [wrapped]])
          map ncoContext occurrences @?= [NoteCitationContext sp channel 7 0]
          map ncoItems occurrences @?= [[item]],
      testCase "root ADR 0470 I5: document identity distinguishes reset S1 note numbers" $ do
        let other = mkSpan (FileId 2) 10 20
            occurrences = bibliographyNoteCitations (notes [note FootnoteChannel 1 [citation]] <> [Document (FileId 2) [paragraph [Note other 1 Nothing (noteBody other [Cite other [item]])]]])
        map (nccNoteSpan . ncoContext) occurrences @?= [sp, other],
      testCase "root ADR 0470 I5: notes in structural containers retain their written order" $ do
        let body n = [note FootnoteChannel n [citation]]
            table = (plainTable [AlignDefault] [body 4] [[body 5]]) {tableCaption = Just (body 3)}
            block = Block sp Nothing Nothing
            blocks =
              [ block (BulletList [ListItem Nothing [paragraph (body 1)]]),
                block (DefList [DefGroup [body 2] []]),
                block (TableBlock table),
                block (CodeBlock (Code Nothing Nothing Nothing (Just (body 6)) False [] False)),
                block (FrameBlock "frame" [paragraph (body 7)])
              ]
        map (nccNumber . ncoContext) (bibliographyNoteCitations [Document (FileId 1) blocks]) @?= [1 .. 7],
      testCase "root ADR 0470 I5: year form locators affixes and item order survive the inventory" $ do
        let items = [CiteYearItem "z" (Just (Locator LocatorPage (LocNumber 3))) [Text sp "<prefix>"] [Text sp "&suffix"], item]
            occurrences = bibliographyNoteCitations (notes [note EndnoteChannel 1 [Cite sp items]])
        map ncoItems occurrences @?= [items]
    ]
