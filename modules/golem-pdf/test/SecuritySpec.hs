{- | Hostile PDF figures end within limits of time and allocation (the
security audit of 2026-10-18, candidates C1 to C7). Each input is small
and is built with the builders of ImportSpec; what is asserted is that
reading it is bounded: it is refused with a diagnostic, or it is read
correctly, in a time and an allocation proportional to the input.
-}
module SecuritySpec (tests) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf
import ImageSpec (allocatedBy, zeros)
import ImportSpec (catalog, classicPdf, layout, objBytes, onePage, stream, xrefTable)
import Test.Tasty
import Test.Tasty.HUnit

-- ------------------------------------------------------------------ helpers

mib :: Int
mib = 1024 * 1024

-- | A zlib stream of a byte repeated.
compressed :: ByteString -> ByteString
compressed = BL.toStrict . Z.compress . BL.fromStrict

-- | The result of importing, fully evaluated: the error, or the length of the content and the number of objects.
imported :: Int -> ByteString -> IO (Either ImportError (Int, Int))
imported n pdf = do
  _ <- evaluate (BS.length pdf)
  r <- try (evaluate (force (importPage n pdf)))
  case r of
    Left (e :: SomeException) -> assertFailure ("importPage threw: " <> show e)
    Right x -> pure x
  where
    force = \case
      Left e -> length (show e) `seq` Left e
      Right p -> let c = BS.length (ipContent p); o = length (ipObjects p) in c `seq` o `seq` Right (c, o)

-- | Reading finished (refused or read); what it gave does not matter here.
finished :: Either ImportError (Int, Int) -> Assertion
finished = either (const (pure ())) (const (pure ()))

-- | Refused, or allocated less than the limit.
refusedOrUnder :: Integer -> (Either ImportError (Int, Int), Integer) -> Assertion
refusedOrUnder limit (r, bytes) = case r of
  Left _ -> pure ()
  Right _ -> assertBool ("read, allocating " <> show bytes <> " bytes") (bytes < limit)

seconds :: Integer -> Integer
seconds = (* 1000000)

-- | One page whose content stream has the dictionary entries and the body given.
pageWith :: ByteString -> ByteString -> ByteString
pageWith dict body =
  classicPdf
    ""
    [ catalog,
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << >> /Contents 4 0 R >>"),
      (4, stream dict body)
    ]

-- ------------------------------------------------------------------ C1: the page tree as a DAG

-- | A page tree of the depth given in which every node names the same child twice.
dagPdf :: Int -> ByteString
dagPdf depth =
  classicPdf "" $
    [catalog]
      <> [(n, "<< /Type /Pages /Kids [" <> ref (n + 1) <> " " <> ref (n + 1) <> "] /Count 2 >>") | n <- [2 .. depth + 1]]
      <> [ (depth + 2, "<< /Type /Page /Parent " <> ref (depth + 1) <> " /MediaBox [0 0 10 10] /Resources << >> /Contents " <> ref (depth + 3) <> " >>"),
           (depth + 3, stream "" "0 0 1 1 re f")
         ]
  where
    ref n = BC.pack (show n) <> " 0 R"

-- ------------------------------------------------------------------ C6: a cross-reference stream named by many revisions

