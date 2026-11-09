{- | The position of characters: normal, superscript or subscript
(docs/adr/0269), the Position of InDesign's character panel.
-}
module Golem.Project.Position
  ( Position (..),
    positionValues,
  )
where

import Data.Text (Text)

data Position = PositionNormal | PositionSuperscript | PositionSubscript
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The values of position in style.toml, in the order of 'Position'.
positionValues :: [(Text, Position)]
positionValues = [("normal", PositionNormal), ("superscript", PositionSuperscript), ("subscript", PositionSubscript)]
