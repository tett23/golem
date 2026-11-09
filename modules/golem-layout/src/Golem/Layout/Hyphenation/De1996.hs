{-# LANGUAGE TemplateHaskell #-}

{- | The German (reformed orthography of 1996) patterns of hyph-utf8, bundled at a fixed
commit (docs/adr ADR 0276; data/hyphenation/README.md). The files are
embedded when compiling, so they cannot change at run time.
-}
module Golem.Layout.Hyphenation.De1996
  ( german,
  )
where

import Data.Text qualified as T
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.Embed (embedText)

-- | Two letters at least before a break and two after, as hyph-utf8 sets for de-1996.
german :: Patterns
german =
  parsePatterns 2 2 (T.pack $(embedText "data/hyphenation/hyph-de-1996.pat.txt"))
