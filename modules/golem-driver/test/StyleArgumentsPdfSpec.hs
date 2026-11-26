{- | The PDF of the paragraphs of @style with named arguments (root ADR
0467): a style without a name, based on the style named, with the keys of
the arguments.
-}
module StyleArgumentsPdfSpec (styleArgumentsPdfTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.Length (Sp (..))
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The grid lines of the lines of each page.
slotsOf :: BS.ByteString -> Text -> IO [[Int]]
slotsOf style src = do
  (_, pl) <- layoutOk style src []
  pure (map (map fst . poSlots) (gridPages pl))

-- | The grid lines and the indents of the lines of each page.
linesOf :: BS.ByteString -> Text -> IO [[(Int, Sp)]]
linesOf style src = do
  (_, pl) <- layoutOk style src []
  pure [[(slot, slIndent sl) | (slot, SLine lid) <- poSlots p, Just sl <- [Map.lookup lid (plLines pl)]] | p <- gridPages pl]

-- | horizontalStyle with the style quote: 2 lines before, 3 after, indent 2zw.
quoteStyle :: BS.ByteString
quoteStyle = horizontalStyle <> "\n[paragraph-styles.quote]\nspace-before = 2\nspace-after = 3\nindent = \"2zw\"\n"

styleArgumentsPdfTests :: [TestTree]
styleArgumentsPdfTests =
  [ testCase "root ADR 0467 I1: @style body sets the paragraph as one without @style" $ do
      body <- linesOf quoteStyle "@style body\nあいう\n"
      plain <- linesOf quoteStyle "あいう\n"
      body @?= plain,
    testCase "root ADR 0467 I2: @style quote k=v sets the paragraph as @style t of @style-def paragraph t based-on=quote k=v" $
      forM_ ["indent=4zw", "first-line-indent=1zw", "end-indent=2zw", "space-before=1", "indent=1zw first-line-indent=1zw", "align=right"] $ \kv -> do
        keyed <- linesOf quoteStyle ("あ\n\n@style quote " <> kv <> "\nあいうえおかきくけこさしすせそたちつてと\n\nい\n")
        defined <- linesOf quoteStyle ("@style-def paragraph t based-on=quote " <> kv <> "\n\nあ\n\n@style t\nあいうえおかきくけこさしすせそたちつてと\n\nい\n")
        (kv, keyed) @?= (kv, defined),
    testCase "root ADR 0467 I2: the body form with space-before=1 gives the space to both paragraphs" $ do
      keyed <- slotsOf quoteStyle "あ\n\n@style quote space-before=1 space-after=0\n:::\nい\n\nう\n:::\n"
      defined <- slotsOf quoteStyle "@style-def paragraph t based-on=quote space-before=1 space-after=0\n\nあ\n\n@style t\nい\n\n@style t\nう\n"
      keyed @?= defined,
    testCase "root ADR 0467 I5: two paragraphs of the same style without a name are apart by its space-between" $
      slotsOf quoteStyle "@style quote space-between=1\nあ\n\n@style quote space-between=1\nい\n" >>= (@?= [[0, 2]]),
    testCase "root ADR 0467 I5: @style quote and @style quote with keys are two styles, apart by the space after and before" $ do
      slotsOf quoteStyle "@style quote\nあ\n\n@style quote space-between=1\nい\n" >>= (@?= [[0, 4]])
      slotsOf quoteStyle "@style quote space-between=1\nあ\n\n@style quote space-between=2\nい\n" >>= (@?= [[0, 4]])
  ]
