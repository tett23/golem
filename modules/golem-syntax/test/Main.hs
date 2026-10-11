module Main (main) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Syntax
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

tests :: TestTree
tests =
  testGroup
    "golem-syntax"
    [ testProperty "offset -> line/col -> offset" $ property $ do
        t <- forAll genText
        off <- forAll (Gen.element (boundaries t))
        let li = mkLineIndex t
        lineColToOffset li (offsetToLineCol li off) === Just off,
      testProperty "offset -> utf16 line/col -> offset" $ property $ do
        t <- forAll genText
        off <- forAll (Gen.element (boundaries t))
        let li = mkLineIndex t
        utf16LineColToOffset li (offsetToUtf16LineCol li off) === Just off,
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
