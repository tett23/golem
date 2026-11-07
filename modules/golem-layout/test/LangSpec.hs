{- | The characters of both scripts and the hyphenation in a language span
(docs/adr ADR 0187): in a Latin span they join the Latin words, in a
Japanese span they are Japanese punctuation, outside a span they are set
as before; the patterns are those of the language of the span.
-}
module LangSpec (langTests) where

import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Fixtures (fs, look0, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.CharClass (charClassIn, dualCharacters)
import Golem.Layout.Hyphenation.EnUs (englishUS)
import Golem.Layout.Hyphenation.Languages (patternsFor)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty
import Test.Tasty.HUnit

-- | The environment with the patterns of each language.
env :: ComposeEnv
env = (defaultComposeEnv fs) {cePatterns = patternsFor}

-- | A paragraph of a language of its block.
inBlock :: Text -> ComposeEnv
inBlock l = env {ceLook = look0 {lkLang = Just l}}

-- | The nodes of a structure, at any depth.
nodes :: InlineNode -> [InlineNode]
nodes n = n : case n of
  NodeElem _ ns -> concatMap nodes ns
  NodeLink _ _ ns -> concatMap nodes ns
  _ -> []

lang :: Text -> [IR.Inline] -> IR.Inline
lang = IR.Lang sp

t :: Text -> IR.Inline
t = IR.Text sp

items :: ComposeEnv -> [IR.Inline] -> [Item]
items e = fst . composeInlines e

-- | Each box: its text, whether it is a Latin word, and its kind.
boxes :: [Item] -> [(Text, Bool, BoxKind)]
boxes its = [(bcText c, bcExpandable c, boxKind c) | Box _ c <- its]

-- | The texts of the boxes.
texts :: [Item] -> [Text]
texts its = [bcText c | Box _ c <- its]

-- | What is between two neighbouring boxes of these texts.
between :: Text -> Text -> [Item] -> [Item]
between a b its = case break isA its of
  (_, _ : rest) -> case break isBox rest of
    (mid, Box _ c : _) | bcText c == b -> mid
    _ -> error "no such pair"
  _ -> error "no such box"
  where
    isA = \case
      Box _ c -> bcText c == a
      _ -> False
    isBox = \case
      Box {} -> True
      _ -> False

hyphens :: [Item] -> [Hyphen]
hyphens its = [h | Penalty _ p h <- its, p < infPenalty, h /= NoHyphen]

latin, punct :: Text -> (Text, Bool, BoxKind)
latin x = (x, True, KindText)
punct x = (x, False, KindPunctuation)

langTests :: TestTree
langTests =
  testGroup
    "the characters of both scripts and the hyphenation in a language span (docs/adr ADR 0187)"
    [ testCase "the thirteen characters of both scripts" $
        dualCharacters @?= "‘’“”«»‹›—–‐‑…",
      testCase "the class of a character of both scripts by the language" $ do
        [charClassIn (Just "en") c | c <- dualCharacters] @?= replicate 13 Western
        [charClassIn (Just "zh-Hant") c | c <- dualCharacters] @?= replicate 13 Western
        [charClassIn (Just "ja") c | c <- "“‘«‹”’»›—…–‐‑"] @?= replicate 4 Opening <> replicate 4 Closing <> replicate 2 Inseparable <> replicate 3 Hyphen
        [charClassIn (Just "JA-JP") c | c <- "‹›"] @?= [Opening, Closing]
        [charClassIn Nothing c | c <- "“‹…"] @?= [Opening, Ideograph, Inseparable]
        [charClassIn (Just "ja") c | c <- "a東"] @?= [Western, Ideograph]
        [charClassIn (Just "en") c | c <- "a東か"] @?= [Western, Ideograph, Kana],
      testCase "[lang en: “東京”] in Japanese text: the quotation marks are Latin words; outside a span, Japanese brackets" $ do
        boxes (items env [t "あ", lang "en" [t "“東京”"], t "い"])
          @?= [("あ", False, KindText), latin "“", ("東", False, KindText), ("京", False, KindText), latin "”", ("い", False, KindText)]
        boxes (items env [t "あ“東京”い"])
          @?= [("あ", False, KindText), punct "“", ("東", False, KindText), ("京", False, KindText), punct "”", ("い", False, KindText)],
      testCase "the Latin marks of [lang en: “東京”] take no aki and no break beside the kanji" $ do
        let its = items env [lang "en" [t "“東京”"]]
        between "“" "東" its @?= []
        between "京" "”" its @?= [],
      testCase "[lang ja: “Hello”]: Japanese brackets around a Latin word" $
        boxes (items env [lang "ja" [t "“Hello”"]]) @?= [punct "“", latin "Hello", punct "”"],
      testCase "[lang en: wait… what]: the ellipsis is in the word; outside a span it is a Japanese character with aki" $ do
        let inSpan = items env [lang "en" [t "wait… what"]]
        texts inSpan @?= ["wait…", "what"]
        let outside = items env [t "wait… what"]
        texts outside @?= ["wait", "…", "what"]
        assertBool (show (between "wait" "…" outside)) (not (null [g | g@Glue {} <- between "wait" "…" outside])),
      testCase "[lang fr: « Bonjour »]: the guillemets are Latin" $
        boxes (items env [lang "fr" [t "« Bonjour »"]]) @?= [latin "«", latin "Bonjour", latin "»"],
      testCase "‹ and › outside a span stay ideographs; in a Japanese span they are brackets" $ do
        boxes (items env [t "‹a›"]) @?= [("‹", False, KindText), latin "a", ("›", False, KindText)]
        boxes (items env [lang "ja" [t "‹a›"]]) @?= [punct "‹", latin "a", punct "›"],
      testCase "a paragraph with @lang en sets “東京” as [lang en: “東京”]; [lang ja] inside it is Japanese" $ do
        boxes (items (inBlock "en") [t "“東京”"]) @?= boxes (items env [lang "en" [t "“東京”"]])
        boxes (items (inBlock "en") [lang "ja" [t "“東京”"]]) @?= boxes (items env [t "“東京”"]),
      testCase "the boundary of a span is the boundary of the words" $
        texts (items env [t "ab", lang "fr" [t "cd"], t "ef"]) @?= ["ab", "cd", "ef"],
      testCase "the boxes of a span have its language in their look" $
        [(bcText c, lkLang (bcLook c)) | Box _ c <- items env [t "a ", lang "fr" [t "b ", lang "de" [t "c"]]]]
          @?= [("a", Nothing), ("b", Just "fr"), ("c", Just "de")],
      testCase "[lang fr: ...] is not hyphenated by patterns; [lang en: ...] and the text outside a span are, as before" $ do
        mapM_
          ( \w -> do
              let outside = items env [t w]
              texts (items env [lang "en" [t w]]) @?= texts outside
              texts (items env [lang "en-GB" [t w]]) @?= texts outside
              texts (items env [lang "fr" [t w]]) @?= [w]
              texts (items (inBlock "fr") [t w]) @?= [w]
          )
          ["proverbe", "hyphenation"]
        texts (items env [t "hyphenation"]) @?= ["hy", "phen", "ation"],
      testCase "[lang fr: porte-monnaie] breaks after porte- and nowhere else" $ do
        let its = items env [lang "fr" [t "porte-monnaie"]]
        texts its @?= ["porte-", "monnaie"]
        hyphens its @?= [ExplicitHyphen],
      testCase "the body of a note or a sidenote is in the language of the place of its mark" $ do
        let note = IR.Note sp 1 [t "n"]
            side = IR.Sidenote sp 1 [t "s"]
            bodies is = [b | AnchorNote _ _ _ b <- snd (composeInlines env is)] <> [b | AnchorSidenote _ _ _ b <- snd (composeInlines env is)]
        bodies [t "a", note, side] @?= [[t "n"], [t "s"]]
        bodies [lang "fr" [t "a", note, side]] @?= [[lang "fr" [t "n"]], [lang "fr" [t "s"]]]
        [b | AnchorNote _ _ _ b <- snd (composeInlines (inBlock "en") [note])] @?= [[lang "en" [t "n"]]]
        [b | NodeNote _ _ _ b <- inlineStructure env [lang "fr" [note]] >>= nodes] @?= [[lang "fr" [t "n"]]],
      testCase "the patterns of a language: English for en, en-GB and outside a span, none for fr and ja" $ do
        map (isJust . patternsFor) [Just "en", Just "en-GB", Just "EN-us", Nothing] @?= [True, True, True, True]
        map (isNothing . patternsFor) [Just "fr", Just "ja", Just "de-CH-1996"] @?= [True, True, True]
        fmap (const ()) (patternsFor Nothing) @?= fmap (const ()) (Just englishUS)
    ]
