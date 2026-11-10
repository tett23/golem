{- | The kinds of what the PDFs of the visual regression test use, against
the list of what the pinned shem reads, scripts/visual/pdf-subset.txt
(docs/adr ADR 0294). The kinds are the operators of the content streams
(of the pages and of the Form XObjects), the filters of the streams, the
families of the colour spaces, the @Subtype@ of the XObjects and the
@Subtype@ of the fonts. V1: no input uses a kind outside the list, so that
a Writer that starts to write what shem does not read fails here, before
shem renders it. V2: every kind of the list is used by some input.

The inputs are those of @scripts/visual/build.sh --list@, prepared and
built as build.sh does it (the profile dev, the crop marks of the two
inputs that have them); a name the test does not know fails it. The two
manuals are built with fonts of the fixtures in place of the fonts that
scripts/manual/fetch-fonts.sh fetches (the tests do not fetch): CFF
OpenType fonts as the fetched ones are, so that the kinds of their fonts
are the same.
-}
module VisualSubsetSpec (visualSubsetTests, Kind, kindsOfPdf, outsideOf, unusedOf, readSubset) where

import Codec.Compression.Zlib qualified as Z
import Control.Concurrent (forkIO, getNumCapabilities, newEmptyMVar, putMVar, takeMVar)
import Control.Concurrent.QSem (newQSem, signalQSem, waitQSem)
import Control.Exception (SomeException, bracket_, evaluate, throwIO, try)
import Control.Monad (forM, forM_, unless)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.Char (isDigit)
import Data.List (isInfixOf, isSuffixOf)
import Data.Map.Strict qualified as Map
import Data.Maybe (mapMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Driver
import Golem.Pdf.Import (contentOperations)
import Golem.Syntax (Diagnostic (..), isError)
import Support
import System.Directory (copyFile, createDirectoryIfMissing, doesFileExist)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

-- | A kind: what it is (operator, filter, colorspace, xobject, font) and its name.
type Kind = (BS.ByteString, BS.ByteString)

-- | The list, from the directory of golem-driver, where the tests run.
subsetFile :: FilePath
subsetFile = "../../scripts/visual/pdf-subset.txt"

visualSubsetTests :: TestTree
visualSubsetTests =
  testGroup
    "the PDFs of the visual regression test against scripts/visual/pdf-subset.txt (docs/adr ADR 0294)"
    [ withResource inputKinds (const (pure ())) $ \kinds ->
        testGroup
          "the inputs of scripts/visual/build.sh"
          [ testCase "V1: no input uses a kind outside scripts/visual/pdf-subset.txt" $ do
              ks <- kinds
              s <- readSubset subsetFile
              [(name, outsideOf s k) | (name, k) <- ks, not (null (outsideOf s k))] @?= [],
            testCase "V2: every kind of scripts/visual/pdf-subset.txt is used by an input" $ do
              ks <- kinds
              s <- readSubset subsetFile
              unusedOf s (map snd ks) @?= []
          ],
      testCase "V1 V2: a kind outside the list, and a kind of the list no input uses" $ do
        let s = Set.fromList [("operator", "q"), ("operator", "Q"), ("filter", "FlateDecode")]
            k = Set.fromList [("operator", "q"), ("operator", "Q"), ("operator", "sh")]
        outsideOf s k @?= [("operator", "sh")]
        unusedOf s [k] @?= [("filter", "FlateDecode")],
      testCase "the kinds of a PDF: operators of the pages and the forms, filters, colour spaces, XObjects and fonts" $ do
        let stream n dict body = BC.pack (show (n :: Int)) <> " 0 obj\n<< " <> dict <> " /Length " <> BC.pack (show (BS.length body)) <> " >>\nstream\n" <> body <> "\nendstream\nendobj\n"
            pdf =
              BS.concat
                [ "%PDF-1.7\n",
                  "1 0 obj\n<< /Type /Page /Contents 2 0 R /Resources << /XObject << /F 3 0 R /I 4 0 R >> /ColorSpace << /C [/Indexed 5 0 R 1 <0000>] >> /Font << /T 6 0 R >> >> >>\nendobj\n",
                  stream 2 "" "q /C cs 1 sc /F Do Q",
                  stream 3 "/Type /XObject /Subtype /Form" "0 0 m S",
                  stream 4 "/Type /XObject /Subtype /Image /ColorSpace /DeviceGray /Filter /DCTDecode" "\255\216",
                  "5 0 obj\n[/ICCBased 7 0 R]\nendobj\n",
                  "6 0 obj\n<< /Type /Font /Subtype /Type0 >>\nendobj\n",
                  stream 7 "/N 3" "x"
                ]
        got <- kindsOfPdf pdf
        got
          @?= Right
            ( Set.fromList
                [ ("operator", "q"),
                  ("operator", "cs"),
                  ("operator", "sc"),
                  ("operator", "Do"),
                  ("operator", "Q"),
                  ("operator", "m"),
                  ("operator", "S"),
                  ("filter", "DCTDecode"),
                  ("colorspace", "Indexed"),
                  ("colorspace", "ICCBased"),
                  ("colorspace", "DeviceGray"),
                  ("xobject", "Form"),
                  ("xobject", "Image"),
                  ("font", "Type0")
                ]
            )
    ]

-- | The kinds of the list that are not in the kinds of an input.
outsideOf :: Set Kind -> Set Kind -> [Kind]
outsideOf s k = Set.toAscList (k `Set.difference` s)

-- | The kinds of the list that no input uses.
unusedOf :: Set Kind -> [Set Kind] -> [Kind]
unusedOf s ks = Set.toAscList (s `Set.difference` Set.unions ks)

{- | The list: a kind on each line, @<what> <name>@; empty lines and lines
starting with @#@ are skipped.
-}
readSubset :: FilePath -> IO (Set Kind)
readSubset f = do
  ls <- BC.lines <$> BS.readFile f
  fmap Set.fromList . forM [l | l <- ls, not (BS.null l), not ("#" `BS.isPrefixOf` l)] $ \l -> case BC.words l of
    [w, n] | w `elem` ["operator", "filter", "colorspace", "xobject", "font"] -> pure (w, n)
    _ -> assertFailure ("pdf-subset.txt: not a kind: " <> BC.unpack l)

-- ------------------------------------------------------------------ the inputs

-- | Every input of build.sh, built, with the kinds of its PDF.
inputKinds :: IO [(String, Set Kind)]
inputKinds = do
  (code, out, err) <- readProcessWithExitCode "sh" ["../../scripts/visual/build.sh", "--list"] ""
  assertEqual err ExitSuccess code
  let names = lines out
  assertBool (show names) (length names >= 20)
  -- at most as many builds at the same time as there are capabilities, as build.sh does
  sem <- newQSem =<< getNumCapabilities
  vars <- forM names $ \name -> do
    v <- newEmptyMVar
    _ <- forkIO (bracket_ (waitQSem sem) (signalQSem sem) (try (inputKind name) >>= putMVar v))
    pure v
  forM vars $ \v -> takeMVar v >>= either (\(e :: SomeException) -> throwIO e) pure

-- | An input built, with the kinds of its PDF.
inputKind :: String -> IO (String, Set Kind)
inputKind name = withSystemTempDirectory "golem-visual-subset" $ \tmp -> do
  prepareInput name tmp
  -- the two inputs with crop marks, built with --marks japanese
  let marks = if "-marks-japanese" `isSuffixOf` name then JapaneseMarks else NoMarks
  r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf], optFonts = realProvider, optMarks = marks}
  assertEqual (name <> ": no errors") [] [(diagCode d, diagMessage d) | d <- brDiagnostics r, isError d]
  pdf <- case filter (".pdf" `isSuffixOf`) (brWritten r) of
    [p] -> BS.readFile p
    other -> assertFailure (name <> ": " <> show other)
  kindsOfPdf pdf >>= either (\e -> assertFailure (name <> ": " <> e)) (pure . (name,))

