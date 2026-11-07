-- | Where each page of the PDF starts in the source (docs/adr ADR 0195).
module PageStartsSpec (pageStartsTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.List (isSuffixOf)
import Data.Maybe (listToMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Twelve characters a line, three lines a page.
threeLines :: BS.ByteString
threeLines = withBodyFont (replaceIn "lines = 30" "lines = 3" horizontalStyle)

-- | Characters that are each once in the source: kana and kanji.
distinct :: [Char]
distinct = ['ぁ' .. 'ゖ'] <> ['亜' ..]

{- | A source with page breaks of every kind: a paragraph over two lines
of the source with a character outside the BMP and an escape before the
break of its page, a paragraph after @page-break, and a blank page made
by two @page-break in a row.
-}
source :: T.Text
source =
  let (a, rest) = splitAt 40 distinct
      (b, rest') = splitAt 60 rest
      (c, rest'') = splitAt 30 rest'
      d = take 10 rest''
   in T.concat
        [ "𠮷\\[",
          T.pack a,
          "\n",
          T.pack b,
          "\n\n@page-break\n",
          T.pack c,
          "\n\n@page-break\n\n@page-break\n",
          T.pack d,
          "\n"
        ]

-- | Builds the source to PDF and reads the file of the starts of the pages.
buildPages :: Bool -> IO (BuildResult, T.Text)
buildPages parallel = withSystemTempDirectory "golem-pages" $ \tmp -> do
  writeProject tmp miniManifest threeLines source fakeFontFiles
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optParallel = parallel}
  assertEqual "no errors" [] [diagMessage d | d <- brDiagnostics r, isError d]
  json <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build/pdf/pages.json")
  pure (r, json)

{- | The JSON expected from the text of the lines of each page: the first
character of the first line of a page is found in the source, where it
is once, and given as an LSP position (UTF-16 code units).
-}
expected :: [[T.Text]] -> T.Text
expected pages = "[" <> T.intercalate "," (zipWith one [1 :: Int ..] pages) <> "]\n"
  where
    li = mkLineIndex source
    bytes = TE.encodeUtf8 source
    one n ls = "{\"page\":" <> tshow n <> maybe "" at (listToMaybe (concatMap T.unpack (take 1 (filter (not . T.null) ls)))) <> "}"
    at ch =
      let off = BS.length (fst (BS.breakSubstring (TE.encodeUtf8 (T.singleton ch)) bytes))
          LineCol l col = offsetToUtf16LineCol li off
       in ",\"file\":\"a.gm\",\"line\":" <> tshow l <> ",\"character\":" <> tshow col
    tshow = T.pack . show

pageStartsTests :: TestTree
pageStartsTests =
  testGroup
    "where each page of the PDF starts in the source (docs/adr ADR 0195)"
    [ testCase "build/pdf/pages.json has the position of the first line of each page" $ do
        (r, json) <- buildPages True
        pages <- pagesMini "" threeLines source fakeFontFiles Map.empty >>= either (assertFailure . show) pure
        json @?= expected pages
        -- more than one page, and a blank page among them
        assertBool "pages" (length pages >= 4)
        assertBool "a blank page" (any (all T.null) pages)
        -- the third page starts on the second line of the paragraph in the source, after its newline
        assertBool (T.unpack json) ("{\"page\":3,\"file\":\"a.gm\",\"line\":1," `T.isInfixOf` json)
        assertBool "written" (any ("/build/pdf/pages.json" `isSuffixOf`) (brWritten r)),
      testCase "the second page starts on the first line of the source, its column in UTF-16 code units" $ do
        (_, json) <- buildPages True
        pages <- pagesMini "" threeLines source fakeFontFiles Map.empty >>= either (assertFailure . show) pure
        -- the page starts after 𠮷, two code units, and \[, two bytes for one character
        let firstOf = T.take 1 . T.concat . take 1 . filter (not . T.null)
        case (drop 1 pages, T.lines source) of
          (p : _, firstLine : _) -> do
            let ch = firstOf p
                cps = T.length (fst (T.breakOn ch firstLine))
            assertBool "on the first line" (ch `T.isInfixOf` firstLine)
            assertBool (T.unpack json) (("{\"page\":2,\"file\":\"a.gm\",\"line\":0,\"character\":" <> T.pack (show (cps + 1)) <> "}") `T.isInfixOf` json)
          _ -> assertFailure "one page",
      testCase "the number of a heading is not in the source: the page starts at its title" $ withSystemTempDirectory "golem-pages" $ \tmp -> do
        writeProject tmp miniManifest (threeLines <> "\n[headings.1]\nnumber = \"{n}.\"\n") "\n\n# 見出し\n\n本文。\n" fakeFontFiles
        r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider}
        assertEqual "no errors" [] [diagMessage d | d <- brDiagnostics r, isError d]
        json <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build/pdf/pages.json")
        -- the heading fills the first page; the paragraph starts the second
        json @?= "[{\"page\":1,\"file\":\"a.gm\",\"line\":2,\"character\":2},{\"page\":2,\"file\":\"a.gm\",\"line\":4,\"character\":0}]\n",
      testCase "the same file in parallel and in sequence" $ do
        (_, a) <- buildPages True
        (_, b) <- buildPages False
        a @?= b
    ]
