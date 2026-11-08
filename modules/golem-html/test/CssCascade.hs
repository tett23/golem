{- | A small evaluator of the cascade of style.css for the tests of the
spaces of paragraph styles (docs/adr/0217). It reads only the selectors
Golem writes: type selectors, classes, the presence of an attribute,
:not() of a simple selector, the descendant and the next-sibling
combinators, and the pseudo-elements ::before and ::after, which match no
element. A rule with margin-block-start (or margin-block) whose selector is
outside that range is an error, not a rule that is skipped.

For each element it picks the margin-block-start that wins: the greatest
specificity, then the last in the order of the style sheet.
-}
module CssCascade
  ( Elem (..),
    Page (..),
    Winner (..),
    Specificity,
    specificity,
    parseSelector,
    winningMarginStart,
    winningMarginStarts,
    pageOf,
  )
where

import Data.Char (isAlphaNum)
import Data.List (sortOn)
import Data.Maybe (listToMaybe)
import Data.Ord (Down (..))
import Data.Text (Text)
import Data.Text qualified as T

-- | An element: its name and its classes.
data Elem = Elem {elName :: Text, elClasses :: [Text]}
  deriving (Eq, Show)

-- | A page: the classes of body and the elements under body, in order.
data Page = Page {pgBody :: [Text], pgBlocks :: [Elem]}
  deriving (Eq, Show)

-- | The declaration that wins: its value and the selector of its rule.
data Winner = Winner {wValue :: Text, wSelector :: Text}
  deriving (Eq, Show)

-- | (ids, classes and attributes and pseudo-classes, types)
type Specificity = (Int, Int, Int)

data Simple
  = SType Text
  | SAny
  | SClass Text
  | SAttr Text
  | SNot Simple
  | SPseudoElement Text
  deriving (Eq, Show)

data Combinator = Descendant | NextSibling
  deriving (Eq, Show)

-- | A complex selector, the rightmost compound first, each with the combinator to its left.
data Selector = Selector [Simple] [(Combinator, [Simple])]
  deriving (Eq, Show)

simpleSpec :: Simple -> Specificity
simpleSpec = \case
  SType _ -> (0, 0, 1)
  SAny -> (0, 0, 0)
  SClass _ -> (0, 1, 0)
  SAttr _ -> (0, 1, 0)
  -- the argument of :not() counts, :not() itself does not (Selectors Level 3)
  SNot s -> simpleSpec s
  SPseudoElement _ -> (0, 0, 1)

plus :: Specificity -> Specificity -> Specificity
plus (a, b, c) (x, y, z) = (a + x, b + y, c + z)

specificity :: Selector -> Specificity
specificity (Selector c rest) = foldr (plus . simpleSpec) (0, 0, 0) (c <> concatMap snd rest)

-- | Parses one complex selector, or says why it is outside the range.
parseSelector :: Text -> Either String Selector
parseSelector t = do
  -- from the left, each compound with the combinator to its left
  compounds <- loop Descendant (T.words t)
  case reverse compounds of
    [] -> Left ("empty selector: " <> T.unpack t)
    ((k, c) : older) -> Right (Selector c (zip (k : map fst older) (map snd older)))
  where
    loop _ [] = Right []
    loop _ ("+" : rest) = loop NextSibling rest
    loop k (w : rest) = do
      c <- compound w
      ((k, c) :) <$> loop Descendant rest

compound :: Text -> Either String [Simple]
compound w0 = loop w0
  where
    loop w
      | T.null w = Right []
      | "::" `T.isPrefixOf` w =
          let (n, rest) = T.span identChar (T.drop 2 w)
           in if n `elem` ["before", "after"] then (SPseudoElement n :) <$> loop rest else bad
      | ":not(" `T.isPrefixOf` w =
          let (inner, rest) = T.breakOn ")" (T.drop 5 w)
           in case compound inner of
                Right [s] | notNested s -> (SNot s :) <$> loop (T.drop 1 rest)
                _ -> bad
      | "." `T.isPrefixOf` w =
          let (n, rest) = T.span identChar (T.drop 1 w)
           in if T.null n then bad else (SClass n :) <$> loop rest
      | "[" `T.isPrefixOf` w =
          let (n, rest) = T.span identChar (T.drop 1 w)
           in if T.null n || not ("]" `T.isPrefixOf` rest) then bad else (SAttr n :) <$> loop (T.drop 1 rest)
      | "*" `T.isPrefixOf` w && w == w0 = (SAny :) <$> loop (T.drop 1 w)
      | w == w0,
        Just _ <- T.uncons w,
        identChar (T.head w) =
          let (n, rest) = T.span identChar w
           in (SType n :) <$> loop rest
      | otherwise = bad
    bad = Left ("selector outside the range of the evaluator: " <> T.unpack w0)
    notNested = \case
      SNot _ -> False
      SPseudoElement _ -> False
      _ -> True

identChar :: Char -> Bool
identChar c = isAlphaNum c || c == '-' || c == '_'

-- | An element in its place: itself, its previous sibling, its parent.
data Ctx = Ctx {cElem :: Elem, cPrev :: Maybe Ctx, cParent :: Maybe Ctx}

