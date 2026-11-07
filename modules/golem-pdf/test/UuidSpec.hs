{- | SHA-1 (FIPS 180-4) and the name-based UUID of the document ID
(RFC 9562 section 5.5), which golem-pdf computes itself instead of
depending on uuid (docs/adr ADR 0202). The uuid package is a dependency
of this test only: the document ID must stay the 16 bytes that
Data.UUID.V5.generateNamed namespaceURL returned.
-}
module UuidSpec (tests) where

import Control.Monad (forM_)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.UUID qualified as UUID
import Data.UUID.V5 qualified as V5
import Golem.Pdf.Sha1 (sha1)
import Golem.Pdf.Writer (documentId, nameBasedUuid)
import Golem.TestSupport.Bytes (hex)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

-- | What uuid gives for the same identifier: the document ID before ADR 0202.
viaUuid :: Text -> ByteString
viaUuid t = BL.toStrict (UUID.toByteString (V5.generateNamed V5.namespaceURL (BS.unpack (TE.encodeUtf8 t))))

{- | The lengths around the 64-byte blocks of SHA-1, counted both as the
UTF-8 of the identifier and as the hashed input (the 16 bytes of the
namespace come first).
-}
boundaryLengths :: [Int]
boundaryLengths = [55, 56, 63, 64, 65] <> [n - 16 | n <- [55, 56, 63, 64, 65]] <> [119, 120, 127, 128, 129]

-- | An identifier of up to 300 bytes of UTF-8: empty, ASCII, Japanese, any code point, or ASCII of a boundary length.
genIdentifier :: Gen Text
genIdentifier =
  Gen.choice
    [ Gen.filter ((<= 300) . BS.length . TE.encodeUtf8) (Gen.text (Range.linear 0 300) char),
      (\n -> T.replicate n "a") <$> Gen.element boundaryLengths
    ]
  where
    char = Gen.choice [Gen.ascii, Gen.enum 'ぁ' 'ヿ', Gen.enum '一' '龥', Gen.unicode]

tests :: TestTree
tests =
  testGroup
    "SHA-1 and the document ID (ADR 0202)"
    [ testCase "SHA-1: the examples of FIPS 180-4" $ do
        hex (sha1 "abc") @?= "a9993e364706816aba3e25717850c26c9cd0d89d"
        hex (sha1 "") @?= "da39a3ee5e6b4b0d3255bfef95601890afd80709"
        hex (sha1 "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") @?= "84983e441c3bd26ebaae4aa1f95129e5e54670f1"
        hex (sha1 (BS.replicate 1000000 0x61)) @?= "34aa973cd4c4daa4f61eeb2bdbad27316534016f",
      testCase "UUID v5: the example of RFC 9562 appendix A.4" $ do
        let dns = BS.pack [0x6b, 0xa7, 0xb8, 0x10, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8]
        -- Figure 22: the SHA-1 of the namespace and the name
        hex (sha1 (dns <> "www.example.com")) @?= "2ed6657de927468b55e12665a8aea6a22dee3e35"
        -- Figure 23: 2ed6657d-e927-568b-95e1-2665a8aea6a2
        hex (nameBasedUuid dns "www.example.com") @?= "2ed6657de927568b95e12665a8aea6a2",
      testCase "documentId: the URL namespace, as uuid gives it" $ do
        hex (documentId "urn:uuid:11111111-2222-4333-8444-555555555555") @?= hex (viaUuid "urn:uuid:11111111-2222-4333-8444-555555555555")
        hex (documentId "x") @?= hex (viaUuid "x"),
      testCase "documentId: the lengths around the 64-byte blocks" $
        forM_ boundaryLengths $ \n ->
          let t = T.replicate n "a"
           in assertEqual (show n <> " bytes") (hex (viaUuid t)) (hex (documentId t)),
      testProperty "documentId equals Data.UUID.V5.generateNamed namespaceURL" $
        withTests 500 $
          property $ do
            t <- forAll genIdentifier
            let ours = documentId t
            BS.length ours === 16
            hex ours === hex (viaUuid t)
    ]
