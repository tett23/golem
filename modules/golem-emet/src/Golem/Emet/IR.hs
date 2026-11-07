{- | The semantic IR as values of .emet (docs/adr/0162): the data types of
the built-in modules @Inline@ and @Block@ ('Golem.Emet.Builtins'), whose
constructors are those of the serialisation of the ABI with the plugins.

What the data types do not show is carried beside the values: the span
of each node, the label of each block, the number of each note and the
expression of each 'Deferred'. A node that comes in has one more field
after its own, the index of what it carries; a function reads it as any
other value only through the patterns, which do not see it. A node a
function makes has no such field and takes the span given for a new node
(the call of a command, or the top of the file of a filter); a node
passed through keeps its own. A deferred expression can only come in:
its constructor is hidden, and its value is the index of the expression.
-}
module Golem.Emet.IR
  ( Carried,
    emptyCarried,
    Enc,
    runEnc,
    encodeInlines,
    encodeBlocks,
    carriedDeferred,
    decodeInlines,
    decodeBlocks,
  )
where

import Control.Monad.State.Strict
import Data.Foldable (toList)
import Data.Maybe (fromMaybe)
import Data.Sequence (Seq)
import Data.Sequence qualified as Seq
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Emet.Eval (Result (..))
import Golem.Eval.Value (Value (..), numberOf)
import Golem.Syntax
import Numeric.Natural (Natural)

-- | What a node carries that its fields do not show.
data Hidden = Hidden !SrcSpan !(Maybe Text) !Int

-- | What the nodes that came in carry, by their indexes.
data Carried = Carried
  { cHidden :: !(Seq Hidden),
    cDeferred :: !(Seq DeferredExpr)
  }

emptyCarried :: Carried
emptyCarried = Carried Seq.empty Seq.empty

-- | The deferred expressions that came in, which alone may go out.
carriedDeferred :: Carried -> [DeferredExpr]
carriedDeferred = toList . cDeferred

type Enc = State Carried

runEnc :: Enc a -> (a, Carried)
runEnc m = runState m emptyCarried

-- | A node with the index of what it carries after its fields.
node :: Text -> [Result] -> Hidden -> Enc Result
node c fs h = do
  i <- gets (Seq.length . cHidden)
  modify' (\s -> s {cHidden = cHidden s Seq.|> h})
  pure (RCon c (fs <> [nat i]))

nat :: (Integral a) => a -> Result
nat = RPrim . VNat . fromIntegral

int :: (Integral a) => a -> Result
int = RPrim . VInt . toInteger

str :: Text -> Result
str = RPrim . VString

bool :: Bool -> Result
bool = RPrim . VBool

con :: Text -> [Result] -> Result
con = RCon

maybeR :: (a -> Result) -> Maybe a -> Result
maybeR f = maybe (con "Nothing" []) (\x -> con "Just" [f x])

maybeE :: (a -> Enc Result) -> Maybe a -> Enc Result
maybeE f = maybe (pure (con "Nothing" [])) (fmap (\x -> con "Just" [x]) . f)

listE :: (a -> Enc Result) -> [a] -> Enc Result
listE f xs = RList <$> mapM f xs

encodeInlines :: [Inline] -> Enc Result
encodeInlines = listE encodeInline

encodeNoRuby :: [InlineNoRuby] -> Enc Result
encodeNoRuby = listE (encodeInline . withRuby)

withRuby :: InlineNoRuby -> Inline
withRuby = \case
  Text s t -> Text s t
  Kenten s sh xs -> Kenten s sh (map withRuby xs)
  Color s c xs -> Color s c (map withRuby xs)
  CharStyle s c xs -> CharStyle s c (map withRuby xs)
  Tcy s t -> Tcy s t
  Number s n st -> Number s n st
  Ref s k l -> Ref s k l
  Deferred s e -> Deferred s e
  Note s n xs -> Note s n (map withRuby xs)
  Sidenote s n xs -> Sidenote s n (map withRuby xs)
  IndexMark s e -> IndexMark s e
  Cite s k -> Cite s k
  ProofComment s t -> ProofComment s t
  LineBreak s -> LineBreak s
  Aki s a -> Aki s a
  ChannelItem s c -> ChannelItem s c
  Link s u xs -> Link s u (map withRuby xs)

