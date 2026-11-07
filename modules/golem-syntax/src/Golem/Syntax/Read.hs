{- | The reading stage of a source file, before its grammar: a BOM at the
start (G01002), invalid UTF-8 (G01001) and CR (G01003), for a .gm file
(golem-parser ADR 0009) and a .emet file (docs/adr/0160). The causes are
the same, and so are the codes; golem-parser and golem-emet share this
module (docs/adr/0173).
-}
module Golem.Syntax.Read
  ( readSourceBytes,
    checkSourceText,
    bomDiagnostic,
    invalidOffset,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', encodeUtf8)
import Golem.Syntax.Diagnostic
import Golem.Syntax.Span

{- | Rejects a BOM at the start, invalid UTF-8 and any CR, in this order;
only the first that applies is reported.
-}
readSourceBytes :: FileId -> ByteString -> Either [Diagnostic] Text
readSourceBytes fid bs
  | "\xEF\xBB\xBF" `BS.isPrefixOf` bs = Left [bomDiagnostic fid]
  | otherwise = case decodeUtf8' bs of
      Left _ ->
        let bad = invalidOffset bs
         in Left [diagnostic "G01001" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
      Right t -> case checkSourceText fid t of
        [] -> Right t
        ds -> Left ds

{- | The checks of 'readSourceBytes' left after decoding: a BOM (U+FEFF at
the start), then CR. At most one diagnostic.
-}
checkSourceText :: FileId -> Text -> [Diagnostic]
checkSourceText fid t
  | "\xFEFF" `T.isPrefixOf` t = [bomDiagnostic fid]
  | otherwise = case T.breakOn "\r" t of
      (pre, rest)
        | T.null rest -> []
        | otherwise ->
            let i = BS.length (encodeUtf8 pre)
             in [ (diagnostic "G01003" Error (mkSpan fid i (i + 1)) "改行に CR が含まれています。改行は LF に限ります")
                    { diagFixes = [Fix "golem fmt で LF に直す" []]
                    }
                ]

-- | G01002: a BOM at the start of the file.
bomDiagnostic :: FileId -> Diagnostic
bomDiagnostic fid = diagnostic "G01002" Error (mkSpan fid 0 3) "ファイルの先頭に BOM があります。BOM を取り除いてください"

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
