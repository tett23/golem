-- | The reading stage before parsing (golem-parser ADR 0002, ADR 0009).
module Golem.Parser.Read
  ( readSource,
    checkText,
    ReadFailure (..),
    readSourceFile,
    readInfo,
    readTableSource,
    checkTableText,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', decodeUtf8Lenient, encodeUtf8)
import Data.Text.Unsafe (lengthWord8)
import Golem.Syntax

{- | A failure of the reading stage ('readSource'). The file that failed is
in the table too, with its line index, so that the diagnostics show where
they point (golem-parser ADR 0009).
-}
data ReadFailure = ReadFailure
  { rfDiagnostics :: ![Diagnostic],
    rfSources :: !(Map FileId SourceInfo)
  }

{- | Rejects a BOM at the start, invalid UTF-8 and any CR, in this order;
only the first that applies is reported.
-}
readSource :: FileId -> ByteString -> Either [Diagnostic] Text
readSource fid bs
  | "\xEF\xBB\xBF" `BS.isPrefixOf` bs = Left [bomDiagnostic fid]
  | otherwise = case decodeUtf8' bs of
      Left _ ->
        let bad = invalidOffset bs
         in Left [diagnostic "G0101" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
      Right t -> case checkText fid t of
        [] -> Right t
        ds -> Left ds

{- | The reading stage of a table file, a CSV or a TSV (golem-eval ADR
0004): invalid UTF-8 is G0101, as in a source file; a BOM at the start is
not an error, and stays in the text (the table readers skip it, and count
its bytes); a CR not before an LF is G0282. CRLF is not an error.
-}
readTableSource :: FileId -> ByteString -> Either [Diagnostic] Text
readTableSource fid bs = case decodeUtf8' bs of
  Left _ ->
    let bad = invalidOffset bs
     in Left [diagnostic "G0101" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
  Right t -> case checkTableText fid t of
    [] -> Right t
    ds -> Left ds

{- | The check of 'readTableSource' left after decoding: the first CR that
is not before an LF, G0282 (golem-eval ADR 0004). At most one diagnostic.
-}
checkTableText :: FileId -> Text -> [Diagnostic]
checkTableText fid = go 0
  where
    go !off t = case T.break (== '\r') t of
      (pre, rest) -> case T.uncons rest of
        Nothing -> []
        Just (_, r) -> case T.uncons r of
          Just ('\n', r') -> go (off + lengthWord8 pre + 2) r'
          _ ->
            let i = off + lengthWord8 pre
             in [diagnostic "G0282" Error (mkSpan fid i (i + 1)) "単独の CR があります。表のファイルの改行は LF か CRLF に限ります"]

{- | 'readSource' for the file at @path@: on failure, the diagnostics and
the file's entry in the source table.
-}
readSourceFile :: FileId -> FilePath -> ByteString -> Either ReadFailure Text
readSourceFile fid path bs = case readSource fid bs of
  Left ds -> Left (ReadFailure ds (Map.singleton fid (readInfo path bs)))
  Right t -> Right t

{- | What the renderers need of a file that may not have passed the reading
stage: its line index over the bytes decoded leniently (an invalid byte
becomes U+FFFD, so positions after it shift).
-}
readInfo :: FilePath -> ByteString -> SourceInfo
readInfo path = SourceInfo path . mkLineIndex . decodeUtf8Lenient

{- | The checks of 'readSource' left after decoding: a BOM (U+FEFF at the
start) and CR. At most one diagnostic.
-}
checkText :: FileId -> Text -> [Diagnostic]
checkText fid t
  | "\xFEFF" `T.isPrefixOf` t = [bomDiagnostic fid]
  | otherwise = case T.breakOn "\r" t of
      (pre, rest)
        | T.null rest -> []
        | otherwise ->
            let i = BS.length (encodeUtf8 pre)
             in [ (diagnostic "G0103" Error (mkSpan fid i (i + 1)) "改行に CR が含まれています。改行は LF に限ります")
                    { diagFixes = [Fix "golem fmt で LF に直す" []]
                    }
                ]

bomDiagnostic :: FileId -> Diagnostic
bomDiagnostic fid = diagnostic "G0102" Error (mkSpan fid 0 3) "ファイルの先頭に BOM があります。BOM を取り除いてください"

-- | The first byte offset at which UTF-8 decoding fails.
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
           in if len == 0 || i + len > n || not (validSeq (BS.take len (BS.drop i bs)))
                then i
                else go (i + len)
    validSeq s = case decodeUtf8' s of
      Left _ -> False
      Right _ -> True
