-- | The tests of docs/adr/0148 but fmt: syntax, types, exhaustiveness, evaluation, tail calls and limits.
module LanguageSpec (languageTests) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Control.Monad (forM, forM_, void)
import Data.Either (isRight)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Gmx
import Golem.Syntax
import Support
import Test.Tasty
import Test.Tasty.HUnit

languageTests :: TestTree
languageTests = testGroup "the .gmx language (docs/adr/0148)" [syntaxTests, typeTests, exhaustiveTests, evalTests, tailTests, limitTests, determinismTests]

cidSystemInfo :: Text
cidSystemInfo =
  T.unlines
    [ "data CidSystemInfo = CidSystemInfo String String Nat;",
      "",
      "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo;",
      "cidSystemInfo registry ordering supplement",
      "  | String.all printable registry && String.all printable ordering = Just (CidSystemInfo registry ordering supplement)",
      "  | otherwise = Nothing",
      "  where {",
      "    printable c = c >= \" \" && c <= \"~\";",
      "  };"
    ]

-- the same declarations, laid out otherwise
cidSystemInfoFlat :: Text
cidSystemInfoFlat =
  T.unlines
    [ "data CidSystemInfo",
      "        = CidSystemInfo String String Nat ;",
      "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo; cidSystemInfo registry ordering supplement | String.all printable registry && String.all printable ordering",
      "= Just (CidSystemInfo registry ordering supplement) | otherwise = Nothing where { printable c = c >= \" \" && c <= \"~\" };"
    ]

labelSrc :: Text
labelSrc =
  T.unlines
    [ "label :: Maybe Nat -> String;",
      "label Nothing = bracket \"なし\";",
      "label (Just n) = bracket (String.fromNat n)",
      "  where {",
      "    bracket s = \"［\" ++ s ++ \"］\";",
      "  };"
    ]

syntaxTests :: TestTree
syntaxTests =
  testGroup
    "syntax"
    [ testCase "cidSystemInfo of the ADR is read and evaluated" $ do
        noDiagnostics cidSystemInfo
        r <- call cidSystemInfo "cidSystemInfo" [str "Adobe", str "Japan1", nat 7] >>= ok
        r @?= RCon "Just" [RCon "CidSystemInfo" [str "Adobe", str "Japan1", nat 7]]
        r' <- call cidSystemInfo "cidSystemInfo" [str "Adobe", str "日本", nat 7] >>= ok
        r' @?= RCon "Nothing" [],
      testCase "the same declarations laid out otherwise have the same AST" $
        parseModule (FileId 0) cidSystemInfoFlat @?= parseModule (FileId 0) cidSystemInfo,
      testCase "the AST is not empty" $
        assertBool "parsed" (isRight (parseModule (FileId 0) cidSystemInfo)),
      testCase "a declaration without ; is G10100" $
        codes "f :: Nat -> Nat\nf x = x;\n" @?= ["G10100"],
      testCase "an unclosed { is G10101" $
        codes "f :: Nat -> Nat;\nf x = case x of {\n  0 -> 1;\n  _ -> 2\n" @?= ["G10101"],
      testCase "an unclosed ( and an unclosed string are G10101" $ do
        codes "f :: Nat -> Nat;\nf x = (x + 1;\n" @?= ["G10101"]
        codes "f :: String;\nf = \"abc;\n" @?= ["G10101"],
      testCase "if is G10102 at the word" $ do
        let src = "f :: Nat -> Nat;\nf x = if x then 1 else 2;\n"
        codes src @?= ["G10102"]
        map (spanStart . diagSpan) (fst (load src)) @?= [T.length (fst (T.breakOn "if" src))],
      testCase "let, for and while are G10102" $
        forM_ ["let", "for", "while"] $ \w ->
          codes ("f :: Nat -> Nat;\nf x = " <> w <> " x;\n") @?= ["G10102"],
      testCase "a where laid out by indentation is G10100" $
        codes "f :: Nat -> Nat;\nf x = g x\n  where\n    g y = y;\n" @?= ["G10100"],
      testCase "label of the ADR: both equations use bracket" $ do
        noDiagnostics labelSrc
        a <- call labelSrc "label" [RCon "Nothing" []] >>= ok
        a @?= str "［なし］"
        b <- call labelSrc "label" [RCon "Just" [nat 3]] >>= ok
        b @?= str "［3］",
      testCase "a where after the first equation is G10103" $
        codes "f :: Bool -> Nat;\nf True = g where { g = 1; };\nf False = 2;\n" @?= ["G10103"],
      testCase "a second where is G10103" $
        codes "f :: Nat -> Nat;\nf x = g where { g = 1; } where { h = 2; };\n" @?= ["G10103"],
      testCase "a where after an alternative of case is G10103" $
        codes "f :: Nat -> Nat;\nf x = case x of { 0 -> g where { g = 1; }; _ -> 2 };\n" @?= ["G10103"],
      testCase "a where in a where is G10103" $
        codes "f :: Nat -> Nat;\nf x = g where { g = h where { h = 1; }; };\n" @?= ["G10103"],
      testCase "a where after a guard that is not the last is G10103" $
        codes "f :: Nat -> Nat;\nf x | x > 1 = g where { g = 1; } | otherwise = 2;\n" @?= ["G10103"],
      testCase "a variable of the patterns of the arguments is not seen in where: G10200" $
        codes "f :: Nat -> Nat;\nf x = g where { g = x + 1; };\n" @?= ["G10200"],
      testCase "a character literal is G10100" $
        codes "f :: String;\nf = 'a';\n" @?= ["G10100"],
      testCase "lazy on a function and on an argument is G10100" $ do
        codes "f :: Nat -> Nat;\nf x = g x where { lazy g y = y; };\n" @?= ["G10100"]
        codes "f :: Nat -> Nat;\nf (lazy x) = x;\n" @?= ["G10100"]
        codes "lazy f :: Nat;\nf = 1;\n" @?= ["G10100"],
      testCase "a BOM is G01002 and a CR is G01003" $ do
        codes "\xFEFF\&f :: Nat;\nf = 1;\n" @?= ["G01002"]
        codes "f :: Nat;\r\nf = 1;\r\n" @?= ["G01003"]
    ]

