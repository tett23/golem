{- | Checks applied to IR that crossed a trust boundary (plugin output):
the invariants that the Haskell types guarantee internally.
-}
module Golem.Doc.Validate
  ( validateInlines,
    validateDocument,
    inlineSpan,
    validateBlocks,
    validateCommandBlocks,
    captionErrors,
    linkErrors,
    langErrors,
    langTagMessage,
  )
where

import Data.Char (isAsciiLower, isDigit)
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing)
import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Doc.Url
import Golem.Length (Sp (..))
import Golem.Syntax.LanguageTag (isLanguageTag)
import Golem.Syntax.Span

{- | @fileSize@ gives the byte length of each known file. @allowed@ are the
deferred expressions present in the request; output may only repeat them.
-}
validateInlines :: (FileId -> Maybe Int) -> [DeferredExpr] -> [Inline] -> [Text]
validateInlines fileSize allowed is = concatMap (inlineErrors fileSize allowed) is <> breakErrors False is

validateDocument :: (FileId -> Maybe Int) -> [DeferredExpr] -> Document -> [Text]
validateDocument fileSize allowed (Document _ bs) = blocksAt fileSize allowed True bs

{- | The blocks a block command puts out (docs/adr/0122): not at the top of
a document, since a block command may stand in a list item, so no forced
break, page control or blank lines.
-}
validateBlocks :: (FileId -> Maybe Int) -> [DeferredExpr] -> [Block] -> [Text]
validateBlocks fileSize allowed = blocksAt fileSize allowed False

-- | A command result may contain a separator at its outermost level.
validateCommandBlocks :: (FileId -> Maybe Int) -> [DeferredExpr] -> [Block] -> [Text]
validateCommandBlocks fileSize allowed = concatMap $ \b -> case blockBody b of
  Separator _ -> validateDocument fileSize allowed (Document (spanFile (blockSpan b)) [b])
  _ -> validateBlocks fileSize allowed [b]

