-- | Human-readable and JSON renderings of diagnostics.
module Golem.Syntax.Render
  ( SourceInfo (..),
    renderHuman,
    renderJson,
  )
where

import Data.Char (ord)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Diagnostic
import Golem.Syntax.Position
import Golem.Syntax.Span
import Golem.Syntax.Text (tshow)
import Numeric (showHex)

-- | What the renderers need to know about each file.
data SourceInfo = SourceInfo
  { siPath :: !FilePath,
    siLines :: !LineIndex
  }

severityText :: Severity -> Text
severityText Error = "error"
severityText Warning = "warning"
severityText Notice = "notice"
severityText Info = "info"

codeText :: DiagnosticCode -> Text
codeText (DiagnosticCode c) = c

location :: Map FileId SourceInfo -> SrcSpan -> (Text, Maybe (LineIndex, LineCol))
location files sp = case Map.lookup (spanFile sp) files of
  Nothing -> ("<unknown>", Nothing)
  Just si ->
    let lc = offsetToLineCol (siLines si) (spanStart sp)
     in (T.pack (siPath si), Just (siLines si, lc))

{- | Whether the human rendering writes a character in its visible form
(docs/adr ADR 0042): the C0 controls but the tab, DEL and the C1 controls.
A newline of a message is written as it is.
-}
isTerminalControl :: Char -> Bool
isTerminalControl c = (c < ' ' && c /= '\t') || (c >= '\DEL' && c <= '\x9F')

-- | A character as the human rendering writes it: a control as @\\x1b@.
visibleChar :: Char -> Text
visibleChar c
  | isTerminalControl c = T.pack ("\\x" <> pad2 (showHex (ord c) ""))
  | otherwise = T.singleton c
  where
    pad2 s = replicate (2 - length s) '0' <> s

-- | A text with every control in its visible form.
visible :: Text -> Text
visible = T.concatMap visibleChar

-- | 'visible' that keeps the newlines of a message.
visibleMessage :: Text -> Text
visibleMessage = T.intercalate "\n" . map visible . T.splitOn "\n"

-- | The most characters of a source line that the human rendering writes.
excerptWidth :: Int
excerptWidth = 200

-- | The most characters of a long source line before the column.
excerptBefore :: Int
excerptBefore = 60

{- | A source line as the human rendering writes it (docs/adr ADR 0042):
the controls visible, and a line longer than 'excerptWidth' after that
cut to the window around the column, with an ellipsis at each cut end.
A character made visible is not cut; the CR of a CRLF line is dropped.
-}
excerptOf :: Text -> Int -> Text
excerptOf line0 col
  | total <= excerptWidth = T.concat pieces
  | otherwise =
      (if skipped > 0 then "…" else "")
        <> T.concat kept
        <> (if skipped + length kept < length pieces then "…" else "")
  where
    line = fromMaybe line0 (T.stripSuffix "\r" line0)
    pieces = map visibleChar (T.unpack line)
    widths = map T.length pieces
    total = sum widths
    -- the start of the column after the replacement
    at = sum (take col widths)
    start = max 0 (at - excerptBefore)
    -- whole pieces from the first that starts at or after start, while they fit
    starts = scanl (+) 0 widths
    skipped = length (takeWhile (< start) (take (length pieces) starts))
    kept = fitting excerptWidth (drop skipped pieces)
    fitting room = \case
      p : ps | T.length p <= room -> p : fitting (room - T.length p) ps
      _ -> []

