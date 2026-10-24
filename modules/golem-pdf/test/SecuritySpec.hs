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
tests = testGroup "security" [tests2018, auditTests]

tests2018 :: TestTree
tests2018 =
  testGroup
    "hostile PDF figures end within limits (security audit 2026-10-18, docs/adr ADR 0040)"
    [ localOption (mkTimeout (seconds 30))
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
      localOption (mkTimeout (seconds 30)) $
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
      -- Two streams in Contents that decode to 256 MiB together join to
      -- 256 MiB and one byte, beyond the joined content's own limit (docs/adr
      -- ADR 0051); the third byte is a form's, so that the joined content is
      -- 256 MiB and the decoded total exactly 256 MiB (docs/adr ADR 0068).
      localOption (mkTimeout (seconds 120)) $
        testCase "a total of exactly 256 MiB decoded is read (docs/adr ADR 0068)" $
          do
            let pdf =
                  classicPdf
                    ""
                    [ catalog,
                      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
                      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /XObject << /F 6 0 R >> >> /Contents [4 0 R 5 0 R] >>"),
                      (4, nulStream (128 * mib)),
                      (5, nulStream (128 * mib - 1)),
                      (6, stream "/Type /XObject /Subtype /Form /BBox [0 0 1 1] /Filter /FlateDecode" (zeros 1))
                    ]
            imported 1 pdf >>= (@?= Right (256 * mib, 1)),
      localOption (mkTimeout (seconds 30))
        $ testCase "C4: the TIFF predictor with Colors 65536 is refused for the predictor"
        $ imported 1 (pageWith "/Filter /FlateDecode /DecodeParms << /Predictor 2 /Colors 65536 /BitsPerComponent 8 /Columns 65536 >>" (zeros mib)) >>= refusedFor "予測子",
      testCase "C4: Colors 33, BitsPerComponent 3 and Columns 0 are refused for the predictor" $ do
        let parms p = pageWith ("/Filter /FlateDecode /DecodeParms << /Predictor 2 " <> p <> " >>") (zeros 16)
        imported 1 (parms "/Colors 33") >>= refusedFor "予測子"
        imported 1 (parms "/BitsPerComponent 3") >>= refusedFor "予測子"
        imported 1 (parms "/Columns 0") >>= refusedFor "予測子",
      localOption (mkTimeout (seconds 30))
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

-- ------------------------------------------------------------------ security audit 2026-10-24

{- | A PDF whose cross-reference is one stream (@/W [1 4 2]@) over objects 0
to the largest: the objects in the file at their offsets, and the objects
in object streams as (number, stream, index).
-}
xrefStreamPdf :: [(Int, ByteString)] -> [(Int, Int, Int)] -> ByteString
xrefStreamPdf inFile inStreams =
  let (body, offs) = layout "%PDF-1.5\n%\xE2\xE3\xCF\xD3\n" inFile
      xrefNum = maximum (map fst inFile <> [n | (n, _, _) <- inStreams]) + 1
      size = xrefNum + 1
      be k (x :: Int) = BS.pack [fromIntegral (x `shiftR` (8 * i)) | i <- reverse [0 .. k - 1]]
      row n
        | Just o <- lookup n offs = BS.singleton 1 <> be 4 o <> be 2 0
        | (s, i) : _ <- [(s, i) | (m, s, i) <- inStreams, m == n] = BS.singleton 2 <> be 4 s <> be 2 i
        | n == xrefNum = BS.singleton 1 <> be 4 (BS.length body) <> be 2 0
        | otherwise = BS.singleton 0 <> be 4 0 <> be 2 0
      rows = BS.concat (map row [0 .. xrefNum])
      xref = stream ("/Type /XRef /Size " <> BC.pack (show size) <> " /W [1 4 2] /Root 1 0 R") rows
   in body <> objBytes (xrefNum, xref) <> "startxref\n" <> BC.pack (show (BS.length body)) <> "\n%%EOF\n"

-- | An object stream of the objects given (number and offset are computed), with the dictionary entries given.
objStm :: ByteString -> [(Int, ByteString)] -> ByteString
objStm dict objs =
  let bodies = map snd objs
      offsets = scanl (+) 0 (map ((+ 1) . BS.length) bodies)
      header = BS.concat [BC.pack (show n) <> " " <> BC.pack (show o) <> " " | ((n, _), o) <- zip objs offsets]
      content = header <> BS.concat [b <> "\n" | b <- bodies]
   in stream ("/Type /ObjStm /N " <> BC.pack (show (length objs)) <> " /First " <> BC.pack (show (BS.length header)) <> " " <> dict) content

-- | A page tree whose Kids are references to arrays of two direct nodes that name the next array.
arrayKidsPdf :: Int -> ByteString
arrayKidsPdf depth =
  classicPdf "" $
    [catalog, (2, "<< /Type /Pages /Kids 10 0 R /Count 1 >>")]
      <> [(10 + k, "[<< /Type /Pages /Kids " <> ref (11 + k) <> " >> << /Type /Pages /Kids " <> ref (11 + k) <> " >>]") | k <- [0 .. depth - 1]]
      <> [(10 + depth, "[]")]
  where
    ref n = BC.pack (show n) <> " 0 R"

