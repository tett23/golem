{- | Plugin distribution (golem-plugin ADR 0002): HTTPS URLs in the
manifest, SHA-256 hashes in plugins.lock, a cache keyed by hash, and the
`golem plugin fetch` / `golem plugin lock` operations.
-}
module Golem.Plugin.Lock
  ( LockEntry (..),
    Lock,
    parseLock,
    renderLock,
    Fetcher,
    httpsFetcher,
    httpsFetcherWith,
    nextRedirect,
    defaultCacheDir,
    cachePath,
    hashHex,
    lockPlugins,
    fetchPlugins,
    readCached,
    CachedError (..),
  )
where

import Control.Exception (SomeException, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Either (lefts, rights)
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.X509.CertificateStore (listCertificates)
import Golem.Project.Manifest (decodeStrict)
import Golem.Syntax
import Golem.Syntax.Sha256 (sha256)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (newTlsManager)
import Network.HTTP.Types (hLocation, statusCode)
import System.Directory (XdgDirectory (..), createDirectoryIfMissing, doesFileExist, getXdgDirectory)
import System.FilePath ((</>))
import System.X509 (getSystemCertificateStore)
import Text.Printf (printf)
import Toml.Schema

data LockEntry = LockEntry {leUrl :: !Text, leSha256 :: !Text}
  deriving stock (Eq, Show)

type Lock = Map Text LockEntry

newtype LockFile = LockFile (Map Text LockEntry)

instance FromValue LockEntry where
  fromValue = parseTableFromValue (LockEntry <$> reqKey "url" <*> reqKey "sha256")

instance FromValue LockFile where
  fromValue = parseTableFromValue (LockFile . fromMaybe Map.empty <$> optKey "plugins")

parseLock :: FileId -> Text -> Either [Diagnostic] Lock
parseLock fid src = (\(LockFile m) -> m) <$> decodeStrict "G0611" fid src

-- | Sorted by plugin name; written only by Golem.
renderLock :: Lock -> Text
renderLock lock =
  T.intercalate
    "\n"
    [ "[plugins." <> name <> "]\nurl = " <> quote (leUrl e) <> "\nsha256 = " <> quote (leSha256 e) <> "\n"
    | (name, e) <- sortOn fst (Map.toList lock)
    ]
  where
    quote t = "\"" <> T.concatMap (\case '"' -> "\\\""; '\\' -> "\\\\"; c -> T.singleton c) t <> "\""

hashHex :: ByteString -> Text
hashHex = T.pack . concatMap (printf "%02x") . BS.unpack . sha256

-- | Downloads a URL.
type Fetcher = Text -> IO (Either Text ByteString)

-- | Where a redirect leads, if it is allowed: HTTPS only.
nextRedirect :: Text -> Maybe Text -> Either Text Text
nextRedirect from = \case
  Nothing -> Left ("リダイレクト先がありません: " <> from)
  Just loc
    | "https://" `T.isPrefixOf` loc -> Right loc
    | "http://" `T.isPrefixOf` loc -> Left ("HTTP へのリダイレクトは許しません: " <> loc)
    | "/" `T.isPrefixOf` loc -> Right (T.intercalate "/" (take 3 (T.splitOn "/" from)) <> loc)
    | otherwise -> Left ("不明なリダイレクト先です: " <> loc)

{- | HTTPS only; redirects are followed one by one and may not leave HTTPS.
The root certificates come from the store of the OS (SSL_CERT_FILE and
SSL_CERT_DIR take precedence). With no root certificates, every fetch fails
before connecting and says how to fix it (docs/adr/0004): a minimal
container has no ca-certificates, and the failure of TLS verification
would not tell why.
-}
httpsFetcher :: IO Fetcher
httpsFetcher = do
  certificates <- listCertificates <$> getSystemCertificateStore
  if null certificates
    then pure (const (pure (Left noRootCertificates)))
    else httpsFetcherWith <$> newTlsManager

noRootCertificates :: Text
noRootCertificates = "TLS のルート証明書が見つかりません。ca-certificates を入れるか、SSL_CERT_FILE で証明書のファイルを指定してください"

{- | The same with a given connection manager (tests use one that trusts a
local server's certificate).
-}
httpsFetcherWith :: Manager -> Fetcher
httpsFetcherWith manager =
  let go :: Int -> Text -> IO (Either Text ByteString)
      go hops url
        | not ("https://" `T.isPrefixOf` url) = pure (Left ("HTTPS の URL だけを使えます: " <> url))
        | hops > 10 = pure (Left ("リダイレクトが多すぎます: " <> url))
        | otherwise = do
            r <- try $ do
              req <- parseRequest (T.unpack url)
              httpLbs req {redirectCount = 0} manager
            case r of
              Left (e :: SomeException) -> pure (Left (T.pack (show e)))
              Right resp ->
                let code = statusCode (responseStatus resp)
                 in if code >= 300 && code < 400
                      then either (pure . Left) (go (hops + 1)) (nextRedirect url (TE.decodeUtf8Lenient <$> lookup hLocation (responseHeaders resp)))
                      else
                        if code == 200
                          then pure (Right (BL.toStrict (responseBody resp)))
                          else pure (Left ("取得に失敗しました（" <> T.pack (show code) <> "）: " <> url))
   in go 0

-- | The user's cache directory (XDG): golem/plugins.
defaultCacheDir :: IO FilePath
defaultCacheDir = getXdgDirectory XdgCache ("golem" </> "plugins")

cachePath :: FilePath -> Text -> FilePath
cachePath dir hash = dir </> T.unpack hash <> ".wasm"

data CachedError = NotCached | HashMismatch
  deriving stock (Eq, Show)

-- | The plugin's bytes from the cache, checked against the lock.
readCached :: FilePath -> LockEntry -> IO (Either CachedError ByteString)
readCached dir e = do
  let path = cachePath dir (leSha256 e)
  ok <- doesFileExist path
  if not ok
    then pure (Left NotCached)
    else do
      b <- BS.readFile path
      pure (if hashHex b == leSha256 e then Right b else Left HashMismatch)

store :: FilePath -> ByteString -> IO Text
store dir bytes = do
  createDirectoryIfMissing True dir
  let h = hashHex bytes
  BS.writeFile (cachePath dir h) bytes
  pure h

{- | `golem plugin lock`: fetch what the manifest declares, write hashes.
Plugins gone from the manifest leave the lock.
-}
lockPlugins :: Fetcher -> FilePath -> Map Text Text -> IO (Either [Text] Lock)
lockPlugins fetch dir declared = do
  results <- mapM one (Map.toList declared)
  pure $ case lefts results of
    [] -> Right (Map.fromList (rights results))
    es -> Left es
  where
    one (name, url)
      | not ("https://" `T.isPrefixOf` url) = pure (Left (name <> ": HTTPS の URL だけを使えます: " <> url))
      | otherwise = do
          r <- fetch url
          case r of
            Left e -> pure (Left (name <> ": " <> e))
            Right bytes -> do
              h <- store dir bytes
              pure (Right (name, LockEntry url h))

{- | `golem plugin fetch`: download what the lock names and verify it;
nothing that fails the hash enters the cache.
-}
fetchPlugins :: Fetcher -> FilePath -> Lock -> IO (Either [Text] ())
fetchPlugins fetch dir lock = do
  results <- mapM one (Map.toList lock)
  pure $ case lefts results of
    [] -> Right ()
    es -> Left es
  where
    one (name, e) = do
      cached <- readCached dir e
      case cached of
        Right _ -> pure (Right ())
        Left _ -> do
          r <- fetch (leUrl e)
          case r of
            Left err -> pure (Left (name <> ": " <> err))
            Right bytes
              | hashHex bytes /= leSha256 e -> pure (Left (name <> ": 配布物のハッシュが plugins.lock と一致しません"))
              | otherwise -> Right () <$ store dir bytes