-- | An input of build.sh in a directory, as build.sh prepares it.
prepareInput :: String -> FilePath -> IO ()
prepareInput name tmp = case name of
  "sample" -> do
    fixtureWith "sample"
    copyFile "../../scripts/determinism/pdf-style.toml" (tmp </> "style.toml")
  "kanikosen" -> copyTree (fix "kanikosen") tmp
  "kanikosen-marks-japanese" -> do
    copyTree (fix "kanikosen") tmp
    withBleed
  "tempest" -> copyTree (fix "tempest") tmp
  "specimens-horizontal" -> fixtureWith "specimens/horizontal"
  "specimens-vertical" -> fixtureWith "specimens/vertical"
  "specimens-vertical-marks-japanese" -> do
    fixtureWith "specimens/vertical"
    withBleed
  "manual" -> manualInput
  "manual-dev" -> manualInput
  _
    | name `elem` ["figures", "complex-vertical", "complex-horizontal", "languages"] -> fixtureWith name
    | Just book <- T.stripPrefix "pd-" (T.pack name) -> pdBook (T.unpack book)
    | otherwise -> assertFailure ("build.sh has an input the test does not know: " <> name)
  where
    fix d = "test/fixtures" </> d
    -- a fixture with fonts/ja.otf and fonts/latin.otf (fonts in build.sh)
    fixtureWith d = do
      copyTree (fix d) tmp
      createDirectoryIfMissing True (tmp </> "fonts")
      copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/ja.otf")
      copyFile "../golem-font/test/fonts/SourceSansPro-Regular.otf" (tmp </> "fonts/latin.otf")
    -- bleed = "3mm" after [page], as the awk of build.sh writes it
    withBleed = do
      style <- TIO.readFile (tmp </> "style.toml")
      unless ("\n[page]\n" `T.isInfixOf` ("\n" <> style)) (assertFailure (name <> ": no [page] in style.toml"))
      TIO.writeFile (tmp </> "style.toml") (T.unlines (concatMap (\l -> if l == "[page]" then [l, "bleed = \"3mm\""] else [l]) (T.lines style)))
    -- the fonts of scripts/fixtures/copy-fonts.sh
    pdBook book = do
      copyTree (fix ("pd" </> book)) tmp
      createDirectoryIfMissing True (tmp </> "fonts")
      if book `elem` ["merry-wives", "frogs", "snark", "elements-of-style", "nightmare-abbey"]
        then copyFile "test/fixtures/tempest/fonts/SourceSerifVariable-Roman.ttf" (tmp </> "fonts/SourceSerifVariable-Roman.ttf")
        else copyFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "fonts/NotoSerifJP-Regular.otf")
    -- the manual with the build-info.gm of build.sh, a CFF font of the fixtures for each of its fonts
    manualInput = do
      copyTree ("../.." </> name) tmp
      createDirectoryIfMissing True (tmp </> "common")
      TIO.writeFile (tmp </> "common" </> "build-info.gm") "@set edition = \"v0.0.0-visual\"\n@set commit = \"0000000000000000000000000000000000000000\"\n@set uncommitted = \"\"\n"
      style <- TIO.readFile (tmp </> "style.toml")
      createDirectoryIfMissing True (tmp </> "fonts")
      let paths = [T.unpack p | l <- T.lines style, (_, rest) <- [T.breakOn "\"fonts/" l], not (T.null rest), let p = T.takeWhile (/= '"') (T.drop 1 rest)]
      assertBool (name <> ": the fonts of style.toml") (length paths >= 6)
      forM_ paths $ \p -> do
        there <- doesFileExist (tmp </> p)
        unless there $
          copyFile (if "JP" `isInfixOf` p then "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" else "../golem-font/test/fonts/SourceSansPro-Regular.otf") (tmp </> p)

