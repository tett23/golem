{-# LANGUAGE TemplateHaskell #-}

{- | The British English patterns and exceptions of hyph-utf8, bundled at a fixed
commit (docs/adr ADR 0276; data/hyphenation/README.md). The files are
embedded when compiling, so they cannot change at run time.
-}
module Golem.Layout.Hyphenation.EnGb
  ( englishGB,
  )
where

import Data.Text qualified as T
import Golem.Layout.Hyphenation
import Golem.Layout.Hyphenation.Embed (embedText)

-- | Two letters at least before a break and three after, as hyph-utf8 sets for en-gb.
englishGB :: Patterns
englishGB =
  withExceptions
    (T.pack $(embedText "data/hyphenation/hyph-en-gb.hyp.txt"))
    (parsePatterns 2 3 (T.pack $(embedText "data/hyphenation/hyph-en-gb.pat.txt")))