typeTests :: TestTree
typeTests =
  testGroup
    "types"
    [ testCase "an undefined name is G10200" $
        codes "f :: Nat -> Nat;\nf x = y;\n" @?= ["G10200"],
      testCase "a String where Nat is wanted is G10201" $
        codes "f :: Nat -> Nat;\nf x = x + 1;\ng :: Nat;\ng = f \"a\";\n" @?= ["G10201"],
      testCase "a top-level function without a signature is G10202" $
        codes "f x = x;\n" @?= ["G10202"],
      testCase "a cycle of imports is G10203, of length 1 too" $ do
        let self = [("main.gmx", "import \"main.gmx\" as M;\nf :: Nat;\nf = 1;\n")]
        codesOf (loadMany self) @?= ["G10203"]
        let two = [("main.gmx", "import \"b.gmx\" as B;\nf :: Nat;\nf = 1;\n"), ("b.gmx", "import \"main.gmx\" as M;\ng :: Nat;\ng = 1;\n")]
        codesOf (loadMany two) @?= ["G10203"],
      testCase "a name defined twice is G10204" $ do
        codes "f :: Nat;\nf = 1;\nf :: Nat;\n" @?= ["G10204"]
        codes "data T = A | A;\n" @?= ["G10204"],
      testCase "an import named as a built-in module is G10204" $
        codesOf (loadMany [("main.gmx", "import \"b.gmx\" as String;\nf :: Nat;\nf = 1;\n"), ("b.gmx", "g :: Nat;\ng = 1;\n")]) @?= ["G10204"],
      testCase "a name that is not pub is G10205" $
        codesOf (loadMany [("main.gmx", "import \"b.gmx\" as B;\nf :: Nat;\nf = B.g;\n"), ("b.gmx", "g :: Nat;\ng = 1;\n")]) @?= ["G10205"],
      testCase "a pub name of an import is used" $ do
        let files = [("main.gmx", "import \"lib/b.gmx\" as B;\nf :: Nat;\nf = B.g + 1;\n"), ("lib/b.gmx", "pub g :: Nat;\ng = 1;\n")]
        r <- callAt files "f" [] >>= ok
        r @?= nat 2,
      testCase "an import outside the root is G03003" $
        codesOf (loadMany [("main.gmx", "import \"../b.gmx\" as B;\nf :: Nat;\nf = 1;\n")]) @?= ["G03003"],
      testCase "an equation whose arguments differ from the signature is G10206" $
        codes "f :: Nat -> Nat;\nf x y = x;\n" @?= ["G10206"],
      testCase "Nat widens to Rat" $ do
        let src = "half :: Rat -> Rat;\nhalf x = x / 2;\nf :: Nat -> Rat;\nf n = half n;\n"
        r <- call src "f" [nat 3] >>= ok
        r @?= rat 1.5,
      testCase "Rat does not narrow to Nat: G10201" $
        codes "f :: Rat -> Nat;\nf x = x;\n" @?= ["G10201"],
      testCase "String.chars of 漢字 is two strings of one character" $ do
        r <- call "f :: List String;\nf = String.chars \"漢字\";\n" "f" [] >>= ok
        r @?= RList [str "漢", str "字"]
    ]
  where
    codesOf (ds, _) = [c | DiagnosticCode c <- map diagCode ds]

