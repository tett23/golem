{-# LANGUAGE TypeApplications #-}

{- | The translation of the messages of toml-parser 2.0.2.0 (golem-project
ADR 0007). The first group lists every message the version can make; the
second makes them from TOML so that a new version with other wording
fails here.
-}
module TomlMessageSpec (tests) where

import Data.Int (Int8)
import Data.List.NonEmpty (NonEmpty)
import Data.Ratio (Ratio)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.TomlMessage
import Numeric.Natural (Natural)
import Test.Tasty
import Test.Tasty.HUnit
import Toml qualified
import Toml.Schema
import Toml.Semantics (SemanticError (..), SemanticErrorKind (..), semantics)
import Toml.Syntax (Located (..), Position (..), parseRawToml)

tests :: TestTree
tests =
  testGroup
    "TomlMessage (golem-project ADR 0007)"
    [ testCase "every schema message is translated" $
        mapM_ (\m -> assertBool m (schemaMessage [] m /= T.pack m)) schemaMessages,
      testCase "every lexical and parse message is translated" $
        mapM_ (\m -> assertBool m (syntaxMessage m /= T.pack m)) syntaxMessages,
      testCase "the messages of the tables" $ do
        schemaMessage [ScopeKey "page"] "unexpected key: bindng" @?= "知らないキーです: page.bindng"
        schemaMessage [] "missing key: metadata" @?= "必須のキーがありません: metadata"
        schemaMessage [ScopeKey "page", ScopeKey "bleed"] "expected string but got integer" @?= "page.bleed には文字列を書きます（整数が書かれています）"
        schemaMessage [ScopeKey "a"] "expected local date but got locate date" @?= "a には日付を書きます（日付が書かれています）"
        schemaMessage [ScopeKey "n"] "integer out of range for Natural" @?= "n には 0 以上の整数を書きます"
        schemaMessage [ScopeKey "n"] "integer out of range for Int8" @?= "n の整数が大きすぎるか小さすぎます"
        schemaMessage [ScopeKey "c"] "expected single character" @?= "c には一文字を書きます"
        schemaMessage [ScopeKey "x"] "finite float required" @?= "x には有限の数を書きます（inf と nan は使えません）"
        schemaMessage [ScopeKey "xs"] "non-empty list required" @?= "xs には空でない配列を書きます"
        syntaxMessage "lexical error: unterminated basic string" @?= "文字列が閉じていません"
        syntaxMessage "lexical error: unexpected '@'" @?= "ここに '@' は書けません"
        syntaxMessage "lexical error: malformed offset date-time" @?= "時差つきの日時の書き方が不正です"
        syntaxMessage "parse error: unexpected '='" @?= "ここに'='は書けません"
        syntaxMessage "parse error: unexpected end-of-line" @?= "ここに行末は書けません"
        syntaxMessage "parse error: unexpected bare key" @?= "ここにキーは書けません"
        semanticMessage AlreadyAssigned "a" @?= "同じキーに二度値を書いています: a"
        semanticMessage ClosedTable "a" @?= "閉じた表にキーを足しています: a"
        semanticMessage ImplicitlyTable "a" @?= "表として定まったキーを表の配列にはできません: a",
      testCase "the path" $ do
        pathText [] @?= ""
        pathText [ScopeKey "chapters", ScopeIndex 0] @?= "chapters[0]"
        pathText [ScopeKey "paragraph-styles", ScopeKey "body", ScopeKey "font"] @?= "paragraph-styles.body.font"
        schemaMessage [ScopeKey "chapters", ScopeIndex 0] "章は、ファイルのパス、表、配列のどれかで書きます" @?= "章は、ファイルのパス、表、配列のどれかで書きます (chapters[0])",
      testCase "a message not in the tables is kept" $ do
        schemaMessage [] "foo" @?= "foo"
        syntaxMessage "foo" @?= "foo",
      testCase "the lexical errors of toml-parser are in the tables" $
        mapM_
          (\(src, ja) -> syntaxOf src @?= Just ja)
          [ ("a = \"abc", "文字列が閉じていません"),
            ("a = 'abc", "リテラル文字列が閉じていません"),
            ("a = \"\"\"abc", "複数行の文字列が閉じていません"),
            ("a = '''abc", "複数行のリテラル文字列が閉じていません"),
            ("a = \"abc\n", "行が途中で終わっています"),
            ("a = 1\x01", "制御文字は書けません"),
            ("a = \"\x01\"", "制御文字はエスケープします（\\u0001 と書きます）"),
            ("a = @", "ここに '@' は書けません"),
            ("a = \"\\uD800\"", "サロゲートの符号位置は \\u で書けません"),
            ("a = \"\\U00110000\"", "\\U の値が Unicode の範囲を超えています"),
            ("a = 1979-13-01", "日付の書き方が不正です"),
            ("a = 07:99:00", "時刻の書き方が不正です"),
            ("a = 1979-05-27T25:00:00", "時差のない日時の書き方が不正です"),
            ("a = 012", "整数の先頭に 0 は書けません"),
            ("a = \"\\q\"", "知らないエスケープです"),
            ("a = \"\\", "エスケープが途中で終わっています")
          ],
      testCase "the parse errors of toml-parser are in the tables" $
        mapM_
          (\(src, ja) -> syntaxOf src @?= Just ja)
          [ ("a = ", "ここにファイルの終わりは書けません"),
            ("a = \n", "ここに行末は書けません"),
            ("= 1", "ここに'='は書けません"),
            ("a = 1 b", "ここにキーは書けません"),
            ("a = 1 'x'", "ここに文字列は書けません"),
            ("a = 1 \"\"\"x\"\"\"", "ここに複数行の文字列は書けません"),
            ("a = [1,,]", "ここに','は書けません")
          ],
      testCase "the semantic errors of toml-parser" $
        mapM_
          (\(src, ja) -> semanticOf src @?= Just ja)
          [ ("a = 1\na = 2\n", "同じキーに二度値を書いています: a"),
            ("[a]\n[a]\n", "閉じた表にキーを足しています: a"),
            ("[a.b]\n[[a]]\n", "表として定まったキーを表の配列にはできません: a")
          ],
      testCase "the schema errors of toml-parser are in the tables" $ do
        schemaOf (reqKey @Integer "a") "a = 1\nb = 2\n" @?= ["知らないキーです: b"]
        schemaOf (reqKey @Integer "a") "" @?= ["必須のキーがありません: a"]
        schemaOf (reqKey @Text "a") "a = 1\n" @?= ["a には文字列を書きます（整数が書かれています）"]
        schemaOf (reqKey @Integer "a") "a = 1.5\n" @?= ["a には整数を書きます（小数が書かれています）"]
        schemaOf (reqKey @Bool "a") "a = 1979-01-01\n" @?= ["a には真偽値を書きます（日付が書かれています）"]
        schemaOf (reqKey @Natural "a") "a = -1\n" @?= ["a には 0 以上の整数を書きます"]
        schemaOf (reqKey @Int8 "a") "a = 1000\n" @?= ["a の整数が大きすぎるか小さすぎます"]
        schemaOf (reqKey @Char "a") "a = \"ab\"\n" @?= ["a には一文字を書きます"]
        schemaOf (reqKey @(Ratio Integer) "a") "a = inf\n" @?= ["a には有限の数を書きます（inf と nan は使えません）"]
        schemaOf (reqKey @(NonEmpty Integer) "a") "a = []\n" @?= ["a には空でない配列を書きます"]
    ]

-- | The messages of the schema, with every pair of expected and actual types.
schemaMessages :: [String]
schemaMessages =
  [ "unexpected key: bindng",
    "unexpected key: \"a b\"",
    "missing key: metadata",
    "integer out of range for Natural",
    "integer out of range for Int",
    "integer out of range for Word8",
    "expected single character",
    "finite float required",
    "non-empty list required"
  ]
    <> ["expected " <> w <> " but got " <> g | w <- wanted, g <- got]
  where
    wanted = ["integer", "float", "array", "table", "boolean", "string", "local date", "local time", "local date-time", "offset date-time"]
    got = ["integer", "float", "array", "table", "boolean", "string", "local time", "local date-time", "locate date", "offset date-time"]

-- | The lexical and parse messages, with every token of 'Toml.Pretty.prettyToken'.
syntaxMessages :: [String]
syntaxMessages =
  map
    ("lexical error: " <>)
    [ "unterminated basic string",
      "unterminated literal string",
      "unterminated multi-line basic string",
      "unterminated multi-line literal string",
      "unexpected end-of-input",
      "unexpected end-of-line",
      "control characters prohibited",
      "control characters must be escaped, use: \\u0001",
      "unexpected '@'",
      "non-scalar unicode escape",
      "unicode escape too large",
      "malformed local date",
      "malformed local time",
      "malformed local date-time",
      "malformed offset date-time",
      "leading zero prohibited",
      "unknown escape sequence",
      "incomplete escape sequence"
    ]
    <> map
      ("parse error: unexpected " <>)
      [ "','",
        "'='",
        "'.'",
        "'['",
        "']'",
        "'[['",
        "']]'",
        "'{'",
        "'}'",
        "end-of-line",
        "bare key",
        "true literal",
        "false literal",
        "string",
        "multi-line string",
        "integer",
        "float",
        "offset date-time",
        "local date-time",
        "local date",
        "local time",
        "end-of-input"
      ]

syntaxOf :: Text -> Maybe Text
syntaxOf src = case parseRawToml src of
  Left (Located _ m) -> Just (syntaxMessage m)
  Right _ -> Nothing

semanticOf :: Text -> Maybe Text
semanticOf src = case parseRawToml src of
  Left _ -> Nothing
  Right es -> case semantics es of
    Left (SemanticError _ k kind) -> Just (semanticMessage kind k)
    Right _ -> Nothing

schemaOf :: ParseTable Position a -> Text -> [Text]
schemaOf p src = case Toml.parse src of
  Left e -> [T.pack e]
  Right t -> case runMatcher (parseTableFromValue p (Toml.Table' (Position 0 1 1) t)) of
    Failure es -> map message es
    Success ws _ -> map message ws
  where
    message (MatchMessage _ path m) = schemaMessage path m
