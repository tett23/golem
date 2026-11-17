{- | The structure of composed inlines and the leaves of their boxes, for
the structure tree of the PDF (docs/adr ADR 0183).
-}
module StructureSpec (structureTests) where

import Control.Monad (replicateM)
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

{- | ADR 0360 I1: a ruby base of a character and the parts given (Nothing
a character, Just a reference of the kind) has one Reference under its RB
per reference, and none under its RT.
-}
rubyBaseReferences :: [Maybe IR.RefKind] -> Assertion
rubyBaseReferences parts = do
  let part = \case
        Nothing -> IR.Text sp "x"
        Just IR.RefNumber -> IR.Resolved sp IR.RefNumber "h" [IR.Text sp "1"]
        Just k -> IR.Resolved sp k "t" [IR.Text sp "題"]
      base = IR.Text sp "a" : map part parts
      (_, _, nodes) = composeInlinesTree env [IR.Ruby sp () [IR.RubySegment base (Just "reading")]]
      inRb = [rb | NodeElem RoleRuby ruby <- nodes, NodeElem RoleRubyBase rb <- ruby]
      inRt = [rt | NodeElem RoleRuby ruby <- nodes, NodeElem RoleRubyText rt <- ruby]
      references ns = [() | NodeElem RoleReference _ <- ns]
  assertEqual (show parts) [length (filter (/= Nothing) parts)] (map (length . references) inRb)
  assertEqual (show parts) [0] (map (length . references) inRt)

structureTests :: TestTree
structureTests =
  testGroup
    "the structure of inlines (docs/adr ADR 0183)"
    [ testCase "ADR 0360 I1: inv1_ruby_base_references_property: each number or title in a ruby base is one Reference under its RB" $
        mapM_ rubyBaseReferences (concatMap (`replicateM` [Nothing, Just IR.RefNumber, Just IR.RefTitle]) [0 .. 4]),
      testCase "plain text is leaf 0 of the site" $ do
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
            note = IR.Note nsp 1 (IR.noteBody nsp [txt "注"])
            (items, _, nodes) = composeInlinesTree env [txt "あ", note, note]
        nodes @?= [NodeLeaf 0, NodeElem RoleReference [NodeLeaf 1], NodeNote nsp 0 1 [[txt "注"]], NodeLeaf 2, NodeElem RoleReference [NodeLeaf 3], NodeNote nsp 1 1 [[txt "注"]], NodeLeaf 4]
        [l | (t, l) <- leaves items, t /= "あ"] @?= [Leaf [7, 0] 1, Leaf [7, 0] 3],
      testCase "code inside text is a Code; colour is not an element" $ do
        let (_, _, nodes) = composeInlinesTree env [IR.Color sp "red" [txt "a", IR.CharStyle sp "code" [txt "x"]], txt "b"]
        nodes @?= [NodeLeaf 0, NodeElem RoleCode [NodeLeaf 1], NodeLeaf 2],
      testCase "the label inlines are a label element" $ do
        let (items, _, nodes) = composeInlinesTree env {ceLabelInlines = 1} [txt "*1", txt "注"]
        nodes @?= [NodeElem RoleLabel [NodeLeaf 0], NodeLeaf 1]
        leaves items @?= [("*1", Leaf [7, 0] 0), ("注", Leaf [7, 0] 1)],
      testCase "R3: [ref-number] and [ref-title] resolved are a Reference each, with what they hold inside (docs/adr/0215)" $ do
        let number = IR.Resolved sp IR.RefNumber "design" [txt "2"]
            title = IR.Resolved sp IR.RefTitle "design" [IR.Ruby sp () [IR.RubySegment [IR.Text sp "設計"] (Just "せっけい")]]
            (items, _, nodes) = composeInlinesTree env [txt "第", number, txt "章「", title, txt "」"]
        nodes
          @?= [ NodeLeaf 0,
                NodeElem RoleReference [NodeLeaf 1],
                NodeLeaf 2,
                NodeElem RoleReference [NodeLeaf 3, NodeElem RoleRuby [NodeElem RoleRubyBase [NodeLeaf 4], NodeElem RoleRubyText [NodeLeaf 5]], NodeLeaf 6],
                NodeLeaf 7
              ]
        leaves items @?= [("第", Leaf [7, 0] 0), ("2", Leaf [7, 0] 1), ("章", Leaf [7, 0] 2), ("「", Leaf [7, 0] 2), ("設計|せっけい", Leaf [7, 0] 4), ("」", Leaf [7, 0] 7)],
      testCase "R4: a resolved reference sets the same boxes as what it holds (docs/adr/0215)" $ do
        let held = [txt "2", IR.CharStyle sp "code" [txt "x"]]
            boxes is = [(bcText c, w) | Box w c <- let (items, _, _) = composeInlinesTree env is in items]
        boxes [txt "第", IR.Resolved sp IR.RefNumber "a" held, txt "章"] @?= boxes ([txt "第"] <> held <> [txt "章"])
    ]
