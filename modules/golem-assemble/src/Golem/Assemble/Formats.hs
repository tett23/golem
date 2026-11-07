{- | The formats of style.toml and the table of number notations
(docs/adr/0177), for the packages that read style.toml through
golem-assemble.
-}
module Golem.Assemble.Formats
  ( module Golem.Numerals.Format,
    module Golem.Numerals.Notation,
  )
where

import Golem.Numerals.Format
import Golem.Numerals.Notation
