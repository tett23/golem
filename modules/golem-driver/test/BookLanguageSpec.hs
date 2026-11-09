{- | The words outside a language span are hyphenated by the language of
the book (docs/adr ADR 0276): F4, a paragraph outside a span is set as in
a span of the language of the book; F5, the exceptions of the book are
looked up by that language; F7, the HTML, the EPUB and the plain text do
not change.
-}
module BookLanguageSpec (bookLanguageTests) where

import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.List (isSuffixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Word (Word8)
import Golem.Driver
import Golem.Layout.KnuthPlass (BoxContent (..), Hyphen (..), Item (..), Leaf (..), Line (..))
import Golem.Layout.Look (Look (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Pdf.Sha256 (sha256)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), SetLine (..), layoutPdf)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | The manifest.toml of a project with the language of the book replaced.
setLanguage :: FilePath -> Text -> IO ()
setLanguage tmp l = do
  m <- TIO.readFile (tmp </> "manifest.toml")
  TIO.writeFile (tmp </> "manifest.toml") (T.replace "language = \"ja\"" ("language = \"" <> l <> "\"") m)

-- | The items of the lines of the chapters, in a book of a language.
linesIn :: Text -> BS.ByteString -> [(FilePath, Text)] -> IO [[Item]]
linesIn l style chapters = withChapters (withBodyFont style) chapters [] $ \tmp -> do
  setLanguage tmp l
  writeFiles tmp fakeFontFiles
  ev <- evaluateProject Dev tmp
  e <- either (assertFailure . show . pfDiagnostics) pure ev
  book <- case (evBook e, filter isError (evDiagnostics e)) of
    (Just b, []) -> pure b
    (_, errs) -> assertFailure (show [(diagCode d, diagMessage d) | d <- errs])
  geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False (evStyle e))
  r <- layoutPdf (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)) geom fakeFonts
  pl <- either (assertFailure . show) pure r
  pure [lineItems (slLine sl) | sl <- Map.elems (plLines pl)]

-- | The texts of the boxes of each line.
texts :: [[Item]] -> [Text]
texts = map (\its -> T.concat [bcText c | Box _ c <- its])

{- | An item without where its characters are in the source, the language
of its look, nor its leaf of the structure tree of the PDF: a language
span is an element of the tree of its own (docs/adr ADR 0187), and the
leaves after it are numbered past it.
-}
plain :: Item -> Item
plain = \case
  Box w c -> Box w c {bcSource = (fst (bcSource c), mkSpan (FileId 0) 0 0), bcAt = 0, bcLook = (bcLook c) {lkLang = Nothing}, bcLeaf = (bcLeaf c) {leafIndex = 0}}
  x -> x

-- | The texts of the boxes before each penalty of a hyphen of the patterns.
hyphensOf :: [[Item]] -> [Text]
hyphensOf ls = [bcText c | its <- ls, (Box _ c, Penalty _ _ (PatternHyphen _)) <- zip its (drop 1 its)]

-- | French words longer than a line of 12 characters.
french :: Text
french = "typographie élémentaire dictionnaire imprimerie connaissance proverbe"

-- | A word of 32 letters, wider than a line, which no patterns break.
word :: Text
word = T.replicate 32 "x"

-- | style.toml with a list of exceptions of a language.
withList :: Text -> BS.ByteString
withList l = horizontalStyle <> "\n[composition.hyphenation-exceptions]\n" <> encode l <> " = [\"" <> encode (T.replicate 16 "x" <> "-" <> T.replicate 16 "x") <> "\"]\n"
  where
    encode = BS.pack . map (fromIntegral . fromEnum) . T.unpack

-- | The SHA-256 of the files written for a target of the sample book in a language, by their names.
webDigests :: Text -> Target -> IO [(FilePath, Text)]
webDigests l target = withSystemTempDirectory "golem-lang" $ \tmp -> do
  copyTree fixture tmp
  setLanguage tmp l
  r <- build (defaultOptions tmp) {optTargets = Just [target], optProfile = Dev}
  assertEqual "diagnostics" [] (map diagCode (filter isError (brDiagnostics r)))
  sort <$> mapM (\p -> (,) (drop (length tmp) p) . hex . sha256 <$> BS.readFile p) [p | p <- brWritten r, not ("/" `isSuffixOf` p)]

