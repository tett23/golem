-- | The tests of docs/adr/0160 but fmt: syntax, types, exhaustiveness, evaluation, imports, tail calls and limits.
module LanguageSpec (languageTests) where

import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (evaluate)
import Control.Monad (forM, forM_, void)
import Data.Either (isRight)
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet
import Golem.Emet.Gm (filterFuel)
import Golem.Emet.Prim (PrimStop (..), PrimValue (..), primList, runPrim)
import Golem.Emet.Syntax
import Golem.Eval.Value (Value (..))
import Golem.Syntax
import Hedgehog (Gen, annotate, forAll, property, success, withTests, (===))
import Hedgehog qualified
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Support
import System.Mem (getAllocationCounter, setAllocationCounter)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

languageTests :: TestTree
languageTests =
  testGroup
    "the .emet language (docs/adr/0160)"
    [ separatorTests,
      whereTests,
      consTests,
      typeTests,
      exhaustiveTests,
      evalTests,
      importTests,
      tailTests,
      limitTests,
      determinismTests
    ]

cidSystemInfo :: Text
cidSystemInfo =
  T.unlines
    [ "data CidSystemInfo = CidSystemInfo String String Nat",
      "",
      "cidSystemInfo :: String -> String -> Nat -> Maybe CidSystemInfo",
      "cidSystemInfo registry ordering supplement",
      "  | String.all printable registry && String.all printable ordering = Just (CidSystemInfo registry ordering supplement)",
      "  | otherwise = Nothing",
      "  where {",
      "    printable c = c >= ' ' && c <= '~'",
      "  }"
    ]

-- the same declarations, indented otherwise
cidSystemInfoFlat :: Text
cidSystemInfoFlat =
  T.unlines
    [ "    data CidSystemInfo =",
      "CidSystemInfo String String Nat",
      "cidSystemInfo ::",
      "      String -> String -> Nat -> Maybe CidSystemInfo",
      "        cidSystemInfo registry ordering supplement | String.all printable registry &&",
      "String.all printable ordering = Just (CidSystemInfo registry",
      "ordering supplement)",
      "| otherwise = Nothing where {",
      "printable c = c >= ' ' && c <= '~' }"
    ]

labelSrc :: Text
labelSrc =
  T.unlines
    [ "label :: Maybe Nat -> String",
      "label Nothing = bracket \"なし\"",
      "label (Just n) = bracket (String.fromNat n)",
      "  where {",
      "    bracket s = \"［\" ++ s ++ \"］\"",
      "  }"
    ]

parsed :: Text -> Either [Diagnostic] Module
parsed = parseModule (FileId 0)

separatorTests :: TestTree
separatorTests =
  testGroup
    "newlines as separators"
    [ testCase "cidSystemInfo of the ADR is read and evaluated" $ do
        noDiagnostics cidSystemInfo
        r <- call cidSystemInfo "cidSystemInfo" [str "Adobe", str "Japan1", nat 7] >>= ok
        r @?= RCon "Just" [RCon "CidSystemInfo" [str "Adobe", str "Japan1", nat 7]]
        r' <- call cidSystemInfo "cidSystemInfo" [str "Adobe", str "日本", nat 7] >>= ok
        r' @?= RCon "Nothing" [],
      testCase "label of the ADR: both equations use bracket" $ do
        noDiagnostics labelSrc
        a <- call labelSrc "label" [RCon "Nothing" []] >>= ok
        a @?= str "［なし］"
        b <- call labelSrc "label" [RCon "Just" [nat 3]] >>= ok
        b @?= str "［3］",
      testCase "the same declarations indented otherwise have the same AST" $ do
        assertBool "parsed" (isRight (parsed cidSystemInfo))
        parsed cidSystemInfoFlat @?= parsed cidSystemInfo,
      testCase "a newline in ( ), [ ] and a record { } is no separator" $ do
        a <- bodyOf "g (1,\n2) [3,\n4]"
        b <- bodyOf "g (1, 2) [3, 4]"
        a @?= b
        c <- bodyOf "B {\n  title = \"t\"\n  , year = 1\n}"
        d <- bodyOf "B { title = \"t\", year = 1 }"
        c @?= d,
      testCase "a newline after a binary operator, =, ->, ::, ',', ? and : is no separator" $ do
        noDiagnostics "f ::\n  Nat ->\n  Nat\nf x =\n  x +\n  1 *\n  2\n"
        noDiagnostics "f :: Bool -> List Nat\nf b = b ?\n  [] :\n  1 :\n  []\n"
        noDiagnostics "f :: Nat -> Nat\nf x = case x of {\n  0 ->\n    1\n  _ -> 2\n}\n",
      testCase "a line that starts with |, an operator, ?, :, where or -> continues the line before" $ do
        noDiagnostics "f :: Nat -> Nat\nf x\n  | x > 1 =\n  x\n  + 1\n  * 2\n  | otherwise = 0\n"
        noDiagnostics "f :: Bool -> List Nat\nf b = b\n  ? []\n  : 1\n  : []\n"
        noDiagnostics "f :: Nat -> Nat\nf x = g x\n  where {\n    g y = y\n  }\n"
        noDiagnostics "f :: Nat -> Nat\nf x = case x of {\n  0\n    -> 1\n  _ -> 2\n}\n"
        a <- bodyOf "1\n  + 2\n  == 3\n  && True\n  || False"
        b <- bodyOf "1 + 2 == 3 && True || False"
        a @?= b,
      testCase "a line that starts with - is a new alternative with a negative pattern" $ do
        let src = "f :: Int -> Nat\nf x = case x of {\n  -1 -> 1\n  -2 -> 2\n  _ -> 0\n}\n"
        noDiagnostics src
        r <- call src "f" [int (-2)] >>= ok
        r @?= nat 2,
      testCase "a - at the end of a line continues the subtraction" $ do
        r <- call "f :: Int\nf = 5 -\n  3\n" "f" [] >>= ok
        r @?= int 2,
      testCase "two bindings on one line are E01100" $
        codes "f :: Nat\nf = a\n  where {\n    a = 1 b = 2\n  }\n" @?= ["E01100"],
      testCase "a ; is E01100" $ do
        codes "f :: Nat;\nf = 1\n" @?= ["E01100"]
        codes "f :: Nat\nf = a\n  where { a = 1; b = 2 }\n" @?= ["E01100"],
      testCase "an unclosed { is E01101" $
        codes "f :: Nat -> Nat\nf x = case x of {\n  0 -> 1\n  _ -> 2\n" @?= ["E01101"],
      testCase "an unclosed ( and an unclosed string are E01101" $ do
        codes "f :: Nat -> Nat\nf x = (x + 1\n" @?= ["E01101"]
        codes "f :: String\nf = \"abc\n" @?= ["E01101"],
      testCase "if is E01102 at the word" $ do
        let src = "f :: Nat -> Nat\nf x = if x then 1 else 2\n"
        codes src @?= ["E01102"]
        map (spanStart . diagSpan) (fst (load src)) @?= [T.length (fst (T.breakOn "if" src))],
      testCase "class, let, for, while, lazy, instance, deriving and default are E01102" $ do
        codes "class Show a\n" @?= ["E01102"]
        codes "data T = A deriving Eq\n" @?= ["E01102"]
        forM_ ["let", "for", "while", "lazy", "instance", "default", "then", "else", "in"] $ \w ->
          (w, codes ("f :: Nat -> Nat\nf x = " <> w <> " x\n")) @?= (w, ["E01102"]),
      testCase "a \\u{...} that is no scalar value is E01100" $ do
        codes "f :: String\nf = \"\\u{D800}\"\n" @?= ["E01100"]
        codes "f :: Char\nf = '\\u{110000}'\n" @?= ["E01100"],
      testCase "the escapes of strings and characters" $ do
        r <- call "f :: String\nf = \"\\\"\\'\\\\\\n\\t\\u{6F22}\"\n" "f" [] >>= ok
        r @?= str "\"'\\\n\t漢"
        c <- call "f :: Char\nf = '\\''\n" "f" [] >>= ok
        c @?= chr '\''
        codes "f :: String\nf = \"\\q\"\n" @?= ["E01100"],
      testCase "a BOM is G01002 and a CR is G01003" $ do
        codes "\xFEFF\&f :: Nat\nf = 1\n" @?= ["G01002"]
        codes "f :: Nat\r\nf = 1\r\n" @?= ["G01003"]
    ]

