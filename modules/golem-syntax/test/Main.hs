module Main (main) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

main :: IO ()
main = defaultMain tests

-- ASCII, Japanese, a 4-byte emoji and a newline, so that byte, code point
-- and UTF-16 units all differ.
genText :: Gen Text
genText =
  T.pack
    <$> Gen.list
      (Range.linear 0 80)
      (Gen.element ("ab 漢字かな\n😀𠮷x" :: String))

-- Byte offsets that fall on a code point boundary.
boundaries :: Text -> [Int]
boundaries t = scanl (+) 0 [BS.length (TE.encodeUtf8 (T.singleton c)) | c <- T.unpack t]

-- | A list-based line index measuring columns with the given function.
naiveLineCol :: (BS.ByteString -> Int) -> Text -> Int -> LineCol
naiveLineCol measure t off =
  let bs = TE.encodeUtf8 t
      starts = 0 : map (+ 1) (BS.elemIndices 10 bs)
      l = length (takeWhile (<= off) starts) - 1
      s = starts !! l
   in LineCol l (measure (BS.take (off - s) (BS.drop s bs)))

utf16Length :: BS.ByteString -> Int
utf16Length = sum . map (\c -> if fromEnum c > 0xFFFF then 2 else 1) . T.unpack . TE.decodeUtf8

