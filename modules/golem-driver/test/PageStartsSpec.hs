-- | Where each page of the PDF starts in the source (docs/adr ADR 0195).
module PageStartsSpec (pageStartsTests) where

import Data.ByteString qualified as BS
import Data.Char (isDigit)
import Data.List (isSuffixOf)
import Data.Map.Strict qualified as Map
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

-- | Builds a source with a style and files to PDF: pages.json and the text of the lines of each page.
codePages :: BS.ByteString -> T.Text -> [(FilePath, BS.ByteString)] -> Bool -> IO ([Maybe (Int, Int)], [[T.Text]])
codePages style src files parallel = withSystemTempDirectory "golem-pages" $ \tmp -> do
  writeProject tmp miniManifest style src (fakeFontFiles <> files)
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = fakeProvider, optParallel = parallel}
  assertEqual "no errors" [] [diagMessage d | d <- brDiagnostics r, isError d]
  json <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build/pdf/pages.json")
  pages <- pagesMini "" style src (fakeFontFiles <> files) Map.empty >>= either (assertFailure . show) pure
  pure (positions json, pages)

-- | The line and character of each page of pages.json, in order.
positions :: T.Text -> [Maybe (Int, Int)]
positions json = map one (T.splitOn "},{" json)
  where
    one o = (,) <$> field "\"line\":" o <*> field "\"character\":" o
    field k o = case T.breakOn k o of
      (_, rest) | not (T.null rest) -> Just (read (T.unpack (T.takeWhile isDigit (T.drop (T.length k) rest))))
      _ -> Nothing

-- | The source from a position: the rest of its line, the character in UTF-16 code units.
fromPosition :: T.Text -> (Int, Int) -> T.Text
fromPosition src (l, c) = case drop l (T.lines src) of
  ln : _ -> T.pack (dropUnits c (T.unpack ln))
  [] -> ""
  where
    dropUnits n cs | n <= 0 = cs
    dropUnits n (x : xs) = dropUnits (n - (if fromEnum x > 0xFFFF then 2 else 1)) xs
    dropUnits _ [] = []

{- | Checks the starts of the pages that start inside a code block
(docs/adr/0218): a page whose first line is a part of the code after
the first starts where the text of that line is in the source (C1, C2),
at the start of an empty line (C3); a page that starts with the first
part, at the fence (C4); no two pages at the same place (C6). @fence@
is the line of the fence, @firstRow@ the text of the first row of the
block and @textOf@ the text of a row without the marks set before it
(a diff mark).
-}
checkCode :: T.Text -> Int -> T.Text -> (T.Text -> T.Text) -> [Maybe (Int, Int)] -> [[T.Text]] -> IO ()
checkCode src fence firstRow textOf starts pages = do
  assertEqual "a start for each page" (length pages) (length starts)
  let inCode = [(n, st, ls) | (n, Just st@(l, _), ls) <- zip3 [1 :: Int ..] starts pages, l >= fence]
  assertBool "pages inside the code" (length inCode >= 2)
  mapM_ check inCode
  let later = [st | (_, st, ls) <- inCode, take 1 ls /= [firstRow]]
  assertBool "pages that start in a later part" (not (null later))
  assertEqual "no two pages at the same place" (length inCode) (length (unique (map (\(_, st, _) -> st) inCode)))
  where
    unique = foldr (\x acc -> if x `elem` acc then acc else x : acc) []
    check (n, st, ls) = case ls of
      l0 : _
        | l0 == firstRow -> assertEqual ("page " <> show n <> " starts at the fence") (fence, 0) st
        | T.null (textOf l0) -> do
            assertEqual ("page " <> show n <> " starts at an empty line") 0 (snd st)
            assertEqual ("page " <> show n <> " at an empty line") "" (fromPosition src st)
        | otherwise -> assertBool ("page " <> show n <> ": " <> T.unpack l0 <> " at " <> show st <> ": " <> T.unpack (fromPosition src st)) (textOf l0 `T.isPrefixOf` fromPosition src st)
      [] -> assertFailure ("page " <> show n <> " has no lines")

-- | The first of a list that is not empty.
firstOf :: [T.Text] -> T.Text
firstOf = maybe "" fst . uncons'

uncons' :: [a] -> Maybe (a, [a])
uncons' = \case
  x : xs -> Just (x, xs)
  [] -> Nothing

-- | horizontalStyle with five lines a page and the body font.
fiveLinesFont :: BS.ByteString
fiveLinesFont = withBodyFont (replaceIn "lines = 30" "lines = 5" horizontalStyle)

