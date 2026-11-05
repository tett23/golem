{- | fmt of .emet (docs/adr/0160): the AST is kept and a second fmt changes
nothing, for sources made from any AST with any white space, newlines
and comments where the grammar reads them as white space, and any
separators between the items.
-}
module FmtSpec (fmtTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet
import Golem.Emet.Syntax
import Golem.Eval.Value (Value (..))
import Golem.Syntax (FileId (..))
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

fmtTests :: TestTree
fmtTests =
  testGroup
    "fmt (docs/adr/0160)"
    [ testCase "the example of the ADR is laid out as the ADR writes it" $
        formatEmet messy @?= Right tidy,
      testCase "guards go to lines of their own, a level down" $
        formatEmet "f :: Nat -> Nat\nf n | n > 1 = 1 | otherwise = 0\n"
          @?= Right "f :: Nat -> Nat\nf n\n  | n > 1 = 1\n  | otherwise = 0\n",
      testCase "case: a line after { and before }, the alternatives a level down" $
        formatEmet "f :: Nat -> Nat\nf n = case n of { 0 -> 1\n_ -> 2 }\n"
          @?= Right "f :: Nat -> Nat\nf n = case n of {\n  0 -> 1\n  _ -> 2\n}\n",
      testCase "the newlines of lines that go on stay where the writer put them" $
        formatEmet "f :: Nat ->\n        Nat\nf x =\nx +\n      1\n    * 2\n"
          @?= Right "f :: Nat ->\n  Nat\nf x =\n  x +\n  1\n  * 2\n",
      testCase "blank lines between declarations become one, and comments stay" $
        formatEmet "-- top\nf :: Nat\n\n\n\nf = 1 -- one\n   -- two\n\n\n"
          @?= Right "-- top\nf :: Nat\n\nf = 1 -- one\n-- two\n",
      testCase "a comment in a where stays" $
        formatEmet "f :: Nat\nf = a\n  where { -- the value\na = 1 -- one\n}\n"
          @?= Right "f :: Nat\nf = a\n  where { -- the value\n    a = 1 -- one\n  }\n",
      testCase "a BOM and CR are removed" $
        formatEmet "\xFEFF\&f :: Nat\r\nf = 1\r\n" @?= Right "f :: Nat\nf = 1\n",
      testProperty "fmt keeps the AST and is idempotent" $ property $ do
        m <- forAll genModule
        src <- forAll (renderPieces (printModule m))
        parseModule (FileId 0) src === Right m
        out <- evalEither (formatEmet src)
        parseModule (FileId 0) out === Right m
        formatEmet out === Right out
    ]
  where
    messy =
      T.unlines
        [ "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo",
          "cidSystemInfo registry ordering supplement | String.all printable registry && String.all printable ordering = Just (CidSystemInfo registry ordering supplement)",
          "        | otherwise = Nothing",
          "where {",
          "printable c = c >= ' ' && c <= '~'",
          "   }"
        ]
    tidy =
      T.unlines
        [ "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo",
          "cidSystemInfo registry ordering supplement",
          "  | String.all printable registry && String.all printable ordering = Just (CidSystemInfo registry ordering supplement)",
          "  | otherwise = Nothing",
          "  where {",
          "    printable c = c >= ' ' && c <= '~'",
          "  }"
        ]

-- * Sources from trees

{- | A token, or what may come between two: the separator of items (a
newline at least), white space that may hold newlines, or white space
without them.
-}
data Piece = T !Text | Item | Free | Tight

renderPieces :: [Piece] -> Gen Text
renderPieces = fmap T.concat . go
  where
    go = \case
      [] -> pure []
      T a : rest@(T _ : _) -> (\s r -> a : s : r) <$> genTight <*> go rest
      T a : rest -> (a :) <$> go rest
      gaps -> let (gs, rest) = span isGap gaps in (:) <$> gapText gs <*> go rest
    isGap = \case
      T _ -> False
      _ -> True
    gapText gs
      | any isItem gs = genItem
      | any isFree gs && not (any isTight gs) = genFree
      | otherwise = genTight
    isItem = \case
      Item -> True
      _ -> False
    isFree = \case
      Free -> True
      _ -> False
    isTight = \case
      Tight -> True
      _ -> False

genTight :: Gen Text
genTight = Gen.element [" ", "  ", "\t "]

genFree :: Gen Text
genFree = Gen.frequency [(6, pure " "), (3, pure "\n"), (1, pure "\n\n\n  "), (1, pure " -- note {\n"), (1, pure "\n-- line\n  "), (1, pure "\t ")]

genItem :: Gen Text
genItem = Gen.element ["\n", "\n\n", "\n   ", " -- note }\n", "\n-- line\n\n"]

sepBy :: [Piece] -> [[Piece]] -> [Piece]
sepBy s = \case
  [] -> []
  x : xs -> x <> concatMap (s <>) xs

-- | The gap of a place: newlines inside brackets, none outside.
gap :: Bool -> Piece
gap nl = if nl then Free else Tight

printModule :: Module -> [Piece]
printModule (Module ds) = sepBy [Item] (map printDecl ds)

printDecl :: Decl -> [Piece]
printDecl = \case
  DImport _ p _ -> [T "import", T (quote p)]
  DSig s -> printSig s
  DEq q -> printEq "=" q
  DData _ pub n vs cs -> [T "pub" | pub] <> [T "data", T n] <> map T vs <> [T "=", Free] <> sepBy [Free, T "|"] (map printCon cs)
  DType _ pub n vs t -> [T "pub" | pub] <> [T "type", T n] <> map T vs <> [T "=", Free] <> printType False t

printSig :: Signature -> [Piece]
printSig s = [T "pub" | sigPub s] <> [T (sigName s), T "::", Free] <> printType False (sigType s)

printCon :: ConDecl -> [Piece]
printCon = \case
  ConPos _ n ts -> T n : concatMap printAType ts
  ConRec _ n fs -> [T n, T "{", Free] <> sepBy [Free, T ",", Free] [[T f, Free, T "::", Free] <> printType True t | (f, t) <- fs] <> [Free, T "}"]

printType :: Bool -> TypeE -> [Piece]
printType nl = \case
  TFun a b -> printBType nl a <> [Free, T "->", Free] <> printType nl b
  t -> printBType nl t

printBType :: Bool -> TypeE -> [Piece]
printBType nl = \case
  TCon _ c as@(_ : _) -> T (qnameText c) : concat [gap nl : printAType a | a <- as]
  t -> printAType t

printAType :: TypeE -> [Piece]
printAType = \case
  TCon _ c [] -> [T (qnameText c)]
  TVar _ v -> [T v]
  TTuple _ ts -> [T "(", Free] <> sepBy [Free, T ",", Free] (map (printType True) ts) <> [Free, T ")"]
  t -> [T "(", Free] <> printType True t <> [Free, T ")"]

printEq :: Text -> Equation -> [Piece]
printEq eqSym q = [T (eqName q)] <> concatMap printAPat (eqPats q) <> printRhs eqSym (eqRhs q) <> concatMap printWhere (eqWheres q)

printRhs :: Text -> Rhs -> [Piece]
printRhs eqSym = \case
  Plain e -> lead eqSym <> [T eqSym, Free] <> printExpr False e
  Guarded gs -> concat [[Free, T "|"] <> cond (guardCond g) <> lead eqSym <> [T eqSym, Free] <> printExpr False (guardBody g) <> concatMap printWhere ws | (g, ws) <- gs]
  where
    cond = \case
      GOtherwise _ -> [T "otherwise"]
      GExpr e -> printExpr False e
    -- -> may start a line, = may not
    lead s = [Free | s == "->"]

printWhere :: Where -> [Piece]
printWhere (Where _ bs) = [Free, T "where", T "{", Free] <> sepBy [Item] (map printBinding bs) <> [Free, T "}"]

printBinding :: Binding -> [Piece]
printBinding = \case
  BSig s -> printSig s
  BEq q -> printEq "=" q

printPat :: Bool -> Pat -> [Piece]
printPat nl = \case
  PCon _ c as@(_ : _) -> T (qnameText c) : concat [gap nl : printAPat a | a <- as]
  PCons _ h t -> printPat0 nl h <> [Free, T ":", Free] <> printPat nl t
  p -> printAPat p
  where
    printPat0 n = \case
      p@PCons {} -> printParen p
      p -> printPat n p

printAPat :: Pat -> [Piece]
printAPat = \case
  PVar _ n -> [T n]
  PWild _ -> [T "_"]
  PNum _ v -> printNum v
  PStr _ s -> [T (quote s)]
  PChar _ c -> [T (quoteChar c)]
  PCon _ c [] -> [T (qnameText c)]
  PList _ ps -> [T "[", Free] <> sepBy [Free, T ",", Free] (map (printPat True) ps) <> [Free, T "]"]
  PTuple _ ps -> [T "(", Free] <> sepBy [Free, T ",", Free] (map (printPat True) ps) <> [Free, T ")"]
  PRec _ c fs -> [T (qnameText c), T "{", Free] <> sepBy [Free, T ",", Free] [[T f, Free, T "=", Free] <> printPat True p | (f, p) <- fs] <> [Free, T "}"]
  p -> printParen p

printParen :: Pat -> [Piece]
printParen p = [T "(", Free] <> printPat True p <> [Free, T ")"]

printNum :: Value -> [Piece]
printNum = \case
  VNat n -> [T (T.pack (show n))]
  VInt n | n < 0 -> [T ("-" <> T.pack (show (negate n)))]
  _ -> [T "0"]

printExpr :: Bool -> Expr -> [Piece]
printExpr nl = \case
  ECase _ e as -> [T "case"] <> printExpr nl e <> [T "of", T "{", Free] <> sepBy [Item] [printPat False (altPat a) <> printRhs "->" (altRhs a) | a <- as] <> [Free, T "}"]
  ETernary _ c a b -> printAtom c <> [Free, T "?", Free] <> printAtom a <> [Free, T ":", Free] <> printAtom b
  EBin _ o a b -> printAtom a <> [if o == OpSub then gap nl else Free, T (binOpText o), Free] <> printAtom b
  ENeg _ e -> [T "-"] <> printAtom e
  EApp f x -> printAtom f <> [gap nl] <> printAtom x
  e -> printAtom e

printAtom :: Expr -> [Piece]
printAtom = \case
  EVar _ q -> [T (qnameText q)]
  ECon _ q -> [T (qnameText q)]
  ENum _ v -> printNum v
  EStr _ s -> [T (quote s)]
  EChar _ c -> [T (quoteChar c)]
  EList _ es -> [T "[", Free] <> sepBy [Free, T ",", Free] (map (printExpr True) es) <> [Free, T "]"]
  ETuple _ es -> [T "(", Free] <> sepBy [Free, T ",", Free] (map (printExpr True) es) <> [Free, T ")"]
  ERecord _ c fs -> [T (qnameText c), T "{", Free] <> sepBy [Free, T ",", Free] [[T f, Free, T "=", Free] <> printExpr True e | (f, _, e) <- fs] <> [Free, T "}"]
  EParen _ e -> [T "(", Free] <> printExpr True e <> [Free, T ")"]
  e -> [T "(", Free] <> printExpr True e <> [Free, T ")"]

quote :: Text -> Text
quote s = "\"" <> T.concatMap esc s <> "\""
  where
    esc = \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\t' -> "\\t"
      c -> T.singleton c

quoteChar :: Char -> Text
quoteChar = \case
  '\'' -> "'\\''"
  '\\' -> "'\\\\'"
  '\n' -> "'\\n'"
  c -> "'" <> T.singleton c <> "'"

-- * Trees

l0 :: Loc
l0 = Loc 0 0

genModule :: Gen Module
genModule = Module <$> Gen.list (Range.linear 0 6) genDecl

genDecl :: Gen Decl
genDecl =
  Gen.choice
    [ DImport l0 <$> genStr <*> pure l0,
      DSig <$> genSig True,
      DEq <$> genEq 2,
      DData l0 <$> Gen.bool <*> genCon <*> Gen.list (Range.linear 0 2) genVar <*> Gen.list (Range.linear 1 3) genConDecl,
      DType l0 <$> Gen.bool <*> genCon <*> Gen.list (Range.linear 0 2) genVar <*> genType
    ]

genSig :: Bool -> Gen Signature
genSig top = do
  pub <- if top then Gen.bool else pure False
  Signature l0 pub <$> genVar <*> pure l0 <*> genType

genConDecl :: Gen ConDecl
genConDecl =
  Gen.choice
    [ ConPos l0 <$> genCon <*> Gen.list (Range.linear 0 2) genType,
      ConRec l0 <$> genCon <*> Gen.list (Range.linear 1 2) ((,) <$> genVar <*> genType)
    ]

genType :: Gen TypeE
genType =
  Gen.recursive
    Gen.choice
    [TCon l0 <$> genTyCon <*> pure [], TVar l0 <$> genVar]
    [ TCon l0 <$> genTyCon <*> Gen.list (Range.linear 1 2) genType,
      TFun <$> genType <*> genType,
      TTuple l0 <$> Gen.list (Range.linear 2 3) genType
    ]

genTyCon :: Gen QName
genTyCon = Gen.element [QName Nothing "Nat", QName Nothing "List", QName Nothing "Maybe", QName (Just "Inline") "Inline"]

genVar :: Gen Name
genVar = Gen.element ["f", "x", "go", "acc", "a1", "_y"]

genCon :: Gen Name
genCon = Gen.element ["A", "Just", "Nothing", "Book", "T"]

genQCon :: Gen QName
genQCon = Gen.element [QName Nothing "Just", QName Nothing "A", QName (Just "Inline") "Text"]

genStr :: Gen Text
genStr = Gen.text (Range.linear 0 5) (Gen.element ("a漢\"'\\\n\t -{}|;" :: String))

genChar :: Gen Char
genChar = Gen.element ("a漢\"'\\\n -{}|;" :: String)

genEq :: Int -> Gen Equation
genEq depth = do
  name <- genVar
  pats <- Gen.list (Range.linear 0 2) genPat
  rhs <- genRhs depth
  -- a where after guards belongs to the last guard
  ws <- case rhs of
    Plain _ | depth > 0 -> Gen.list (Range.linear 0 1) (genWhere (depth - 1))
    _ -> pure []
  pure (Equation l0 name l0 pats rhs ws)

genRhs :: Int -> Gen Rhs
genRhs depth =
  Gen.choice
    [ Plain <$> genExpr,
      Guarded <$> Gen.list (Range.linear 1 3) ((,) <$> genGuard <*> (if depth > 0 then Gen.list (Range.linear 0 1) (genWhere (depth - 1)) else pure []))
    ]
  where
    genGuard = Guard l0 <$> Gen.choice [pure (GOtherwise l0), GExpr <$> genExpr] <*> genExpr

genWhere :: Int -> Gen Where
genWhere depth = Where l0 <$> Gen.list (Range.linear 0 3) genBinding
  where
    genBinding =
      Gen.choice
        [ BSig <$> genSig False,
          BEq <$> genEq depth
        ]

genPat :: Gen Pat
genPat =
  Gen.recursive
    Gen.choice
    [ PVar l0 <$> genVar,
      pure (PWild l0),
      PNum l0 . VNat <$> Gen.integral (Range.linear 0 100),
      PNum l0 . VInt . negate <$> Gen.integral (Range.linear 1 100),
      PStr l0 <$> genStr,
      PChar l0 <$> genChar,
      PCon l0 <$> genQCon <*> pure []
    ]
    [ PCon l0 <$> genQCon <*> Gen.list (Range.linear 1 2) genPat,
      PList l0 <$> Gen.list (Range.linear 0 2) genPat,
      PCons l0 <$> genPat <*> genPat,
      PTuple l0 <$> Gen.list (Range.linear 2 3) genPat,
      PRec l0 <$> genQCon <*> Gen.list (Range.linear 0 2) ((,) <$> genVar <*> genPat)
    ]

genExpr :: Gen Expr
genExpr =
  Gen.recursive
    Gen.choice
    [ EVar l0 <$> Gen.element [QName Nothing "x", QName Nothing "go", QName (Just "List") "map"],
      ECon l0 <$> genQCon,
      ENum l0 . VNat <$> Gen.integral (Range.linear 0 1000),
      EStr l0 <$> genStr,
      EChar l0 <$> genChar
    ]
    [ EList l0 <$> Gen.list (Range.linear 0 3) genExpr,
      ETuple l0 <$> Gen.list (Range.linear 2 3) genExpr,
      EApp <$> genExpr <*> genExpr,
      EBin l0 <$> Gen.enumBounded <*> genExpr <*> genExpr,
      ENeg l0 <$> genExpr,
      ECase l0 <$> genExpr <*> Gen.list (Range.linear 0 3) (Alt l0 <$> genPat <*> genAltRhs <*> pure []),
      ETernary l0 <$> genExpr <*> genExpr <*> genExpr,
      ERecord l0 <$> genQCon <*> Gen.list (Range.linear 0 2) ((,,) <$> genVar <*> pure l0 <*> genExpr)
    ]
  where
    genAltRhs = Gen.choice [Plain <$> genExpr, Guarded <$> Gen.list (Range.linear 1 2) ((,[]) <$> (Guard l0 <$> Gen.choice [pure (GOtherwise l0), GExpr <$> genExpr] <*> genExpr))]