blocksAt :: (FileId -> Maybe Int) -> [DeferredExpr] -> Bool -> [Block] -> [Text]
blocksAt fileSize allowed top0 = concatMap (blockAt top0)
  where
    blockErrors = blockAt False
    -- a forced break stands only at the top of a document, without a label (docs/adr ADR 0017)
    blockAt top (Block sp lbl lang body) =
      spanErrors fileSize sp <> langTagErrors lang <> case body of
        ForcedBreak _ ->
          ["改ページは文書の最上位にだけ置けます" | not top]
            <> ["改ページはラベルを持てません" | Just _ <- [lbl]]
        -- a page control likewise, with a valid count (docs/adr ADR 0030)
        PageControl c ->
          ["改ページの制御は文書の最上位にだけ置けます" | not top]
            <> ["改ページの制御はラベルを持てません" | Just _ <- [lbl]]
            <> case c of
              NeedLines n | n < 1 -> ["@need-lines の行数は 1 以上です"]
              AdjustLines 0 -> ["@page-lines の増減は 0 でない整数です"]
              _ -> []
        -- blank lines likewise, at least one (docs/adr ADR 0046)
        BlankLines n ->
          ["行アキは文書の最上位にだけ置けます" | not top]
            <> ["行アキはラベルを持てません" | Just _ <- [lbl]]
            <> ["行アキの行数は 1 以上です" | n < 1]
        Separator name ->
          ["区切りは文書の最上位にだけ置けます" | not top]
            <> ["区切りはラベルを持てません" | isJust lbl]
            <> ["区切りは言語を持てません" | isJust lang]
            <> ["区切りの名前は空にできません" | T.null name]
        _ -> bodyErrors body
    inl is = concatMap (inlineErrors fileSize allowed) is <> breakErrors False is
    bodyErrors = \case
      Paragraph st is ->
        ["段落スタイル body は null で表します" | st == Just "body"]
          <> styleRefErrors st
          <> concatMap (inlineErrors fileSize allowed) is
          <> breakErrors True is
      Heading l a is ->
        ["見出しの階層が範囲外です: " <> T.pack (show l) | l < 1 || l > 6]
          <> maybe [] inl (haTocTitle a)
          <> inl is
      BulletList items -> concatMap (concatMap blockErrors . itemBlocks) items
      OrderedList items -> concatMap (concatMap blockErrors . itemBlocks) items
      DefList gs -> concatMap (\(DefGroup ts ds) -> concatMap inl ts <> concatMap (concatMap blockErrors) ds) gs
      TableBlock t -> tableErrors t <> maybe [] inl (tableCaption t) <> concatMap inl (tableHeader t) <> concatMap (concatMap inl) (tableRows t)
      -- the caption, the callouts and the diff marks (golem-driver ADR 0023)
      CodeBlock c ->
        maybe [] inl (codeCaption c)
          -- the span of each line, as any other span (docs/adr/0218)
          <> concat [spanErrors fileSize lsp | Just lsp <- map clSpan (codeLines c)]
          <> ["注釈の印の番号は 1 から 50 までです" | any (any (\n -> n < 1 || n > 50) . clCallouts) (codeLines c)]
          <> ["差分のコードの行には差分の印が、ほかのコードの行には印がありません" | any (\l -> isJust (clDiff l) /= codeDiff c) (codeLines c)]
          -- only a code block with a caption has a number to go without (docs/adr/0200; G02134)
          <> ["キャプションのないコードブロックは番号を持たないので、@nonumber は要りません" | codeNoNumber c, isNothing (codeCaption c)]
      -- a caption holds paragraphs only (docs/adr/0144)
      FigureBlock f -> captionErrors f <> concatMap blockErrors [b | b@(Block _ _ _ (Paragraph _ _)) <- figCaption f]
      ChannelOutput _ -> []
      ForcedBreak _ -> []
      PageControl _ -> []
      BlankLines _ -> []
      Separator _ -> []
      -- a frame holds paragraphs only, and is named as a style is (root ADR 0438)
      FrameBlock name bs ->
        ["フレームの名前は英小文字で始まり、英小文字、数字、- だけからなります: " <> name | not (frameName name)]
          <> ["フレームの中身は段落だけです" | not (all isParagraph bs)]
          <> concatMap blockErrors bs
    frameName name = case T.uncons name of
      Just (c, rest) -> isAsciiLower c && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
      Nothing -> False
    isParagraph = \case
      Block _ _ _ (Paragraph _ _) -> True
      _ -> False

{- | The invariants of a table (docs/adr/0262): as many cells in each row
as in the header row, no widths or one for each column, every width but
auto above 0, @nonumber only with a caption, and the built-in table
written as null, as body is for a paragraph.
-}
tableErrors :: Table -> [Text]
tableErrors t =
  ["表のセルの数が一致しません" | any ((/= length h) . length) (tableRows t)]
    <> ["表の列の幅の数が列の数と違います" | not (null ws), length ws /= length h]
    <> ["表の列の幅は 0 より大きい値です" | any nonPositive ws]
    <> ["キャプションのない表は番号を持たないので、@nonumber は要りません" | tableNoNumber t, isNothing (tableCaption t)]
    <> ["表の段落スタイル table は null で表します" | tableStyle t == Just "table"]
    <> styleRefErrors (tableStyle t)
  where
    h = tableHeader t
    ws = tableWidths t
    nonPositive = \case
      ColumnAuto -> False
      ColumnZw q -> q <= 0
      ColumnAbs x -> x <= 0
      ColumnPercent q -> q <= 0

