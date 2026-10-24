{- | The active content of an SVG figure that HTML and EPUB copy as it is
(docs/adr ADR 0039): what a browser runs or loads when the file is opened
as a document. The figure is read with the XML reader of golem-svg and
its elements and attributes are walked in the order of the document.
-}
module Golem.Svg.Active
  ( Active (..),
    activeContent,
  )
where

import Data.ByteString (ByteString)
import Data.Char (isHexDigit, isSpace, toLower)
import Data.IntMap.Strict qualified as IntMap
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Svg.Xml
import Numeric (readHex)

-- | One thing that is refused: its name and where it is in the file.
data Active = Active
  { acName :: !Text,
    acLine :: !Int,
    acColumn :: !Int
  }
  deriving stock (Eq, Show)

-- | The namespace of the @xlink:@ prefix.
xlinkNs :: Text
xlinkNs = "http://www.w3.org/1999/xlink"

{- | The active content of an SVG file, in the order of the document; the
reason when it cannot be read as XML (the words of G08010).
-}
activeContent :: ByteString -> Either Text [Active]
activeContent bytes = element <$> parseXml bytes

element :: Element -> [Active]
element e =
  [at (elName e) (elPos e) | refusedElement]
    <> concatMap attribute (elAttrs e)
    <> concatMap child (elChildren e)
  where
    lower = T.toLower (elName e)
    refusedElement =
      lower `elem` ["script", "foreignobject", "iframe", "embed", "object", "handler", "listener"]
        || (lower `elem` ["set", "animate"] && maybe False animatesLink (attrValue "attributeName"))
    animatesLink v =
      let n = T.toLower (T.strip v)
       in n `elem` ["href", "xlink:href"] || "on" `T.isPrefixOf` n
    attrValue k = case [atValue a | a <- elAttrs e, atNs a == "", atName a == k] of
      v : _ -> Just v
      [] -> Nothing
    child = \case
      NElement c -> element c
      NText t p
        | lower == "style" -> css t p
        | otherwise -> []

attribute :: Attr -> [Active]
attribute a
  | "on" `T.isPrefixOf` T.toLower (atName a) = [at (atName a) (atPos a)]
  | atName a == "href" && not (internal (atValue a)) = [at (if atNs a == xlinkNs then "xlink:href" else "href") (atPos a)]
  | atNs a == "" && atName a == "style" = [at n (atPos a) | (n, _) <- cssRefs (atValue a)]
  | otherwise = []
  where
    internal v = "#" `T.isPrefixOf` T.stripStart v

{- | The external references of the text of a style element, each at its
place in the file: the text starts at the position given.
-}
css :: Text -> Pos -> [Active]
css t (Pos l c) =
  [ Active n (l + lines') (if lines' == 0 then c + T.length before else T.length (snd (T.breakOnEnd "\n" before)) + 1)
  | (n, off) <- cssRefs t,
    let before = T.take off t
        lines' = T.count "\n" before
  ]

{- | @import and url() whose target does not start with #, with their
offsets, in order. The text is read as CSS tokenizes it: comments are
dropped, but not inside strings, and escapes are decoded, so that
@\\69mport and \\75 rl( are found too (security audit 2026-10-24).
Letters are compared without case, as CSS does.
-}
cssRefs :: Text -> [(Text, Int)]
cssRefs t0 =
  sortOn snd $
    [("@import", origin o) | (o, _) <- occurrences "@import"]
      <> [("url()", origin o) | (o, after) <- occurrences "url(", not ("#" `T.isPrefixOf` T.dropWhile (\ch -> isSpace ch || ch == '"' || ch == '\'') after)]
  where
    decoded = cssChars t0
    t = T.pack (map (toLower . fst) decoded)
    offsets = IntMap.fromDistinctAscList (zip [0 ..] (map snd decoded))
    origin o = IntMap.findWithDefault (T.length t0) o offsets
    -- each occurrence of a text: its offset and what follows it, in time linear in the text
    occurrences p = go 0 (T.splitOn p t)
      where
        go off = \case
          x : rest@(y : _) -> (off + T.length x, y) : go (off + T.length x + T.length p) rest
          _ -> []

{- | The characters of CSS as its tokenizer sees them, each with the offset
in the text where it starts: comments outside strings dropped, escapes
decoded (CSS Syntax Level 3, 4.3.7), a backslash and a newline in a
string dropped.
-}
cssChars :: Text -> [(Char, Int)]
cssChars = go Nothing 0
  where
    go quote off t = case T.uncons t of
      Nothing -> []
      Just (c, rest)
        | Nothing <- quote,
          c == '/',
          Just ('*', rest') <- T.uncons rest ->
            let (comment, after) = T.breakOn "*/" rest'
                used = 2 + T.length comment + min 2 (T.length after)
             in go quote (off + used) (T.drop (min 2 (T.length after)) after)
        | c == '\\' -> escape quote off rest
        | Just q <- quote, c == q -> (c, off) : go Nothing (off + 1) rest
        | Just _ <- quote, c == '\n' -> (c, off) : go Nothing (off + 1) rest
        | Nothing <- quote, c == '"' || c == '\'' -> (c, off) : go (Just c) (off + 1) rest
        | otherwise -> (c, off) : go quote (off + 1) rest
    escape quote off rest =
      let hex = T.takeWhile isHexDigit (T.take 6 rest)
          after = T.drop (T.length hex) rest
          space = case T.uncons after of
            Just ('\r', r) | Just ('\n', _) <- T.uncons r -> 2
            Just (w, _) | w `elem` [' ', '\t', '\n', '\r', '\f'] -> 1
            _ -> 0
          value = case readHex (T.unpack hex) of
            [(v, "")] -> v
            _ -> 0 :: Int
          ch
            | value == 0 || value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF) = '\xFFFD'
            | otherwise = toEnum value
       in case () of
            _
              | not (T.null hex) -> (ch, off) : go quote (off + 1 + T.length hex + space) (T.drop space after)
              | Just ('\n', r) <- T.uncons rest, Just _ <- quote -> go quote (off + 2) r
              | Just (e, r) <- T.uncons rest -> (e, off) : go quote (off + 2) r
              | otherwise -> [('\\', off)]

at :: Text -> Pos -> Active
at n (Pos l c) = Active n l c
