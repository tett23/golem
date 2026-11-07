{- | The wasm reactor module of Golem (docs/adr/0199): the PDF of a project
from the bytes of its files, with the same build as golem build --target
pdf, reading no file. The exports are C functions; the host calls
_initialize once, hs_init(0, 0) once, and then these.

Every buffer these functions hand out or take has its length in the four
bytes before it, so that golem_result_len can tell the length of a result
and of the version, and golem_free frees any of them.
-}
module Main (main) where

import Data.ByteString qualified as BS
import Data.ByteString.Unsafe qualified as BU
import Data.Map.Strict qualified as Map
import Data.Text.Encoding qualified as TE
import Data.Word (Word32, Word8)
import Foreign.Marshal.Alloc (free, mallocBytes)
import Foreign.Marshal.Utils (copyBytes)
import Foreign.Ptr (Ptr, castPtr, nullPtr, plusPtr)
import Foreign.Storable (peek, poke)
import Golem.Driver (BuildInMemory (..), buildPdfInMemory)
import Golem.Driver.Version (golemVersion)
import Golem.Syntax (renderJson)
import Golem.Wasm.Frame (respond)

foreign export ccall golem_alloc :: Word32 -> IO (Ptr Word8)

foreign export ccall golem_free :: Ptr Word8 -> IO ()

foreign export ccall golem_build_pdf :: Ptr Word8 -> Word32 -> IO (Ptr Word8)

foreign export ccall golem_result_len :: Ptr Word8 -> IO Word32

foreign export ccall golem_version :: IO (Ptr Word8)

-- | Not called: the module is a reactor (-no-hs-main).
main :: IO ()
main = pure ()

-- | A buffer of @len@ bytes, with its length before it.
golem_alloc :: Word32 -> IO (Ptr Word8)
golem_alloc len = do
  p <- mallocBytes (4 + fromIntegral len)
  poke (castPtr p) len
  pure (p `plusPtr` 4)

-- | Frees a buffer of golem_alloc, golem_build_pdf or golem_version.
golem_free :: Ptr Word8 -> IO ()
golem_free p
  | p == nullPtr = pure ()
  | otherwise = free (p `plusPtr` (-4))

-- | The length of a buffer of golem_build_pdf or golem_version.
golem_result_len :: Ptr Word8 -> IO Word32
golem_result_len p = peek (castPtr (p `plusPtr` (-4)))

-- | The bytes in a new buffer.
handOut :: BS.ByteString -> IO (Ptr Word8)
handOut bytes = do
  p <- golem_alloc (fromIntegral (BS.length bytes))
  BU.unsafeUseAsCStringLen bytes $ \(src, n) -> copyBytes p (castPtr src) n
  pure p

{- | Reads the input frame, builds the PDF of its files (buildPdfInMemory)
and returns the result frame; status 1 for an input frame that cannot be
read.
-}
golem_build_pdf :: Ptr Word8 -> Word32 -> IO (Ptr Word8)
golem_build_pdf input len = do
  bytes <- BS.packCStringLen (castPtr input, fromIntegral len)
  result <- respond build bytes
  handOut result
  where
    build files = do
      r <- buildPdfInMemory (Map.fromList files)
      pure (bimPdf r, TE.encodeUtf8 (renderJson (bimSources r) (bimDiagnostics r)))

-- | VERSION, in UTF-8.
golem_version :: IO (Ptr Word8)
golem_version = handOut (TE.encodeUtf8 golemVersion)
