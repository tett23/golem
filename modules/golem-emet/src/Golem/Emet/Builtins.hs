{- | The built-in modules of .emet (docs/adr/0160): @List@ and @String@,
used without import and always with their names (@List.map@). Their
functions are written in .emet on top of primitives ('Golem.Emet.Prim'):
a signature without equations is a primitive. The functions written in
.emet count their steps and frames as any other. Each module has a path
that no file of a project can have.
-}
module Golem.Emet.Builtins
  ( builtinSources,
    divInfo,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Check (FunInfo (..))
import Golem.Emet.Core (GKey, Global (..))
import Golem.Emet.Types

-- | The built-in modules in the order they are checked: their names, paths and sources.
builtinSources :: [(Text, FilePath, Text)]
builtinSources =
  [ ("List", "<builtin>/List.emet", listSource),
    ("String", "<builtin>/String.emet", stringSource)
  ]

-- | @div@: the floor division of integers, as in the expression context.
divInfo :: (FunInfo, (GKey, Global))
divInfo =
  let key = ("<builtin>", "div")
   in (FunInfo key (Scheme [] (TF tInt (TF tInt tInt))) True, (key, GPrim "div" 2))

listSource :: Text
listSource =
  T.unlines
    [ "pub length :: List a -> Nat",
      "pub reverse :: List a -> List a",
      "pub take :: Nat -> List a -> List a",
      "pub drop :: Nat -> List a -> List a",
      "pub range :: Int -> Int -> List Int",
      "pub concat :: List (List a) -> List a",
      "pub at :: Nat -> List a -> Maybe a",
      "",
      "pub isEmpty :: List a -> Bool",
      "isEmpty [] = True",
      "isEmpty _ = False",
      "",
      "pub map :: (a -> b) -> List a -> List b",
      "map f xs = mapGo f xs []",
      "",
      "mapGo :: (a -> b) -> List a -> List b -> List b",
      "mapGo _ [] acc = reverse acc",
      "mapGo f (y : ys) acc = mapGo f ys (f y : acc)",
      "",
      "pub select :: (a -> Bool) -> List a -> List a",
      "select p xs = selectGo p xs []",
      "",
      "selectGo :: (a -> Bool) -> List a -> List a -> List a",
      "selectGo _ [] acc = reverse acc",
      "selectGo p (y : ys) acc = selectGo p ys (p y ? (y : acc) : acc)",
      "",
      "pub foldl :: (b -> a -> b) -> b -> List a -> b",
      "foldl _ z [] = z",
      "foldl f z (y : ys) = foldl f (f z y) ys",
      "",
      "pub foldr :: (a -> b -> b) -> b -> List a -> b",
      "foldr f z xs = foldrGo f z (reverse xs)",
      "",
      "foldrGo :: (a -> b -> b) -> b -> List a -> b",
      "foldrGo _ z [] = z",
      "foldrGo f z (y : ys) = foldrGo f (f y z) ys",
      "",
      "pub any :: (a -> Bool) -> List a -> Bool",
      "any _ [] = False",
      "any p (y : ys) = p y || any p ys",
      "",
      "pub all :: (a -> Bool) -> List a -> Bool",
      "all _ [] = True",
      "all p (y : ys) = p y && all p ys",
      "",
      "pub concatMap :: (a -> List b) -> List a -> List b",
      "concatMap f xs = concat (map f xs)",
      "",
      "pub zip :: List a -> List b -> List (a, b)",
      "zip xs ys = zipGo xs ys []",
      "",
      "zipGo :: List a -> List b -> List (a, b) -> List (a, b)",
      "zipGo (x : xs) (y : ys) acc = zipGo xs ys ((x, y) : acc)",
      "zipGo _ _ acc = reverse acc"
    ]

stringSource :: Text
stringSource =
  T.unlines
    [ "pub length :: String -> Nat",
      "pub chars :: String -> List Char",
      "pub fromChars :: List Char -> String",
      "pub fromChar :: Char -> String",
      "pub join :: String -> List String -> String",
      "pub split :: String -> String -> List String",
      "pub lines :: String -> List String",
      "pub trim :: String -> String",
      "pub startsWith :: String -> String -> Bool",
      "pub endsWith :: String -> String -> Bool",
      "pub contains :: String -> String -> Bool",
      "pub replace :: String -> String -> String -> String",
      "pub take :: Nat -> String -> String",
      "pub drop :: Nat -> String -> String",
      "pub fromNat :: Nat -> String",
      "pub fromInt :: Int -> String",
      "pub fromRat :: Rat -> String",
      "pub toNat :: String -> Maybe Nat",
      "pub toInt :: String -> Maybe Int",
      "",
      "pub all :: (Char -> Bool) -> String -> Bool",
      "all p s = List.all p (chars s)",
      "",
      "pub any :: (Char -> Bool) -> String -> Bool",
      "any p s = List.any p (chars s)",
      "",
      "pub map :: (Char -> Char) -> String -> String",
      "map f s = fromChars (List.map f (chars s))"
    ]
