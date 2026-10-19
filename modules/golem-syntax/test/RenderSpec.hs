{- | The human and JSON renderings of related locations and of control
characters (golem-syntax ADR 0001, "出力の形式").
-}
module RenderSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Syntax
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

-- | Two files: a.gm (FileId 0) and b.gm (FileId 1); FileId 9 is not known.
files :: Map.Map FileId SourceInfo
files =
  Map.fromList
    [ (FileId 0, SourceInfo "a.gm" (mkLineIndex "@label x\nab\n")),
      (FileId 1, SourceInfo "b.gm" (mkLineIndex "one\ntwo\n"))
    ]

-- | A duplicate label in a.gm, line 2, whose first definition is in b.gm, line 2.
duplicate :: Diagnostic
duplicate =
  (diagnostic "G0403" Error (mkSpan (FileId 0) 9 11) "ラベルが重複しています")
    { diagRelated = [(mkSpan (FileId 1) 5 7, "最初の定義")]
    }

relatedTests :: TestTree
relatedTests =
  testGroup
    "related locations"
    [ testCase "human: each related location follows the excerpt as '  = path:line:col: message'" $
        renderHuman files [duplicate]
          @?= "a.gm:2:1: error[G0403]: ラベルが重複しています\n  | ab\n  = b.gm:2:2: 最初の定義\n",
      testCase "human: related locations keep their order" $
        renderHuman files [duplicate {diagRelated = [(mkSpan (FileId 1) 4 5, "二つ目"), (mkSpan (FileId 0) 0 1, "一つ目")]}]
          @?= "a.gm:2:1: error[G0403]: ラベルが重複しています\n  | ab\n  = b.gm:2:1: 二つ目\n  = a.gm:1:1: 一つ目\n",
      testCase "human: a related location in an unknown file has the path <unknown> and no line" $
        renderHuman files [duplicate {diagRelated = [(mkSpan (FileId 9) 0 1, "外")]}]
          @?= "a.gm:2:1: error[G0403]: ラベルが重複しています\n  | ab\n  = <unknown>: 外\n",
      testCase "human: a diagnostic in an unknown file has ?:? and no excerpt" $
        renderHuman files [diagnostic "G0801" Error (mkSpan (FileId 9) 3 4) "m"]
          @?= "<unknown>:?:?: error[G0801]: m\n",
      testCase "json: related locations are objects with a span and a message" $
        renderJson files [duplicate]
          @?= "[{\"code\":\"G0403\",\"severity\":\"error\",\"span\":{\"file\":\"a.gm\",\"start\":9,\"end\":11,\"line\":2,\"column\":1},\"message\":\"ラベルが重複しています\",\"related\":[{\"span\":{\"file\":\"b.gm\",\"start\":5,\"end\":7,\"line\":2,\"column\":2},\"message\":\"最初の定義\"}],\"fixes\":[]}]\n",
      testCase "json: two related locations are separated by a comma" $
        renderJson files [duplicate {diagRelated = [(mkSpan (FileId 1) 0 1, "x"), (mkSpan (FileId 1) 4 5, "y")]}]
          @?= "[{\"code\":\"G0403\",\"severity\":\"error\",\"span\":{\"file\":\"a.gm\",\"start\":9,\"end\":11,\"line\":2,\"column\":1},\"message\":\"ラベルが重複しています\",\"related\":[{\"span\":{\"file\":\"b.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\"x\"},{\"span\":{\"file\":\"b.gm\",\"start\":4,\"end\":5,\"line\":2,\"column\":1},\"message\":\"y\"}],\"fixes\":[]}]\n",
      testCase "json: a span in an unknown file is <unknown>, line 1, column 1" $
        renderJson files [diagnostic "G0801" Error (mkSpan (FileId 9) 3 4) "m"]
          @?= "[{\"code\":\"G0801\",\"severity\":\"error\",\"span\":{\"file\":\"<unknown>\",\"start\":3,\"end\":4,\"line\":1,\"column\":1},\"message\":\"m\",\"related\":[],\"fixes\":[]}]\n"
    ]

-- | The JSON of one diagnostic in a.gm at 0..1 with the given message.
jsonWithMessage :: T.Text -> T.Text
jsonWithMessage m = renderJson files [diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) m]

-- | What 'jsonWithMessage' writes around the message.
wrapped :: T.Text -> T.Text
wrapped escaped =
  "[{\"code\":\"G0101\",\"severity\":\"error\",\"span\":{\"file\":\"a.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\""
    <> escaped
    <> "\",\"related\":[],\"fixes\":[]}]\n"