-- ------------------------------------------------------------------ the kinds of a PDF

-- | An object of a PDF: its value and the data of its stream, if it has one.
data Obj = Obj {objValue :: PdfValue, objStream :: Maybe BS.ByteString}

{- | The objects of a PDF that Golem writes (no object streams), by number,
as 'pdfObjects' reads them, with the data of their streams: /Length bytes
after @stream@ and its end of line.
-}
objectsOf :: BS.ByteString -> Map.Map Int Obj
objectsOf pdf = Map.fromList (go pdf)
  where
    go b = case BS.breakSubstring " 0 obj" b of
      (before, rest)
        | BS.null rest -> []
        | otherwise ->
            let num = BC.reverse (BC.takeWhile isDigit (BC.reverse before))
                atLineStart = maybe True ((`elem` ("\r\n" :: String)) . snd) (BC.unsnoc (BS.take (BS.length before - BS.length num) before))
                body = BS.drop (BS.length " 0 obj") rest
                text = fst (BS.breakSubstring "endobj" body)
                (dictText, streamPart) = BS.breakSubstring "stream" text
             in case (BC.readInt num, pdfValue (pdfTokens dictText)) of
                  (Just (n, _), Just (v, _)) | not (BS.null num), atLineStart ->
                    let afterKw = BS.drop (BS.length "stream") (snd (BS.breakSubstring "stream" body))
                        dataStart = if "\r\n" `BS.isPrefixOf` afterKw then BS.drop 2 afterKw else BS.drop 1 afterKw
                        len = case lookup "/Length" (dictOf v) of
                          Just (PdfAtom l) | Just (k, "") <- BC.readInt l -> Just k
                          _ -> Nothing
                     in case (BS.null streamPart, len) of
                          (True, _) -> (n, Obj v Nothing) : go body
                          (False, Just k) -> (n, Obj v (Just (BS.take k dataStart))) : go (BS.drop k dataStart)
                          (False, Nothing) ->
                            let d = fst (BS.breakSubstring "endstream" dataStart)
                             in (n, Obj v (Just (fst (BC.spanEnd (`elem` ("\r\n" :: String)) d)))) : go (BS.drop (BS.length d) dataStart)
                  _ -> go body