hex :: BS.ByteString -> Text
hex = T.pack . concatMap byte . BS.unpack
  where
    byte :: Word8 -> String
    byte b = [intToDigit (fromIntegral (b `div` 16)), intToDigit (fromIntegral (b `mod` 16))]

bookLanguageTests :: TestTree
bookLanguageTests =
  testGroup
    "the words outside a span by the language of the book (docs/adr ADR 0276)"
    [ testCase "F4: in a book of fr, a paragraph outside a span is set as the same paragraph in [lang fr]" $ do
        outside <- linesIn "fr" horizontalStyle [("a.gm", french <> "\n")]
        inside <- linesIn "fr" horizontalStyle [("a.gm", "[lang fr: " <> french <> "]\n")]
        map (map plain) outside @?= map (map plain) inside
        -- the hyphens of the patterns of the items are not those of US English
        ja <- linesIn "ja" horizontalStyle [("a.gm", french <> "\n")]
        assertBool "the French patterns, not the English ones" (hyphensOf outside /= hyphensOf ja),
      testCase "F4: in a book of ja, a paragraph outside a span is set by US English, as before" $ do
        ja <- linesIn "ja" horizontalStyle [("a.gm", french <> "\n")]
        en <- linesIn "ja" horizontalStyle [("a.gm", "[lang en-US: " <> french <> "]\n")]
        map (map plain) ja @?= map (map plain) en,
      testCase "F5: in a book of fr, the list of fr breaks a word outside a span; in a book of ja it does not" $ do
        fr <- linesIn "fr" (withList "fr") [("a.gm", word <> "\n")]
        texts fr @?= [T.replicate 16 "x", T.replicate 16 "x"]
        ja <- linesIn "ja" (withList "fr") [("a.gm", word <> "\n")]
        texts ja @?= [word]
        en <- linesIn "fr" (withList "en") [("a.gm", word <> "\n")]
        texts en @?= [word],
      testCase "F7: the HTML, the EPUB and the plain text of a book of fr are the bytes before docs/adr ADR 0276" $ do
        html <- webDigests "fr" TargetHtml
        epub <- webDigests "fr" TargetEpub
        txt <- webDigests "fr" TargetText
        html
          @?= [ ("/build/html/chapters/01.xhtml", "fae711aa882d844c642cdfa3cfd2f2792e6659134a200634b1007490df691de7"),
                ("/build/html/chapters/02.xhtml", "fd2f8c139b35404f882ba78a6c6b7fec3b0ab25a775854094c74ed8a97d0be43"),
                ("/build/html/front.xhtml", "2ef2a685a52ce79fda2f11c003970101dbbadc156a825d81c9aaae98025f1959"),
                ("/build/html/index.xhtml", "e47c4d4a58811c0318da4a766c453badccd836ad606c0b518807c1ab107566a6"),
                ("/build/html/style.css", "3360b21aaa4acb000f05be9fb92cac49ef48b6277ee0eeb9e7a81115a173bb00")
              ]
        epub
          @?= [ ("/build/epub/book.epub", "88f8e8e8a0709a526115f62352ffacdd33e8ea1b7e27b775935bdf026bc91241")
              ]
        txt
          @?= [ ("/build/text/horizontal/chapters/01.txt", "969d7ea922c84ec6b81c466962dd39d47d395be6d1f8c45de196c50ad588d56c"),
                ("/build/text/horizontal/chapters/02.txt", "42cd748171bebfc517af6c24202ec5987ded668627ea6396641a0e768b283b9c"),
                ("/build/text/horizontal/front.txt", "23e6cbdf66541ff247c98314aede9de5c547e341cd17500b36e52c1beec32057"),
                ("/build/text/vertical/chapters/01.txt", "e852e9ded944db6ee54b9ef68791f21f85bd24e52ec32d86a8dddb0ec4079041"),
                ("/build/text/vertical/chapters/02.txt", "42cd748171bebfc517af6c24202ec5987ded668627ea6396641a0e768b283b9c"),
                ("/build/text/vertical/front.txt", "23e6cbdf66541ff247c98314aede9de5c547e341cd17500b36e52c1beec32057")
              ]
    ]
