{- | The wording of G08014, the active content of an SVG figure that HTML
and EPUB refuse (docs/adr ADR 0039).
-}
module Golem.Driver.Svg
  ( activeMessage,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Svg.Active qualified as A

{- | G08014 (docs/adr ADR 0039): the first active thing, with where it is,
and how many more; or why the SVG cannot be read, in the words of G08010.
Nothing when the SVG has nothing active.
-}
activeMessage :: Text -> Either Text [A.Active] -> Maybe Text
activeMessage path = \case
  Left why -> Just (prefix <> path <> "（" <> why <> "）")
  Right [] -> Nothing
  Right (a : rest) ->
    Just $
      prefix
        <> path
        <> ":"
        <> tshow (A.acLine a)
        <> ":"
        <> tshow (A.acColumn a)
        <> "（"
        <> A.acName a
        <> "）"
        <> (if null rest then "" else "ほか " <> tshow (length rest) <> " 件")
  where
    prefix = "SVG の図版に、HTML と EPUB に写せない動的なコンテンツがあります: "
    tshow :: Int -> Text
    tshow = T.pack . show
