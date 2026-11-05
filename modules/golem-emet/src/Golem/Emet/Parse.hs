{- | Reading and parsing a .emet file (docs/adr/0160): UTF-8 without a BOM
or CR, as a .gm file (G01001 to G01003), then the grammar (E01100 to
E01102).
-}
module Golem.Emet.Parse
  ( readEmet,
    checkEmetText,
    parseModule,
    lineOf,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isHexDigit)
import Data.List (sort)
import Data.Maybe (isJust, isNothing)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Data.Text.Encoding qualified as TE
import Golem.Emet.Generated qualified as G
import Golem.Emet.Syntax
import Golem.Syntax
import Numeric (readHex)
import Peg.Runtime (Expected (..), ParseError (..), Pos (..))

{- | The reading stage of a .emet file: G01002 for a BOM, G01001 for invalid
UTF-8, G01003 for a CR, as for a .gm file (golem-parser ADR 0009); the
causes are the same, and so are the codes.
-}
readEmet :: FileId -> ByteString -> Either [Diagnostic] Text
readEmet fid bs
  | "\xEF\xBB\xBF" `BS.isPrefixOf` bs = Left [bomDiagnostic fid]
  | otherwise = case decodeUtf8' bs of
      Left _ ->
        let bad = invalidOffset bs
         in Left [diagnostic "G01001" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
      Right t -> case checkEmetText fid t of
        [] -> Right t
        ds -> Left ds

-- | The checks of 'readEmet' on a decoded text: a BOM, then a CR.
checkEmetText :: FileId -> Text -> [Diagnostic]
checkEmetText fid t
  | "\xFEFF" `T.isPrefixOf` t = [bomDiagnostic fid]
  | otherwise = case T.breakOn "\r" t of
      (pre, rest)
        | T.null rest -> []
        | otherwise ->
            let i = BS.length (encodeUtf8 pre)
             in [(diagnostic "G01003" Error (mkSpan fid i (i + 1)) "改行に CR が含まれています。改行は LF に限ります") {diagFixes = [Fix "golem fmt で LF に直す" []]}]

bomDiagnostic :: FileId -> Diagnostic
bomDiagnostic fid = diagnostic "G01002" Error (mkSpan fid 0 3) "ファイルの先頭に BOM があります。BOM を取り除いてください"

-- | The first byte offset at which UTF-8 decoding fails (as golem-parser's).
invalidOffset :: ByteString -> Int
invalidOffset bs = go 0
  where
    n = BS.length bs
    go i
      | i >= n = n
      | otherwise =
          let b = BS.index bs i
              len
                | b < 0x80 = 1
                | b >= 0xC2 && b < 0xE0 = 2
                | b >= 0xE0 && b < 0xF0 = 3
                | b >= 0xF0 && b < 0xF5 = 4
                | otherwise = 0
           in if len == 0 || i + len > n || either (const True) (const False) (decodeUtf8' (BS.take len (BS.drop i bs)))
                then i
                else go (i + len)

{- | Parses a .emet file after the checks of reading. The first error only:
the grammar has no recovery (docs/adr/0160).
-}
parseModule :: FileId -> Text -> Either [Diagnostic] Module
parseModule fid src = case checkEmetText fid src of
  ds@(_ : _) -> Left ds
  [] -> case G.parse src of
    Left e -> Left [parseErrorDiagnostic fid src e]
    Right m -> case escapeErrors fid src of
      [] -> Right m
      ds -> Left ds

-- | The words that are reserved and cannot be used (E01102).
unusableWords :: [Text]
unusableWords = ["if", "then", "else", "for", "while", "let", "in", "lazy", "class", "instance", "deriving", "default"]

{- | E01101 for a label of an unclosed bracket or quote; E01102 when the
parse stops at a word that is reserved and cannot be used (no rule reads
it); E01100 otherwise, with the tokens expected there.
-}
parseErrorDiagnostic :: FileId -> Text -> ParseError -> Diagnostic
parseErrorDiagnostic fid src e =
  let off = posOffset (parseErrorPos e)
      at n = mkSpan fid off (off + n)
   in case parseErrorLabel e of
        Just "unclosed_paren" -> diagnostic "E01101" Error (at 0) "閉じていない ( があります。) が要ります"
        Just "unclosed_bracket" -> diagnostic "E01101" Error (at 0) "閉じていない [ があります。] が要ります"
        Just "unclosed_brace" -> diagnostic "E01101" Error (at 0) "閉じていない { があります。} が要ります"
        Just "unclosed_string" -> diagnostic "E01101" Error (at 0) "閉じていない文字列があります。\" が要ります"
        Just "unclosed_char" -> diagnostic "E01101" Error (at 0) "閉じていない文字のリテラルがあります。' が要ります"
        _ -> case wordAt off of
          Just (start, w)
            | w `elem` unusableWords ->
                diagnostic "E01102" Error (mkSpan fid start (start + BS.length (encodeUtf8 w))) (w <> " は .emet で使えない予約語です" <> hint w)
          _ ->
            let next = T.take 1 (afterOffset off src)
             in diagnostic "E01100" Error (at (BS.length (encodeUtf8 next))) ("構文の誤りです。" <> expected (parseErrorExpected e))
  where
    bytes = encodeUtf8 src
    isWordByte b = (b >= 97 && b <= 122) || (b >= 65 && b <= 90) || (b >= 48 && b <= 57) || b == 95
    -- the word the offset is in, at the start of or just after
    wordAt off =
      let start = off - BS.length (BS.takeWhileEnd isWordByte (BS.take off bytes))
          w = TE.decodeUtf8 (BS.takeWhile isWordByte (BS.drop start bytes))
       in if T.null w then Nothing else Just (start, w)
    hint w
      | w `elem` ["if", "then", "else"] = "。分岐はガード、case、三項演算子で書きます"
      | w `elem` ["for", "while"] = "。繰り返しは再帰で書きます"
      | w `elem` ["let", "in"] = "。局所の定義は関数の末尾の where に書きます"
      | w == "lazy" = "。where の束縛はどれも、使ったときに一度だけ評価します"
      | otherwise = "。型クラスのために予約しています"
    expected es = case sort (Set.toList es) of
      [] -> "ここは解釈できません"
      xs -> T.intercalate "、" (map expectedText xs) <> " が要ります"
    expectedText = \case
      ExpectedLiteral t -> t
      ExpectedClass t -> t
      ExpectedAny -> "任意の一字"
      ExpectedEnd -> "ファイルの終わり"

afterOffset :: Int -> Text -> Text
afterOffset off src = T.pack (decodeAfter (BS.drop off (encodeUtf8 src)))
  where
    decodeAfter b = either (const "") T.unpack (decodeUtf8' b)

{- | The escapes @\\u{...}@ of string and character literals that are no
Unicode scalar value (a surrogate or past U+10FFFF): E01100 at the
escape. A string cannot hold them, and the text is not changed silently.
-}
escapeErrors :: FileId -> Text -> [Diagnostic]
escapeErrors fid src = go 0 (T.unpack src) Nothing
  where
    -- the quote of the literal the scan is in
    go :: Int -> String -> Maybe Char -> [Diagnostic]
    go _ [] _ = []
    go off s quote = case s of
      '-' : '-' : rest | isNothing quote -> let (c, r) = break (== '\n') rest in go (off + 2 + bytes c) r Nothing
      q : rest | q `elem` ['"', '\''], isNothing quote -> go (off + 1) rest (Just q)
      q : rest | Just q == quote -> go (off + 1) rest Nothing
      '\\' : 'u' : '{' : rest
        | isJust quote ->
            let (h, r) = span isHexDigit rest
                n = case readHex h of
                  [(v, "")] -> v :: Integer
                  _ -> 0
                len = 3 + length h + 1
                bad = n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)
             in [diagnostic "E01100" Error (mkSpan fid off (off + len)) ("\\u{" <> T.pack h <> "} は Unicode のスカラー値ではありません") | bad] <> go (off + len) (drop 1 r) quote
      '\\' : c : rest | isJust quote -> go (off + 1 + bytes [c]) rest quote
      c : rest -> go (off + bytes [c]) rest quote
    bytes = BS.length . encodeUtf8 . T.pack

-- | The line (from 1) of a byte offset.
lineOf :: Text -> Int -> Int
lineOf src off = 1 + BS.count 10 (BS.take off (encodeUtf8 src))
