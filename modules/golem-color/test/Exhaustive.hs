{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE ImportQualifiedPost #-}

-- root ADR 0474 I2: build with ghc -O2 -i./modules/golem-color/src
-- -outputdir /tmp/golem-color-obj modules/golem-color/test/Exhaustive.hs
-- -o /tmp/golem-color-exhaustive, then run without arguments for all RGB8.
import Control.Monad (forM_)
import Data.Ratio ((%))
import Golem.Color qualified as C
import System.Environment (getArgs)

main :: IO ()
main = do
  args <- getArgs
  let top = case args of [x] -> read x; _ -> 255
  forM_ [0 .. top] $ \r -> do
    forM_ [0 .. 255] $ \g ->
      forM_ [0 .. 255] $ \b -> do
        let !v = max r (max g b)
            ref x = if v == 0 then 0 else round (255 * ((v - x) % v))
            !expected = (ref r, ref g, ref b, 255 - v)
            !actual = C.cmyk8Components (C.rgb8ToCmyk8 (case C.rgb8 r g b of Just x -> x; Nothing -> error "invalid"))
        if actual == expected then pure () else error (show ((r, g, b), expected, actual))
    putStrLn ("R=" <> show r <> " passed")
  putStrLn ("RGB8 exhaustive parity: " <> show ((top + 1) * 256 * 256) <> " passed")
