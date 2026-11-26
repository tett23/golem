-- | Source-line numbering before the renderers wrap lines (root ADR 0384).
module Golem.Evaluate.Verse (numberVerseDocument, numberVerseLines) where

import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Golem.Assemble (inlineText)
import Golem.Doc.IR
import Golem.Project.Style
import Golem.Syntax (SrcSpan)

-- | Each paragraph is one verse block and starts its own counter.
numberVerseDocument :: Style -> Document -> Document
numberVerseDocument style doc = doc {docBlocks = map block (docBlocks doc)}
  where
    values r = [(k, case v of StyleWord w -> LocalWord w; StyleString t -> LocalString t) | (k, v) <- Map.toAscList (styleRefKeys r)]
    block b = b {blockBody = body (blockSpan b) (blockBody b)}
    body sp = \case
      Paragraph st is ->
        let content = map inline is
            -- the keys of @style over the style (root ADR 0467)
            numbered = case paraStyleWith style (styleRefNameOf st) (maybe [] values st) of
              Just d | psLineBreaks d == Just KeepLines, Just interval <- psLineNumberInterval d -> numberVerseLines sp interval content
              _ -> content
         in Paragraph st numbered
      Heading level attrs is -> Heading level attrs (map inline is)
      BulletList items -> BulletList (map item items)
      OrderedList items -> OrderedList (map item items)
      DefList groups -> DefList [g {dgTerms = map (map inline) (dgTerms g), dgDefs = map (map block) (dgDefs g)} | g <- groups]
      FigureBlock f -> FigureBlock f {figCaption = map block (figCaption f)}
      FrameBlock name bs -> FrameBlock name (map block bs)
      TableBlock t -> TableBlock t {tableHeader = map (map inline) (tableHeader t), tableRows = map (map (map inline)) (tableRows t), tableCaption = map inline <$> tableCaption t}
      CodeBlock c -> CodeBlock c {codeCaption = map inline <$> codeCaption c}
      other -> other
    item x = x {itemBlocks = map block (itemBlocks x)}
    inline :: InlineF r -> InlineF r
    inline = \case
      Note sp n lbl bs -> Note sp n lbl (map block bs)
      Sidenote sp n lbl bs -> Sidenote sp n lbl (map block bs)
      Endnote sp n lbl bs -> Endnote sp n lbl (map block bs)
      CharStyle sp n xs -> CharStyle sp n (map inline xs)
      Color sp n xs -> Color sp n (map inline xs)
      Kenten sp n xs -> Kenten sp n (map inline xs)
      Link sp n xs -> Link sp n (map inline xs)
      Lang sp n xs -> Lang sp n (map inline xs)
      Resolved sp kind n xs -> Resolved sp kind n (map inline xs)
      Ruby sp kind segs -> Ruby sp kind [seg {rsBase = map inline (rsBase seg)} | seg <- segs]
      other -> other

{- | The generated prefix belongs only to the source line, so a renderer's
continuation lines never repeat it. Blank lines preserve their breaks.
-}
numberVerseLines :: SrcSpan -> Int -> [Inline] -> [Inline]
numberVerseLines sp interval
  | interval <= 0 = id
  | otherwise = go 0
  where
    go count xs =
      let (line, rest) = break isLineBreak xs
          nonempty = any hasContent line
          next = if nonempty then count + 1 else count
          prefix = [Text sp (T.pack (show next) <> " ") | nonempty, next `mod` toInteger interval == 0]
       in prefix <> line <> case rest of
            [] -> []
            br : after -> br : go next after

-- References and note marks occupy a source line even without literal text.
hasContent :: InlineF r -> Bool
hasContent = \case
  Ref {} -> True
  Deferred {} -> True
  Cite {} -> True
  Note {} -> True
  Sidenote {} -> True
  Endnote {} -> True
  CharStyle _ _ xs -> any hasContent xs
  Color _ _ xs -> any hasContent xs
  Kenten _ _ xs -> any hasContent xs
  Link _ _ xs -> any hasContent xs
  Lang _ _ xs -> any hasContent xs
  Resolved _ _ _ xs -> any hasContent xs
  Ruby _ _ segs -> any (any hasContent . rsBase) segs
  other -> not (T.null (T.strip (inlineText other)))
