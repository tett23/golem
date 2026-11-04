{- | fmt of .gmx (docs/adr/0148). Indentation has no meaning in .gmx, so
fmt decides it: two spaces a level, a line after @{@ and before @}@ of
@case@ and @where@, the guards on lines of their own a level below the
name of the equation. The line breaks the writer chose stay; lines are
not wrapped. Runs of blank lines become one. A BOM is removed and CR
becomes LF (G01002, G01003).

fmt works on the tokens of the lossless syntax tree, so comments stay
where they are.
-}
module Golem.Gmx.Fmt
  ( formatGmx,
  )
where

import Data.List (sort)
import Data.Maybe (fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Gmx.Generated qualified as G
import Golem.Gmx.Parse (parseModule)
import Golem.Syntax
import Peg.Runtime.Syntax (syntaxTokens, tokenKind, tokenText)

data Tok = Tok !TokKind !Text

data TokKind = KWs | KNl | KComment | KOpen | KClose | KGuard | KSemi | KArrow | KReq | KOther
  deriving stock (Eq)

-- | The formatted text, or the errors that keep the file from being read.
formatGmx :: Text -> Either [Diagnostic] Text
formatGmx raw = do
  let src = T.replace "\r" "\n" (T.replace "\r\n" "\n" (fromMaybe raw (T.stripPrefix "\xFEFF" raw)))
  _ <- parseModule (FileId 0) src
  tree <- either (const (Left [])) Right (G.parseSyntax src)
  let toks = [Tok (kindOf (G.nameOfSyntaxKind (tokenKind t))) (tokenText t) | t <- syntaxTokens tree]
  pure (render (layout (splitLines (sortRequirements toks))))

kindOf :: Text -> TokKind
kindOf = \case
  "Ws" -> KWs
  "Nl" -> KNl
  "Comment" -> KComment
  "OpenBlock" -> KOpen
  "CloseBlock" -> KClose
  "GuardBar" -> KGuard
  "Semi" -> KSemi
  "FatArrow" -> KArrow
  "ReqTok" -> KReq
  _ -> KOther

{- | The names of the requirements of each signature in the order of the
names (docs/adr/0149); the commas, white space and comments between them
stay where they are.
-}
sortRequirements :: [Tok] -> [Tok]
sortRequirements = \case
  [] -> []
  t@(Tok KArrow _) : rest ->
    let (run, after) = span (\(Tok k _) -> k `elem` [KReq, KWs, KNl, KComment, KOther] && not (isEnd k)) rest
        isEnd k = k == KSemi
        names = sort [x | Tok KReq x <- run]
        refill ns = \case
          Tok KReq _ : more | n : ns' <- ns -> Tok KReq n : refill ns' more
          other : more -> other : refill ns more
          [] -> []
     in t : refill names run <> sortRequirements after
  t : rest -> t : sortRequirements rest

{- | The lines of the tokens, without their newlines: the breaks of the
writer, and the breaks fmt adds after @{@, before @}@ and before a guard.
-}
splitLines :: [Tok] -> [[Tok]]
splitLines = finish . foldl' step ([], [], False)
  where
    -- (done lines reversed, current line reversed, break before the next code)
    step (done, cur, brk) t@(Tok k _) = case k of
      KNl -> (reverse cur : done, [], False)
      KWs -> (done, t : cur, brk)
      KComment -> (done, t : cur, brk)
      _ ->
        let breakHere = (brk || k == KClose || k == KGuard) && hasCode cur
            (done', cur') = if breakHere then (reverse cur : done, []) else (done, cur)
         in (done', t : cur', k == KOpen)
    finish (done, cur, _) = reverse (reverse cur : done)
    hasCode = any (\(Tok k _) -> k /= KWs)

{- | Each line with its indentation: an item of a block (a declaration, an
alternative of case, a binding of where) starts at the level of the
block, and its other lines are a level below; the contents of @{ }@ are a
level below the line of @{@, and @}@ is at that line's level.
-}
layout :: [[Tok]] -> [Maybe (Int, [Tok])]
layout = go [] True
  where
    go _ _ [] = []
    go stack itemStart (l : ls) =
      let code = dropWhile isWs l
       in case code of
            [] -> Nothing : go stack itemStart ls
            Tok first _ : _ ->
              let base = case stack of
                    o : _ -> o + 1
                    [] -> 0
                  indent
                    | first == KClose = case stack of
                        o : _ -> o
                        [] -> 0
                    | isComment code = if itemStart then base else base + 1
                    | itemStart = base
                    | otherwise = base + 1
                  (stack', itemStart') = foldl' (advance indent) (stack, itemStart) code
               in Just (indent, code) : go stack' itemStart' ls
    advance indent (stack, itemStart) (Tok k _) = case k of
      KOpen -> (indent : stack, True)
      KClose -> (drop 1 stack, False)
      KSemi -> (stack, True)
      KWs -> (stack, itemStart)
      KComment -> (stack, itemStart)
      _ -> (stack, False)
    isWs (Tok k _) = k == KWs
    isComment = all (\(Tok k _) -> k == KWs || k == KComment)

-- | The text: runs of blank lines as one, none at the start or the end.
render :: [Maybe (Int, [Tok])] -> Text
render ls =
  let texts = squeeze (map line ls)
      trimmed = reverse (dropWhile isNothing (reverse (dropWhile isNothing texts)))
   in T.unlines (map (fromMaybe "") trimmed)
  where
    line = fmap (\(n, toks) -> T.replicate (2 * n) " " <> T.stripEnd (T.concat [t | Tok _ t <- toks]))
    squeeze = \case
      Nothing : rest@(Nothing : _) -> squeeze rest
      x : rest -> x : squeeze rest
      [] -> []