encodeInline :: Inline -> Enc Result
encodeInline = \case
  Text sp t -> at sp "Text" [str t]
  Ruby sp _ segs -> do
    ss <- listE (\(RubySegment base reading) -> (\b -> con "RubySegment" [b, maybeR str reading]) <$> encodeNoRuby base) segs
    at sp "Ruby" [ss]
  Kenten sp sh xs -> encodeInlines xs >>= \b -> at sp "Kenten" [maybeR str sh, b]
  Color sp c xs -> encodeInlines xs >>= \b -> at sp "Color" [str c, b]
  CharStyle sp c xs -> encodeInlines xs >>= \b -> at sp "CharStyle" [str c, b]
  Tcy sp t -> at sp "Tcy" [str t]
  Number sp n st -> at sp "Number" [int n, maybeR numberStyle st]
  Ref sp k l -> at sp "Ref" [con (refKind k) [], str l]
  Deferred sp e -> do
    j <- gets (Seq.length . cDeferred)
    modify' (\s -> s {cDeferred = cDeferred s Seq.|> e})
    at sp "Deferred" [con "Opaque" [nat j]]
  Note sp n xs -> encodeInlines xs >>= \b -> node "Note" [b] (Hidden sp Nothing n)
  Sidenote sp n xs -> encodeInlines xs >>= \b -> node "Sidenote" [b] (Hidden sp Nothing n)
  IndexMark sp (IndexEntry ts rs) -> at sp "IndexMark" [RList (map str ts), RList (map str rs)]
  Cite sp k -> at sp "Cite" [str k]
  ProofComment sp t -> at sp "ProofComment" [str t]
  LineBreak sp -> at sp "LineBreak" []
  Aki sp a -> at sp "Aki" [aki a]
  ChannelItem sp (ChannelItemData c k r body) -> encodeInlines body >>= \b -> at sp "ChannelItem" [str c, maybeR str k, maybeR str r, b]
  -- a link to an external URL (docs/adr ADR 0182)
  Link sp u xs -> encodeInlines xs >>= \b -> at sp "Link" [str u, b]
  where
    at sp c fs = node c fs (Hidden sp Nothing 0)
    numberStyle = \case
      StyleKanji -> con "Kanji" []
      StyleKanjiDigits -> con "KanjiDigits" []
      StyleTcy -> con "TateChuYoko" []
    refKind = \case
      RefNumber -> "RefNumber"
      RefTitle -> "RefTitle"
      RefPage -> "RefPage"
    aki = \case
      AkiZw q -> con "Zw" [RPrim (VRat q)]
      a@(AkiAbs _) -> con "Sp" [nat (fromMaybe 0 (akiAbsoluteSp a))]

encodeBlocks :: [Block] -> Enc Result
encodeBlocks = listE encodeBlock

encodeBlock :: Block -> Enc Result
encodeBlock (Block sp lbl body) = do
  (c, fs) <- case body of
    Paragraph st xs -> encodeInlines xs >>= \b -> pure ("Paragraph", [maybeR str st, b])
    Heading lv (HeadingAttrs toc n nonum notoc) xs -> do
      t <- maybeE encodeInlines toc
      b <- encodeInlines xs
      pure ("Heading", [nat lv, con "HeadingAttrs" [t, maybeR nat n, bool nonum, bool notoc], b])
    BulletList items -> (\is -> ("BulletList", [is])) <$> listE item items
    OrderedList items -> (\is -> ("OrderedList", [is])) <$> listE item items
    DefList gs -> (\g -> ("DefList", [g])) <$> listE (\(DefGroup ts ds) -> (\a b -> con "DefGroup" [a, b]) <$> listE encodeInlines ts <*> listE encodeBlocks ds) gs
    Table al h rows -> do
      hs <- listE encodeInlines h
      rs <- listE (listE encodeInlines) rows
      pure ("Table", [RList (map alignment al), hs, rs])
    CodeBlock (Code lang nums file cap diff ls) -> do
      c <- maybeE encodeInlines cap
      pure ("CodeBlock", [con "Code" [maybeR str lang, maybeR bool nums, maybeR str file, c, bool diff, RList (map codeLine ls)]])
    FigureBlock (Figure src web alt wrap width cap page rot) -> do
      c <- encodeBlocks cap
      pure ("FigureBlock", [con "Figure" [str src, maybeR str web, str alt, maybeR wrapR wrap, maybeR str width, c, maybeR nat page, bool rot]])
    ChannelOutput ch -> pure ("ChannelOutput", [channel ch])
    ForcedBreak k -> pure ("ForcedBreak", [con (breakKind k) []])
    PageControl pc -> pure ("PageControl", [pageControl pc])
    BlankLines n -> pure ("BlankLines", [nat n])
  node c fs (Hidden sp lbl 0)
  where
    item (ListItem n bs) = (\b -> con "ListItem" [maybeR nat n, b]) <$> encodeBlocks bs
    alignment = \case
      AlignDefault -> con "AlignDefault" []
      AlignLeft -> con "AlignLeft" []
      AlignCenter -> con "AlignCenter" []
      AlignRight -> con "AlignRight" []
    codeLine (CodeLine t n m hl cs) = con "CodeLine" [str t, maybeR nat n, maybeR diffMark m, bool hl, RList (map nat cs)]
    diffMark = \case
      DiffAdded -> con "Added" []
      DiffRemoved -> con "Removed" []
      DiffContext -> con "Unchanged" []
    wrapR = \case
      WrapStart -> con "WrapStart" []
      WrapEnd -> con "WrapEnd" []
    channel = \case
      TocOutput d -> con "TocOutput" [nat d]
      IndexOutput -> con "IndexOutput" []
      BibliographyOutput -> con "BibliographyOutput" []
      CustomOutput n st -> con "CustomOutput" [str n, maybeR str st]
    breakKind = \case
      BreakPage -> "BreakPage"
      BreakRecto -> "BreakRecto"
      BreakVerso -> "BreakVerso"
      BreakColumn -> "BreakColumn"
    pageControl = \case
      NoBreak -> con "NoBreak" []
      NeedLines n -> con "NeedLines" [nat n]
      AdjustLines n -> con "AdjustLines" [int n]