{- | @path:line:col: severity[code]: message@ followed by the source line.
Lines and columns are one-based for humans. Control characters are
written in their visible form, and a long source line is cut (docs/adr
ADR 0042).
-}
renderHuman :: Map FileId SourceInfo -> [Diagnostic] -> Text
renderHuman files = T.concat . map one . sortDiagnostics
  where
    one d =
      let (path, mpos) = location files (diagSpan d)
          posText = case mpos of
            Just (_, LineCol l c) -> T.pack (show (l + 1)) <> ":" <> T.pack (show (c + 1))
            Nothing -> "?:?"
          header =
            visible path
              <> ":"
              <> posText
              <> ": "
              <> severityText (diagSeverity d)
              <> "["
              <> codeText (diagCode d)
              <> "]: "
              <> visibleMessage (diagMessage d)
              <> "\n"
          excerpt = case mpos of
            Just (li, LineCol l c) -> "  | " <> excerptOf (lineText li l) c <> "\n"
            Nothing -> ""
          related =
            T.concat
              [ "  = " <> visible (fst (location files sp)) <> relPos sp <> ": " <> visibleMessage msg <> "\n"
              | (sp, msg) <- diagRelated d
              ]
          relPos sp = case snd (location files sp) of
            Just (_, LineCol l c) -> ":" <> T.pack (show (l + 1)) <> ":" <> T.pack (show (c + 1))
            Nothing -> ""
       in header <> excerpt <> related

jsonString :: Text -> Text
jsonString t = "\"" <> T.concatMap esc t <> "\""
  where
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc '\n' = "\\n"
    esc '\r' = "\\r"
    esc '\t' = "\\t"
    esc c
      | ord c < 0x20 = T.pack ("\\u" <> pad (showHex (ord c) ""))
      | otherwise = T.singleton c
    pad s = replicate (4 - length s) '0' <> s

jsonSpan :: Map FileId SourceInfo -> SrcSpan -> Text
jsonSpan files sp =
  let (path, mpos) = location files sp
      (l, c) = maybe (0, 0) (\(_, LineCol a b) -> (a, b)) mpos
   in "{\"file\":"
        <> jsonString path
        <> ",\"start\":"
        <> tshow (spanStart sp)
        <> ",\"end\":"
        <> tshow (spanEnd sp)
        <> ",\"line\":"
        <> tshow (l + 1)
        <> ",\"column\":"
        <> tshow (c + 1)
        <> "}"

-- | A JSON array with a fixed key order, one diagnostic per element.
renderJson :: Map FileId SourceInfo -> [Diagnostic] -> Text
renderJson files ds = "[" <> T.intercalate "," (map one (sortDiagnostics ds)) <> "]\n"
  where
    one d =
      "{\"code\":"
        <> jsonString (codeText (diagCode d))
        <> ",\"severity\":"
        <> jsonString (severityText (diagSeverity d))
        <> ",\"span\":"
        <> jsonSpan files (diagSpan d)
        <> ",\"message\":"
        <> jsonString (diagMessage d)
        <> ",\"related\":["
        <> T.intercalate "," [rel sp m | (sp, m) <- diagRelated d]
        <> "],\"fixes\":["
        <> T.intercalate "," (map fix (diagFixes d))
        <> "]"
        <> facts (diagFacts d)
        <> "}"
    -- only a diagnostic with facts has the key (golem-cli ADR 0006)
    facts [] = ""
    facts fs = ",\"facts\":{" <> T.intercalate "," [jsonString k <> ":" <> factJson v | (k, v) <- fs] <> "}"
    factJson = \case
      FactInt i -> T.pack (show i)
      FactText t -> jsonString t
      FactInts is -> "[" <> T.intercalate "," (map (T.pack . show) is) <> "]"
      FactTexts ts -> "[" <> T.intercalate "," (map jsonString ts) <> "]"
    rel sp m = "{\"span\":" <> jsonSpan files sp <> ",\"message\":" <> jsonString m <> "}"
    fix f =
      "{\"title\":"
        <> jsonString (fixTitle f)
        <> ",\"edits\":["
        <> T.intercalate "," [edit sp t | (sp, t) <- fixEdits f]
        <> "]}"
    edit sp t = "{\"span\":" <> jsonSpan files sp <> ",\"text\":" <> jsonString t <> "}"
