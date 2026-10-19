{-# LANGUAGE MultiWayIf #-}

{- | The CSS that SVG figures need (golem-pdf ADR 0009): style sheets and
style attributes. Selectors are a type, @.class@, @#id@, @*@ and their
compounds (@rect.proc@), in comma-separated lists. Combinators,
pseudo-classes, attribute selectors, @!important@ and every at-rule are
unsupported; each is reported at its offset in the text.
-}
module Golem.Svg.Css
  ( Selector (..),
    Rule (..),
    CssProblem (..),
    parseStylesheet,
    parseDeclarations,
    specificity,
    selects,
  )
where

import Data.Char (isAlphaNum, isSpace)
import Data.Maybe (isJust, isNothing)
import Data.Text (Text)
import Data.Text qualified as T

-- | A compound selector: a type (none for @*@ or no type), classes, an id.
data Selector = Selector
  { selType :: !(Maybe Text),
    selClasses :: ![Text],
    selId :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

data Rule = Rule
  { ruSelectors :: ![Selector],
    ruDeclarations :: ![(Text, Text)]
  }
  deriving stock (Eq, Show)

-- | Something unsupported: its offset in the text, its name, and whether it is about text (@font-face).
data CssProblem = CssProblem
  { cpOffset :: !Int,
    cpName :: !Text,
    cpText :: !Bool
  }
  deriving stock (Eq, Show)

-- | (ids, classes, types).
specificity :: Selector -> (Int, Int, Int)
specificity s = (maybe 0 (const 1) (selId s), length (selClasses s), maybe 0 (const 1) (selType s))

-- | Whether a selector selects an element of a name, classes and an id.
selects :: Selector -> Text -> [Text] -> Maybe Text -> Bool
selects s name classes ident =
  maybe True (== name) (selType s)
    && all (`elem` classes) (selClasses s)
    && maybe True ((== ident) . Just) (selId s)

-- | Comments replaced by spaces of the same length, so that offsets hold.
stripComments :: Text -> Text
stripComments = T.concat . go
  where
    -- the pieces, joined once: joining at each comment is quadratic (security audit 2026-10-18, C9)
    go t = case T.breakOn "/*" t of
      (before, after)
        | T.null after -> [t]
        | otherwise ->
            let (comment, rest) = T.breakOn "*/" after
                n = T.length comment + min 2 (T.length rest)
             in before : T.replicate n " " : go (T.drop 2 rest)

-- | The rules of a style sheet, and what is unsupported in it.
parseStylesheet :: Text -> ([Rule], [CssProblem])
parseStylesheet src = go 0 (stripComments src) [] []
  where
    go off t rules probs =
      let lead = T.length (T.takeWhile isSpace t)
          t' = T.drop lead t
          off' = off + lead
       in case T.uncons t' of
            Nothing -> (reverse rules, reverse probs)
            Just ('@', _) ->
              let name = "@" <> T.takeWhile isIdent (T.drop 1 t')
                  skipped = atRuleLength t'
               in go (off' + skipped) (T.drop skipped t') rules (CssProblem off' name (name == "@font-face") : probs)
            _ ->
              let (prelude, rest) = T.breakOn "{" t'
                  (body, after) = T.breakOn "}" (T.drop 1 rest)
                  bodyOff = off' + T.length prelude + 1
                  used = T.length prelude + 1 + T.length body + min 1 (T.length after)
                  (sels, selProbs) = selectorList off' prelude
                  (decls, declProbs) = declarationsAt bodyOff body
               in if T.null rest
                    then (reverse rules, reverse (CssProblem off' "CSS の規則" False : probs))
                    else go (off' + used) (T.drop used t') (Rule sels decls : rules) (reverse (selProbs <> declProbs) <> probs)
    -- an at-rule: up to its ; or its balanced block
    atRuleLength t =
      let (before, rest) = T.break (\c -> c == ';' || c == '{') t
       in case T.uncons rest of
            Just (';', _) -> T.length before + 1
            Just ('{', _) -> T.length before + balanced 0 (T.unpack rest)
            _ -> T.length t
    balanced :: Int -> String -> Int
    balanced depth = \case
      [] -> 0
      '{' : r -> 1 + balanced (depth + 1) r
      '}' : r -> if depth == 1 then 1 else 1 + balanced (depth - 1) r
      _ : r -> 1 + balanced depth r

isIdent :: Char -> Bool
isIdent c = isAlphaNum c || c == '-' || c == '_' || c > '\x7F'

-- | A comma-separated list of compound selectors.
selectorList :: Int -> Text -> ([Selector], [CssProblem])
selectorList off prelude =
  let parts = scanParts off (T.splitOn "," prelude)
      parsed = [(o, T.strip p, compound (T.strip p)) | (o, p) <- parts]
   in ([s | (_, _, Just s) <- parsed], [CssProblem o p' False | (o, p', Nothing) <- parsed])
  where
    scanParts o = \case
      [] -> []
      p : ps -> (o + T.length (T.takeWhile isSpace p), p) : scanParts (o + T.length p + 1) ps
    compound t
      | T.null t = Nothing
      | otherwise = go (Selector Nothing [] Nothing) t
    go s t = case T.uncons t of
      Nothing -> Just s
      Just ('*', r) | isNothing (selType s) -> go s r
      Just ('.', r) -> let (n, r') = T.span isIdent r in if T.null n then Nothing else go s {selClasses = selClasses s <> [n]} r'
      Just ('#', r) -> let (n, r') = T.span isIdent r in if T.null n || isJust (selId s) then Nothing else go s {selId = Just n} r'
      Just (c, _)
        | isIdent c && isNothing (selType s) && null (selClasses s) && isNothing (selId s) ->
            let (n, r') = T.span isIdent t in go s {selType = Just n} r'
      _ -> Nothing

-- | The declarations of a style attribute.
parseDeclarations :: Text -> ([(Text, Text)], [CssProblem])
parseDeclarations = declarationsAt 0 . stripComments

declarationsAt :: Int -> Text -> ([(Text, Text)], [CssProblem])
declarationsAt off body =
  let parts = scan off (T.splitOn ";" body)
      one (o, p) =
        let (name, rest) = T.breakOn ":" p
            prop = T.toLower (T.strip name)
            value = T.strip (T.drop 1 rest)
         in if
              | T.null (T.strip p) -> ([], [])
              | T.null rest || T.null prop -> ([], [CssProblem o (T.strip p) False])
              | "!important" `T.isInfixOf` T.toLower value -> ([], [CssProblem o "!important" False])
              | otherwise -> ([(prop, value)], [])
      results = map one parts
   in (concatMap fst results, concatMap snd results)
  where
    scan o = \case
      [] -> []
      p : ps -> (o + T.length (T.takeWhile isSpace p), p) : scan (o + T.length p + 1) ps
