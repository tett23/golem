{- | fmt of .gmx (docs/adr/0148): the AST is kept and a second fmt changes
nothing, for sources made from any AST with any white space and comments
between the tokens.
-}
module FmtSpec (fmtTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.Value (Value (..))
import Golem.Gmx
import Golem.Gmx.Syntax
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
    "fmt (docs/adr/0148)"
    [ testCase "the example of the ADR is laid out as the ADR writes it" $
        formatGmx messy @?= Right tidy,
      testCase "guards go to lines of their own, a level down" $
        formatGmx "f :: Nat -> Nat;\nf n | n > 1 = 1 | otherwise = 0;\n"
          @?= Right "f :: Nat -> Nat;\nf n\n  | n > 1 = 1\n  | otherwise = 0;\n",
      testCase "case: a line after { and before }, the alternatives a level down" $
        formatGmx "f :: Nat -> Nat;\nf n = case n of { 0 -> 1;\n_ -> 2 };\n"
          @?= Right "f :: Nat -> Nat;\nf n = case n of {\n  0 -> 1;\n  _ -> 2\n};\n",
      testCase "blank lines between declarations become one, and comments stay" $
        formatGmx "-- top\nf :: Nat;\n\n\n\nf = 1; -- one\n\n\n"
          @?= Right "-- top\nf :: Nat;\n\nf = 1; -- one\n",
      testCase "a BOM and CR are removed" $
        formatGmx "\xFEFF\&f :: Nat;\r\nf = 1;\r\n" @?= Right "f :: Nat;\nf = 1;\n",
      testProperty "fmt keeps the AST and is idempotent" $ property $ do
        m <- forAll genModule
        src <- forAll (render <$> mapM (\t -> (t <>) <$> genSep) (printModule m))
        parseModule (FileId 0) src === Right m
        out <- evalEither (formatGmx src)
        parseModule (FileId 0) out === Right m
        formatGmx out === Right out
    ]
  where
    render = T.concat
    messy =
      T.unlines
        [ "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo;",
          "cidSystemInfo registry ordering supplement | String.all printable registry && String.all printable ordering = Just (CidSystemInfo registry ordering supplement)",
          "        | otherwise = Nothing",
          "where {",
          "printable c = c >= \" \" && c <= \"~\";",
          "   };"
        ]
    tidy =
      T.unlines
        [ "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo;",
          "cidSystemInfo registry ordering supplement",
          "  | String.all printable registry && String.all printable ordering = Just (CidSystemInfo registry ordering supplement)",
          "  | otherwise = Nothing",
          "  where {",
          "    printable c = c >= \" \" && c <= \"~\";",
          "  };"
        ]

-- * Sources from trees

genSep :: Gen Text
genSep = Gen.frequency [(8, pure " "), (3, pure "\n"), (1, pure "\n\n\n  "), (1, pure " -- note {\n"), (1, pure "\n-- line\n"), (1, pure "\t ")]

printModule :: Module -> [Text]
printModule (Module ds) = concatMap printDecl ds

printDecl :: Decl -> [Text]
printDecl = \case
  DImport _ p _ a -> ["import", quote p, "as", a, ";"]
  DSig s -> printSig s <> [";"]
  DEq q -> printEq "=" q <> [";"]
  DData _ pub n vs cs -> ["pub" | pub] <> ["data", n] <> vs <> ["="] <> sepBy "|" (map printCon cs) <> [";"]
  DType _ n vs t -> ["type", n] <> vs <> ["="] <> printType t <> [";"]

sepBy :: Text -> [[Text]] -> [Text]
sepBy s = \case
  [] -> []
  x : xs -> x <> concatMap (s :) xs

printSig :: Signature -> [Text]
printSig s = ["pub" | sigPub s] <> [sigName s, "::"] <> printType (sigType s)

printCon :: ConDecl -> [Text]
printCon = \case
  ConPos _ n ts -> n : concatMap printAType ts
  ConRec _ n fs -> [n, "{"] <> sepBy "," [[f, "::"] <> printType t | (f, t) <- fs] <> ["}"]

printType :: TypeE -> [Text]
printType = \case
  TFun a b -> printBType a <> ["->"] <> printType b
  t -> printBType t

printBType :: TypeE -> [Text]
printBType = \case
  TCon _ c as@(_ : _) -> qnameText c : concatMap printAType as
  t -> printAType t

printAType :: TypeE -> [Text]
printAType = \case
  TCon _ c [] -> [qnameText c]
  TVar _ v -> [v]
  t -> ["("] <> printType t <> [")"]

printEq :: Text -> Equation -> [Text]
printEq eqSym q = [eqName q] <> concatMap printAPat (eqPats q) <> printRhs eqSym (eqRhs q) <> concatMap printWhere (eqWheres q)

printRhs :: Text -> Rhs -> [Text]
printRhs eqSym = \case
  Plain e -> eqSym : printExpr e
  Guarded gs -> concat [["|"] <> cond (guardCond g) <> [eqSym] <> printExpr (guardBody g) <> concatMap printWhere ws | (g, ws) <- gs]
  where
    cond = \case
      GOtherwise _ -> ["otherwise"]
      GExpr e -> printExpr e

printWhere :: Where -> [Text]
printWhere (Where _ bs) = ["where", "{"] <> concat [printBinding b <> [";"] | b <- bs] <> ["}"]

printBinding :: Binding -> [Text]
printBinding = \case
  BSig s -> printSig s
  BLazy _ n _ e ws -> ["lazy", n, "="] <> printExpr e <> concatMap printWhere ws
  BEq q -> printEq "=" q

printPat :: Pat -> [Text]
printPat = \case
  PCon _ c as@(_ : _) -> qnameText c : concatMap printAPat as
  p -> printAPat p

printAPat :: Pat -> [Text]
printAPat = \case
  PVar _ n -> [n]
  PWild _ -> ["_"]
  PNum _ v -> printNum v
  PStr _ s -> [quote s]
  PCon _ c [] -> [qnameText c]
  PList _ ps -> ["["] <> sepBy "," (map printPat ps) <> ["]"]
  PRec _ c fs -> [qnameText c, "{"] <> sepBy "," [[f, "="] <> printPat p | (f, p) <- fs] <> ["}"]
  p -> ["("] <> printPat p <> [")"]

printNum :: Value -> [Text]
printNum = \case
  VNat n -> [T.pack (show n)]
  _ -> ["0"]

printExpr :: Expr -> [Text]
printExpr = \case
  ECase _ e as -> ["case"] <> printExpr e <> ["of", "{"] <> sepBy ";" [printPat (altPat a) <> printRhs "->" (altRhs a) | a <- as] <> ["}"]
  ETernary _ c a b -> printAtom c <> ["?"] <> printAtom a <> [":"] <> printAtom b
  EBin _ o a b -> printAtom a <> [binOpText o] <> printAtom b
  ENeg _ e -> ["-"] <> printAtom e
  EApp f x -> printAtom f <> printAtom x
  e -> printAtom e

printAtom :: Expr -> [Text]
printAtom = \case
  EVar _ q -> [qnameText q]
  ECon _ q -> [qnameText q]
  ENum _ v -> printNum v
  EStr _ s -> [quote s]
  EList _ es -> ["["] <> sepBy "," (map printExpr es) <> ["]"]
  ERecord _ c fs -> [qnameText c, "{"] <> sepBy "," [[f, "="] <> printExpr e | (f, _, e) <- fs] <> ["}"]
  EParen _ e -> ["("] <> printExpr e <> [")"]
  e -> ["("] <> printExpr e <> [")"]

quote :: Text -> Text
quote s = "\"" <> T.concatMap esc s <> "\""
  where
    esc = \case
      '"' -> "\\\""
      '\\' -> "\\\\"
      '\n' -> "\\n"
      '\t' -> "\\t"
      c -> T.singleton c

-- * Trees

l0 :: Loc
l0 = Loc 0 0

genModule :: Gen Module
genModule = Module <$> Gen.list (Range.linear 0 6) genDecl

genDecl :: Gen Decl
genDecl =
  Gen.choice
    [ DImport l0 <$> genStr <*> pure l0 <*> genCon,
      DSig <$> genSig True,
      DEq <$> genEq 2,
      DData l0 <$> Gen.bool <*> genCon <*> Gen.list (Range.linear 0 2) genVar <*> Gen.list (Range.linear 1 3) genConDecl,
      DType l0 <$> genCon <*> Gen.list (Range.linear 0 2) genVar <*> genType
    ]

genSig :: Bool -> Gen Signature
genSig top = Signature l0 <$> (if top then Gen.bool else pure False) <*> genVar <*> pure l0 <*> genType

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
      TFun <$> genType <*> genType
    ]

