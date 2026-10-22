{- | Hostile PDF figures end within limits of time and allocation (the
security audit of 2026-10-18, candidates C1 to C7; docs/adr ADR 0040).
Each input is small and is built with the builders of ImportSpec; what is
asserted is that reading it is bounded: it is refused with a diagnostic,
or it is read correctly, in a time and an allocation proportional to the
input.
-}
module SecuritySpec (tests) where

import Codec.Compression.Zlib qualified as Z
import Control.Exception (SomeException, evaluate, try)
import Data.Bits (shiftR)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
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

-- | Read, whatever it gave.
readOk :: Either ImportError (Int, Int) -> Assertion
readOk = either (assertFailure . show) (const (pure ()))

-- | Refused for the reason given (the text in the parentheses of G08010).
refusedFor :: Text -> Either ImportError (Int, Int) -> Assertion
refusedFor why r = r @?= Left (Malformed why)

-- | The reason when decoding passes the limits (docs/adr ADR 0040).
tooLarge :: Text
tooLarge = "展開した大きさが上限を超えました"

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

-- | One page whose Contents is the array given, with the streams given.
contentsOf :: ByteString -> [(Int, ByteString)] -> ByteString
contentsOf refs streams =
  classicPdf
    ""
    ( [ catalog,
        (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
        (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << >> /Contents [" <> refs <> "] >>")
      ]
        <> streams
    )

-- | A content stream of @n@ bytes of @0 g@ (a colour set at the top), Flate-compressed.
grayStream :: Int -> ByteString
grayStream n = stream "/Filter /FlateDecode" (compressed (BS.concat (replicate (n `div` 4) "0 g\n")))

-- | The Form XObjects a page's content calls by the names Golem gives (docs/adr ADR 0051).
innerForms :: ImportedPage -> [ByteString]
innerForms p = [body | (_, OStream d body) <- ipObjects p, lookup "Subtype" d == Just (OName "Form")]

inflated :: ByteString -> ByteString
inflated = BL.toStrict . Z.decompress . BL.fromStrict

-- | A stream of @n@ bytes of NUL (white space in a content stream), Flate-compressed.
nulStream :: Int -> ByteString
nulStream n = stream "/Filter /FlateDecode" (zeros n)

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
(so that the real objects are not shadowed), @/Size@ the largest allowed.
-}
xrefStmRevisions :: Int -> Int -> ByteString
xrefStmRevisions rows revisions =
  let (body, offs) = layout "%PDF-1.5\n%\xE2\xE3\xCF\xD3\n" (onePage "<< >>" "0 0 1 1 re f")
      stmOff = BS.length body
      xref =
        stream
          ("/Type /XRef /Size 8388608 /W [1 4 2] /Index [10 " <> BC.pack (show rows) <> "] /Root 1 0 R /Filter /FlateDecode")
          (compressed (BS.replicate (7 * rows) 0))
      body2 = body <> objBytes (9, xref)
      table0 = "xref\n0 1\n0000000000 65535 f \n" <> BS.drop 5 (xrefTable offs) <> "trailer\n<< /Size 10 /Root 1 0 R >>\n"
      revision prev = "xref\n0 0\ntrailer\n<< /Size 10 /Root 1 0 R /XRefStm " <> BC.pack (show stmOff) <> " /Prev " <> BC.pack (show prev) <> " >>\n"
      go acc prev 0 = (acc, prev)
      go acc prev k = let off = BS.length acc in go (acc <> revision prev) off (k - 1 :: Int)
      (withRevisions, lastOff) = go (body2 <> table0) (BS.length body2) revisions
   in withRevisions <> "startxref\n" <> BC.pack (show lastOff) <> "\n%%EOF\n"

-- | One page whose cross-reference is a stream with the Index given; its rows are objects 0 to 4.
xrefIndexPdf :: ByteString -> ByteString
xrefIndexPdf index =
  let (body, offs) = layout "%PDF-1.5\n%\xE2\xE3\xCF\xD3\n" (onePage "<< >>" "0 0 1 1 re f")
      row t (o :: Int) = BS.pack ([t] <> [fromIntegral (o `shiftR` (8 * i)) | i <- [3, 2, 1, 0 :: Int]] <> [0, 0])
      rows = row 0 0 <> BS.concat [row 1 o | (_, o) <- offs]
      xref = stream ("/Type /XRef /Size 5 /W [1 4 2] /Index [" <> index <> "] /Root 1 0 R") rows
   in body <> objBytes (9, xref) <> "startxref\n" <> BC.pack (show (BS.length body)) <> "\n%%EOF\n"

-- ------------------------------------------------------------------ tests

tests :: TestTree
tests =
  testGroup
    "hostile PDF figures end within limits (security audit 2026-10-18, docs/adr ADR 0040)"
    [ localOption (mkTimeout (seconds 5))
        $ testCase "C1: a page tree that is a DAG of depth 24 is refused for the page tree at the node named twice"
        $ imported 2 (dagPdf 24) >>= refusedFor "ページの木",
      testCase "C1: a page named by two Kids is refused for the page tree" $ do
        let pdf =
              classicPdf
                ""
                [ catalog,
                  (2, "<< /Type /Pages /Kids [3 0 R 3 0 R] /Count 2 >>"),
                  (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Resources << >> /Contents 4 0 R >>"),
                  (4, stream "" "0 0 1 1 re f")
                ]
        imported 2 pdf >>= refusedFor "ページの木",
      testCase "C1: the walk ends at the page asked for" $ do
        -- the second kid is not a page tree node, but the walk ends before it
        let pdf =
              classicPdf
                ""
                [ catalog,
                  (2, "<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>"),
                  (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Resources << >> /Contents 4 0 R >>"),
                  (4, stream "" "0 0 1 1 re f"),
                  (5, "42")
                ]
        imported 1 pdf >>= readOk
        imported 2 pdf >>= refusedFor "ページの木",
      localOption (mkTimeout (seconds 10)) $
        testCase "C2: a literal string of 50000 short octal escapes is read in time and allocation linear in its length" $
          do
            let body = "BT (" <> BS.concat (replicate 50000 "\\1x") <> ") Tj ET"
                pdf = pageWith "" body
            (r, bytes) <- allocatedBy (imported 1 pdf)
            readOk r
            -- 150 KB of string: linear reading allocates some tens of MB (most of it the SHA-256
            -- of the file, about 150 bytes a byte), quadratic reading a few GB
            assertBool ("allocated " <> show bytes) (bytes < 512 * toInteger (BS.length body)),
      localOption (mkTimeout (seconds 60)) $
        testCase "C3: one stream of 8 MiB named 40 times in Contents is inflated once and written once (docs/adr ADR 0051)" $
          do
            let pdf = contentsOf (BC.unwords (replicate 40 "4 0 R")) [(4, nulStream (8 * mib))]
            (r, bytes) <- allocatedBy (imported 1 pdf)
            readOk r
            assertBool ("allocated " <> show bytes) (bytes < toInteger (300 * mib))
            p <- either (assertFailure . show) pure (importPage 1 pdf)
            ipContent p @?= BC.intercalate "\n" (replicate 40 "/GolemC4 Do")
            map (BS.length . inflated) (innerForms p) @?= [8 * mib],
      localOption (mkTimeout (seconds 60)) $
        testCase "C3: one stream of 8 MiB named 30 times in Contents counts 8 MiB" $
          do
            let pdf = contentsOf (BC.unwords (replicate 30 "4 0 R")) [(4, nulStream (8 * mib))]
            imported 1 pdf >>= (@?= Right (30 * BS.length "/GolemC4 Do" + 29, 1)),
      localOption (mkTimeout (seconds 120)) $
        testCase "C3: a stream of 8 MiB that sets the colour at the top, named 40 times, is ContentTooLarge (docs/adr ADR 0051)" $
          do
            let pdf = contentsOf (BC.unwords (replicate 40 "4 0 R")) [(4, grayStream (8 * mib))]
            (r, bytes) <- allocatedBy (imported 1 pdf)
            r @?= Left (ContentTooLarge (40 * 8 * mib + 39))
            assertBool ("allocated " <> show bytes) (bytes < toInteger (300 * mib)),
      localOption (mkTimeout (seconds 300)) $
        testCase "the joined content of a stream named 32 times is refused, of one named 31 times read (docs/adr ADR 0051)" $
          do
            let named k = contentsOf (BC.unwords (replicate k "4 0 R")) [(4, grayStream (8 * mib))]
            imported 1 (named 32) >>= (@?= Left (ContentTooLarge (32 * 8 * mib + 31)))
            -- not reused: the content is the streams joined
            imported 1 (named 31) >>= (@?= Right (31 * 8 * mib + 30, 0)),
      localOption (mkTimeout (seconds 120)) $
        testCase "C3: an ICC profile of 130 MiB named by two colour spaces is decoded once" $
          do
            -- decoded twice it would be 260 MiB, more than an import may decode
            let pdf =
                  classicPdf
                    ""
                    [ catalog,
                      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /ColorSpace << /A [/ICCBased 5 0 R] /B [/ICCBased 5 0 R] >> >> /Contents 4 0 R >>"),
                      (4, stream "" "/A cs 0 0 0 sc 0 0 1 1 re f"),
                      (5, stream "/N 3 /Filter /FlateDecode" (zeros (130 * mib)))
                    ]
            imported 1 pdf >>= readOk,
      localOption (mkTimeout (seconds 120)) $
        testCase "the total of two streams in Contents just over 256 MiB is refused" $
          do
            let pdf = contentsOf "4 0 R 5 0 R" [(4, nulStream (128 * mib)), (5, nulStream (128 * mib + 1))]
            imported 1 pdf >>= refusedFor tooLarge,
      localOption (mkTimeout (seconds 120)) $
        testCase "the total of two streams in Contents just under 256 MiB is read" $
          do
            let pdf = contentsOf "4 0 R 5 0 R" [(4, nulStream (128 * mib)), (5, nulStream (128 * mib - 1))]
            imported 1 pdf >>= (@?= Right (256 * mib, 0)),
      localOption (mkTimeout (seconds 10))
        $ testCase "C4: the TIFF predictor with Colors 65536 is refused for the predictor"
        $ imported 1 (pageWith "/Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 65536 /BitsPerComponent 8 /Columns 65536 >>" (zeros mib)) >>= refusedFor "予測子",
      testCase "C4: Colors 33, BitsPerComponent 3 and Columns 0 are refused for the predictor" $ do
        let parms p = pageWith ("/Filter /FlateDecode /DecodeParms << /Predictor 2 " <> p <> " >>") (zeros 16)
        imported 1 (parms "/Colors 33") >>= refusedFor "予測子"
        imported 1 (parms "/BitsPerComponent 3") >>= refusedFor "予測子"
        imported 1 (parms "/Columns 0") >>= refusedFor "予測子",
      localOption (mkTimeout (seconds 10))
        $ testCase "C4: the TIFF predictor with Colors 4 decodes 1 MiB in time linear in its length"
        $ imported 1 (pageWith "/Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 4 /BitsPerComponent 8 /Columns 65536 >>" (zeros mib)) >>= (@?= Right (mib, 0)),
      testCase "C4: the TIFF predictor adds the byte a pixel before" $ do
        -- 2 colours, 3 pixels a row: "0 " then twice 1 0 gives "0 1 2 "
        let pdf = pageWith "/Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 2 /Columns 3 >>" (compressed (BS.pack [48, 32, 1, 0, 1, 0]))
        fmap ipContent (importPage 1 pdf) @?= Right "0 1 2 ",
      localOption (mkTimeout (seconds 60)) $
        testCase "C5: Flate then ASCII85 of 80 MiB of z is refused before it expands to 320 MiB" $
          do
            let pdf = pageWith "/Filter [/FlateDecode /ASCII85Decode]" (compressed (BS.replicate (80 * mib) 122))
            (r, bytes) <- allocatedBy (imported 1 pdf)
            refusedFor tooLarge r
            assertBool ("allocated " <> show bytes) (bytes < toInteger (300 * mib)),
      localOption (mkTimeout (seconds 30)) $
        testCase "C6: a cross-reference stream of 4 million rows named by 4 revisions is decoded within bounds" $
          do
            let pdf = xrefStmRevisions 4000000 4
            (r, bytes) <- allocatedBy (imported 1 pdf)
            -- the rows are 28 MiB once; they should not be decoded four times over
            readOk r
            assertBool ("read, allocating " <> show bytes) (bytes < toInteger (256 * mib)),
      testCase "C6: more cross-reference entries than the largest object number are refused" $ do
        -- the table of the first revision has 5 entries, the stream the rest
        imported 1 (xrefStmRevisions 8388602 1) >>= readOk
        imported 1 (xrefStmRevisions 8388603 1) >>= refusedFor "相互参照",
      testCase "C6: a revision whose Prev is itself is read once" $ do
        let objs = onePage "<< >>" "0 0 1 1 re f"
            (body, _) = layout "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n" objs
        imported 1 (classicPdf ("/Prev " <> BC.pack (show (BS.length body))) objs) >>= readOk,
      testCase "C6: the subsections of a cross-reference stream are sorted and do not overlap" $ do
        imported 1 (xrefIndexPdf "0 5") >>= readOk
        imported 1 (xrefIndexPdf "0 2 2 3") >>= readOk
        imported 1 (xrefIndexPdf "0 3 2 2") >>= refusedFor "相互参照"
        imported 1 (xrefIndexPdf "2 3 0 2") >>= refusedFor "相互参照",
      localOption (mkTimeout (seconds 60)) $
        testCase "C7: a content stream of 16 MiB of tiny tokens is rewritten in allocation a few times its size" $
          do
            let body = BS.concat (replicate (4 * mib) "0 g\n")
                pdf = pageWith "/Filter /FlateDecode" (compressed body)
            (r, bytes) <- allocatedBy (imported 1 pdf)
            either (assertFailure . show) (\(c, _) -> c @?= BS.length body) r
            assertBool ("allocated " <> show bytes) (bytes < 16 * toInteger (BS.length body))
    ]
