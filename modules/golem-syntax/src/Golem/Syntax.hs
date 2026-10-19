{- | Source positions and diagnostics shared by every Golem module
(golem-syntax ADR 0001).
-}
module Golem.Syntax
  ( module Golem.Syntax.Span,
    module Golem.Syntax.Position,
    module Golem.Syntax.Diagnostic,
    module Golem.Syntax.Render,
    module Golem.Syntax.Chars,
  )
where

import Golem.Syntax.Chars
import Golem.Syntax.Diagnostic
import Golem.Syntax.Position
import Golem.Syntax.Render
import Golem.Syntax.Span
