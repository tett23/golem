{- | The breaks inside a link (docs/adr ADR 0182): a Latin word of the text
of a link is not broken inside, by the patterns or after a hyphen; a URL
in the character style url keeps its breaks, and no line ends with a
hyphen inside it.
-}
module LinkSpec (linkTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (LinkTarget (..), Look (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The environment with the patterns, a link and the character style url as golem-driver restyles them.
env :: ComposeEnv
env =
  (defaultComposeEnv fs)
    { cePatterns = Just englishUS,
      ceRestyle = \lk -> \case
        IR.Link _ u _ -> lk {lkLink = Just (LinkUri u)}
        IR.CharStyle _ "url" _ -> lk {lkUrl = True}
        _ -> lk
    }

link :: [IR.Inline] -> IR.Inline
link = IR.Link sp "https://example.com/"

texts :: [Item] -> [Text]
texts its = [bcText c | Box _ c <- its]

-- | The kinds of the breaks a paragraph may take, the end left out.
hyphens :: [Item] -> [Hyphen]
hyphens its = [h | Penalty _ p h <- its, p < infPenalty, h /= NoHyphen]

linkTests :: TestTree
linkTests =
  testGroup
    "breaks inside a link (docs/adr ADR 0182)"
    [ testCase "the boxes of a link have its target in their look" $ do
        let its = fst (composeInlines env [IR.Text sp "a ", link [IR.Text sp "b"]])
        [(bcText c, lkLink (bcLook c)) | Box _ c <- its] @?= [("a", Nothing), ("b", Just (LinkUri "https://example.com/"))],
      testCase "a Latin word of a link is not hyphenated, nor broken after a hyphen" $ do
        let inside = fst (composeInlines env [link [IR.Text sp "hyphenation porte-monnaie"]])
        texts inside @?= ["hyphenation", "porte-monnaie"]
        hyphens inside @?= []
        let ls = brLines (breakParagraph defaultParams (const (3 * fs)) inside)
        [T.concat (texts (lineItems l)) | l <- ls] @?= ["hyphenation", "porte-monnaie"],
      testCase "the same words outside a link are broken as before" $ do
        let outside = fst (composeInlines env [IR.Text sp "hyphenation porte-monnaie"])
        texts outside @?= ["hy", "phen", "ation", "porte-", "mon", "naie"]
        assertBool (show (hyphens outside)) (ExplicitHyphen `elem` hyphens outside),
      testCase "a URL in the character style url inside a link breaks after / and draws no hyphen" $ do
        let u = "https://example.com/a-very-long-path/with-hyphens/"
            its = fst (composeInlines env [IR.Link sp u [IR.CharStyle sp "url" [IR.Text sp u]]])
            ls = brLines (breakParagraph defaultParams (const (12 * fs)) its)
            lineTexts = [T.concat (texts (lineItems l)) | l <- ls]
        assertBool (show lineTexts) (length ls > 1)
        hyphens its @?= []
        T.concat lineTexts @?= u
        -- no line ends or starts at a hyphen
        assertBool (show lineTexts) (not (any ("-" `T.isSuffixOf`) (init lineTexts)) && not (any ("-" `T.isPrefixOf`) lineTexts))
    ]
