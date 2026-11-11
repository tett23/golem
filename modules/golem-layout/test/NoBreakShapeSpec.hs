module NoBreakShapeSpec (noBreakShapeTests) where

import Data.ByteString qualified as BS
import Data.Ratio ((%))
import Data.Text (Text)
import Golem.Font
import NoBreakEnum (realProbe)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertBool, assertEqual, testCase)

fontPath :: FilePath -> FilePath
fontPath name = "../golem-font/test/fonts/" ++ name

loadTestFont :: FilePath -> IO Font
loadTestFont name = BS.readFile (fontPath name) >>= loadFont >>= either (fail . show) pure

advance :: Font -> Text -> Integer
advance font text = sum [fromIntegral x | (_, _, (x, _, _, _)) <- shapeUnits font request]
  where
    request = (shapeRequest text) {srScript = "Latn", srLanguage = "en"}

wordWidth :: Font -> Text -> Rational
wordWidth font text = advance font text % fromIntegral (fontUnitsPerEm font)

noBreakShapeTests :: TestTree
noBreakShapeTests =
  testGroup
    "Golem ADR 0314"
    [ testCase "H1: Source Sans Pro AV has a pair advance" $ do
        font <- loadTestFont "SourceSansPro-Regular.otf"
        let joined = wordWidth font "AV"
            separate = wordWidth font "A" + wordWidth font "V"
        assertBool "Source Sans Pro must exercise pair adjustment" (joined /= separate),
      testCase "S1: real font advances preserve every small no-break range" $
        mapM_
          ( \name -> do
              font <- loadTestFont name
              let (count, failures) = realProbe (wordWidth font)
              assertEqual name 1814 count
              assertEqual name [] (take 1 failures)
          )
          ["SourceSansPro-Regular.otf", "SourceSerifVariable-Roman.ttf", "SourceHanSans-Regular_subset.otf"]
    ]
