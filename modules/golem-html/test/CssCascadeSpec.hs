{- | The evaluator of the cascade (docs/adr/0217), checked against rules
made by hand: specificity, the order of the style sheet, the selectors it
reads and those it refuses.
-}
module CssCascadeSpec (cssCascadeTests) where

import CssCascade
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
import Test.Tasty
import Test.Tasty.HUnit

p, pc :: Text -> Elem
p c = Elem "p" [c]
pc = p

plain :: Elem
plain = Elem "p" []

values :: Text -> Page -> Either String [Maybe Text]
values css page = map (fmap wValue) <$> winningMarginStarts css page

specOf :: Text -> Either String Specificity
specOf s = specificity <$> parseSelector s

cssCascadeTests :: TestTree
cssCascadeTests =
  testGroup
    "the evaluator of the cascade (docs/adr/0217)"
    [ testCase "specificity: types, classes, attributes and the argument of :not()" $ do
        specOf "p" @?= Right (0, 0, 1)
        specOf "p.ps-a" @?= Right (0, 1, 1)
        specOf "p:not([class])" @?= Right (0, 1, 1)
        specOf "p.ps-a + :not(.ps-a):not(.blank-line)" @?= Right (0, 3, 1)
        specOf "p.ps-a + p.ps-b:not(.ps-a)" @?= Right (0, 3, 2)
        specOf "body.file-1 p.ps-b" @?= Right (0, 2, 2)
        specOf "body:not(.file-1):not(.file-2) p.ps-a + p.ps-b" @?= Right (0, 4, 3)
        specOf "p.ps-sec::before" @?= Right (0, 1, 2),
      testCase "the greater specificity wins, whatever the order" $
        values "p.ps-a + p { margin-block-start: 2em; }\np { margin-block-start: 1em; }\n" (Page [] [pc "ps-a", plain])
          @?= Right [Just "1em", Just "2em"],
      testCase "of equal specificity, the later rule wins; in one rule, the later declaration" $ do
        values "p { margin-block-start: 1em; }\np { margin-block-start: 3em; }\n" (Page [] [plain]) @?= Right [Just "3em"]
        values "p { margin-block: 1em; margin-block-start: 2em; }\n" (Page [] [plain]) @?= Right [Just "2em"]
        values "p { margin-block-start: 2em; margin-block: 1em 0; }\n" (Page [] [plain]) @?= Right [Just "1em"],
      testCase "the next sibling, the descendant, the classes of body" $ do
        let css = "div.blank-line + p { margin-block-start: 0; }\nbody.file-1 p { margin-block-start: 5em; }\nbody:not(.file-1) p.ps-a { margin-block-start: 4em; }\n"
        values css (Page [] [Elem "div" ["blank-line"], plain, pc "ps-a"]) @?= Right [Nothing, Just "0", Just "4em"]
        values css (Page ["file-1"] [Elem "div" ["blank-line"], plain, pc "ps-a"]) @?= Right [Nothing, Just "5em", Just "5em"],
      testCase "a selector list: each selector by its own specificity" $
        values "p:not([class]) + :not(p):not(.blank-line), p:not([class]) + p[class] { margin-block-start: 1em; }\np.ps-a { margin-block-start: 2em; }\n" (Page [] [plain, Elem "h2" [], plain, p "ps-a"])
          @?= Right [Nothing, Just "1em", Nothing, Just "1em"],
      testCase "pseudo-elements match no element; rules without margin-block-start are not read" $
        values "p::before { margin-block: 1em 0; }\n@font-face { font-family: \"x\"; }\n.x > .y { color: red; }\n" (Page [] [plain]) @?= Right [Nothing],
      testCase "a rule outside the range is an error, not skipped" $ do
        assertBool "child" (isLeft (values "body > p { margin-block-start: 1em; }\n" (Page [] [plain])))
        assertBool "attribute value" (isLeft (values "p[data-x=\"y\"] { margin-block-start: 1em; }\n" (Page [] [plain])))
        assertBool "nested :not" (isLeft (values "p:not(:not(.a)) { margin-block-start: 1em; }\n" (Page [] [plain])))
        assertBool "at-rule" (isLeft (values "@media print { p { margin-block-start: 1em; } }\n" (Page [] [plain]))),
      testCase "the page of an XHTML file: the classes of body and the elements right under it" $
        pageOf "<?xml version=\"1.0\"?>\n<html><head><title>t</title></head>\n<body class=\"file-2\">\n<p class=\"ps-a\">a<br/>b</p>\n<div class=\"blank-line\"><br/></div>\n<ul>\n<li><p>x</p></li>\n</ul>\n<p>c</p>\n</body></html>"
          @?= Page ["file-2"] [p "ps-a", Elem "div" ["blank-line"], Elem "ul" [], plain],
      testCase "no rule: Nothing" $
        values (T.unlines ["h1 { color: red; }"]) (Page [] [plain]) @?= Right [Nothing]
    ]
