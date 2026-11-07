-- | [lang] and @lang (docs/adr ADR 0187).
module LangSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Eval.Builtin (builtinBlockCommands, parseBuiltin)
import Golem.Eval.File
import Golem.Project.Style (LineBreaks (..))
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

ctx :: EvalContext
ctx = baseCtx {ctxCharStyles = Set.fromList ["term"], ctxParaStyles = Map.fromList [("body", JoinLines), ("note", JoinLines)], ctxAssets = Map.fromList [("images/a.png", AssetPresent)]}

-- | The inlines of the paragraphs, without their spans.
inlinesOf :: Text -> [[Inline]]
inlinesOf src = [map unspan is | Paragraph _ is <- resultBodies (evalResult ctx src)]

unspan :: Inline -> Inline
unspan = \case
  Text _ t -> Text z t
  CharStyle _ c xs -> CharStyle z c (map unspan xs)
  Lang _ l xs -> Lang z l (map unspan xs)
  Note _ n xs -> Note z n (map unspan xs)
  x -> x

z :: SrcSpan
z = mkSpan (FileId 0) 0 0

-- | The code and the message of each diagnostic.
msgs :: Text -> [(Text, Text)]
msgs src = [(c, m) | (c, m, _, _) <- map diagSite (fst (evalSource ctx src))]

codes :: Text -> [Text]
codes = map fst . msgs

-- | The blocks of a source.
blocksOf :: Text -> [Block]
blocksOf = resultBlocks . evalResult ctx

-- | The language of each block at the top of a source, with the kind of its body.
langs :: Text -> [(Text, Maybe Text)]
langs src = [(kind (blockBody b), blockLang b) | b <- blocksOf src]

kind :: BlockBody -> Text
kind = \case
  Paragraph {} -> "p"
  Heading {} -> "h"
  BulletList {} -> "ul"
  OrderedList {} -> "ol"
  DefList {} -> "dl"
  Table {} -> "table"
  CodeBlock {} -> "code"
  FigureBlock {} -> "figure"
  ChannelOutput {} -> "channel"
  _ -> "other"

wrongArgs :: (Text, Text)
wrongArgs = ("G02131", "lang には言語のタグを一つ書きます")

wrongTag :: Text -> (Text, Text)
wrongTag t = ("G02132", "言語のタグの形が誤っています: " <> t)

