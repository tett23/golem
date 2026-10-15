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
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Diagnostic
import Golem.Syntax.Position
import Golem.Syntax.Span
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

codeText :: DiagnosticCode -> Text
codeText (DiagnosticCode c) = c

location :: Map FileId SourceInfo -> SrcSpan -> (Text, Maybe (LineIndex, LineCol))
location files sp = case Map.lookup (spanFile sp) files of
  Nothing -> ("<unknown>", Nothing)
  Just si ->
    let lc = offsetToLineCol (siLines si) (spanStart sp)
     in (T.pack (siPath si), Just (siLines si, lc))

{- | @path:line:col: severity[code]: message@ followed by the source line.
Lines and columns are one-based for humans.
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
            path
              <> ":"
              <> posText
              <> ": "
              <> severityText (diagSeverity d)
              <> "["
              <> codeText (diagCode d)
              <> "]: "
              <> diagMessage d
              <> "\n"
          excerpt = case mpos of
            Just (li, LineCol l _) -> "  | " <> lineText li l <> "\n"
            Nothing -> ""
          related =
            T.concat
              [ "  = " <> fst (location files sp) <> relPos sp <> ": " <> msg <> "\n"
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

tshow :: Int -> Text
tshow = T.pack . show

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
        <> "]}"
    rel sp m = "{\"span\":" <> jsonSpan files sp <> ",\"message\":" <> jsonString m <> "}"
    fix f =
      "{\"title\":"
        <> jsonString (fixTitle f)
        <> ",\"edits\":["
        <> T.intercalate "," [edit sp t | (sp, t) <- fixEdits f]
        <> "]}"
    edit sp t = "{\"span\":" <> jsonSpan files sp <> ",\"text\":" <> jsonString t <> "}"
