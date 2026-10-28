{- | Deterministic CBOR for the semantic IR (golem-doc ADR 0001).

Sum types are arrays @[tag, fields...]@; maps are never used, so no key
order is involved. Integers use the shortest form (cborg does this). The
host writes no float: a rational is tag 30 (docs/adr ADR 0101), and a
float a plugin writes in an expression is read as its exact rational.
-}
module Golem.Doc.Cbor
  ( encodeDocument,
    decodeDocument,
    encodeInlines,
    decodeInlines,
    documentTerm,
    inlinesTerm,
    termDocument,
    termInlines,
    termDocumentE,
    termInlinesE,
    DecodeError (..),
    describeDecodeError,
    rationalTerm,
    spanT,
    termSpan,
  )
where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (when, (>=>))
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Ratio (denominator, numerator, (%))
import Data.String (IsString (..))
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void, absurd)
import GHC.Float (float2Double)
import Golem.Doc.IR
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Length (Sp (..))
import Golem.Syntax.Span
import Numeric.Natural (Natural)

-- ------------------------------------------------------------------ encoding

encodeDocument :: Document -> ByteString
encodeDocument = toStrictByteString . encodeTerm . documentTerm

encodeInlines :: [Inline] -> ByteString
encodeInlines = toStrictByteString . encodeTerm . inlinesTerm

int :: (Integral a) => a -> Term
int = TInteger . checked . toInteger

{- | An integer of the IR as it is encoded. The evaluator keeps every
integer within int64 (G02091), so one out of range is a bug of the host
(golem-doc ADR 0006): the encoding never writes a bignum.
-}
checked :: Integer -> Integer
checked n
  | inInt64 n = n
  | otherwise = error ("golem-doc: an integer out of int64 reached the encoder: " <> show n)

text :: Text -> Term
text = TString

opt :: (a -> Term) -> Maybe a -> Term
opt = maybe TNull

list :: (a -> Term) -> [a] -> Term
list f = TList . map f

tagged :: Int -> [Term] -> Term
tagged t xs = TList (int t : xs)

spanT :: SrcSpan -> Term
spanT (SrcSpan (FileId f) s e) = TList [int f, int s, int e]

{- | A rational as the CDDL @rational@: tag 30 of the numerator and the
denominator in lowest terms (RFC 8949, docs/adr ADR 0101), the
denominator 1 for an integral value.
-}
rationalTerm :: Rational -> Term
rationalTerm q = TTagged 30 (TList [int (numerator q), int (denominator q)])

documentTerm :: Document -> Term
documentTerm (Document (FileId f) bs) = TList [int abiVersion, int f, list blockT bs]

blockT :: Block -> Term
blockT (Block sp lbl body) = TList [spanT sp, opt text lbl, bodyT body]

bodyT :: BlockBody -> Term
bodyT = \case
  Paragraph st is -> tagged 10 [opt text st, inlinesTerm is]
  Heading l a is -> tagged 1 [int l, attrsT a, inlinesTerm is]
  BulletList items -> tagged 2 [list itemT items]
  OrderedList items -> tagged 3 [list itemT items]
  DefList gs -> tagged 4 [list (\(DefGroup ts ds) -> TList [list inlinesTerm ts, list (list blockT) ds]) gs]
  Table al h rows -> tagged 5 [list (int . fromEnum) al, list inlinesTerm h, list (list inlinesTerm) rows]
  CodeBlock c -> tagged 6 [codeT c]
  FigureBlock fig -> tagged 7 [figureT fig]
  ChannelOutput c -> tagged 8 [channelT c]
  ForcedBreak k -> tagged 11 [int (fromEnum k)]
  PageControl c -> tagged 12 [pageControlT c]
  BlankLines n -> tagged 13 [int n]

pageControlT :: PageControl -> Term
pageControlT = \case
  NoBreak -> TList [int (0 :: Int)]
  NeedLines n -> TList [int (1 :: Int), int n]
  AdjustLines n -> TList [int (2 :: Int), int n]

codeT :: Code -> Term
codeT (Code lang nums file cap diff ls) =
  TList [opt text lang, opt TBool nums, opt text file, opt inlinesTerm cap, TBool diff, list lineT ls]
  where
    lineT (CodeLine t n d h cs) = TList [text t, opt int n, opt (int . fromEnum) d, TBool h, list int cs]

attrsT :: HeadingAttrs -> Term
attrsT (HeadingAttrs tt n nn nt) = TList [opt inlinesTerm tt, opt int n, TBool nn, TBool nt]