-- * Decoding

-- | Why a value is no IR; the types of .emet keep it from happening, but for the ranges of integers.
type Dec = Either Text

data Ctx = Ctx !Carried !SrcSpan

{- | The fields of a node of n fields, and what it carries: its own when it
came in, a new one at the span of new nodes otherwise.
-}
fieldsOf :: Ctx -> Int -> [Result] -> ([Result], Hidden)
fieldsOf (Ctx carried sp) n fs = case drop n fs of
  [RPrim (VNat i)] | Just h <- Seq.lookup (fromIntegral i) (cHidden carried) -> (take n fs, h)
  _ -> (take n fs, Hidden sp Nothing 0)

bad :: Text -> Dec a
bad = Left

listD :: (Result -> Dec a) -> Result -> Dec [a]
listD f = \case
  RList xs -> mapM f xs
  r -> bad ("リストではない値です: " <> shown r)

maybeD :: (Result -> Dec a) -> Result -> Dec (Maybe a)
maybeD f = \case
  RCon "Nothing" [] -> pure Nothing
  RCon "Just" [x] -> Just <$> f x
  r -> bad ("Maybe ではない値です: " <> shown r)

strD :: Result -> Dec Text
strD = \case
  RPrim (VString t) -> pure t
  r -> bad ("文字列ではない値です: " <> shown r)

boolD :: Result -> Dec Bool
boolD = \case
  RPrim (VBool b) -> pure b
  r -> bad ("真偽値ではない値です: " <> shown r)

-- | An integer of the CDDL @int64@ (golem-doc ADR 0006).
intD :: Result -> Dec Integer
intD = \case
  RPrim v
    | Just (_, q) <- numberOf v,
      q == fromInteger (round q) ->
        let n = round q
         in if inInt64 n then pure n else bad ("整数が範囲の外です: " <> T.pack (show n))
  r -> bad ("整数ではない値です: " <> shown r)

natD :: Result -> Dec Natural
natD r = intD r >>= \n -> if n < 0 then bad ("負の数です: " <> T.pack (show n)) else pure (fromInteger n)

smallD :: Result -> Dec Int
smallD r = fromInteger <$> intD r

ratD :: Result -> Dec Rational
ratD = \case
  RPrim v | Just (_, q) <- numberOf v -> pure q
  r -> bad ("数ではない値です: " <> shown r)

shown :: Result -> Text
shown = \case
  RCon c _ -> c
  RList _ -> "リスト"
  RTuple _ -> "組"
  RChar _ -> "文字"
  RPrim _ -> "値"
  RFun -> "関数"

{- | The inlines of a value of @Inlines@: the carried of what came in, and
the span of the nodes a function made.
-}
decodeInlines :: Carried -> SrcSpan -> Result -> Dec [Inline]
decodeInlines carried sp = listD (inlineD (Ctx carried sp))

inlinesD :: Ctx -> Result -> Dec [Inline]
inlinesD cx = listD (inlineD cx)