whereTests :: TestTree
whereTests =
  testGroup
    "where"
    [ testCase "a where after the first equation is E01103" $
        codes "f :: Bool -> Nat\nf True = g\n  where {\n    g = 1\n  }\nf False = 2\n" @?= ["E01103"],
      testCase "a second where is E01103" $
        codes "f :: Nat -> Nat\nf x = g\n  where {\n    g = 1\n  }\n  where {\n    h = 2\n  }\n" @?= ["E01103"],
      testCase "a where after an alternative of case is E01103" $
        codes "f :: Nat -> Nat\nf x = case x of {\n  0 -> g\n    where {\n      g = 1\n    }\n  _ -> 2\n}\n" @?= ["E01103"],
      testCase "a where in a where is E01103" $
        codes "f :: Nat -> Nat\nf x = g\n  where {\n    g = h\n      where {\n        h = 1\n      }\n  }\n" @?= ["E01103"],
      testCase "a where after a guard that is not the last is E01103" $
        codes "f :: Nat -> Nat\nf x\n  | x > 1 = g\n  where {\n    g = 1\n  }\n  | otherwise = 2\n" @?= ["E01103"],
      testCase "a variable of the patterns of the arguments is not seen in where: E02100" $
        codes "f :: Nat -> Nat\nf x = g\n  where {\n    g = x + 1\n  }\n" @?= ["E02100"],
      testCase "an equation with more arguments than the signature's arrows is E02106" $
        codes "f :: Nat -> Nat\nf x y = x\n" @?= ["E02106"],
      testCase "equations with different numbers of arguments are E02106" $
        codes "f :: Nat -> Nat -> Nat\nf 0 y = y\nf x = g\n  where {\n    g y = y\n  }\n" @?= ["E02106"],
      testCase "fewer arguments than arrows return a function" $ do
        let src = "add :: Nat -> Nat -> Nat\nadd x = plus\n  where {\n    plus y = y + 1\n  }\nf :: Nat\nf = add 1 2\n"
        r <- call src "f" [] >>= ok
        r @?= nat 3,
      testCase "equations with another declaration between them are E02107" $
        codes "f :: Nat -> Nat\nf 0 = 1\ng :: Nat\ng = 1\nf _ = 2\n" @?= ["E02107"],
      testCase "a binding with a signature" $ do
        r <- call "f :: Nat\nf = g 2\n  where {\n    g :: Nat -> Nat\n    g x = x * 3\n  }\n" "f" [] >>= ok
        r @?= nat 6
    ]

