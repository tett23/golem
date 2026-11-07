{- | The structure of composed inlines and the leaves of their boxes, for
the structure tree of the PDF (docs/adr ADR 0183).
-}
module StructureSpec (structureTests) where

import Data.Text (Text)
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.Syntax (FileId (..), mkSpan)
import Test.Tasty
import Test.Tasty.HUnit

env :: ComposeEnv
env = (defaultComposeEnv fs) {ceRestyle = \lk -> \case IR.CharStyle _ "code" _ -> lk {lkCode = True}; _ -> lk, ceSite = [7, 0]}

txt :: Text -> IR.Inline
txt = IR.Text sp

-- | The text and the leaf of each box.
leaves :: [Item] -> [(Text, Leaf)]
leaves items = [(bcText c, bcLeaf c) | Box _ c <- items, bcText c /= ""]

structureTests :: TestTree
structureTests =
  testGroup
    "the structure of inlines (docs/adr ADR 0183)"
    [ testCase "plain text is leaf 0 of the site" $ do
        let (items, _, nodes) = composeInlinesTree env [txt "あい"]
        nodes @?= [NodeLeaf 0]
        leaves items @?= [("あ", Leaf [7, 0] 0), ("い", Leaf [7, 0] 0)],
      testCase "a ruby with a reading is a Ruby of its base and reading; the text after it is a new leaf" $ do
        let ruby = IR.Ruby sp () [IR.RubySegment [IR.Text sp "漢"] (Just "かん")]
            (items, _, nodes) = composeInlinesTree env [txt "あ", ruby, txt "い"]
        nodes @?= [NodeLeaf 0, NodeElem RoleRuby [NodeElem RoleRubyBase [NodeLeaf 1], NodeElem RoleRubyText [NodeLeaf 2]], NodeLeaf 3]
        leaves items @?= [("あ", Leaf [7, 0] 0), ("漢|かん", Leaf [7, 0] 1), ("い", Leaf [7, 0] 3)],
      testCase "a segment without a reading stays in the content" $ do
        let ruby = IR.Ruby sp () [IR.RubySegment [IR.Text sp "漢"] (Just "かん"), IR.RubySegment [IR.Text sp "字"] Nothing]
            (_, _, nodes) = composeInlinesTree env [ruby]
        nodes @?= [NodeLeaf 0, NodeElem RoleRuby [NodeElem RoleRubyBase [NodeLeaf 1], NodeElem RoleRubyText [NodeLeaf 2]], NodeLeaf 3],
      testCase "a note mark is a Reference, then the note; two notes of one span count apart" $ do
        let nsp = mkSpan (FileId 1) 3 9
            note = IR.Note nsp 1 [txt "注"]
            (items, _, nodes) = composeInlinesTree env [txt "あ", note, note]
        nodes @?= [NodeLeaf 0, NodeElem RoleReference [NodeLeaf 1], NodeNote nsp 0 1 [txt "注"], NodeLeaf 2, NodeElem RoleReference [NodeLeaf 3], NodeNote nsp 1 1 [txt "注"], NodeLeaf 4]
        [l | (t, l) <- leaves items, t /= "あ"] @?= [Leaf [7, 0] 1, Leaf [7, 0] 3],
      testCase "code inside text is a Code; colour is not an element" $ do
        let (_, _, nodes) = composeInlinesTree env [IR.Color sp "red" [txt "a", IR.CharStyle sp "code" [txt "x"]], txt "b"]
        nodes @?= [NodeLeaf 0, NodeElem RoleCode [NodeLeaf 1], NodeLeaf 2],
      testCase "the label inlines are a label element" $ do
        let (items, _, nodes) = composeInlinesTree env {ceLabelInlines = 1} [txt "*1", txt "注"]
        nodes @?= [NodeElem RoleLabel [NodeLeaf 0], NodeLeaf 1]
        leaves items @?= [("*1", Leaf [7, 0] 0), ("注", Leaf [7, 0] 1)]
    ]
