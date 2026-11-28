module WriterNotesSpec (tests) where

import Control.Monad (forM_, when)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Assemble
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

at :: Int -> SrcSpan
at n = mkSpan (FileId 0) n (n + 1)

config :: AssembleConfig
config = AssembleConfig Map.empty "{n}" Map.empty NumberPerBook [] "{n}" "{n}" Map.empty 16 NumberPerBook

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic T.Text
noEval _ _ _ = Right ""

tests :: TestTree
tests =
  testGroup
    "writer note compatibility"
    [ testCase "root ADR 0482 I1: eight written note sites retain numbering and label targets in each channel" $
        forM_ [0 :: Int .. 2] $ \kind -> do
          let constructor = case kind of 0 -> Note; 1 -> Sidenote; _ -> Endnote
              label n = "note-" <> T.pack (show n)
              note n = constructor (at n) 0 (Just (label n)) (noteBody (at n) [Text (at n) "body"])
              block n = Block (at n) Nothing Nothing
              table = (plainTable [AlignDefault] [[note 5]] [[[note 6]]]) {tableCaption = Just [note 4]}
              code = Code Nothing Nothing Nothing (Just [note 7]) False [] False
              docs = [Document (FileId 0) [block 0 (Paragraph Nothing [note 0, note 1, Kenten (at 2) Nothing [note 2], Ruby (at 3) () [RubySegment [note 3] Nothing]]), block 4 (TableBlock table), block 7 (CodeBlock code)]]
              (book, diagnostics) = assemble config noEval docs
          diagnostics @?= []
          forM_ [0 :: Int .. 7] $ \n -> fmap ltNumber (Map.lookup (label n) (bookLabels book)) @?= Just (Just (Number (at n) (fromIntegral (n + 1)) Nothing))
          when (kind == 0) $ concatMap (map (\(_, n, _) -> n) . documentNotes) (bookDocs book) @?= [1 .. 8]
          when (kind == 2) $ concatMap (map (\(_, n, _) -> n) . documentEndnotes) (bookDocs book) @?= [1 .. 8],
      testCase "root ADR 0482 I1: ruby citations inside written note bodies retain their bibliography association" $
        forM_ [0 :: Int .. 2] $ \kind -> do
          let constructor = case kind of 0 -> Note; 1 -> Sidenote; _ -> Endnote
              citation = Cite (at 8) [CiteItem "a" Nothing [] []]
              note xs = constructor (at 0) 0 Nothing (noteBody (at 0) xs)
              ruby xs = Ruby (at 1) () [RubySegment xs Nothing]
          forM_ [ruby [note [citation]], note [ruby [citation]]] $ \value -> do
            let (book, diagnostics) = assemble config noEval [Document (FileId 0) [Block (at 0) Nothing Nothing (Paragraph Nothing [value])]]
            diagnostics @?= []
            concatMap snd (bookBibliographies book) @?= [("a", 1)]
            citeNumber book (at 8) "a" @?= Just 1,
      testCase "root ADR 0482 I5: raw ruby citations without a written note keep the old uncollected scope" $ do
        let raw = Ruby (at 1) () [RubySegment [Cite (at 8) [CiteItem "a" Nothing [] []]] Nothing]
            (book, diagnostics) = assemble config noEval [Document (FileId 0) [Block (at 0) Nothing Nothing (Paragraph Nothing [raw])]]
        diagnostics @?= []
        concatMap snd (bookBibliographies book) @?= []
        citeNumber book (at 8) "a" @?= Nothing
    ]