consTests :: TestTree
consTests =
  testGroup
    ": and the ternary operator"
    [ testCase "total of [1, 2, 3] is 6" $ do
        let src = "total :: List Nat -> Nat\ntotal [] = 0\ntotal (x : xs) = x + total xs\n"
        noDiagnostics src
        r <- call src "total" [RList [nat 1, nat 2, nat 3]] >>= ok
        r @?= nat 6,
      testCase ": is right-associative and makes a list" $ do
        r <- call "f :: List Nat\nf = 1 : 2 : [3] ++ [4]\n" "f" [] >>= ok
        r @?= RList [nat 1, nat 2, nat 3, nat 4],
      testCase "c ? (x : xs) : ys is a list in the true branch" $ do
        a <- bodyOf "c ? (x : xs) : ys"
        a @?= ETernary l0 (v "c") (EBin l0 OpCons (v "x") (v "xs")) (v "ys"),
      testCase "c ? [] : x : xs reads x : xs as the false branch" $ do
        a <- bodyOf "c ? [] : x : xs"
        a @?= ETernary l0 (v "c") (EList l0 []) (EBin l0 OpCons (v "x") (v "xs")),
      testCase "a ? b : c ? d : e is a ? b : (c ? d : e)" $ do
        a <- bodyOf "a ? b : c ? d : e"
        a @?= ETernary l0 (v "a") (v "b") (ETernary l0 (v "c") (v "d") (v "e")),
      -- docs/adr/0160 lists this as E01100, but by its rules of reading the
      -- false branch is any expression, x : (xs : ys) included
      testCase "c ? x : xs : ys is c ? x : (xs : ys)" $ do
        a <- bodyOf "c ? x : xs : ys"
        a @?= ETernary l0 (v "c") (v "x") (EBin l0 OpCons (v "xs") (v "ys")),
      testCase "a ? at the top of the true branch is E01100" $
        codes "f :: Bool -> Nat\nf c = c ? c ? 1 : 2 : 3\n" @?= ["E01100"],
      testCase "the ternary operator binds weaker than ||" $ do
        a <- bodyOf "a || b ? c : d"
        a @?= ETernary l0 (EBin l0 OpOr (v "a") (v "b")) (v "c") (v "d"),
      testCase "a tuple in types, expressions and patterns" $ do
        let src = "swap :: (Nat, String) -> (String, Nat)\nswap (n, s) = (s, n)\n"
        noDiagnostics src
        r <- call src "swap" [RTuple [nat 1, str "a"]] >>= ok
        r @?= RTuple [str "a", nat 1]
    ]
  where
    v = EVar l0 . QName Nothing

l0 :: Loc
l0 = Loc 0 0

typeTests :: TestTree
typeTests =
  testGroup
    "types"
    [ testCase "an undefined name is E02100" $
        codes "f :: Nat -> Nat\nf x = y\n" @?= ["E02100"],
      testCase "a String where Nat is wanted is E02101" $
        codes "f :: Nat -> Nat\nf x = x + 1\ng :: Nat\ng = f \"a\"\n" @?= ["E02101"],
      testCase "a top-level function without a signature is E02102" $
        codes "f x = x\n" @?= ["E02102"],
      testCase "a cycle of imports is E02103, of length 1 too" $ do
        codesOf (loadMany [("main.emet", "import \"main.emet\"\nf :: Nat\nf = 1\n")]) @?= ["E02103"]
        let two = [("main.emet", "import \"b.emet\"\nf :: Nat\nf = 1\n"), ("b.emet", "import \"main.emet\"\ng :: Nat\ng = 1\n")]
        codesOf (loadMany two) @?= ["E02103"],
      testCase "a name defined twice is E02104" $ do
        codes "f :: Nat\nf = 1\nf :: Nat\n" @?= ["E02104"]
        codes "data T = A | A\n" @?= ["E02104"]
        codes "data T = A\ndata T = B\n" @?= ["E02104"]
        codes "data B = B { a :: Nat, a :: Nat }\n" @?= ["E02104"]
        codes "f :: (Nat, Nat) -> Nat\nf (x, x) = x\n" @?= ["E02104"],
      testCase "a type or a constructor named as a built-in module is E02104" $ do
        codes "data String = A\n" @?= ["E02104"]
        codes "data T = List\n" @?= ["E02104"],
      testCase "a name that is not pub is E02105" $
        codesOf (loadMany [("main.emet", "import \"b.emet\"\nf :: Nat\nf = g\n"), ("b.emet", "g :: Nat\ng = 1\n")]) @?= ["E02105"],
      testCase "Nat widens to Rat" $ do
        let src = "half :: Rat -> Rat\nhalf x = x / 2\nf :: Nat -> Rat\nf n = half n\n"
        r <- call src "f" [nat 3] >>= ok
        r @?= rat 1.5,
      testCase "Nat and Int in a list widen to Int" $ do
        r <- call "f :: List Int\nf = [1, -1]\n" "f" [] >>= ok
        r @?= RList [nat 1, int (-1)],
      testCase "Rat does not narrow to Nat: E02101" $
        codes "f :: Rat -> Nat\nf x = x\n" @?= ["E02101"],
      testCase "'a' == \"a\" is E02101" $
        codes "f :: Bool\nf = 'a' == \"a\"\n" @?= ["E02101"],
      testCase "Char and String compare by their code points" $ do
        r <- call "f :: Bool\nf = 'a' < 'b' && \"ab\" < \"b\" && '漢' > 'z'\n" "f" [] >>= ok
        r @?= bool True,
      testCase "String.chars of 漢字 is two Chars" $ do
        r <- call "f :: List Char\nf = String.chars \"漢字\"\n" "f" [] >>= ok
        r @?= RList [chr '漢', chr '字']
        codes "f :: List String\nf = String.chars \"漢字\"\n" @?= ["E02101"],
      testCase "String.fromChars, String.map and String.length" $ do
        r <- call "up :: Char -> Char\nup 'a' = 'A'\nup c = c\nf :: (String, Nat)\nf = (String.map up (String.fromChars ['a', 'b']), String.length \"漢字\")\n" "f" [] >>= ok
        r @?= RTuple [str "Ab", nat 2],
      testCase "comparing values of a data type of the user with == is E02101" $
        codes "data T = A | B\nf :: Bool\nf = A == B\n" @?= ["E02101"],
      testCase "++ joins strings and lists only" $ do
        codes "f :: Nat\nf = 1 ++ 2\n" @?= ["E02101"]
        r <- call "f :: String\nf = \"a\" ++ \"b\"\n" "f" [] >>= ok
        r @?= str "ab",
      testCase "an operator on variables of type takes the narrowest type of the arguments" $ do
        r <- call "f :: Nat\nf = g\n  where {\n    g = h 1 2\n    h x y = x + y\n  }\n" "f" [] >>= ok
        r @?= nat 3,
      testCase "a variable of a signature is no number: E02101" $
        codes "f :: a -> a\nf x = x + 1\n" @?= ["E02101"],
      testCase "a polymorphic function of the user" $ do
        r <- call "first :: List a -> Maybe a\nfirst [] = Nothing\nfirst (x : _) = Just x\nf :: Maybe String\nf = first [\"a\"]\n" "f" [] >>= ok
        r @?= RCon "Just" [str "a"]
    ]

