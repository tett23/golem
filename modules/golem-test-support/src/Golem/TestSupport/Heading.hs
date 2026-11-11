{- | One source for checking the parser, CLI and language server against
the same headings (Golem ADR 0310, 0311 and 0323).
-}
module Golem.TestSupport.Heading (headingLimitSource) where

import Data.Text (Text)

{- | The six-mark heading is legal. The two seven-mark headings follow
multibyte text, and the first error ends after a surrogate pair.
-}
headingLimitSource :: Text
headingLimitSource = "😀\n\n###### ok\n\n####### 😀\n\n漢😀\n\n####### A\n"
