{- | The built-in modules of .gmx (docs/adr/0148): @List@ and @String@,
used without import. Their functions are written in .gmx on top of
primitives ('Golem.Gmx.Prim'), so that the functions they call count
their steps and frames as any other. Each has a path that no file of a
project can have.
-}
module Golem.Gmx.Builtins
  ( builtinSources,
    divInfo,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Gmx.Check (FunInfo (..))
import Golem.Gmx.Core (GKey, Global (..))
import Golem.Gmx.Types

-- | The built-in modules in the order they are checked: their names, paths and sources.
builtinSources :: [(Text, FilePath, Text)]
builtinSources =
  [ ("List", "<builtin>/List.gmx", listSource),
    ("String", "<builtin>/String.gmx", stringSource)
  ]

-- | @div@: the floor division of integers, as in the expression context.
divInfo :: (FunInfo, (GKey, Global))
divInfo =
  let key = ("<builtin>", "div")
   in (FunInfo key (Scheme [] (TF tInt (TF tInt tInt))) True, (key, GPrim "div" 2))

listSource :: Text
listSource =
  T.unlines
    [ "-- the head and the rest of a list, the value of uncons",
      "pub data Cons a = Cons a (List a);",
      "",
      "pub length :: List a -> Nat;",
      "pub reverse :: List a -> List a;",
      "pub cons :: a -> List a -> List a;",
      "pub uncons :: List a -> Maybe (Cons a);",
      "pub take :: Nat -> List a -> List a;",
      "pub drop :: Nat -> List a -> List a;",
      "pub range :: Int -> Int -> List Int;",
      "pub concat :: List (List a) -> List a;",
      "pub at :: Nat -> List a -> Maybe a;",
      "",
      "pub isEmpty :: List a -> Bool;",
      "isEmpty [] = True;",
      "isEmpty _ = False;",
      "",
      "pub map :: (a -> b) -> List a -> List b;",
      "map f xs = mapGo f xs [];",
      "",
      "mapGo :: (a -> b) -> List a -> List b -> List b;",
      "mapGo f xs acc = case uncons xs of {",
      "  Nothing -> reverse acc;",
      "  Just (Cons y ys) -> mapGo f ys (cons (f y) acc)",
      "};",
      "",
      "pub filter :: (a -> Bool) -> List a -> List a;",
      "filter p xs = filterGo p xs [];",
      "",
      "filterGo :: (a -> Bool) -> List a -> List a -> List a;",
      "filterGo p xs acc = case uncons xs of {",
      "  Nothing -> reverse acc;",
      "  Just (Cons y ys) -> filterGo p ys (p y ? cons y acc : acc)",
      "};",
      "",
      "pub foldl :: (b -> a -> b) -> b -> List a -> b;",
      "foldl f z xs = case uncons xs of {",
      "  Nothing -> z;",
      "  Just (Cons y ys) -> foldl f (f z y) ys",
      "};",
      "",
      "pub foldr :: (a -> b -> b) -> b -> List a -> b;",
      "foldr f z xs = foldrGo f z (reverse xs);",
      "",
      "foldrGo :: (a -> b -> b) -> b -> List a -> b;",
      "foldrGo f z xs = case uncons xs of {",
      "  Nothing -> z;",
      "  Just (Cons y ys) -> foldrGo f (f y z) ys",
      "};",
      "",
      "pub any :: (a -> Bool) -> List a -> Bool;",
      "any p xs = case uncons xs of {",
      "  Nothing -> False;",
      "  Just (Cons y ys) -> p y || any p ys",
      "};",
      "",
      "pub all :: (a -> Bool) -> List a -> Bool;",
      "all p xs = case uncons xs of {",
      "  Nothing -> True;",
      "  Just (Cons y ys) -> p y && all p ys",
      "};",
      "",
      "pub concatMap :: (a -> List b) -> List a -> List b;",
      "concatMap f xs = concat (map f xs);"
    ]

stringSource :: Text
stringSource =
  T.unlines
    [ "pub length :: String -> Nat;",
      "pub chars :: String -> List String;",
      "pub fromChars :: List String -> String;",
      "pub join :: String -> List String -> String;",
      "pub split :: String -> String -> List String;",
      "pub lines :: String -> List String;",
      "pub trim :: String -> String;",
      "pub startsWith :: String -> String -> Bool;",
      "pub endsWith :: String -> String -> Bool;",
      "pub contains :: String -> String -> Bool;",
      "pub replace :: String -> String -> String -> String;",
      "pub take :: Nat -> String -> String;",
      "pub drop :: Nat -> String -> String;",
      "pub fromNat :: Nat -> String;",
      "pub fromInt :: Int -> String;",
      "pub fromRat :: Rat -> String;",
      "pub toNat :: String -> Maybe Nat;",
      "pub toInt :: String -> Maybe Int;",
      "",
      "pub all :: (String -> Bool) -> String -> Bool;",
      "all p s = List.all p (chars s);",
      "",
      "pub any :: (String -> Bool) -> String -> Bool;",
      "any p s = List.any p (chars s);",
      "",
      "pub map :: (String -> String) -> String -> String;",
      "map f s = fromChars (List.map f (chars s));"
    ]
