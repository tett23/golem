{- | Decode the successful citation keyword values of root ADR 0385.
Nothing means unhandled, not an error: argument conflict, unknown-key and
invalid-value diagnostics remain the responsibility of the caller.
-}
module Golem.Eval.CitationArgument
  ( CitationArgument (..),
    decodeCitationArgument,
  )
where

import Data.Ratio (denominator, numerator)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR (Locator (..), LocatorValue (..), locatorLabelNamed)
import Golem.Eval.Value (Value (..))

-- | A recognized locator or an explicitly written literal affix.
data CitationArgument
  = CitationLocator !Locator
  | CitationPrefix !Text
  | CitationSuffix !Text
  deriving stock (Eq, Show)

-- | Retain a supported value without choosing a policy for other values.
decodeCitationArgument :: Text -> Value -> Maybe CitationArgument
decodeCitationArgument "prefix" (VString text) = Just (CitationPrefix text)
decodeCitationArgument "suffix" (VString text) = Just (CitationSuffix text)
decodeCitationArgument key value = do
  label <- locatorLabelNamed key
  locator <- case value of
    VNat n -> Just (LocNumber (toInteger n))
    VInt n | n >= 0 -> Just (LocNumber n)
    VRat q | denominator q == 1, q >= 0 -> Just (LocNumber (numerator q))
    VRange a b | a >= 0 -> Just (LocRange a b)
    VString text | not (T.null text) -> Just (LocText text)
    _ -> Nothing
  pure (CitationLocator (Locator label locator))
