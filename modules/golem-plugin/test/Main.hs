module Main (main) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import ConcurrencySpec (concurrencyTests)
import Control.Concurrent.Async
  ( async,
    cancel,
    mapConcurrently,
  )
import Control.Exception (finally)
import Control.Monad (forM_, void)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Default (def)
import Data.Either (isLeft)
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (ChannelDecl (..))
import Golem.Doc.Cbor (documentTerm, inlinesTerm)
import Golem.Doc.IR
import Golem.Eval.Value (Value (..))
import Golem.Parser.AST qualified as A
import Golem.Plugin
import Golem.Plugin.Lock
import Golem.Syntax
import Golem.TestSupport.ExternalTool (needsTool)
import Network.Connection (TLSSettings (..))
import Network.HTTP.Client (newManager)
import Network.HTTP.Client.TLS (mkManagerSettings)
import Network.HTTP.Types qualified as H
import Network.Socket
import Network.Wai qualified as W
import Network.Wai.Handler.Warp qualified as Warp
import Network.Wai.Handler.WarpTLS qualified as WT
import ResponseSpec (responseTests)
import System.Directory
  ( doesFileExist,
    findExecutable,
    listDirectory,
  )
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Printf (printf)

main :: IO ()
main = defaultMain (testGroup "golem-plugin" [tests, lockTests, httpsTests, rootCertTests, responseTests, concurrencyTests])

callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

wat :: FilePath -> IO Text
wat name = TIO.readFile ("test/plugins/" <> name)

compile :: Text -> IO ByteString
compile src = watToWasm src >>= either (assertFailure . T.unpack) pure

escape :: ByteString -> Text
escape = T.pack . concatMap (printf "\\%02x") . BS.unpack

cbor :: Term -> ByteString
cbor = toStrictByteString . encodeTerm

-- | The ABI version of the host, as the fixed-response plugin's argument.
abi :: Int
abi = fromIntegral Golem.Plugin.abiVersion

-- | The fixed-response plugin with a response and an ABI version.
fixed :: Int -> ByteString -> IO ByteString
fixed = fixedFrom "fixed.wat"

-- | A fixed-response plugin of a file with a response and an ABI version.
fixedFrom :: FilePath -> Int -> ByteString -> IO ByteString
fixedFrom file ver response = do
  src <- wat file
  let describe = cbor (TList [TList [TString "shout"], TList [TString "upper"], TList []])
      filled =
        T.replace "{{ABI}}" (T.pack (show ver))
          . T.replace "{{DESCRIBE}}" (escape describe)
          . T.replace "{{DESCRIBE_LEN}}" (T.pack (show (BS.length describe)))
          . T.replace "{{RESPONSE}}" (escape response)
          . T.replace "{{RESPONSE_LEN}}" (T.pack (show (BS.length response)))
          $ src
  compile filled

load :: ByteString -> IO Plugin
load wasm = loadPlugin wasm >>= either (assertFailure . show) pure

-- | A response whose output is the given inlines.
responseWith :: Term -> ByteString
responseWith out = cbor (TList [out, TList []])

shout :: Plugin -> Either PluginError ([Inline], [Diagnostic])
shout p = callCommand p "shout" [VString "x"] [[Text callSpan "slot"]] callSpan

-- | Replaces the first occurrence of a subterm.
replaceTerm :: Term -> Term -> Term -> Term
replaceTerm from to t
  | t == from = to
  | otherwise = case t of
      TList xs -> TList (go xs)
      other -> other
  where
    go [] = []
    go (x : xs) =
      let x' = replaceTerm from to x
       in if x' /= x then x' : xs else x : go xs

