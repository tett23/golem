{- | The check of exhaustiveness and of alternatives never chosen
(docs/adr/0160), by the usefulness of a vector of patterns against a
matrix of them (Maranget, "Warnings for pattern matching", 2007).

Literals of numbers, characters and strings have no complete set of
constructors, so a column of literals is covered by a wildcard only.
@(x : xs)@ is the constructor @::@ and @[]@ the other one of lists; a list
pattern @[a, b]@ is @::@ twice before @[]@. A tuple is the one constructor
@(,)@ of its type.
-}
module Golem.Emet.Exhaust
  ( XPat (..),
    ConSignature,
    useful,
    showWitness,
  )
where

import Data.List (find, nub)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T

data XPat
  = XWild
  | XCon !Text ![XPat]
  | -- | a literal of a number or a string, by its text
    XLit !Text
  deriving stock (Eq, Show)

-- | The constructors and arities of the type of a constructor.
type ConSignature = Text -> Maybe [(Text, Int)]

{- | A vector of values that the vector of patterns matches and no row of
the matrix does; Nothing when every value it matches is matched by a row.
-}
useful :: ConSignature -> [[XPat]] -> [XPat] -> Maybe [XPat]
useful _ rows [] = if null rows then Just [] else Nothing
useful sig rows (q : qs) = case q of
  XCon c args ->
    let n = length args
     in rebuild c n <$> useful sig (specialize c n rows) (args <> qs)
  XLit k -> (XLit k :) <$> useful sig [rest | (h : rest) <- rows, h == XLit k || h == XWild] qs
  XWild ->
    let heads = nub [(c, length as) | (XCon c as : _) <- rows]
        complete = case heads of
          (c, _) : _ | Just cs <- sig c, all (\k -> isJust (find ((== fst k) . fst) heads)) cs -> Just cs
          _ -> Nothing
     in case complete of
          Just cs ->
            let try (c, n) = rebuild c n <$> useful sig (specialize c n rows) (replicate n XWild <> qs)
             in firstJust (map try cs)
          Nothing ->
            let defaults = [rest | (XWild : rest) <- rows]
             in (missing heads :) <$> useful sig defaults qs
  where
    missing heads = case heads of
      (c, _) : _ | Just cs <- sig c, Just (m, n) <- find (\(k, _) -> k `notElem` map fst heads) cs -> XCon m (replicate n XWild)
      _ -> XWild

specialize :: Text -> Int -> [[XPat]] -> [[XPat]]
specialize c n rows =
  [ args <> rest
  | (h : rest) <- rows,
    Just args <- [match h]
  ]
  where
    match = \case
      XCon c' as | c' == c -> Just as
      XWild -> Just (replicate n XWild)
      _ -> Nothing

rebuild :: Text -> Int -> [XPat] -> [XPat]
rebuild c n ps = XCon c (take n ps) : drop n ps

firstJust :: [Maybe a] -> Maybe a
firstJust = \case
  [] -> Nothing
  Just x : _ -> Just x
  Nothing : xs -> firstJust xs

-- | A witness as a pattern of .emet: @Just _@, @[]@, @[_, _]@, @(_ : _)@, @(_, _)@.
showWitness :: XPat -> Text
showWitness = go False
  where
    go p = \case
      XWild -> "_"
      XLit t -> t
      x@(XCon "::" _) -> list [] x
      XCon "[]" [] -> "[]"
      XCon c as | "(,)" `T.isPrefixOf` c -> "(" <> T.intercalate ", " (map (go False) as) <> ")"
      XCon c [] -> c
      XCon c as -> (if p then \t -> "(" <> t <> ")" else id) (T.unwords (c : map (go True) as))
    list acc = \case
      XCon "::" [h, t] -> list (go False h : acc) t
      XCon "[]" [] -> "[" <> T.intercalate ", " (reverse acc) <> "]"
      t -> "(" <> T.intercalate " : " (reverse (go True t : acc)) <> ")"