-- | Lines of code of two characters each, each character once in the source.
codeLinesOf :: Int -> [T.Text]
codeLinesOf n = take n [T.pack [a, b] | (a, b) <- pairs (drop 200 distinct)]
  where
    pairs (a : b : rest) = (a, b) : pairs rest
    pairs _ = []

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
        a @?= b,
      testCase "C1 C4 C6: a page that starts in a later part of a code block starts at its first line of code (docs/adr/0218)" $ do
        let ls = codeLinesOf 9
            src = "あ。\n\n```\n" <> T.unlines ls <> "```\n"
        (starts, pages) <- codePages fiveLinesFont src [] True
        checkCode src 2 (firstOf ls) id starts pages
        -- the third page starts in the third part, at a line of code after the fence
        case drop 2 starts of
          Just (l, _) : _ -> assertBool (show starts) (l > 2)
          other -> assertFailure (show other),
      testCase "C2: a page that starts in a wrapped line starts at the first character of its row (docs/adr/0218)" $ do
        let long = T.pack (take 60 (drop 400 distinct))
            ls = codeLinesOf 2 <> [long] <> drop 2 (codeLinesOf 4)
            src = "```\n" <> T.unlines ls <> "```\n"
        (starts, pages) <- codePages fiveLinesFont src [] True
        checkCode src 0 (firstOf ls) id starts pages
        -- some page starts inside the long line, past its first character
        assertBool (show starts) (any (\case Just (3, c) -> c > 0; _ -> False) starts),
      testCase "C3: a page that starts at an empty line of code starts at that line (docs/adr/0218)" $ do
        let ls = concat [[l, ""] | l <- codeLinesOf 12]
            src = "```\n" <> T.unlines ls <> "```\n"
        (starts, pages) <- codePages fiveLinesFont src [] True
        checkCode src 0 (firstOf ls) id starts pages,
      testCase "the diff mark, a text that starts with +, characters outside the BMP and callouts (docs/adr/0218)" $ do
        let ps = codeLinesOf 16
            ls = zipWith (<>) (cycle ["++", "-", " ", "+\x20BB7"]) (map (<> " <1>") ps)
            src = "``` diff=true callouts=true\n" <> T.unlines ls <> "```\n"
            -- the row without its diff mark and its callout
            textOf t =
              let t' = if T.take 1 t `elem` ["+", "-"] then T.drop 1 t else t
               in T.takeWhile (/= '\x2460') t'
        (starts, pages) <- codePages fiveLinesFont src [] True
        checkCode src 0 ("++" <> firstOf ps <> "\x2460") textOf starts pages
        -- a page that starts at a line of ++ starts after its diff mark
        let pluses = [c | Just (l, c) <- starts, l >= 1, Just t <- [listToMaybe (drop (l - 1) ls)], "++" `T.isPrefixOf` t]
        assertBool (show starts) (all (== 1) pluses),
      testCase "a tab at the start of a line of code is a character of the source (docs/adr/0218)" $ do
        let ps = codeLinesOf 12
            ls = map ("\t" <>) ps
            src = "```\n" <> T.unlines ls <> "```\n"
        (starts, _) <- codePages fiveLinesFont src [] True
        let later = [st | Just st@(l, _) <- drop 1 starts, l > 1]
        assertBool (show starts) (not (null later))
        mapM_ (\st -> assertBool (show st) (snd st == 0 && any (`T.isPrefixOf` fromPosition src st) ls)) later,
      testCase "a code block in a list item, after its caption and with its file name (docs/adr/0218)" $ do
        let ls = codeLinesOf 12
            src = "# 章\n\n- 項目\n\n  @caption 例\n  ```haskell file=\"a.hs\"\n" <> T.concat ["  " <> l <> "\n" | l <- ls] <> "  ```\n"
            fence = 5
        (starts, pages) <- codePages fiveLinesFont src [] True
        assertEqual "a start for each page" (length pages) (length starts)
        -- after the first page, each page starts at a line of the code, after its indent
        let later = drop 1 [st | Just st@(l, _) <- starts, l > fence]
        assertBool (show starts) (not (null later))
        mapM_ (\st@(l, c) -> assertBool (show st) (c == 2 && any (`T.isPrefixOf` fromPosition src st) ls && l > fence)) later,
      testCase "C5: the pages of @listing start at the block (docs/adr/0218)" $ do
        let src = "@listing src/a.txt\n"
            file = TE.encodeUtf8 (T.unlines (codeLinesOf 12))
        (starts, pages) <- codePages fiveLinesFont src [("src/a.txt", file)] True
        assertBool "pages" (length pages >= 3)
        starts @?= map (const (Just (0, 0))) pages,
      testCase "C8: pages that start in code blocks are the same in parallel and in sequence (docs/adr/0218)" $ do
        let src = "```\n" <> T.unlines (codeLinesOf 12) <> "```\n\n本文。\n\n```\n" <> T.unlines (drop 12 (codeLinesOf 24)) <> "```\n"
        a <- codePages fiveLinesFont src [] True
        b <- codePages fiveLinesFont src [] False
        a @?= b,
      testCase "C1: the second column starts at its first line of code (docs/adr/0218)" $ do
        let style = replaceIn "columns = 1" "columns = 2\ncolumn-gap = \"2zw\"" fiveLinesFont
            ls = codeLinesOf 14
            src = "```\n" <> T.unlines ls <> "```\n"
        (starts, columns) <- codePages style src [] True
        -- the lines of the pages: two columns each
        let pairs (a : b : rest) = (a <> b) : pairs rest
            pairs rest = rest
        checkCode src 0 (firstOf ls) id starts (pairs columns)
    ]
