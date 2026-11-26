{- | The named arguments of @style (root ADR 0467): the keys of a paragraph
style that @style-def takes, but based-on, over the style named, for the
paragraphs and the tables of its body.
-}
module StyleArgumentsSpec (tests) where

import Control.Monad (forM_)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.File
import Golem.Project.Style (LocalValue (..), ParaStyleDef (..), Style (..), paraLineBreaks, paraStyle, paraStyleWith, parseStyle)
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | A style of style.toml with the styles quote (next-style after), after and caption.
style :: Style
style =
  either
    (error . show)
    id
    ( parseStyle
        (FileId 9)
        (page <> "[paragraph-styles.quote]\nindent = \"2zw\"\nnext-style = \"after\"\n\n[paragraph-styles.after]\nindent = \"1zw\"\n\n[paragraph-styles.keep]\nline-breaks = \"keep\"\n")
    )

-- | A page of a free grid, where a line pitch may be a length.
page :: Text
page = "[page]\nsize = \"B6\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 20\nlines = 20\nline-pitch = \"16pt\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\nalignment = \"free\"\n"

ctx :: EvalContext
ctx = baseCtx {ctxStyle = style, ctxCharStyles = Map.keysSet (stCharStyles style), ctxParaStyles = paraLineBreaks style}

-- | The codes of the diagnostics of a source.
codes :: Text -> [Text]
codes src = map diagCodeText (fst (evalSource ctx src))

-- | The paragraph styles of the paragraphs of a source, in their order.
styles :: Text -> [Maybe StyleRef]
styles src = [st | Paragraph st _ <- resultBodies (evalResult ctx src)]

-- | The paragraph style of the cells of the tables of a source.
tableStyles :: Text -> [Maybe StyleRef]
tableStyles src = [tableStyle t | TableBlock t <- resultBodies (evalResult ctx src)]

-- | A style with keys, each written as a string.
keyed :: Text -> [(Text, Text)] -> StyleRef
keyed n kvs = StyleRef n (Map.fromList [(k, StyleString v) | (k, v) <- kvs])

-- | The keys of a style as @style-def reads them.
values :: StyleRef -> [(Text, LocalValue)]
values r = [(k, case v of StyleWord w -> LocalWord w; StyleString t -> LocalString t) | (k, v) <- Map.toAscList (styleRefKeys r)]

-- | The arguments written: key="value" for each.
written :: [(Text, Text)] -> Text
written kvs = T.concat [" " <> k <> "=\"" <> v <> "\"" | (k, v) <- kvs]