exhaustiveTests :: TestTree
exhaustiveTests =
  testGroup
    "exhaustiveness"
    [ testCase "equations without Nothing are G10300 and name Nothing" $ do
        let src = "f :: Maybe Nat -> Nat;\nf (Just n) = n;\n"
        codes src @?= ["G10300"]
        assertBool (show (messages src)) (any ("Nothing" `T.isInfixOf`) (messages src)),
      testCase "a case without [] is G10300" $
        codes "f :: List Nat -> Nat;\nf xs = case xs of { [x] -> x; [x, y] -> y };\n" @?= ["G10300"],
      testCase "guards without otherwise are G10302" $ do
        let src = "f :: Nat -> Nat;\nf n\n  | n > 1 = 1\n  | n <= 1 = 0;\n"
        codes src @?= ["G10302"]
        messages src @?= ["ガードの並びの最後が otherwise ではありません: f"],
      testCase "guards without otherwise followed by an equation of variables only are no error" $
        noDiagnostics "f :: Nat -> Nat;\nf n\n  | n > 1 = 1;\nf _ = 0;\n",
      testCase "a last guard of True is G10302" $
        codes "f :: Nat -> Nat;\nf n\n  | n > 1 = 1\n  | True = 0;\n" @?= ["G10302"],
      testCase "a guard after otherwise is G10301" $
        codes "f :: Nat -> Nat;\nf n\n  | otherwise = 1\n  | n > 1 = 0;\n" @?= ["G10301"],
      testCase "a second _ is G10301" $
        codes "f :: Nat -> Nat;\nf _ = 1;\nf _ = 2;\n" @?= ["G10301"],
      testCase "an alternative of case never chosen is G10301" $
        codes "f :: Bool -> Nat;\nf b = case b of { True -> 1; False -> 0; True -> 2 };\n" @?= ["G10301"],
      testCase "the ternary operator always covers" $
        noDiagnostics "f :: Nat -> Nat;\nf n = n > 1 ? 1 : n == 0 ? 2 : 3;\n",
      testCase "literals need a catch-all" $ do
        codes "f :: Nat -> Nat;\nf 0 = 1;\nf 1 = 2;\n" @?= ["G10300"]
        noDiagnostics "f :: Nat -> Nat;\nf 0 = 1;\nf n = n;\n",
      testCase "a record pattern" $ do
        let src = "data Book = Book { title :: String, year :: Nat };\nt :: Book -> String;\nt Book { title = s } = s;\nb :: String;\nb = t (Book \"題\" 2020);\n"
        noDiagnostics src
        r <- call src "b" [] >>= ok
        r @?= str "題"
    ]