exhaustiveTests :: TestTree
exhaustiveTests =
  testGroup
    "exhaustiveness"
    [ testCase "equations without Nothing are E03100 and name Nothing" $ do
        let src = "f :: Maybe Nat -> Nat\nf (Just n) = n\n"
        codes src @?= ["E03100"]
        assertBool (show (messages src)) (any ("Nothing" `T.isInfixOf`) (messages src)),
      testCase "equations of (x : xs) only are E03100 and name []" $ do
        let src = "f :: List Nat -> Nat\nf (x : xs) = x\n"
        codes src @?= ["E03100"]
        assertBool (show (messages src)) (any ("[]" `T.isInfixOf`) (messages src)),
      testCase "[a, b] counts as a : b : []" $ do
        noDiagnostics "f :: List Nat -> Nat\nf [] = 0\nf [a] = a\nf (a : b : rest) = b\n"
        codes "f :: List Nat -> Nat\nf [] = 0\nf (a : b : rest) = b\n" @?= ["E03100"],
      testCase "a case without [] is E03100" $
        codes "f :: List Nat -> Nat\nf xs = case xs of {\n  [x] -> x\n  [x, y] -> y\n}\n" @?= ["E03100"],
      testCase "guards without otherwise are E03102" $ do
        let src = "f :: Nat -> Nat\nf n\n  | n > 1 = 1\n  | n <= 1 = 0\n"
        codes src @?= ["E03102"]
        messages src @?= ["ガードの並びの最後が otherwise ではありません: f"],
      testCase "guards without otherwise followed by an equation of variables only are no error" $
        noDiagnostics "f :: Nat -> Nat\nf n\n  | n > 1 = 1\nf _ = 0\n",
      testCase "a last guard of True is E03102" $
        codes "f :: Nat -> Nat\nf n\n  | n > 1 = 1\n  | True = 0\n" @?= ["E03102"],
      testCase "a guard after otherwise is E03101" $
        codes "f :: Nat -> Nat\nf n\n  | otherwise = 1\n  | n > 1 = 0\n" @?= ["E03101"],
      testCase "a second _ is E03101" $
        codes "f :: Nat -> Nat\nf _ = 1\nf _ = 2\n" @?= ["E03101"],
      testCase "an alternative of case never chosen is E03101" $
        codes "f :: Bool -> Nat\nf b = case b of {\n  True -> 1\n  False -> 0\n  True -> 2\n}\n" @?= ["E03101"],
      testCase "the ternary operator always covers" $
        noDiagnostics "f :: Nat -> Nat\nf n = n > 1 ? 1 : n == 0 ? 2 : 3\n",
      testCase "literals need a catch-all" $ do
        codes "f :: Nat -> Nat\nf 0 = 1\nf 1 = 2\n" @?= ["E03100"]
        noDiagnostics "f :: Nat -> Nat\nf 0 = 1\nf n = n\n",
      testCase "a tuple of Bools" $ do
        noDiagnostics "f :: (Bool, Bool) -> Nat\nf (True, _) = 1\nf (False, True) = 2\nf (False, False) = 3\n"
        codes "f :: (Bool, Bool) -> Nat\nf (True, _) = 1\nf (False, True) = 2\n" @?= ["E03100"],
      testCase "a record pattern" $ do
        let src = "data Book = Book { title :: String, year :: Nat }\nt :: Book -> String\nt Book { title = s } = s\nb :: String\nb = t (Book \"題\" 2020)\nc :: String\nc = t (Book { year = 2020, title = \"名\" })\n"
        noDiagnostics src
        r <- call src "b" [] >>= ok
        r @?= str "題"
        r' <- call src "c" [] >>= ok
        r' @?= str "名"
    ]