genTyCon :: Gen QName
genTyCon = Gen.element [QName Nothing "Nat", QName Nothing "List", QName Nothing "Maybe", QName (Just "T") "Shape"]

genVar :: Gen Name
genVar = Gen.element ["f", "x", "go", "acc", "a1", "_y"]

genCon :: Gen Name
genCon = Gen.element ["A", "Just", "Nothing", "Book", "T"]

genQCon :: Gen QName
genQCon = Gen.element [QName Nothing "Just", QName Nothing "A", QName (Just "T") "Circle"]

genStr :: Gen Text
genStr = Gen.text (Range.linear 0 5) (Gen.element ("a漢\"\\\n\t -{}|;" :: String))

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
          BLazy l0 <$> genVar <*> pure l0 <*> genExpr <*> pure [],
          BEq <$> genEq depth
        ]

genPat :: Gen Pat
genPat =
  Gen.recursive
    Gen.choice
    [ PVar l0 <$> genVar,
      pure (PWild l0),
      PNum l0 . VNat <$> Gen.integral (Range.linear 0 100),
      PStr l0 <$> genStr,
      PCon l0 <$> genQCon <*> pure []
    ]
    [ PCon l0 <$> genQCon <*> Gen.list (Range.linear 1 2) genPat,
      PList l0 <$> Gen.list (Range.linear 0 2) genPat,
      PRec l0 <$> genQCon <*> Gen.list (Range.linear 0 2) ((,) <$> genVar <*> genPat)
    ]

