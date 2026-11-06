{- | What the editor shows of a .emet (docs/adr/0170): the highlighting
of the lossless syntax tree, the outline, renaming, and the types of the
local names.
-}
module IdeSpec (ideTests) where

import Data.ByteString qualified as BS
import Data.Either (fromRight)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet
import Golem.Emet.Highlight
import Golem.Emet.Ide (emetLocalHover)
import Golem.Emet.Outline
import Golem.Emet.Rename
import Golem.Emet.Syntax (Module (..))
import Golem.Syntax (FileId (..), isError)
import Support
import Test.Tasty
import Test.Tasty.HUnit

ideTests :: TestTree
ideTests =
  testGroup
    "the editor support of .emet (docs/adr/0170)"
    [highlightTests, outlineTests, renameTests, localTypeTests]

-- | The byte offset of a needle in a text, and a number of bytes further.
offsetIn :: Text -> Text -> Int -> Int
offsetIn text needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle text))) + k

-- * Highlighting

sample :: Text
sample =
  T.unlines
    [ "-- 税込み",
      "import \"lib.emet\"",
      "pub inline \"x-y\" f :: (tax :: Bool = True) -> List.T a -> <file \"a.tsv\"|e> Nat",
      "f tax x = List.map g [x, 'c'] ? 1.5 : Just -2",
      "  where {",
      "    g :: a -> a",
      "    g y = case y of {",
      "      Just z -> z",
      "      _ | otherwise -> \"s\"",
      "    }",
      "  }",
      "data T a = A | B { b :: Nat }",
      "type U = T Nat"
    ]

-- | The type, the declaration and the length of the token that starts at a needle and a number of bytes further.
tokenAt :: Text -> Text -> Int -> Maybe (HlType, Bool, Int)
tokenAt src needle k =
  let off = offsetIn src needle k
   in listToMaybe [(hlType h, hlDeclaration h, hlEnd h - hlStart h) | h <- emetHighlights src, hlStart h == off]

