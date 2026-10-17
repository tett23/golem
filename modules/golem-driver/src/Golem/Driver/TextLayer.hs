{- | The text layer of the PDF (golem-driver ADR 0030): the ToUnicode
entries of the glyphs drawn and the clusters that need ActualText. Each
glyph stands for its whole cluster; of a cluster of several glyphs, the
first one has the text.
-}
module Golem.Driver.TextLayer
  ( ClusterPart (..),
    toUnicodeOf,
    actualTextOf,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T

-- | Which glyph of its cluster a glyph is, for ToUnicode (golem-driver ADR 0030).
data ClusterPart
  = -- | the only glyph of its cluster: a glyph of one character or a ligature
    ClusterWhole
  | -- | the first glyph, in glyph order, of a cluster of several glyphs
    ClusterLead
  | -- | the second and later glyphs of a cluster of several glyphs
    ClusterRest
  deriving stock (Eq, Ord, Show)

{- | The ToUnicode entry of each glyph from the glyphs drawn, in order, with
their texts and parts: the glyphs of the rest of a cluster have none; a
whole cluster wins over the first glyph of a cluster, then the first
drawn; glyph 0 and empty texts are left out.
-}
toUnicodeOf :: [(Int, Text, ClusterPart)] -> [(Int, Text)]
toUnicodeOf drawn =
  Map.toList
    ( snd
        <$> foldl'
          (\m (g, t, part) -> Map.insertWith keep g (part, t) m)
          Map.empty
          [(g, t, part) | (g, t, part) <- drawn, part /= ClusterRest, g /= 0, not (T.null t)]
    )
  where
    -- the new candidate wins only over a worse part
    keep new@(newPart, _) old@(oldPart, _) = if newPart < oldPart then new else old

{- | The glyphs drawn, in order, cut into the occurrences of their clusters
(a whole cluster, or a first glyph and the rest of its cluster), each with
its text when the ToUnicode entries of the font do not give it back.
-}
actualTextOf :: Map Int Text -> [(Int, Text, ClusterPart)] -> [([Int], Maybe Text)]
actualTextOf entries = map judge . occurrences
  where
    occurrences = \case
      [] -> []
      g@(_, _, ClusterLead) : rest ->
        let (more, rest') = span (\(_, _, part) -> part == ClusterRest) rest
         in (g : more) : occurrences rest'
      g : rest -> [g] : occurrences rest
    judge gs =
      let text = case gs of
            (_, t, _) : _ -> t
            [] -> ""
          back = T.concat [Map.findWithDefault "" g entries | (g, _, _) <- gs]
       in ([g | (g, _, _) <- gs], if back == text then Nothing else Just text)
