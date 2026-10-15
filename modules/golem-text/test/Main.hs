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
import TextOutputSpec (textOutputTests)

main :: IO ()
main = defaultMain tests

-- | One file, a.gm, whose only block is @bibliography, citing @cites@.
render :: Map Text Text -> [(Text, Int)] -> [(FilePath, Text)]
render bib cites = renderBlocks bib cites Map.empty [ChannelOutput BibliographyOutput]

-- | One file, a.gm, of blocks at offsets 0, 1, ... with the listing numbers by offset.
renderBlocks :: Map Text Text -> [(Text, Int)] -> Map Int Text -> [BlockBody] -> [(FilePath, Text)]
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
          @?= [("a.txt", "[1] 日本語組版処理の要件、W3C、2020。\n[2] missing\n")],
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