evalTests :: TestTree
evalTests =
  testGroup
    "evaluation"
    [ testCase "a binding of where divided by 0 is no error unused" $ do
        r <- call "f :: Nat -> Rat\nf x = x == 0 ? 1 : y\n  where {\n    y = 1 / 0\n  }\n" "f" [nat 0] >>= ok
        r @?= nat 1,
      testCase "a binding of where divided by 0 is the error of division used" $ do
        d <- call "f :: Nat -> Rat\nf x = x == 0 ? y : 1\n  where {\n    y = 1 / 0\n  }\n" "f" [nat 0] >>= failure
        diagCode d @?= DiagnosticCode "G02003",
      testCase "a binding used twice is evaluated once" $ do
        let src u = "f :: Nat\nf = " <> u <> "\n  where {\n    y = List.length (List.range 1 1000)\n  }\n"
        (a, once) <- stepsOf (src "y + 1") "f" []
        (b, twice) <- stepsOf (src "y + y") "f" []
        a @?= Right (nat 1001)
        b @?= Right (nat 2000)
        twice @?= once,
      testCase "a binding used by no equation nor binding is the notice E02109" $ do
        let src = "f :: Nat\nf = 1\n  where {\n    unused = 2\n  }\n"
            (ds, p) = load src
        [(c, diagSeverity d, diagMessage d) | d <- ds, let { DiagnosticCode c = diagCode d }] @?= [("E02109", Notice, "使われていない where の束縛です: unused")]
        assertBool "the program loads" (isJust p)
        assertBool "E02109 is a notice" (DiagnosticCode "E02109" `elem` noticeCodes)
        silenceNotices (Just (Set.fromList [DiagnosticCode "E02109"])) ds @?= [],
      testCase "a binding used by another binding only is used" $
        noDiagnostics "f :: Nat\nf = a\n  where {\n    a = b + 1\n    b = 2\n  }\n",
      testCase "a binding that needs itself is E04102" $ do
        d <- call "f :: Nat\nf = a\n  where {\n    a :: Nat\n    a = a + 1\n  }\n" "f" [] >>= failure
        diagCode d @?= DiagnosticCode "E04102"
        diagSpan d @?= callSpan
        diagMessage d @?= "where の束縛が評価の途中で自分自身の値を求めました: a → a（f、main.emet:1）",
      testCase "two bindings that need each other are E04102" $ do
        d <- call "f :: Nat\nf = a\n  where {\n    a :: Nat\n    a = b + 1\n    b :: Nat\n    b = a + 1\n  }\n" "f" [] >>= failure
        diagCode d @?= DiagnosticCode "E04102"
        diagMessage d @?= "where の束縛が評価の途中で自分自身の値を求めました: a → b → a（f、main.emet:1）",
      testCase "the error of division points into the .emet" $ do
        let src = "f :: Nat -> Rat\nf x = 1 / x\n"
        d <- call src "f" [nat 0] >>= failure
        (spanFile (diagSpan d), spanStart (diagSpan d)) @?= (FileId 100, T.length (fst (T.breakOn "1 / x" src))),
      testCase "&& and || evaluate the right only when needed" $ do
        r <- call "f :: Nat -> Bool\nf x = x == 0 || 1 / x > 0\n" "f" [nat 0] >>= ok
        r @?= bool True,
      testCase "List.map, List.foldl and ++" $ do
        let src = "double :: Nat -> Nat\ndouble n = n * 2\nadd :: Nat -> Nat -> Nat\nadd a b = a + b\nf :: Nat\nf = List.foldl add 0 (List.map double ([1, 2] ++ [3]))\n"
        r <- call src "f" [] >>= ok
        r @?= nat 12,
      testCase "the arithmetic of the expression context: 1 - 2 is an integer" $ do
        r <- call "f :: Int\nf = 1 - 2\n" "f" [] >>= ok
        r @?= int (-1)
    ]

importTests :: TestTree
importTests =
  testGroup
    "import"
    [ testCase "a pub function of an import is called without a namespace" $ do
        let files = [("main.emet", "import \"lib/a.emet\"\nf :: Nat\nf = g + 1\n"), ("lib/a.emet", "pub g :: Nat\ng = 1\n")]
        r <- callAt files "f" [] >>= ok
        r @?= nat 2,
      testCase "pub data types, constructors and aliases come too" $ do
        let files = [("main.emet", "import \"lib/a.emet\"\nf :: Name -> Shape\nf _ = Circle 1\n"), ("lib/a.emet", "pub data Shape = Circle Nat | Square Nat\npub type Name = String\n")]
        r <- callAt files "f" [str "x"] >>= ok
        r @?= RCon "Circle" [nat 1],
      testCase "a name that is not pub is E02105" $
        codesOf (loadMany [("main.emet", "import \"lib/a.emet\"\nf :: Nat\nf = g\n"), ("lib/a.emet", "g :: Nat\ng = 1\n")]) @?= ["E02105"],
      testCase "two imports of the same name are E02108, unused too" $ do
        let files = [("main.emet", "import \"a.emet\"\nimport \"b.emet\"\nf :: Nat\nf = 1\n"), ("a.emet", "pub g :: Nat\ng = 1\n"), ("b.emet", "pub g :: Nat\ng = 2\n")]
            (ds, _) = loadMany files
        codesOf (ds, ()) @?= ["E02108"]
        assertBool (show ds) (all (\d -> "a.emet" `T.isInfixOf` diagMessage d && "b.emet" `T.isInfixOf` diagMessage d) ds),
      testCase "an imported name and a definition of the file are E02108" $
        codesOf (loadMany [("main.emet", "import \"a.emet\"\ng :: Nat\ng = 2\n"), ("a.emet", "pub g :: Nat\ng = 1\n")]) @?= ["E02108"],
      testCase "imports are not transitive: E02100" $
        codesOf (loadMany [("main.emet", "import \"a.emet\"\nf :: Nat\nf = h\n"), ("a.emet", "import \"b.emet\"\npub g :: Nat\ng = h\n"), ("b.emet", "pub h :: Nat\nh = 1\n")]) @?= ["E02100"],
      testCase "a built-in module is used with its name only" $
        codes "f :: Nat\nf = length [1]\n" @?= ["E02100"],
      testCase "a missing file is G03002 and a path outside the root G03003" $ do
        codesOf (loadMany [("main.emet", "import \"none.emet\"\nf :: Nat\nf = 1\n")]) @?= ["G03002"]
        codesOf (loadMany [("main.emet", "import \"../b.emet\"\nf :: Nat\nf = 1\n")]) @?= ["G03003"]
    ]

