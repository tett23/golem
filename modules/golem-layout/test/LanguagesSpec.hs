{- | The patterns of the language of a word (docs/adr ADR 0276): the table
of the bundled patterns looked up by RFC 4647, the words outside a span
by the language of the book, and the bundled files as hyph-utf8 has them.
-}
module LanguagesSpec (languagesTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Char (intToDigit)
import Data.List (nub, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Word (Word8)
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Hyphenation (hyphenMins, hyphenate)
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Hyphenation.Languages
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Syntax.Sha256 (sha256)
import Test.Tasty
import Test.Tasty.HUnit

none :: Map Text [Text]
none = Map.empty

-- | The bundled patterns of a tag, by the name of their hyph-utf8 file; Nothing for none.
expectedNames :: [(Maybe Text, Maybe Text)]
expectedNames =
  [ (Nothing, Just "en-us"),
    (Just "en", Just "en-us"),
    (Just "en-US", Just "en-us"),
    (Just "en-us", Just "en-us"),
    (Just "en-GB", Just "en-gb"),
    (Just "en-AU", Just "en-us"),
    (Just "fr", Just "fr"),
    (Just "fr-CA", Just "fr"),
    (Just "de", Just "de-1996"),
    (Just "de-1901", Just "de-1996"),
    (Just "de-CH", Just "de-1996"),
    (Just "de-CH-1901", Just "de-1996"),
    (Just "es", Just "es"),
    (Just "it", Just "it"),
    (Just "pt", Just "pt"),
    (Just "pt-BR", Just "pt"),
    (Just "nl", Just "nl"),
    (Just "ja", Nothing),
    (Just "ru", Nothing),
    (Just "zh", Nothing)
  ]

-- | The tag of the words outside a span, by the language of the book.
expectedOutside :: [(Text, Text)]
expectedOutside = [("ja", "en-US"), ("", "en-US"), ("zh", "en-US"), ("en", "en"), ("en-GB", "en-GB"), ("fr", "fr"), ("de", "de")]

-- | The tag of Golem for each language of showhyphens.tex.
texTags :: [(Text, Text)]
texTags = [("enus", "en-US"), ("engb", "en-GB"), ("fr", "fr"), ("de1996", "de"), ("es", "es"), ("it", "it"), ("pt", "pt"), ("nl", "nl")]

-- | The words TeX hyphenated (test/data/hyphenation/showhyphens.txt), as (tag, the parts of the word).
texWords :: IO [(Text, [Text])]
texWords = do
  src <- TE.decodeUtf8 <$> BS.readFile "test/data/hyphenation/showhyphens.txt"
  pure [(fromMaybe tag (lookup tag texTags), T.splitOn "-" w) | l <- T.lines src, [tag, w] <- [T.splitOn "\t" l]]

-- | The SHA-256 of the files, from the table of data/hyphenation/README.md.
readmeDigests :: IO [(FilePath, Text)]
readmeDigests = do
  src <- TE.decodeUtf8 <$> BS.readFile "data/hyphenation/README.md"
  pure (mapMaybe row (T.lines src))
  where
    row l = case map T.strip (T.splitOn "|" l) of
      ["", f, h, ""]
        | T.length h == 66 -> Just (T.unpack (unquote f), unquote h)
      _ -> Nothing
    unquote = T.dropAround (== '`')

hex :: BS.ByteString -> Text
hex = T.pack . concatMap byte . BS.unpack
  where
    byte :: Word8 -> String
    byte b = [intToDigit (fromIntegral (b `div` 16)), intToDigit (fromIntegral (b `mod` 16))]

-- | The files of data/hyphenation/ but its README: the patterns, the exceptions and the licence of each language.
bundledFiles :: [FilePath]
bundledFiles =
  concat
    [ ["hyph-" <> l <> ".pat.txt", "LICENSE-hyph-" <> l <> ".txt"] <> ["hyph-" <> l <> ".hyp.txt" | l `elem` ["en-us", "en-gb", "pt", "nl"]]
    | l <- ["en-us", "en-gb", "fr", "de-1996", "es", "it", "pt", "nl"]
    ]

lang :: Text -> [IR.Inline] -> IR.Inline
lang = IR.Lang sp

t :: Text -> IR.Inline
t = IR.Text sp

-- | The composition of a book of a language, without exceptions of the book.
inBook :: Text -> ComposeEnv
inBook book = (defaultComposeEnv fs) {cePatterns = exceptionPatterns book none none}

-- | The texts of the boxes of the items.
texts :: ComposeEnv -> [IR.Inline] -> [Text]
texts e is = [bcText c | Box _ c <- fst (composeInlines e is)]

{- | The items without the language of the look of their boxes, nor their
leaf of the structure tree of the PDF: a language span is an element of
the tree of its own (docs/adr ADR 0187), and the leaves in it are
numbered past it.
-}
withoutLang :: [Item] -> [Item]
withoutLang = map $ \case
  Box w c -> Box w c {bcLook = (bcLook c) {lkLang = Nothing}, bcLeaf = (bcLeaf c) {leafIndex = 0}}
  x -> x

languagesTests :: TestTree
languagesTests =
  testGroup
    "the patterns of the language of a word (docs/adr ADR 0276)"
    [ testCase "F1: patternsFor looks the tag up in the table, and none for a language not in it" $ do
        map (patternsNameFor . fst) expectedNames @?= map snd expectedNames
        map (isJust . patternsFor . fst) expectedNames @?= map (isJust . snd) expectedNames,
      testCase "F1: the words outside a span take the language of the book when the table has it, US English otherwise" $ do
        map (outsideSpanTag . fst) expectedOutside @?= map snd expectedOutside
        map (patternsNameFor . Just . outsideSpanTag) ["fr", "ja", "de-CH", "pt-BR", ""] @?= map Just ["fr", "en-us", "de-1996", "pt", "en-us"],
      testCase "F1: the letters kept before and after a break are those of hyph-utf8" $
        [(n, hyphenMins <$> patternsFor (Just n)) | n <- ["en-US", "en-GB", "fr", "de", "es", "it", "pt", "nl"]]
          @?= [("en-US", Just (2, 3)), ("en-GB", Just (2, 3)), ("fr", Just (2, 2)), ("de", Just (2, 2)), ("es", Just (2, 2)), ("it", Just (2, 2)), ("pt", Just (2, 3)), ("nl", Just (2, 2))],
      testCase "F2: each word breaks where TeX's \\showhyphens broke it with the same patterns" $ do
        ws <- texWords
        sort (nub (map fst ws)) @?= sort (map snd texTags)
        length ws @?= 61
        forM_ ws $ \(l, parts) -> case patternsFor (Just l) of
          Nothing -> assertFailure ("no patterns for " <> T.unpack l)
          Just p -> assertEqual (T.unpack l <> " " <> T.unpack (T.concat parts)) parts (hyphenate p (T.concat parts)),
      testCase "F2: [lang fr: proverbe] breaks where TeX breaks it by the French patterns; [lang ja: proverbe] does not break" $ do
        let env = (defaultComposeEnv fs) {cePatterns = patternsFor}
        texts env [lang "fr" [t "proverbe"]] @?= ["pro", "verbe"]
        texts env [lang "de" [t "silbentrennung"]] @?= ["sil", "ben", "tren", "nung"]
        texts env [lang "ja" [t "proverbe"]] @?= ["proverbe"]
        texts env [lang "ru" [t "proverbe"]] @?= ["proverbe"],
      testCase "F2: the US English patterns break British words otherwise than the British ones" $ do
        let env = (defaultComposeEnv fs) {cePatterns = patternsFor}
        texts env [lang "en-GB" [t "hyphenation"]] @?= ["hy", "phen", "a", "tion"]
        texts env [lang "en-US" [t "hyphenation"]] @?= ["hy", "phen", "ation"],
      testCase "F3: a book of ja, or of no language, sets the words outside a span and those of en and en-US as before" $
        forM_ ["ja", "", "zh"] $ \book ->
          forM_ [Nothing, Just "en", Just "en-US"] $ \l ->
            forM_ ["hyphenation", "typesetting", "proverbe", "table", "project"] $ \w ->
              assertEqual (show (book, l, w)) (hyphenate englishUS w) (maybe [w] (`hyphenate` w) (exceptionPatterns book none none l)),
      testCase "F4: in a book of fr, a paragraph outside a span has the items of the same paragraph in [lang fr], but for the language and the leaf of the boxes" $ do
        let para = [t "Le proverbe de la typographie élémentaire, imprimerie et dictionnaire."]
            outside = fst (composeInlines (inBook "fr") para)
            inside = fst (composeInlines (inBook "fr") [lang "fr" para])
        withoutLang outside @?= withoutLang inside
        texts (inBook "fr") para @?= texts (inBook "ja") [lang "fr" para]
        assertBool "the French patterns break proverbe" ("verbe" `elem` texts (inBook "fr") para),
      testCase "F5: the exceptions of a book of fr are looked up by fr outside a span" $ do
        let book = Map.fromList [("fr", ["pro-ver-be"])]
            parts l w = maybe [w] (`hyphenate` w) (exceptionPatterns "fr" none book l)
        parts Nothing "proverbe" @?= ["pro", "ver", "be"]
        parts (Just "fr") "proverbe" @?= ["pro", "ver", "be"]
        parts (Just "en") "proverbe" @?= hyphenate englishUS "proverbe"
        -- the key en is not that of the words outside a span of a book of fr
        maybe [] (`hyphenate` "algorithm") (exceptionPatterns "fr" none (Map.fromList [("en", ["algo-rithm"])]) Nothing) @?= maybe [] (`hyphenate` "algorithm") (patternsFor (Just "fr")),
      testCase "F6: each bundled file of data/hyphenation/ has the SHA-256 the README gives, that of hyph-utf8 at 5684c0f5" $ do
        digests <- readmeDigests
        sort (map fst digests) @?= sort bundledFiles
        forM_ digests $ \(f, h) -> do
          bytes <- BS.readFile ("data/hyphenation/" <> f)
          assertEqual f h (hex (sha256 bytes))
    ]