tests :: TestTree
tests =
  testGroup
    "golem-plugin (ADR 0001)"
    [ testCase "a valid plugin describes itself and answers" $ do
        p <- load =<< fixed abi (responseWith (inlinesTerm [Text callSpan "SLOT"]))
        (pluginCommands p, pluginFilters p) @?= (["shout"], ["upper"])
        fmap fst (shout p) @?= Right [Text callSpan "SLOT"],
      -- golem-doc ADR 0007
      testCase "channels.wat declares two channels and sends the slot to them" $ do
        p <- load =<< compile =<< wat "channels.wat"
        map channelName (pluginChannels p) @?= ["glossary", "people"]
        let slot = [Text callSpan "語"]
            itemOf c k r = ChannelItem callSpan (ChannelItemData c k r slot)
        fmap fst (callCommand p "term" [VString "k", VString "よみ"] [slot] callSpan) @?= Right (slot <> [itemOf "glossary" (Just "k") (Just "よみ")])
        fmap fst (callCommand p "person" [VString "甲"] [slot] callSpan) @?= Right (slot <> [itemOf "people" (Just "甲") Nothing])
        fmap fst (callCommand p "person" [] [slot] callSpan) @?= Right (slot <> [itemOf "people" Nothing Nothing]),
      -- docs/adr ADR 0031
      testCase "a plugin without golem_dealloc loads and answers" $ do
        p <- load =<< fixedFrom "no-dealloc.wat" abi (responseWith (inlinesTerm [Text callSpan "SLOT"]))
        fmap fst (shout p) @?= Right [Text callSpan "SLOT"],
      testCase "a module that asks for imports is rejected when loading" $ do
        w <- compile =<< wat "imports.wat"
        loadPlugin w >>= (@?= Left (HasImports ["env.now"])) . void,
      testCase "a different ABI version is rejected when loading" $ do
        w <- fixed 1 (responseWith (TList []))
        loadPlugin w >>= (@?= Left (AbiMismatch 1)) . void,
      testCase "a plugin of ABI version 2 is rejected (docs/adr ADR 0005)" $ do
        w <- fixed 2 (responseWith (TList []))
        loadPlugin w >>= (@?= Left (AbiMismatch 2)) . void,
      testCase "the ABI version is 7 and a plugin of version 6 is rejected (golem-pdf ADR 0008)" $ do
        (Golem.Plugin.abiVersion, Golem.Doc.IR.abiVersion) @?= (7, 7)
        w <- fixed 6 (responseWith (TList []))
        loadPlugin w >>= (@?= Left (AbiMismatch 6)) . void,
      testCase "a code block survives a filter unchanged (golem-driver ADR 0023)" $ do
        p <- load =<< compile =<< wat "identity.wat"
        let code = Code (Just "haskell") (Just True) (Just "a.hs") (Just [Text callSpan "c"]) True [CodeLine "a" (Just 1) (Just DiffAdded) True [1], CodeLine "b" Nothing (Just DiffRemoved) False []]
            doc = Document (FileId 1) [Block callSpan (Just "l") (CodeBlock code)]
        fmap fst (applyFilter p "same" doc) @?= Right doc,
      testCase "a paragraph with aki survives a filter unchanged (docs/adr ADR 0019)" $ do
        p <- load =<< compile =<< wat "identity.wat"
        let doc = Document (FileId 1) [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a", Aki callSpan (AkiZw (1 / 5)), Aki callSpan (AkiAbs 65536)])]
        fmap fst (applyFilter p "same" doc) @?= Right doc,
      testCase "a document with forced breaks survives a filter unchanged (docs/adr ADR 0017)" $ do
        p <- load =<< compile =<< wat "identity.wat"
        let blk k = Block callSpan Nothing (ForcedBreak k)
            doc = Document (FileId 1) ([blk k | k <- [minBound .. maxBound]] <> [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])])
        fmap fst (applyFilter p "same" doc) @?= Right doc,
      testCase "a document with page controls survives a filter unchanged (docs/adr ADR 0030)" $ do
        p <- load =<< compile =<< wat "identity.wat"
        let doc = Document (FileId 1) ([Block callSpan Nothing (PageControl c) | c <- [NoBreak, NeedLines 3, AdjustLines (-1)]] <> [Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])])
        fmap fst (applyFilter p "same" doc) @?= Right doc,
      testCase "a filter that puts a page control below the top gives bad output (docs/adr ADR 0030)" $ do
        let para = Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])
            nested = Document (FileId 1) [Block callSpan Nothing (BulletList [ListItem Nothing [Block callSpan Nothing (PageControl NoBreak)]])]
        p <- load =<< fixed abi (responseWith (documentTerm nested))
        case applyFilter p "upper" (Document (FileId 1) [para]) of
          Left (BadOutput _) -> pure ()
          other -> assertFailure (show other),
      testCase "a filter that puts a forced break below the top gives bad output (docs/adr ADR 0017)" $ do
        let para = Block callSpan Nothing (Paragraph Nothing [Text callSpan "a"])
            nested = Document (FileId 1) [Block callSpan Nothing (BulletList [ListItem Nothing [Block callSpan Nothing (ForcedBreak BreakPage)]])]
        p <- load =<< fixed abi (responseWith (documentTerm nested))
        case applyFilter p "upper" (Document (FileId 1) [para]) of
          Left (BadOutput _) -> pure ()
          other -> assertFailure (show other),
      testCase "an endless loop runs out of fuel, at the same place every time" $ do
        w <- compile =<< wat "loop.wat"
        p <- loadPluginWith 100000 defaultMemoryLimit w >>= either (assertFailure . show) pure
        let r1 = invokeRaw p "x"
            r2 = invokeRaw p "x"
        case r1 of
          Left (OutOfFuel _) -> pure ()
          other -> assertFailure (show other)
        r1 @?= r2,
      testCase "memory beyond the limit is an error" $ do
        w <- compile =<< wat "memory.wat"
        p <- loadPluginWith defaultFuel (4 * 1024 * 1024) w >>= either (assertFailure . show) pure
        case invokeRaw p "x" of
          Left (Trapped _) -> pure ()
          other -> assertFailure (show other),
      testCase "a table beyond the limit on table elements cannot be instantiated (docs/adr ADR 0035)" $ do
        w <- compile =<< wat "table.wat"
        loadPlugin w >>= \case
          Left (InstantiateFailed _) -> pure ()
          other -> assertFailure (show (void other)),
      testCase "a result of the wrong type is bad output, every time (docs/adr ADR 0035)" $ do
        w <- compile =<< wat "describe-i32.wat"
        loadPlugin w >>= (@?= Left (BadOutput "golem_describe の戻り値の型が不正です")) . void,
      testCase "a sha256 that is not 64 lowercase hexadecimal digits is G06011 (docs/adr ADR 0035)" $
        forM_ ["../../../../tmp/x", "00", T.toUpper (hashHex "AAA"), hashHex "AAA" <> "0"] $ \h ->
          case parseLock (FileId 0) ("[plugins.a]\nurl = \"https://example.com/a.wasm\"\nsha256 = \"" <> h <> "\"\n") of
            Left ds -> do
              map diagCode ds @?= [DiagnosticCode "G06011"]
              map diagMessage ds @?= ["plugins.a.sha256 は 64 文字の小文字の 16 進数で書きます"]
            Right m -> assertFailure (show m),
      testCase "NaN results are the same bytes on every run" $ do
        w <- compile =<< wat "nan.wat"
        p <- load w
        let runs = [invokeRaw p "x" | _ <- [1 :: Int .. 5]]
        assertBool "same" (all (== head' runs) runs)
        fmap BS.length (head' runs) @?= Right 8,
      testGroup
        "output validation"
        [ testCase "broken CBOR" $ do
            p <- load =<< fixed abi (BS.pack [0xff, 0x00])
            assertBool "error" (isLeft (shout p)),
          testCase "CBOR that does not match the schema" $ do
            p <- load =<< fixed abi (cbor (TList [TInt 1, TInt 2]))
            assertBool "error" (isLeft (shout p)),
          testCase "nested ruby" $ do
            let inner = inlinesTerm [Ruby callSpan () [RubySegment [Text callSpan "漢"] (Just "かん")]]
                textT = case inlinesTerm [Text callSpan "漢"] of
                  TList [t] -> t
                  t -> t
                rubyT = case inner of
                  TList [t] -> t
                  t -> t
                nested = replaceTerm textT rubyT inner
            assertBool "the term changed" (nested /= inner)
            p <- load =<< fixed abi (responseWith nested)
            assertBool "error" (isLeft (shout p)),
          testCase "a DeferredExpr the request did not contain" $ do
            let d = DeferredExpr (A.Located callSpan (A.EVar ["doc", "chapters", "count"]))
            p <- load =<< fixed abi (responseWith (inlinesTerm [Deferred callSpan d]))
            case shout p of
              Left (BadOutput _) -> pure ()
              other -> assertFailure (show other),
          testCase "a source position outside the request" $ do
            p <- load =<< fixed abi (responseWith (inlinesTerm [Text (mkSpan (FileId 1) 900 901) "x"]))
            case shout p of
              Left (BadOutput _) -> pure ()
              other -> assertFailure (show other)
        ],
      testCase "parallel calls give the same results as sequential ones" $ do
        p <- load =<< fixed abi (responseWith (inlinesTerm [Text callSpan "SLOT"]))
        let calls = replicate 16 ()
        par <- mapConcurrently (\_ -> pure $! either (const 0) (length . fst) (shout p)) calls
        par @?= map (\_ -> either (const 0) (length . fst) (shout p)) calls
    ]
  where
    head' (x : _) = x
    head' [] = Left (BadOutput "none")

-- | A fake distribution server: URL → bytes, with a request log.
fakeServer :: IORef (Map.Map Text ByteString) -> IORef Int -> Fetcher
fakeServer files hits url = do
  modifyIORef' hits (+ 1)
  m <- readIORef files
  pure (maybe (Left ("404: " <> url)) Right (Map.lookup url m))

urlA, urlB :: Text
urlA = "https://example.com/releases/a.wasm"
urlB = "https://example.com/releases/b.wasm"

lockTests :: TestTree
lockTests =
  testGroup
    "distribution and lock (ADR 0002)"
    [ testCase "lock writes hashes sorted by name and fills the cache" $ withSystemTempDirectory "cache" $ \cache -> do
        files <- newIORef (Map.fromList [(urlA, "AAA"), (urlB, "BBB")])
        hits <- newIORef 0
        Right lock <- lockPlugins (fakeServer files hits) cache (Map.fromList [("zeta", urlB), ("alpha", urlA)])
        renderLock lock
          @?= T.unlines
            [ "[plugins.alpha]",
              "url = \"https://example.com/releases/a.wasm\"",
              "sha256 = \"" <> hashHex "AAA" <> "\"",
              "",
              "[plugins.zeta]",
              "url = \"https://example.com/releases/b.wasm\"",
              "sha256 = \"" <> hashHex "BBB" <> "\""
            ]
        parseLock (FileId 0) (renderLock lock) @?= Right lock
        listDirectory cache >>= (@?= 2) . length,
      testCase "an unknown key of plugins.lock is G06011 in Japanese (golem-project ADR 0007)" $
        case parseLock (FileId 0) "[plugins.a]\nurl = \"https://example.com/a.wasm\"\nsha256 = \"00\"\nsha = \"00\"\n" of
          Left ds -> do
            map diagCode ds @?= [DiagnosticCode "G06011"]
            assertBool (show (map diagMessage ds)) (all (("知らないキーです: " `T.isPrefixOf`) . diagMessage) ds)
          Right m -> assertFailure (show m),
      testCase "a plugin removed from the manifest leaves the lock" $ withSystemTempDirectory "cache" $ \cache -> do
        files <- newIORef (Map.fromList [(urlA, "AAA"), (urlB, "BBB")])
        hits <- newIORef 0
        Right lock <- lockPlugins (fakeServer files hits) cache (Map.fromList [("alpha", urlA)])
        Map.keys lock @?= ["alpha"],
      testCase "with a cache, fetch needs no network; without, it downloads" $ withSystemTempDirectory "cache" $ \cache -> do
        files <- newIORef (Map.fromList [(urlA, "AAA")])
        hits <- newIORef 0
        let lock = Map.fromList [("alpha", LockEntry urlA (hashHex "AAA"))]
        readCached cache (lock Map.! "alpha") >>= (@?= Left NotCached)
        fetchPlugins (fakeServer files hits) cache lock >>= (@?= Right ())
        readIORef hits >>= (@?= 1)
        fetchPlugins (fakeServer files hits) cache lock >>= (@?= Right ())
        readIORef hits >>= (@?= 1)
        readCached cache (lock Map.! "alpha") >>= (@?= Right "AAA"),
      testCase "a replaced artifact fails fetch and never enters the cache" $ withSystemTempDirectory "cache" $ \cache -> do
        files <- newIORef (Map.fromList [(urlA, "AAA")])
        hits <- newIORef 0
        let lock = Map.fromList [("alpha", LockEntry urlA (hashHex "AAA"))]
        writeIORef files (Map.fromList [(urlA, "EVIL")])
        r <- fetchPlugins (fakeServer files hits) cache lock
        assertBool "error" (isLeft r)
        exists <- doesFileExist (cachePath cache (hashHex "EVIL"))
        exists @?= False
        readCached cache (lock Map.! "alpha") >>= (@?= Left NotCached),
      testCase "HTTP URLs and redirects to HTTP are errors" $ withSystemTempDirectory "cache" $ \cache -> do
        files <- newIORef Map.empty
        hits <- newIORef 0
        r <- lockPlugins (fakeServer files hits) cache (Map.fromList [("x", "http://example.com/x.wasm")])
        assertBool "http" (isLeft r)
        readIORef hits >>= (@?= 0)
        assertBool "to http" (isLeft (nextRedirect urlA (Just "http://evil.example/x.wasm")))
        nextRedirect urlA (Just "https://objects.example/x.wasm") @?= Right "https://objects.example/x.wasm"
        nextRedirect urlA (Just "/other.wasm") @?= Right "https://example.com/other.wasm"
        fetcher <- httpsFetcher
        r' <- fetcher "http://example.com/x.wasm"
        assertBool "fetcher refuses http" (isLeft r')
    ]

{- | A local HTTPS server with a self-signed certificate (made with the
openssl CLI at the given path), serving files from an IORef, plus redirects.
-}
withHttpsServer :: IO FilePath -> IORef (Map.Map Text ByteString) -> (Int -> Fetcher -> IO ()) -> IO ()
withHttpsServer openssl files k = do
  exe <- openssl
  withSystemTempDirectory "golem-https" $ \dir -> do
    let cert = dir <> "/cert.pem"
        key = dir <> "/key.pem"
    (code, _, err) <- readProcessWithExitCode exe ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "1", "-subj", "/CN=localhost"] ""
    assertEqual ("openssl req: " <> err) ExitSuccess code
    sock <- socket AF_INET Stream defaultProtocol
    bind sock (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
    listen sock 16
    port <- fromIntegral <$> socketPort sock
    let base = "https://127.0.0.1:" <> T.pack (show port)
        app req respond = do
          m <- readIORef files
          let path = TE.decodeUtf8 (W.rawPathInfo req)
          respond $ case path of
            "/redirect" -> W.responseLBS (H.mkStatus 302 "Found") [(H.hLocation, TE.encodeUtf8 (base <> "/a.wasm"))] ""
            "/to-http" -> W.responseLBS (H.mkStatus 302 "Found") [(H.hLocation, TE.encodeUtf8 ("http://127.0.0.1:" <> T.pack (show port) <> "/a.wasm"))] ""
            _ -> case Map.lookup path m of
              Just b -> W.responseLBS H.status200 [] (BL.fromStrict b)
              Nothing -> W.responseLBS H.status404 [] ""
    server <- async (WT.runTLSSocket (WT.tlsSettings cert key) Warp.defaultSettings sock app)
    manager <- newManager (mkManagerSettings (TLSSettingsSimple True False False def) Nothing)
    k port (httpsFetcherWith manager) `finally` cancel server

httpsTests :: TestTree
httpsTests =
  needsTool "openssl" (findExecutable "openssl") $ \openssl ->
    testGroup
      "distribution over a local HTTPS server (ADR 0002)"
      [ testCase "lock from the server; a replaced artifact fails fetch; redirects stay on HTTPS" $ do
          files <- newIORef (Map.fromList [("/a.wasm", "PLUGIN-A")])
          withHttpsServer openssl files $ \port fetch -> withSystemTempDirectory "cache" $ \cache -> do
            let base = "https://127.0.0.1:" <> T.pack (show port)
            Right lock <- lockPlugins fetch cache (Map.fromList [("a", base <> "/a.wasm")])
            renderLock lock @?= "[plugins.a]\nurl = \"" <> base <> "/a.wasm\"\nsha256 = \"" <> hashHex "PLUGIN-A" <> "\"\n"
            -- through an HTTPS redirect
            fetch (base <> "/redirect") >>= (@?= Right "PLUGIN-A")
            -- a redirect to HTTP is refused
            r <- fetch (base <> "/to-http")
            assertBool (show r) (isLeft r)
            -- the server replaces the artifact: fetch into an empty cache fails
            writeIORef files (Map.fromList [("/a.wasm", "EVIL")])
            withSystemTempDirectory "cache2" $ \cache2 -> do
              f <- fetchPlugins fetch cache2 lock
              assertBool "mismatch" (isLeft f)
              readCached cache2 (lock Map.! "a") >>= (@?= Left NotCached)
      ]

{- | With no root certificates, httpsFetcher fails before it connects and
says how to fix it (docs/adr/0004).

The test sets SSL_CERT_FILE, and changing the environment while another
thread starts a process can break the start (posix_spawnp read the
environment as it changed: "Bad address"). tasty runs tests at once, so
this one waits for the HTTPS tests, which start openssl.
-}
rootCertTests :: TestTree
rootCertTests =
  after AllFinish "/local HTTPS server/" $
    testGroup
      "TLS root certificates (docs/adr/0004)"
      [ testCase "an empty certificate store fails before connecting" $ withSystemTempDirectory "golem-certs" $ \dir -> do
          let empty = dir <> "/empty.pem"
          BS.writeFile empty ""
          sock <- socket AF_INET Stream defaultProtocol
          bind sock (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
          listen sock 16
          port <- socketPort sock
          old <- lookupEnv "SSL_CERT_FILE"
          r <-
            ( do
                setEnv "SSL_CERT_FILE" empty
                fetch <- httpsFetcher
                fetch ("https://127.0.0.1:" <> T.pack (show port) <> "/a.wasm")
            )
              `finally` maybe (unsetEnv "SSL_CERT_FILE") (setEnv "SSL_CERT_FILE") old
          -- a connection of the test's own after the fetch: the listening
          -- socket queues connections in order, so the first one accepted is
          -- the fetcher's if it connected, without waiting for a timeout
          own <- socket AF_INET Stream defaultProtocol
          connect own (SockAddrInet port (tupleToHostAddress (127, 0, 0, 1)))
          ownAddr <- getSocketName own
          (conn, peer) <- accept sock
          mapM_ close [conn, own, sock]
          case r of
            Left msg -> assertBool (T.unpack msg) ("SSL_CERT_FILE" `T.isInfixOf` msg && "ca-certificates" `T.isInfixOf` msg)
            Right _ -> assertFailure "fetched with no root certificates"
          assertEqual "the first connection to the server is the test's own" ownAddr peer
      ]