itemT :: ListItem -> Term
itemT (ListItem n bs) = TList [opt int n, list blockT bs]

figureT :: Figure -> Term
figureT (Figure src web alt wr w cap pg rot) =
  TList [text src, opt text web, text alt, opt (int . fromEnum) wr, opt text w, list blockT cap, opt int pg, TBool rot]

channelT :: ChannelBlock -> Term
channelT = \case
  TocOutput d -> tagged 0 [int d]
  IndexOutput -> tagged 1 []
  BibliographyOutput -> tagged 2 []
  CustomOutput n st -> tagged 3 [text n, opt text st]

inlinesTerm :: [Inline] -> Term
inlinesTerm = list (inlineT (const TNull))

inlineT :: (r -> Term) -> InlineF r -> Term
inlineT rt = \case
  Text s t -> tagged 0 [spanT s, text t]
  Ruby s r segs -> let _ = rt r in tagged 4 [spanT s, list segT segs]
  Kenten s sh xs -> tagged 5 [spanT s, opt text sh, sub xs]
  Color s c xs -> tagged 6 [spanT s, text c, sub xs]
  CharStyle s c xs -> tagged 7 [spanT s, text c, sub xs]
  Tcy s t -> tagged 8 [spanT s, text t]
  Number s n st -> tagged 9 [spanT s, int n, opt (int . fromEnum) st]
  Ref s k l -> tagged 10 [spanT s, int (fromEnum k), text l]
  Deferred s (DeferredExpr e) -> tagged 11 [spanT s, exprT e]
  Note s n xs -> tagged 12 [spanT s, int n, sub xs]
  Sidenote s n xs -> tagged 13 [spanT s, int n, sub xs]
  IndexMark s (IndexEntry ts rs) -> tagged 14 [spanT s, list text ts, list text rs]
  Cite s k -> tagged 15 [spanT s, text k]
  ProofComment s t -> tagged 16 [spanT s, text t]
  LineBreak s -> tagged 17 [spanT s]
  Aki s (AkiZw r) -> tagged 18 [spanT s, TList [int (numerator r), int (denominator r)], TNull]
  Aki s (AkiAbs x) -> tagged 18 [spanT s, TNull, int (unSp x)]
  ChannelItem s (ChannelItemData c k r body) -> tagged 19 [spanT s, text c, opt text k, opt text r, inlinesTerm body]
  where
    sub = list (inlineT rt)

segT :: RubySegment -> Term
segT (RubySegment base reading) = TList [list (inlineT absurd) base, opt text reading]

exprT :: AST.Located AST.Expr -> Term
exprT (AST.Located s e) = case e of
  AST.EInt i -> tagged 0 [spanT s, int i]
  AST.ENat n -> tagged 12 [spanT s, int n]
  AST.ERat q -> tagged 13 [spanT s, rationalTerm q]
  AST.EString t -> tagged 2 [spanT s, text t]
  AST.EBool b -> tagged 3 [spanT s, TBool b]
  AST.ENil -> tagged 4 [spanT s]
  AST.EArray xs -> tagged 5 [spanT s, list exprT xs]
  AST.EHash kvs -> tagged 6 [spanT s, list (\(k, v) -> TList [text k, exprT v]) kvs]
  AST.EVar ns -> tagged 7 [spanT s, list text ns]
  AST.ECall f xs -> tagged 8 [spanT s, text f, list exprT xs]
  AST.EUnary _ x -> tagged 9 [spanT s, exprT x]
  AST.EBinary op a b -> tagged 10 [spanT s, int (binopIndex op), exprT a, exprT b]
  AST.EError -> tagged 11 [spanT s]

binops :: [AST.BinaryOp]
binops = [AST.Add, AST.Sub, AST.Mul, AST.Div, AST.Mod, AST.Pow, AST.OpEq, AST.OpNe, AST.OpLt, AST.OpLe, AST.OpGt, AST.OpGe]

binopIndex :: AST.BinaryOp -> Int
binopIndex op = length (takeWhile (/= op) binops)

-- ------------------------------------------------------------------ decoding

{- | Why a term is no IR: it does not conform to the schema, or a float a
plugin wrote in an expression has no finite value (G06100, docs/adr ADR
0101), with the value as text: NaN, Infinity or -Infinity.
-}
data DecodeError
  = SchemaError Text
  | FloatNotFinite Text
  deriving stock (Eq, Show)

instance IsString DecodeError where
  fromString = SchemaError . T.pack

