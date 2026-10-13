-- | Regex styles laid on the semantic IR (docs/adr ADR 0015).
module RegexStyleSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Doc.IR
import Golem.Doc.Validate (validateDocument)
import Golem.Eval.RegexStyle
import Golem.Project.Style (ParaStyleDef (..), RegexStyleDef (..), Style (..), defaultStyle, noParaDef)
import Golem.Regex (compile)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = mkSpan (FileId 1) 0 0

t :: Text -> Inline
t = Text sp

cs :: Text -> [Inline] -> Inline
cs = CharStyle sp

-- | Rules from patterns, by paragraph style.
rules :: [(Text, [(Text, Text)])] -> RegexRules
rules xs = Map.fromList [(n, [(either (error . show) id (compile p), s) | (p, s) <- rs]) | (n, rs) <- xs]

digits :: RegexRules
digits = rules [("body", [("[0-9]+", "n")])]

-- | A paragraph of body through the rules.
para :: RegexRules -> [Inline] -> [Inline]
para r is = case map blockBody (docBlocks (applyRegexStyles r (doc [Paragraph Nothing is]))) of
  [Paragraph _ is'] -> is'
  other -> error (show other)

doc :: [BlockBody] -> Document
doc = Document (FileId 1) . map (Block sp Nothing)

bodies :: RegexRules -> [BlockBody] -> [BlockBody]
bodies r = map blockBody . docBlocks . applyRegexStyles r . doc

tests :: TestTree
tests =
  testGroup
    "regex styles (docs/adr ADR 0015)"
    [ testCase "a match is wrapped in the character style" $
        para digits [t "第12章"] @?= [t "第", cs "n" [t "12"], t "章"],
      testCase "a later rule is inside an earlier one" $
        para (rules [("body", [("[0-9]+", "n"), ("2", "m")])]) [t "12"] @?= [cs "n" [t "1"], cs "n" [cs "m" [t "2"]]],
      testCase "a style written by hand goes inside the regex style" $
        para digits [t "a1", cs "x" [t "2b"]] @?= [t "a", cs "n" [t "1", cs "x" [t "2"]], cs "x" [t "b"]],
      testCase "kenten and colour are split at the boundary and copied" $ do
        para digits [Kenten sp Nothing [t "a1"]] @?= [Kenten sp Nothing [t "a"], cs "n" [Kenten sp Nothing [t "1"]]]
        para digits [Color sp "accent" [t "1a"]] @?= [cs "n" [Color sp "accent" [t "1"]], Color sp "accent" [t "a"]],
      testCase "a match inside a ruby base is wrapped inside the base" $
        para digits [ruby [(["東京12"], Just "とうきょう")]] @?= [ruby' [([Text sp "東京", CharStyle sp "n" [Text sp "12"]], Just "とうきょう")]],
      testCase "a ruby whose whole base matches is wrapped as a whole" $
        para digits [ruby [(["12"], Just "じゅうに")]] @?= [cs "n" [ruby [(["12"], Just "じゅうに")]]],
      testCase "the reading is not matched" $
        para digits [ruby [(["東京"], Just "12")]] @?= [ruby [(["東京"], Just "12")]],
      testCase "a ruby of several segments split by the match" $
        para digits [ruby [(["a"], Just "x"), (["1"], Just "y")]] @?= [ruby' [([Text sp "a"], Just "x"), ([CharStyle sp "n" [Text sp "1"]], Just "y")]],
      testCase "tcy is one replacement character" $ do
        para digits [t "a", Tcy sp "12", t "b"] @?= [t "a", Tcy sp "12", t "b"]
        para (rules [("body", [(".", "n")])]) [Tcy sp "12"] @?= [cs "n" [Tcy sp "12"]]
        para (rules [("body", [("a.b", "n")])]) [t "a", Number sp 3 Nothing, t "b"] @?= [cs "n" [t "a", Number sp 3 Nothing, t "b"]],
      testCase "the body of a note is not matched" $
        para digits [t "a", Note sp 1 [t "12"]] @?= [t "a", Note sp 1 [t "12"]],
      testCase "a note is not wrapped and cuts a run" $
        para (rules [("body", [(".+", "n")])]) [t "a", Note sp 1 [t "x"], t "b"] @?= [cs "n" [t "a"], Note sp 1 [t "x"], cs "n" [t "b"]],
      testCase "an index mark and a proof comment cut a run" $
        para (rules [("body", [(".+", "n")])]) [t "a", IndexMark sp (IndexEntry ["k"] []), t "b"]
          @?= [cs "n" [t "a"], IndexMark sp (IndexEntry ["k"] []), cs "n" [t "b"]],
      testCase "the body of a sidenote has the rules of sidenote" $ do
        let r = rules [("body", [("[0-9]+", "n")]), ("sidenote", [("[a-z]+", "m")])]
        para r [t "1", Sidenote sp 1 [t "2b"]] @?= [cs "n" [t "1"], Sidenote sp 1 [t "2", cs "m" [t "b"]]],
      testCase "a caption has the rules of caption, not of body" $ do
        let r = rules [("body", [("[0-9]+", "n")]), ("caption", [("[a-z]+", "m")])]
            fig = FigureBlock (Figure "a.png" Nothing "" Nothing Nothing [Block sp Nothing (Paragraph Nothing [t "1a"])])
        bodies r [fig] @?= [FigureBlock (Figure "a.png" Nothing "" Nothing Nothing [Block sp Nothing (Paragraph Nothing [t "1", cs "m" [t "a"]])])],
      testCase "a line break is not wrapped and cuts a run" $ do
        let r = rules [("body", [("[0-9\\n]+", "n")])]
            out = para r [t "a1", LineBreak sp, t "2b"]
        out @?= [t "a", cs "n" [t "1"], LineBreak sp, cs "n" [t "2"], t "b"]
        validateDocument (const (Just 100)) [] (doc [Paragraph Nothing out]) @?= [],
      testCase "headings, table cells and terms are not matched; list items are" $ do
        let h = Heading 1 noHeadingAttrs [t "1"]
            tbl = Table [AlignDefault] [[t "1"]] [[[t "2"]]]
            dl = DefList [DefGroup [[t "1"]] [[Block sp Nothing (Paragraph Nothing [t "2"])]]]
            ul = BulletList [ListItem Nothing [Block sp Nothing (Paragraph Nothing [t "3"])]]
        bodies digits [h, tbl, dl, ul]
          @?= [ h,
                tbl,
                DefList [DefGroup [[t "1"]] [[Block sp Nothing (Paragraph Nothing [cs "n" [t "2"]])]]],
                BulletList [ListItem Nothing [Block sp Nothing (Paragraph Nothing [cs "n" [t "3"]])]]
              ],
      testCase "a paragraph style uses its own rules" $ do
        let r = rules [("body", [("[0-9]+", "n")]), ("quote", [("[a-z]+", "m")])]
        bodies r [Paragraph (Just "quote") [t "1a"]] @?= [Paragraph (Just "quote") [t "1", cs "m" [t "a"]]]
        bodies r [Paragraph (Just "verse") [t "1a"]] @?= [Paragraph (Just "verse") [t "1a"]],
      testCase "the span of a wrapper runs from its first to its last element" $ do
        let a = Text (mkSpan (FileId 1) 0 2) "1"
            b = Text (mkSpan (FileId 1) 5 7) "2"
        para digits [a, Kenten (mkSpan (FileId 1) 3 8) Nothing [b]] @?= [CharStyle (mkSpan (FileId 1) 0 8) "n" [a, Kenten (mkSpan (FileId 1) 3 8) Nothing [b]]],
      testCase "regexRules resolves based-on and leaves out empty lists" $ do
        let st =
              defaultStyle
                { stParaStyles =
                    Map.insert "body" noParaDef {psRegexStyles = Just [RegexStyleDef "[0-9]+" "bold"]}
                      $ Map.insert "quote" noParaDef {psBasedOn = Just "body"}
                      $ Map.insert "plain" noParaDef {psRegexStyles = Just []} (stParaStyles defaultStyle)
                }
            r = regexRules st
        Map.keys r @?= ["body", "caption", "quote", "sidenote", "verse"]
        map snd (Map.findWithDefault [] "quote" r) @?= ["bold"]
    ]
  where
    ruby segs = Ruby sp () [RubySegment [Text sp b | b <- bs] rd | (bs, rd) <- segs]
    ruby' segs = Ruby sp () [RubySegment bs rd | (bs, rd) <- segs]
