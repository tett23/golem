{- | The structure of composed inlines and the leaves of their boxes, for
the structure tree of the PDF (docs/adr ADR 0183).
-}
module StructureSpec (structureTests) where

import Control.Monad (forM_, replicateM)
import Data.List (elemIndex, sortOn)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
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

-- | A part of a ruby base in the tests of docs/adr/0393: a character, a [ref-number] or a [ref-title].
data BasePart = PartChar | PartNumber | PartTitle
  deriving stock (Eq, Show)

{- | A ruby of the segments given, each its parts and whether it has a
reading, between the texts 前 and 後; each character a different one. The
inlines, the text of the bases in source order, and the text of each
reference in source order, with whether its segment has a reading.
-}
rubyOfSegments :: [([BasePart], Bool)] -> ([IR.Inline], Text, [(Bool, Text)])
rubyOfSegments segs =
  let fresh = map T.singleton ['一' ..]
      go _ [] = []
      go cs ((parts, reading) : rest) =
        let (inls, refs, cs') = segParts cs parts
         in ((inls, reading), refs) : go cs' rest
      segParts cs = \case
        [] -> ([], [], cs)
        part : more ->
          let (inl, ref, cs1) = case (part, cs) of
                (PartChar, c : r) -> (IR.Text sp c, Nothing, r)
                (PartNumber, c : r) -> (IR.Resolved sp IR.RefNumber "h" [IR.Text sp c], Just c, r)
                (PartTitle, c : d : r) -> (IR.Resolved sp IR.RefTitle "t" [IR.Text sp (c <> d)], Just (c <> d), r)
                _ -> error "no characters left"
              (inls, refs, cs2) = segParts cs1 more
           in (inl : inls, maybe refs (: refs) ref, cs2)
      built = go fresh segs
      ruby = IR.Ruby sp () [IR.RubySegment inls (if reading then Just "よ" else Nothing) | ((inls, reading), _) <- built]
      baseText = T.concat [t | ((inls, _), _) <- built, inl <- inls, t <- textOf inl]
      textOf = \case
        IR.Text _ t -> [t]
        IR.Resolved _ _ _ xs -> concatMap textOf xs
        _ -> []
   in ([txt "前", ruby, txt "後"], baseText, [(reading, r) | ((_, reading), refs) <- built, r <- refs])

-- | Every ruby of up to three segments, each of up to two parts, with a reading or without.
everyRubyOfSegments :: [[([BasePart], Bool)]]
everyRubyOfSegments =
  let seg = [(parts, reading) | n <- [0 .. 2], parts <- replicateM n [PartChar, PartNumber, PartTitle], reading <- [True, False]]
   in concatMap (`replicateM` seg) [1 .. 3]

-- | The leaves of inline nodes in the order of the structure tree.
leafOrder :: [InlineNode] -> [Int]
leafOrder = concatMap $ \case
  NodeLeaf n -> [n]
  NodeElem _ ns -> leafOrder ns
  NodeLink _ _ ns -> leafOrder ns
  _ -> []

-- | The References of inline nodes in tree order, each with whether it is inside a Ruby and its leaves.
referencesIn :: Bool -> [InlineNode] -> [(Bool, [Int])]
referencesIn inRuby = concatMap $ \case
  NodeElem RoleReference ns -> [(inRuby, leafOrder ns)] <> referencesIn inRuby ns
  NodeElem RoleRuby ns -> referencesIn True ns
  NodeElem _ ns -> referencesIn inRuby ns
  NodeLink _ _ ns -> referencesIn inRuby ns
  _ -> []

{- | Each base character of the boxes, a ruby's reading left out, with the
leaf it is drawn in: a base character's own leaf (lkRubyBaseLeaf) or that
of its box.
-}
charLeaves :: [Item] -> [(Text, Int)]
charLeaves items =
  concat
    [ if boxKind c `elem` [KindRuby, KindGroupRuby]
        then [(u, fromMaybe (leafIndex (bcLeaf c)) (lkRubyBaseLeaf lk)) | (u, lk) <- zip (map T.singleton (T.unpack (fst (T.breakOn "|" (bcText c))))) (bcBaseLooks c <> repeat (bcLook c))]
        else [(T.singleton ch, leafIndex (bcLeaf c)) | ch <- T.unpack (bcText c)]
    | Box _ c <- items
    ]

-- | The characters of the leaves given, in the order of the structure tree.
textInTreeOrder :: [Int] -> [(Text, Int)] -> Either String Text
textInTreeOrder order chars =
  case [l | (_, l) <- chars, l `notElem` order] of
    [] -> Right (T.concat (map fst (sortOn (\(_, l) -> elemIndex l order) chars)))
    missing -> Left ("leaves not in the tree: " <> show missing)

structureTests :: TestTree
structureTests =
  testGroup
    "the structure of inlines (docs/adr ADR 0183)"
    [ testCase "ADR 0393 I1: inv1_ruby_references_property: each reference in a ruby base is exactly one Reference, with or without a reading" $
        forM_ everyRubyOfSegments $ \segs -> do
          let (inls, _, refs) = rubyOfSegments segs
              (items, _, nodes) = composeInlinesTree env inls
              found = referencesIn False nodes
              chars = charLeaves items
          assertEqual (show segs) (length refs) (length found)
          -- each Reference draws the text of its reference, in source order
          assertEqual (show segs) (map snd refs) [T.concat [t | (t, l) <- chars, l `elem` ls] | (_, ls) <- found],
      testCase "ADR 0393 I2: inv2_ruby_references_property: a reference in a segment without a reading is a Reference outside the Ruby" $
        forM_ everyRubyOfSegments $ \segs -> do
          let (inls, _, refs) = rubyOfSegments segs
              (_, _, nodes) = composeInlinesTree env inls
          assertEqual (show segs) (map fst refs) (map fst (referencesIn False nodes)),
      testCase "ADR 0393 I3: inv3_ruby_references_property: the characters of the bases are in the leaves once each, in source order" $
        forM_ everyRubyOfSegments $ \segs -> do
          let (inls, base, _) = rubyOfSegments segs
              (items, _, nodes) = composeInlinesTree env inls
          assertEqual (show segs) (Right ("前" <> base <> "後")) (textInTreeOrder (leafOrder nodes) (charLeaves items)),
      testCase "ADR 0360 I1: inv1_ruby_base_references_property: each number or title in a ruby base is one Reference under its RB" $
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