describeDecodeError :: DecodeError -> Text
describeDecodeError = \case
  SchemaError t -> t
  FloatNotFinite v -> "遅延した式に有限でない浮動小数点数（" <> v <> "）があります"

type D = Either DecodeError

decodeDocument :: ByteString -> Either Text Document
decodeDocument bs = first describeDecodeError (termOf bs >>= termDocumentE)

decodeInlines :: ByteString -> Either Text [Inline]
decodeInlines bs = first describeDecodeError (termOf bs >>= termInlinesE)

termDocument :: Term -> Either Text Document
termDocument = first describeDecodeError . termDocumentE

termInlines :: Term -> Either Text [Inline]
termInlines = first describeDecodeError . termInlinesE

termOf :: ByteString -> D Term
termOf bs = case deserialiseFromBytes decodeTerm (BL.fromStrict bs) of
  Left e -> Left (SchemaError (T.pack (show e)))
  Right (rest, t)
    | BL.null rest -> Right t
    | otherwise -> Left "CBOR の後に余分なバイト列があります"

bad :: Text -> D a
bad what = Left (SchemaError ("スキーマに合いません: " <> what))

{- | An integer of the CDDL @int64@ (golem-doc ADR 0006); a larger one,
a bignum (tags 2 and 3) included, does not conform.
-}
asInt :: Term -> D Integer
asInt = \case
  TInt i -> Right (toInteger i)
  TInteger i
    | inInt64 i -> Right i
    | otherwise -> bad "整数が範囲の外です"
  _ -> bad "整数"

{- | An integer of a field of type 'Int'. 'asInt' has checked the range,
which is the range of 'Int', so 'fromInteger' never rounds it.
-}
asIntI :: Term -> D Int
asIntI t = fromInteger <$> asInt t

asText :: Term -> D Text
asText = \case
  TString t -> Right t
  _ -> bad "文字列"

asBool :: Term -> D Bool
asBool = \case
  TBool b -> Right b
  _ -> bad "真偽値"

asList :: Term -> D [Term]
asList = \case
  TList xs -> Right xs
  _ -> bad "配列"

asOpt :: (Term -> D a) -> Term -> D (Maybe a)
asOpt _ TNull = Right Nothing
asOpt f t = Just <$> f t

asEnum :: forall a. (Bounded a, Enum a) => Term -> D a
asEnum t = do
  i <- asIntI t
  if i >= fromEnum (minBound :: a) && i <= fromEnum (maxBound :: a) then Right (toEnum i) else bad "列挙の範囲"

{- | A float a plugin wrote in an expression, as its exact rational, a
negative zero as 0 (docs/adr ADR 0101); NaN and the infinities have none.
-}
asFloatRational :: Term -> D Rational
asFloatRational = \case
  THalf f -> exact (float2Double f)
  TFloat f -> exact (float2Double f)
  TDouble d -> exact d
  _ -> bad "浮動小数点数"
  where
    exact d
      | isNaN d = Left (FloatNotFinite "NaN")
      | isInfinite d = Left (FloatNotFinite (if d > 0 then "Infinity" else "-Infinity"))
      | otherwise = Right (toRational d)

-- | The CDDL @rational@ in lowest terms with a denominator of 1 or more.
asRational :: Term -> D Rational
asRational = \case
  TTagged 30 (TList [n, d]) -> do
    n' <- asInt n
    d' <- asInt d
    if d' < 1
      then bad "有理数"
      else if gcd n' d' /= 1 then bad "有理数が既約ではありません" else Right (n' % d')
  _ -> bad "有理数"

-- | The CDDL @uint64@ as a natural number.
asNatural :: Term -> D Natural
asNatural t = asInt t >>= \i -> if i < 0 then bad "自然数" else Right (fromInteger i)

termSpan :: Term -> D SrcSpan
termSpan t =
  asList t >>= \case
    [f, s, e] -> do
      f' <- asIntI f
      s' <- asIntI s
      e' <- asIntI e
      if s' < 0 || e' < s' then bad "位置の範囲" else Right (SrcSpan (FileId f') s' e')
    _ -> bad "位置"