tests :: TestTree
tests =
  testGroup
    "the named arguments of @style (root ADR 0467)"
    [ testCase "root ADR 0467 I1: @style body without named arguments is body as before" $ do
        styles "@style body\n本文\n" @?= [Nothing]
        codes "@style body\n本文\n" @?= [],
      testCase "root ADR 0467 I1: @style quote without named arguments is the style quote without keys" $
        styles "@style quote\n本文\n" @?= [Just "quote"],
      testCase "root ADR 0467 I1: @style line-pitch=\"16pt\" without a name is G02047, as before" $ do
        codes "@style line-pitch=\"16pt\"\n本文\n" @?= ["G02047"]
        styles "@style line-pitch=\"16pt\"\n本文\n" @?= [Nothing],
      testCase "root ADR 0467 I2: @style body line-pitch=\"16pt\" is body with the key line-pitch" $ do
        styles "@style body line-pitch=\"16pt\"\n本文\n" @?= [Just (keyed "body" [("line-pitch", "16pt")])]
        codes "@style body line-pitch=\"16pt\"\n本文\n" @?= [],
      testCase "root ADR 0467 I2: a key written as a word is kept as a word" $
        styles "@style quote indent=3zw\n本文\n" @?= [Just (StyleRef "quote" (Map.fromList [("indent", StyleWord "3zw")]))],
      testCase "root ADR 0467 I2: the body form with space-before=1 (one line) gives the key to both paragraphs" $
        styles "@style body space-before=1\n:::\n一\n\n二\n:::\n" @?= replicate 2 (Just (StyleRef "body" (Map.fromList [("space-before", StyleWord "1")]))),
      testCase "root ADR 0467 I2: a table in the body of @style s line-pitch=\"16pt\" has the keys for its cells" $
        tableStyles "@style quote line-pitch=\"16pt\"\n| a | b |\n|---|---|\n| 1 | 2 |\n" @?= [Just (keyed "quote" [("line-pitch", "16pt")])],
      testCase "root ADR 0467 I2: the style without a name resolves as @style-def paragraph t based-on=s with the keys" $
        forM_ keyCases $ \kvs -> do
          let src = "@style quote" <> written kvs <> "\n本文\n"
              defined = either (error . show) id (parseStyle (FileId 9) (page <> "[paragraph-styles.quote]\nindent = \"2zw\"\nnext-style = \"after\"\n\n[paragraph-styles.after]\nindent = \"1zw\"\n\n[paragraph-styles.t]\nbased-on = \"quote\"\n" <> T.concat [k <> " = \"" <> v <> "\"\n" | (k, v) <- kvs]))
          (kvs, codes src) @?= (kvs, [])
          case styles src of
            [Just r] -> (kvs, paraStyleWith style (Just (styleRefName r)) (values r)) @?= (kvs, (\d -> d {psBasedOn = Just "quote"}) <$> paraStyle defined (Just "t"))
            other -> assertFailure ("one paragraph with a style: " <> show other),
      testCase "root ADR 0467 I3: a value @style-def rejects is the same code and leaves the key out" $ do
        let defCodes = map diagCodeText (fst (evalSource ctx "@style-def paragraph t line-pitch=\"-1pt\"\n\n本文\n"))
        codes "@style body line-pitch=\"-1pt\"\n本文\n" @?= defCodes
        styles "@style body line-pitch=\"-1pt\"\n本文\n" @?= [Nothing],
      testCase "root ADR 0467 I3, I4: colour=\"red\" and line-pitch=\"16pt\" is one G02288 and the line pitch of 16pt" $ do
        codes "@style body colour=\"red\" line-pitch=\"16pt\"\n本文\n" @?= ["G02288"]
        styles "@style body colour=\"red\" line-pitch=\"16pt\"\n本文\n" @?= [Just (keyed "body" [("line-pitch", "16pt")])],
      testCase "root ADR 0467 I4: based-on is G02288" $ do
        codes "@style body based-on=caption\n本文\n" @?= ["G02288"]
        styles "@style body based-on=caption\n本文\n" @?= [Nothing],
      testCase "root ADR 0467 I4: k arguments that are based-on or no key of a paragraph style give exactly k G02288" $
        forM_ [0 .. 3 :: Int] $ \k -> do
          let bad = take k [("based-on", "caption"), ("colour", "red"), ("weight", "bold")]
              src = "@style quote" <> written (bad <> [("line-pitch", "16pt")]) <> "\n本文\n"
          (k, length (filter (== "G02288") (codes src))) @?= (k, k)
          (k, styles src) @?= (k, [Just (keyed "quote" [("line-pitch", "16pt")])]),
      testCase "root ADR 0467 I5: two paragraphs with the same name and keys have equal styles, others not" $ do
        case styles "@style body line-pitch=\"16pt\"\n一\n\n@style body line-pitch=\"16pt\"\n二\n\n@style body\n三\n\n@style body line-pitch=\"18pt\"\n四\n" of
          [a, b, c, d] -> do
            a @?= b
            assertBool "with keys and without differ" (a /= c)
            assertBool "other values differ" (a /= d)
          other -> assertFailure ("four paragraphs: " <> show other),
      testCase "root ADR 0467: the next-style of the style decides the next paragraph when the keys have none" $
        styles "@style quote line-pitch=\"16pt\"\n一\n\n二\n" @?= [Just (keyed "quote" [("line-pitch", "16pt")]), Just "after"],
      testCase "root ADR 0467: next-style among the keys decides the next paragraph" $
        styles "@style body next-style=quote\n一\n\n二\n" @?= [Just (StyleRef "body" (Map.fromList [("next-style", StyleWord "quote")])), Just "quote"],
      testCase "root ADR 0467: next-style of a style that does not exist is an error and leaves the keys out" $ do
        assertBool "an error at @style" (not (null (codes "@style body next-style=missing\n一\n")))
        styles "@style body next-style=missing\n一\n" @?= [Nothing],
      testCase "root ADR 0467: line-breaks=\"keep\" keeps the lines of the paragraph" $
        [length [() | LineBreak _ <- is] | Paragraph _ is <- resultBodies (evalResult ctx "@style body line-breaks=\"keep\"\n一\n二\n")] @?= [1]
    ]
  where
    keyCases =
      [ [("line-pitch", "16pt")],
        [("space-before", "6pt")],
        [("indent", "3zw")],
        [("first-line-indent", "1zw"), ("indent", "1zw")],
        [("align", "center")],
        [("space-between", "4pt"), ("line-pitch", "18pt")]
      ]