evalTests :: TestTree
evalTests =
  testGroup
    "evaluation"
    [ testCase "a strict binding of where divided by 0 is the error of division even unused" $ do
        r <- call "f :: Nat -> Nat;\nf x = x where { y = 1 / 0; };\n" "f" [nat 1]
        either (Just . diagCode) (const Nothing) r @?= Just (DiagnosticCode "G02003"),
      testCase "a lazy binding unused is no error" $ do
        r <- call "f :: Nat -> Nat;\nf x = x where { lazy y = 1 / 0; };\n" "f" [nat 1] >>= ok
        r @?= nat 1,
      testCase "a lazy binding is evaluated when used" $ do
        r <- call "f :: Nat -> Rat;\nf x = x == 0 ? y : 1 where { lazy y = 1 / 0; };\n" "f" [nat 0]
        either (Just . diagCode) (const Nothing) r @?= Just (DiagnosticCode "G02003"),
      testCase "the error of division points into the .gmx" $ do
        let src = "f :: Nat -> Rat;\nf x = 1 / x;\n"
        r <- call src "f" [nat 0]
        case r of
          Left d -> (spanFile (diagSpan d), spanStart (diagSpan d)) @?= (FileId 100, T.length (fst (T.breakOn "1 / x" src)))
          Right v -> assertFailure (show v),
      testCase "&& and || evaluate the right only when needed" $ do
        r <- call "f :: Nat -> Bool;\nf x = x == 0 || 1 / x > 0;\n" "f" [nat 0] >>= ok
        r @?= bool True,
      testCase "List.map, List.foldl and ++" $ do
        let src = "double :: Nat -> Nat;\ndouble n = n * 2;\nadd :: Nat -> Nat -> Nat;\nadd a b = a + b;\nf :: Nat;\nf = List.foldl add 0 (List.map double ([1, 2] ++ [3]));\n"
        r <- call src "f" [] >>= ok
        r @?= nat 12,
      testCase "the arithmetic of the expression context: 1 - 2 is an integer" $ do
        r <- call "f :: Int;\nf = 1 - 2;\n" "f" [] >>= ok
        r @?= int (-1)
    ]

tailTests :: TestTree
tailTests =
  testGroup
    "tail calls"
    [ testCase "a tail recursion of ten million calls ends" $ do
        r <- call "loop :: Int -> Int;\nloop 0 = 0;\nloop n = loop (n - 1);\n" "loop" [nat 10000000]
        void r @?= Right (),
      testCase "a mutual tail recursion ends" $ do
        let src = "even :: Int -> Bool;\neven 0 = True;\neven n = odd (n - 1);\nodd :: Int -> Bool;\nodd 0 = False;\nodd n = even (n - 1);\n"
        r <- call src "even" [nat 100001] >>= ok
        r @?= bool False,
      testCase "a recursion that is not a tail call beyond 10000 is G10401" $ do
        let src = "sum :: Int -> Int;\nsum 0 = 0;\nsum n = n + sum (n - 1);\n"
        ok' <- call src "sum" [nat 9000] >>= ok
        ok' @?= int (9000 * 9001 `div` 2)
        r <- call src "sum" [nat 20000]
        case r of
          Left d -> do
            diagCode d @?= DiagnosticCode "G10401"
            diagSpan d @?= callSpan
            diagMessage d @?= "末尾でない呼び出しの深さが上限（10000）を超えました: sum（main.gmx:1）"
          Right v -> assertFailure (show v)
    ]

-- | Nat to kanji numerals, the work of the sample plugin kansuji.
kansujiSrc :: Text
kansujiSrc =
  T.unlines
    [ "digit :: Nat -> String;",
      "digit 1 = \"一\"; digit 2 = \"二\"; digit 3 = \"三\"; digit 4 = \"四\"; digit 5 = \"五\";",
      "digit 6 = \"六\"; digit 7 = \"七\"; digit 8 = \"八\"; digit 9 = \"九\"; digit _ = \"\";",
      "unit :: Nat -> String -> String;",
      "unit 0 _ = \"\";",
      "unit 1 u = u;",
      "unit d u = digit d ++ u;",
      "small :: Nat -> String;",
      "small n = unit (div n 1000) \"千\" ++ unit (div (n % 1000) 100) \"百\" ++ unit (div (n % 100) 10) \"十\" ++ digit (n % 10);",
      "kansuji :: Nat -> String;",
      "kansuji 0 = \"〇\";",
      "kansuji n = groups n [\"\", \"万\", \"億\", \"兆\", \"京\"] \"\";",
      "groups :: Nat -> List String -> String -> String;",
      "groups 0 _ acc = acc;",
      "groups n units acc = case List.uncons units of {",
      "  Nothing -> acc;",
      "  Just (List.Cons u rest) -> groups (div n 10000) rest ((n % 10000 == 0 ? \"\" : small (n % 10000) ++ u) ++ acc)",
      "};"
    ]

