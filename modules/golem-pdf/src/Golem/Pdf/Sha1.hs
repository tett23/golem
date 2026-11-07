{- | SHA-1 (FIPS 180-4), reimplemented instead of depending on uuid for
the name-based UUID of the document ID (docs/adr ADR 0202). Only
golem-pdf uses it, so it lives here and not in golem-syntax. SHA-1 is not
used here for security: RFC 9562 section 5.5 fixes it as the hash of
version 5.
-}
module Golem.Pdf.Sha1
  ( sha1,
  )
where

import Data.Array (Array, elems, listArray, (!))
import Data.Bits (complement, rotateL, shiftL, shiftR, xor, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word32, Word8)

-- | The five working variables, strict, as in Golem.Syntax.Sha256.
data State = State !Word32 !Word32 !Word32 !Word32 !Word32

h0 :: State
h0 = State 0x67452301 0xefcdab89 0x98badcfe 0x10325476 0xc3d2e1f0

{- | The last bytes of the message (fewer than 64) with the padding: the
full blocks before them are read from the message itself, not copied.
-}
padTail :: Int -> ByteString -> ByteString
padTail total rest =
  let bitLen = fromIntegral total * 8 :: Integer
      zeros = (55 - BS.length rest) `mod` 64
   in BS.concat [rest, BS.singleton 0x80, BS.replicate zeros 0, BS.pack [fromIntegral (bitLen `shiftR` (8 * i)) | i <- [7, 6 .. 0]]]

word :: ByteString -> Int -> Word32
word b i = foldl' (\acc j -> (acc `shiftL` 8) .|. fromIntegral (BS.index b (i + j))) 0 [0 .. 3]

-- | The function and the constant of round t (FIPS 180-4 4.1.1 and 4.2.1).
roundOf :: Int -> Word32 -> Word32 -> Word32 -> (Word32, Word32)
roundOf t b c d
  | t < 20 = ((b .&. c) `xor` (complement b .&. d), 0x5a827999)
  | t < 40 = (b `xor` c `xor` d, 0x6ed9eba1)
  | t < 60 = ((b .&. c) `xor` (b .&. d) `xor` (c .&. d), 0x8f1bbcdc)
  | otherwise = (b `xor` c `xor` d, 0xca62c1d6)

block :: State -> ByteString -> State
block hs@(State a0 b0 c0 d0 e0) chunk =
  let -- a lazily self-referential array: each entry refers to earlier ones
      w :: Array Int Word32
      w = listArray (0, 79) [entry i | i <- [0 .. 79]]
      entry i
        | i < 16 = word chunk (4 * i)
        | otherwise = rotateL (w ! (i - 3) `xor` w ! (i - 8) `xor` w ! (i - 14) `xor` w ! (i - 16)) 1
      step (State a b c d e) (t, wt) =
        let (f, kt) = roundOf t b c d
            temp = rotateL a 5 + f + e + kt + wt
         in State temp a (rotateL b 30) c d
      State a1 b1 c1 d1 e1 = foldl' step hs (zip [0 ..] (elems w))
   in State (a0 + a1) (b0 + b1) (c0 + c1) (d0 + d1) (e0 + e1)

sha1 :: ByteString -> ByteString
sha1 msg =
  let len = BS.length msg
      full = len `div` 64
      blocksOf p = [BS.take 64 (BS.drop (64 * i) p) | i <- [0 .. BS.length p `div` 64 - 1]]
      chunks = [BS.take 64 (BS.drop (64 * i) msg) | i <- [0 .. full - 1]] ++ blocksOf (padTail len (BS.drop (64 * full) msg))
      State a b c d e = foldl' block h0 chunks
   in BS.pack (concatMap bytes [a, b, c, d, e])
  where
    bytes :: Word32 -> [Word8]
    bytes w = [fromIntegral (w `shiftR` s) | s <- [24, 16, 8, 0]]
