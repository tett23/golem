{-# LANGUAGE MultiWayIf #-}

{- | The XML that SVG needs (golem-pdf ADR 0009): UTF-8 documents only;
elements, attributes, namespaces, text, CDATA, comments, processing
instructions (their targets kept, docs/adr/0158), character references and
the five predefined entity references. A DOCTYPE with an internal subset is refused, as
entities are never expanded.
-}
module Golem.Svg.Xml
  ( Pos (..),
    Element (..),
    Attr (..),
    Node (..),
    Document (..),
    parseXml,
    parseXmlDocument,
    xmlNs,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (chr, isAlphaNum, isHexDigit, isSpace)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Numeric (readHex)

-- | A line and a column, from 1, in characters.
data Pos = Pos {posLine :: !Int, posColumn :: !Int}
  deriving stock (Eq, Ord, Show)

data Element = Element
  { -- | the namespace (empty for none)
    elNs :: !Text,
    -- | the local name
    elName :: !Text,
    elAttrs :: ![Attr],
    elChildren :: ![Node],
    elPos :: !Pos
  }
  deriving stock (Eq, Show)

data Attr = Attr
  { atNs :: !Text,
    atName :: !Text,
    atValue :: !Text,
    atPos :: !Pos
  }
  deriving stock (Eq, Show)

data Node
  = NElement !Element
  | -- | text and CDATA, with references resolved
    NText !Text !Pos
  | {- | a processing instruction: its target and the place of its @<?@
    (docs/adr/0158); the drawing skips it
    -}
    NInstruction !Text !Pos
  deriving stock (Eq, Show)

-- | A document: its root and the processing instructions around it (docs/adr/0158).
data Document = Document
  { docRoot :: !Element,
    {- | the processing instructions before and after the root, in the
    order of the document; the XML declaration is not one
    -} docInstructions :: ![(Text, Pos)]
  }
  deriving stock (Eq, Show)

-- | The namespace of the @xml:@ prefix.
xmlNs :: Text
xmlNs = "http://www.w3.org/XML/1998/namespace"

-- | The input with the offset where it starts, for positions.
data Input = Input !Int !Text

type P a = Input -> Either Text (a, Input)

-- | The root element of a document.
parseXml :: ByteString -> Either Text Element
parseXml bytes = docRoot <$> parseXmlDocument bytes

-- | A document, with the processing instructions outside its root (docs/adr/0158).
parseXmlDocument :: ByteString -> Either Text Document
parseXmlDocument bytes = do
  decoded <- either (const (Left "UTF-8 として読めません")) Right (TE.decodeUtf8' (if "\xEF\xBB\xBF" `BS.isPrefixOf` bytes then BS.drop 3 bytes else bytes))
  let lineStarts = Map.fromList (zip (0 : [i + 1 | (i, c) <- zip [0 ..] (T.unpack decoded), c == '\n']) [1 ..])
      posAt off = case Map.lookupLE off lineStarts of
        Just (s, l) -> Pos l (off - s + 1)
        Nothing -> Pos 1 (off + 1)
  (before, start) <- prolog posAt (Input 0 decoded)
  (raw, rest) <- element posAt Map.empty start
  (instructions, end) <- misc posAt before rest
  case end of
    Input _ t | T.null t -> Right (Document raw (reverse instructions))
    _ -> Left "ルートの要素の後に余分なものがあります"

-- the input helpers

advance :: Int -> Input -> Input
advance n (Input o t) = Input (o + n) (T.drop n t)

rest' :: Input -> Text
rest' (Input _ t) = t

offset :: Input -> Int
offset (Input o _) = o

skipSpace :: Input -> Input
skipSpace i@(Input _ t) = advance (T.length (T.takeWhile isSpace t)) i

-- | Up to and past a delimiter.
upTo :: Text -> Text -> Input -> Either Text (Text, Input)
upTo what delim i =
  let (before, after) = T.breakOn delim (rest' i)
   in if T.null after then Left (what <> "が閉じていません") else Right (before, advance (T.length before + T.length delim) i)

-- | The XML declaration, comments, processing instructions (the last first) and a DOCTYPE before the root.
prolog :: (Int -> Pos) -> Input -> Either Text ([(Text, Pos)], Input)
prolog posAt i0 = do
  i1 <-
    if "<?xml" `T.isPrefixOf` rest' i0 && maybe False (isSpace . fst) (T.uncons (T.drop 5 (rest' i0)))
      then do
        (decl, i) <- upTo "XML の宣言" "?>" i0
        let enc = T.toLower <$> attrIn "encoding" decl
        if maybe True (`elem` ["utf-8", "utf8"]) enc then Right i else Left ("UTF-8 でない文字コードです: " <> fromMaybe "" (attrIn "encoding" decl))
      else Right i0
  go [] i1
  where
    go acc i = do
      (acc', i') <- misc posAt acc i
      let t = rest' i'
      if "<!DOCTYPE" `T.isPrefixOf` t
        then do
          let body = T.takeWhile (/= '>') t
          if "[" `T.isInfixOf` body then Left "内部サブセットを持つ DOCTYPE は使えません" else go acc' (advance (T.length body + 1) i')
        else Right (acc', i')
    attrIn k decl =
      let (_, after) = T.breakOn (k <> "=") decl
       in if T.null after
            then Nothing
            else
              let v = T.drop (T.length k + 1) after
               in case T.uncons v of
                    Just (q, r) | q == '"' || q == '\'' -> Just (T.takeWhile (/= q) r)
                    _ -> Nothing

