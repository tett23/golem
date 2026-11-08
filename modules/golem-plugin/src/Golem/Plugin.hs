{-# LANGUAGE CApiFFI #-}

{- | Plugins as wasm modules run by wasmtime 49.0.5 (golem-plugin ADR 0001).
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
    pluginDataNames,
    pluginBlocks,
    takesData,
    withPluginData,
    HostContext (..),
    contextNames,
    pluginContextNames,
    withPluginContext,
    maxDataBytes,
    PluginError (..),
    abiVersion,
    defaultFuel,
    fuelPerDocumentByte,
    filterFuel,
    defaultMemoryLimit,
    watToWasm,
    loadPlugin,
    loadPluginWith,
    invokeRaw,
    commandRequest,
    blockCommandRequest,
    valueTerm,
    termValue,
    filterRequest,
    callCommand,
    callBlockCommand,
    applyFilter,
    applyFilterFuel,
    describePluginError,
    DataDiagnostic (..),
    pluginChecksData,
    checkDataRequest,
    checkData,
    pluginCodeForm,
  )
where

import Codec.CBOR.Encoding (Encoding, encodeBytes, encodeListLen, encodePreEncoded, encodeString)
import Codec.CBOR.Read (deserialiseFromBytes)
import Codec.CBOR.Term (Term (..), decodeTerm, encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.ByteString.Unsafe qualified as BU
import Data.Char (isAsciiLower, isDigit)
import Data.List (sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Foreign
import Foreign.C.String (CString, peekCString, withCString, withCStringLen)
import Foreign.C.Types
import Golem.Doc.Cbor
import Golem.Doc.IR hiding (abiVersion)
import Golem.Doc.Validate (captionErrors, langErrors, linkErrors, validateBlocks, validateDocument)
import Golem.Eval.Builtin (builtinBlockCommands)
import Golem.Eval.Value (PluginArg (..), Value (..))
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Numeric.Natural (Natural)
import System.Environment (lookupEnv)
import System.IO (hPutStrLn, stderr)
import System.IO.Unsafe (unsafePerformIO)

data CPlugin

foreign import capi unsafe "golem_plugin.h golem_plugin_load" c_load :: Ptr Word8 -> CSize -> Ptr CString -> IO (Ptr CPlugin)

foreign import capi unsafe "golem_plugin.h &golem_plugin_free" c_free :: FunPtr (Ptr CPlugin -> IO ())

foreign import capi unsafe "golem_plugin.h golem_plugin_import_count" c_importCount :: Ptr CPlugin -> IO CInt

foreign import capi unsafe "golem_plugin.h golem_plugin_import_name" c_importName :: Ptr CPlugin -> CInt -> IO CString

foreign import capi unsafe "golem_plugin.h golem_plugin_has_export" c_hasExport :: Ptr CPlugin -> CString -> IO CInt

foreign import capi safe "golem_plugin.h golem_plugin_call"
  c_call :: Ptr CPlugin -> CInt -> Word64 -> Int64 -> Ptr Word8 -> CSize -> Ptr (Ptr Word8) -> Ptr CSize -> Ptr Word32 -> Ptr Word64 -> Ptr CString -> IO CInt

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

{- | The fuel a filter gets for each byte of the CBOR of its document, over
the fuel of a command (docs/adr/0124): about three times the most two
ruby filters used on the fixtures.
-}
fuelPerDocumentByte :: Word64
fuelPerDocumentByte = 10000

{- | The limit on the instructions of one call of a filter (docs/adr/0124):
the limit of a command and 'fuelPerDocumentByte' for each byte of the
CBOR of the document, the data not counted.
-}
filterFuel :: Word64 -> Int -> Word64
filterFuel base documentBytes = base + fuelPerDocumentByte * fromIntegral documentBytes

{- | The most bytes of the data of one plugin, all its files together
(docs/adr/0105): a quarter of the memory of an instance, which holds the
request and what the plugin makes of it.
-}
maxDataBytes :: Int64
maxDataBytes = 64 * 1024 * 1024

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
    pluginChannels :: ![ChannelDecl],
    -- | the names of the data it takes (docs/adr/0105)
    pluginDataNames :: ![Text],
    -- | the block commands it provides (docs/adr/0122)
    pluginBlocks :: ![Text],
    -- | the data the project passes, as the CBOR of the last element of a request
    plData :: !ByteString,
    -- | whether it exports golem_check_data (docs/adr/0120)
    pluginChecksData :: !Bool,
    -- | the names of the context of the book it asks for (docs/adr/0121)
    pluginContextNames :: ![Text],
    -- | the context, as the CBOR of the element of a request before the data
    plContext :: !ByteString
  }

{- | The context of the book a plugin may ask for (docs/adr/0121): the
writing mode of [page] in style.toml (horizontal or vertical) and the
vertical notation of numbers of [numbers] (kanji, kanji-digits, tcy,
auto or auto-digits). The list is closed; a name is added with the ABI.
-}
data HostContext = HostContext
  { hcWritingMode :: !Text,
    hcVerticalNumbers :: !Text
  }
  deriving stock (Eq, Show)

-- | The names a plugin may ask for, in code point order.
contextNames :: [Text]
contextNames = ["vertical-numbers", "writing-mode"]

contextValue :: HostContext -> Text -> Text
contextValue c = \case
  "writing-mode" -> hcWritingMode c
  _ -> hcVerticalNumbers c

{- | The context of the book for the names the plugin asked for, and only
those: @[* [name, value]]@ in code point order of the names, encoded once
here. A plugin that asks for nothing gets the same requests in every
book (docs/adr/0121).
-}
withPluginContext :: HostContext -> Plugin -> Plugin
withPluginContext c p = p {plContext = toStrictByteString (encodeListLen (fromIntegral (length names)) <> foldMap entry names)}
  where
    names = sort (pluginContextNames p)
    entry n = encodeListLen 2 <> encodeString n <> encodeString (contextValue c n)

{- | Whether the plugin takes data of a name (docs/adr/0119): one of the
names it declares, or any well-formed name when it declares @*@.
-}
takesData :: Plugin -> Text -> Bool
takesData p n
  | pluginDataNames p == ["*"] = dataName n
  | otherwise = n `elem` pluginDataNames p

{- | A name of data: a lowercase ASCII letter, then lowercase letters,
digits and - (docs/adr/0105).
-}
dataName :: Text -> Bool
dataName n = case T.uncons n of
  Just (h, rest) -> isAsciiLower h && T.all (\x -> isAsciiLower x || isDigit x || x == '-') rest
  Nothing -> False

{- | The data the project passes to the plugin (docs/adr/0105), by name.
Every request ends with it, @[* [name, bytes]]@ in the order of the
names; it is encoded here once, not at each call.
-}
withPluginData :: Map Text ByteString -> Plugin -> Plugin
withPluginData m p = p {plData = toStrictByteString (encodeListLen (fromIntegral (Map.size m)) <> foldMap entry (Map.toAscList m))}
  where
    entry (k, v) = encodeListLen 2 <> encodeString k <> encodeBytes v

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
  | -- | names of context the host does not have, in the order of the description (G06105, docs/adr/0121)
    UnknownContext [Text]
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
  UnknownContext ns -> "Golem が渡せない文脈を求めています: " <> T.intercalate "、" ns <> "（渡せる文脈: " <> T.intercalate "、" contextNames <> "）"

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
      checks <- withCString "golem_check_data" (c_hasExport p)
      let plugin = Plugin fp fuel memory [] [] [] [] [] noData (checks /= 0) [] noData
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
                    (cmds, filts, chans, names, ctx, blocks) <- decodeDescription bytes
                    Right plugin {pluginCommands = cmds, pluginFilters = filts, pluginChannels = chans, pluginDataNames = names, pluginContextNames = ctx, pluginBlocks = blocks}

-- | No data, no context: the empty array.
noData :: ByteString
noData = BS.singleton 0x80

callMode :: Plugin -> CInt -> ByteString -> IO (Either PluginError (ByteString, Word32))
callMode plugin mode input = fst <$> callModeWith (plFuel plugin) plugin mode input

{- | A call with a limit on its instructions, and the fuel it used, all of
it when it ran out (docs/adr/0124). With GOLEM_DEBUG_PLUGIN_FUEL a line
of the call goes to the standard error; the outputs do not change.
-}
callModeWith :: Word64 -> Plugin -> CInt -> ByteString -> IO (Either PluginError (ByteString, Word32), Word64)
callModeWith fuel plugin mode input = withForeignPtr (plPtr plugin) $ \p ->
  BU.unsafeUseAsCStringLen input $ \(inPtr, inLen) ->
    alloca $ \outPtr -> alloca $ \outLen -> alloca $ \u32 -> alloca $ \usedPtr -> do
      poke outPtr nullPtr
      poke u32 0
      poke usedPtr 0
      (status, msg) <- withMessage (c_call p mode fuel (plMemory plugin) (castPtr inPtr) (fromIntegral inLen) outPtr outLen u32 usedPtr)
      used <- peek usedPtr
      debugFuel <- isJust <$> lookupEnv "GOLEM_DEBUG_PLUGIN_FUEL"
      when debugFuel $
        hPutStrLn stderr ("golem-debug-fuel: mode=" <> show mode <> " request=" <> show inLen <> " fuel=" <> show fuel <> " used=" <> show used <> " status=" <> show status)
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
      pure . (,used) $ case status of
        0 -> Right (bytes, v)
        2 -> Left (OutOfFuel msg)
        3 -> Left (MissingExport msg)
        4 -> Left (BadOutput msg)
        -- the ABI's type of a result, checked by the host (docs/adr ADR 0035)
        6 -> Left (BadOutput (msg <> " の戻り値の型が不正です"))
        5 -> Left (InstantiateFailed msg)
        _ -> Left (Trapped msg)

-- | One call of @golem_invoke@ with raw CBOR, with the fuel of a command.
invokeRaw :: Plugin -> ByteString -> Either PluginError ByteString
invokeRaw plugin = fst . invokeRawFuel (plFuel plugin) plugin

{- | One call of @golem_invoke@ with a limit on the instructions, and the
fuel the call used (docs/adr/0124). The one unsafePerformIO of this
module (docs/adr ADR 0034): the evaluator, a pure function, calls it. It
is a function of the limit, the plugin and the input alone, since each
call gets a fresh store and instance, the plugin has no imports, and its
limits and the fuel used are counted in instructions and bytes, not in
time (ADR 0001). The line GOLEM_DEBUG_PLUGIN_FUEL writes to the standard
error changes no result.
-}
invokeRawFuel :: Word64 -> Plugin -> ByteString -> (Either PluginError ByteString, Word64)
invokeRawFuel fuel plugin input = let (r, used) = unsafePerformIO (callModeWith fuel plugin 2 input) in (fst <$> r, used)

decodeTermBytes :: ByteString -> Either PluginError Term
decodeTermBytes b = case deserialiseFromBytes decodeTerm (BL.fromStrict b) of
  Right (rest, t) | BL.null rest -> Right t
  Right _ -> Left (BadOutput "CBOR の後ろに余分なバイトがあります")
  Left e -> Left (BadOutput (T.pack (show e)))

{- | The commands, the filters, the channels (golem-doc ADR 0007) and the
names of the data (docs/adr/0105) of a description: a map from the names
of its fields to arrays, in any order (docs/adr/0107). A field left out
is empty; an unknown field, a field given twice, a key that is not a
text string and anything but a map of definite length are not a
description. A name of data is a lowercase ASCII letter, then lowercase
letters, digits and -, and is given once; or the data is * alone, any
name (docs/adr/0119). A name of the context (docs/adr/0121) is one of
'contextNames', given once; the others are 'UnknownContext', all of
them. A block command (docs/adr/0122) is a name of the form of a name of
data, given once, and not the name of a built-in block command.
-}
decodeDescription :: ByteString -> Either PluginError ([Text], [Text], [ChannelDecl], [Text], [Text], [Text])
decodeDescription b = do
  t <- decodeTermBytes b
  kvs <- case t of
    TMap kvs -> Right kvs
    _ -> Left (BadOutput "golem_describe の形が不正です")
  keys <- mapM key kvs
  case [k | k <- keys, k `notElem` fields] of
    (k : _) -> Left (BadOutput ("golem_describe に未知の欄があります: " <> k))
    [] -> Right ()
  case [k | (i, k) <- zip [0 :: Int ..] keys, k `elem` take i keys] of
    (k : _) -> Left (BadOutput ("golem_describe の欄が重複しています: " <> k))
    [] -> Right ()
  let field k = case [v | (k', v) <- zip keys (map snd kvs), k' == k] of
        [] -> Right []
        (TList xs : _) -> Right xs
        _ -> Left (BadOutput ("golem_describe の欄の形が不正です: " <> k))
  cs <- field "commands"
  fs <- field "filters"
  chs <- field "channels"
  ds <- field "data"
  xs <- field "context"
  bs <- field "blocks"
  (,,,,,) <$> mapM name cs <*> mapM name fs <*> mapM channel chs <*> (mapM name ds >>= dataNames) <*> (mapM name xs >>= contextOf) <*> (mapM name bs >>= blockNames)
  where
    fields = ["commands", "filters", "channels", "data", "context", "blocks"]
    blockNames ns = case [n | n <- ns, not (dataName n)] of
      (n : _) -> Left (BadOutput ("ブロックコマンドの名前が不正です: " <> n))
      [] -> case [n | (i, n) <- zip [0 :: Int ..] ns, n `elem` take i ns] of
        (n : _) -> Left (BadOutput ("ブロックコマンドの名前が重複しています: " <> n))
        [] -> case [n | n <- ns, n `elem` builtinBlockCommands] of
          (n : _) -> Left (BadOutput ("組み込みのブロックコマンドの名前です: " <> n))
          [] -> Right ns
    contextOf ns = case [n | (i, n) <- zip [0 :: Int ..] ns, n `elem` take i ns] of
      (n : _) -> Left (BadOutput ("文脈の名前が重複しています: " <> n))
      [] -> case filter (`notElem` contextNames) ns of
        [] -> Right ns
        unknown -> Left (UnknownContext unknown)
    key = \case
      (TString k, _) -> Right k
      _ -> Left (BadOutput "golem_describe の形が不正です")
    -- \* alone takes any name (docs/adr/0119); with another name it is a bad name
    dataNames ["*"] = Right ["*"]
    dataNames ns = case [n | n <- ns, not (dataName n)] of
      (n : _) -> Left (BadOutput ("データの名前が不正です: " <> n))
      [] -> case [n | (i, n) <- zip [0 :: Int ..] ns, n `elem` take i ns] of
        (n : _) -> Left (BadOutput ("データの名前が重複しています: " <> n))
        [] -> Right ns
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

{- | The CBOR of a command request (golem-doc.cddl @command-request@), with
the data of the plugin at the end (docs/adr/0105).
-}
commandRequest :: Plugin -> Text -> [PluginArg] -> [[Inline]] -> SrcSpan -> Either PluginError ByteString
commandRequest plugin name args slots sp = do
  argTerms <- mapM argumentTerm args
  pure (withData plugin [TInt 0, TString name, TList argTerms, TList (map inlinesTerm slots), spanT sp])

{- | The CBOR of the request of a block command (golem-doc.cddl
@block-command-request@, docs/adr/0122): its arguments, its body
evaluated, where it is called, the context and the data.
-}
blockCommandRequest :: Plugin -> Text -> [PluginArg] -> [Block] -> SrcSpan -> Either PluginError ByteString
blockCommandRequest plugin name args body sp = do
  argTerms <- mapM argumentTerm args
  pure (withData plugin [TInt 2, TString name, TList argTerms, blocksTerm body, spanT sp])

-- | golem-doc.cddl's argument: [0, value] / [1, key, value] (docs/adr/0110).
argumentTerm :: PluginArg -> Either PluginError Term
argumentTerm = \case
  PluginPositional v -> (\t -> TList [TInt 0, t]) <$> valueTerm v
  PluginKeyword k v -> (\t -> TList [TInt 1, TString k, t]) <$> valueTerm v

-- | The CBOR of a filter request (golem-doc.cddl @filter-request@), with the context and the data at the end.
filterRequest :: Plugin -> Text -> Document -> ByteString
filterRequest plugin name doc = filterRequestOf plugin name (toStrictByteString (encodeTerm (documentTerm doc)))

-- | The same with the CBOR of the document already encoded, which sets the fuel of the call (docs/adr/0124).
filterRequestOf :: Plugin -> Text -> ByteString -> ByteString
filterRequestOf plugin name docBytes =
  toStrictByteString (encodeListLen 5 <> encodeTerm (TInt 1) <> encodeTerm (TString name) <> encodePreEncoded docBytes <> encodePreEncoded (plContext plugin) <> encodePreEncoded (plData plugin) :: Encoding)

-- | An array of the terms, then the context and the data of the plugin, already encoded (docs/adr/0105, docs/adr/0121).
withData :: Plugin -> [Term] -> ByteString
withData plugin ts = toStrictByteString (encodeListLen (fromIntegral (length ts + 2)) <> foldMap encodeTerm ts <> encodePreEncoded (plContext plugin) <> encodePreEncoded (plData plugin) :: Encoding)

-- | The IR of an answer; a float without a finite value is G06100, not bad output.
decoded :: Either DecodeError a -> Either PluginError a
decoded = \case
  Right x -> Right x
  Left (FloatNotFinite v) -> Left (NonFiniteFloat v)
  Left e -> Left (BadOutput (describeDecodeError e))

-- | A command of the plugin. Returns the inlines and the plugin's diagnostics.
callCommand :: Plugin -> Text -> [PluginArg] -> [[Inline]] -> SrcSpan -> Either PluginError ([Inline], [Diagnostic])
callCommand plugin name args slots sp = do
  req <- commandRequest plugin name args slots sp
  out <- invokeRaw plugin req
  (outT, diags) <- response out
  inls <- decoded (termInlinesE outT)
  checkItems plugin [] (concatMap inlineItems inls)
  let allowedSpans = Set.insert sp (Set.fromList (concatMap (concatMap inlineSpans) slots))
      allowedDeferred = concatMap (concatMap inlineDeferred) slots
  checkOutput allowedSpans allowedDeferred (concatMap inlineSpans inls) (concatMap inlineDeferred inls)
  checkDiagnosticSpans allowedSpans diags
  -- the links it makes pass the checks of [link] (docs/adr ADR 0182), its language spans those of [lang] (docs/adr ADR 0187)
  case linkErrors inls <> langErrors inls of
    [] -> Right (inls, diags)
    errs -> Left (BadOutput (T.intercalate "、" errs))

{- | A block command of the plugin (docs/adr/0122). Returns the blocks, the
images of its figures by the source the host gives them (docs/adr/0123)
and the plugin's diagnostics. A block of the body passes as it came; any
other block is a paragraph, a list, a definition list, a table or a code
block, without a label, and holds only blocks of those kinds; its spans
are the call's or those of the body, and the IR holds as below the top of
a document.
-}
callBlockCommand :: Plugin -> Text -> [PluginArg] -> [Block] -> SrcSpan -> Either PluginError ([Block], Map Text ByteString, [Diagnostic])
callBlockCommand plugin name args body sp = do
  req <- blockCommandRequest plugin name args body sp
  out <- invokeRaw plugin req
  (outT, diags) <- response out
  -- [blocks, images] (docs/adr/0123)
  (blocksT, imagesT) <- case outT of
    TList [b, TList is] -> Right (b, is)
    _ -> Left (BadOutput "ブロックコマンドの出力は [ブロックの列, 画像の列] です")
  bs0 <- decoded (termBlocksE blocksT)
  images <- mapM image imagesT
  -- a caption holds paragraphs only, so a figure in it is that error, not one of its image (docs/adr/0144)
  case concat [captionErrors f | Block _ _ _ (FigureBlock f) <- bs0] of
    e : _ -> Left (BadOutput e)
    [] -> Right ()
  (bs, used) <- placeImages body images bs0
  let made = filter (`notElem` body) bs
      bodyDoc = Document (FileId 0) body
      madeDoc = Document (FileId 0) made
      allowedSpans = Set.insert sp (Set.fromList (documentSpans bodyDoc))
  mapM_ blockKind made
  checkItems plugin (documentItems bodyDoc) (documentItems madeDoc)
  checkOutput allowedSpans (documentDeferred bodyDoc) (documentSpans madeDoc) (documentDeferred madeDoc)
  checkDiagnosticSpans allowedSpans diags
  case validateBlocks (const (Just maxBound)) (documentDeferred bodyDoc) made of
    [] -> Right (bs, used, diags)
    errs -> Left (BadOutput (T.intercalate "、" errs))
  where
    image = \case
      TList [TString n, TString f, TBytes b] -> Right (n, f, b)
      _ -> Left (BadOutput "画像の形が不正です")

{- | The images of the figures a block command returns (docs/adr/0123):
each named once with a name of the form of a name of data, of SVG, PNG or
JPEG, used, and at most 'maxDataBytes' together. A figure of its own
stands at the top of the output, without a web image, and points at an
image as plugin:<name>; its source becomes the one the host names the
image by, the SHA-256 of the bytes. The figures of the body pass as they
came.
-}
placeImages :: [Block] -> [(Text, Text, ByteString)] -> [Block] -> Either PluginError ([Block], Map Text ByteString)
placeImages body images bs = do
  case [n | (n, _, _) <- images, not (dataName n)] of
    (n : _) -> Left (BadOutput ("画像の名前が不正です: " <> n))
    [] -> Right ()
  case [n | (i, (n, _, _)) <- zip [0 :: Int ..] images, n `elem` [m | (m, _, _) <- take i images]] of
    (n : _) -> Left (BadOutput ("画像の名前が重複しています: " <> n))
    [] -> Right ()
  named <- mapM source images
  if sum [BS.length b | (_, _, b) <- images] > fromIntegral maxDataBytes
    then Left (BadOutput ("画像の大きさの合計が上限（" <> T.pack (show maxDataBytes) <> " バイト）を超えています"))
    else Right ()
  mapM_ nested bs
  bs' <- mapM (place named) bs
  let usedNames = [n | b@(Block _ _ _ (FigureBlock f)) <- bs, b `notElem` body, Just n <- [T.stripPrefix "plugin:" (figSource f)]]
  case [n | (n, _, _) <- images, n `notElem` usedNames] of
    (n : _) -> Left (BadOutput ("どの図版も使っていない画像があります: " <> n))
    [] -> Right ()
  Right (bs', Map.fromList [(p, b) | (n, (p, b)) <- named, n `elem` usedNames])
  where
    source (n, f, b) = case lookup f [("svg", ".svg"), ("png", ".png"), ("jpeg", ".jpg")] of
      Just ext -> Right (n, (pluginImagePrefix <> hexOf (sha256 b) <> ext, b))
      Nothing -> Left (BadOutput ("画像の形式は svg、png、jpeg のどれかです: " <> f))
    hexOf = T.pack . concatMap (\w -> [hexDigit (w `div` 16), hexDigit (w `mod` 16)]) . BS.unpack
    hexDigit w = "0123456789abcdef" !! fromIntegral w
    place named b@(Block bsp lbl lang (FigureBlock f))
      | b `elem` body = Right b
      | Just _ <- figWeb f = Left (BadOutput "プラグインの図版は web を持てません")
      | Just n <- T.stripPrefix "plugin:" (figSource f) = case lookup n named of
          Just (p, _) -> Right (Block bsp lbl lang (FigureBlock f {figSource = p}))
          Nothing -> Left (BadOutput ("応答にない画像です: " <> figSource f))
      | otherwise = Left (BadOutput ("プラグインの図版は plugin:<名前> で画像を指します: " <> figSource f))
    place _ b = Right b
    -- a figure of its own below the top of the output
    nested (Block _ _ _ b) = mapM_ deep (inner b)
    deep blk@(Block _ _ _ b) = case b of
      FigureBlock _ | blk `notElem` body -> Left (BadOutput "図版は出力の最上位にだけ置けます")
      _ -> mapM_ deep (inner b)
    inner = \case
      BulletList items -> concatMap itemBlocks items
      OrderedList items -> concatMap itemBlocks items
      DefList gs -> concat (concatMap dgDefs gs)
      _ -> []

{- | The kinds of blocks a block command makes, at any depth, and no label
(docs/adr/0122).
-}
blockKind :: Block -> Either PluginError ()
blockKind (Block _ lbl _ body)
  | Just _ <- lbl = Left (BadOutput "ブロックコマンドの出力はラベルを持てません")
  | otherwise = case body of
      Paragraph _ _ -> Right ()
      Table {} -> Right ()
      CodeBlock _ -> Right ()
      BulletList items -> mapM_ (mapM_ blockKind . itemBlocks) items
      OrderedList items -> mapM_ (mapM_ blockKind . itemBlocks) items
      DefList gs -> mapM_ (mapM_ (mapM_ blockKind) . dgDefs) gs
      Heading {} -> refuse "見出し"
      -- its image is checked by placeImages (docs/adr/0123), its caption of paragraphs by validateBlocks (docs/adr/0144)
      FigureBlock _ -> Right ()
      ChannelOutput _ -> refuse "一覧の出力"
      ForcedBreak _ -> refuse "改ページ"
      PageControl _ -> refuse "改ページの制御"
      BlankLines _ -> refuse "行アキ"
  where
    refuse k = Left (BadOutput ("ブロックコマンドが返せないブロックです: " <> k))

-- | A filter of the plugin over one file's document.
applyFilter :: Plugin -> Text -> Document -> Either PluginError (Document, [Diagnostic])
applyFilter plugin name doc = fst (applyFilterFuel plugin name doc)

{- | 'applyFilter', and the fuel the call used (docs/adr/0124). The limit
is 'filterFuel' of the CBOR of the document.
-}
applyFilterFuel :: Plugin -> Text -> Document -> (Either PluginError (Document, [Diagnostic]), Word64)
applyFilterFuel plugin name doc =
  let docBytes = toStrictByteString (encodeTerm (documentTerm doc))
      fuel = filterFuel (plFuel plugin) (BS.length docBytes)
      (out, used) = invokeRawFuel fuel plugin (filterRequestOf plugin name docBytes)
   in (out >>= filtered plugin doc, used)

-- | The answer of a filter over the document: checked as below.
filtered :: Plugin -> Document -> ByteString -> Either PluginError (Document, [Diagnostic])
filtered plugin doc out = do
  (outT, diags) <- response out
  doc' <- decoded (termDocumentE outT)
  -- the items that came in with the document pass as they are (golem-doc ADR 0007)
  checkItems plugin (documentItems doc) (documentItems doc')
  checkOutput (Set.fromList (documentSpans doc)) (documentDeferred doc) (documentSpans doc') (documentDeferred doc')
  -- a filter has no call: the top of the file stands for what no node holds, such as its data (docs/adr/0108)
  checkDiagnosticSpans (Set.insert (mkSpan (docFile doc) 0 0) (Set.fromList (documentSpans doc))) diags
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
        -- the host puts the name of the plugin before it (docs/adr/0108)
        pluginCode code
        sp <- decoded (termSpan spT)
        severity <- pluginSeverity sev
        Right (diagnostic code severity sp msg)
      _ -> Left (BadOutput "診断の形が不正です")

{- | The diagnostics of a plugin point at what came in with the request
(docs/adr/0108).
-}
checkDiagnosticSpans :: Set.Set SrcSpan -> [Diagnostic] -> Either PluginError ()
checkDiagnosticSpans allowed ds
  | any ((`Set.notMember` allowed) . diagSpan) ds = Left (BadOutput "診断が要求にないソース位置を指しています")
  | otherwise = Right ()

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
      Link _ _ xs -> any sends xs
      Lang _ _ xs -> any sends xs
      Resolved _ _ _ xs -> any sends xs
      _ -> False

-- | The items of channels among inlines, with their spans.
inlineItems :: InlineF r -> [(SrcSpan, ChannelItem)]
inlineItems = \case
  ChannelItem s c -> [(s, c)]
  Ruby _ _ segs -> concat [concatMap inlineItems (rsBase g) | g <- segs]
  Kenten _ _ xs -> concatMap inlineItems xs
  Color _ _ xs -> concatMap inlineItems xs
  CharStyle _ _ xs -> concatMap inlineItems xs
  Link _ _ xs -> concatMap inlineItems xs
  Lang _ _ xs -> concatMap inlineItems xs
  Resolved _ _ _ xs -> concatMap inlineItems xs
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
  Link s _ xs -> s : concatMap inlineSpans xs
  Lang s _ xs -> s : concatMap inlineSpans xs
  Resolved s _ _ xs -> s : concatMap inlineSpans xs

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
  Link _ _ xs -> concatMap inlineDeferred xs
  Lang _ _ xs -> concatMap inlineDeferred xs
  Resolved _ _ _ xs -> concatMap inlineDeferred xs
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

{- | The form of a code of a plugin's diagnostic, the part after the name
of the plugin: a lowercase letter, then lowercase letters, digits and -
(docs/adr/0139). golem explain judges the codes it is given by it
(docs/adr/0151).
-}
pluginCodeForm :: Text -> Bool
pluginCodeForm = dataName

{- | A code of a plugin's diagnostic, of the form of 'pluginCodeForm'.
The host puts the name of the plugin before it (docs/adr/0108).
-}
pluginCode :: Text -> Either PluginError ()
pluginCode code
  | pluginCodeForm code = Right ()
  | otherwise = Left (BadOutput ("診断のコードの形が不正です: " <> code))

-- | The severity of a plugin's diagnostic: 0 an error, 1 a warning.
pluginSeverity :: Term -> Either PluginError Severity
pluginSeverity = \case
  TInt 0 -> Right Error
  TInt 1 -> Right Warning
  _ -> Left (BadOutput "診断の重大度が不正です")

{- | A diagnostic of the data of a plugin (golem-doc.cddl @data-diagnostic@,
docs/adr/0120): the code, the severity, the name of the data and the line,
from 1, or none for the whole file. The host makes it a diagnostic at the
start of that line of the file of the data. No name is a diagnostic of
all the data the plugin was given, such as data it needs and was not
given, and has no line (docs/adr/0136).
-}
data DataDiagnostic = DataDiagnostic
  { ddCode :: !Text,
    ddSeverity :: !Severity,
    ddName :: !(Maybe Text),
    ddLine :: !(Maybe Natural),
    ddMessage :: !Text
  }
  deriving stock (Eq, Show)

-- | The request of golem_check_data: @[data]@ (docs/adr/0120).
checkDataRequest :: Plugin -> ByteString
checkDataRequest p = BS.cons 0x81 (plData p)

{- | The check of the data of a plugin, called once after the data is
read (docs/adr/0120): the diagnostics of golem_check_data, or none for a
plugin without the export. The name and the line are checked by the
host, which knows the files.
-}
checkData :: Plugin -> IO (Either PluginError [DataDiagnostic])
checkData p
  | not (pluginChecksData p) = pure (Right [])
  | otherwise = do
      out <- callMode p 3 (checkDataRequest p)
      pure (out >>= decodeTermBytes . fst >>= diags)
  where
    diags = \case
      TList ds -> mapM one ds
      _ -> Left (BadOutput "データの検査の応答の形が不正です")
    one = \case
      TList [TString code, sev, nameT, lineT, TString msg] -> do
        pluginCode code
        severity <- pluginSeverity sev
        name <- case nameT of
          TString n -> Right (Just n)
          TNull -> Right Nothing
          _ -> Left (BadOutput "データの診断の形が不正です")
        line <- case lineT of
          TNull -> Right Nothing
          TInt n | n >= 1 -> Right (Just (fromIntegral n))
          _ -> Left (BadOutput "データの診断の行が不正です")
        -- no name is no file, so no line to count (docs/adr/0136)
        case (name, line) of
          (Nothing, Just _) -> Left (BadOutput "データの名前のない診断に行があります")
          _ -> Right (DataDiagnostic code severity name line msg)
      _ -> Left (BadOutput "データの診断の形が不正です")
