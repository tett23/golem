-- | The paragraph style controls of the PDF (docs/adr/0374): opening-indent.
module ParagraphStyleControlsSpec (paragraphStyleControlsTests) where

import Data.ByteString qualified as BS
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Length (Sp (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The size of the type of 'horizontal30', 10pt.
fs :: Sp
fs = 655360

-- | Half of 'fs'.
hf :: Sp
hf = 327680

-- | The keys of body after those of 'horizontal30'.
bodyKeys :: T.Text -> BS.ByteString
bodyKeys keys = horizontal30 (TE.encodeUtf8 ("\n[paragraph-styles.body]\n" <> keys))

-- | The first line of a source: its length and its indent.
firstLine :: T.Text -> T.Text -> IO (Sp, Sp)
firstLine keys src = do
  (_, ls) <- verseLines (bodyKeys keys) src
  case ls of
    l : _ -> pure l
    [] -> assertFailure "no line"

paragraphStyleControlsTests :: [TestTree]
paragraphStyleControlsTests =
  [ testCase "ADR 0374: opening-indent = \"half\" takes half a character from the indent of a paragraph that starts with an opening bracket" $ do
      firstLine "first-line-indent = \"1zw\"\nopening-indent = \"half\"\n" ("「" <> T.replicate 40 "あ" <> "」\n") >>= (@?= (30 * fs - hf, hf))
      firstLine "first-line-indent = \"2zw\"\nopening-indent = \"half\"\n" ("（" <> T.replicate 40 "あ" <> "）\n") >>= (@?= (30 * fs - 3 * hf, 3 * hf)),
    testCase "ADR 0374: opening-indent = \"normal\", its default, and a paragraph without an opening bracket keep the indent" $ do
      firstLine "first-line-indent = \"1zw\"\n" ("「" <> T.replicate 40 "あ" <> "」\n") >>= (@?= (29 * fs, fs))
      firstLine "first-line-indent = \"1zw\"\nopening-indent = \"normal\"\n" ("「" <> T.replicate 40 "あ" <> "」\n") >>= (@?= (29 * fs, fs))
      firstLine "first-line-indent = \"1zw\"\nopening-indent = \"half\"\n" (T.replicate 40 "あ" <> "\n") >>= (@?= (29 * fs, fs)),
    testCase "ADR 0374: the indent of opening-indent = \"half\" is 0 at the least" $ do
      firstLine "opening-indent = \"half\"\n" ("「" <> T.replicate 40 "あ" <> "」\n") >>= (@?= (30 * fs, 0))
      firstLine "indent = \"2zw\"\nfirst-line-indent = \"-2zw\"\nopening-indent = \"half\"\n" ("「" <> T.replicate 40 "あ" <> "」\n") >>= (@?= (30 * fs, 0))
      -- the indent of the lines after the first is left as it is
      (_, ls) <- verseLines (bodyKeys "indent = \"2zw\"\nfirst-line-indent = \"-1zw\"\nopening-indent = \"half\"\n") ("「" <> T.replicate 40 "あ" <> "」\n")
      map snd ls @?= [hf, 2 * fs],
    testCase "ADR 0374: each line of a paragraph that keeps its lines starts as a paragraph, with opening-indent" $ do
      (_, ls) <- verseLines (horizontal30 "\n[paragraph-styles.verse]\nindent = \"0zw\"\nfirst-line-indent = \"1zw\"\nopening-indent = \"half\"\nspace-before = 0\nspace-after = 0\n") "@style verse\n  「一行」\n  二行\n"
      map snd ls @?= [hf, fs]
  ]