{- | A caption of a figure holds paragraphs only (docs/adr/0144): the
outputs set nothing else of it, so anything else would vanish.
-}
captionErrors :: Figure -> [Text]
captionErrors f = ["図版のキャプションには段落だけを置けます" | not (all (isParagraph . blockBody) (figCaption f))]
  where
    isParagraph = \case
      Paragraph _ _ -> True
      _ -> False

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
      Note _ _ _ bs -> deep (concat (noteParagraphs bs))
      Sidenote _ _ _ bs -> deep (concat (noteParagraphs bs))
      Endnote _ _ _ bs -> deep (concat (noteParagraphs bs))
      Cite _ items -> deep (citeInlines items)
      Link _ _ xs -> deep xs
      Lang _ _ xs -> deep xs
      Resolved _ _ _ xs -> deep xs
      _ -> False
    deep :: [InlineF r] -> Bool
    deep = any (\x -> isBreak x || nested x)

-- Inline ruby options are also checked on the plugin boundary (root ADR 0379).
rubyErrors :: RubySegment -> [Text]
rubyErrors seg =
  let opts = rsOptions seg
      positive = case roSize opts of Nothing -> True; Just (RubySizeAbsolute n) -> n > 0; Just (RubySizeRelative r) -> r > 0
      representable = case roSize opts of Nothing -> True; Just (RubySizeAbsolute (Sp n)) -> inInt64 n; Just (RubySizeRelative r) -> inInt64 (numerator r) && inInt64 (denominator r)
      validMarks reading marks = (null marks || length marks == maybe 0 T.length reading) && all (maybe True (`elem` ["sesame", "open-sesame", "dot", "open-dot", "circle", "open-circle", "double-circle", "open-double-circle", "triangle", "open-triangle"])) marks
   in ["ルビの読みのサイズは正でなければなりません" | not positive]
        <> ["ルビの寸法が意味論 IR の範囲外です" | not representable]
        <> ["ルビの配置が不正です" | maybe False (`notElem` ["start", "center", "1-2-1", "0-1-0"]) (roAlign opts)]
        <> ["両側ルビにだけ二つ目の読みが必要です" | (roSide opts == RubyBoth) /= isJust (rsOtherReading seg)]
        <> ["両側ルビの読みは空にできません" | roSide opts == RubyBoth, any (maybe True T.null) [rsReading seg, rsOtherReading seg]]
        <> ["ルビの圏点が不正です" | not (validMarks (rsReading seg) (roReadingKenten opts) && validMarks (rsOtherReading seg) (roOtherKenten opts))]

spanErrors :: (FileId -> Maybe Int) -> SrcSpan -> [Text]
spanErrors fileSize (SrcSpan f s e) = case fileSize f of
  Nothing -> ["存在しないファイルの位置です"]
  Just n -> ["ソース位置がファイルの範囲外です" | s < 0 || e < s || e > n]

