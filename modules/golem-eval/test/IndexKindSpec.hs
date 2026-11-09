-- | The range and the reference of [index] (docs/adr/0265).
module IndexKindSpec (tests) where

import Data.Text (Text)
import Golem.Doc.IR
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | The index marks of a source and the codes of its diagnostics.
marksOf :: Text -> ([IndexEntry], [Text])
marksOf src =
  let (ds, r) = evalSource baseCtx src
   in ([e | Paragraph _ xs <- resultBodies r, IndexMark _ e <- xs], map diagCodeText ds)

tests :: TestTree
tests =
  testGroup
    "the range and the reference of [index] (docs/adr/0265)"
    [ testCase "a mark without range nor see is a point" $
        marksOf "[index reading=くみはん: 組版]\n" @?= ([IndexEntry ["組版"] ["くみはん"] IndexPoint], []),
      testCase "range=begin and range=end are the two ends of a range" $ do
        marksOf "[index reading=くみはん range=begin: 組版]\n" @?= ([IndexEntry ["組版"] ["くみはん"] IndexRangeBegin], [])
        marksOf "[index reading=くみはん/わぶん range=end: 組版/和文]\n" @?= ([IndexEntry ["組版", "和文"] ["くみはん", "わぶん"] IndexRangeEnd], []),
      testCase "see is an automatic reference to one level or two" $ do
        marksOf "[index reading=たいぷせってぃんぐ see=組版: タイプセッティング]\n" @?= ([IndexEntry ["タイプセッティング"] ["たいぷせってぃんぐ"] (IndexSee SeeAuto ["組版"])], [])
        marksOf "[index reading=わぶんくみはん see=組版/和文組版: 和文組版]\n" @?= ([IndexEntry ["和文組版"] ["わぶんくみはん"] (IndexSee SeeAuto ["組版", "和文組版"])], []),
      testCase "G02144: a range neither begin nor end, alone" $ do
        marksOf "[index reading=くみはん range=start: 組版]\n" @?= ([], ["G02144"])
        marksOf "[index reading=くみはん range=\"\": 組版]\n" @?= ([], ["G02144"]),
      testCase "G02145: see and range on one mark, alone" $ do
        marksOf "[index reading=くみはん see=印刷 range=begin: 組版]\n" @?= ([], ["G02145"])
        marksOf "[index reading=くみはん range=end see=印刷: 組版]\n" @?= ([], ["G02145"]),
      testCase "G02146: a target of three levels or of an empty level, alone" $ do
        marksOf "[index reading=くみはん see=a/b/c: 組版]\n" @?= ([], ["G02146"])
        marksOf "[index reading=くみはん see=a/: 組版]\n" @?= ([], ["G02146"])
        marksOf "[index reading=くみはん see=/b: 組版]\n" @?= ([], ["G02146"])
        marksOf "[index reading=くみはん see=\"\": 組版]\n" @?= ([], ["G02146"])
    ]
