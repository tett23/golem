module Gen (genDocument, genInline, genExpr, genInt64) where

import Data.Text (Text)
import Data.Void (Void)
import Golem.Doc.IR
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Numeric.Natural (Natural)

genSpan :: Gen SrcSpan
genSpan = do
  s <- Gen.int (Range.linear 0 100)
  l <- Gen.int (Range.linear 0 20)
  pure (SrcSpan (FileId 0) s (s + l))

genText :: Gen Text
genText = Gen.text (Range.linear 0 8) (Gen.element ("aあ漢😀 [" :: String))

genInline :: Gen Inline
genInline = genInlineWith (Just (pure ()))

genNoRuby :: Gen InlineNoRuby
genNoRuby = genInlineWith (Nothing :: Maybe (Gen Void))

genInlineWith :: Maybe (Gen r) -> Gen (InlineF r)
genInlineWith mr =
  Gen.recursive
    Gen.choice
    ( [ Text <$> genSpan <*> genText,
        Tcy <$> genSpan <*> genText,
        Number <$> genSpan <*> genInt64 <*> Gen.maybe Gen.enumBounded,
        Ref <$> genSpan <*> Gen.enumBounded <*> genText,
        Deferred <$> genSpan <*> (DeferredExpr <$> genExpr),
        IndexMark <$> genSpan <*> (IndexEntry <$> Gen.list (Range.singleton 1) genText <*> Gen.list (Range.singleton 1) genText),
        Cite <$> genSpan <*> genText,
        ProofComment <$> genSpan <*> genText,
        LineBreak <$> genSpan,
        Aki <$> genSpan <*> Gen.choice [AkiZw <$> genRatio, AkiAbs <$> genNonNegative64],
        -- an item of a channel of a plugin (golem-doc ADR 0007)
        ChannelItem <$> genSpan <*> (ChannelItemData <$> genText <*> Gen.maybe genText <*> Gen.maybe genText <*> Gen.list (Range.linear 0 2) (Text <$> genSpan <*> genText))
      ]
        <> maybe [] (\gr -> [Ruby <$> genSpan <*> gr <*> Gen.list (Range.linear 1 3) (RubySegment <$> Gen.list (Range.linear 0 2) genNoRuby <*> Gen.maybe genText)]) mr
    )
    [ Kenten <$> genSpan <*> Gen.maybe genText <*> sub,
      Color <$> genSpan <*> genText <*> sub,
      CharStyle <$> genSpan <*> genText <*> sub,
      Note <$> genSpan <*> Gen.int (Range.linear 1 99) <*> sub,
      Sidenote <$> genSpan <*> Gen.int (Range.linear 1 99) <*> sub
    ]
  where
    sub = Gen.list (Range.linear 0 3) (genInlineWith mr)

{- | A non-negative amount in zw, in lowest terms as 'Rational' keeps it;
the numerator and the denominator reach the end of int64 (golem-doc ADR
0006).
-}
genRatio :: Gen Rational
genRatio =
  (\n d -> fromInteger n / fromInteger d)
    <$> Gen.choice [Gen.integral (Range.linear 0 40), genNonNegative64]
    <*> Gen.choice [Gen.integral (Range.linear 1 12), Gen.integral (Range.linear 1 maxInt64), pure maxInt64]

maxInt64, minInt64 :: Integer
maxInt64 = 2 ^ (63 :: Int) - 1
minInt64 = negate (2 ^ (63 :: Int))

-- | An integer of the CDDL @int64@, with its ends (golem-doc ADR 0006).
genInt64 :: Gen Integer
genInt64 =
  Gen.choice
    [ Gen.integral (Range.linearFrom 0 (-1000000000000) 1000000000000),
      Gen.integral (Range.linearFrom 0 minInt64 maxInt64),
      Gen.element [maxInt64, minInt64, maxInt64 - 1, minInt64 + 1, 4294967296, -4294967297]
    ]

-- | A natural number of the CDDL @uint64@ (docs/adr ADR 0102).
genNat :: Gen Natural
genNat = fromInteger <$> genNonNegative64

-- | A non-negative integer of the CDDL @int64@, with its end.
genNonNegative64 :: Gen Integer
genNonNegative64 = Gen.choice [Gen.integral (Range.linear 0 10000000), Gen.integral (Range.linear 0 maxInt64), pure maxInt64]

