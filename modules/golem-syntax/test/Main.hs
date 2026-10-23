module Main (main) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import RenderSpec qualified
import ShowTreeSpec qualified
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
      testCase "lineEndOffset is the offset before the newline (golem-lsp ADR 0003)" $ do
        let li = mkLineIndex "漢字\nab"
        lineEndOffset li 0 @?= Just 6
        lineEndOffset li 1 @?= Just 9
        lineEndOffset li 2 @?= Nothing
        lineEndOffset (mkLineIndex "a\n") 1 @?= Just 2,
      -- The time limit is the one golem-lsp ADR 0002 sets. The test takes
      -- about 0.06 s (2026-10), over 30 times below it, while a search
      -- linear in the line count would make the 100001 round trips take
      -- billions of steps; a count of steps would need a change to the
      -- library, so the wall clock stays.
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
            lbl = diagnostic "G05004" Warning sp "unused label"
            other = diagnostic "G01001" Warning sp "other"
        diagSeverity (adjustForProfile Prod lbl) @?= Error
        diagSeverity (adjustForProfile Dev lbl) @?= Warning
        diagSeverity (adjustForProfile Prod other) @?= Warning,
      testCase "G08100, a character the font has not, is a warning in dev and an error in prod (docs/adr 0081)" $ do
        let d = diagnostic "G08100" Warning (mkSpan (FileId 0) 0 1) "m"
        diagSeverity (adjustForProfile Dev d) @?= Warning
        diagSeverity (adjustForProfile Prod d) @?= Error,
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
            d = (diagnostic "G01001" Error (mkSpan (FileId 0) 10 13) "閉じていない [") {diagFixes = [Fix "fix" [(mkSpan (FileId 0) 13 13, "]")]]}
        renderJson files [d]
          @?= "[{\"code\":\"G01001\",\"severity\":\"error\",\"span\":{\"file\":\"ch/01.gm\",\"start\":10,\"end\":13,\"line\":2,\"column\":1},\"message\":\"閉じていない [\",\"related\":[],\"fixes\":[{\"title\":\"fix\",\"edits\":[{\"span\":{\"file\":\"ch/01.gm\",\"start\":13,\"end\":13,\"line\":2,\"column\":2},\"text\":\"]\"}]}]}]\n",
      testCase "facts (golem-cli ADR 0006): none leaves the JSON as it was" $ do
        let files = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex "x"))]
            d = diagnostic "G02001" Error (mkSpan (FileId 0) 0 1) "m"
        diagFacts d @?= []
        renderJson files [d]
          @?= "[{\"code\":\"G02001\",\"severity\":\"error\",\"span\":{\"file\":\"a.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\"m\",\"related\":[],\"fixes\":[]}]\n",
      testCase "facts (golem-cli ADR 0006): written in the order given" $ do
        let files = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex "x"))]
            d = (diagnostic "G09006" Warning (mkSpan (FileId 0) 0 1) "m") {diagFacts = [("pdf-pages", FactInts [12, 13]), ("ppi", FactInt 212), ("font", FactText "f\"x"), ("names", FactTexts ["a", "b"])]}
        renderJson files [d]
          @?= "[{\"code\":\"G09006\",\"severity\":\"warning\",\"span\":{\"file\":\"a.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\"m\",\"related\":[],\"fixes\":[],\"facts\":{\"pdf-pages\":[12,13],\"ppi\":212,\"font\":\"f\\\"x\",\"names\":[\"a\",\"b\"]}}]\n"
        renderHuman files [d] @?= renderHuman files [d {diagFacts = []}],
      testCase "preflightCodes are G09002 to G09018 but the retired G09005, apart from notices and the profile" $ do
        preflightCodes @?= [DiagnosticCode (T.pack ("G090" <> (if n < 10 then "0" else "") <> show n)) | n <- [2 .. 18 :: Int], n /= 5]
        assertBool "no notice" (not (any (`elem` noticeCodes) preflightCodes))
        assertBool "no profile" (not (any (`elem` profileDependentCodes) preflightCodes)),
      testCase "every code is G, the two digits of its stage and three digits (docs/adr 0061)" $ do
        let stage (DiagnosticCode c) = T.take 2 (T.drop 1 c)
            shaped (DiagnosticCode c) =
              T.length c == 6
                && T.take 1 c == "G"
                && T.all (`elem` ['0' .. '9']) (T.drop 1 c)
                && stage (DiagnosticCode c) `elem` ["01", "02", "03", "04", "05", "06", "07", "08", "09"]
        [c | c <- noticeCodes <> profileDependentCodes <> preflightCodes, not (shaped c)] @?= []
        -- the stage that gives each of them
        map stage noticeCodes @?= ["02", "02", "02", "02", "02", "02", "03", "03", "04", "04", "04", "04", "07", "07", "07", "07", "07", "08"]
        map stage profileDependentCodes @?= ["05", "03", "08"]
        assertBool "preflight is 09" (all ((== "09") . stage) preflightCodes),
      testCase "human rendering" $ do
        let src = "abc\ndef"
            files = Map.fromList [(FileId 0, SourceInfo "x.gm" (mkLineIndex src))]
        renderHuman files [diagnostic "G02001" Error (mkSpan (FileId 0) 5 6) "msg"]
          @?= "x.gm:2:2: error[G02001]: msg\n  | def\n",
      noticeTests,
      RenderSpec.tests,
      ShowTreeSpec.tests
    ]

