module Main (main) where

import Golem.Color

assert :: (Eq a, Show a) => String -> a -> a -> IO ()
assert name expected actual = if expected == actual then pure () else error (name <> ": " <> show actual <> " /= " <> show expected)

expectJust :: String -> Maybe a -> a
expectJust _ (Just value) = value
expectJust name Nothing = error (name <> ": construction failed")

main :: IO ()
main = do
  let black = expectJust "black" (rgb 0 0 0)
      white = expectJust "white" (rgb 1 1 1)
      sample = expectJust "sample" (rgb (1 / 5) (2 / 5) (3 / 5))
      grayRgb = expectJust "gray" (rgb (1 / 2) (1 / 2) (1 / 2))
      neutral = expectJust "neutral" (cmyk (1 / 2) (1 / 2) (1 / 2) (1 / 4))
      sample8 = expectJust "sample8" (rgb8 51 102 153)
      sample16 = expectJust "sample16" (rgb16 13107 26214 39321)
  assert "root ADR 0474 I1: black" (0, 0, 0, 1) (cmykComponents (rgbToCmyk black))
  assert "root ADR 0474 I1: white" (0, 0, 0, 0) (cmykComponents (rgbToCmyk white))
  assert "root ADR 0474 I1: sample" (2 / 3, 1 / 3, 0, 2 / 5) (cmykComponents (rgbToCmyk sample))
  assert "root ADR 0474 I7: inverse" (1 / 5, 2 / 5, 3 / 5) (rgbComponents (cmykToRgb (rgbToCmyk sample)))
  assert "root ADR 0474 I7: gray inverse" (rgbComponents grayRgb) (rgbComponents (cmykToRgb (rgbToCmyk grayRgb)))
  assert "root ADR 0474 I2: rgb8" (170, 85, 0, 102) (cmyk8Components (rgb8ToCmyk8 sample8))
  assert "root ADR 0474 I2: rgb16" (43690, 21845, 0, 26214) (cmyk16Components (rgb16ToCmyk16 sample16))
  assert "root ADR 0474 I4: old screen" (184, 138, 92) (cmykPercentToRgb8 (20, 40, 60, 10))
  assert "root ADR 0474 I1: invalid" Nothing (rgb (-1) 0 0)
  assert "root ADR 0474 I1: invalid high" Nothing (cmyk 0 0 0 2)
  assert "root ADR 0474 I1: gray invalid" Nothing (gray (3 / 2))
  assert "root ADR 0474 I1: rgb8 invalid" Nothing (rgb8 0 0 256)
  assert "root ADR 0474 I1: rgb16 invalid" Nothing (rgb16 65536 0 0)
  assert "root ADR 0474 I5: neutral gray" (Just (3 / 8)) (neutralCmykGray neutral)
  assert "root ADR 0474 I4: CSS percentage" 128 (percentageToRgb8 50)
  assert "root ADR 0474 I4: PDF half-up" 1 (quantizeHalfUp 1 (1 / 2))
  assert "root ADR 0474 I2: inverse tie-even" (128, 0, 0, 253) (cmyk8Components (rgb8ToCmyk8 (expectJust "tie" (rgb8 1 2 2))))
  mapM_ compare8 [(r, g, b) | r <- [0, 1, 2, 51, 128, 255], g <- [0, 2, 51, 128, 255], b <- [0, 1, 51, 128, 255]]
  mapM_ compare16 [(r, g, b) | r <- [0, 1, 13107, 65535], g <- [0, 21845, 65535], b <- [0, 39321, 65535]]
  let sequence16 = iterate (\x -> (1103515245 * x + 12345) `mod` 65536) (47 :: Int)
  mapM_ compare16 (take 1024 (zip3 sequence16 (drop 1 sequence16) (drop 2 sequence16)))
  assert "root ADR 0474 I2: 16-bit product fits Word64" True (toInteger (65535 :: Int) ^ (2 :: Int) < 2 ^ (64 :: Int))
  putStrLn "root ADR 0474: 18 checks and 1210 integer parity cases passed"

compare8 :: (Int, Int, Int) -> IO ()
compare8 (r, g, b) =
  let actual = cmyk8Components (rgb8ToCmyk8 (expectJust "rgb8 parity" (rgb8 r g b)))
      (c, m, y, k) = cmykComponents (rgbToCmyk (expectJust "rgb parity" (rgb (fromIntegral r / 255) (fromIntegral g / 255) (fromIntegral b / 255))))
   in assert "root ADR 0474 I2: 8-bit rational parity" (round (255 * c), round (255 * m), round (255 * y), round (255 * k)) actual

compare16 :: (Int, Int, Int) -> IO ()
compare16 (r, g, b) =
  let actual = cmyk16Components (rgb16ToCmyk16 (expectJust "rgb16 parity" (rgb16 r g b)))
      (c, m, y, k) = cmykComponents (rgbToCmyk (expectJust "rgb parity" (rgb (fromIntegral r / 65535) (fromIntegral g / 65535) (fromIntegral b / 65535))))
   in assert "root ADR 0474 I2: 16-bit rational parity" (round (65535 * c), round (65535 * m), round (65535 * y), round (65535 * k)) actual
