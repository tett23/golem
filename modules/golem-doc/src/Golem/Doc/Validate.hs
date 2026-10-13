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
validateInlines fileSize allowed is = concatMap (inlineErrors fileSize allowed) is <> breakErrors False is

validateDocument :: (FileId -> Maybe Int) -> [DeferredExpr] -> Document -> [Text]
validateDocument fileSize allowed (Document _ bs) = concatMap (blockAt True) bs
  where
    blockErrors = blockAt False
    -- a forced break stands only at the top of a document, without a label (docs/adr ADR 0017)
    blockAt top (Block sp lbl body) =
      spanErrors fileSize sp <> case body of
        ForcedBreak _ ->
          ["改ページは文書の最上位にだけ置けます" | not top]
            <> ["改ページはラベルを持てません" | Just _ <- [lbl]]
        _ -> bodyErrors body
    inl is = concatMap (inlineErrors fileSize allowed) is <> breakErrors False is
    bodyErrors = \case
      Paragraph st is ->
        ["段落スタイル body は null で表します" | st == Just "body"]
          <> concatMap (inlineErrors fileSize allowed) is
          <> breakErrors True is
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
      ForcedBreak _ -> []

{- | A line break stands only between two inlines at the top of a
paragraph, never two in a row (docs/adr ADR 0005).
-}
breakErrors :: Bool -> [InlineF r] -> [Text]
breakErrors top is =
  ["改行は段落の最上位のインラインの間にだけ置けます" | any nested is || topLevel]
  where
    isBreak = \case
      LineBreak _ -> True
      _ -> False
    topLevel
      | not top = any isBreak is
      | otherwise = case is of
          [] -> False
          (x : _) -> isBreak x || isBreak (last is) || or (zipWith (\a b -> isBreak a && isBreak b) is (drop 1 is))
    nested :: InlineF r -> Bool
    nested = \case
      Ruby _ _ segs -> any (any (\x -> isBreak x || nested x) . rsBase) segs
      Kenten _ _ xs -> deep xs
      Color _ _ xs -> deep xs
      CharStyle _ _ xs -> deep xs
      Note _ _ xs -> deep xs
      Sidenote _ _ xs -> deep xs
      _ -> False
    deep :: [InlineF r] -> Bool
    deep = any (\x -> isBreak x || nested x)

spanErrors :: (FileId -> Maybe Int) -> SrcSpan -> [Text]
spanErrors fileSize (SrcSpan f s e) = case fileSize f of
  Nothing -> ["存在しないファイルの位置です"]
  Just n -> ["ソース位置がファイルの範囲外です" | s < 0 || e < s || e > n]

inlineErrors :: (FileId -> Maybe Int) -> [DeferredExpr] -> InlineF r -> [Text]
inlineErrors fileSize allowed i =
  spanErrors fileSize (inlineSpan i) <> case i of
    Ruby _ _ segs -> concatMap (concatMap (inlineErrors fileSize allowed) . rsBase) segs
    Kenten _ _ xs -> sub xs
    Color _ _ xs -> sub xs
    CharStyle _ _ xs -> sub xs
    Deferred _ e -> ["プラグインが新しい遅延式を作っています" | e `notElem` allowed]
    Note _ _ xs -> sub xs
    Sidenote _ _ xs -> sub xs
    IndexMark _ (IndexEntry ts rs) -> ["索引の項目の段の数が不正です" | null ts || length ts > 2 || length ts /= length rs]
    -- negative amounts are not written (docs/adr ADR 0019)
    Aki _ a -> ["アキの量が負です" | negativeAki a]
    _ -> []
  where
    sub = concatMap (inlineErrors fileSize allowed)
    negativeAki = \case
      AkiZw r -> r < 0
      AkiAbs x -> x < 0

inlineSpan :: InlineF r -> SrcSpan
inlineSpan = \case
  Text s _ -> s
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
  LineBreak s -> s
  Aki s _ -> s