matchSimple :: Elem -> Simple -> Bool
matchSimple e = \case
  SType n -> elName e == n
  SAny -> True
  SClass c -> c `elem` elClasses e
  -- the only attribute Golem's selectors test is class
  SAttr "class" -> not (null (elClasses e))
  SAttr _ -> False
  SNot s -> not (matchSimple e s)
  SPseudoElement _ -> False

matches :: Selector -> Ctx -> Bool
matches (Selector c rest) ctx = all (matchSimple (cElem ctx)) c && leftOf rest ctx
  where
    leftOf [] _ = True
    leftOf ((NextSibling, c') : more) x = case cPrev x of
      Just p -> all (matchSimple (cElem p)) c' && leftOf more p
      Nothing -> False
    leftOf ((Descendant, c') : more) x = any (\a -> all (matchSimple (cElem a)) c' && leftOf more a) (ancestors x)
    ancestors x = case cParent x of
      Just p -> p : ancestors p
      Nothing -> []

-- | The rules of a style sheet, one a line, as (selector list, declarations).
rulesOf :: Text -> [(Text, [(Text, Text)])]
rulesOf css =
  [ (T.strip sel, decls)
  | l <- T.lines css,
    not ("@" `T.isPrefixOf` T.strip l),
    let (sel, body) = T.breakOn "{" l,
    not (T.null body),
    let decls = [(T.strip k, T.strip (T.drop 1 v)) | d <- T.splitOn ";" (T.dropEnd 1 (T.strip (T.drop 1 body))), let (k, v) = T.breakOn ":" d, not (T.null (T.strip k))]
  ]

-- | The value of margin-block-start a declaration sets, if any.
startOf :: (Text, Text) -> Maybe Text
startOf (k, v)
  | k == "margin-block-start" = Just v
  | k == "margin-block" = listToMaybe (T.words v)
  | otherwise = Nothing

{- | The declaration of margin-block-start that wins on each element of the
page, Nothing where no rule of the style sheet sets it. An at-rule that sets
it, or a selector outside the range, is an error.
-}
winningMarginStarts :: Text -> Page -> Either String [Maybe Winner]
winningMarginStarts css page = do
  checkAtRules
  candidates <-
    concat
      <$> sequence
        [ do
            sels <- traverse (\s -> (,) s <$> parseSelector s) (T.splitOn ", " sel)
            pure [(t, sp, (ri, di), v) | (t, sp) <- sels, (di, d) <- zip [0 :: Int ..] decls, Just v <- [startOf d]]
        | (ri, (sel, decls)) <- zip [0 :: Int ..] (rulesOf css),
          any ((/= Nothing) . startOf) decls
        ]
  pure
    [ case sortOn (\(_, sp, order, _) -> Down (specificity sp, order)) [c | c@(_, sp, _, _) <- candidates, matches sp ctx] of
        ((t, _, _, v) : _) -> Just (Winner v t)
        [] -> Nothing
    | ctx <- contexts
    ]
  where
    checkAtRules = case [l | l <- T.lines css, "@" `T.isPrefixOf` T.strip l, "margin-block" `T.isInfixOf` l] of
      [] -> Right ()
      (l : _) -> Left ("an at-rule sets margin-block: " <> T.unpack l)
    body = Ctx (Elem "body" (pgBody page)) Nothing (Just (Ctx (Elem "html" []) Nothing Nothing))
    contexts = snd (foldl step (Nothing, []) (pgBlocks page))
    step (prev, acc) e = let c = Ctx e prev (Just body) in (Just c, acc <> [c])

-- | The winning margin-block-start of one element of the page, by its index.
winningMarginStart :: Text -> Page -> Int -> Either String (Maybe Winner)
winningMarginStart css page i = do
  ws <- winningMarginStarts css page
  case drop i ws of
    (w : _) -> Right w
    [] -> Left ("no element " <> show i)

{- | The page of an XHTML file: the classes of body and the elements right
under it. The writer's XHTML is well-formed, so counting the tags is enough.
-}
pageOf :: Text -> Page
pageOf x =
  let (_, afterBody) = T.breakOn "<body" x
      (bodyTag, rest) = T.breakOn ">" afterBody
   in Page (classesIn bodyTag) (children 0 (T.drop 1 rest))
  where
    children :: Int -> Text -> [Elem]
    children depth t = case T.breakOn "<" t of
      (_, r) | T.null r -> []
      (_, r) ->
        let (tag, after) = T.breakOn ">" (T.drop 1 r)
            more = T.drop 1 after
         in if "/" `T.isPrefixOf` tag
              then if depth == 0 then [] else children (depth - 1) more
              else
                if "!" `T.isPrefixOf` tag || "?" `T.isPrefixOf` tag
                  then children depth more
                  else
                    let name = T.takeWhile identChar tag
                        selfClosing = "/" `T.isSuffixOf` tag
                        here = [Elem name (classesIn tag) | depth == 0]
                     in here <> children (if selfClosing then depth else depth + 1) more
    classesIn tag = case T.breakOn "class=\"" tag of
      (_, r) | T.null r -> []
      (_, r) -> T.words (T.takeWhile (/= '"') (T.drop 7 r))