inlineErrors :: (FileId -> Maybe Int) -> [DeferredExpr] -> InlineF r -> [Text]
inlineErrors fileSize allowed i =
  spanErrors fileSize (inlineSpan i) <> case i of
    Tcy _ (TcyNumber q) -> rationalErrors q
    Number _ q st -> rationalErrors q <> ["明示した縦中横は TcyNumber で表します" | st == Just StyleTcy]
    Ruby _ _ segs -> concatMap (\seg -> rubyErrors seg <> concatMap (inlineErrors fileSize allowed) (rsBase seg)) segs
    Kenten _ _ xs -> sub xs
    Color _ _ xs -> sub xs
    CharStyle _ _ xs -> sub xs
    Deferred _ e -> ["プラグインが新しい遅延式を作っています" | e `notElem` allowed]
    Note _ _ _ bs -> noteErrors ["脚注の本文は一つ以上の段落です" | null bs] bs
    Sidenote _ _ _ bs -> noteErrors ["傍注の本文は段落をちょうど一つ持ちます" | length bs /= 1] bs
    -- an endnote, as a footnote (root ADR 0412)
    Endnote _ _ _ bs -> noteErrors ["章末の注の本文は一つ以上の段落です" | null bs] bs
    Cite _ is -> citeErrors is <> sub (citeInlines is)
    IndexMark _ (IndexEntry ts rs k) ->
      ["索引の項目の段の数が不正です" | null ts || length ts > 2 || length ts /= length rs]
        -- a target of one level or two, none empty (docs/adr/0265)
        <> case k of
          IndexSee _ target -> ["索引の参照先の段の数が不正です" | null target || length target > 2 || any T.null target]
          _ -> []
    -- negative amounts are not written (docs/adr ADR 0019)
    Aki _ a -> ["アキの量が負です" | negativeAki a]
    -- the body sends nothing to another channel (golem-doc ADR 0007)
    ChannelItem _ c ->
      sub (ciBody c)
        <> breakErrors False (ciBody c)
        <> ["チャネルの項目の本文に置けない要素があります" | any sends (ciBody c)]
    -- a URL that passes the checks, and no element inside that is a link itself (docs/adr ADR 0182)
    Link _ u xs -> linkOwnErrors u xs <> sub xs
    -- a tag of the form of BCP 47 (docs/adr ADR 0187)
    Lang _ l xs -> langTagErrors (Just l) <> sub xs
    -- only the assembly resolves a reference, after the plugins (docs/adr/0215, 0229)
    Resolved {} -> ["解決した参照は文書の組み立てだけが作ります"]
    _ -> []
  where
    rationalErrors q = ["数が意味論 IR の有理数の範囲外です" | not (inInt64 (numerator q) && inInt64 (denominator q)) || denominator q < 1 || gcd (numerator q) (denominator q) /= 1]
    sub :: [InlineF q] -> [Text]
    sub = concatMap (inlineErrors fileSize allowed)
    {- the body of a footnote: one paragraph or more, of a sidenote: one
    paragraph; paragraphs without a paragraph style, their inlines checked
    as those of a note were (docs/adr/0263) -}
    noteErrors counted bs =
      counted
        <> ["注の本文には段落スタイルのない段落だけを置けます" | not (all plain bs)]
        <> concat [spanErrors fileSize bsp <> langTagErrors blang | Block bsp _ blang _ <- bs]
        <> concatMap sub (noteParagraphs bs)
    plain = \case
      Block _ _ _ (Paragraph Nothing _) -> True
      _ -> False
    {- a citation of one item or more, their keys distinct; the values the
    outputs cannot set yet stop it (docs/adr/0266) -}
    citeErrors is =
      ["引用は一つ以上の文献を持ちます" | null is]
        <> ["引用に同じキーが二度あります: " <> k | k <- twice (map citKey is)]
        <> concat [locatorErrors l | Just l <- map citLocator is]
        <> ["まだ組めない引用の値です: 前置きと後置き" | any (any nonLiteral . citeInlines . pure) is]
    nonLiteral = \case
      Text {} -> False
      _ -> True
    locatorErrors (Locator _ v) = case v of
      LocNumber n -> ["引用の位置の数が負です" | n < 0]
      LocRange a b -> ["引用の位置の範囲が負か逆向きです" | a < 0 || b < a]
      LocText t -> ["引用の位置の文字列が空です" | T.null t]
    twice ks = nub [k | (n, k) <- zip [0 :: Int ..] ks, k `elem` take n ks]
    sends :: InlineF q -> Bool
    sends = \case
      Note {} -> True
      Sidenote {} -> True
      Endnote {} -> True
      IndexMark {} -> True
      Cite {} -> True
      ChannelItem {} -> True
      Ruby _ _ segs -> any (any sends . rsBase) segs
      Kenten _ _ xs -> any sends xs
      Color _ _ xs -> any sends xs
      CharStyle _ _ xs -> any sends xs
      Link _ _ xs -> any sends xs
      Lang _ _ xs -> any sends xs
      Resolved _ _ _ xs -> any sends xs
      _ -> False
    negativeAki = \case
      AkiZw r -> r < 0
      AkiAbs x -> x < 0

-- | The errors of a link itself: its URL, and the elements inside it that are links (docs/adr ADR 0182).
linkOwnErrors :: Text -> [InlineF r] -> [Text]
linkOwnErrors u xs =
  [urlProblemMessage p u | Just p <- [checkUrl u]]
    <> ["リンクの中にリンクになる要素は置けません: " <> e | e <- linkElements xs]

