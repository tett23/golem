module Gen (genDocument, genInline, genExpr, genFloat) where

import Data.Text (Text)
import Data.Void (Void)
import Golem.Doc.IR
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range

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
        Number <$> genSpan <*> Gen.integral (Range.linearFrom 0 (-1000000000000) 1000000000000) <*> Gen.maybe Gen.enumBounded,
        Ref <$> genSpan <*> Gen.enumBounded <*> genText,
        Deferred <$> genSpan <*> (DeferredExpr <$> genExpr),
        IndexMark <$> genSpan <*> (IndexEntry <$> Gen.list (Range.singleton 1) genText <*> Gen.list (Range.singleton 1) genText),
        Cite <$> genSpan <*> genText,
        ProofComment <$> genSpan <*> genText,
        LineBreak <$> genSpan,
        Aki <$> genSpan <*> Gen.choice [AkiZw <$> genRatio, AkiAbs <$> Gen.integral (Range.linear 0 10000000)]
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

-- | A non-negative amount in zw, in lowest terms as 'Rational' keeps it.
genRatio :: Gen Rational
genRatio = (\n d -> fromInteger n / fromInteger d) <$> Gen.integral (Range.linear 0 40) <*> Gen.integral (Range.linear 1 12)

-- | Every kind of expression and every operator (golem-doc ADR 0001).
genExpr :: Gen (AST.Located AST.Expr)
genExpr =
  AST.Located
    <$> genSpan
    <*> Gen.recursive
      Gen.choice
      [ AST.EInt <$> genInt,
        AST.EFloat <$> genFloat,
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

-- | Integers within the CBOR major types 0 and 1 (the CDDL @int@), with their ends.
genInt :: Gen Integer
genInt =
  Gen.choice
    [ Gen.integral (Range.linearFrom 0 (-100) 100),
      Gen.element [23, 24, 255, 256, 65535, 65536, 4294967295, 4294967296, 18446744073709551615, -24, -25, -18446744073709551616]
    ]

{- | Floats at the edges of the half, single and double precision encodings
(RFC 8949 preferred serialization).
-}
genFloat :: Gen Double
genFloat =
  Gen.choice
    [ Gen.element
        [ 0,
          0.5,
          -2.5,
          65504, -- the largest half
          65520, -- rounds past the largest half: single
          6.103515625e-5, -- 2^-14, the smallest normal half
          5.960464477539063e-8, -- 2^-24, the smallest subnormal half
          2.9802322387695312e-8, -- 2^-25: single
          1.0009765625, -- 1 + 2^-10: half
          1.00048828125, -- 1 + 2^-11: single
          3.4028234663852886e38, -- the largest single
          1.401298464324817e-45, -- the smallest subnormal single
          0.1, -- double
          1.5e-7,
          2.675,
          1e300,
          5.0e-324, -- the smallest subnormal double
          1.7976931348623157e308 -- the largest double
        ],
      Gen.double (Range.exponentialFloatFrom 0 (-1e30) 1e30)
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
        ChannelOutput <$> Gen.element [TocOutput 2, IndexOutput, BibliographyOutput],
        Table <$> Gen.list (Range.singleton 2) Gen.enumBounded <*> Gen.list (Range.singleton 2) inl <*> Gen.list (Range.linear 0 2) (Gen.list (Range.singleton 2) inl)
      ]
      [ BulletList <$> Gen.list (Range.linear 1 3) (ListItem <$> Gen.maybe (Gen.integral (Range.linear 1 9)) <*> Gen.list (Range.linear 0 2) genBlock),
        OrderedList <$> Gen.list (Range.linear 1 3) (ListItem Nothing <$> Gen.list (Range.linear 0 2) genBlock),
        DefList <$> Gen.list (Range.linear 1 2) (DefGroup <$> Gen.list (Range.linear 1 2) inl <*> Gen.list (Range.linear 1 2) (Gen.list (Range.linear 0 2) genBlock)),
        FigureBlock <$> (Figure <$> genText <*> Gen.maybe genText <*> genText <*> Gen.maybe Gen.enumBounded <*> Gen.maybe genText <*> Gen.list (Range.linear 0 1) genBlock <*> Gen.maybe (Gen.int (Range.linear 1 9)))
      ]
  where
    inl = Gen.list (Range.linear 0 3) genInline
    attrs = HeadingAttrs <$> Gen.maybe inl <*> Gen.maybe (Gen.integral (Range.linear 1 9)) <*> Gen.bool <*> Gen.bool

genCode :: Gen Code
genCode =
  Code
    <$> Gen.maybe genText
    <*> Gen.maybe Gen.bool
    <*> Gen.maybe genText
    <*> Gen.maybe (Gen.list (Range.linear 0 2) genInline)
    <*> Gen.bool
    <*> Gen.list (Range.linear 0 3) (CodeLine <$> genText <*> Gen.maybe (Gen.integral (Range.linear 0 99)) <*> Gen.maybe Gen.enumBounded <*> Gen.bool <*> Gen.list (Range.linear 0 2) (Gen.int (Range.linear 1 50)))

genDocument :: Gen Document
genDocument = Document (FileId 0) <$> Gen.list (Range.linear 0 5) genTopBlock

-- | A block at the top of a document, where a forced break may stand (docs/adr ADR 0017).
genTopBlock :: Gen Block
genTopBlock =
  Gen.frequency
    [ (5, genBlock),
      (1, Block <$> genSpan <*> pure Nothing <*> (ForcedBreak <$> Gen.enumBounded))
    ]
