{-# LANGUAGE TemplateHaskell #-}

{- | The French patterns of hyph-utf8, bundled at a fixed
commit (docs/adr ADR 0276; data/hyphenation/README.md). The files are
embedded when compiling, so they cannot change at run time.
-}
module Golem.Layout.Hyphenation.Fr
  ( french,
  )
where

import Data.Text qualified as T
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.Embed (embedText)

-- | Two letters at least before a break and two after, as hyph-utf8 sets for fr.
french :: Patterns
french =
  parsePatterns 2 2 (T.pack $(embedText "data/hyphenation/hyph-fr.pat.txt"))