-- | The notices (golem-syntax ADR 0002).
noticeTests :: TestTree
noticeTests =
  testGroup
    "notices (golem-syntax ADR 0002)"
    [ testCase "Error < Warning < Notice" $ do
        Error < Warning @?= True
        Warning < Notice @?= True,
      testCase "notices alone are no errors" $
        hasErrors [notice "G02065" sp0 "a", notice "G02062" sp0 "b"] @?= False,
      testCase "notice builds a diagnostic of severity Notice" $ do
        let d = notice "G02065" sp0 "m"
        (diagCode d, diagSeverity d, diagMessage d) @?= (DiagnosticCode "G02065", Notice, "m"),
      testCase "the profile does not change a notice" $ do
        let d = notice "G02065" sp0 "m"
        diagSeverity (adjustForProfile Prod d) @?= Notice
        diagSeverity (adjustForProfile Dev d) @?= Notice,
      testCase "no code is a notice and profile-dependent" $
        [c | c <- noticeCodes, c `elem` profileDependentCodes] @?= [],
      testCase "the initial notice codes" $
        noticeCodes @?= map DiagnosticCode ["G02062", "G02063", "G02064", "G02065", "G02079", "G02094", "G03023", "G03100", "G04007", "G04008", "G04009", "G04011", "G07030", "G07039", "G07045", "G07046", "G07047", "G08008"],
      testCase "a notice early in the file comes after an error late in it" $ do
        let n = notice "G02065" (mkSpan (FileId 0) 0 1) "n"
            e = diagnostic "G02001" Error (mkSpan (FileId 1) 50 51) "e"
        sortDiagnostics [n, e] @?= [e, n],
      testCase "errors and warnings stay mixed in the order of their positions" $ do
        let w = diagnostic "G02005" Warning (mkSpan (FileId 0) 0 1) "w"
            e = diagnostic "G02001" Error (mkSpan (FileId 0) 5 6) "e"
            n = notice "G02062" (mkSpan (FileId 0) 1 2) "n"
        sortDiagnostics [e, n, w] @?= [w, e, n],
      testProperty "notices come last, whatever the input order" $ property $ do
        ds <- forAll (Gen.list (Range.linear 0 20) genDiagWithNotices)
        perm <- forAll (Gen.shuffle ds)
        let sorted = sortDiagnostics ds
        sorted === sortDiagnostics perm
        let sevs = map diagSeverity sorted
        dropWhile (== Notice) (dropWhile (/= Notice) sevs) === [],
      testCase "silencing some codes drops their notices only" $ do
        let n1 = notice "G02062" sp0 "a"
            n2 = notice "G02065" sp0 "b"
            e = diagnostic "G02062" Error sp0 "error with a silenced code"
            w = diagnostic "G02062" Warning sp0 "warning with a silenced code"
        silenceNotices (Just (Set.singleton (DiagnosticCode "G02062"))) [n1, n2, e, w] @?= [n2, e, w],
      testProperty "silencing every code drops every notice and keeps the rest" $ property $ do
        ds <- forAll (Gen.list (Range.linear 0 20) genDiagWithNotices)
        silenceNotices Nothing ds === filter ((/= Notice) . diagSeverity) ds,
      testCase "human rendering of a notice" $ do
        let src = "@listing src=a.hs\n"
            files = Map.fromList [(FileId 0, SourceInfo "chapters/01.gm" (mkLineIndex src))]
        renderHuman files [notice "G02065" (mkSpan (FileId 0) 9 17) "@listing の src= は廃止予定です。パスを最初の引数に書きます"]
          @?= "chapters/01.gm:1:10: notice[G02065]: @listing の src= は廃止予定です。パスを最初の引数に書きます\n  | @listing src=a.hs\n",
      testCase "json rendering of a notice, after the errors" $ do
        let src = "ab\ncd\n"
            files = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex src))]
            n = notice "G02065" (mkSpan (FileId 0) 0 1) "n"
            e = diagnostic "G02001" Error (mkSpan (FileId 0) 3 4) "e"
        renderJson files [n, e]
          @?= "[{\"code\":\"G02001\",\"severity\":\"error\",\"span\":{\"file\":\"a.gm\",\"start\":3,\"end\":4,\"line\":2,\"column\":1},\"message\":\"e\",\"related\":[],\"fixes\":[]},"
            <> "{\"code\":\"G02065\",\"severity\":\"notice\",\"span\":{\"file\":\"a.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\"n\",\"related\":[],\"fixes\":[]}]\n"
    ]
  where
    sp0 = mkSpan (FileId 0) 0 1

genDiagWithNotices :: Gen Diagnostic
genDiagWithNotices = do
  d <- genDiag
  sev <- Gen.element [Error, Warning, Notice]
  pure d {diagSeverity = sev}

genDiag :: Gen Diagnostic
genDiag = do
  f <- Gen.int (Range.linear 0 3)
  s <- Gen.int (Range.linear 0 50)
  l <- Gen.int (Range.linear 0 5)
  code <- Gen.element ["G01001", "G02001", "G05004"]
  sev <- Gen.element [Error, Warning]
  msg <- Gen.element ["a", "b"]
  pure (diagnostic code sev (mkSpan (FileId f) s (s + l)) msg)

hex :: BS.ByteString -> String
hex = concatMap (\w -> [digits !! fromIntegral (w `div` 16), digits !! fromIntegral (w `mod` 16)]) . BS.unpack
  where
    digits = "0123456789abcdef"
