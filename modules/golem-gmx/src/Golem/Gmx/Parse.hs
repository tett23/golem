{- | Reading and parsing a .gmx file (docs/adr/0148): UTF-8 without a BOM
or CR, as a .gm file (G01001 to G01003), then the grammar (G10100 to
G10102).
-}
module Golem.Gmx.Parse
  ( readGmx,
    checkGmxText,
    parseModule,
    lineOf,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAsciiLower, isHexDigit)
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Golem.Gmx.Generated qualified as G
import Golem.Gmx.Syntax
import Golem.Syntax
import Numeric (readHex)
import Peg.Runtime (Expected (..), ParseError (..), Pos (..))

{- | The reading stage of a .gmx file: G01002 for a BOM, G01001 for invalid
UTF-8, G01003 for a CR, as for a .gm file (golem-parser ADR 0009); the
causes are the same, and so are the codes.
-}
readGmx :: FileId -> ByteString -> Either [Diagnostic] Text
readGmx fid bs
  | "\xEF\xBB\xBF" `BS.isPrefixOf` bs = Left [bomDiagnostic fid]
  | otherwise = case decodeUtf8' bs of
      Left _ ->
        let bad = invalidOffset bs
         in Left [diagnostic "G01001" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
      Right t -> case checkGmxText fid t of
        [] -> Right t
        ds -> Left ds

-- | The checks of 'readGmx' on a decoded text: a BOM, then a CR.
checkGmxText :: FileId -> Text -> [Diagnostic]
checkGmxText fid t
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

{- | Parses a .gmx file after the checks of reading. The first error only:
the grammar has no recovery.
-}
parseModule :: FileId -> Text -> Either [Diagnostic] Module
parseModule fid src = case checkGmxText fid src of
  ds@(_ : _) -> Left ds
  [] -> case G.parse src of
    Left e -> Left [parseErrorDiagnostic fid src e]
    Right m -> case escapeErrors fid src of
      [] -> Right m
      ds -> Left ds

parseErrorDiagnostic :: FileId -> Text -> ParseError -> Diagnostic
parseErrorDiagnostic fid src e =
  let off = posOffset (parseErrorPos e)
      at n = mkSpan fid off (off + n)
   in case parseErrorLabel e of
        Just "reserved" ->
          -- the farthest position is the end of the word the lookahead read
          let back = BS.length (BS.takeWhileEnd (\b -> b >= 97 && b <= 122) (BS.take off (encodeUtf8 src)))
              start = off - back
              w = T.takeWhile isAsciiLower (afterOffset start src)
           in diagnostic "G10102" Error (mkSpan fid start (start + BS.length (encodeUtf8 w))) (w <> " は .gmx で使えない予約語です。分岐はパターンマッチ、ガード、case、三項演算子で、繰り返しは再帰で書きます")
        Just "unclosed_paren" -> diagnostic "G10101" Error (at 0) "閉じていない ( があります。) が要ります"
        Just "unclosed_bracket" -> diagnostic "G10101" Error (at 0) "閉じていない [ があります。] が要ります"
        Just "unclosed_brace" -> diagnostic "G10101" Error (at 0) "閉じていない { があります。} が要ります"
        Just "unclosed_string" -> diagnostic "G10101" Error (at 0) "閉じていない文字列があります。\" が要ります"
        _ ->
          let next = T.take 1 (afterOffset off src)
           in diagnostic "G10100" Error (at (BS.length (encodeUtf8 next))) ("構文の誤りです。" <> expected (parseErrorExpected e))
  where
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

{- | The escapes @\\u{...}@ of string literals that are no Unicode scalar
value (a surrogate or past U+10FFFF): G10100 at the escape. A string
cannot hold them, and the text is not changed silently.
-}
escapeErrors :: FileId -> Text -> [Diagnostic]
escapeErrors fid src = go 0 (T.unpack src) False
  where
    go :: Int -> String -> Bool -> [Diagnostic]
    go _ [] _ = []
    go off s inStr = case s of
      '-' : '-' : rest | not inStr -> let (c, r) = break (== '\n') rest in go (off + 2 + bytes c) r False
      '"' : rest -> go (off + 1) rest (not inStr)
      '\\' : 'u' : '{' : rest
        | inStr ->
            let (h, r) = span isHexDigit rest
                n = case readHex h of
                  [(v, "")] -> v :: Integer
                  _ -> 0
                len = 3 + length h + 1
                bad = n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF)
             in [diagnostic "G10100" Error (mkSpan fid off (off + len)) ("\\u{" <> T.pack h <> "} は Unicode のスカラー値ではありません") | bad] <> go (off + len) (drop 1 r) inStr
      '\\' : c : rest | inStr -> go (off + 1 + bytes [c]) rest inStr
      c : rest -> go (off + bytes [c]) rest inStr
    bytes = BS.length . encodeUtf8 . T.pack

-- | The line (from 1) of a byte offset.
lineOf :: Text -> Int -> Int
lineOf src off = 1 + BS.count 10 (BS.take off (encodeUtf8 src))
