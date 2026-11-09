{- | The generators make every constructor of the semantic IR
(docs/adr/0191).

'blockKind' and 'inlineKind' name every constructor with no wildcard, so
a constructor added to the IR stops the compilation of this suite
(-Werror=incomplete-patterns) until it has a kind here too; the property
then fails with too little coverage until the generators make it.
-}
module Main (main) where

import CborExprSpec qualified
import CborSpec qualified
import Data.Foldable (for_)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.String (fromString)
import Golem.Doc.IR
import Golem.DocGen (genDocument)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import Hedgehog
import Test.Tasty
import Test.Tasty.Hedgehog

-- | The constructors of 'BlockBody'.
data BlockKind
  = KParagraph
  | KHeading
  | KBulletList
  | KOrderedList
  | KDefList
  | KTable
  | KCodeBlock
  | KFigureBlock
  | KChannelOutput
  | KForcedBreak
  | KPageControl
  | KBlankLines
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The constructors of 'InlineF'.
data InlineKind
  = KText
  | KRuby
  | KKenten
  | KColor
  | KCharStyle
  | KTcy
  | KNumber
  | KRef
  | KDeferred
  | KNote
  | KSidenote
  | KIndexMark
  | KCite
  | KProofComment
  | KLineBreak
  | KAki
  | KChannelItem
  | KLink
  | KLang
  | KResolved
  deriving stock (Eq, Ord, Show, Enum, Bounded)

blockKind :: BlockBody -> BlockKind
blockKind = \case
  Paragraph {} -> KParagraph
  Heading {} -> KHeading
  BulletList {} -> KBulletList
  OrderedList {} -> KOrderedList
  DefList {} -> KDefList
  TableBlock _ -> KTable
  CodeBlock {} -> KCodeBlock
  FigureBlock {} -> KFigureBlock
  ChannelOutput {} -> KChannelOutput
  ForcedBreak {} -> KForcedBreak
  PageControl {} -> KPageControl
  BlankLines {} -> KBlankLines

inlineKind :: InlineF r -> InlineKind
inlineKind = \case
  Text {} -> KText
  Ruby {} -> KRuby
  Kenten {} -> KKenten
  Color {} -> KColor
  CharStyle {} -> KCharStyle
  Tcy {} -> KTcy
  Number {} -> KNumber
  Ref {} -> KRef
  Deferred {} -> KDeferred
  Note {} -> KNote
  Sidenote {} -> KSidenote
  IndexMark {} -> KIndexMark
  Cite {} -> KCite
  ProofComment {} -> KProofComment
  LineBreak {} -> KLineBreak
  Aki {} -> KAki
  ChannelItem {} -> KChannelItem
  Link {} -> KLink
  Lang {} -> KLang
  Resolved {} -> KResolved

-- | The kinds of the blocks and the inlines in a document, at any depth.
kinds :: Document -> (Set BlockKind, Set InlineKind)
kinds = foldMap block . docBlocks
  where
    block b = (Set.singleton (blockKind (blockBody b)), mempty) <> body (blockBody b)
    blocks = foldMap block
    body = \case
      Paragraph _ is -> inlines is
      Heading _ a is -> foldMap inlines (haTocTitle a) <> inlines is
      BulletList items -> foldMap (blocks . itemBlocks) items
      OrderedList items -> foldMap (blocks . itemBlocks) items
      DefList gs -> foldMap (\g -> foldMap inlines (dgTerms g) <> foldMap blocks (dgDefs g)) gs
      TableBlock Table {tableHeader = hs, tableRows = rows} -> foldMap inlines hs <> foldMap (foldMap inlines) rows
      CodeBlock c -> foldMap inlines (codeCaption c)
      FigureBlock f -> blocks (figCaption f)
      ChannelOutput _ -> mempty
      ForcedBreak _ -> mempty
      PageControl _ -> mempty
      BlankLines _ -> mempty
    inlines :: [InlineF r] -> (Set BlockKind, Set InlineKind)
    inlines = foldMap inline
    inline :: InlineF r -> (Set BlockKind, Set InlineKind)
    inline i = (mempty, Set.singleton (inlineKind i)) <> children i
    children :: InlineF r -> (Set BlockKind, Set InlineKind)
    children = \case
      Ruby _ _ segs -> foldMap (inlines . rsBase) segs
      Kenten _ _ is -> inlines is
      Color _ _ is -> inlines is
      CharStyle _ _ is -> inlines is
      Note _ _ is -> inlines is
      Sidenote _ _ is -> inlines is
      ChannelItem _ c -> inlines (ciBody c)
      Link _ _ is -> inlines is
      Lang _ _ is -> inlines is
      Resolved _ _ _ is -> inlines is
      Text {} -> mempty
      Tcy {} -> mempty
      Number {} -> mempty
      Ref {} -> mempty
      Deferred {} -> mempty
      IndexMark {} -> mempty
      Cite {} -> mempty
      ProofComment {} -> mempty
      LineBreak {} -> mempty
      Aki {} -> mempty

main :: IO ()
main = defaultMainReportingSkips (const tests)

tests :: TestTree
tests =
  testGroup
    "golem-doc-gen"
    [ -- the rarest kinds are in about 5% of the documents (2026-11-07):
      -- in 1000 documents, too few to cover 1% is far from chance,
      -- where in the 100 of the default it is not (docs/adr/0191)
      testProperty "the generators make every constructor of the IR" $ withTests 1000 $ property $ do
        (bs, is) <- kinds <$> forAll genDocument
        for_ [minBound .. maxBound] $ \k -> cover 1 (fromString ("block " <> show k)) (k `Set.member` bs)
        -- the generators make the IR of the evaluation (S0), which has no resolved reference (docs/adr/0215)
        for_ [k | k <- [minBound .. maxBound], k /= KResolved] $ \k -> cover 1 (fromString ("inline " <> show k)) (k `Set.member` is),
      -- the properties of golem-doc that use the generators (docs/adr/0197)
      CborSpec.tests,
      CborExprSpec.tests
    ]