tests :: TestTree
tests =
  testGroup
    "golem-syntax"
    [ testGroup
        "sha256"
        [ testCase "the empty string" $
            hex (sha256 "") @?= "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
          testCase "abc" $
            hex (sha256 "abc") @?= "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
          testCase "two blocks (FIPS 180-2)" $
            hex (sha256 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
              @?= "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
          testCase "a million times a" $
            hex (sha256 (BS.replicate 1000000 0x61)) @?= "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
          -- the test suite runs with a heap limit of 64 MB (golem-syntax.cabal):
          -- the state of the rounds must not build up across the blocks
          testCase "16 MB in a bounded heap" $
            hex (sha256 (BS.replicate (16 * 1024 * 1024) 0)) @?= "080acf35a507ac9849cfcba47dc2ad83e01b75663a516279c8b9d243b719643e"
        ],
      testProperty "offset -> line/col -> offset" $ property $ do
        t <- forAll genText
        off <- forAll (Gen.element (boundaries t))
        let li = mkLineIndex t
        lineColToOffset li (offsetToLineCol li off) === Just off,
      testProperty "offset -> utf16 line/col -> offset" $ property $ do
        t <- forAll genText
        off <- forAll (Gen.element (boundaries t))
        let li = mkLineIndex t
        utf16LineColToOffset li (offsetToUtf16LineCol li off) === Just off,
      testProperty "offset -> utf8 line/col -> offset (golem-lsp ADR 0002)" $ property $ do
        t <- forAll genText
        off <- forAll (Gen.element (boundaries t))
        let li = mkLineIndex t
        utf8LineColToOffset li (offsetToUtf8LineCol li off) === Just off,
      testProperty "the line index agrees with a naive list-based index (golem-lsp ADR 0002)" $ property $ do
        t <- forAll genText
        off <- forAll (Gen.element (boundaries t))
        let li = mkLineIndex t
        offsetToLineCol li off === naiveLineCol (T.length . TE.decodeUtf8) t off
        offsetToUtf16LineCol li off === naiveLineCol utf16Length t off
        offsetToUtf8LineCol li off === naiveLineCol BS.length t off,
      testCase "utf8 columns inside a character, at the line end and beyond (golem-lsp ADR 0002)" $ do
        let li = mkLineIndex "漢字\nab"
        utf8LineColToOffset li (LineCol 0 1) @?= Nothing
        utf8LineColToOffset li (LineCol 0 2) @?= Nothing
        utf8LineColToOffset li (LineCol 0 3) @?= Just 3
        utf8LineColToOffset li (LineCol 0 6) @?= Just 6
        utf8LineColToOffset li (LineCol 0 7) @?= Nothing
        utf8LineColToOffset li (LineCol 1 2) @?= Just 9
        utf8LineColToOffset li (LineCol 2 0) @?= Nothing,
      localOption (mkTimeout 2000000) $
        testCase "positions on 100000 lines round-trip quickly (golem-lsp ADR 0002)" $ do
          let n = 100000 :: Int
              t = T.replicate n "漢😀a\n" <> "漢😀a"
              li = mkLineIndex t
              starts = [k * 9 | k <- [0 .. n]]
              lastOff = n * 9 + 8
          lineCount li @?= n + 1
          lineColToOffset li (offsetToLineCol li lastOff) @?= Just lastOff
          utf16LineColToOffset li (offsetToUtf16LineCol li lastOff) @?= Just lastOff
          utf8LineColToOffset li (offsetToUtf8LineCol li lastOff) @?= Just lastOff
          offsetToUtf16LineCol li lastOff @?= LineCol n 4
          all (\o -> utf8LineColToOffset li (offsetToUtf8LineCol li o) == Just o) starts @?= True
          all (\o -> utf16LineColToOffset li (offsetToUtf16LineCol li o) == Just o) starts @?= True,
      testCase "columns count code points, utf16 counts surrogate pairs" $ do
        let t = "😀a\n漢b"
            li = mkLineIndex t
        offsetToLineCol li 5 @?= LineCol 0 2
        offsetToUtf16LineCol li 5 @?= LineCol 0 3
        offsetToLineCol li 9 @?= LineCol 1 1
        lineText li 1 @?= "漢b",
      testCase "a column inside a multi-byte character has no offset" $ do
        let li = mkLineIndex "漢字"
        lineColToOffset li (LineCol 0 1) @?= Just 3
        isJust (lineColToOffset li (LineCol 0 5)) @?= False,
      testCase "profile adjusts only profile-dependent codes" $ do
        let sp = mkSpan (FileId 0) 0 1
            lbl = diagnostic "G0504" Warning sp "unused label"
            other = diagnostic "G0101" Warning sp "other"
        diagSeverity (adjustForProfile Prod lbl) @?= Error
        diagSeverity (adjustForProfile Dev lbl) @?= Warning
        diagSeverity (adjustForProfile Prod other) @?= Warning,
      testProperty "sorting ignores input order" $ property $ do
        ds <- forAll (Gen.list (Range.linear 0 20) genDiag)
        perm <- forAll (Gen.shuffle ds)
        sortDiagnostics ds === sortDiagnostics perm,
      testCase "file table assigns ids in registration order" $ do
        let (a, ft1) = registerFile "a.gm" emptyFileTable
            (b, ft2) = registerFile "b.gm" ft1
            (a', _) = registerFile "a.gm" ft2
        (a, b, a') @?= (FileId 0, FileId 1, FileId 0),
      testCase "json rendering is stable" $ do
        let src = "一行目\n二行目\"x\""
            files = Map.fromList [(FileId 0, SourceInfo "ch/01.gm" (mkLineIndex src))]
            d = (diagnostic "G0101" Error (mkSpan (FileId 0) 10 13) "閉じていない [") {diagFixes = [Fix "fix" [(mkSpan (FileId 0) 13 13, "]")]]}
        renderJson files [d]
          @?= "[{\"code\":\"G0101\",\"severity\":\"error\",\"span\":{\"file\":\"ch/01.gm\",\"start\":10,\"end\":13,\"line\":2,\"column\":1},\"message\":\"閉じていない [\",\"related\":[],\"fixes\":[{\"title\":\"fix\",\"edits\":[{\"span\":{\"file\":\"ch/01.gm\",\"start\":13,\"end\":13,\"line\":2,\"column\":2},\"text\":\"]\"}]}]}]\n",
      testCase "human rendering" $ do
        let src = "abc\ndef"
            files = Map.fromList [(FileId 0, SourceInfo "x.gm" (mkLineIndex src))]
        renderHuman files [diagnostic "G0201" Error (mkSpan (FileId 0) 5 6) "msg"]
          @?= "x.gm:2:2: error[G0201]: msg\n  | def\n"
    ]

genDiag :: Gen Diagnostic
genDiag = do
  f <- Gen.int (Range.linear 0 3)
  s <- Gen.int (Range.linear 0 50)
  l <- Gen.int (Range.linear 0 5)
  code <- Gen.element ["G0101", "G0201", "G0504"]
  sev <- Gen.element [Error, Warning]
  msg <- Gen.element ["a", "b"]
  pure (diagnostic code sev (mkSpan (FileId f) s (s + l)) msg)

hex :: BS.ByteString -> String
hex = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
  where
    digits = "0123456789abcdef"