tests :: TestTree
tests =
  testGroup
    "[lang] and @lang (docs/adr ADR 0187)"
    [ testCase "[lang en: text] is a language span" $ do
        inlinesOf "[lang en: text]\n" @?= [[Lang z "en" [Text z "text"]]]
        msgs "[lang en: text]\n" @?= [],
      testCase "the tag as written, its case kept" $ do
        inlinesOf "[lang en-US: x]\n" @?= [[Lang z "en-US" [Text z "x"]]]
        inlinesOf "[lang zh-Hant-TW: x]\n" @?= [[Lang z "zh-Hant-TW" [Text z "x"]]]
        inlinesOf "[lang \"de-CH-1996\": x]\n" @?= [[Lang z "de-CH-1996" [Text z "x"]]]
        msgs "[lang en-US: x][lang zh-Hant-TW: x][lang \"de-CH-1996\": x]\n" @?= [],
      testCase "G02131: no tag, two tags, a keyword argument, an expression" $ do
        msgs "[lang: x]\n" @?= [wrongArgs]
        msgs "[lang en fr: x]\n" @?= [wrongArgs]
        msgs "[lang en x=y: x]\n" @?= [wrongArgs]
        msgs "[lang [= \"en\"]: x]\n" @?= [wrongArgs],
      testCase "G02132: a tag not of the form of BCP 47" $ do
        msgs "[lang e_n: x]\n" @?= [wrongTag "e_n"]
        msgs "[lang 123: x]\n" @?= [wrongTag "123"]
        msgs "[lang en-: x]\n" @?= [wrongTag "en-"],
      testCase "G02038: no prose slot, or two" $ do
        codes "[lang en]\n" @?= ["G02038"]
        codes "[lang en: a | b]\n" @?= ["G02038"],
      testCase "the text of a wrong [lang] stays, without a span" $
        inlinesOf "[lang e_n: x]\n" @?= [[Text z "x"]],
      testCase "nested spans: the inner one inside the outer one" $
        inlinesOf "[lang en: a [lang fr: b] c]\n" @?= [[Lang z "en" [Text z "a ", Lang z "fr" [Text z "b"], Text z " c"]]],
      testCase "a span in a character style, a note and the base of a ruby" $ do
        inlinesOf "[style term: [lang en: a]]\n" @?= [[CharStyle z "term" [Lang z "en" [Text z "a"]]]]
        inlinesOf "本文[note: [lang en: a]]\n" @?= [[Text z "本文", Note z 1 [Lang z "en" [Text z "a"]]]]
        msgs "[ruby: [lang ja: 東] | ひがし]\n" @?= [],
      testCase "a span in a heading stays in its title" $
        [map unspan is | Heading _ _ is <- resultBodies (evalResult ctx "# [lang en: Tokyo] の話\n")] @?= [[Lang z "en" [Text z "Tokyo"], Text z " の話"]],
      testCase "a span in a cell of a table" $
        [map (map unspan) h | Table _ h _ <- resultBodies (evalResult ctx "| [lang en: a] | b |\n|---|---|\n| c | d |\n")] @?= [[[Lang z "en" [Text z "a"]], [Text z "b"]]],
      testCase "@lang en on the next paragraph, heading, list, table, code block and figure" $ do
        langs "@lang en\nHe said nothing.\n" @?= [("p", Just "en")]
        langs "@lang en\n# Title\n" @?= [("h", Just "en")]
        langs "@lang en\n- a\n- b\n" @?= [("ul", Just "en")]
        langs "@lang en\n+ a\n" @?= [("ol", Just "en")]
        langs "@lang en\n| a | b |\n|---|---|\n| c | d |\n" @?= [("table", Just "en")]
        langs "@lang en\n```\ncode\n```\n" @?= [("code", Just "en")]
        langs "@lang en\n@toc\n" @?= [("channel", Just "en")]
        langs "@lang en\n@figure images/a.png alt=x\n  A caption.\n" @?= [("figure", Just "en")]
        msgs "@lang en\nHe said nothing.\n" @?= [],
      testCase "the blocks in the items of a list with @lang have no language of their own" $
        [[map blockLang (itemBlocks i) | i <- items] | BulletList items <- resultBodies (evalResult ctx "@lang en\n- a\n- b\n")] @?= [[[Nothing], [Nothing]]],
      testCase "@lang with the other attributes" $ do
        [(blockLabel b, blockLang b) | b <- blocksOf "@label intro\n@lang en\n# Intro\n"] @?= [(Just "intro", Just "en")]
        [(blockLabel b, blockLang b) | b <- blocksOf "@lang en\n@label intro\n# Intro\n"] @?= [(Just "intro", Just "en")]
        msgs "@lang en\n@label intro\n# Intro\n" @?= [],
      testCase "@lang with @style on a paragraph" $
        [(st, blockLang b) | b@(Block _ _ _ (Paragraph st _)) <- blocksOf "@lang en\n@style note\nNote.\n"] @?= [(Just "note", Just "en")],
      testCase "two @lang on a block: the later wins, as with @label" $ do
        langs "@lang en\n@lang fr\nBonjour.\n" @?= [("p", Just "fr")]
        codes "@lang en\n@lang fr\nBonjour.\n" @?= ["G02012"],
      testCase "the body of @lang: each block at the top of the body" $ do
        langs "@lang en\n  The first paragraph.\n\n  The second.\n\n  - A list inside it.\n" @?= [("p", Just "en"), ("p", Just "en"), ("ul", Just "en")]
        msgs "@lang en\n  The first paragraph.\n\n  The second.\n\n  - A list inside it.\n" @?= [],
      testCase "a block with @lang of its own in the body of @lang" $
        langs "@lang en\n  English.\n\n  @lang de\n  Deutsch.\n\n  English again.\n" @?= [("p", Just "en"), ("p", Just "de"), ("p", Just "en")],
      testCase "a heading in the body of @lang" $ do
        langs "@lang en\n  # Title\n\n  Text.\n" @?= [("h", Just "en"), ("p", Just "en")]
        msgs "@lang en\n  # Title\n\n  Text.\n" @?= [],
      testCase "a page break in the body of @lang is G02059, and so on" $ do
        codes "@lang en\n  Text.\n\n  @page-break\n" @?= ["G02059"]
        langs "@lang en\n  Text.\n\n  @page-break\n" @?= [("p", Just "en")]
        codes "@lang en\n  Text.\n\n  @no-page-break\n" @?= ["G02071"]
        codes "@lang en\n  Text.\n\n  @blank-line\n" @?= ["G02093"],
      testCase "G02010: @lang without a block after it" $ do
        codes "@lang en\n" @?= ["G02010"]
        codes "@lang en\n@label a\n" @?= ["G02010"],
      testCase "G02131 and G02132 of @lang" $ do
        codes "@lang\nText.\n" @?= ["G02131"]
        codes "@lang en fr\nText.\n" @?= ["G02131"]
        codes "@lang en x=y\nText.\n" @?= ["G02131"]
        msgs "@lang e_n\nText.\n" @?= [wrongTag "e_n"]
        codes "@lang e_n\n  Text.\n" @?= ["G02132"]
        langs "@lang e_n\nText.\n" @?= [("p", Nothing)],
      testCase "a plugin may not provide a block command or an inline command named lang" $ do
        assertBool "block" ("lang" `elem` builtinBlockCommands)
        assertBool "inline" (isJust (parseBuiltin "lang"))
    ]