highlightTests :: TestTree
highlightTests =
  testGroup
    "highlighting"
    [ testCase "comments, keywords, strings and the names of declarations" $ do
        let at = tokenAt sample
        at "-- 税込み" 0 @?= Just (HlComment, False, 12)
        at "import" 0 @?= Just (HlKeyword, False, 6)
        at "\"lib.emet\"" 0 @?= Just (HlString, False, 10)
        at "pub" 0 @?= Just (HlKeyword, False, 3)
        at "inline" 0 @?= Just (HlKeyword, False, 6)
        at "\"x-y\"" 0 @?= Just (HlString, False, 5)
        at "f ::" 0 @?= Just (HlFunction, True, 1)
        at "f tax" 0 @?= Just (HlFunction, True, 1)
        at "g ::" 0 @?= Just (HlFunction, True, 1)
        at "g y" 0 @?= Just (HlFunction, True, 1)
        at "data" 0 @?= Just (HlKeyword, False, 4)
        at "T a =" 0 @?= Just (HlType, True, 1)
        at "A |" 0 @?= Just (HlEnumMember, True, 1)
        at "B {" 0 @?= Just (HlEnumMember, True, 1)
        at "type" 0 @?= Just (HlKeyword, False, 4)
        at "U =" 0 @?= Just (HlType, True, 1)
        at "where" 0 @?= Just (HlKeyword, False, 5)
        at "case" 0 @?= Just (HlKeyword, False, 4)
        at "of {" 0 @?= Just (HlKeyword, False, 2)
        at "otherwise" 0 @?= Just (HlKeyword, False, 9),
      testCase "names: parameters, variables, functions applied, types, type parameters, constructors, modules" $ do
        let at = tokenAt sample
        at "tax ::" 0 @?= Just (HlParameter, False, 3)
        at "tax x =" 0 @?= Just (HlParameter, False, 3)
        at "x = List" 0 @?= Just (HlParameter, False, 1)
        at "y = case" 0 @?= Just (HlParameter, False, 1)
        at "z ->" 0 @?= Just (HlVariable, False, 1)
        at "y of" 0 @?= Just (HlVariable, False, 1)
        at "List.map" 0 @?= Just (HlNamespace, False, 5)
        at "map g" 0 @?= Just (HlFunction, False, 3)
        at "g [" 0 @?= Just (HlVariable, False, 1)
        at "x, 'c'" 0 @?= Just (HlVariable, False, 1)
        at "b ::" 0 @?= Just (HlVariable, False, 1)
        at "Bool" 0 @?= Just (HlType, False, 4)
        at "List.T" 0 @?= Just (HlNamespace, False, 5)
        at "List.T" 5 @?= Just (HlType, False, 1)
        at "a -> <" 0 @?= Just (HlTypeParameter, False, 1)
        at "a -> a" 0 @?= Just (HlTypeParameter, False, 1)
        at "a = A" 0 @?= Just (HlTypeParameter, False, 1)
        at "Nat\n" 0 @?= Just (HlType, False, 3)
        at "T Nat" 0 @?= Just (HlType, False, 1)
        at "True" 0 @?= Just (HlEnumMember, False, 4)
        at "Just -2" 0 @?= Just (HlEnumMember, False, 4)
        at "Just z" 0 @?= Just (HlEnumMember, False, 4),
      testCase "literals, operators and rows of requirements" $ do
        let at = tokenAt sample
        at "'c'" 0 @?= Just (HlString, False, 3)
        at "1.5" 0 @?= Just (HlNumber, False, 3)
        at "2\n" 0 @?= Just (HlNumber, False, 1)
        at "-2" 0 @?= Just (HlOperator, False, 1)
        at ":: (" 0 @?= Just (HlOperator, False, 2)
        at "= True" 0 @?= Just (HlOperator, False, 1)
        at "-> List" 0 @?= Just (HlOperator, False, 2)
        at "= List" 0 @?= Just (HlOperator, False, 1)
        at "? 1.5" 0 @?= Just (HlOperator, False, 1)
        at ": Just" 0 @?= Just (HlOperator, False, 1)
        at "| otherwise" 0 @?= Just (HlOperator, False, 1)
        at "<file" 0 @?= Just (HlMacro, False, 1)
        at "file" 0 @?= Just (HlMacro, False, 4)
        at "\"a.tsv\"" 0 @?= Just (HlString, False, 7)
        at "|e>" 0 @?= Just (HlMacro, False, 1)
        at "e>" 0 @?= Just (HlTypeParameter, False, 1)
        at "> Nat" 0 @?= Just (HlMacro, False, 1),
      testCase "no tokens for brackets, braces, commas and the wildcard" $ do
        let at = tokenAt sample
        at "(tax" 0 @?= Nothing
        at "[x" 0 @?= Nothing
        at ", 'c'" 0 @?= Nothing
        at "where {" 6 @?= Nothing
        at "_ |" 0 @?= Nothing,
      testCase "a comment over the end of a line: one token for each line" $ do
        let src = "-- one\n-- two\nf :: Nat\nf = 1\n"
        [(hlStart h, hlEnd h) | h <- emetHighlights src, hlType h == HlComment] @?= [(0, 6), (7, 13)],
      testCase "a syntax error: the tokens before it" $ do
        let src = "f :: Nat\nf = 1\ng :: Nat\ng = (1 +\nh :: Nat\nh = 2\n"
            hs = emetHighlights src
        assertBool "the tokens of g's signature" (any ((== offsetIn src "g ::" 0) . hlStart) hs)
        assertBool "no token from the error on" (all ((< offsetIn src "g = (" 0) . hlStart) hs),
      testCase "tokens are in the order of the text and do not overlap" $ do
        let hs = emetHighlights sample
        assertBool "ordered" (and (zipWith (\a b -> hlEnd a <= hlStart b) hs (drop 1 hs)))
        assertBool "not empty" (all (\h -> hlEnd h > hlStart h) hs)
    ]

-- * The outline

outlineSource :: Text
outlineSource =
  T.unlines
    [ "import \"lib.emet\"",
      "",
      "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
      "taxIncluded n = Inline.text (show n ++ unit)",
      "  where {",
      "    show :: Nat -> String",
      "    show k = String.fromNat k",
      "    unit = \"円\"",
      "  }",
      "",
      "pub fn total :: List Nat -> <file \"w.tsv\"> Nat",
      "total xs = List.length xs",
      "",
      "data Shape = Circle Nat | Rect { w :: Nat, h :: Nat }",
      "",
      "data Point = Point { x :: Nat, y :: Nat }",
      "",
      "type Size = Nat"
    ]

-- | The names, kinds and children of a tree of symbols.
data Tree = Tree Text SymbolKind [Tree]
  deriving stock (Eq, Show)

tree :: Symbol -> Tree
tree s = Tree (symName s) (symKind s) (map tree (symChildren s))