tailTests :: TestTree
tailTests =
  testGroup
    "tail calls"
    [ testCase "a tail recursion of ten million calls ends" $ do
        r <- call loopSrc "loop" [nat 10000000]
        void r @?= Right (),
      testCase "a mutual tail recursion ends" $ do
        let src = "even :: Int -> Bool\neven 0 = True\neven n = odd (n - 1)\nodd :: Int -> Bool\nodd 0 = False\nodd n = even (n - 1)\n"
        r <- call src "even" [nat 100001] >>= ok
        r @?= bool False,
      testCase "a recursion that is not a tail call beyond 10000 is E04101" $ do
        let src = "sum :: Int -> Int\nsum 0 = 0\nsum n = n + sum (n - 1)\n"
        small <- call src "sum" [nat 9000] >>= ok
        small @?= int (9000 * 9001 `div` 2)
        d <- call src "sum" [nat 20000] >>= failure
        diagCode d @?= DiagnosticCode "E04101"
        diagSpan d @?= callSpan
        diagMessage d @?= "末尾でない呼び出しの深さが上限（10000）を超えました: sum（main.emet:1）"
    ]

loopSrc :: Text
loopSrc = "loop :: Int -> Int\nloop 0 = 0\nloop n = loop (n - 1)\n"

-- | Nat to kanji numerals, the work of the sample plugin kansuji.
kansujiSrc :: Text
kansujiSrc =
  T.unlines
    [ "digit :: Nat -> String",
      "digit 1 = \"一\"",
      "digit 2 = \"二\"",
      "digit 3 = \"三\"",
      "digit 4 = \"四\"",
      "digit 5 = \"五\"",
      "digit 6 = \"六\"",
      "digit 7 = \"七\"",
      "digit 8 = \"八\"",
      "digit 9 = \"九\"",
      "digit _ = \"\"",
      "unit :: Nat -> String -> String",
      "unit 0 _ = \"\"",
      "unit 1 u = u",
      "unit d u = digit d ++ u",
      "small :: Nat -> String",
      "small n = unit (div n 1000) \"千\" ++ unit (div (n % 1000) 100) \"百\" ++ unit (div (n % 100) 10) \"十\" ++ digit (n % 10)",
      "kansuji :: Nat -> String",
      "kansuji 0 = \"〇\"",
      "kansuji n = groups n [\"\", \"万\", \"億\", \"兆\", \"京\"] \"\"",
      "groups :: Nat -> List String -> String -> String",
      "groups 0 _ acc = acc",
      "groups _ [] acc = acc",
      "groups n (u : rest) acc = groups (div n 10000) rest ((n % 10000 == 0 ? \"\" : small (n % 10000) ++ u) ++ acc)"
    ]

-- | The first occurrence of each word marked, the work of the sample plugin first-ruby on strings.
firstSrc :: Text
firstSrc =
  T.unlines
    [ "firstMarks :: List String -> List String -> List String",
      "firstMarks words tokens = go words tokens []",
      "go :: List String -> List String -> List String -> List String",
      "go _ [] acc = List.reverse acc",
      "go seen (t : rest) acc = List.any (same t) seen",
      "  ? go (List.select (other t) seen) rest ((\"《\" ++ t ++ \"》\") : acc)",
      "  : go seen rest (t : acc)",
      "same :: String -> String -> Bool",
      "same a b = a == b",
      "other :: String -> String -> Bool",
      "other a b = a /= b"
    ]

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
        (_, ls) <- stepsOf loopSrc "loop" [nat 10000000]
        assertBool (show (ks, fs, ls)) (3 * maximum [ks, fs, ls] <= stepLimit),
      testCase "a tail recursion that never stops is E04100, the same twice" $ do
        let src = "spin :: Nat -> Nat\nspin n = spin (n + 1)\n"
        a <- call src "spin" [nat 0]
        b <- call src "spin" [nat 0]
        a @?= b
        d <- failure a
        diagCode d @?= DiagnosticCode "E04100"
        diagSpan d @?= callSpan
        diagMessage d @?= "関数の評価の手数が上限（" <> T.pack (show stepLimit) <> " 手）を超えました: spin（main.emet:1）",
      testCase "doubling a string is E04100 before the memory runs out" $ do
        d <- call "grow :: String -> String\ngrow s = grow (s ++ s)\n" "grow" [str "ab"] >>= failure
        diagCode d @?= DiagnosticCode "E04100",
      sizeTests
    ]

