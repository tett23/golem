{- | The paragraph style controls of the evaluation (docs/adr/0374):
next-style, the paragraph style of the paragraph after one, and
initial-style, the character style of the first character of a paragraph.
-}
module ParagraphStyleControlsSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Parser.SourceSettings (ParagraphSeparator (..), SourceSettings (..))
import Golem.Project.Style (OpeningIndent (..), ParaStyleDef (..), Style (..), paraLineBreaks, paraStyle, parseStyle)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | A style of style.toml; a test fails when it is not read.
styleOf :: Text -> Style
styleOf src = either (error . show) id (parseStyle (FileId 9) src)

-- | The codes of the errors of a style.toml.
styleCodes :: Text -> [Text]
styleCodes src = case parseStyle (FileId 9) src of
  Left ds -> map diagCodeText ds
  Right _ -> []

-- | A context with the styles of a style.toml.
ctxOf :: Style -> EvalContext
ctxOf s = baseCtx {ctxStyle = s, ctxCharStyles = Map.keysSet (stCharStyles s), ctxParaStyles = paraLineBreaks s}

-- | The paragraphs of a source: the paragraph style of each and its inlines, without their spans.
paragraphs :: Style -> Text -> [(Maybe Text, [Text])]
paragraphs s src = [(st, map shape is) | Paragraph st is <- resultBodies (evalResult (ctxOf s) src)]