inlineD :: Ctx -> Result -> Dec Inline
inlineD cx = \case
  RCon c fs -> case c of
    "Text" -> one1 $ \s t -> Text s <$> strD t
    "Ruby" -> one1 $ \s segs -> Ruby s () <$> listD segment segs
    "Kenten" -> one2 $ \s sh xs -> Kenten s <$> maybeD strD sh <*> inlinesD cx xs
    "Color" -> one2 $ \s n xs -> Color s <$> strD n <*> inlinesD cx xs
    "CharStyle" -> one2 $ \s n xs -> CharStyle s <$> strD n <*> inlinesD cx xs
    "Tcy" -> one1 $ \s t -> Tcy s <$> strD t
    "Number" -> one2 $ \s n st -> Number s <$> intD n <*> maybeD numberStyle st
    "Ref" -> one2 $ \s k l -> Ref s <$> refKind k <*> strD l
    "Deferred" -> one1 $ \s d -> Deferred s <$> deferred d
    "Note" -> withNumber Note
    "Sidenote" -> withNumber Sidenote
    "IndexMark" -> one2 $ \s ts rs -> (\a b -> IndexMark s (IndexEntry a b)) <$> listD strD ts <*> listD strD rs
    "Cite" -> one1 $ \s k -> Cite s <$> strD k
    "ProofComment" -> one1 $ \s t -> ProofComment s <$> strD t
    "LineBreak" -> one 0 $ \s _ -> pure (LineBreak s)
    "Aki" -> one1 $ \s a -> Aki s <$> akiD a
    "ChannelItem" -> one 4 $ \s -> \case
      [ch, k, r, xs] -> (\a b d e -> ChannelItem s (ChannelItemData a b d e)) <$> strD ch <*> maybeD strD k <*> maybeD strD r <*> inlinesD cx xs
      _ -> arity
    "Link" -> one2 $ \s u xs -> Link s <$> strD u <*> inlinesD cx xs
    _ -> bad ("インラインではない値です: " <> c)
    where
      arity = bad ("欄の数が合いません: " <> c)
      one n k =
        let (xs, Hidden s _ _) = fieldsOf cx n fs
         in if length xs == n then k s xs else arity
      one1 k = one 1 $ \s -> \case
        [a] -> k s a
        _ -> arity
      one2 k = one 2 $ \s -> \case
        [a, b] -> k s a b
        _ -> arity
      withNumber mk =
        let (xs, Hidden s _ num) = fieldsOf cx 1 fs
         in case xs of
              [body] -> mk s num <$> inlinesD cx body
              _ -> bad ("欄の数が合いません: " <> c)
  r -> bad ("インラインではない値です: " <> shown r)
  where
    Ctx carried _ = cx
    segment = \case
      RCon "RubySegment" [base, reading] -> do
        bs <- inlinesD cx base
        nr <- maybe (bad "ルビの親文字にルビがあります") pure (traverse noRuby bs)
        RubySegment nr <$> maybeD strD reading
      r -> bad ("ルビの区切りではない値です: " <> shown r)
    numberStyle = \case
      RCon "Kanji" [] -> pure StyleKanji
      RCon "KanjiDigits" [] -> pure StyleKanjiDigits
      RCon "TateChuYoko" [] -> pure StyleTcy
      r -> bad ("数の書き方ではない値です: " <> shown r)
    refKind = \case
      RCon "RefNumber" [] -> pure RefNumber
      RCon "RefTitle" [] -> pure RefTitle
      RCon "RefPage" [] -> pure RefPage
      r -> bad ("参照の種類ではない値です: " <> shown r)
    deferred = \case
      RCon "Opaque" [RPrim (VNat j)] | Just e <- Seq.lookup (fromIntegral j) (cDeferred carried) -> pure e
      r -> bad ("遅延した値ではない値です: " <> shown r)
    akiD = \case
      RCon "Zw" [q] -> AkiZw <$> ratD q
      RCon "Sp" [n] -> akiAbsolute . toInteger <$> natD n
      r -> bad ("アキの量ではない値です: " <> shown r)

-- | The blocks of a value of @Blocks@, as 'decodeInlines'.
decodeBlocks :: Carried -> SrcSpan -> Result -> Dec [Block]
decodeBlocks carried sp = listD (blockD (Ctx carried sp))