{- | The sizes of what the built-in functions and @++@ make, found before
they make it (docs/adr/0223). Each test that refuses a value bounds the
allocation of its thread by 64 MiB; the time-out of the watchdog and of
'within' bounds the time.
-}
sizeTests :: TestTree
sizeTests =
  testGroup
    "the sizes before the values (docs/adr/0223)"
    [ testProperty "S1: the size of every built-in function is the length of what it makes" $ withTests 2000 $ property $ do
        (name, args) <- forAll primCall
        case runPrim (2 ^ (80 :: Int)) name args of
          Right (v, n) -> toInteger n === lengthOf v
          Left _ -> failure_ name
        -- and one step less is refused
        case runPrim (toInteger (either (const 0) snd (runPrim (2 ^ (80 :: Int)) name args)) - 1) name args of
          Left PrimOverLimit -> success
          _ -> failure_ name,
      testCase "S2, S3: a call of List.range takes exactly the steps it is counted" $
        forM_ [0, 1, 2, 10, 50] $ \n -> limits rangeSrc [int n],
      testCase "S2, S3: String.replace, String.join, List.concat and ++ take exactly the steps they are counted" $ do
        -- from empty, no occurrence, to shorter than from, longer
        forM_ [("", "x", "abc"), ("q", "xy", "abc"), ("ab", "x", "ababab"), ("a", "xyz", "banana")] $ \(a, b, c) ->
          limits replaceSrc [str a, str b, str c]
        -- no element, one, an empty separator, a long one
        forM_ [("", []), (",", ["a"]), ("", ["ab", "c"]), ("-----", ["ab", "c", "d"])] $ \(sep, xs) ->
          limits joinSrc [str sep, RList (map str xs)]
        forM_ [[], [[]], [[1], [], [2, 3]]] $ \xss -> limits concatSrc [RList [RList (map int xs) | xs <- xss]]
        forM_ [("", ""), ("", "ab"), ("abc", "de")] $ \(a, b) -> limits appendSrc [str a, str b]
        forM_ [([], []), ([1], [2, 3])] $ \(a, b) -> limits appendListSrc [RList (map int a), RList (map int b)],
      testCase "S3, S4: List.range of 2^63, 2^64 and 2^4097 elements is E04100, given to List.take 3 or to List.length" $
        forM_ [2 ^ (63 :: Int), 2 ^ (64 :: Int), 2 ^ (4097 :: Int)] $ \n ->
          forM_ [takeSrc, lengthSrc] $ \src -> do
            (r, bytes) <- allocated (call src "f" [int n])
            fmap diagCode (either Just (const Nothing) r) @?= Just (DiagnosticCode "E04100")
            assertBool ("allocated " <> show bytes) (bytes <= 64 * 2 ^ (20 :: Int)),
      testCase "S3, S4: List.range of 2^31, 2^32 and 2^63 - 1 elements is E04100" $
        forM_ [2 ^ (31 :: Int), 2 ^ (32 :: Int), 2 ^ (63 :: Int) - 1] $ \n -> do
          (r, bytes) <- allocated (call takeSrc "f" [int n])
          fmap diagCode (either Just (const Nothing) r) @?= Just (DiagnosticCode "E04100")
          assertBool ("allocated " <> show bytes) (bytes <= 64 * 2 ^ (20 :: Int)),
      -- the remaining steps exactly and one more are the tests of S2 and S3
      -- above, with small limits: a range that fills the default limit is
      -- 10^8 values
      testCase "S4: a limit of the largest Int64 - 10 and List.range of 2^63 - 1 elements is E04100" $ do
        (r, bytes) <- allocated (limited (maxBound - 10) takeSrc [int (2 ^ (63 :: Int) - 1)])
        fmap diagCode (either Just (const Nothing) r) @?= Just (DiagnosticCode "E04100")
        assertBool ("allocated " <> show bytes) (bytes <= 64 * 2 ^ (20 :: Int)),
      testCase "S3: String.replace of 400,000,000 characters is E04100 (the security audit of 2026-11-06, E-02)" $ do
        (r, bytes) <- allocated (call replaceSrc "f" [str "a", str (T.replicate 20000 "b"), str (T.replicate 20000 "a")])
        fmap diagCode (either Just (const Nothing) r) @?= Just (DiagnosticCode "E04100")
        assertBool ("allocated " <> show bytes) (bytes <= 64 * 2 ^ (20 :: Int)),
      testCase "S3: String.join and List.concat of a value shared 20,000 times are E04100" $ do
        {- the 20,000 calls of rep allocate some 50 MB themselves, the same
        for a value of one element: the bound is 64 MiB over that -}
        _ <- allocated (call repSrc "joined" [int 0, str "x"])
        (_, jBase) <- allocated (call repSrc "joined" [int 20000, str "x"])
        (j, jb) <- allocated (call repSrc "joined" [int 20000, str (T.replicate 20000 "x")])
        fmap diagCode (either Just (const Nothing) j) @?= Just (DiagnosticCode "E04100")
        assertBool ("allocated " <> show jb <> ", for one character " <> show jBase) (jb <= jBase + 64 * 2 ^ (20 :: Int))
        (_, cBase) <- allocated (call repSrc "concatenated" [int 20000, RList [int 1]])
        (c, cb) <- allocated (call repSrc "concatenated" [int 20000, RList (replicate 20000 (int 1))])
        fmap diagCode (either Just (const Nothing) c) @?= Just (DiagnosticCode "E04100")
        assertBool ("allocated " <> show cb <> ", for one element " <> show cBase) (cb <= cBase + 64 * 2 ^ (20 :: Int))
        -- ten times is no error
        small <- call repSrc "joined" [int 10, str (T.replicate 20000 "x")]
        case small of
          Right (RPrim (VString t)) -> T.length t @?= 200000
          other -> assertFailure (show other),
      testCase "S5: a call stopped by E04100 took the limit + 1 steps, by a reduction or by a size" $ do
        (spin, spun) <- stepsOf "spin :: Nat -> Nat\nspin n = spin (n + 1)\n" "spin" [nat 0]
        fmap diagCode (either Just (const Nothing) spin) @?= Just (DiagnosticCode "E04100")
        spun @?= stepLimit + 1
        (range, ranged) <- stepsOf takeSrc "f" [int (2 ^ (64 :: Int))]
        fmap diagCode (either Just (const Nothing) range) @?= Just (DiagnosticCode "E04100")
        ranged @?= stepLimit + 1,
      testCase "S6: E04100 of a size is at the call, with the name and the line of the function, the same twice" $ do
        a <- call takeSrc "f" [int (2 ^ (64 :: Int))]
        b <- call takeSrc "f" [int (2 ^ (64 :: Int))]
        a @?= b
        d <- failure a
        diagCode d @?= DiagnosticCode "E04100"
        diagSpan d @?= callSpan
        diagMessage d @?= "関数の評価の手数が上限（" <> T.pack (show stepLimit) <> " 手）を超えました: f（main.emet:1）",
      testCase "S6: the limit of a filter is that of a command and 10000 steps a byte, up to the largest Int64" $ do
        filterFuel 0 @?= stepLimit
        filterFuel 204748 @?= 2147480000
        filterFuel 204749 @?= 2147490000
        filterFuel maxBound @?= maxBound
    ]
  where
    failure_ name = annotate (T.unpack name) >> Hedgehog.failure
    rangeSrc = "f :: Int -> List Int\nf n = List.range 1 n\n"
    takeSrc = "f :: Int -> List Int\nf n = List.take 3 (List.range 1 n)\n"
    lengthSrc = "f :: Int -> Nat\nf n = List.length (List.range 1 n)\n"
    replaceSrc = "f :: String -> String -> String -> String\nf a b c = String.replace a b c\n"
    joinSrc = "f :: String -> List String -> String\nf sep xs = String.join sep xs\n"
    concatSrc = "f :: List (List Int) -> List Int\nf xss = List.concat xss\n"
    appendSrc = "f :: String -> String -> String\nf a b = a ++ b\n"
    appendListSrc = "f :: List Int -> List Int -> List Int\nf a b = a ++ b\n"
    -- the functions of 「確かめたこと」 of the ADR
    repSrc =
      T.unlines
        [ "rep :: Int -> String -> List String -> List String",
          "rep 0 s acc = acc",
          "rep n s acc = rep (n - 1) s (s : acc)",
          "repl :: Int -> List Int -> List (List Int) -> List (List Int)",
          "repl 0 s acc = acc",
          "repl n s acc = repl (n - 1) s (s : acc)",
          "joined :: Int -> String -> String",
          "joined n x = String.join \"\" (rep n x [])",
          "concatenated :: Int -> List Int -> Nat",
          "concatenated n xs = List.length (List.concat (repl n xs []))"
        ]
    -- the call succeeds with the limit of the steps it took, and is E04100 with one less
    limits src args = do
      (r, c) <- stepsOf src "f" args
      fmap (const ()) r @?= Right ()
      atC <- limited c src args
      atC @?= r
      below <- limited (c - 1) src args
      fmap diagCode (either Just (const Nothing) below) @?= Just (DiagnosticCode "E04100")
    limited limit src args = case load src of
      (ds, Just p) | not (any isError ds) -> pure (callFunctionLimited limit noHandlers p callSpan "main.emet" "f" args)
      (ds, _) -> assertFailure (show ds) >> fail "unreachable"
    -- the result forced, and the bytes this thread allocated for it
    allocated act = do
      setAllocationCounter 0
      r <- act >>= evaluate . forceEither
      left <- getAllocationCounter
      pure (r, negate left)
    forceEither r = case r of
      Left d -> length (show d) `seq` r
      Right v -> length (show v) `seq` r

