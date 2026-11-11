module Main where
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.Ratio
import Golem.Font
import NoBreakEnum
main :: IO ()
main = mapM_ run ["SourceSansPro-Regular.otf", "SourceSerifVariable-Roman.ttf", "SourceHanSans-Regular_subset.otf"]

run :: FilePath -> IO ()
run path = do
  bytes <- BS.readFile ("modules/golem-font/test/fonts/" ++ path)
  Right font <- loadFont bytes
  let advance text = sum [fromIntegral x | (_,_,(x,_,_,_)) <- shapeUnits font ((shapeRequest text) {srScript="Latn",srLanguage="en"})]
      width t = advance t % fromIntegral (fontUnitsPerEm font)
      delta = advance "AV" - advance "A" - advance "V"
      (count, failures) = realProbe width
  unless (path /= "SourceSansPro-Regular.otf" || (delta /= 0 && width "AV" /= width "A" + width "V")) $ fail "H1 fixture has no pair adjustment"
  unless (null failures) $ fail (show (take 2 failures))
  putStrLn (path ++ " H1/S1 cases=" ++ show count ++ " AV adjustment=" ++ show delta ++ " fi glyphs=" ++ show (length (shapeUnits font ((shapeRequest "fi") {srScript="Latn",srLanguage="en"}))) ++ " 日 gid=" ++ show [g | (g,_,_) <- shapeUnits font (shapeRequest "日")] ++ " upem=" ++ show (fontUnitsPerEm font))