dictOf :: PdfValue -> [(BS.ByteString, PdfValue)]
dictOf = \case
  PdfDict kvs -> kvs
  _ -> []

-- | A name without its slash.
nameOf :: PdfValue -> Maybe BS.ByteString
nameOf = \case
  PdfAtom a | Just ('/', n) <- BC.uncons a -> Just n
  _ -> Nothing

-- | The kinds of a PDF, or why they cannot be read.
kindsOfPdf :: BS.ByteString -> IO (Either String (Set Kind))
kindsOfPdf pdf = do
  let objs = objectsOf pdf
  -- the content streams, inflated
  contents <- forM (contentRefs objs) $ \n -> case Map.lookup n objs of
    Nothing -> pure (Left ("no object " <> show n))
    Just o -> case (objStream o, filtersOf objs (dictOf (objValue o))) of
      (Nothing, _) -> pure (Left ("object " <> show n <> " is not a stream"))
      (Just raw, []) -> pure (Right (n, raw))
      (Just raw, ["FlateDecode"]) -> do
        r <- try (evaluate (BL.toStrict (Z.decompress (BL.fromStrict raw))))
        pure (either (\(_ :: SomeException) -> Left ("object " <> show n <> ": a Flate stream that does not inflate")) (Right . (n,)) r)
      (Just _, fs) -> pure (Left ("object " <> show n <> ": a content stream with the filters " <> show fs))
  pure (kindsOf objs =<< sequence contents)

-- | The value of an object reference, the value itself otherwise.
resolveIn :: Map.Map Int Obj -> PdfValue -> PdfValue
resolveIn objs = \case
  PdfRef n -> maybe (PdfAtom "null") objValue (Map.lookup n objs)
  v -> v

