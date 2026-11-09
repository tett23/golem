{- | The memo of the shaping of texts (docs/adr/0253): the provider that
remembers its shaping gives what the provider without the memo gives,
for any shaping and text, looked up once or twice, from one thread or
from two at once (I1).
-}
module ShapingMemoSpec (shapingMemoTests) where

import Control.Concurrent (forkIO)
import Control.Concurrent.MVar (newEmptyMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Files (diskFiles)
import Golem.Project.Style (parseStyle)
import Golem.Syntax (FileId (..))
import Golem.Typeset (FontProvider (..), LoadedFonts (..), Shaped (..), Shaping (..))
import Golem.Typeset.FontProvider (golemFontProvider, unmemoisedFontProvider)
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit hiding (assert)
import Test.Tasty.Hedgehog (testProperty)

-- | Two roles with a Japanese and a Latin face, the second with features of its own.
style :: Text
style =
  "[fonts.body]\nja = \"ja.otf\"\nlatin = \"latin.ttf\"\n\n\
  \[fonts.ruby]\nja = \"ja.otf\"\nlatin = \"latin.ttf\"\nfeatures = [\"palt\", \"-kern\"]\n"

-- | The fonts of the provider with the memo and of the one without it.
loadBoth :: IO (LoadedFonts, LoadedFonts)
loadBoth = withSystemTempDirectory "golem-shaping-memo" $ \tmp -> do
  BS.readFile "test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" >>= BS.writeFile (tmp </> "ja.otf")
  BS.readFile "test/fixtures/tempest/fonts/SourceSerifVariable-Roman.ttf" >>= BS.writeFile (tmp </> "latin.ttf")
  st <- either (fail . show) pure (parseStyle (FileId 0) style)
  let load p = loadFonts p (diskFiles tmp) (FileId 1) st [] >>= either (fail . show) pure
  (,) <$> load golemFontProvider <*> load unmemoisedFontProvider

-- the boundaries of docs/adr/0253
roles :: [Text]
roles = ["body", "ruby", "none"]

featureSets :: [[Text]]
featureSets = [[], ["palt"], ["-kern", "+liga", "vpal"], ["kern=0"], ["パルト"]]

texts :: [Text]
texts = ["", "a", "あ", "ab", "「、", "e\x0301", "葛\xE0100", T.singleton '\x10FFFF', "\x1F600\xFE0F", "office", T.replicate 60 "組版と typesetting、"]

genShaping :: Gen Shaping
genShaping =
  Shaping
    <$> Gen.element roles
    <*> Gen.bool
    <*> Gen.subsequence ["palt", "-kern", "vert", "+liga", "kern=0"]
    <*> Gen.bool

genText :: Gen Text
genText = Gen.text (Range.linear 0 24) (Gen.frequency [(4, Gen.element pool), (1, Gen.unicode)])
  where
    pool :: String
    pool = "あいう漢字「」『』、。ーゃ〜…—–-“”’ abcdefiAVTo1fflé\x0301\xE0100\xFE0F"

-- | Whether the two providers agree on a shaping and a text.
agree :: (LoadedFonts, LoadedFonts) -> Shaping -> Text -> Bool
agree (memo, plain) s t =
  let expected = lfShape plain s t
   in lfShape memo s t == expected && lfWordAdvance memo s t == sum (map shAdvance expected)

shapingMemoTests :: TestTree
shapingMemoTests =
  withResource loadBoth (const (pure ())) $ \fonts ->
    testGroup
      "the memo of the shaping of texts (docs/adr/0253)"
      [ testCase "I1: the boundaries: every role, the features, vertical and dual, looked up twice" $ do
          fs <- fonts
          forM_ [Shaping r v e d | r <- roles, v <- [False, True], e <- featureSets, d <- [False, True]] $ \s ->
            forM_ texts $ \t -> (s, t, agree fs s t, agree fs s t) @?= (s, t, True, True),
        testCase "I1: two threads look up the same keys at once" $ do
          fs <- fonts
          let all' = and [agree fs (Shaping r v [] False) t | r <- roles, v <- [False, True], t <- texts]
              other = and [agree fs (Shaping r v [] False) t | r <- reverse roles, v <- [True, False], t <- texts]
          box <- newEmptyMVar
          _ <- forkIO (evaluate other >>= putMVar box)
          a <- evaluate all'
          b <- takeMVar box
          (a, b) @?= (True, True),
        testProperty "I1: the shaping and the advance of a word are those without the memo" . property $ do
          fs <- evalIO fonts
          s <- forAll genShaping
          t <- forAll genText
          assert (agree fs s t)
          -- the second look-up finds the remembered value
          assert (agree fs s t)
      ]
