{-# LANGUAGE CApiFFI #-}

{- | Plugins as wasm modules run by wasmtime 49.0.2 (golem-plugin ADR 0001).
No imports, no WASI, no threads, canonical NaNs, no relaxed SIMD, fuel
and memory limits, a fresh instance per call. Requests and responses
are CBOR (golem-doc.cddl); every response is validated. Compiling and
checking a plugin is IO, called where its bytes are read; only a call
('invokeRaw', which 'callCommand' and 'applyFilter' use) is wrapped as a
pure function, since the evaluator makes it (docs/adr ADR 0034).
-}
module Golem.Plugin
  ( Plugin,
    pluginCommands,
    pluginFilters,
    pluginChannels,
    PluginError (..),
    abiVersion,
    defaultFuel,
    defaultMemoryLimit,
    watToWasm,
    loadPlugin,
    loadPluginWith,
    invokeRaw,
    commandRequest,
    valueTerm,
    termValue,
    callCommand,
    applyFilter,
    describePluginError,
  )
where

import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Unsafe qualified as BU
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Foreign
import Foreign.C.String (CString, peekCString, withCStringLen)
import Foreign.C.Types
import Golem.Doc.Assemble (ChannelDecl (..), ChannelOrder (..))
import Golem.Doc.Cbor
import Golem.Doc.IR hiding (abiVersion)
import Golem.Doc.Validate (validateDocument)
import Golem.Eval.Value (Value (..))
import Golem.Syntax
import System.IO.Unsafe (unsafePerformIO)

data CPlugin

foreign import capi unsafe "golem_plugin.h golem_plugin_load" c_load :: Ptr Word8 -> CSize -> Ptr CString -> IO (Ptr CPlugin)

foreign import capi unsafe "golem_plugin.h &golem_plugin_free" c_free :: FunPtr (Ptr CPlugin -> IO ())

foreign import capi unsafe "golem_plugin.h golem_plugin_import_count" c_importCount :: Ptr CPlugin -> IO CInt

foreign import capi unsafe "golem_plugin.h golem_plugin_import_name" c_importName :: Ptr CPlugin -> CInt -> IO CString

foreign import capi safe "golem_plugin.h golem_plugin_call"
  c_call :: Ptr CPlugin -> CInt -> Word64 -> Int64 -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> Ptr Word32 -> Ptr CString -> IO CInt

foreign import capi unsafe "golem_plugin.h golem_plugin_free_bytes" c_freeBytes :: Ptr a -> IO ()

foreign import capi unsafe "golem_plugin.h golem_wat2wasm" c_wat2wasm :: CString -> CSize -> Ptr CSize -> Ptr CString -> IO (Ptr Word8)

{- | The ABI version of this host, the one of the IR ('Golem.Doc.IR.abiVersion'):
one more than the last release only when the ABI changed since
(docs/adr ADR 0052).
-}
abiVersion :: Word32
abiVersion = 8

-- | The fuel of one call: about this many wasm instructions.
defaultFuel :: Word64
defaultFuel = 1000000000

-- | The memory of one instance: 256 MiB.
defaultMemoryLimit :: Int64
defaultMemoryLimit = 256 * 1024 * 1024

data Plugin = Plugin
  { plPtr :: !(ForeignPtr CPlugin),
    plFuel :: !Word64,
    plMemory :: !Int64,
    pluginCommands :: ![Text],
    pluginFilters :: ![Text],
    -- | the channels it declares (golem-doc ADR 0007)
    pluginChannels :: ![ChannelDecl]
  }

data PluginError
  = CompileFailed Text
  | HasImports [Text]
  | AbiMismatch Word32
  | MissingExport Text
  | OutOfFuel Text
  | Trapped Text
  | InstantiateFailed Text
  | BadOutput Text
  | {- | a float without a finite value in a deferred expression, with the
    value: NaN, Infinity or -Infinity (G06100, docs/adr ADR 0101)
    -}
    NonFiniteFloat Text
  deriving stock (Eq, Show)

describePluginError :: PluginError -> Text
describePluginError = \case
  CompileFailed m -> "プラグインを読み込めません: " <> m
  HasImports is -> "プラグインが import を要求しています: " <> T.intercalate ", " is
  AbiMismatch v -> "プラグインの ABI のバージョンが異なります: " <> T.pack (show v)
  MissingExport n -> "プラグインが関数を公開していません: " <> n
  OutOfFuel _ -> "プラグインの実行が命令数の上限を超えました"
  Trapped m -> "プラグインの実行が失敗しました（メモリの上限を超えた場合を含む）: " <> m
  InstantiateFailed m -> "プラグインを起動できません: " <> m
  BadOutput m -> "プラグインの出力が不正です: " <> m
  NonFiniteFloat v -> "遅延した式に有限でない浮動小数点数（" <> v <> "）があります"

withMessage :: (Ptr CString -> IO a) -> IO (a, Text)
withMessage k = alloca $ \errPtr -> do
  poke errPtr nullPtr
  r <- k errPtr
  e <- peek errPtr
  msg <- if e == nullPtr then pure "" else T.pack <$> peekCString e <* c_freeBytes e
  pure (r, msg)

-- | The text format to the binary format (for test plugins written in wat).
watToWasm :: Text -> IO (Either Text ByteString)
watToWasm wat =
  withCStringLen (T.unpack wat) $ \(p, n) ->
    alloca $ \lenPtr -> do
      (out, msg) <- withMessage (c_wat2wasm p (fromIntegral n) lenPtr)
      if out == nullPtr
        then pure (Left msg)
        else do
          len <- peek lenPtr
          b <- BS.packCStringLen (castPtr out, fromIntegral len)
          c_freeBytes out
          pure (Right b)

loadPlugin :: ByteString -> IO (Either PluginError Plugin)
loadPlugin = loadPluginWith defaultFuel defaultMemoryLimit

{- | Compiles a module and checks it: no imports, the ABI version, the
description of its commands and filters.
-}
loadPluginWith :: Word64 -> Int64 -> ByteString -> IO (Either PluginError Plugin)
loadPluginWith fuel memory wasm = do
  (p, msg) <- BU.unsafeUseAsCStringLen wasm $ \(ptr, len) -> withMessage (c_load (castPtr ptr) (fromIntegral len))
  if p == nullPtr
    then pure (Left (CompileFailed msg))
    else do
      fp <- newForeignPtr c_free p
      n <- c_importCount p
      names <- mapM (\i -> c_importName p i >>= \c -> T.pack <$> peekCString c <* c_freeBytes c) [0 .. n - 1]
      let plugin = Plugin fp fuel memory [] [] []
      if not (null names)
        then pure (Left (HasImports names))
        else do
          version <- callMode plugin 0 BS.empty
          case version of
            Left e -> pure (Left e)
            Right (_, v)
              | v /= abiVersion -> pure (Left (AbiMismatch v))
              | otherwise -> do
                  described <- callMode plugin 1 BS.empty
                  pure $ do
                    (bytes, _) <- described
                    (cmds, filts, chans) <- decodeDescription bytes
                    Right plugin {pluginCommands = cmds, pluginFilters = filts, pluginChannels = chans}

callMode :: Plugin -> CInt -> ByteString -> IO (Either PluginError (ByteString, Word32))
callMode plugin mode input = withForeignPtr (plPtr plugin) $ \p ->
  BU.unsafeUseAsCStringLen input $ \(inPtr, inLen) ->
    alloca $ \outPtr -> alloca $ \outLen -> alloca $ \u32 -> do
      poke outPtr nullPtr
      poke u32 0
      (status, msg) <- withMessage (c_call p mode (plFuel plugin) (plMemory plugin) (castPtr inPtr) (fromIntegral inLen) outPtr outLen u32)
      out <- peek outPtr
      bytes <-
        if out == nullPtr
          then pure BS.empty
          else do
            len <- peek outLen
            b <- BS.packCStringLen (castPtr out, fromIntegral len)
            c_freeBytes out
            pure b
      v <- peek u32
      pure $ case status of
        0 -> Right (bytes, v)
        2 -> Left (OutOfFuel msg)
        3 -> Left (MissingExport msg)
        4 -> Left (BadOutput msg)
        -- the ABI's type of a result, checked by the host (docs/adr ADR 0035)
        6 -> Left (BadOutput (msg <> " の戻り値の型が不正です"))
        5 -> Left (InstantiateFailed msg)
        _ -> Left (Trapped msg)

{- | One call of @golem_invoke@ with raw CBOR. The one unsafePerformIO of
this module (docs/adr ADR 0034): the evaluator, a pure function, calls
it. It is a function of the plugin and the input alone, since each call
gets a fresh store and instance, the plugin has no imports, and its
limits are counted in instructions and bytes, not in time (ADR 0001).
-}
invokeRaw :: Plugin -> ByteString -> Either PluginError ByteString
invokeRaw plugin input = fst <$> unsafePerformIO (callMode plugin 2 input)

decodeTermBytes :: ByteString -> Either PluginError Term
decodeTermBytes b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
  Right (rest, t) | BL.null rest -> Right t
  Right _ -> Left (BadOutput "CBOR の後ろに余分なバイトがあります")
  Left e -> Left (BadOutput (T.pack (show e)))

{- | The commands, the filters and the channels of a description
(golem-doc ADR 0007): three lists; two are not a description.
-}
decodeDescription :: ByteString -> Either PluginError ([Text], [Text], [ChannelDecl])
decodeDescription b = do
  t <- decodeTermBytes b
  case t of
    TList [TList cs, TList fs, TList chs] -> (,,) <$> mapM name cs <*> mapM name fs <*> mapM channel chs
    _ -> Left (BadOutput "golem_describe の形が不正です")
  where
    name = \case
      TString s -> Right s
      _ -> Left (BadOutput "名前が文字列ではありません")
    channel = \case
      TList [TString n, TInt o, TBool l]
        | o == 0 -> Right (ChannelDecl n OrderDocument l)
        | o == 1 -> Right (ChannelDecl n OrderReading l)
      _ -> Left (BadOutput "チャネルの宣言の形が不正です")

{- | A value as a plugin gets it (docs/adr ADR 0101): a natural number and
an integer as an integer, a rational as tag 30 even when it is integral,
a range as the map of first and last, the keys in that order (docs/adr
ADR 0113).
-}
valueTerm :: Value -> Either PluginError Term
valueTerm = \case
  VNat n -> Right (TInteger (toInteger n))
  VInt i -> Right (TInteger i)
  VRat q -> Right (rationalTerm q)
  VString s -> Right (TString s)
  VBool b -> Right (TBool b)
  VNil -> Right TNull
  VArray vs -> TList <$> mapM valueTerm vs
  VHash _ -> Left (BadOutput "ハッシュはプラグインに渡せません")
  VRange a b -> Right (TMap [(TString "first", TInteger a), (TString "last", TInteger b)])

{- | The @value@ of the CDDL read back, as a plugin reads its arguments
(docs/adr ADR 0113): an integer as 'VInt', a rational of tag 30 in
lowest terms, and a range as a map of exactly first and last whose first
is not after its last. The host writes values and never reads them; this
is the reading the schema asks of a plugin.
-}
termValue :: Term -> Either Text Value
termValue = \case
  TInt i -> Right (VInt (toInteger i))
  TInteger i | inInt64 i -> Right (VInt i)
  TTagged 30 (TList [n, d])
    | Just a <- int64 n, Just b <- int64 d, b >= 1, gcd a b == 1 -> Right (VRat (fromInteger a / fromInteger b))
  TString t -> Right (VString t)
  TBool b -> Right (VBool b)
  TNull -> Right VNil
  TList ts -> VArray <$> mapM termValue ts
  TMap kvs -> case kvs of
    [(TString "first", f), (TString "last", l)]
      | Just a <- int64 f, Just b <- int64 l -> if a > b then Left "範囲の first が last より大きくなっています" else Right (VRange a b)
    _ -> Left "範囲のキーは first と last の二つです"
  _ -> Left "値の形が不正です"
  where
    int64 = \case
      TInt i -> Just (toInteger i)
      TInteger i | inInt64 i -> Just i
      _ -> Nothing
    inInt64 i = i >= -9223372036854775808 && i <= 9223372036854775807

-- | The CBOR of a command request (golem-doc.cddl @command-request@).
commandRequest :: Text -> [Value] -> [[Inline]] -> SrcSpan -> Either PluginError ByteString
commandRequest name args slots sp = do
  argTerms <- mapM valueTerm args
  pure (toStrictByteString (encodeTerm (TList [TInt 0, TString name, TList [TList [TInt 0, a] | a <- argTerms], TList (map inlinesTerm slots), spanT sp])))

-- | The IR of an answer; a float without a finite value is G06100, not bad output.
decoded :: Either DecodeError a -> Either PluginError a
decoded = \case
  Right x -> Right x
  Left (FloatNotFinite v) -> Left (NonFiniteFloat v)
  Left e -> Left (BadOutput (describeDecodeError e))

-- | A command of the plugin. Returns the inlines and the plugin's diagnostics.
callCommand :: Plugin -> Text -> [Value] -> [[Inline]] -> SrcSpan -> Either PluginError ([Inline], [Diagnostic])
callCommand plugin name args slots sp = do
  req <- commandRequest name args slots sp
  out <- invokeRaw plugin req
  (outT, diags) <- response out
  inls <- decoded (termInlinesE outT)
  checkItems plugin [] (concatMap inlineItems inls)
  let allowedSpans = Set.insert sp (Set.fromList (concatMap (concatMap inlineSpans) slots))
      allowedDeferred = concatMap (concatMap inlineDeferred) slots
  checkOutput allowedSpans allowedDeferred (concatMap inlineSpans inls) (concatMap inlineDeferred inls)
  Right (inls, diags)

-- | A filter of the plugin over one file's document.
applyFilter :: Plugin -> Text -> Document -> Either PluginError (Document, [Diagnostic])
applyFilter plugin name doc = do
  let req = TList [TInt 1, TString name, documentTerm doc]
  out <- invokeRaw plugin (toStrictByteString (encodeTerm req))
  (outT, diags) <- response out
  doc' <- decoded (termDocumentE outT)
  -- the items that came in with the document pass as they are (golem-doc ADR 0007)
  checkItems plugin (documentItems doc) (documentItems doc')
  checkOutput (Set.fromList (documentSpans doc)) (documentDeferred doc) (documentSpans doc') (documentDeferred doc')
  -- the invariants of the IR, such as forced breaks only at the top (docs/adr ADR 0017);
  -- the spans were checked above, so every file is taken to be large enough
  case validateDocument (const (Just maxBound)) (documentDeferred doc) doc' of
    [] -> Right (doc', diags)
    errs -> Left (BadOutput (T.intercalate "、" errs))

response :: ByteString -> Either PluginError (Term, [Diagnostic])
response bytes = do
  t <- decodeTermBytes bytes
  case t of
    TList [out, TList ds] -> (out,) <$> mapM diag ds
    _ -> Left (BadOutput "応答の形が不正です")
  where
    diag = \case
      TList [TString code, sev, spT, TString msg] -> do
        sp <- decoded (termSpan spT)
        severity <- case sev of
          TInt 0 -> Right Error
          TInt 1 -> Right Warning
          _ -> Left (BadOutput "診断の重大度が不正です")
        Right (diagnostic code severity sp msg)
      _ -> Left (BadOutput "診断の形が不正です")

{- | The output may only carry source positions and deferred expressions
that came in with the request (ADR 0001).
-}
checkOutput :: Set.Set SrcSpan -> [DeferredExpr] -> [SrcSpan] -> [DeferredExpr] -> Either PluginError ()
checkOutput allowedSpans allowedDeferred spans deferred
  | any (`Set.notMember` allowedSpans) spans = Left (BadOutput "要求にないソース位置を含んでいます")
  | any (`notElem` allowedDeferred) deferred = Left (BadOutput "要求にない DeferredExpr を含んでいます")
  | otherwise = Right ()

{- | The items of channels a plugin puts out (golem-doc ADR 0007): of a
channel it declares, with a reading when the channel is in reading order;
an item that came in with the request is let through. The body is
checked with the IR (Golem.Doc.Validate).
-}
checkItems :: Plugin -> [(SrcSpan, ChannelItem)] -> [(SrcSpan, ChannelItem)] -> Either PluginError ()
checkItems plugin given = mapM_ check
  where
    check x@(_, c)
      | x `elem` given = Right ()
      | otherwise = case [d | d <- pluginChannels plugin, channelName d == ciChannel c] of
          [] -> Left (BadOutput ("宣言していないチャネルです: " <> ciChannel c))
          (d : _)
            | channelOrder d == OrderReading && maybe True T.null (ciReading c) -> Left (BadOutput ("読みの順のチャネルの項目には読みが要ります: " <> ciChannel c))
            | any sends (ciBody c) -> Left (BadOutput "チャネルの項目の本文に置けない要素があります")
            | otherwise -> Right ()
    sends :: InlineF q -> Bool
    sends = \case
      Note {} -> True
      Sidenote {} -> True
      IndexMark {} -> True
      Cite {} -> True
      ChannelItem {} -> True
      Ruby _ _ segs -> any (any sends . rsBase) segs
      Kenten _ _ xs -> any sends xs
      Color _ _ xs -> any sends xs
      CharStyle _ _ xs -> any sends xs
      _ -> False

-- | The items of channels among inlines, with their spans.
inlineItems :: InlineF r -> [(SrcSpan, ChannelItem)]
inlineItems = \case
  ChannelItem s c -> [(s, c)]
  Ruby _ _ segs -> concat [concatMap inlineItems (rsBase g) | g <- segs]
  Kenten _ _ xs -> concatMap inlineItems xs
  Color _ _ xs -> concatMap inlineItems xs
  CharStyle _ _ xs -> concatMap inlineItems xs
  Note _ _ xs -> concatMap inlineItems xs
  Sidenote _ _ xs -> concatMap inlineItems xs
  _ -> []

documentItems :: Document -> [(SrcSpan, ChannelItem)]
documentItems doc = concat [concatMap inlineItems (blockInlines b) | b <- blocksOf doc]

inlineSpans :: InlineF r -> [SrcSpan]
inlineSpans = \case
  Text s _ -> [s]
  Ruby s _ segs -> s : concat [concatMap inlineSpans (rsBase g) | g <- segs]
  Kenten s _ xs -> s : concatMap inlineSpans xs
  Color s _ xs -> s : concatMap inlineSpans xs
  CharStyle s _ xs -> s : concatMap inlineSpans xs
  Tcy s _ -> [s]
  Number s _ _ -> [s]
  Ref s _ _ -> [s]
  Deferred s _ -> [s]
  Note s _ xs -> s : concatMap inlineSpans xs
  Sidenote s _ xs -> s : concatMap inlineSpans xs
  IndexMark s _ -> [s]
  Cite s _ -> [s]
  ProofComment s _ -> [s]
  LineBreak s -> [s]
  Aki s _ -> [s]
  ChannelItem s c -> s : concatMap inlineSpans (ciBody c)

inlineDeferred :: InlineF r -> [DeferredExpr]
inlineDeferred = \case
  Deferred _ d -> [d]
  Ruby _ _ segs -> concat [concatMap inlineDeferred (rsBase g) | g <- segs]
  Kenten _ _ xs -> concatMap inlineDeferred xs
  Color _ _ xs -> concatMap inlineDeferred xs
  CharStyle _ _ xs -> concatMap inlineDeferred xs
  Note _ _ xs -> concatMap inlineDeferred xs
  Sidenote _ _ xs -> concatMap inlineDeferred xs
  ChannelItem _ c -> concatMap inlineDeferred (ciBody c)
  _ -> []

blocksOf :: Document -> [Block]
blocksOf (Document _ bs) = concatMap go bs
  where
    go b =
      b : case blockBody b of
        BulletList items -> concatMap (concatMap go . itemBlocks) items
        OrderedList items -> concatMap (concatMap go . itemBlocks) items
        DefList gs -> concatMap (concatMap (concatMap go) . dgDefs) gs
        FigureBlock f -> concatMap go (figCaption f)
        _ -> []

blockInlines :: Block -> [Inline]
blockInlines b = case blockBody b of
  Paragraph _ is -> is
  Heading _ _ is -> is
  DefList gs -> concat (concatMap dgTerms gs)
  Table _ h rows -> concat h <> concat (concat rows)
  _ -> []

documentSpans :: Document -> [SrcSpan]
documentSpans doc = concat [blockSpan b : concatMap inlineSpans (blockInlines b) | b <- blocksOf doc]

documentDeferred :: Document -> [DeferredExpr]
documentDeferred doc = concat [concatMap inlineDeferred (blockInlines b) | b <- blocksOf doc]
