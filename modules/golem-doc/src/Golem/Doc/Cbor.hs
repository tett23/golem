{- | Deterministic CBOR for the semantic IR (golem-doc ADR 0001).

Sum types are arrays @[tag, fields...]@; maps are never used, so no key
order is involved. Integers use the shortest form (cborg does this) and
floats the shortest of half, single and double that keeps the value
(RFC 8949 preferred serialization).
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
    floatTerm,
    spanT,
    termSpan,
  )
where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (when, (>=>))
import Data.Bits (shiftR, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Void (Void, absurd)
import GHC.Float (castFloatToWord32, double2Float, float2Double)
import Golem.Doc.IR
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span

-- ------------------------------------------------------------------ encoding

encodeDocument :: Document -> ByteString
encodeDocument = toStrictByteString . encodeTerm . documentTerm

encodeInlines :: [Inline] -> ByteString
encodeInlines = toStrictByteString . encodeTerm . inlinesTerm

int :: (Integral a) => a -> Term
int = TInteger . toInteger

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

-- | The shortest float encoding that preserves the value.
floatTerm :: Double -> Term
floatTerm d
  | float2Double f == d = if halfExact f then THalf f else TFloat f
  | otherwise = TDouble d
  where
    f = double2Float d

-- Whether a single-precision value is exactly representable as binary16.
halfExact :: Float -> Bool
halfExact f
  | isNaN f || isInfinite f = False
  | f == 0 = True
  | otherwise =
      let w = castFloatToWord32 f
          ex = fromIntegral ((w `shiftR` 23) .&. 0xFF) - 127 :: Int
          mant = w .&. 0x7FFFFF
       in if ex >= -14 && ex <= 15
            then mant .&. 0x1FFF == 0 -- 10 mantissa bits survive
            else
              ex >= -24
                && ex < -14
                && let dropBits = 13 + (-14 - ex) in mant .&. ((2 ^ dropBits) - 1) == 0

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
  CodeBlock lang t -> tagged 6 [opt text lang, text t]
  FigureBlock fig -> tagged 7 [figureT fig]
  ChannelOutput c -> tagged 8 [channelT c]

attrsT :: HeadingAttrs -> Term
attrsT (HeadingAttrs tt n nn nt) = TList [opt inlinesTerm tt, opt int n, TBool nn, TBool nt]

itemT :: ListItem -> Term
itemT (ListItem n bs) = TList [opt int n, list blockT bs]

figureT :: Figure -> Term
figureT (Figure src web alt wr w cap) =
  TList [text src, opt text web, text alt, opt (int . fromEnum) wr, opt text w, list blockT cap]

channelT :: ChannelBlock -> Term
channelT = \case
  TocOutput d -> tagged 0 [int d]
  IndexOutput -> tagged 1 []
  BibliographyOutput -> tagged 2 []

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
  where
    sub = list (inlineT rt)

segT :: RubySegment -> Term
segT (RubySegment base reading) = TList [list (inlineT absurd) base, opt text reading]

exprT :: AST.Located AST.Expr -> Term
exprT (AST.Located s e) = case e of
  AST.EInt i -> tagged 0 [spanT s, TInteger i]
  AST.EFloat d -> tagged 1 [spanT s, floatTerm d]
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

type D = Either Text

decodeDocument :: ByteString -> D Document
decodeDocument bs = termOf bs >>= termDocument

decodeInlines :: ByteString -> D [Inline]
decodeInlines bs = termOf bs >>= termInlines

termOf :: ByteString -> D Term
termOf bs = case deserialiseFromBytes decodeTerm (BL.fromStrict bs) of
  Left e -> Left (T.pack (show e))
  Right (rest, t)
    | BL.null rest -> Right t
    | otherwise -> Left "CBOR の後に余分なバイト列があります"

bad :: Text -> D a
bad what = Left ("スキーマに合いません: " <> what)

asInt :: Term -> D Integer
asInt = \case
  TInt i -> Right (toInteger i)
  TInteger i -> Right i
  _ -> bad "整数"

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

asFloat :: Term -> D Double
asFloat = \case
  THalf f -> Right (float2Double f)
  TFloat f -> Right (float2Double f)
  TDouble d -> Right d
  _ -> bad "浮動小数点数"

termSpan :: Term -> D SrcSpan
termSpan t =
  asList t >>= \case
    [f, s, e] -> do
      f' <- asIntI f
      s' <- asIntI s
      e' <- asIntI e
      if s' < 0 || e' < s' then bad "位置の範囲" else Right (SrcSpan (FileId f') s' e')
    _ -> bad "位置"

termDocument :: Term -> D Document
termDocument t =
  asList t >>= \case
    [v, f, bs] -> do
      v' <- asIntI v
      when (v' /= abiVersion) $
        Left ("ABI の版が異なります: " <> T.pack (show v'))
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
        10 | [st, is] <- fs -> Paragraph <$> asOpt asText st <*> termInlines is
        1 | [l, a, is] <- fs -> Heading <$> asIntI l <*> termAttrs a <*> termInlines is
        2 | [xs] <- fs -> BulletList <$> (asList xs >>= traverse termItem)
        3 | [xs] <- fs -> OrderedList <$> (asList xs >>= traverse termItem)
        4 | [gs] <- fs -> DefList <$> (asList gs >>= traverse termGroup)
        5
          | [al, h, rows] <- fs ->
              Table
                <$> (asList al >>= traverse asEnum)
                <*> (asList h >>= traverse termInlines)
                <*> (asList rows >>= traverse (asList >=> traverse termInlines))
        6 | [l, x] <- fs -> CodeBlock <$> asOpt asText l <*> asText x
        7 | [fig] <- fs -> FigureBlock <$> termFigure fig
        8 | [c] <- fs -> ChannelOutput <$> termChannel c
        -- 0 (paragraph without a style) and 9 (verse) are retired (docs/adr ADR 0005)
        _ -> bad "ブロックの種類"
    [] -> bad "ブロックの種類"

termAttrs :: Term -> D HeadingAttrs
termAttrs t =
  asList t >>= \case
    [tt, n, nn, nt] -> HeadingAttrs <$> asOpt termInlines tt <*> asOpt asInt n <*> asBool nn <*> asBool nt
    _ -> bad "見出しの属性"

termItem :: Term -> D ListItem
termItem t =
  asList t >>= \case
    [n, bs] -> ListItem <$> asOpt asInt n <*> (asList bs >>= traverse termBlock)
    _ -> bad "リストの項目"

termGroup :: Term -> D DefGroup
termGroup t =
  asList t >>= \case
    [ts, ds] -> DefGroup <$> (asList ts >>= traverse termInlines) <*> (asList ds >>= traverse (asList >=> traverse termBlock))
    _ -> bad "定義リストの組"

termFigure :: Term -> D Figure
termFigure t =
  asList t >>= \case
    [src, web, alt, wr, w, cap] ->
      Figure <$> asText src <*> asOpt asText web <*> asText alt <*> asOpt asEnum wr <*> asOpt asText w <*> (asList cap >>= traverse termBlock)
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
    _ -> bad "チャネル"

termInlines :: Term -> D [Inline]
termInlines t = asList t >>= traverse (termInline (const (Right ())))

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
        (1, [x]) -> AST.EFloat <$> asFloat x
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
