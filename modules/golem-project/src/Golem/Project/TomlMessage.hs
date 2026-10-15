{-# LANGUAGE ViewPatterns #-}

{- | The messages of toml-parser in Japanese (golem-project ADR 0007).

toml-parser 2.0.2.0 writes its messages as strings, so the translation
matches the strings. A message not in the tables is returned as it is:
the messages Golem writes with 'fail' are already Japanese, and an English
message of another version of toml-parser is caught by the tests.
-}
module Golem.Project.TomlMessage
  ( schemaMessage,
    syntaxMessage,
    semanticMessage,
    pathText,
  )
where

import Data.List (stripPrefix)
import Data.Text (Text)
import Data.Text qualified as T
import Toml.Schema (Scope (..))
import Toml.Semantics (SemanticErrorKind (..))

{- | A message of the schema with its path. The path goes into the message;
a message not in the table keeps the path after it in parentheses, and an
empty path is not shown.
-}
schemaMessage :: [Scope] -> String -> Text
schemaMessage path msg = case translateSchema path msg of
  Just t -> t
  Nothing
    | null path -> T.pack msg
    | otherwise -> T.pack msg <> " (" <> pathText path <> ")"

translateSchema :: [Scope] -> String -> Maybe Text
translateSchema path msg
  | Just k <- stripPrefix "unexpected key: " msg = Just ("知らないキーです: " <> keyed k)
  | Just k <- stripPrefix "missing key: " msg = Just ("必須のキーがありません: " <> keyed k)
  | Just rest <- stripPrefix "expected " msg,
    (wanted, gotPart) <- T.breakOn " but got " (T.pack rest),
    Just got <- T.stripPrefix " but got " gotPart,
    Just w <- typeName wanted,
    Just g <- typeName got =
      Just (subject <> "には" <> w <> "を書きます（" <> g <> "が書かれています）")
  | msg == "integer out of range for Natural" = Just (subject <> "には 0 以上の整数を書きます")
  | Just _ <- stripPrefix "integer out of range for " msg = Just (subjectNo <> "整数が大きすぎるか小さすぎます")
  | msg == "expected single character" = Just (subject <> "には一文字を書きます")
  | msg == "finite float required" = Just (subject <> "には有限の数を書きます（inf と nan は使えません）")
  | msg == "non-empty list required" = Just (subject <> "には空でない配列を書きます")
  | otherwise = Nothing
  where
    keyed k
      | null path = T.pack k
      | otherwise = pathText path <> "." <> T.pack k
    -- a value at the top of the file has no path to name
    subject
      | null path = "値"
      | otherwise = pathText path <> " "
    subjectNo
      | null path = "値の"
      | otherwise = pathText path <> " の"

-- | The names of the types of toml-parser ('Toml.Semantics.Types.valueType' and the expected types).
typeName :: Text -> Maybe Text
typeName = \case
  "integer" -> Just "整数"
  "float" -> Just "小数"
  "string" -> Just "文字列"
  "boolean" -> Just "真偽値"
  "array" -> Just "配列"
  "table" -> Just "表"
  "local date" -> Just "日付"
  -- the spelling of toml-parser 2.0.2.0
  "locate date" -> Just "日付"
  "local time" -> Just "時刻"
  "local date-time" -> Just "時差のない日時"
  "offset date-time" -> Just "時差つきの日時"
  _ -> Nothing

-- | A lexical or parse error, without its position and its prefix.
syntaxMessage :: String -> Text
syntaxMessage msg = case msg of
  (stripPrefix "lexical error: " -> Just m) | Just t <- lexical m -> t
  (stripPrefix "parse error: unexpected " -> Just tok) | Just t <- tokenName (T.pack tok) -> "ここに" <> t <> "は書けません"
  _ -> T.pack msg

lexical :: String -> Maybe Text
lexical = \case
  "unterminated basic string" -> Just "文字列が閉じていません"
  "unterminated literal string" -> Just "リテラル文字列が閉じていません"
  "unterminated multi-line basic string" -> Just "複数行の文字列が閉じていません"
  "unterminated multi-line literal string" -> Just "複数行のリテラル文字列が閉じていません"
  "unexpected end-of-input" -> Just "ファイルが途中で終わっています"
  "unexpected end-of-line" -> Just "行が途中で終わっています"
  "control characters prohibited" -> Just "制御文字は書けません"
  "non-scalar unicode escape" -> Just "サロゲートの符号位置は \\u で書けません"
  "unicode escape too large" -> Just "\\U の値が Unicode の範囲を超えています"
  "leading zero prohibited" -> Just "整数の先頭に 0 は書けません"
  "unknown escape sequence" -> Just "知らないエスケープです"
  "incomplete escape sequence" -> Just "エスケープが途中で終わっています"
  (stripPrefix "control characters must be escaped, use: " -> Just esc) -> Just ("制御文字はエスケープします（" <> T.pack esc <> " と書きます）")
  (stripPrefix "malformed " -> Just kind) | Just t <- typeName (T.pack kind) -> Just (t <> "の書き方が不正です")
  (stripPrefix "unexpected " -> Just c@('\'' : _)) -> Just ("ここに " <> T.pack c <> " は書けません")
  _ -> Nothing

-- | The names of the tokens of 'Toml.Pretty.prettyToken'.
tokenName :: Text -> Maybe Text
tokenName tok
  | "'" `T.isPrefixOf` tok = Just tok
  | otherwise = case tok of
      "end-of-line" -> Just "行末"
      "end-of-input" -> Just "ファイルの終わり"
      "bare key" -> Just "キー"
      "string" -> Just "文字列"
      "multi-line string" -> Just "複数行の文字列"
      "integer" -> Just "整数"
      "float" -> Just "小数"
      "true literal" -> Just "真偽値"
      "false literal" -> Just "真偽値"
      _ -> typeName tok

-- | A semantic error of a key.
semanticMessage :: SemanticErrorKind -> Text -> Text
semanticMessage kind key = case kind of
  AlreadyAssigned -> "同じキーに二度値を書いています: " <> key
  ClosedTable -> "閉じた表にキーを足しています: " <> key
  ImplicitlyTable -> "表として定まったキーを表の配列にはできません: " <> key

-- | A path as page.bleed or chapters[0].
pathText :: [Scope] -> Text
pathText = T.concat . zipWith one [0 :: Int ..]
  where
    one i = \case
      ScopeKey k
        | i == 0 -> k
        | otherwise -> "." <> k
      ScopeIndex n -> "[" <> T.pack (show n) <> "]"
