{-# LANGUAGE TemplateHaskell #-}

{- | The Dutch patterns and exceptions of hyph-utf8, bundled at a fixed
commit (docs/adr ADR 0276; data/hyphenation/README.md). The files are
embedded when compiling, so they cannot change at run time.
-}
module Golem.Layout.Hyphenation.Nl
  ( dutch,
  )
where

import Data.Text qualified as T
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.Embed (embedText)

-- | Two letters at least before a break and two after, as hyph-utf8 sets for nl.
dutch :: Patterns
dutch =
  withExceptions
    (T.pack $(embedText "data/hyphenation/hyph-nl.hyp.txt"))
    (parsePatterns 2 2 (T.pack $(embedText "data/hyphenation/hyph-nl.pat.txt")))
