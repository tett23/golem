module Main (main) where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.Assemble (Book (..))
import Golem.Doc.IR
import Golem.Syntax.Span
import Golem.Text
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

-- | One file, a.gm, whose only block is @bibliography, citing @cites@.
render :: Map Text Text -> [(Text, Int)] -> [(FilePath, Text)]
render bib cites =
  let (fid, ft) = registerFile "a.gm" emptyFileTable
      book =
        Book
          { bookDocs = [Document fid [Block (mkSpan fid 0 13) Nothing (ChannelOutput BibliographyOutput)]],
            bookHeadings = Map.empty,
            bookFigures = Map.empty,
            bookToc = [],
            bookTocDepth = Nothing,
            bookIndex = [],
            bookCitations = cites,
            bookLabels = Map.empty,
            bookReferenced = Set.empty
          }
   in renderText "kanji" False (const 0) (TextLists (pure "・") Nothing Nothing) bib Horizontal ft book

tests :: TestTree
tests =
  testGroup
    "golem-text"
    [ testCase "@bibliography lists the entries, or the key without one (golem-doc ADR 0004)" $
        render (Map.fromList [("jlreq", "日本語組版処理の要件、W3C、2020。")]) [("jlreq", 1), ("missing", 2)]
          @?= [("a.txt", "[1] 日本語組版処理の要件、W3C、2020。\n[2] missing\n")]
    ]
