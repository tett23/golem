{-# LANGUAGE MultiWayIf #-}

{- | The frames of bytes of the wasm entry point (docs/adr/0199): the input,
the files of a project, and the result, the PDF and the diagnostics. Pure;
built and tested natively too.

The input is a sequence of files. Each is the length of its path (a
little-endian uint32), the path (UTF-8), the length of its content (the
same) and the content. A path is relative to the root of the project and
equal to what normalizeRelative (golem-project) makes of it; no path comes
twice.

The result is one byte of status, the length of the PDF and the PDF, and
the length of the JSON of the diagnostics and the JSON, the lengths
little-endian uint32. Status 0: built (a PDF of length 0 when an error
stopped it). Status 1: the input could not be read; both lengths are 0.
-}
module Golem.Wasm.Frame
  ( FrameError (..),
    readFiles,
    writeFiles,
    Result (..),
    writeResult,
    respond,
    isNormalized,
  )
where

import Data.Bits (shiftL, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Lazy qualified as BL
import Data.Char (chr)
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.Maybe (fromMaybe)
import Data.Word (Word32, Word8)

-- | Why an input cannot be read: the host's mistake, not one of the project (status 1).
data FrameError
  = -- | the input ends inside a length or a field
    Truncated
  | -- | a path that is not UTF-8
    NotUtf8 !ByteString
  | -- | a path that normalizeRelative changes or rejects
    NotNormalized !FilePath
  | -- | a path that comes twice
    Duplicate !FilePath
  deriving stock (Eq, Show)

-- | The files of an input frame, in their order.
readFiles :: ByteString -> Either FrameError [(FilePath, ByteString)]
readFiles = go [] []
  where
    go seen acc bs
      | BS.null bs = Right (reverse acc)
      | otherwise = do
          (rawPath, rest) <- field bs
          (content, rest') <- field rest
          path <- maybe (Left (NotUtf8 rawPath)) Right (decodeUtf8 rawPath)
          if
            | not (isNormalized path) -> Left (NotNormalized path)
            | path `elem` seen -> Left (Duplicate path)
            | otherwise -> go (path : seen) ((path, content) : acc) rest'
    field bs = do
      (n, rest) <- word32 bs
      if toInteger n > toInteger (BS.length rest)
        then Left Truncated
        else Right (BS.splitAt (fromIntegral n) rest)
    word32 :: ByteString -> Either FrameError (Word32, ByteString)
    word32 bs
      | BS.length bs < 4 = Left Truncated
      | otherwise =
          let (h, rest) = BS.splitAt 4 bs
           in Right (foldr (\b n -> n `shiftL` 8 .|. fromIntegral b) 0 (BS.unpack h), rest)

-- | The input frame of files, for hosts and the tests.
writeFiles :: [(FilePath, ByteString)] -> ByteString
writeFiles = BL.toStrict . B.toLazyByteString . foldMap one
  where
    one (p, c) = let raw = encodeUtf8 p in sized raw <> sized c

-- | What a call of the entry point returns.
data Result
  = -- | the PDF, when one was made, and the JSON of the diagnostics
    Built !(Maybe ByteString) !ByteString
  | -- | the input frame could not be read
    Unreadable
  deriving stock (Eq, Show)

writeResult :: Result -> ByteString
writeResult r = BL.toStrict (B.toLazyByteString frame)
  where
    frame = case r of
      Built pdf json -> B.word8 0 <> sized (fromMaybe BS.empty pdf) <> sized json
      Unreadable -> B.word8 1 <> sized BS.empty <> sized BS.empty

{- | The result frame of an input frame: Unreadable when it cannot be read,
without calling @build@; otherwise what @build@ makes of its files, the
PDF (if any) and the JSON of the diagnostics.
-}
respond :: ([(FilePath, ByteString)] -> IO (Maybe ByteString, ByteString)) -> ByteString -> IO ByteString
respond build input = case readFiles input of
  Left _ -> pure (writeResult Unreadable)
  Right files -> writeResult . uncurry Built <$> build files

sized :: ByteString -> B.Builder
sized b = B.word32LE (fromIntegral (BS.length b) :: Word32) <> B.byteString b

{- | Whether a path is what normalizeRelative (golem-project) makes of it:
no URL, not absolute, and its segments, split at / with the empty ones
dropped as System.FilePath does, without . and without .. . A copy of that
rule, so that this package depends on base and bytestring only.
-}
isNormalized :: FilePath -> Bool
isNormalized p = normalizeRelative p == Just p
  where
    normalizeRelative q
      | "://" `isInfixOf` q = Nothing
      | "/" `isPrefixOf` q = Nothing
      | otherwise = intercalate "/" . reverse <$> go [] (filter (not . null) (splitOn q))
    go acc [] = Just acc
    go acc ("." : rest) = go acc rest
    go (_ : acc) (".." : rest) = go acc rest
    go [] (".." : _) = Nothing
    go acc (seg : rest) = go (seg : acc) rest
    splitOn s = case break (== '/') s of
      (a, []) -> [a]
      (a, _ : rest) -> a : splitOn rest

-- | UTF-8 of a string; a lone surrogate becomes U+FFFD, as in text.
encodeUtf8 :: String -> ByteString
encodeUtf8 = BL.toStrict . B.toLazyByteString . B.stringUtf8

{- | Strict UTF-8 (RFC 3629): no overlong form, no surrogate, nothing above
U+10FFFF, nothing truncated.
-}
decodeUtf8 :: ByteString -> Maybe String
decodeUtf8 = go . BS.unpack
  where
    go [] = Just []
    go (b : bs)
      | b < 0x80 = (chr (fromIntegral b) :) <$> go bs
      | b >= 0xC2 && b <= 0xDF = multi 1 (fromIntegral b .&. 0x1F) 0x80 bs
      | b >= 0xE0 && b <= 0xEF = multi 2 (fromIntegral b .&. 0x0F) 0x800 bs
      | b >= 0xF0 && b <= 0xF4 = multi 3 (fromIntegral b .&. 0x07) 0x10000 bs
      | otherwise = Nothing
    multi :: Int -> Int -> Int -> [Word8] -> Maybe String
    multi n lead lowest bs =
      let (cont, rest) = splitAt n bs
       in if length cont /= n || any (\c -> c .&. 0xC0 /= 0x80) cont
            then Nothing
            else
              let cp = foldl (\acc c -> acc `shiftL` 6 .|. (fromIntegral c .&. 0x3F)) lead cont
               in if cp < lowest || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)
                    then Nothing
                    else (chr cp :) <$> go rest