blockD :: Ctx -> Result -> Dec Block
blockD cx = \case
  RCon c fs -> case c of
    "Paragraph" -> one 2 $ \case
      [st, xs] -> Paragraph <$> maybeD strD st <*> inls xs
      _ -> arity
    "Heading" -> one 3 $ \case
      [lv, attrs, xs] -> Heading <$> smallD lv <*> headingAttrs attrs <*> inls xs
      _ -> arity
    "BulletList" -> one1 (fmap BulletList . listD item)
    "OrderedList" -> one1 (fmap OrderedList . listD item)
    "DefList" -> one1 (fmap DefList . listD group)
    "Table" -> one 3 $ \case
      [al, h, rows] -> Table <$> listD alignment al <*> listD inls h <*> listD (listD inls) rows
      _ -> arity
    "CodeBlock" -> one1 (fmap CodeBlock . codeD)
    "FigureBlock" -> one1 (fmap FigureBlock . figure)
    "ChannelOutput" -> one1 (fmap ChannelOutput . channel)
    "ForcedBreak" -> one1 (fmap ForcedBreak . breakKind)
    "PageControl" -> one1 (fmap PageControl . pageControl)
    "BlankLines" -> one1 $ \n -> BlankLines . fromInteger <$> (intD n >>= \m -> if m < 0 then bad "負の数です" else pure m)
    _ -> bad ("ブロックではない値です: " <> c)
    where
      arity = bad ("欄の数が合いません: " <> c)
      one n k =
        let (xs, Hidden s lbl _) = fieldsOf cx n fs
         in if length xs == n then Block s lbl <$> k xs else arity
      one1 k = one 1 $ \case
        [a] -> k a
        _ -> arity
  r -> bad ("ブロックではない値です: " <> shown r)
  where
    inls = inlinesD cx
    blocks = listD (blockD cx)
    headingAttrs = \case
      RCon "HeadingAttrs" [t, n, nonum, notoc] -> HeadingAttrs <$> maybeD inls t <*> maybeD natD n <*> boolD nonum <*> boolD notoc
      r -> bad ("見出しの属性ではない値です: " <> shown r)
    item = \case
      RCon "ListItem" [n, bs] -> ListItem <$> maybeD natD n <*> blocks bs
      r -> bad ("リストの項目ではない値です: " <> shown r)
    group = \case
      RCon "DefGroup" [ts, ds] -> DefGroup <$> listD inls ts <*> listD blocks ds
      r -> bad ("定義の組ではない値です: " <> shown r)
    alignment = \case
      RCon "AlignDefault" [] -> pure AlignDefault
      RCon "AlignLeft" [] -> pure AlignLeft
      RCon "AlignCenter" [] -> pure AlignCenter
      RCon "AlignRight" [] -> pure AlignRight
      r -> bad ("揃えではない値です: " <> shown r)
    codeD = \case
      RCon "Code" [lang, nums, file, cap, diff, ls] -> Code <$> maybeD strD lang <*> maybeD boolD nums <*> maybeD strD file <*> maybeD inls cap <*> boolD diff <*> listD codeLine ls
      r -> bad ("コードではない値です: " <> shown r)
    codeLine = \case
      RCon "CodeLine" [t, n, m, hl, cs] -> CodeLine <$> strD t <*> maybeD natD n <*> maybeD diffMark m <*> boolD hl <*> listD smallD cs
      r -> bad ("コードの行ではない値です: " <> shown r)
    diffMark = \case
      RCon "Added" [] -> pure DiffAdded
      RCon "Removed" [] -> pure DiffRemoved
      RCon "Unchanged" [] -> pure DiffContext
      r -> bad ("差分の印ではない値です: " <> shown r)
    figure = \case
      RCon "Figure" [src, web, alt, wrap, width, cap, page, rot] -> Figure <$> strD src <*> maybeD strD web <*> strD alt <*> maybeD wrapD wrap <*> maybeD strD width <*> blocks cap <*> maybeD natD page <*> boolD rot
      r -> bad ("図版ではない値です: " <> shown r)
    wrapD = \case
      RCon "WrapStart" [] -> pure WrapStart
      RCon "WrapEnd" [] -> pure WrapEnd
      r -> bad ("回り込みではない値です: " <> shown r)
    channel = \case
      RCon "TocOutput" [d] -> TocOutput <$> smallD d
      RCon "IndexOutput" [] -> pure IndexOutput
      RCon "BibliographyOutput" [] -> pure BibliographyOutput
      RCon "CustomOutput" [n, st] -> CustomOutput <$> strD n <*> maybeD strD st
      r -> bad ("一覧の出力ではない値です: " <> shown r)
    breakKind = \case
      RCon "BreakPage" [] -> pure BreakPage
      RCon "BreakRecto" [] -> pure BreakRecto
      RCon "BreakVerso" [] -> pure BreakVerso
      RCon "BreakColumn" [] -> pure BreakColumn
      r -> bad ("改ページの種類ではない値です: " <> shown r)
    pageControl = \case
      RCon "NoBreak" [] -> pure NoBreak
      RCon "NeedLines" [n] -> NeedLines <$> smallD n
      RCon "AdjustLines" [n] -> AdjustLines <$> smallD n
      r -> bad ("改ページの制御ではない値です: " <> shown r)
