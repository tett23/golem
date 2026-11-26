{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -Wincomplete-patterns -Werror=incomplete-patterns #-}

-- Export the canonical peg-hs AST.  The JavaScript generator never parses a
-- second copy of the PEG syntax for its Lean model.
import Data.Aeson (Value, encode, object, (.=))
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Char (ord)
import Data.Maybe (listToMaybe)
import qualified Data.Text.IO as T
import Peg.Grammar
import Peg.Grammar.Parser (parseGrammar)
import System.Environment (getArgs)
import System.Exit (die)

itemValue :: Item -> Value
itemValue item = object ["line" .= locLine (itemLoc item), "bind" .= itemBind item, "expr" .= exprValue (itemExpr item)]

exprValue :: Expr -> Value
exprValue = \case
  ELit value written -> object ["tag" .= ("lit" :: String), "value" .= value, "written" .= written]
  EClass ranges written -> object ["tag" .= ("class" :: String), "ranges" .= [[ord lo, ord hi] | (lo, hi) <- ranges], "written" .= written]
  EAny -> object ["tag" .= ("any" :: String)]
  ERef _ name args -> object ["tag" .= ("ref" :: String), "name" .= name, "args" .= map unLoc args]
  EGroup alts -> object ["tag" .= ("choice" :: String), "alts" .= map (map itemValue) alts]
  EStar child -> unary "star" child
  EPlus child -> unary "plus" child
  EOpt child -> unary "opt" child
  EAnd child -> unary "and" child
  ENot child -> unary "not" child
  ECapture child -> unary "capture" child
  ELabel _ child name -> object ["tag" .= ("label" :: String), "expr" .= exprValue child, "name" .= name]
  EPred positive source -> object ["tag" .= ("pred" :: String), "positive" .= positive, "source" .= unLoc source]
  ETemplate _ name children args -> object ["tag" .= ("template" :: String), "name" .= name, "children" .= map exprValue children, "args" .= map unLoc args]
  EDiscard child -> unary "discard" child
  where
    unary :: String -> Expr -> Value
    unary tag child = object ["tag" .= tag, "expr" .= exprValue child]

altValue :: Alt -> Value
altValue alt =
  object
    [ "line" .= locLine (altLoc alt),
      "items" .= map itemValue (altItems alt),
      "action" .= fmap unLoc (altAction alt),
      "constructor" .= fmap unLoc (altConstructor alt)
    ]

ruleValue :: Rule -> Value
ruleValue rule =
  object
    [ "name" .= ruleName rule,
      "line" .= locLine (ruleLoc rule),
      "params" .= map paramName (ruleParams rule),
      "templateParams" .= map templateParamName (ruleTemplateParams rule),
      "type" .= unLoc (ruleType rule),
      "alts" .= map altValue (ruleAlts rule)
    ]

grammarValue :: Grammar -> Value
grammarValue grammar =
  object
    [ "start" .= maybe (maybe "" ruleName (listToMaybe (grammarRules grammar))) unLoc (grammarStart grammar),
      "tokens" .= map unLoc (grammarTokens grammar),
      "trivia" .= map unLoc (grammarTrivia grammar),
      "inline" .= map unLoc (grammarInline grammar),
      "rules" .= map ruleValue (grammarRules grammar)
    ]

main :: IO ()
main = do
  args <- getArgs
  case args of
    [input] -> do
      source <- T.readFile input
      case parseGrammar source of
        Left diagnostics -> die (unlines (map show diagnostics))
        Right grammar -> BL.putStrLn (encode (grammarValue grammar))
    _ -> die "usage: export-peg.hs Golem.hpeg"