{- | A classic PDF whose last revisions each name the same cross-reference
stream with @/XRefStm@. The stream has @rows@ free entries from object 10
(so that the real objects are not shadowed), @/Size@ near 1e8.
-}
xrefStmRevisions :: Int -> Int -> ByteString
xrefStmRevisions rows revisions =
  let (body, offs) = layout "%PDF-1.5\n%\xE2\xE3\xCF\xD3\n" (onePage "<< >>" "0 0 1 1 re f")
      stmOff = BS.length body
      xref =
        stream
          ("/Type /XRef /Size 100000000 /W [1 4 2] /Index [10 " <> BC.pack (show rows) <> "] /Root 1 0 R /Filter /FlateDecode")
          (compressed (BS.replicate (7 * rows) 0))
      body2 = body <> objBytes (9, xref)
      table0 = "xref\n0 1\n0000000000 65535 f \n" <> BS.drop 5 (xrefTable offs) <> "trailer\n<< /Size 10 /Root 1 0 R >>\n"
      revision prev = "xref\n0 0\ntrailer\n<< /Size 10 /Root 1 0 R /XRefStm " <> BC.pack (show stmOff) <> " /Prev " <> BC.pack (show prev) <> " >>\n"
      go acc prev 0 = (acc, prev)
      go acc prev k = let off = BS.length acc in go (acc <> revision prev) off (k - 1 :: Int)
      (withRevisions, lastOff) = go (body2 <> table0) (BS.length body2) revisions
   in withRevisions <> "startxref\n" <> BC.pack (show lastOff) <> "\n%%EOF\n"

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests =
  testGroup
    "hostile PDF figures end within limits (security audit 2026-10-18)"
    [ localOption (mkTimeout (seconds 5))
        $ testCase "C1: a page tree that is a DAG of depth 24 is refused or counted without walking 2^24 leaves"
        $ imported 1 (dagPdf 24) >>= finished,
      localOption (mkTimeout (seconds 10))
        $ testCase "C2: a literal string of 50000 short octal escapes is read in time and allocation linear in its length"
        $ do
          let body = "BT (" <> BS.concat (replicate 50000 "\\1x") <> ") Tj ET"
              pdf = pageWith "" body
          (r, bytes) <- allocatedBy (imported 1 pdf)
          either (assertFailure . show) (const (pure ())) r
          -- 150 KB of string: linear reading allocates a few MB, quadratic reading a few GB
          assertBool ("allocated " <> show bytes) (bytes < 64 * toInteger (BS.length body)),
      localOption (mkTimeout (seconds 60))
        $ testCase "C3: one stream of 8 MiB named 40 times in Contents does not expand to 320 MiB"
        $ do
          let refs = BC.unwords (replicate 40 "4 0 R")
              pdf =
                classicPdf
                  ""
                  [ catalog,
                    (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                    (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << >> /Contents [" <> refs <> "] >>"),
                    (4, stream "/Filter /FlateDecode" (zeros (8 * mib)))
                  ]
          allocatedBy (imported 1 pdf) >>= refusedOrUnder (toInteger (300 * mib)),
      localOption (mkTimeout (seconds 10))
        $ testCase "C4: the TIFF predictor with Colors 65536 decodes 1 MiB in time linear in its length"
        $ imported 1 (pageWith "/Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 65536 /BitsPerComponent 8 /Columns 65536 >>" (zeros mib)) >>= finished,
      localOption (mkTimeout (seconds 60))
        $ testCase "C5: Flate then ASCII85 of 80 MiB of z does not expand to 320 MiB"
        $ do
          let pdf = pageWith "/Filter [/FlateDecode /ASCII85Decode]" (compressed (BS.replicate (80 * mib) 122))
          allocatedBy (imported 1 pdf) >>= refusedOrUnder (toInteger (300 * mib)),
      localOption (mkTimeout (seconds 30))
        $ testCase "C6: a cross-reference stream of 4 million rows named by 4 revisions is decoded within bounds"
        $ do
          let pdf = xrefStmRevisions 4000000 4
          (r, bytes) <- allocatedBy (imported 1 pdf)
          -- the rows are 28 MiB once; the map of them should not be built four times over
          case r of
            Left _ -> assertBool ("refused, allocating " <> show bytes) (bytes < toInteger (256 * mib))
            Right _ -> assertBool ("read, allocating " <> show bytes) (bytes < toInteger (256 * mib)),
      localOption (mkTimeout (seconds 60))
        $ testCase "C7: a content stream of 16 MiB of tiny tokens is rewritten in allocation a few times its size"
        $ do
          let body = BS.concat (replicate (4 * mib) "0 g\n")
              pdf = pageWith "/Filter /FlateDecode" (compressed body)
          (r, bytes) <- allocatedBy (imported 1 pdf)
          either (assertFailure . show) (\(c, _) -> c @?= BS.length body) r
          assertBool ("allocated " <> show bytes) (bytes < 16 * toInteger (BS.length body)),
      testCase "C15: a control character in the title does not reach the XMP packet" $ do
        let xmp = TE.decodeUtf8 (xmpPacket (PdfX "" "JC200103" ["a\SOHb"] []) "t\SOHt" "p" (2026, 10, 18) (BS.replicate 16 0) (BS.replicate 16 1))
        T.filter (\c -> c < ' ' && c `notElem` ("\t\n\r" :: String)) xmp @?= ""
    ]
