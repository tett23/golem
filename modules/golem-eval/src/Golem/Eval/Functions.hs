{- | The table of the functions of .emet that a .gm file uses (docs/adr/0162):
for each .emet, by its path from the root of the project, the inline
commands, the block commands and the functions of the expression context
it gives, with what they take. golem-eval holds the types and resolves
the names of a namespace of @import through them; golem-driver fills the
table from golem-emet, so golem-eval does not depend on golem-emet.

The values .gm passes are checked here, before a function is called: the
number of the positional arguments (G02120), the type of each value
(G02121) and the keyword arguments the signature has not (G02119).
-}
module Golem.Eval.Functions
  ( ArgType (..),
    argTypeText,
    KeywordParam (..),
    Params (..),
    noParams,
    InlineFunction (..),
    BlockFunction (..),
    ExprFunction (..),
    FunctionNamespace (..),
    emptyNamespace,
    FunctionTable (..),
    noFunctions,
    FunctionRef (..),
    ArgError (..),
    argErrorDiagnostic,
    positionalValues,
    fitValue,
    unloadedFact,
    isUnloaded,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR (Block, Inline)
import Golem.Eval.Value
import Golem.Syntax

-- | The type of a value .gm passes to a function, and of a value a @pub fn@ returns.
data ArgType = ArgNat | ArgInt | ArgRat | ArgString | ArgBool | ArgList !ArgType
  deriving stock (Eq, Show)

-- | A type as .emet writes it, for the messages.
argTypeText :: ArgType -> Text
argTypeText = \case
  ArgNat -> "Nat"
  ArgInt -> "Int"
  ArgRat -> "Rat"
  ArgString -> "String"
  ArgBool -> "Bool"
  ArgList t -> "List " <> paren (argTypeText t)
  where
    paren t = if " " `T.isInfixOf` t then "(" <> t <> ")" else t

-- | A keyword argument of a command: its name in .gm, its type and the value when it is left out.
data KeywordParam = KeywordParam
  { kpName :: !Text,
    kpType :: !ArgType,
    kpDefault :: !Value
  }
  deriving stock (Eq, Show)

{- | What a function takes from .gm: the positional arguments, the type of
the variable arguments after them (@Varargs a@), and the keyword
arguments.
-}
data Params = Params
  { prPositional :: ![ArgType],
    prVarargs :: !(Maybe ArgType),
    prKeywords :: ![KeywordParam]
  }
  deriving stock (Eq, Show)

noParams :: Params
noParams = Params [] Nothing []

{- | An inline command: what it takes, the number of its prose slots, and
the call with the values (the positional ones, the variable ones as an
array, then the keyword ones in the order of the signature), the slots
evaluated, and the span of the call.
-}
data InlineFunction = InlineFunction
  { ifParams :: !Params,
    ifSlots :: !Int,
    ifSignature :: !Text,
    ifCall :: [Value] -> [[Inline]] -> SrcSpan -> Either [Diagnostic] [Inline]
  }

-- | A block command: whether it takes the indented body.
data BlockFunction = BlockFunction
  { bfParams :: !Params,
    bfBody :: !Bool,
    bfSignature :: !Text,
    bfCall :: [Value] -> [Block] -> SrcSpan -> Either [Diagnostic] [Block]
  }

-- | A function of the expression context (@pub fn@) and the type of what it returns.
data ExprFunction = ExprFunction
  { efParams :: !Params,
    efResult :: !ArgType,
    efSignature :: !Text,
    efCall :: [Value] -> SrcSpan -> Either Diagnostic Value
  }

{- | What one .emet gives .gm. @fnOthers@ are the names of the functions
that the expression context cannot call, with why, for G02002.
-}
data FunctionNamespace = FunctionNamespace
  { fnInline :: !(Map Text InlineFunction),
    fnBlock :: !(Map Text BlockFunction),
    fnExpr :: !(Map Text ExprFunction),
    fnOthers :: !(Map Text Text)
  }

emptyNamespace :: FunctionNamespace
emptyNamespace = FunctionNamespace Map.empty Map.empty Map.empty Map.empty

{- | The .emet of a project by their paths from the root. @ftUnloaded@:
the .emet could not be loaded or checked, and their errors are reported
in them; the calls through their namespaces report nothing.
-}
data FunctionTable = FunctionTable
  { ftFiles :: !(Map FilePath FunctionNamespace),
    ftUnloaded :: !Bool,
    -- | the .gm a filter of a .emet applies to, whose names are checked after the filters
    ftFilterFiles :: !(Set FilePath)
  }

noFunctions :: FunctionTable
noFunctions = FunctionTable Map.empty False Set.empty

{- | A namespace of @import of a .emet in a .gm: its functions, or an .emet
that could not be loaded, whose calls report nothing.
-}
data FunctionRef = Loaded !FunctionNamespace | Unloaded

-- | Why the values .gm passed do not fit what a function takes.
data ArgError
  = -- | the number of the positional values, and how many the function takes, at least when it has variable ones
    WrongCount !Int !Int !Bool
  | -- | the place from 1, the type it takes, and the value
    WrongType !Int !ArgType !Value
  deriving stock (Eq, Show)

{- | G02120 and G02121 at the span of a call of a function of a name. The
message of G02121 tells the place of the value, the type and the value.
-}
argErrorDiagnostic :: SrcSpan -> Text -> ArgError -> Diagnostic
argErrorDiagnostic sp name = \case
  WrongCount n want atLeast ->
    diagnostic "G02120" Error sp ("位置引数の数が合いません: " <> name <> " は " <> tshow want <> " 個" <> (if atLeast then "以上" else "") <> "の位置引数を取りますが、" <> tshow n <> " 個あります")
  WrongType i t v ->
    diagnostic "G02121" Error sp ("引数の型が合いません: " <> name <> " の " <> tshow i <> " 番目の値は " <> argTypeText t <> " を求めますが、" <> typeName v <> "です")
  where
    tshow :: Int -> Text
    tshow = T.pack . show

{- | The positional values fitted to the positional arguments: the values
of the arguments in order, and those of the variable arguments as one
array at the end.
-}
positionalValues :: Params -> [Value] -> Either ArgError [Value]
positionalValues ps vs =
  let fixed = prPositional ps
      n = length fixed
   in case prVarargs ps of
        Nothing
          | length vs /= n -> Left (WrongCount (length vs) n False)
          | otherwise -> sequence [fitAt i t v | (i, t, v) <- zip3 [1 ..] fixed vs]
        Just vt
          | length vs < n -> Left (WrongCount (length vs) n True)
          | otherwise -> do
              xs <- sequence [fitAt i t v | (i, t, v) <- zip3 [1 ..] fixed vs]
              rest <- sequence [fitAt i vt v | (i, v) <- zip [n + 1 ..] (drop n vs)]
              pure (xs <> [VArray rest])
  where
    fitAt i t v = maybe (Left (WrongType i t v)) Right (fitValue t v)

{- | A value of .gm as a value of a type, a narrower number widened to a
wider one (docs/adr ADR 0101); the words true and false are booleans.
Nothing when it does not fit.
-}
fitValue :: ArgType -> Value -> Maybe Value
fitValue t v = case (t, v) of
  (ArgNat, VNat _) -> Just v
  (ArgInt, VNat n) -> Just (VInt (toInteger n))
  (ArgInt, VInt _) -> Just v
  (ArgRat, _) | Just (_, q) <- numberOf v -> Just (VRat q)
  (ArgString, VString _) -> Just v
  (ArgBool, VBool _) -> Just v
  (ArgBool, VString "true") -> Just (VBool True)
  (ArgBool, VString "false") -> Just (VBool False)
  (ArgList e, VArray xs) -> VArray <$> traverse (fitValue e) xs
  _ -> Nothing

{- | The fact a diagnostic of a call through a namespace whose .emet could
not be loaded carries: such a diagnostic is not reported (docs/adr/0162).
-}
unloadedFact :: (Text, Fact)
unloadedFact = ("unloaded-functions", FactText "")

isUnloaded :: Diagnostic -> Bool
isUnloaded d = unloadedFact `elem` diagFacts d
