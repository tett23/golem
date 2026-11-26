-- | Relate merged output text to the original AST without evaluating expressions again.
module Golem.Driver.PageMap.Alignment (sourceOffset) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.IntSet qualified as IS
import Data.List (sortOn)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Vector qualified as V
import Data.Vector.Mutable qualified as MV
import Golem.Parser.AST qualified as A
import Golem.Syntax

-- | Nothing denotes generated text; a known part has its exact output text.
data Part = Part !SrcSpan !(Maybe Text)

-- | Resolve a source position only when every consistent alignment agrees.
sourceOffset :: A.File -> Text -> SrcSpan -> Text -> Int -> Maybe Int
sourceOffset ast source span' output offset = do
  let parts = maximal (sortOn order (mapMaybe clipped (astParts ast)))
      (before, hereAndAfter) = break (contains offset) parts
      starts = foldl' forward (IS.singleton 0) before
  (here : after) <- pure hereAndAfter
  let ends = foldr backward (IS.singleton outputLength) after
      candidates = case here of
        Part _ Nothing -> case fst <$> IS.maxView ends of
          Nothing -> IS.empty
          Just end -> IS.filter (<= end) starts
        Part _ (Just known) -> matching known (IS.intersection starts (IS.map (subtract (T.length known)) ends))
  start <- case IS.toList candidates of [one] -> Just one; _ -> Nothing
  case here of
    Part _ Nothing -> pure start
    Part sp (Just known)
      | T.null known -> Nothing
      | otherwise ->
          let raw = slice sp
              prefix = BS.take (offset - spanStart sp) (TE.encodeUtf8 raw)
              local = if raw == known then T.length (TE.decodeUtf8 prefix) else 0
           in pure (start + local)
  where
    encoded = TE.encodeUtf8 source
    outputLength = T.length output
    outputVector = V.fromList (T.unpack output)
    slice sp = TE.decodeUtf8 (BS.take (spanEnd sp - spanStart sp) (BS.drop (spanStart sp) encoded))
    order (Part sp _) = (spanStart sp, negate (spanEnd sp))
    contains off (Part sp _) = spanStart sp <= off && off < spanEnd sp
    clipped (Part sp known)
      | spanFile sp /= spanFile span' || spanEnd sp <= spanStart span' || spanStart sp >= spanEnd span' = Nothing
      | Just text <- known,
        text == slice sp =
          let narrowed = mkSpan (spanFile sp) (max (spanStart sp) (spanStart span')) (min (spanEnd sp) (spanEnd span'))
           in Just (Part narrowed (Just (slice narrowed)))
      | spanStart span' <= spanStart sp && spanEnd sp <= spanEnd span' = Just (Part sp known)
      | otherwise = Nothing
    maximal = go (-1)
      where
        go _ [] = []
        go end (p@(Part sp _) : ps)
          | spanStart sp < end = go end ps
          | otherwise = p : go (spanEnd sp) ps
    occurrences text
      | T.null text = IS.fromDistinctAscList [0 .. outputLength]
      | otherwise = matchStarts outputVector (V.fromList (T.unpack text))
    matching known candidates
      | T.null known = candidates
      | IS.size candidates <= 4 = IS.filter (matches known) candidates
      | otherwise = IS.intersection candidates (occurrences known)
    matches known start =
      let chars = V.fromList (T.unpack known)
          size = V.length chars
       in start >= 0 && start + size <= outputLength && V.and (V.imap (\i c -> outputVector V.! (start + i) == c) chars)
    forward states (Part _ Nothing) = case fst <$> IS.minView states of
      Nothing -> IS.empty
      Just start
        | IS.size states == outputLength - start + 1 -> states
        | otherwise -> IS.fromDistinctAscList [start .. outputLength]
    forward states (Part _ (Just known)) = IS.map (+ T.length known) (matching known states)
    backward (Part _ Nothing) states = case fst <$> IS.maxView states of
      Nothing -> IS.empty
      Just end
        | IS.size states == end + 1 -> states
        | otherwise -> IS.fromDistinctAscList [0 .. end]
    backward (Part _ (Just known)) states = matching known (IS.map (subtract (T.length known)) states)

-- | KMP, including overlapping matches, in linear time in the two strings.
matchStarts :: V.Vector Char -> V.Vector Char -> IS.IntSet
matchStarts text pattern' = IS.fromDistinctAscList (go 0 0)
  where
    size = V.length pattern'
    prefix = V.create $ do
      table <- MV.replicate size 0
      let fallback i j
            | j > 0 && pattern' V.! i /= pattern' V.! j = MV.read table (j - 1) >>= fallback i
            | otherwise = pure j
      forM_ [1 .. size - 1] $ \i -> do
        previous <- MV.read table (i - 1)
        j <- fallback i previous
        MV.write table i (if pattern' V.! i == pattern' V.! j then j + 1 else j)
      pure table
    go i j
      | i == V.length text = []
      | text V.! i == pattern' V.! j =
          if j + 1 == size then (i - size + 1) : go (i + 1) (prefix V.! (size - 1)) else go (i + 1) (j + 1)
      | j > 0 = go i (prefix V.! (j - 1))
      | otherwise = go (i + 1) 0

astParts :: A.File -> [Part]
astParts (A.File _ blocks) = concatMap block blocks
  where
    block (A.Located _ body) = case body of
      A.Paragraph xs -> concatMap inline xs
      A.Heading _ xs -> concatMap inline xs
      A.BulletList items -> concatMap (concatMap block) items
      A.OrderedList items -> concatMap (concatMap block) items
      A.DefList groups -> concat [concatMap (concatMap inline) (A.dgTerms group) <> concatMap (concatMap block) (A.dgDefs group) | group <- groups]
      A.Table _ header rows -> concatMap (concatMap inline) (header <> concat rows)
      A.BlockCommand _ _ bs -> concatMap block bs
      A.Attributed bs body' -> concatMap block bs <> maybe [] block body'
      A.Fenced bs -> concatMap block bs
      _ -> []
    inline (A.Located sp body) = case body of
      A.Text text -> [Part sp (Just text)]
      A.Escaped c -> [Part sp (Just (T.singleton c))]
      A.SoftBreak -> [Part sp (Just "")]
      A.Expr _ -> [Part sp Nothing]
      A.NumberShorthand _ -> [Part sp Nothing]
      A.Command _ _ slots -> Part sp Nothing : concatMap (concatMap inline) slots
      A.ProofComment _ -> [Part sp (Just "")]
      _ -> []
