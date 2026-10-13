-- | SHA-256 (FIPS 180-4), reimplemented instead of adding a dependency.
module Golem.Syntax.Sha256
  ( sha256,
  )
where

import Data.Array (Array, elems, listArray, (!))
import Data.Bits (complement, rotateR, shiftL, shiftR, xor, (.&.), (.|.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word32, Word8)

k :: [Word32]
k =
  [ 0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2
  ]

{- | The eight working variables, strict, so that each block is computed
when it is folded in and no thunks pile up across the blocks of a large
input (a list kept its elements unevaluated until the end).
-}
data State = State !Word32 !Word32 !Word32 !Word32 !Word32 !Word32 !Word32 !Word32

h0 :: State
h0 = State 0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a 0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19

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

block :: State -> ByteString -> State
block hs@(State a0 b0 c0 d0 e0 f0 g0 h0') chunk =
  let -- a lazily self-referential array: each entry refers to earlier ones
      w :: Array Int Word32
      w = listArray (0, 63) [entry i | i <- [0 .. 63]]
      entry i
        | i < 16 = word chunk (4 * i)
        | otherwise =
            let s0 x = rotateR x 7 `xor` rotateR x 18 `xor` shiftR x 3
                s1 x = rotateR x 17 `xor` rotateR x 19 `xor` shiftR x 10
             in s1 (w ! (i - 2)) + w ! (i - 7) + s0 (w ! (i - 15)) + w ! (i - 16)
      step (State a b c d e f g h) (ki, wi) =
        let s1 = rotateR e 6 `xor` rotateR e 11 `xor` rotateR e 25
            ch = (e .&. f) `xor` (complement e .&. g)
            t1 = h + s1 + ch + ki + wi
            s0 = rotateR a 2 `xor` rotateR a 13 `xor` rotateR a 22
            maj = (a .&. b) `xor` (a .&. c) `xor` (b .&. c)
            t2 = s0 + maj
         in State (t1 + t2) a b c (d + t1) e f g
      State a1 b1 c1 d1 e1 f1 g1 h1 = foldl' step hs (zip k (elems w))
   in State (a0 + a1) (b0 + b1) (c0 + c1) (d0 + d1) (e0 + e1) (f0 + f1) (g0 + g1) (h0' + h1)

sha256 :: ByteString -> ByteString
sha256 msg =
  let len = BS.length msg
      full = len `div` 64
      blocksOf p = [BS.take 64 (BS.drop (64 * i) p) | i <- [0 .. BS.length p `div` 64 - 1]]
      chunks = [BS.take 64 (BS.drop (64 * i) msg) | i <- [0 .. full - 1]] ++ blocksOf (padTail len (BS.drop (64 * full) msg))
      State a b c d e f g h = foldl' block h0 chunks
   in BS.pack (concatMap bytes [a, b, c, d, e, f, g, h])
  where
    bytes :: Word32 -> [Word8]
    bytes w = [fromIntegral (w `shiftR` s) | s <- [24, 16, 8, 0]]
