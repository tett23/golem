{- | Aki sets (docs/adr ADR 0019): the space between two characters by the
pair of their classes, and at the line start, the paragraph start and the
line end. Amounts are in zw, as (minimum, optimum, maximum).
-}
module Golem.Layout.Aki
  ( AkiPos (..),
    Aki (..),
    AkiSet,
    noAki,
    akiBetween,
    withAkiRule,
    akiPositions,
    builtinAkiSets,
    defaultAkiSet,
    resolveAkiSet,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Golem.Layout.CharClass
import Golem.Project.Style (AkiRuleDef (..), AkiSetDef (..), defaultAkiSetName)

-- | One side of a pair: a character of a class, or an edge.
data AkiPos = AkiChar !CharClass | AkiLineStart | AkiParagraphStart | AkiLineEnd
  deriving stock (Eq, Ord, Show)

-- | Minimum, optimum and maximum, in zw.
data Aki = Aki {akiMinimum, akiOptimum, akiMaximum :: !Rational}
  deriving stock (Eq, Show)

-- | The aki of every pair a rule names; the other pairs have none.
newtype AkiSet = AkiSet (Map (AkiPos, AkiPos) Aki)
  deriving stock (Eq, Show)

-- | No space, no stretch, no shrink.
noAki :: Aki
noAki = Aki 0 0 0

-- | The aki between two positions; a pair no rule names has 'noAki'.
akiBetween :: AkiSet -> AkiPos -> AkiPos -> Aki
akiBetween (AkiSet m) a b = Map.findWithDefault noAki (a, b) m

-- | A rule added after the rules of a set: it overrides the pairs it names.
withAkiRule :: [AkiPos] -> [AkiPos] -> Aki -> AkiSet -> AkiSet
withAkiRule befores afters a (AkiSet m) = AkiSet (foldl' (\acc k -> Map.insert k a acc) m [(x, y) | x <- befores, y <- afters])

{- | The positions a name of a rule stands for: a class, @japanese@ (every
class but @western@), or an edge. An unknown name stands for none.
-}
akiPositions :: Text -> [AkiPos]
akiPositions = \case
  "opening" -> chars [Opening]
  "closing" -> chars [Closing]
  "hyphen" -> chars [Hyphen]
  "dividing" -> chars [Dividing]
  "middle-dot" -> chars [MiddleDot]
  "full-stop" -> chars [FullStop]
  "comma" -> chars [Comma]
  "inseparable" -> chars [Inseparable]
  "iteration" -> chars [Iteration]
  "prolonged-sound" -> chars [ProlongedSound]
  "small-kana" -> chars [SmallKana]
  "ideographic-space" -> chars [IdeographicSpace]
  "kana" -> chars [Kana]
  "ideograph" -> chars [Ideograph]
  "western" -> chars [Western]
  "japanese" -> chars [c | c <- [minBound .. maxBound], c /= Western]
  "line-start" -> [AkiLineStart]
  "paragraph-start" -> [AkiParagraphStart]
  "line-end" -> [AkiLineEnd]
  _ -> []
  where
    chars = map AkiChar

{- | gyomatsu-yakumono-hankaku: the composition of golem-layout ADR 0002.
P is closing, full stop and comma, O opening, M middle dot, J the other
Japanese classes and W western.
-}
defaultAkiSet :: AkiSet
defaultAkiSet = foldl' (\s (b, a, x) -> withAkiRule b a x s) (AkiSet Map.empty) rules
  where
    chars = map AkiChar
    p = chars [Closing, FullStop, Comma]
    o = chars [Opening]
    m = chars [MiddleDot]
    w = chars [Western]
    j = chars [Hyphen, Dividing, Inseparable, Iteration, ProlongedSound, SmallKana, IdeographicSpace, Kana, Ideograph]
    rules =
      [ (j, chars [Kana, Ideograph, IdeographicSpace, Inseparable], Aki 0 0 (1 / 10)),
        (chars [Inseparable], chars [Inseparable], noAki),
        (j <> w <> o, o, Aki 0 (1 / 2) (1 / 2)),
        (j <> w <> o, m, Aki 0 (1 / 4) (1 / 4)),
        (p, o, Aki 0 (1 / 2) (1 / 2)),
        (m, o, Aki 0 (3 / 4) (3 / 4)),
        (p, j <> w, Aki 0 (1 / 2) (1 / 2)),
        (p, m, Aki 0 (3 / 4) (3 / 4)),
        (m, j <> w, Aki 0 (1 / 4) (1 / 4)),
        (m, m, Aki 0 (1 / 2) (1 / 2)),
        (j, w, Aki (1 / 8) (1 / 4) (1 / 2)),
        (w, j, Aki (1 / 8) (1 / 4) (1 / 2)),
        ([AkiParagraphStart], o, Aki 0 (1 / 2) (1 / 2)),
        ([AkiParagraphStart], m, Aki 0 (1 / 4) (1 / 4))
      ]

-- | The built-in sets: gyomatsu-yakumono-hankaku and gyomatsu-yakumono-zenkaku.
builtinAkiSets :: Map Text AkiSet
builtinAkiSets =
  Map.fromList
    [ ("gyomatsu-yakumono-hankaku", defaultAkiSet),
      ( "gyomatsu-yakumono-zenkaku",
        withAkiRule [AkiChar MiddleDot] [AkiLineEnd] (Aki (1 / 4) (1 / 4) (1 / 4)) $
          withAkiRule (map AkiChar [Closing, FullStop, Comma]) [AkiLineEnd] (Aki (1 / 2) (1 / 2) (1 / 2)) defaultAkiSet
      )
    ]

{- | The set of a name: a built-in set, or a set of style.toml with its
rules after those of the set it is based on. A name that is not found,
and a cycle, which style.toml's checks reject, fall back to the default.
-}
resolveAkiSet :: Map Text AkiSetDef -> Text -> AkiSet
resolveAkiSet defs = go []
  where
    go seen name
      | name `elem` seen = defaultAkiSet
      | Just s <- Map.lookup name builtinAkiSets = s
      | Just d <- Map.lookup name defs = foldl' rule (go (name : seen) (fromMaybe defaultAkiSetName (asBasedOn d))) (asRules d)
      | otherwise = defaultAkiSet
    rule s r = withAkiRule (concatMap akiPositions (arBefore r)) (concatMap akiPositions (arAfter r)) (Aki (arMinimum r) (arOptimum r) (arMaximum r)) s