-- | Every dictionary of the objects, nested ones too.
dictsOf :: Map.Map Int Obj -> [[(BS.ByteString, PdfValue)]]
dictsOf objs = concatMap (nested . objValue) (Map.elems objs)
  where
    nested = \case
      PdfDict kvs -> kvs : concatMap (nested . snd) kvs
      PdfArray vs -> concatMap nested vs
      _ -> []

nameAt :: BS.ByteString -> [(BS.ByteString, PdfValue)] -> Maybe BS.ByteString
nameAt k d = nameOf =<< lookup ("/" <> k) d

-- | The content streams: the /Contents of the pages and the Form XObjects.
contentRefs :: Map.Map Int Obj -> [Int]
contentRefs objs =
  concat
    [ case lookup "/Contents" d of
        Just (PdfRef n) -> [n]
        Just (PdfArray rs) -> [n | PdfRef n <- rs]
        _ -> []
    | d <- dictsOf objs,
      nameAt "Type" d == Just "Page"
    ]
    <> [n | (n, o) <- Map.toList objs, nameAt "Subtype" (dictOf (objValue o)) == Just "Form"]

filtersOf :: Map.Map Int Obj -> [(BS.ByteString, PdfValue)] -> [BS.ByteString]
filtersOf objs d = case resolveIn objs <$> lookup "/Filter" d of
  Just (PdfArray fs) -> mapMaybe (nameOf . resolveIn objs) fs
  Just f -> maybe [] pure (nameOf f)
  Nothing -> []

-- | The kinds of the objects of a PDF and of its content streams, inflated.
kindsOf :: Map.Map Int Obj -> [(Int, BS.ByteString)] -> Either String (Set Kind)
kindsOf objs contents = do
  operations <- forM contents $ \(n, content) ->
    maybe (Left ("object " <> show n <> ": a broken content stream")) Right (contentOperations content)
  let resolve = resolveIn objs
      dicts = dictsOf objs
      -- the families of a colour space, and those of the spaces it is based on
      families :: Int -> PdfValue -> [BS.ByteString]
      families depth v
        | depth > 4 = []
        | otherwise = case resolve v of
            PdfArray (h : rest) -> case nameOf (resolve h) of
              Just "Indexed" | base : _ <- rest -> "Indexed" : families (depth + 1) base
              Just f | f `elem` ["Separation", "DeviceN"], _ : alt : _ <- rest -> f : families (depth + 1) alt
              Just f -> [f]
              Nothing -> []
            a -> maybe [] pure (nameOf a)
      spaces =
        concat
          [ case resolve sp of
              PdfDict spaceDict | k == "/ColorSpace" -> concatMap (families 0 . snd) spaceDict
              other -> families 0 other
          | d <- dicts,
            (k, sp) <- d,
            k `elem` ["/ColorSpace", "/CS"]
          ]
      -- a colour space named in a content stream: a device one
      named = [f | ops <- operations, (op, [a]) <- ops, op `elem` ["cs", "CS"], Just f <- [nameOf (PdfAtom a)], f `elem` ["DeviceGray", "DeviceRGB", "DeviceCMYK", "Pattern"]]
      xobjects =
        [ s
        | d <- dicts,
          Just xs <- [resolve <$> lookup "/XObject" d],
          (_, x) <- dictOf xs,
          Just s <- [nameAt "Subtype" (dictOf (resolve x))]
        ]
      fonts = [s | d <- dicts, nameAt "Type" d == Just "Font", Just s <- [nameAt "Subtype" d]]
  pure . Set.fromList $
    [("operator", op) | ops <- operations, (op, _) <- ops]
      <> [("filter", f) | o <- Map.elems objs, Just _ <- [objStream o], f <- filtersOf objs (dictOf (objValue o))]
      <> [("colorspace", f) | f <- spaces <> named]
      <> [("xobject", s) | s <- xobjects]
      <> [("font", s) | s <- fonts]
