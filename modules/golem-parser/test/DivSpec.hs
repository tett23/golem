{- | The blocks between ::: lines that a block command takes as its body
(root ADR 0459): the line that opens, the line that closes, nesting, the
blank line before a close after a block command, code blocks, the open
left unclosed (G01030), one block alone (G01031), and ::: elsewhere.
-}
module DivSpec (tests) where

import Data.List (isInfixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Parser
import Golem.Parser.AST qualified as A
import Golem.Parser.CST (render)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

fid :: FileId
fid = FileId 0

-- | The codes of the diagnostics of the parser.
codes :: Text -> [Text]
codes src = [c | DiagnosticCode c <- map diagCode (snd (parse fid src))]

-- | The blocks at the top of the file.
top :: Text -> [A.Located A.Block]
top src = let (f, _, _) = parseAst fid src in A.fileBlocks f

-- | Whether a text ::: is left in the AST.
textLeft :: Text -> Bool
textLeft src = "Text \":::\"" `isInfixOf` show (top src)

-- | The start and the end of each diagnostic of a code.
sitesOf :: Text -> Text -> [(Int, Int)]
sitesOf code src = [(spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- snd (parse fid src), diagCode d == DiagnosticCode code]

tests :: TestTree
tests =
  testGroup
    "::: (root ADR 0459)"
    [ testCase "root ADR 0459 I3: ::: right after a paragraph closes the body" $ do
        let src = "@x\n:::\n一\n\n二\n:::\n後\n"
        codes src @?= []
        length (top src) @?= 2
        assertBool "no text :::" (not (textLeft src))
        render (fst (parse fid src)) @?= src,
      testCase "root ADR 0459 I3: a heading and blank lines are in the body" $ do
        let src = "@x\n:::\n# 見出し\n\n\n一\n\n- 項目\n:::\n"
        codes src @?= []
        length (top src) @?= 1
        assertBool "no text :::" (not (textLeft src)),
      testCase "root ADR 0459 I3: ::: in a code block is a line of code" $ do
        let src = "@x\n:::\n```\n:::\n```\n\n二\n:::\n"
        codes src @?= []
        length (top src) @?= 1
        assertBool "the code keeps :::" ("\":::\"" `isInfixOf` show (top src)),
      testCase "root ADR 0459 I3: a blank line before ::: after a block command closes the body" $ do
        let src = "@x\n:::\n一\n\n@figure x.png\n\n:::\n"
        codes src @?= []
        length (top src) @?= 1,
      testCase "root ADR 0459 I3: ::: right after a block command inside opens a nested body" $ do
        let src = "@x\n:::\n@note n\n:::\n注一\n\n注二\n:::\n\n一\n:::\n\n後\n"
        codes src @?= []
        length (top src) @?= 2
        assertBool "no text :::" (not (textLeft src)),
      testCase "root ADR 0459 I3: ::: in an indented body" $ do
        let src = "@a\n  @b\n  :::\n  一\n\n  二\n  :::\n"
        codes src @?= []
        length (top src) @?= 1
        assertBool "no text :::" (not (textLeft src)),
      testCase "root ADR 0459 I4: an unclosed ::: is G01030 at the line that opens it" $ do
        let src = "前\n\n@x\n:::\n一\n\n二\n"
        codes src @?= ["G01030"]
        sitesOf "G01030" src @?= [(8, 11)],
      testCase "root ADR 0459 I4: ::: at the end of the file is G01030" $
        codes "@x\n:::" @?= ["G01030"],
      testCase "root ADR 0459 I4: ::: right after a block command at the end opens a nested body: two G01030" $
        codes "@x\n:::\n一\n\n@figure x.png\n:::\n" @?= ["G01030", "G01030"],
      testCase "root ADR 0459 I4: an unclosed ::: in an indented body ends with the body" $ do
        let src = "@a\n  @b\n  :::\n  一\n\n後\n"
        codes src @?= ["G01030"]
        length (top src) @?= 2,
      testCase "root ADR 0459 I1: one block between ::: lines is G01031, an info" $ do
        codes "@x\n:::\n一\n:::\n" @?= ["G01031"]
        [diagSeverity d | d <- snd (parse fid "@x\n:::\n一\n:::\n")] @?= [Info]
        sitesOf "G01031" "@x\n:::\n一\n:::\n" @?= [(3, 6)],
      testCase "root ADR 0459 I5: ::: that neither opens nor closes is text" $ do
        mapM_
          (\src -> assertBool (T.unpack src) (textLeft src && null (codes src)))
          [ "本文\n:::\n続き\n",
            ":::\n",
            "@label x\n本文\n:::\n",
            "@x\n  一\n:::\n",
            "@x\n\n:::\n"
          ]
        render (fst (parse fid "本文\n:::\n続き\n")) @?= "本文\n:::\n続き\n"
        codes "@label x\n\\:::\n" @?= []
        length (top "@label x\n\\:::\n") @?= 1
    ]