outlineTests :: TestTree
outlineTests =
  testGroup
    "the outline"
    [ testCase "functions, bindings of where, data types, constructors, fields, aliases and imports" $
        map tree (emetOutline outlineSource)
          @?= [ Tree "lib.emet" SymModule [],
                Tree "taxIncluded" SymFunction [Tree "show" SymFunction [], Tree "unit" SymVariable []],
                Tree "total" SymFunction [],
                Tree "Shape" SymEnum [Tree "Circle" SymEnumMember [], Tree "Rect" SymEnumMember [Tree "w" SymField [], Tree "h" SymField []]],
                Tree "Point" SymStruct [Tree "Point" SymEnumMember [Tree "x" SymField [], Tree "y" SymField []]],
                Tree "Size" SymTypeParameter []
              ],
      testCase "the details: the type, after the kind and the name .gm uses" $ do
        let syms = emetOutline outlineSource
            detail n = listToMaybe [symDetail s | s <- syms, symName s == n]
        detail "taxIncluded" @?= Just (Just "pub inline \"tax-included\" :: Nat -> Inlines")
        detail "total" @?= Just (Just "pub fn :: List Nat -> <file \"w.tsv\"> Nat")
        detail "Size" @?= Just (Just "Nat")
        [symDetail c | s <- syms, symName s == "taxIncluded", c <- symChildren s] @?= [Just "Nat -> String", Nothing],
      testCase "the ranges: a function from its signature to the end of its where, its name selected" $ do
        let syms = emetOutline outlineSource
        [(symStart s, symEnd s, symNameStart s, symNameEnd s) | s <- syms, symName s == "taxIncluded"]
          @?= [(offsetIn outlineSource "pub inline" 0, offsetIn outlineSource "円\"\n  }" 8, offsetIn outlineSource "taxIncluded ::" 0, offsetIn outlineSource "taxIncluded ::" 11)]
        [(symNameStart f, symNameEnd f) | s <- syms, symName s == "Shape", c <- symChildren s, symName c == "Rect", f <- symChildren c] @?= [(offsetIn outlineSource "{ w ::" 2, offsetIn outlineSource "{ w ::" 3), (offsetIn outlineSource ", h ::" 2, offsetIn outlineSource ", h ::" 3)]
        [(symNameStart s, symNameEnd s) | s <- syms, symName s == "Shape"] @?= [(offsetIn outlineSource "Shape" 0, offsetIn outlineSource "Shape" 5)],
      testCase "a syntax error: the declarations before it" $
        map symName (emetOutline "f :: Nat\nf = 1\ng = (1 +\nh :: Nat\nh = 2\n") @?= ["f"]
    ]

-- * Renaming

mainEmet :: Text
mainEmet =
  T.unlines
    [ "import \"lib.emet\"",
      "",
      "pub fn total :: List Nat -> Nat",
      "total xs = count xs + twice (size (Circle unit))",
      "  where {",
      "    count ys = List.length ys",
      "    unit = 1",
      "  }",
      "",
      "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
      "taxIncluded n = Inline.text (String.fromNat n)",
      "",
      "pub block rule :: Blocks",
      "rule = Block.paragraph (Inline.text \"――\")",
      "",
      "pub filter tidy :: Blocks -> Blocks",
      "tidy bs = bs"
    ]

libEmet :: Text
libEmet =
  T.unlines
    [ "pub twice :: Nat -> Nat",
      "twice n = n * 2",
      "",
      "pub data Shape = Circle Nat | Square Nat",
      "",
      "pub type Size = Nat",
      "",
      "pub size :: Shape -> Size",
      "size s = case s of {",
      "  Circle r -> r * r",
      "  Square a -> a * a",
      "}"
    ]

programFiles' :: [(FilePath, Text)]
programFiles' = [("main.emet", mainEmet), ("lib.emet", libEmet)]

-- | The files as a program last checked them, the texts as the editor has them.
filesOf :: [(FilePath, Text)] -> Map.Map FilePath (Module, Text)
filesOf fs = Map.fromList [(p, (fromRight (Module []) (parseModule (FileId 0) t), t)) | (p, t) <- fs]

