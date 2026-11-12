{- | fmt of .emet (docs/adr/0160): the AST is kept and a second fmt changes
nothing, for sources made from any AST with any white space, newlines
and comments where the grammar reads them as white space, and any
separators between the items.
-}
module FmtSpec (fmtTests) where

import Data.Bifunctor (first)
import Data.Int (Int64)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet
import Golem.Emet.Syntax
import Golem.Eval.Value (Value (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), FileId (..))
import Hedgehog
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Support (callSpan, load, nat, str)
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
        formatEmet out === Right out,
      i5EvalTests
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

-- Golem ADR 0351 I5: the same cases appear in eval/Eval.lean.
i5EvalTests :: TestTree
i5EvalTests =
  testGroup
    "Golem ADR 0351 I5 evaluation"
    [ testCase "I5 integer binding and Emet function preserve value" $ do
        let source = "id :: Nat -> Nat\nid n = n\nf :: Nat -> Nat\nf x = id (x + 3)\n"
        compareEval source "f" [nat 2] 100 (Right (nat 5)),
      testCase "I5 string binding preserves value" $ do
        let source = "f :: String -> String\nf x = x ++ \"b\"\n"
        compareEval source "f" [str "a"] 100 (Right (str "ab")),
      testCase "I5 the same external input preserves value or failure" $ do
        let source = "f :: <file \"data/a.tsv\"> String\nf = File.read \"data/a.tsv\" ++ \"b\"\n"
        compareEvalWith (fileHandlers (Map.fromList [("data/a.tsv", "a")])) source "f" [] 100 (Right (str "ab"))
        compareEval source "f" [] 100 (Left (DiagnosticCode "E05104")),
      testCase "I5 same budget at boundary preserves value or E04100" $ do
        let source = "f :: Nat -> Nat\nf x = x + 3\n"
        case load source of
          ([], Just program) -> do
            let (_, used) = callFunctionCounted noHandlers program callSpan "main.emet" "f" [nat 2]
            compareEval source "f" [nat 2] used (Right (nat 5))
            compareEval source "f" [nat 2] (used - 1) (Left (DiagnosticCode "E04100"))
          other -> assertFailure (show (fst other)),
      testCase "I5 expression reductions match the Lean budget boundaries" $ do
        let evaluate budget source = first (map diagCode) (evaluateExpression Nothing budget (TE.encodeUtf8 source))
            overLimit = Left [DiagnosticCode "E04100"]
            addition = "(1 + 1) + (1 + 1)"
            append = "\"鰍\" ++ \"𠮷\""
        evaluate 0 "1" @?= Right (nat 1)
        evaluate 2 addition @?= overLimit
        evaluate 3 addition @?= Right (nat 4)
        evaluate 2 append @?= overLimit
        evaluate 3 append @?= Right (str "鰍𠮷"),
      testCase "I5 checker error is preserved before evaluation" $ do
        let source = "f :: String -> String\nf x = x + 3\n"
        formatted <- either (assertFailure . show) pure (formatEmet source)
        let before = map diagCode (fst (load source))
        assertBool "expected a type error" (not (null before))
        before @?= map diagCode (fst (load formatted))
    ]

compareEval :: Text -> Text -> [Result] -> Int64 -> Either DiagnosticCode Result -> IO ()
compareEval = compareEvalWith noHandlers

compareEvalWith :: Handlers -> Text -> Text -> [Result] -> Int64 -> Either DiagnosticCode Result -> IO ()
compareEvalWith handlers source name args budget expected = do
  formatted <- either (assertFailure . show) pure (formatEmet source)
  before <- run source
  formattedResult <- run formatted
  before @?= expected
  formattedResult @?= expected
  where
    run text = case load text of
      ([], Just program) ->
        pure
          $ either (Left . diagCode) Right
          $ callFunctionLimited budget handlers program callSpan "main.emet" name args
      (diagnostics, _) -> assertFailure (show diagnostics) >> fail "unreachable"

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
printSig s = [T "pub" | sigPub s] <> [T (kindWord k) | Just (k, _) <- [sigKind s]] <> [T (quote n) | Just (n, _) <- [sigExport s]] <> [T (sigName s), T "::", Free] <> maybe [] (\r -> printBracketRow r <> [Tight]) (sigRow s) <> printType False (sigType s)

-- | A row in brackets, or a variable alone.
printRow :: RowE -> [Piece]
printRow = \case
  RowE _ [] (Just (v, _)) -> [T v]
  r -> printBracketRow r

printBracketRow :: RowE -> [Piece]
printBracketRow = \case
  RowE _ qs v -> [T "<", Free] <> sepBy [Free, T ",", Free] (map printReq qs) <> maybe [] (\(n, _) -> [Free, T "|", Free, T n]) v <> [Free, T ">"]
  where
    printReq (ReqE _ k as) = T k : concat [[Free, T (quote a)] | a <- as]

printCon :: ConDecl -> [Piece]
printCon = \case
  ConPos _ n ts -> T n : concatMap printAType ts
  ConRec _ n fs -> [T n, T "{", Free] <> sepBy [Free, T ",", Free] [[T f, Free, T "::", Free] <> printType True t | (f, t) <- fs] <> [Free, T "}"]

printType :: Bool -> TypeE -> [Piece]
printType nl = \case
  TFun a r b -> printBType nl a <> [Free, T "->", Free] <> maybe [] (\x -> printRow x <> [gap nl]) r <> printType nl b
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
  -- a keyword argument (docs/adr/0162)
  TNamed _ n t d -> [T "(", Free, T (if argNameQuoted n then quote (argNameText n) else argNameText n), Free, T "::", Free] <> printType True t <> maybe [] (\e -> [Free, T "=", Free] <> printExpr True e) d <> [Free, T ")"]
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
  -- the kind of a function .gm uses, and its name in .gm (docs/adr/0162)
  kind <- if pub then Gen.maybe ((,l0) <$> Gen.enumBounded) else pure Nothing
  export <- if isJust kind then Gen.maybe ((,l0) <$> Gen.element ["tax-included", "a", "x1"]) else pure Nothing
  Signature l0 pub kind export <$> genVar <*> pure l0 <*> Gen.maybe genBracketRow <*> genType

{- | A row in brackets, its requirements in the order fmt puts them (by
their kinds, then their literals), each once.
-}
genBracketRow :: Gen RowE
genBracketRow = do
  qs <- Gen.list (Range.linear 0 3) (ReqE l0 <$> Gen.element ["file", "net"] <*> Gen.list (Range.linear 0 2) (Gen.element ["a.tsv", "data/b.tsv", "c"]))
  v <- Gen.maybe ((,l0) <$> genVar)
  pure (RowE l0 (nubOrdOn key (sortOn key qs)) v)
  where
    key (ReqE _ k as) = (k, map quote as)
    nubOrdOn f = \case
      x : y : rest | f x == f y -> nubOrdOn f (x : rest)
      x : rest -> x : nubOrdOn f rest
      [] -> []

-- | The row of an arrow: none, a row in brackets, or a variable alone.
genRow :: Gen (Maybe RowE)
genRow = Gen.frequency [(3, pure Nothing), (1, Just <$> genBracketRow), (1, (\v -> Just (RowE l0 [] (Just (v, l0)))) <$> genVar)]

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
      TFun <$> genType <*> genRow <*> genType,
      TTuple l0 <$> Gen.list (Range.linear 2 3) genType,
      TNamed l0 <$> Gen.choice [ArgName "tax" l0 <$> Gen.bool, pure (ArgName "font-size" l0 True)] <*> genType <*> Gen.maybe genExpr
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