{- | White space, comments and processing instructions: the instructions
are put before those given, the last first (adding at the end is
quadratic).
-}
misc :: (Int -> Pos) -> [(Text, Pos)] -> P [(Text, Pos)]
misc posAt acc i0 =
  let i = skipSpace i0
      t = rest' i
   in if
        | "<!--" `T.isPrefixOf` t -> upTo "コメント" "-->" (advance 4 i) >>= misc posAt acc . snd
        | "<?" `T.isPrefixOf` t -> do
            (target, i') <- instruction i
            misc posAt ((target, posAt (offset i)) : acc) i'
        | otherwise -> Right (acc, i)

-- | A processing instruction at @<?@: its target, and the input after it.
instruction :: P Text
instruction i =
  let target = T.takeWhile isNameChar (T.drop 2 (rest' i))
   in (\(_, i') -> (target, i')) <$> upTo "処理命令" "?>" (advance 2 i)

isNameChar :: Char -> Bool
isNameChar c = isAlphaNum c || c `elem` ("-_.:" :: String) || c > '\x7F'

-- | An element, with the namespaces in scope.
element :: (Int -> Pos) -> Map Text Text -> Input -> Either Text (Element, Input)
element posAt scope i0 = do
  let start = offset i0
  i1 <- if "<" `T.isPrefixOf` rest' i0 then Right (advance 1 i0) else Left "要素がありません"
  let qname = T.takeWhile isNameChar (rest' i1)
  if T.null qname then Left "要素の名前がありません" else Right ()
  (attrs, i2) <- attributes [] Set.empty (advance (T.length qname) i1)
  let scope' = Map.union (Map.fromList [(nsPrefix n, v) | (n, v, _) <- attrs, isNsDecl n]) scope
      resolveEl n = case T.breakOn ":" n of
        (p, suffix) | not (T.null suffix) -> (Map.findWithDefault ("?" <> p) p scope', T.drop 1 suffix)
        _ -> (Map.findWithDefault "" "" scope', n)
      resolveAt n = case T.breakOn ":" n of
        ("xml", suffix) | not (T.null suffix) -> (xmlNs, T.drop 1 suffix)
        (p, suffix) | not (T.null suffix) -> (Map.findWithDefault ("?" <> p) p scope', T.drop 1 suffix)
        _ -> ("", n)
      (ns, local) = resolveEl qname
      attrs' = [Attr ans aname v (posAt o) | (n, v, o) <- attrs, not (isNsDecl n), let (ans, aname) = resolveAt n]
      mk children = Element ns local attrs' children (posAt start)
  case T.uncons (rest' i2) of
    Just ('/', _) | "/>" `T.isPrefixOf` rest' i2 -> Right (mk [], advance 2 i2)
    Just ('>', _) -> do
      (children, i3) <- content posAt scope' [] (advance 1 i2)
      let close = "</" <> qname
      if close `T.isPrefixOf` rest' i3
        then do
          let i4 = skipSpace (advance (T.length close) i3)
          if ">" `T.isPrefixOf` rest' i4 then Right (mk children, advance 1 i4) else Left ("終わりのタグが壊れています: " <> qname)
        else Left ("終わりのタグがありません: " <> qname)
    _ -> Left ("開始のタグが壊れています: " <> qname)
  where
    isNsDecl n = n == "xmlns" || "xmlns:" `T.isPrefixOf` n
    nsPrefix n = if n == "xmlns" then "" else T.drop 6 n
    -- the names seen so far are a set: a list makes the check quadratic (security audit 2026-10-18, C10)
    attributes acc seen i = do
      let i' = skipSpace i
          name = T.takeWhile isNameChar (rest' i')
      if T.null name
        then Right (reverse acc, i')
        else do
          let o = offset i'
              i'' = skipSpace (advance (T.length name) i')
          i3 <- if "=" `T.isPrefixOf` rest' i'' then Right (skipSpace (advance 1 i'')) else Left ("属性の値がありません: " <> name)
          case T.uncons (rest' i3) of
            Just (q, _) | q == '"' || q == '\'' -> do
              (raw, i4) <- upTo "属性の値" (T.singleton q) (advance 1 i3)
              v <- references raw
              if name `Set.member` seen then Left ("属性が重なっています: " <> name) else Right ()
              attributes ((name, normalizeSpace v, o) : acc) (Set.insert name seen) i4
            _ -> Left ("属性の値が引用符で囲まれていません: " <> name)
    -- attribute value normalization: white space characters become spaces
    normalizeSpace = T.map (\c -> if c == '\t' || c == '\n' || c == '\r' then ' ' else c)

{- | A node of content being read: text is kept as its pieces, last first,
and joined once at the end tag (joining at each piece is quadratic,
security audit 2026-10-18, C9).
-}
data Partial
  = PNode !Node
  | PText ![Text] !Pos

-- | The content of an element up to its end tag.
content :: (Int -> Pos) -> Map Text Text -> [Partial] -> Input -> Either Text ([Node], Input)
content posAt scope acc i =
  let t = rest' i
   in if
        | T.null t -> Left "要素が閉じていません"
        | "</" `T.isPrefixOf` t -> Right (reverse (map complete acc), i)
        | "<!--" `T.isPrefixOf` t -> upTo "コメント" "-->" (advance 4 i) >>= content posAt scope acc . snd
        | "<![CDATA[" `T.isPrefixOf` t -> do
            (body, i') <- upTo "CDATA" "]]>" (advance 9 i)
            content posAt scope (text body (posAt (offset i)) acc) i'
        | "<?" `T.isPrefixOf` t -> do
            (target, i') <- instruction i
            content posAt scope (PNode (NInstruction target (posAt (offset i))) : acc) i'
        | "<!" `T.isPrefixOf` t -> Left "要素の中に置けない宣言があります"
        | "<" `T.isPrefixOf` t -> do
            (e, i') <- element posAt scope i
            content posAt scope (PNode (NElement e) : acc) i'
        | otherwise -> do
            let raw = T.takeWhile (/= '<') t
            v <- references raw
            content posAt scope (text v (posAt (offset i)) acc) (advance (T.length raw) i)

-- | Text after text is one text, at the position of the first.
text :: Text -> Pos -> [Partial] -> [Partial]
text t p = \case
  PText ts p' : rest -> PText (t : ts) p' : rest
  acc -> PText [t] p : acc

complete :: Partial -> Node
complete = \case
  PNode n -> n
  PText ts p -> NText (T.concat (reverse ts)) p

-- | Character references and the five predefined entities.
references :: Text -> Either Text Text
references t
  | not ("&" `T.isInfixOf` t) = Right t
  | otherwise = T.concat <$> pieces t
  where
    -- the pieces, joined once: joining at each reference is quadratic (security audit 2026-10-18, C9)
    pieces s
      | not ("&" `T.isInfixOf` s) = Right [s]
      | otherwise =
          let (before, after) = T.breakOn "&" s
              (ref, rest) = T.breakOn ";" (T.drop 1 after)
           in if T.null rest
                then Left "参照が閉じていません"
                else do
                  c <- resolve ref
                  (\r -> before : c : r) <$> pieces (T.drop 1 rest)
    resolve ref = case ref of
      "lt" -> Right "<"
      "gt" -> Right ">"
      "amp" -> Right "&"
      "quot" -> Right "\""
      "apos" -> Right "'"
      _
        | Just h <- T.stripPrefix "#x" ref, not (T.null h), T.length h <= 6, T.all isHexDigit h -> hexCode h
        | Just d <- T.stripPrefix "#" ref, not (T.null d), T.length d <= 7, T.all (`elem` ['0' .. '9']) d -> codePoint (read (T.unpack d))
        | otherwise -> Left ("知らない実体参照です: &" <> ref <> ";")
    hexCode h = case readHex (T.unpack h) of
      [(n, "")] -> codePoint n
      _ -> Left "文字参照が不正です"
    codePoint :: Int -> Either Text Text
    codePoint n
      | n == 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) = Left "文字参照が不正です"
      | otherwise = Right (T.singleton (chr n))
