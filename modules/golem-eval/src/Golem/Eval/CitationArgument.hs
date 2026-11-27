{- | Decode the successful citation keyword values of root ADR 0385.
Nothing means unhandled, not an error: argument conflict, unknown-key and
invalid-value diagnostics remain the responsibility of the caller.
-}
module Golem.Eval.CitationArgument
  ( CitationArgument (..),
    decodeCitationArgument,
    CitationKeyword (..),
    validateCitationLocatorArguments,
  )
where

import Data.Ratio (denominator, numerator)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR (Locator (..), LocatorValue (..), locatorLabelNamed)
import Golem.Eval.Expr (valueText)
import Golem.Eval.Value (Value (..))
import Golem.Syntax (Diagnostic, Severity (Error), SrcSpan, diagnostic)

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

-- | The keyword name and value retain separate source locations.
data CitationKeyword = CitationKeyword
  { ckNameSpan :: !SrcSpan,
    ckValueSpan :: !SrcSpan,
    ckName :: !Text,
    ckValue :: !Value
  }
  deriving stock (Eq, Show)

{- | Validate locator keywords in input order, leaving affix/form policy to the caller.
This API does not enable a new citation output path.
-}
validateCitationLocatorArguments :: [CitationKeyword] -> [Diagnostic]
validateCitationLocatorArguments = go Set.empty
  where
    go _ [] = []
    go seen (keyword : rest)
      | ckName keyword `elem` ["prefix", "suffix", "form"] = go seen rest
      | Just label <- locatorLabelNamed (ckName keyword) =
          conflicts seen label keyword <> invalid keyword <> go (Set.insert label seen) rest
      | otherwise =
          diagnostic "G02297" Error (ckNameSpan keyword) ("cite の名前付き引数に書けない名前です: " <> ckName keyword)
            : go seen rest
    conflicts seen label keyword
      | Set.member label seen = [diagnostic "G02296" Error (ckNameSpan keyword) ("cite に同じ位置の種類を二度書いています: " <> ckName keyword)]
      | not (Set.null seen) = [diagnostic "G02295" Error (ckNameSpan keyword) ("cite には位置の種類を一つだけ書きます: " <> ckName keyword)]
      | otherwise = []
    invalid keyword = case ckValue keyword of
      VRange a b | a < 0 || b < 0 -> badValue keyword
      -- root ADR 0113 rejects reversed ranges before constructing VRange.
      -- Defend the same invariant for direct callers without a new constraint.
      VRange a b
        | a > b ->
            [diagnostic "G02106" Error (ckValueSpan keyword) ("範囲の始め " <> T.pack (show a) <> " が終わり " <> T.pack (show b) <> " より大きくなっています")]
      value -> case decodeCitationArgument (ckName keyword) value of
        Just (CitationLocator _) -> []
        _ -> badValue keyword
    badValue keyword =
      let (code, message) =
            if ckName keyword == "page"
              then ("G02148", "page には頁の数、範囲、文字列を書きます: ")
              else ("G02298", ckName keyword <> " には位置の数、範囲、文字列を書きます: ")
       in [diagnostic code Error (ckValueSpan keyword) (message <> valueText (ckValue keyword))]