-- | Every kind of expression and every operator (golem-doc ADR 0001).
genExpr :: Gen (AST.Located AST.Expr)
genExpr =
  AST.Located
    <$> genSpan
    <*> Gen.recursive
      Gen.choice
      [ AST.ENat . fromInteger <$> genNonNegative64,
        AST.EInt <$> genInt,
        AST.ERat <$> genRatio,
        AST.EString <$> genText,
        AST.EBool <$> Gen.bool,
        pure AST.ENil,
        AST.EVar <$> Gen.list (Range.linear 1 3) genText,
        pure AST.EError
      ]
      [ AST.EArray <$> Gen.list (Range.linear 0 3) genExpr,
        AST.EHash <$> Gen.list (Range.linear 0 3) ((,) <$> genText <*> genExpr),
        AST.EBinary <$> Gen.element binaryOps <*> genExpr <*> genExpr,
        AST.EUnary AST.Negate <$> genExpr,
        AST.ECall <$> genText <*> Gen.list (Range.linear 0 2) genExpr
      ]

binaryOps :: [AST.BinaryOp]
binaryOps = [AST.Add, AST.Sub, AST.Mul, AST.Div, AST.Mod, AST.Pow, AST.OpEq, AST.OpNe, AST.OpLt, AST.OpLe, AST.OpGt, AST.OpGe]

-- | Integers of the CDDL @int64@ (golem-doc ADR 0006), with the ends of the CBOR heads.
genInt :: Gen Integer
genInt =
  Gen.choice
    [ Gen.integral (Range.linearFrom 0 (-100) 100),
      Gen.element [23, 24, 255, 256, 65535, 65536, 4294967295, 4294967296, maxInt64, -24, -25, minInt64],
      genInt64
    ]

genBlock :: Gen Block
genBlock =
  Block
    <$> genSpan
    <*> Gen.maybe genText
    <*> Gen.recursive
      Gen.choice
      [ Paragraph <$> Gen.maybe genText <*> inl,
        Heading <$> Gen.int (Range.linear 1 3) <*> attrs <*> inl,
        CodeBlock <$> genCode,
        ChannelOutput <$> Gen.choice [Gen.element [TocOutput 2, IndexOutput, BibliographyOutput], CustomOutput <$> genText <*> Gen.maybe genText],
        Table <$> Gen.list (Range.singleton 2) Gen.enumBounded <*> Gen.list (Range.singleton 2) inl <*> Gen.list (Range.linear 0 2) (Gen.list (Range.singleton 2) inl)
      ]
      [ BulletList <$> Gen.list (Range.linear 1 3) (ListItem <$> Gen.maybe genNat <*> Gen.list (Range.linear 0 2) genBlock),
        OrderedList <$> Gen.list (Range.linear 1 3) (ListItem Nothing <$> Gen.list (Range.linear 0 2) genBlock),
        DefList <$> Gen.list (Range.linear 1 2) (DefGroup <$> Gen.list (Range.linear 1 2) inl <*> Gen.list (Range.linear 1 2) (Gen.list (Range.linear 0 2) genBlock)),
        FigureBlock <$> (Figure <$> genText <*> Gen.maybe genText <*> genText <*> Gen.maybe Gen.enumBounded <*> Gen.maybe genText <*> Gen.list (Range.linear 0 1) genBlock <*> Gen.maybe (Gen.integral (Range.linear 1 9)) <*> Gen.bool)
      ]
  where
    inl = Gen.list (Range.linear 0 3) genInline
    attrs = HeadingAttrs <$> Gen.maybe inl <*> Gen.maybe genNat <*> Gen.bool <*> Gen.bool

genCode :: Gen Code
genCode =
  Code
    <$> Gen.maybe genText
    <*> Gen.maybe Gen.bool
    <*> Gen.maybe genText
    <*> Gen.maybe (Gen.list (Range.linear 0 2) genInline)
    <*> Gen.bool
    <*> Gen.list (Range.linear 0 3) (CodeLine <$> genText <*> Gen.maybe genNat <*> Gen.maybe Gen.enumBounded <*> Gen.bool <*> Gen.list (Range.linear 0 2) (Gen.int (Range.linear 1 50)))

genDocument :: Gen Document
genDocument = Document (FileId 0) <$> Gen.list (Range.linear 0 5) genTopBlock

-- | A block at the top of a document, where a forced break may stand (docs/adr ADR 0017).
genTopBlock :: Gen Block
genTopBlock =
  Gen.frequency
    [ (5, genBlock),
      (1, Block <$> genSpan <*> pure Nothing <*> (ForcedBreak <$> Gen.enumBounded)),
      -- a manual control of page breaks (docs/adr ADR 0030)
      ( 1,
        Block
          <$> genSpan
          <*> pure Nothing
          <*> ( PageControl
                  <$> Gen.choice
                    [ pure NoBreak,
                      NeedLines <$> Gen.int (Range.linear 1 40),
                      AdjustLines <$> Gen.filter (/= 0) (Gen.int (Range.linear (-5) 5))
                    ]
              )
      ),
      -- blank lines (docs/adr ADR 0046)
      (1, Block <$> genSpan <*> pure Nothing <*> (BlankLines <$> Gen.int64 (Range.exponential 1 maxBound)))
    ]
