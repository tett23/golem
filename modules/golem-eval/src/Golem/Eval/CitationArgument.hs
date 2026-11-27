{- | Decode the successful citation keyword values of root ADR 0385.
Nothing means unhandled, not an error: argument conflict, unknown-key and
invalid-value diagnostics remain the responsibility of the caller.
-}
module Golem.Eval.CitationArgument
  ( CitationArgument (..),
    decodeCitationArgument,
    CitationKeyword (..),
    validateCitationLocatorArguments,
    validateCitationLocatorNames,
    validateCitationLocatorValue,
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
The source evaluator uses the same name and value checks.
-}
validateCitationLocatorArguments :: [CitationKeyword] -> [Diagnostic]
validateCitationLocatorArguments keywords = concat (zipWith (\names keyword -> names <> validateCitationLocatorValue keyword) (validateCitationLocatorNames [(ckNameSpan k, ckName k) | k <- keywords]) keywords)

{- | One list per input keyword, so evaluation errors can be interleaved
without fabricating values for arguments whose evaluation failed.
-}
validateCitationLocatorNames :: [(SrcSpan, Text)] -> [[Diagnostic]]
validateCitationLocatorNames = go Set.empty
  where
    go _ [] = []
    go seen ((at, name) : rest)
      | name `elem` ["prefix", "suffix", "form"] = [] : go seen rest
      | Just label <- locatorLabelNamed name =
          let problems
                | Set.member label seen = [diagnostic "G02296" Error at ("cite に同じ位置の種類を二度書いています: " <> name)]
                | not (Set.null seen) = [diagnostic "G02295" Error at ("cite には位置の種類を一つだけ書きます: " <> name)]
                | otherwise = []
           in problems : go (Set.insert label seen) rest
      | otherwise = [diagnostic "G02297" Error at ("cite の名前付き引数に書けない名前です: " <> name)] : go seen rest

validateCitationLocatorValue :: CitationKeyword -> [Diagnostic]
validateCitationLocatorValue keyword
  | Nothing <- locatorLabelNamed (ckName keyword) = []
  | otherwise = case ckValue keyword of
      VRange a b | a < 0 || b < 0 -> badValue keyword
      -- root ADR 0113 rejects reversed ranges before constructing VRange.
      -- Defend the same invariant for direct callers without a new constraint.
      VRange a b
        | a > b ->
            [diagnostic "G02106" Error (ckValueSpan keyword) ("範囲の始め " <> T.pack (show a) <> " が終わり " <> T.pack (show b) <> " より大きくなっています")]
      value -> case decodeCitationArgument (ckName keyword) value of
        Just (CitationLocator _) -> []
        _ -> badValue keyword
  where
    badValue badKeyword =
      let (code, message) =
            if ckName badKeyword == "page"
              then ("G02148", "page には頁の数、範囲、文字列を書きます: ")
              else ("G02298", ckName badKeyword <> " には位置の数、範囲、文字列を書きます: ")
       in [diagnostic code Error (ckValueSpan badKeyword) (message <> valueText (ckValue badKeyword))]
