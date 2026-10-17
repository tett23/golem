{-# LANGUAGE CApiFFI #-}

{- | Plugins as wasm modules run by wasmtime 49.0.2 (golem-plugin ADR 0001).
No imports, no WASI, no threads, canonical NaNs, no relaxed SIMD, fuel
and memory limits, a fresh instance per call. Requests and responses
are CBOR (golem-doc.cddl); every response is validated.
-}
module Golem.Plugin
  ( Plugin,
    pluginCommands,
    pluginFilters,
    PluginError (..),
    abiVersion,
    defaultFuel,
    defaultMemoryLimit,
    watToWasm,
    loadPlugin,
    loadPluginWith,
    invokeRaw,
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

-- | The ABI version of this host.
abiVersion :: Word32
abiVersion = 6

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
    pluginFilters :: ![Text]
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
  deriving stock (Eq, Show)

describePluginError :: PluginError -> Text
describePluginError = \case
  CompileFailed m -> "プラグインを読み込めません: " <> m
  HasImports is -> "プラグインが import を要求しています: " <> T.intercalate ", " is
  AbiMismatch v -> "プラグインの ABI の版が異なります: " <> T.pack (show v)
  MissingExport n -> "プラグインが関数を公開していません: " <> n
  OutOfFuel _ -> "プラグインの実行が命令数の上限を超えました"
  Trapped m -> "プラグインの実行が失敗しました（メモリの上限を超えた場合を含む）: " <> m
  InstantiateFailed m -> "プラグインを起動できません: " <> m
  BadOutput m -> "プラグインの出力が不正です: " <> m

withMessage :: (Ptr CString -> IO a) -> IO (a, Text)
withMessage k = alloca $ \errPtr -> do
  poke errPtr nullPtr
  r <- k errPtr
  e <- peek errPtr
  msg <- if e == nullPtr then pure "" else T.pack <$> peekCString e <* c_freeBytes e
  pure (r, msg)

-- | The text format to the binary format (for test plugins written in wat).
watToWasm :: Text -> Either Text ByteString
watToWasm wat = unsafePerformIO $
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

loadPlugin :: ByteString -> Either PluginError Plugin
loadPlugin = loadPluginWith defaultFuel defaultMemoryLimit

{- | Compiles a module and checks it: no imports, the ABI version, the
description of its commands and filters.
-}
loadPluginWith :: Word64 -> Int64 -> ByteString -> Either PluginError Plugin
loadPluginWith fuel memory wasm = unsafePerformIO $ do
  (p, msg) <- BU.unsafeUseAsCStringLen wasm $ \(ptr, len) -> withMessage (c_load (castPtr ptr) (fromIntegral len))
  if p == nullPtr
    then pure (Left (CompileFailed msg))
    else do
      fp <- newForeignPtr c_free p
      n <- c_importCount p
      names <- mapM (\i -> c_importName p i >>= \c -> T.pack <$> peekCString c <* c_freeBytes c) [0 .. n - 1]
      let plugin = Plugin fp fuel memory [] []
      pure $
        if not (null names)
          then Left (HasImports names)
          else do
            (_, v) <- callMode plugin 0 BS.empty
            if v /= abiVersion
              then Left (AbiMismatch v)
              else do
                (bytes, _) <- callMode plugin 1 BS.empty
                (cmds, filts) <- decodeDescription bytes
                Right plugin {pluginCommands = cmds, pluginFilters = filts}

callMode :: Plugin -> CInt -> ByteString -> Either PluginError (ByteString, Word32)
callMode plugin mode input = unsafePerformIO $ withForeignPtr (plPtr plugin) $ \p ->
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

-- | One call of @golem_invoke@ with raw CBOR.
invokeRaw :: Plugin -> ByteString -> Either PluginError ByteString
invokeRaw plugin input = fst <$> callMode plugin 2 input

decodeTermBytes :: ByteString -> Either PluginError Term
decodeTermBytes b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
  Right (rest, t) | BL.null rest -> Right t
  Right _ -> Left (BadOutput "CBOR の後ろに余分なバイトがあります")
  Left e -> Left (BadOutput (T.pack (show e)))

decodeDescription :: ByteString -> Either PluginError ([Text], [Text])
decodeDescription b = do
  t <- decodeTermBytes b
  case t of
    TList [TList cs, TList fs] -> (,) <$> mapM name cs <*> mapM name fs
    _ -> Left (BadOutput "golem_describe の形が不正です")
  where
    name = \case
      TString s -> Right s
      _ -> Left (BadOutput "名前が文字列ではありません")

valueTerm :: Value -> Either PluginError Term
valueTerm = \case
  VInt i -> Right (TInteger i)
  VFloat d -> Right (floatTerm d)
  VString s -> Right (TString s)
  VBool b -> Right (TBool b)
  VNil -> Right TNull
  VArray vs -> TList <$> mapM valueTerm vs
  VHash _ -> Left (BadOutput "ハッシュはプラグインに渡せません")

-- | A command of the plugin. Returns the inlines and the plugin's diagnostics.
callCommand :: Plugin -> Text -> [Value] -> [[Inline]] -> SrcSpan -> Either PluginError ([Inline], [Diagnostic])
callCommand plugin name args slots sp = do
  argTerms <- mapM valueTerm args
  let req = TList [TInt 0, TString name, TList [TList [TInt 0, a] | a <- argTerms], TList (map inlinesTerm slots), spanT sp]
  out <- invokeRaw plugin (toStrictByteString (encodeTerm req))
  (outT, diags) <- response out
  inls <- either (Left . BadOutput) Right (termInlines outT)
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
  doc' <- either (Left . BadOutput) Right (termDocument outT)
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
        sp <- either (Left . BadOutput) Right (termSpan spT)
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

inlineDeferred :: InlineF r -> [DeferredExpr]
inlineDeferred = \case
  Deferred _ d -> [d]
  Ruby _ _ segs -> concat [concatMap inlineDeferred (rsBase g) | g <- segs]
  Kenten _ _ xs -> concatMap inlineDeferred xs
  Color _ _ xs -> concatMap inlineDeferred xs
  CharStyle _ _ xs -> concatMap inlineDeferred xs
  Note _ _ xs -> concatMap inlineDeferred xs
  Sidenote _ _ xs -> concatMap inlineDeferred xs
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
