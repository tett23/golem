{- | The functions of golem-typeset that its tests use and the library
does not otherwise export (root ADR 0436): the composition environment of
the product ('composeEnv'), the look of a paragraph style ('paraLook') and
the empty assumed page numbers, so that a test composes in the environment
the product composes in; the indent of a paragraph that starts with an
opening bracket ('openingIndent', root ADR 0469); the items of a paragraph of
fit-characters ('fitItems', root ADR 0466).
-}
module Golem.Typeset.Internal
  ( composeEnv,
    paraLook,
    emptyAssumed,
    Indent (..),
    openingIndent,
    fitItems,
  )
where

import Data.Map.Strict qualified as Map
import Golem.Typeset.Flow (Assumed (..), Indent (..), composeEnv, fitItems, openingIndent, paraLook)

-- | No assumed page numbers: the first round of the page references, and a text without them.
emptyAssumed :: Assumed
emptyAssumed = Assumed Map.empty Map.empty Map.empty Map.empty