-- | An inline without its span: text as itself, a character style as <name:...>, others by kind.
shape :: Inline -> Text
shape = \case
  Text _ x -> x
  CharStyle _ n xs -> "<" <> n <> ":" <> T.concat (map shape xs) <> ">"
  Ruby _ _ segs -> "<ruby:" <> T.concat [T.concat (map shapeNoRuby (rsBase s')) | s' <- segs] <> ">"
  Tcy _ x -> "<tcy " <> x <> ">"
  LineBreak _ -> "<br>"
  IndexMark {} -> "<index>"
  _ -> "<other>"
  where
    shapeNoRuby :: InlineNoRuby -> Text
    shapeNoRuby = \case
      Text _ x -> x
      CharStyle _ n xs -> "<" <> n <> ":" <> T.concat (map shapeNoRuby xs) <> ">"
      _ -> "<other>"

-- | The diagnostics codes of a source evaluated in a style.
evalCodes :: Style -> Text -> [Text]
evalCodes s src = map diagCodeText (fst (evalSource (ctxOf s) src))

tests :: TestTree
tests =
  testGroup
    "paragraph style controls (docs/adr/0374)"
    [ nextStyleTests,
      initialStyleTests,
      keyTests
    ]

{- | next-style: the style of the next paragraph when it has none written,
for that paragraph only.
-}
nextStyleTests :: TestTree
nextStyleTests =
  testGroup
    "next-style"
    [ testCase "ADR 0374 I1: inv1_paragraph_style_controls_property: the style of a paragraph is the one written, the next-style of the paragraph before, or body, in this order; next-style and initial-style are found through based-on" $
        forM_ combinations $ \(written, childNext, parentNext, bodyNext) -> do
          let s =
                styleOf
                  ( "[paragraph-styles.body]\n"
                      <> key "next-style" bodyNext
                      <> "\n[paragraph-styles.parent]\n"
                      <> key "next-style" parentNext
                      <> "\n[paragraph-styles.child]\nbased-on = \"parent\"\n"
                      <> key "next-style" childNext
                      <> T.concat ["\n[paragraph-styles." <> n <> "]\nbased-on = \"leaf\"\n" | n <- ["w", "x", "y", "z"]]
                      <> "\n[paragraph-styles.leaf]\nnext-style = \"body\"\n"
                  )
              src = "@style child\n一\n\n" <> maybe "" (\w -> "@style " <> w <> "\n") written <> "二\n"
              expected = case written <|> childNext <|> parentNext <|> bodyNext of
                Just "body" -> Nothing
                other -> other
          (written, childNext, parentNext, bodyNext, map fst (paragraphs s src)) @?= (written, childNext, parentNext, bodyNext, [Just "child", expected]),
      testCase "ADR 0374 I1: inv1_paragraph_style_controls_case_3: a style written on the paragraph wins over the next-style of the paragraph before" $ do
        let s = styleOf "[paragraph-styles.lead]\nnext-style = \"after\"\n\n[paragraph-styles.after]\n\n[paragraph-styles.other]\n"
        map fst (paragraphs s "@style lead\n一\n\n@style other\n二\n") @?= [Just "lead", Just "other"]
        -- body written is a style written too
        map fst (paragraphs s "@style lead\n一\n\n@style body\n二\n") @?= [Just "lead", Nothing]
        -- the body form of @style likewise
        map fst (paragraphs s "@style lead\n一\n\n@style other\n  二\n") @?= [Just "lead", Just "other"],
      testCase "ADR 0374: next-style is applied to the one paragraph right after, and a reference alone makes no paragraph" $ do
        let s = styleOf "[paragraph-styles.lead]\nnext-style = \"after\"\n\n[paragraph-styles.after]\n"
        map fst (paragraphs s "@style lead\n一\n\n二\n\n三\n") @?= [Just "lead", Just "after", Nothing]
        map fst (paragraphs s "@style lead\n一\n") @?= [Just "lead"]
        -- every paragraph of a body form is in the style written; the one after takes the next-style
        map fst (paragraphs s "@style lead\n  一\n\n  二\n\n三\n") @?= [Just "lead", Just "lead", Just "after"],
      testCase "ADR 0374: next-style is followed from paragraph to paragraph, each by its own style" $ do
        let s = styleOf "[paragraph-styles.a]\nnext-style = \"b\"\n\n[paragraph-styles.b]\nnext-style = \"c\"\n\n[paragraph-styles.c]\n"
        map fst (paragraphs s "@style a\n一\n\n二\n\n三\n\n四\n") @?= [Just "a", Just "b", Just "c", Nothing],
      testCase "ADR 0374: a block between the two paragraphs leaves the second without the next-style; a variable does not" $ do
        let s = styleOf "[paragraph-styles.lead]\nnext-style = \"after\"\n\n[paragraph-styles.after]\n"
        map fst (paragraphs s "@style lead\n一\n\n- 項目\n\n二\n") @?= [Just "lead", Nothing]
        map fst (paragraphs s "@style lead\n一\n\n@blank-line\n\n二\n") @?= [Just "lead", Nothing]
        map fst (paragraphs s "@style lead\n一\n\n@set x = 1\n\n二\n") @?= [Just "lead", Just "after"],
      testCase "ADR 0374: a paragraph with other attributes takes the next-style" $ do
        let s = styleOf "[paragraph-styles.lead]\nnext-style = \"after\"\n\n[paragraph-styles.after]\n"
            r = evalResult (ctxOf s) "@style lead\n一\n\n@label p\n二\n"
        [(blockLabel b, st) | b@Block {blockBody = Paragraph st _} <- resultBlocks r] @?= [(Nothing, Just "lead"), (Just "p", Just "after")],
      testCase "ADR 0374: a next-style that keeps its lines keeps the lines of the paragraph" $ do
        let s = styleOf "[paragraph-styles.lead]\nnext-style = \"verse\"\n"
        paragraphs s "@style lead\n一\n\n二\n三\n" @?= [(Just "lead", ["一"]), (Just "verse", ["二", "<br>", "三"])],
      testCase "ADR 0374: in the line style, the line after a paragraph of the style is the next paragraph" $ do
        let s = styleOf "[paragraph-styles.lead]\nnext-style = \"after\"\n\n[paragraph-styles.after]\n"
            c = (ctxOf s) {ctxSource = SourceSettings LineSeparated}
        [st | Paragraph st _ <- resultBodies (evalResult c "@style lead\n一\n\n二\n三\n")] @?= [Just "lead", Just "after", Nothing],
      testCase "ADR 0374: next-style of @style-def is applied as one of style.toml" $ do
        let s = styleOf "[paragraph-styles.after]\n"
        map fst (paragraphs s "@style-def paragraph lead next-style=after\n\n@style lead\n一\n\n二\n") @?= [Just "lead", Just "after"]
    ]
  where
    combinations = [(w, c, p, b) | w <- [Nothing, Just "w", Just "body"], c <- [Nothing, Just "x"], p <- [Nothing, Just "y"], b <- [Nothing, Just "z"]]
    key k = maybe "" (\v -> k <> " = \"" <> v <> "\"\n")
    a <|> b = case a of
      Just _ -> a
      Nothing -> b

-- | initial-style: the character style of the first character of a paragraph.
initialStyleTests :: TestTree
initialStyleTests =
  testGroup
    "initial-style"
    [ testCase "ADR 0374 I1: inv1_paragraph_style_controls_property (initial-style): the style of the first character is that of the paragraph style, its based-on, or body, in this order" $
        forM_ [(c, p, b) | c <- [Nothing, Just "c1"], p <- [Nothing, Just "c2"], b <- [Nothing, Just "c3"]] $ \(c, p, b) -> do
          let s =
                styleOf
                  ( T.concat ["[character-styles." <> n <> "]\n\n" | n <- ["c1", "c2", "c3"]]
                      <> "[paragraph-styles.body]\n"
                      <> key b
                      <> "\n[paragraph-styles.parent]\n"
                      <> key p
                      <> "\n[paragraph-styles.child]\nbased-on = \"parent\"\n"
                      <> key c
                  )
              expected = case catMaybes [c, p, b] of
                n : _ -> ["<" <> n <> ":本>", "文"]
                [] -> ["本文"]
          (c, p, b, paragraphs s "@style child\n本文\n") @?= (c, p, b, [(Just "child", expected)]),
      testCase "ADR 0374 I1: inv1_paragraph_style_controls_case_1: a paragraph without a character has no decoration of its first character" $ do
        let s = styleOf "[character-styles.drop]\n\n[paragraph-styles.body]\ninitial-style = \"drop\"\n"
        paragraphs s "[index reading=くみはん: 組版]\n" @?= [(Nothing, ["<index>"])]
        -- the character after a mark of the index is the first
        paragraphs s "[index reading=くみはん: 組版]組版\n" @?= [(Nothing, ["<index>", "<drop:組>", "版"])],
      testCase "ADR 0374: the first character is a base and its combining characters, inside the styles written" $ do
        let s = styleOf "[character-styles.drop]\n\n[character-styles.em]\n\n[paragraph-styles.body]\ninitial-style = \"drop\"\n"
        paragraphs s "e\x0301te\n" @?= [(Nothing, ["<drop:e\x0301>", "te"])]
        -- the styles written by hand are split and copied inside, as in the regex styles (docs/adr ADR 0015)
        paragraphs s "[style em: 本文]です\n" @?= [(Nothing, ["<drop:<em:本>>", "<em:文>", "です"])]
        paragraphs s "[ruby: 漢字|かんじ]です\n" @?= [(Nothing, ["<ruby:<drop:漢>字>", "です"])]
        -- an element that is not split is one character, as for the regex styles (docs/adr ADR 0015)
        paragraphs s "[tcy: 12]日\n" @?= [(Nothing, ["<drop:<tcy 12>>", "日"])],
      testCase "ADR 0374: initial-style decorates the first line only of a paragraph that keeps its lines" $ do
        let s = styleOf "[character-styles.drop]\n\n[paragraph-styles.verse]\ninitial-style = \"drop\"\n"
        paragraphs s "@style verse\n  一行\n  二行\n" @?= [(Just "verse", ["<drop:一>", "行", "<br>", "二行"])],
      testCase "ADR 0374: initial-style applies to the paragraphs at the top of the document, not to the paragraphs of a list" $ do
        let s = styleOf "[character-styles.drop]\n\n[paragraph-styles.body]\ninitial-style = \"drop\"\n"
            r = evalResult (ctxOf s) "本文\n\n- 項目\n"
        [map shape is | Paragraph _ is <- resultBodies r] @?= [["<drop:本>", "文"]]
        [map shape is | BulletList items <- resultBodies r, i <- items, Block {blockBody = Paragraph _ is} <- itemBlocks i] @?= [["項目"]]
    ]
  where
    key = maybe "" (\v -> "initial-style = \"" <> v <> "\"\n")

-- | The keys and their checks, in style.toml and @style-def.
keyTests :: TestTree
keyTests =
  testGroup
    "the keys"
    [ testCase "ADR 0374: next-style, initial-style and opening-indent are read and inherited through based-on" $ do
        let s = styleOf "[character-styles.drop]\n\n[paragraph-styles.a]\nnext-style = \"b\"\ninitial-style = \"drop\"\nopening-indent = \"half\"\n\n[paragraph-styles.b]\nbased-on = \"a\"\n"
            keys n = fmap (\d -> (psNextStyle d, psInitialStyle d, psOpeningIndent d)) (paraStyle s (Just n))
        keys "a" @?= Just (Just "b", Just "drop", Just OpeningHalf)
        keys "b" @?= Just (Just "b", Just "drop", Just OpeningHalf)
        fmap psOpeningIndent (paraStyle s Nothing) @?= Just (Just OpeningNormal),
      testCase "ADR 0374: a next-style or an initial-style that names no style is an error at the key (G03013)" $ do
        styleCodes "[paragraph-styles.a]\nnext-style = \"nope\"\n" @?= ["G03013"]
        styleCodes "[paragraph-styles.a]\ninitial-style = \"nope\"\n" @?= ["G03013"]
        -- a paragraph style is not a character style, nor the other way
        styleCodes "[character-styles.c]\n\n[paragraph-styles.a]\nnext-style = \"c\"\n" @?= ["G03013"]
        styleCodes "[paragraph-styles.a]\ninitial-style = \"body\"\n" @?= ["G03013"],
      testCase "ADR 0374: a value of a wrong type or out of the values is an error at the key (G03006)" $ do
        styleCodes "[paragraph-styles.a]\nopening-indent = \"full\"\n" @?= ["G03006"]
        styleCodes "[paragraph-styles.a]\nopening-indent = 1\n" @?= ["G03006"]
        styleCodes "[paragraph-styles.a]\nnext-style = 1\n" @?= ["G03006"]
        styleCodes "[paragraph-styles.a]\ninitial-style = true\n" @?= ["G03006"],
      testCase "ADR 0374: @style-def takes the keys with the same checks" $ do
        let s = styleOf "[character-styles.drop]\n"
        evalCodes s "@style-def paragraph a next-style=nope\n\n本文\n" @?= ["G03013"]
        evalCodes s "@style-def paragraph a initial-style=nope\n\n本文\n" @?= ["G03013"]
        evalCodes s "@style-def paragraph a opening-indent=full\n\n本文\n" @?= ["G03006"]
        paragraphs s "@style-def paragraph a initial-style=drop opening-indent=half\n\n@style a\n本文\n" @?= [(Just "a", ["<drop:本>", "文"])]
    ]