termDocumentE :: Term -> D Document
termDocumentE t =
  asList t >>= \case
    [v, f, bs] -> do
      v' <- asIntI v
      when (v' /= abiVersion) $
        Left (SchemaError ("ABI のバージョンが異なります: " <> T.pack (show v')))
      Document . FileId <$> asIntI f <*> (asList bs >>= traverse termBlock)
    _ -> bad "文書"

termBlock :: Term -> D Block
termBlock t =
  asList t >>= \case
    [sp, lbl, body] -> Block <$> termSpan sp <*> asOpt asText lbl <*> termBody body
    _ -> bad "ブロック"

termBody :: Term -> D BlockBody
termBody t =
  asList t >>= \case
    (tag : fs) ->
      asIntI tag >>= \case
        10 | [st, is] <- fs -> Paragraph <$> asOpt asText st <*> termInlinesE is
        1 | [l, a, is] <- fs -> Heading <$> asIntI l <*> termAttrs a <*> termInlinesE is
        2 | [xs] <- fs -> BulletList <$> (asList xs >>= traverse termItem)
        3 | [xs] <- fs -> OrderedList <$> (asList xs >>= traverse termItem)
        4 | [gs] <- fs -> DefList <$> (asList gs >>= traverse termGroup)
        5
          | [al, h, rows] <- fs ->
              Table
                <$> (asList al >>= traverse asEnum)
                <*> (asList h >>= traverse termInlinesE)
                <*> (asList rows >>= traverse (asList >=> traverse termInlinesE))
        6 | [c] <- fs -> CodeBlock <$> termCode c
        7 | [fig] <- fs -> FigureBlock <$> termFigure fig
        8 | [c] <- fs -> ChannelOutput <$> termChannel c
        11 | [k] <- fs -> ForcedBreak <$> asEnum k
        12 | [c] <- fs -> PageControl <$> termPageControl c
        13 | [n] <- fs -> BlankLines . fromInteger <$> asInt n
        -- 0 (paragraph without a style) and 9 (verse) are retired (docs/adr ADR 0005)
        _ -> bad "ブロックの種類"
    [] -> bad "ブロックの種類"

termPageControl :: Term -> D PageControl
termPageControl t =
  asList t >>= \case
    [k] | Right 0 <- asIntI k -> Right NoBreak
    [k, n] | Right 1 <- asIntI k -> NeedLines <$> asIntI n
    [k, n] | Right 2 <- asIntI k -> AdjustLines <$> asIntI n
    _ -> bad "改ページの制御"

termCode :: Term -> D Code
termCode t =
  asList t >>= \case
    [l, n, f, c, d, ls] -> Code <$> asOpt asText l <*> asOpt asBool n <*> asOpt asText f <*> asOpt termInlinesE c <*> asBool d <*> (asList ls >>= traverse termLine)
    _ -> bad "コードブロック"
  where
    termLine x =
      asList x >>= \case
        [s, n, d, h, cs] -> CodeLine <$> asText s <*> asOpt asNatural n <*> asOpt asEnum d <*> asBool h <*> (asList cs >>= traverse asIntI)
        _ -> bad "コードの行"

termAttrs :: Term -> D HeadingAttrs
termAttrs t =
  asList t >>= \case
    [tt, n, nn, nt] -> HeadingAttrs <$> asOpt termInlinesE tt <*> asOpt asNatural n <*> asBool nn <*> asBool nt
    _ -> bad "見出しの属性"

termItem :: Term -> D ListItem
termItem t =
  asList t >>= \case
    [n, bs] -> ListItem <$> asOpt asNatural n <*> (asList bs >>= traverse termBlock)
    _ -> bad "リストの項目"

termGroup :: Term -> D DefGroup
termGroup t =
  asList t >>= \case
    [ts, ds] -> DefGroup <$> (asList ts >>= traverse termInlinesE) <*> (asList ds >>= traverse (asList >=> traverse termBlock))
    _ -> bad "定義リストの組"

termFigure :: Term -> D Figure
termFigure t =
  asList t >>= \case
    [src, web, alt, wr, w, cap, pg, rot] ->
      Figure <$> asText src <*> asOpt asText web <*> asText alt <*> asOpt asEnum wr <*> asOpt asText w <*> (asList cap >>= traverse termBlock) <*> asOpt asNatural pg <*> asBool rot
    _ -> bad "図版"

termChannel :: Term -> D ChannelBlock
termChannel t =
  asList t >>= \case
    [tag, d] ->
      asIntI tag >>= \case
        0 -> TocOutput <$> asIntI d
        _ -> bad "チャネル"
    [tag] ->
      asIntI tag >>= \case
        1 -> Right IndexOutput
        2 -> Right BibliographyOutput
        _ -> bad "チャネル"
    [tag, n, st] ->
      asIntI tag >>= \case
        3 -> CustomOutput <$> asText n <*> asOpt asText st
        _ -> bad "チャネル"
    _ -> bad "チャネル"

termInlinesE :: Term -> D [Inline]
termInlinesE t = asList t >>= traverse (termInline (const (Right ())))

{- | The ruby decoder decides whether ruby is allowed: inside a ruby base it
is 'Left', which is how nested ruby is rejected.
-}
termInline :: (Term -> D r) -> Term -> D (InlineF r)
termInline rd t =
  asList t >>= \case
    (tag : sp : fs) -> do
      s <- termSpan sp
      i <- asIntI tag
      let sub x = asList x >>= traverse (termInline rd)
      case (i, fs) of
        (0, [x]) -> Text s <$> asText x
        (4, [segs]) -> Ruby s <$> rd TNull <*> (asList segs >>= traverse termSeg)
        (5, [sh, x]) -> Kenten s <$> asOpt asText sh <*> sub x
        (6, [c, x]) -> Color s <$> asText c <*> sub x
        (7, [c, x]) -> CharStyle s <$> asText c <*> sub x
        (8, [x]) -> Tcy s <$> asText x
        (9, [n, st]) -> Number s <$> asInt n <*> asOpt asEnum st
        (10, [k, l]) -> Ref s <$> asEnum k <*> asText l
        (11, [e]) -> Deferred s . DeferredExpr <$> termExpr e
        (12, [n, x]) -> Note s <$> asIntI n <*> sub x
        (13, [n, x]) -> Sidenote s <$> asIntI n <*> sub x
        (14, [ts, rs]) -> (\a b -> IndexMark s (IndexEntry a b)) <$> (asList ts >>= traverse asText) <*> (asList rs >>= traverse asText)
        (15, [k]) -> Cite s <$> asText k
        (16, [x]) -> ProofComment s <$> asText x
        (17, []) -> Right (LineBreak s)
        -- aki (docs/adr ADR 0019): zw as numerator and denominator, or sp; exactly one of them
        (18, [TList [n, d], TNull]) -> do
          n' <- toInteger <$> asNatural n
          d' <- asInt d
          if d' > 0 then Right (Aki s (AkiZw (n' % d'))) else bad "アキの分母"
        (18, [TNull, x]) -> Aki s . AkiAbs . Sp . toInteger <$> asNatural x
        -- an item of a channel of a plugin (golem-doc ADR 0007)
        (19, [c, k, r, x]) -> fmap (ChannelItem s) (ChannelItemData <$> asText c <*> asOpt asText k <*> asOpt asText r <*> termInlinesE x)
        -- 1, 2 and 3 (strong, bold, italic) are retired: they are character styles (docs/adr ADR 0005)
        _ -> bad "インラインの種類"
    _ -> bad "インライン"

termSeg :: Term -> D RubySegment
termSeg t =
  asList t >>= \case
    [base, reading] -> RubySegment <$> (asList base >>= traverse (termInline noRubyHere)) <*> asOpt asText reading
    _ -> bad "ルビのセグメント"
  where
    noRubyHere :: Term -> D Void
    noRubyHere _ = Left "ルビの中にルビがあります"

termExpr :: Term -> D (AST.Located AST.Expr)
termExpr t =
  asList t >>= \case
    (tag : sp : fs) -> do
      s <- termSpan sp
      i <- asIntI tag
      AST.Located s <$> case (i, fs) of
        (0, [x]) -> AST.EInt <$> asInt x
        -- written by a plugin, never by the host (docs/adr ADR 0101)
        (1, [x]) -> AST.ERat <$> asFloatRational x
        (12, [x]) -> AST.ENat <$> asNatural x
        (13, [x]) -> AST.ERat <$> asRational x
        (2, [x]) -> AST.EString <$> asText x
        (3, [x]) -> AST.EBool <$> asBool x
        (4, []) -> Right AST.ENil
        (5, [xs]) -> AST.EArray <$> (asList xs >>= traverse termExpr)
        (6, [kvs]) -> AST.EHash <$> (asList kvs >>= traverse kv)
        (7, [ns]) -> AST.EVar <$> (asList ns >>= traverse asText)
        (8, [f, xs]) -> AST.ECall <$> asText f <*> (asList xs >>= traverse termExpr)
        (9, [x]) -> AST.EUnary AST.Negate <$> termExpr x
        (10, [op, a, b]) -> do
          o <- asIntI op
          if o < 0 || o >= length binops then bad "演算子" else AST.EBinary (binops !! o) <$> termExpr a <*> termExpr b
        (11, []) -> Right AST.EError
        _ -> bad "式"
    _ -> bad "式"
  where
    kv x =
      asList x >>= \case
        [k, v] -> (,) <$> asText k <*> termExpr v
        _ -> bad "連想配列の要素"