escapeTests :: TestTree
escapeTests =
  testGroup
    "JSON string escapes"
    [ testCase "a quote and a backslash are escaped with a backslash" $
        jsonWithMessage "a\"b\\c" @?= wrapped "a\\\"b\\\\c",
      testCase "newline, carriage return and tab use their short escapes" $
        jsonWithMessage "a\nb\rc\td" @?= wrapped "a\\nb\\rc\\td",
      testCase "other control characters are \\u and four lowercase hex digits" $
        jsonWithMessage "\NUL\SOH\ESC\US" @?= wrapped "\\u0000\\u0001\\u001b\\u001f",
      testCase "space, DEL and non-ASCII characters are written as they are" $
        jsonWithMessage " \DEL漢😀" @?= wrapped " \DEL漢😀",
      testCase "a control character in a path and in a related message is escaped too" $ do
        let fs = Map.fromList [(FileId 0, SourceInfo "a\tb.gm" (mkLineIndex "x"))]
            d = (diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) "m") {diagRelated = [(mkSpan (FileId 0) 0 1, "r\SOH")]}
        renderJson fs [d]
          @?= "[{\"code\":\"G0101\",\"severity\":\"error\",\"span\":{\"file\":\"a\\tb.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\"m\",\"related\":[{\"span\":{\"file\":\"a\\tb.gm\",\"start\":0,\"end\":1,\"line\":1,\"column\":1},\"message\":\"r\\u0001\"}],\"fixes\":[]}]\n",
      testProperty "no raw control character reaches the JSON output except its final newline" $ property $ do
        m <- forAll (Gen.text (Range.linear 0 40) (Gen.frequency [(3, Gen.element ['\0' .. '\x1f']), (1, Gen.unicode)]))
        T.filter (< ' ') (T.dropEnd 1 (jsonWithMessage m)) === ""
    ]

-- | The human rendering is written to a terminal: no C0 control character but the newline may reach it.
terminalTests :: TestTree
terminalTests =
  testGroup
    "the human rendering and the terminal (security audit 2026-10-18, C13)"
    [ testCase "an escape sequence in the source line is not written as it is" $ do
        let fs = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex "x\ESC[31m\ESC]0;title\BELy\n"))]
            out = renderHuman fs [diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) "m"]
        T.filter (\c -> c < ' ' && c /= '\n') out @?= "",
      testCase "an escape sequence in the path and in the message is not written as it is" $ do
        let fs = Map.fromList [(FileId 0, SourceInfo "a\ESC[2Jb.gm" (mkLineIndex "x"))]
            d = (diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) "m\ESC[0m") {diagRelated = [(mkSpan (FileId 0) 0 1, "r\SOH")]}
        T.filter (\c -> c < ' ' && c /= '\n') (renderHuman fs [d]) @?= "",
      -- ADR 0042: the form of the replacement
      testCase "ESC is written as \\x1b in the source line, the path and the message" $ do
        let fs = Map.fromList [(FileId 0, SourceInfo "a\ESCb.gm" (mkLineIndex "x\ESCy\BELz\n"))]
            d = (diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) "m\ESCn") {diagRelated = [(mkSpan (FileId 0) 0 1, "r\SOH")]}
        renderHuman fs [d] @?= "a\\x1bb.gm:1:1: error[G0101]: m\\x1bn\n  | x\\x1by\\x07z\n  = a\\x1bb.gm:1:1: r\\x01\n",
      testCase "a tab is written as it is; U+007F and U+0085 are replaced" $ do
        let fs = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex "a\tb\DELc\x85\&d\n"))]
        renderHuman fs [diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) "m"] @?= "a.gm:1:1: error[G0101]: m\n  | a\tb\\x7fc\\x85d\n",
      testCase "a line of 1000 characters is cut to 200 around the column, with an ellipsis at each cut end" $ do
        let line = T.pack [toEnum (0x4e00 + i) | i <- [0 .. 999 :: Int]]
            fs = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex (line <> "\n")))]
            off = 3 * 500
            out = renderHuman fs [diagnostic "G0101" Error (mkSpan (FileId 0) off (off + 3)) "m"]
            excerpt = T.drop 4 (T.lines out !! 1)
        excerpt @?= "\x2026" <> T.take 200 (T.drop 440 line) <> "\x2026"
        assertBool "the character at the column" (T.index line 500 `T.elem` excerpt),
      testCase "a line of 100 characters is written as it is" $ do
        let line = T.replicate 100 "a"
            fs = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex line))]
        T.lines (renderHuman fs [diagnostic "G0101" Error (mkSpan (FileId 0) 50 51) "m"]) !! 1 @?= "  | " <> line,
      testCase "near the start of a long line only the end is cut" $ do
        let line = T.replicate 300 "a"
            fs = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex line))]
        T.lines (renderHuman fs [diagnostic "G0101" Error (mkSpan (FileId 0) 10 11) "m"]) !! 1 @?= "  | " <> T.replicate 200 "a" <> "\x2026",
      testCase "the length is counted after the replacement" $ do
        let line = T.replicate 100 "\SOH"
            fs = Map.fromList [(FileId 0, SourceInfo "a.gm" (mkLineIndex line))]
        T.lines (renderHuman fs [diagnostic "G0101" Error (mkSpan (FileId 0) 0 1) "m"]) !! 1 @?= "  | " <> T.replicate 50 "\\x01" <> "\x2026"
    ]

tests :: TestTree
tests = testGroup "rendering (golem-syntax ADR 0001)" [relatedTests, escapeTests, terminalTests]
