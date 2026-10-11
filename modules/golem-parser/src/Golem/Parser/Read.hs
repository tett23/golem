-- | The reading stage before parsing (golem-parser ADR 0002).
module Golem.Parser.Read
  ( readSource,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text.Encoding (decodeUtf8')
import Golem.Syntax

-- | Rejects invalid UTF-8, a BOM and CRLF line endings.
readSource :: FileId -> ByteString -> Either [Diagnostic] Text
readSource fid bs
  | "\xEF\xBB\xBF" `BS.isPrefixOf` bs =
      Left [diagnostic "G0102" Error (mkSpan fid 0 3) "ファイルの先頭に BOM があります。BOM を取り除いてください"]
  | otherwise = case decodeUtf8' bs of
      Left _ ->
        let bad = invalidOffset bs
         in Left [diagnostic "G0101" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
      Right t -> case BS.findIndex (== 13) bs of
        Just i ->
          Left
            [ (diagnostic "G0103" Error (mkSpan fid i (i + 1)) "改行に CR が含まれています。改行は LF に限ります")
                { diagFixes = [Fix "golem fmt で LF に直す" []]
                }
            ]
        Nothing -> Right t

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