-- | The texts after a renaming at a needle of a file.
renamed :: FilePath -> Text -> Int -> Text -> Either RenameError [(FilePath, Text)]
renamed path needle k new = do
  let src = fromMaybe "" (lookup path programFiles')
  r <- emetRename (filesOf programFiles') path (offsetIn src needle k) new
  pure [(p, applyEdits t [(s, e) | (q, s, e) <- rnEdits r, q == p]) | (p, t) <- programFiles']
  where
    applyEdits t es =
      let bytes = TE.encodeUtf8 t
          go from = \case
            [] -> [BS.drop from bytes]
            (s, e) : rest -> BS.take (s - from) (BS.drop from bytes) : TE.encodeUtf8 new : go e rest
       in TE.decodeUtf8 (BS.concat (go 0 (sortOn fst es)))

exportedAt :: FilePath -> Text -> Text -> Either RenameError (Maybe (FilePath, Text, Kind, Bool))
exportedAt path needle new = do
  let src = fromMaybe "" (lookup path programFiles')
  rnExported <$> emetRename (filesOf programFiles') path (offsetIn src needle 0) new

renameTests :: TestTree
renameTests =
  testGroup
    "renaming"
    [ testCase "the program of the tests loads" $
        codesOf (loadMany (("main.emet", mainEmet) : [("lib.emet", libEmet)])) @?= [],
      testCase "a variable of a pattern: its binding and its uses in the equation" $
        fmap (lookup "lib.emet") (renamed "lib.emet" "n * 2" 0 "m") @?= Right (Just (T.replace "twice n = n * 2" "twice m = m * 2" libEmet)),
      testCase "a variable of a case alternative" $
        fmap (lookup "lib.emet") (renamed "lib.emet" "r ->" 0 "q") @?= Right (Just (T.replace "Circle r -> r * r" "Circle q -> q * q" libEmet)),
      testCase "a binding of where: its equation and its uses" $
        fmap (lookup "main.emet") (renamed "main.emet" "count xs" 0 "tally") @?= Right (Just (T.replace "count" "tally" mainEmet)),
      testCase "a top-level function: its declaration and its uses in the files that import it" $ do
        r <- either (assertFailure . show) pure (renamed "main.emet" "twice (" 0 "double")
        lookup "lib.emet" r @?= Just (T.replace "twice" "double" libEmet)
        lookup "main.emet" r @?= Just (T.replace "twice" "double" mainEmet),
      testCase "a constructor and a type: their declarations, patterns, expressions and signatures" $ do
        r <- either (assertFailure . show) pure (renamed "lib.emet" "Circle Nat" 0 "Round")
        lookup "lib.emet" r @?= Just (T.replace "Circle" "Round" libEmet)
        lookup "main.emet" r @?= Just (T.replace "Circle" "Round" mainEmet)
        s <- either (assertFailure . show) pure (renamed "lib.emet" "Shape ->" 0 "Form")
        lookup "lib.emet" s @?= Just (T.replace "Shape" "Form" libEmet)
        a <- either (assertFailure . show) pure (renamed "lib.emet" "Size =" 0 "Dim")
        lookup "lib.emet" a @?= Just (T.replace "Size" "Dim" libEmet),
      testCase "a function .gm uses: its kind and whether it has a string name" $ do
        exportedAt "main.emet" "total ::" "sum" @?= Right (Just ("main.emet", "total", KindFn, False))
        exportedAt "main.emet" "taxIncluded ::" "withTax" @?= Right (Just ("main.emet", "taxIncluded", KindInline, True))
        exportedAt "main.emet" "rule ::" "line" @?= Right (Just ("main.emet", "rule", KindBlock, False))
        exportedAt "main.emet" "tidy bs" "clean" @?= Right (Just ("main.emet", "tidy", KindFilter, False))
        exportedAt "lib.emet" "twice ::" "double" @?= Right Nothing,
      testCase "a command without a string name keeps a name of .gm" $
        exportedAt "main.emet" "rule ::" "ruleTwo" @?= Left (RenameNotCommand "ruleTwo"),
      testCase "a reserved word, a name of another kind, a name taken, a built-in name: an error, and nothing renamed" $ do
        renamed "lib.emet" "n * 2" 0 "where" @?= Left (RenameReserved "where")
        renamed "lib.emet" "n * 2" 0 "then" @?= Left (RenameReserved "then")
        renamed "lib.emet" "n * 2" 0 "N" @?= Left (RenameInvalid "N")
        renamed "lib.emet" "Circle Nat" 0 "circle" @?= Left (RenameInvalid "circle")
        renamed "main.emet" "count xs" 0 "unit" @?= Left (RenameTaken "unit")
        renamed "main.emet" "count xs" 0 "xs" @?= Left (RenameTaken "xs")
        renamed "main.emet" "xs =" 0 "count" @?= Left (RenameTaken "count")
        renamed "main.emet" "xs =" 0 "twice" @?= Left (RenameTaken "twice")
        renamed "lib.emet" "twice ::" 0 "total" @?= Left (RenameTaken "total")
        renamed "lib.emet" "twice ::" 0 "size" @?= Left (RenameTaken "size")
        renamed "lib.emet" "twice ::" 0 "div" @?= Left (RenameTaken "div")
        renamed "lib.emet" "Circle Nat" 0 "Just" @?= Left (RenameTaken "Just")
        renamed "lib.emet" "Shape ->" 0 "List" @?= Left (RenameTaken "List")
        renamed "main.emet" "List.length" 6 "len" @?= Left (RenameBuiltin "List.length")
        renamed "main.emet" "Nat ->" 0 "N" @?= Left (RenameBuiltin "Nat")
        renamed "main.emet" "total xs" 0 "taxIncluded" @?= Left (RenameTaken "taxIncluded"),
      testCase "a file to rewrite that does not parse: an error" $
        emetRename (Map.insert "main.emet" (fst (filesOf programFiles' Map.! "main.emet"), mainEmet <> "broken = (\n") (filesOf programFiles')) "lib.emet" (offsetIn libEmet "twice ::" 0) "double"
          @?= Left (RenameSyntax "main.emet")
    ]

-- * The types of local names

typedEmet :: Text
typedEmet =
  T.unlines
    [ "pub fn count :: List String -> <file \"data/words.tsv\"> Nat",
      "count xs = List.length (List.select known xs) + pick (List.at 0 xs) + konst xs",
      "  where {",
      "    words = String.lines (File.read \"data/words.tsv\")",
      "    known w = List.any (same w) words",
      "    same a b = a == b",
      "    konst y = 0",
      "    pick m = case m of {",
      "      Just s -> String.length s",
      "      Nothing -> 0",
      "    }",
      "  }",
      "",
      "pub inline \"tax-included\" taxIncluded :: Nat -> (rate :: Nat = 10) -> Inlines",
      "taxIncluded n rate = Inline.text (String.fromNat (n + rate))"
    ]

localTypeTests :: TestTree
localTypeTests =
  testGroup
    "the types of local names"
    [ testCase "variables of patterns, of alternatives, bindings of where and keyword arguments, where bound and named" $ do
        p <- program
        let at needle k = emetLocalHover p "main.emet" typedEmet (offsetIn typedEmet needle k)
        at "xs =" 0 @?= Just "xs :: List String"
        at "xs) +" 0 @?= Just "xs :: List String"
        at "s ->" 0 @?= Just "s :: String"
        at "length s\n" 7 @?= Just "s :: String"
        at "m =" 0 @?= Just "m :: Maybe String"
        at "words =" 0 @?= Just "words :: <file \"data/words.tsv\"> List String"
        at "words\n" 0 @?= Just "words :: <file \"data/words.tsv\"> List String"
        at "rate =" 0 @?= Just "rate :: Nat"
        at "rate))" 0 @?= Just "rate :: Nat"
        at "n rate" 0 @?= Just "n :: Nat",
      testCase "a function of where generalised: its variables named a, b; a variable never decided: a" $ do
        p <- program
        let at needle k = emetLocalHover p "main.emet" typedEmet (offsetIn typedEmet needle k)
        at "konst y" 0 @?= Just "konst :: a -> Nat"
        at "konst xs" 0 @?= Just "konst :: a -> Nat"
        at "y = 0" 0 @?= Just "y :: a",
      testCase "a function of where with requirements: its row" $ do
        p <- program
        let at needle k = emetLocalHover p "main.emet" typedEmet (offsetIn typedEmet needle k)
        fmap (T.isPrefixOf "known :: String -> <file \"data/words.tsv\"") (at "known w" 0) @?= Just True,
      testCase "no type of a local name when the text is not the one checked" $ do
        p <- program
        emetLocalHover p "main.emet" (typedEmet <> "\n") (offsetIn typedEmet "xs =" 0) @?= Nothing,
      testCase "a top-level name is no local name" $ do
        p <- program
        emetLocalHover p "main.emet" typedEmet (offsetIn typedEmet "count xs" 0) @?= Nothing
    ]
  where
    program = case loadMany [("main.emet", typedEmet)] of
      (ds, Just p) | not (any isError ds) -> pure p
      (ds, _) -> assertFailure ("the source did not load: " <> show ds) >> fail "unreachable"