-- | The first occurrence of each word marked, the work of the sample plugin first-ruby on strings.
firstSrc :: Text
firstSrc =
  T.unlines
    [ "firstMarks :: List String -> List String -> List String;",
      "firstMarks words tokens = go words tokens [];",
      "go :: List String -> List String -> List String -> List String;",
      "go seen ts acc = case List.uncons ts of {",
      "  Nothing -> List.reverse acc;",
      "  Just (List.Cons t rest) -> List.any (same t) seen ? go (List.filter (other t) seen) rest (List.cons (\"《\" ++ t ++ \"》\") acc) : go seen rest (List.cons t acc)",
      "};",
      "same :: String -> String -> Bool;",
      "same a b = a == b;",
      "other :: String -> String -> Bool;",
      "other a b = a /= b;"
    ]

-- | The steps of a call of main.gmx.
stepsOf :: Text -> Text -> [Result] -> IO (Either Diagnostic Result, Int)
stepsOf src f args = case load src of
  ([], Just p) -> pure (callFunctionCounted p callSpan "main.gmx" f args)
  (ds, _) -> assertFailure (show ds) >> fail "unreachable"

limitTests :: TestTree
limitTests =
  testGroup
    "the limit of steps"
    [ testCase "the measured work is a third of the limit or less" $ do
        (k, ks) <- stepsOf kansujiSrc "kansuji" [nat 9876543210123456789]
        k @?= Right (str "九百八十七京六千五百四十三兆二千百一億二千三百四十五万六千七百八十九")
        let vocabulary = [str ("語" <> T.pack (show i)) | i <- [1 .. 50 :: Int]]
            tokens = [str ("語" <> T.pack (show (i `mod` 80))) | i <- [1 .. 1000 :: Int]]
        (r, fs) <- stepsOf firstSrc "firstMarks" [RList vocabulary, RList tokens]
        either (assertFailure . show) (const (pure ())) r
        (_, ls) <- stepsOf "loop :: Int -> Int;\nloop 0 = 0;\nloop n = loop (n - 1);\n" "loop" [nat 10000000]
        -- measured: 423, 30290 and 30000002 steps, as the specification of golem-gmx writes
        assertBool (show (ks, fs, ls)) (3 * maximum [ks, fs, ls] <= stepLimit),
      testCase "a tail recursion that never stops is G10400, the same twice" $ do
        let src = "spin :: Nat -> Nat;\nspin n = spin (n + 1);\n"
        a <- call src "spin" [nat 0]
        b <- call src "spin" [nat 0]
        a @?= b
        case a of
          Left d -> do
            diagCode d @?= DiagnosticCode "G10400"
            diagSpan d @?= callSpan
            diagMessage d @?= "関数の評価の手数が上限（" <> T.pack (show stepLimit) <> " 手）を超えました: spin（main.gmx:1）"
          Right v -> assertFailure (show v),
      testCase "doubling a string is G10400 before the memory runs out" $ do
        r <- call "grow :: String -> String;\ngrow s = grow (s ++ s);\n" "grow" [str "ab"]
        either (Just . diagCode) (const Nothing) r @?= Just (DiagnosticCode "G10400")
    ]

determinismTests :: TestTree
determinismTests =
  testCase "evaluating in parallel gives what evaluating in sequence gives" $ do
    let src = "sum :: Int -> Int;\nsum 0 = 0;\nsum n = n + sum (n - 1);\nf :: Nat -> Rat;\nf n = 1 / (n - 3);\n"
        calls = [("sum", [nat n]) | n <- [10, 5000, 20000]] <> [("f", [nat n]) | n <- [1 .. 5]]
    sequential <- mapM (uncurry (call src)) calls
    vars <- forM calls $ \(f, as) -> do
      v <- newEmptyMVar
      _ <- forkIO (call src f as >>= evaluate . forceResult >>= putMVar v)
      pure v
    parallel <- mapM takeMVar vars
    parallel @?= sequential
  where
    forceResult r = length (show r) `seq` r
