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
import Data.Char (isSpace, toLower)
import Data.List (sortOn)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Svg.Css (stripComments)
import Golem.Svg.Xml

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
reason when it cannot be read as XML (the words of G0810).
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
offsets, in order; comments are blanked first, keeping the offsets.
Letters are compared without case, as CSS does.
-}
cssRefs :: Text -> [(Text, Int)]
cssRefs t0 =
  sortOn snd $
    [("@import", o) | (o, _) <- occurrences "@import"]
      <> [("url()", o) | (o, after) <- occurrences "url(", not ("#" `T.isPrefixOf` T.dropWhile (\ch -> isSpace ch || ch == '"' || ch == '\'') after)]
  where
    t = T.map toLower (stripComments t0)
    -- each occurrence of a text: its offset and what follows it, in time linear in the text
    occurrences p = go 0 (T.splitOn p t)
      where
        go off = \case
          x : rest@(y : _) -> (off + T.length x, y) : go (off + T.length x + T.length p) rest
          _ -> []

at :: Text -> Pos -> Active
at n (Pos l c) = Active n l c
