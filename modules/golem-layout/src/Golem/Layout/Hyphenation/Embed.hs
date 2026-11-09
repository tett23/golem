{- | The text of a file of data/hyphenation/, embedded when compiling (docs/adr
ADR 0276): read as UTF-8 whatever the locale, as the patterns of most
languages have letters outside ASCII.
-}
module Golem.Layout.Hyphenation.Embed
  ( embedText,
  )
where

import Language.Haskell.TH (Exp, Q, litE, stringL)
import Language.Haskell.TH.Syntax (addDependentFile, runIO)
import System.IO (IOMode (ReadMode), hGetContents', hSetEncoding, utf8, withFile)

-- | The characters of a file, as a string literal; a change of the file recompiles the module.
embedText :: FilePath -> Q Exp
embedText path = do
  addDependentFile path
  runIO (withFile path ReadMode (\h -> hSetEncoding h utf8 >> hGetContents' h)) >>= litE . stringL