genExpr :: Gen Expr
genExpr =
  Gen.recursive
    Gen.choice
    [ EVar l0 <$> Gen.element [QName Nothing "x", QName Nothing "go", QName (Just "List") "map"],
      ECon l0 <$> genQCon,
      ENum l0 . VNat <$> Gen.integral (Range.linear 0 1000),
      EStr l0 <$> genStr
    ]
    [ EList l0 <$> Gen.list (Range.linear 0 3) genExpr,
      EApp <$> genExpr <*> genExpr,
      EBin l0 <$> Gen.enumBounded <*> genExpr <*> genExpr,
      ENeg l0 <$> genExpr,
      ECase l0 <$> genExpr <*> Gen.list (Range.linear 0 3) (Alt l0 <$> genPat <*> genAltRhs <*> pure []),
      ETernary l0 <$> genExpr <*> genExpr <*> genExpr,
      ERecord l0 <$> genQCon <*> Gen.list (Range.linear 0 2) ((,,) <$> genVar <*> pure l0 <*> genExpr)
    ]
  where
    genAltRhs = Gen.choice [Plain <$> genExpr, Guarded <$> Gen.list (Range.linear 1 2) ((,[]) <$> (Guard l0 <$> Gen.choice [pure (GOtherwise l0), GExpr <$> genExpr] <*> genExpr))]
