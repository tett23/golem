module Main (main) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Assemble
import Golem.Doc.IR
import Golem.Syntax
import Golem.Text
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

sp :: Int -> SrcSpan
sp s = mkSpan (FileId 0) s (s + 1)

heading :: Int -> HeadingAttrs -> Text -> Block
heading s a t = Block (sp s) Nothing (Heading 1 a [Text (sp s) t])

figure :: Int -> Text -> Block
figure s cap = Block (sp s) Nothing (FigureBlock (Figure "a.png" Nothing "" Nothing Nothing [Block (sp (s + 1)) Nothing (Paragraph Nothing [Text (sp (s + 1)) cap])]))

toc :: Int -> Block
toc s = Block (sp s) Nothing (ChannelOutput (TocOutput 1))

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
noEval _ _ _ = Right ""

-- | The plain text of one file in a book of the language, with the number format of headings.
render :: Text -> Text -> [Block] -> [Text]
render lang format bs =
  let cfg = AssembleConfig (Map.fromList [(1, format)]) "図{chapter}-{n}" Map.empty
      (book, _) = assemble cfg noEval [Document (FileId 0) bs]
      (_, ft) = registerFile "a.gm" emptyFileTable
      lists = TextLists ("・" :| []) Nothing Nothing
   in concatMap (T.lines . snd) (renderText lang "kanji" False (const 0) lists Horizontal ft book)

tests :: TestTree
tests =
  testGroup
    "golem-text"
    [ testGroup
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
        ]
    ]
