module Gen (genDocument, genInline) where

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
        ProofComment <$> genSpan <*> genText
      ]
        <> maybe [] (\gr -> [Ruby <$> genSpan <*> gr <*> Gen.list (Range.linear 1 3) (RubySegment <$> Gen.list (Range.linear 0 2) genNoRuby <*> Gen.maybe genText)]) mr
    )
    [ Strong <$> genSpan <*> sub,
      Bold <$> genSpan <*> sub,
      Italic <$> genSpan <*> sub,
      Kenten <$> genSpan <*> Gen.maybe genText <*> sub,
      Color <$> genSpan <*> genText <*> sub,
      CharStyle <$> genSpan <*> genText <*> sub,
      Note <$> genSpan <*> Gen.int (Range.linear 1 99) <*> sub,
      Sidenote <$> genSpan <*> Gen.int (Range.linear 1 99) <*> sub
    ]
  where
    sub = Gen.list (Range.linear 0 3) (genInlineWith mr)

genExpr :: Gen (AST.Located AST.Expr)
genExpr =
  AST.Located
    <$> genSpan
    <*> Gen.recursive
      Gen.choice
      [ AST.EInt <$> Gen.integral (Range.linearFrom 0 (-100) 100),
        AST.EFloat <$> Gen.element [0.5, 1.5e-7, 2.675, 1e300, 65504, 0.1],
        AST.EString <$> genText,
        AST.EBool <$> Gen.bool,
        pure AST.ENil,
        AST.EVar <$> Gen.list (Range.linear 1 3) genText
      ]
      [ AST.EArray <$> Gen.list (Range.linear 0 3) genExpr,
        AST.EBinary <$> Gen.element [AST.Add, AST.Pow, AST.OpGe] <*> genExpr <*> genExpr,
        AST.ECall <$> genText <*> Gen.list (Range.linear 0 2) genExpr
      ]

genBlock :: Gen Block
genBlock =
  Block
    <$> genSpan
    <*> Gen.maybe genText
    <*> Gen.recursive
      Gen.choice
      [ Paragraph <$> inl,
        Heading <$> Gen.int (Range.linear 1 3) <*> attrs <*> inl,
        CodeBlock <$> Gen.maybe genText <*> genText,
        ChannelOutput <$> Gen.element [TocOutput 2, IndexOutput, BibliographyOutput],
        VerseBlock <$> Gen.list (Range.linear 1 3) (Gen.list (Range.linear 1 3) (Gen.list (Range.linear 1 3) genInline)),
        Table <$> Gen.list (Range.singleton 2) Gen.enumBounded <*> Gen.list (Range.singleton 2) inl <*> Gen.list (Range.linear 0 2) (Gen.list (Range.singleton 2) inl)
      ]
      [ BulletList <$> Gen.list (Range.linear 1 3) (ListItem <$> Gen.maybe (Gen.integral (Range.linear 1 9)) <*> Gen.list (Range.linear 0 2) genBlock),
        OrderedList <$> Gen.list (Range.linear 1 3) (ListItem Nothing <$> Gen.list (Range.linear 0 2) genBlock),
        DefList <$> Gen.list (Range.linear 1 2) (DefGroup <$> Gen.list (Range.linear 1 2) inl <*> Gen.list (Range.linear 1 2) (Gen.list (Range.linear 0 2) genBlock)),
        FigureBlock <$> (Figure <$> genText <*> Gen.maybe genText <*> genText <*> Gen.maybe Gen.enumBounded <*> Gen.maybe genText <*> Gen.list (Range.linear 0 1) genBlock)
      ]
  where
    inl = Gen.list (Range.linear 0 3) genInline
    attrs = HeadingAttrs <$> Gen.maybe inl <*> Gen.maybe (Gen.integral (Range.linear 1 9)) <*> Gen.bool <*> Gen.bool

genDocument :: Gen Document
genDocument = Document (FileId 0) <$> Gen.list (Range.linear 0 5) genBlock
