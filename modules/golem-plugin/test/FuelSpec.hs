{- | The limit on the instructions of a call of a filter, in proportion to
the size of its document (docs/adr/0124).
-}
module FuelSpec (fuelTests) where

import Codec.CBOR.Term (encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.Cbor (documentTerm)
import Golem.Doc.IR hiding (abiVersion)
import Golem.Plugin
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 0 1

-- | A document of one paragraph of n characters a.
documentOf :: Int -> Document
documentOf n = Document (FileId 1) [Block callSpan Nothing Nothing (Paragraph Nothing [Text callSpan (T.replicate n "a")])]

-- | The bytes of the CBOR of a document, as the filter request carries it.
documentBytes :: Document -> Int
documentBytes = BS.length . toStrictByteString . encodeTerm . documentTerm

-- | loop-filter.wat with memory for a request of a few megabytes.
spinning :: IO Plugin
spinning = do
  src <- TIO.readFile "test/plugins/loop-filter.wat"
  let wide = T.replace "(memory (export \"memory\") 1)" "(memory (export \"memory\") 64)" src
  wasm <- watToWasm wide >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm >>= either (assertFailure . show) pure

identity :: IO Plugin
identity = do
  src <- TIO.readFile "test/plugins/identity.wat"
  wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
  loadPlugin wasm >>= either (assertFailure . show) pure

outOfFuel :: Either PluginError a -> Assertion
outOfFuel = \case
  Left (OutOfFuel _) -> pure ()
  Left e -> assertFailure (show e)
  Right _ -> assertFailure "the filter finished"

fuelTests :: TestTree
fuelTests =
  testGroup
    "the fuel of a filter (docs/adr/0124)"
    [ testCase "the limit is the limit of a command and 10000 for each byte of the document" $ do
        fuelPerDocumentByte @?= 10000
        filterFuel defaultFuel 0 @?= defaultFuel
        filterFuel defaultFuel 123 @?= defaultFuel + 1230000
        defaultFuel @?= 1000000000,
      testCase "an endless filter uses up the limit of its document, more for a larger one, the same every time" $ do
        p <- spinning
        let small = documentOf 10
            large = documentOf 200000
            (r1, used1) = applyFilterFuel p "spin" small
            (r2, used2) = applyFilterFuel p "spin" large
            (r3, used3) = applyFilterFuel p "spin" large
        outOfFuel r1
        outOfFuel r2
        used1 @?= filterFuel defaultFuel (documentBytes small)
        used2 @?= filterFuel defaultFuel (documentBytes large)
        assertBool "a larger document gets more" (used2 > used1)
        (void r3, used3) @?= (void r2, used2),
      testCase "a filter that finishes uses fewer than the limit, and more than none" $ do
        p <- identity
        let doc = documentOf 100
            (r, used) = applyFilterFuel p "same" doc
        fmap fst r @?= Right doc
        assertBool (show used) (used > 0 && used < filterFuel defaultFuel (documentBytes doc))
    ]