-- | A built-in function that makes a value, with small arguments of its types.
primCall :: Gen (Text, [PrimValue])
primCall =
  Gen.choice
    [ (\a b -> ("List.range", [PV (VInt a), PV (VInt b)])) <$> small <*> small,
      (\a b c -> ("String.replace", [s' a, s' b, s' c])) <$> text' <*> text' <*> text',
      (\a xs -> ("String.join", [s' a, primList (map s' xs)])) <$> text' <*> Gen.list (Range.linear 0 20) text',
      (\xss -> ("List.concat", [primList [primList (map (PV . VInt) xs) | xs <- xss]])) <$> Gen.list (Range.linear 0 20) (Gen.list (Range.linear 0 20) small),
      (\cs -> ("String.fromChars", [primList (map PCh cs)])) <$> Gen.string (Range.linear 0 20) charG,
      (\c -> ("String.fromChar", [PCh c])) <$> charG,
      (\a -> ("String.chars", [s' a])) <$> text',
      (\a b -> ("String.split", [s' a, s' b])) <$> text' <*> text',
      (\a -> ("String.lines", [s' a])) <$> text',
      (\a -> ("String.trim", [s' a])) <$> text',
      (\n a -> ("String.take", [PV (VInt n), s' a])) <$> small <*> text',
      (\n a -> ("String.drop", [PV (VInt n), s' a])) <$> small <*> text',
      (\xs -> ("List.reverse", [primList (map (PV . VInt) xs)])) <$> Gen.list (Range.linear 0 20) small,
      (\n xs -> ("List.take", [PV (VInt n), primList (map (PV . VInt) xs)])) <$> small <*> Gen.list (Range.linear 0 20) small,
      (\n xs -> ("List.drop", [PV (VInt n), primList (map (PV . VInt) xs)])) <$> small <*> Gen.list (Range.linear 0 20) small,
      (\n -> ("String.fromNat", [PV (VNat (fromInteger (abs n)))])) <$> Gen.integral (Range.linear 0 (10 ^ (30 :: Int))),
      (\n -> ("String.fromInt", [PV (VInt n)])) <$> Gen.integral (Range.linearFrom 0 (negate (10 ^ (30 :: Int))) (10 ^ (30 :: Int))),
      (\a b -> ("String.fromRat", [PV (VRat (fromInteger a / fromInteger (max 1 b)))])) <$> small <*> Gen.integral (Range.linear 1 64)
    ]
  where
    small = Gen.integral (Range.linearFrom 0 (-50) 50)
    charG = Gen.element ("ab\n あ" :: String)
    text' = Gen.text (Range.linear 0 20) charG
    s' = PV . VString

-- | The length of a value a built-in function made: of a string or a list.
lengthOf :: PrimValue -> Integer
lengthOf = \case
  PV (VString t) -> toInteger (T.length t)
  PL _ xs -> toInteger (length xs)
  _ -> 0

determinismTests :: TestTree
determinismTests =
  testCase "evaluating in parallel gives what evaluating in sequence gives" $ do
    let src = "sum :: Int -> Int\nsum 0 = 0\nsum n = n + sum (n - 1)\nf :: Nat -> Rat\nf n = 1 / (n - 3)\n"
        calls = [("sum", [nat n]) | n <- [10, 5000, 20000]] <> [("f", [nat n]) | n <- [1 .. 5]]
    sequential <- mapM (uncurry (call src)) calls
    vars <- forM calls $ \(f, as) -> do
      var <- newEmptyMVar
      _ <- forkIO (call src f as >>= evaluate . forceResult >>= putMVar var)
      pure var
    parallel <- mapM takeMVar vars
    parallel @?= sequential
  where
    forceResult r = length (show r) `seq` r