{- | One page whose resources name an array of @n@ font dictionaries, each
with the same descriptor, an object in the file of @pad@ numbers.
-}
sharedDescriptorPdf :: Int -> Int -> ByteString
sharedDescriptorPdf n pad =
  classicPdf
    ""
    [ catalog,
      (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
      (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << /Extra 5 0 R >> /Contents 4 0 R >>"),
      (4, stream "" "0 0 1 1 re f"),
      (5, "[" <> BS.concat (replicate n "<< /Type /Font /Subtype /Type1 /FontDescriptor 6 0 R >> ") <> "]"),
      (6, "<< /Type /FontDescriptor /FontFile 7 0 R /Pad [" <> BS.concat (replicate pad "0 ") <> "] >>"),
      (7, stream "" "font")
    ]

{- | One page whose catalog and pages are in an object stream with @n@ more
pairs that all name the offset of one array of @pad@ numbers.
-}
sharedOffsetPdf :: Int -> Int -> ByteString
sharedOffsetPdf n pad =
  let big = "[" <> BS.concat (replicate pad "0 ") <> "]"
      objs = [(1, "<< /Type /Catalog /Pages 2 0 R >>"), (2, "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"), (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Resources << >> /Contents 4 0 R >>"), (100, big)]
      bodies = map snd objs
      offsets = scanl (+) 0 (map ((+ 1) . BS.length) bodies)
      bigOff = offsets !! 3
      pairs = [(k, o) | ((k, _), o) <- zip objs offsets] <> [(200 + i, bigOff) | i <- [1 .. n]]
      header = BS.concat [BC.pack (show k) <> " " <> BC.pack (show o) <> " " | (k, o) <- pairs]
      content = header <> BS.concat [b <> "\n" | b <- bodies]
      stm = stream ("/Type /ObjStm /N " <> BC.pack (show (length pairs)) <> " /First " <> BC.pack (show (BS.length header)) <> " /Filter /FlateDecode") (compressed content)
   in xrefStreamPdf [(4, stream "" "0 0 1 1 re f"), (6, stm)] ([(1, 6, 0), (2, 6, 1), (3, 6, 2), (100, 6, 3)] <> [(200 + i, 6, 3 + i) | i <- [1 .. n]])

-- | The allocation of importing the page of a PDF.
allocationOf :: ByteString -> IO Integer
allocationOf pdf = do
  _ <- evaluate (BS.length pdf)
  (r, bytes) <- allocatedBy (imported 1 pdf)
  readOk r
  pure bytes

auditTests :: TestTree
auditTests =
  testGroup
    "hostile PDF figures of the security audit of 2026-10-24"
    [ localOption (mkTimeout (seconds 30)) $
        testCase "an object stream whose Filter is an object in itself is refused for the object stream" $ do
          let stm = objStm "/Filter 5 0 R" [(1, "<< /Type /Catalog /Pages 2 0 R >>"), (5, "/FlateDecode")]
          imported 1 (xrefStreamPdf [(4, stm)] [(1, 4, 0), (5, 4, 1)]) >>= refusedFor "オブジェクトのストリーム",
      localOption (mkTimeout (seconds 30)) $
        testCase "two object streams whose Filters are objects in each other are refused for the object stream" $ do
          let a = objStm "/Filter 7 0 R" [(1, "<< /Type /Catalog /Pages 2 0 R >>"), (5, "/FlateDecode")]
              b = objStm "/Filter 5 0 R" [(7, "/FlateDecode")]
          imported 1 (xrefStreamPdf [(4, a), (6, b)] [(1, 4, 0), (5, 4, 1), (7, 6, 0)]) >>= refusedFor "オブジェクトのストリーム",
      localOption (mkTimeout (seconds 30))
        $ testCase "Kids that are references to arrays named twice, 30 deep, are refused for the page tree"
        $ imported 1 (arrayKidsPdf 30) >>= refusedFor "ページの木",
      testCase "Kids that are a reference to an array named once are read" $ do
        let pdf =
              classicPdf
                ""
                [ catalog,
                  (2, "<< /Type /Pages /Kids 5 0 R /Count 1 >>"),
                  (5, "[3 0 R]"),
                  (3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Resources << >> /Contents 4 0 R >>"),
                  (4, stream "" "0 0 1 1 re f")
                ]
        imported 1 pdf >>= readOk,
      localOption (mkTimeout (seconds 60)) $
        testCase "200 font dictionaries naming one descriptor in the file parse it once" $ do
          one <- allocationOf (sharedDescriptorPdf 1 (256 * 1024))
          many <- allocationOf (sharedDescriptorPdf 200 (256 * 1024))
          assertBool ("allocated " <> show many <> " for 200, " <> show one <> " for 1") (many < 2 * one),
      localOption (mkTimeout (seconds 60)) $
        testCase "200 pairs of an object stream at one offset parse the object there once" $ do
          one <- allocationOf (sharedOffsetPdf 1 (256 * 1024))
          many <- allocationOf (sharedOffsetPdf 200 (256 * 1024))
          assertBool ("allocated " <> show many <> " for 200, " <> show one <> " for 1") (many < 2 * one)
    ]
