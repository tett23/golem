{- | Checks applied to IR that crossed a trust boundary (plugin output):
the invariants that the Haskell types guarantee internally.
-}
module Golem.Doc.Validate
  ( validateInlines,
    validateDocument,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Syntax.Span

{- | @fileSize@ gives the byte length of each known file. @allowed@ are the
deferred expressions present in the request; output may only repeat them.
-}
validateInlines :: (FileId -> Maybe Int) -> [DeferredExpr] -> [Inline] -> [Text]
validateInlines fileSize allowed = concatMap (inlineErrors fileSize allowed)

validateDocument :: (FileId -> Maybe Int) -> [DeferredExpr] -> Document -> [Text]
validateDocument fileSize allowed (Document _ bs) = concatMap blockErrors bs
  where
    blockErrors (Block sp _ body) = spanErrors fileSize sp <> bodyErrors body
    inl = concatMap (inlineErrors fileSize allowed)
    bodyErrors = \case
      Paragraph is -> inl is
      Heading l a is ->
        ["見出しの階層が範囲外です: " <> T.pack (show l) | l < 1 || l > 3]
          <> maybe [] inl (haTocTitle a)
          <> inl is
      BulletList items -> concatMap (concatMap blockErrors . itemBlocks) items
      OrderedList items -> concatMap (concatMap blockErrors . itemBlocks) items
      DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap inl ts <> concatMap (concatMap blockErrors) ds) gs
      Table _ h rows ->
        concatMap inl h
          <> concatMap (concatMap inl) rows
          <> ["表のセルの数が一致しません" | any ((/= length h) . length) rows]
      CodeBlock _ _ -> []
      FigureBlock f -> concatMap blockErrors (figCaption f)
      ChannelOutput _ -> []
      VerseBlock stanzas -> concatMap (concatMap inl) stanzas

spanErrors :: (FileId -> Maybe Int) -> SrcSpan -> [Text]
spanErrors fileSize (SrcSpan f s e) = case fileSize f of
  Nothing -> ["存在しないファイルの位置です"]
  Just n -> ["ソース位置がファイルの範囲外です" | s < 0 || e < s || e > n]

inlineErrors :: (FileId -> Maybe Int) -> [DeferredExpr] -> InlineF r -> [Text]
inlineErrors fileSize allowed i =
  spanErrors fileSize (inlineSpan i) <> case i of
    Strong _ xs -> sub xs
    Bold _ xs -> sub xs
    Italic _ xs -> sub xs
    Ruby _ _ segs -> concatMap (concatMap (inlineErrors fileSize allowed) . rsBase) segs
    Kenten _ _ xs -> sub xs
    Color _ _ xs -> sub xs
    CharStyle _ _ xs -> sub xs
    Deferred _ e -> ["プラグインが新しい遅延式を作っています" | e `notElem` allowed]
    Note _ _ xs -> sub xs
    Sidenote _ _ xs -> sub xs
    IndexMark _ (IndexEntry ts rs) -> ["索引の項目の段の数が不正です" | null ts || length ts > 2 || length ts /= length rs]
    _ -> []
  where
    sub = concatMap (inlineErrors fileSize allowed)

inlineSpan :: InlineF r -> SrcSpan
inlineSpan = \case
  Text s _ -> s
  Strong s _ -> s
  Bold s _ -> s
  Italic s _ -> s
  Ruby s _ _ -> s
  Kenten s _ _ -> s
  Color s _ _ -> s
  CharStyle s _ _ -> s
  Tcy s _ -> s
  Number s _ _ -> s
  Ref s _ _ -> s
  Deferred s _ -> s
  Note s _ _ -> s
  Sidenote s _ _ -> s
  IndexMark s _ -> s
  Cite s _ -> s
  ProofComment s _ -> s
