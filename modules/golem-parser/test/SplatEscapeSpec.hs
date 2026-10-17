{- | The lowering of splat arguments and of malformed expressions
(golem-parser ADR 0005, ADR 0009), and escapes inside lists (ADR 0010).
-}
module SplatEscapeSpec (tests) where

import Data.Text (Text)
import Golem.Parser
import Golem.Parser.AST
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

fid :: FileId
fid = FileId 0

blocks :: Text -> [Block]
blocks src = let (File _ bs, _, _) = parseAst fid src in map locValue bs

-- | The code, start and end of each syntax diagnostic.
syntaxDiags :: Text -> [(Text, Int, Int)]
syntaxDiags src =
  let (_, _, ds) = parseAst fid src
   in [(c, spanStart (diagSpan d), spanEnd (diagSpan d)) | d <- ds, let DiagnosticCode c = diagCode d]

-- | The arguments of the only command of a one-paragraph file.
argsOf :: Text -> [Argument]
argsOf src = case blocks src of
  [Paragraph [Located _ (Command _ args _)]] -> map locValue args
  other -> error (show other)

-- | An expression without its positions, one level deep.
bare :: Located Expr -> Expr
bare = locValue

-- | The position of an expression.
at :: Located Expr -> (Int, Int)
at (Located sp _) = (spanStart sp, spanEnd sp)

-- | The expression of the only inline of a one-paragraph file.
exprIn :: Text -> Located Expr
exprIn src = case blocks src of
  [Paragraph [Located _ (Expr e)]] -> e
  other -> error (show other)

tests :: TestTree
tests =
  testGroup
    "splats, malformed expressions and escapes in lists"
    [ splats,
      malformed,
      escapesInLists
    ]

splats :: TestTree
splats =
  testGroup
    "splat arguments (ADR 0005)"
    [ testCase "**[h] is a keyword splat" $
        [bare e | SplatKeyword e <- argsOf "[f **[h]]\n"] @?= [EVar ["h"]],
      testCase "*[xs] is a positional splat" $
        [bare e | SplatPositional e <- argsOf "[f *[xs]]\n"] @?= [EVar ["xs"]],
      testCase "splats keep their places among the other arguments" $
        map kind (argsOf "[f a *[xs] **[h] k=v]\n") @?= ["positional", "splat", "keyword splat", "keyword"],
      -- golem-parser ADR 0013
      testCase "**[h] may follow a keyword argument" $
        map kind (argsOf "[f k=v **[h]]\n") @?= ["keyword", "keyword splat"],
      testCase "keyword arguments and **[...] mix in any order" $
        map kind (argsOf "[f k=1 **[h] j=2 **[i]]\n") @?= ["keyword", "keyword splat", "keyword", "keyword splat"],
      testCase "the expression of a keyword splat is at its source" $
        -- "[f **[h]]": h is byte 6
        [at e | SplatKeyword e <- argsOf "[f **[h]]\n"] @?= [(6, 7)],
      testCase "a keyword splat holds a whole expression" $
        [bare e | SplatKeyword e <- argsOf "[f **[{a: 1}]]\n"] @?= [EHash [("a", Located (mkSpan fid 10 11) (EInt 1))]]
    ]
  where
    kind :: Argument -> String
    kind = \case
      Positional _ -> "positional"
      Keyword _ _ -> "keyword"
      SplatPositional _ -> "splat"
      SplatKeyword _ -> "keyword splat"

malformed :: TestTree
malformed =
  testGroup
    "malformed expressions (ADR 0009)"
    [ testCase "[=] is an EError at the G0120" $ do
        let e = exprIn "[=]\n"
        (bare e, at e) @?= (EError, (2, 2))
        syntaxDiags "[=]\n" @?= [("G0120", 2, 2)],
      testCase "an empty keyword splat is an EError where its expression was wanted" $ do
        [(bare e, at e) | SplatKeyword e <- argsOf "[f **[]]\n"] @?= [(EError, (6, 6))]
        syntaxDiags "[f **[]]\n" @?= [("G0120", 6, 6)],
      testCase "an empty positional splat is an EError where its expression was wanted" $ do
        [(bare e, at e) | SplatPositional e <- argsOf "[f *[]]\n"] @?= [(EError, (5, 5))]
        syntaxDiags "[f *[]]\n" @?= [("G0120", 5, 5)],
      testCase "@set without an expression is a SetVar of an EError at the G0120" $ do
        [(locValue n, bare e, at e) | SetVar n e <- blocks "@set x = +\n"] @?= [("x", EError, (9, 10))]
        syntaxDiags "@set x = +\n" @?= [("G0120", 9, 10)],
      testCase "a hash entry without a value is an EError" $ do
        bare (exprIn "[= {a:}]\n") @?= EError
        map (\(c, _, _) -> c) (syntaxDiags "[= {a:}]\n") @?= ["G0120"],
      testCase "an expression followed by a stray token keeps the expression and is a G0117" $ do
        bare (exprIn "[= 1 ? 2]\n") @?= EInt 1
        syntaxDiags "[= 1 ? 2]\n" @?= [("G0117", 5, 9)]
    ]

escapesInLists :: TestTree
escapesInLists =
  testGroup
    "escapes inside lists (ADR 0010)"
    [ testCase "an escape in a bullet item is Escaped" $
        [map locValue is | BulletList [[Located _ (Paragraph is)]] <- blocks "- a\\[b\n"] @?= [[Text "a", Escaped '[', Text "b"]],
      testCase "an escape in a numbered item is Escaped" $
        [map locValue is | OrderedList [[Located _ (Paragraph is)]] <- blocks "+ a\\[b\n"] @?= [[Text "a", Escaped '[', Text "b"]],
      testCase "plainEscapesIn makes the escapes of a numbered item text" $
        [map locValue is | OrderedList [[Located _ (Paragraph is)]] <- plainBlocks "+ a\\[b\n"] @?= [[Text "a[b"]],
      testCase "plainEscapesIn makes the escapes of a bullet item text" $
        [map locValue is | BulletList [[Located _ (Paragraph is)]] <- plainBlocks "- a\\[b\n"] @?= [[Text "a[b"]],
      testCase "plainEscapesIn makes the escapes of a definition term text" $
        [map (map locValue) ts | DefList [DefGroup ts _] <- plainBlocks "= a\\/b\n  d\n"] @?= [[[Text "a/b"]]],
      testCase "plainEscapesIn makes the escapes of a definition text" $
        [[map locValue is | Located _ (Paragraph is) <- d] | DefList [DefGroup _ [d]] <- plainBlocks "= t\n  c\\%d\n"] @?= [[[Text "c%d"]]],
      testCase "plainEscapesIn reaches an item nested in an item" $
        [ map locValue is
        | BulletList [[_, Located _ (BulletList [[Located _ (Paragraph is)]])]] <- plainBlocks "- a\n  - b\\#c\n"
        ]
          @?= [[Text "b#c"]],
      testCase "plainEscapesIn leaves the characters that do not match" $
        [map locValue is | OrderedList [[Located _ (Paragraph is)]] <- plainBlocksWith (== '#') "+ a\\[b\n"] @?= [[Text "a", Escaped '[', Text "b"]],
      testCase "plainEscapesIn reaches a table cell" $
        [map (map locValue) h | Table _ h _ <- plainBlocks "| a\\|b | c |\n|---|---|\n"] @?= [[[Text "a|b"], [Text "c"]]]
    ]
  where
    plainBlocks = plainBlocksWith (const True)
    plainBlocksWith p src =
      let (f, _, _) = parseAst fid src
          File _ bs = plainEscapesIn p f
       in map locValue bs
