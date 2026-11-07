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
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding (decodeUtf8', decodeUtf8Lenient)
import Data.Text.Unsafe (lengthWord8)
import Golem.Syntax
import Golem.Syntax.Read (checkSourceText, invalidOffset, readSourceBytes)

{- | A failure of the reading stage ('readSource'). The file that failed is
in the table too, with its line index, so that the diagnostics show where
they point (golem-parser ADR 0009).
-}
data ReadFailure = ReadFailure
  { rfDiagnostics :: ![Diagnostic],
    rfSources :: !(Map FileId SourceInfo)
  }

{- | Rejects a BOM at the start, invalid UTF-8 and any CR, in this order;
only the first that applies is reported (golem-syntax's 'readSourceBytes',
shared with golem-emet, docs/adr/0173).
-}
readSource :: FileId -> ByteString -> Either [Diagnostic] Text
readSource = readSourceBytes

{- | The reading stage of a table file, a CSV or a TSV (golem-eval ADR
0004): invalid UTF-8 is G01001, as in a source file; a BOM at the start is
not an error, and stays in the text (the table readers skip it, and count
its bytes); a CR not before an LF is G02082. CRLF is not an error.
-}
readTableSource :: FileId -> ByteString -> Either [Diagnostic] Text
readTableSource fid bs = case decodeUtf8' bs of
  Left _ ->
    let bad = invalidOffset bs
     in Left [diagnostic "G01001" Error (mkSpan fid bad (bad + 1)) "UTF-8 として不正なバイト列があります"]
  Right t -> case checkTableText fid t of
    [] -> Right t
    ds -> Left ds

{- | The check of 'readTableSource' left after decoding: the first CR that
is not before an LF, G02082 (golem-eval ADR 0004). At most one diagnostic.
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
             in [diagnostic "G02082" Error (mkSpan fid i (i + 1)) "単独の CR があります。表のファイルの改行は LF か CRLF に限ります"]

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
checkText = checkSourceText