{- | The errors of the links among inlines at any depth (docs/adr ADR
0182), for the inlines a command of a plugin puts out.
-}
linkErrors :: [InlineF r] -> [Text]
linkErrors = concatMap $ \case
  Link _ u xs -> linkOwnErrors u xs <> linkErrors xs
  Ruby _ _ segs -> concatMap (linkErrors . rsBase) segs
  Kenten _ _ xs -> linkErrors xs
  Color _ _ xs -> linkErrors xs
  CharStyle _ _ xs -> linkErrors xs
  Note _ _ _ bs -> concatMap linkErrors (noteParagraphs bs)
  Sidenote _ _ _ bs -> concatMap linkErrors (noteParagraphs bs)
  Endnote _ _ _ bs -> concatMap linkErrors (noteParagraphs bs)
  Cite _ is -> linkErrors (citeInlines is)
  ChannelItem _ c -> linkErrors (ciBody c)
  Lang _ _ xs -> linkErrors xs
  Resolved _ _ _ xs -> linkErrors xs
  _ -> []

-- | The message of a language tag not of the form of BCP 47 (G02132, docs/adr ADR 0187).
langTagMessage :: Text -> Text
langTagMessage l = "言語のタグの形が誤っています: " <> l

-- | The error of the language tag of a block or a language span, if it is not of the form (docs/adr ADR 0187).
langTagErrors :: Maybe Text -> [Text]
langTagErrors = \case
  Just l | not (isLanguageTag l) -> [langTagMessage l]
  _ -> []

{- | The errors of the language spans among inlines at any depth (docs/adr
ADR 0187), for the inlines a command of a plugin puts out.
-}
langErrors :: [InlineF r] -> [Text]
langErrors = concatMap $ \case
  Lang _ l xs -> langTagErrors (Just l) <> langErrors xs
  Link _ _ xs -> langErrors xs
  Ruby _ _ segs -> concatMap (langErrors . rsBase) segs
  Kenten _ _ xs -> langErrors xs
  Color _ _ xs -> langErrors xs
  CharStyle _ _ xs -> langErrors xs
  Note _ _ _ bs -> concat [langTagErrors l | Block _ _ l _ <- bs] <> concatMap langErrors (noteParagraphs bs)
  Sidenote _ _ _ bs -> concat [langTagErrors l | Block _ _ l _ <- bs] <> concatMap langErrors (noteParagraphs bs)
  Endnote _ _ _ bs -> concat [langTagErrors l | Block _ _ l _ <- bs] <> concatMap langErrors (noteParagraphs bs)
  Cite _ is -> langErrors (citeInlines is)
  ChannelItem _ c -> langErrors (ciBody c)
  Resolved _ _ _ xs -> langErrors xs
  _ -> []

inlineSpan :: InlineF r -> SrcSpan
inlineSpan = \case
  Text s _ -> s
  Ruby s _ _ -> s
  Kenten s _ _ -> s
  Color s _ _ -> s
  CharStyle s _ _ -> s
  Tcy s _ -> s
  Warichu s _ -> s
  Upright s _ -> s
  Number s _ _ -> s
  Ref s _ _ -> s
  Deferred s _ -> s
  Note s _ _ _ -> s
  Sidenote s _ _ _ -> s
  Endnote s _ _ _ -> s
  IndexMark s _ -> s
  Cite s _ -> s
  ProofComment s _ -> s
  LineBreak s -> s
  Aki s _ -> s
  ChannelItem s _ -> s
  Link s _ _ -> s
  Lang s _ _ -> s
  Resolved s _ _ _ -> s

-- | The keys of a paragraph style (root ADR 0467): based-on is the name, never a key.
styleRefErrors :: Maybe StyleRef -> [Text]
styleRefErrors st = ["段落スタイルのキーに based-on は書けません" | Just r <- [st], Map.member "based-on" (styleRefKeys r)]
