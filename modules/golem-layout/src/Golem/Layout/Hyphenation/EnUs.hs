{-# LANGUAGE TemplateHaskell #-}

{- | The US English patterns and exceptions of hyph-utf8, bundled at a fixed
commit (golem-layout ADR 0001; data/hyphenation/README.md). The files
are embedded when compiling, so they cannot change at run time.
-}
module Golem.Layout.Hyphenation.EnUs
  ( englishUS,
  )
where

import Data.Text qualified as T
import Golem.Layout.Hyphenation
import Language.Haskell.TH (litE, stringL)
import Language.Haskell.TH.Syntax (addDependentFile, runIO)

{- | Two letters at least before a break and three after, as hyph-utf8 sets
for en-us.
-}
englishUS :: Patterns
englishUS =
  withExceptions
    ( T.pack
        $( do
             let path = "data/hyphenation/hyph-en-us.hyp.txt"
             addDependentFile path
             runIO (readFile path) >>= litE . stringL
         )
    )
    ( parsePatterns
        2
        3
        ( T.pack
            $( do
                 let path = "data/hyphenation/hyph-en-us.pat.txt"
                 addDependentFile path
                 runIO (readFile path) >>= litE . stringL
             )
        )
    )
