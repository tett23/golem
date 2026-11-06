{- | The highlighting of .emet (docs/adr/0170): the type of each token of
the lossless syntax tree, decided by the kind of the token and the nodes
above it alone, never by the check of types, so that the colours do not
change while a file being typed does not check.

A name is one token over its characters (the tree splits it into its
characters). Brackets, braces, commas, white space, and the place of a
syntax error have no token. A file that does not parse has the tokens of
the part before the error ('parsedPrefix').
-}
module Golem.Emet.Highlight
  ( HlType (..),
    Highlight (..),
    emetHighlights,
  )
where

import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Generated qualified as G
import Golem.Emet.Parse (parsedPrefix)
import Peg.Runtime.Syntax

-- | The types of the tokens: those of the semantic tokens of LSP the table of docs/adr/0170 names.
data HlType
  = HlComment
  | HlKeyword
  | HlFunction
  | HlVariable
  | HlParameter
  | HlType
  | HlTypeParameter
  | HlEnumMember
  | HlNamespace
  | HlString
  | HlNumber
  | HlOperator
  | HlMacro
  deriving stock (Eq, Show, Enum, Bounded)

-- | A token: its range in UTF-8 bytes, its type, and whether it is the name of a declaration.
data Highlight = Highlight
  { hlStart :: !Int,
    hlEnd :: !Int,
    hlType :: !HlType,
    hlDeclaration :: !Bool
  }
  deriving stock (Eq, Show)

-- | The tokens of a text, in the order of the text.
emetHighlights :: Text -> [Highlight]
emetHighlights text = maybe [] (node []) (parsedPrefix G.parseSyntax text)

kindName :: SyntaxNode -> Text
kindName = G.nameOfSyntaxKind . syntaxKind

-- | The tokens under a node, given the nodes above it, the nearest first.
node :: [SyntaxNode] -> SyntaxNode -> [Highlight]
node above n = case kindName n of
  "VarTok" -> [plain s e (varType above n) | let (s, e) = syntaxRange n]
  "ConTok" -> [conToken above n]
  "QualVar" -> qualified n (fst (varType above n))
  "QualCon" -> qualified n (if any ((== "TyConLoc") . kindName) (take 1 above) then HlType else HlEnumMember)
  "NumTok" -> [Highlight s e HlNumber False | let (s, e) = syntaxRange n]
  _ -> concatMap child (syntaxChildrenWithTokens n)
  where
    child = \case
      NodeElement m -> node (n : above) m
      TokenElement t -> token n t
    plain s e (ty, decl) = Highlight s e ty decl

-- | A name with a built-in module before it: the module and its dot, then the name.
qualified :: SyntaxNode -> HlType -> [Highlight]
qualified n ty =
  let (s, e) = syntaxRange n
      dot = s + T.length (T.takeWhile (/= '.') (syntaxText n)) + 1
   in [Highlight s dot HlNamespace False, Highlight dot e ty False]

-- | A token that is no name: by its kind, or by the node it is in.
token :: SyntaxNode -> SyntaxToken -> [Highlight]
token parent t = [Highlight s e ty False | Just ty <- [typeOf (G.nameOfSyntaxKind (tokenKind t))]]
  where
    (s, e) = tokenRange t
    typeOf = \case
      "Comment" -> Just HlComment
      "StrTok" -> Just HlString
      "CharTok" -> Just HlString
      "GuardBar" -> Just HlOperator
      "RowOpen" -> Just HlMacro
      "RowClose" -> Just HlMacro
      "TEXT"
        | p `elem` keywordParents -> Just HlKeyword
        | p `elem` operatorParents -> Just HlOperator
        | p == "RowTail" -> Just HlMacro
      _ -> Nothing
    p = kindName parent

-- | The nodes whose own text is a reserved word.
keywordParents :: [Text]
keywordParents = ["Import", "Data", "PubOpt", "TypeAlias", "SigPub", "KindWord", "WhereS", "Case", "GuardCond"]

-- | The nodes whose own text is an operator.
operatorParents :: [Text]
operatorParents = ["EqS", "DColonS", "ArrowS", "ColonS", "QuestionS", "AddOp", "MulOp", "CmpOp", "OrOpS", "AndOpS", "AppendOpS", "PowOpS", "MinusS", "DataBarS"]

-- | The first node above that is not the wrapper of a name.
owner :: [SyntaxNode] -> Maybe SyntaxNode
owner = listToMaybe . dropWhile ((`elem` ["VarNameLoc", "VarName", "ConNameLoc", "QualVarLoc"]) . kindName)

{- | The type of a lowercase name: the name of a signature or an equation
is a function declared; a name at the head of an application is a
function; a variable of a pattern of the arguments of an equation and the
name of a keyword argument are parameters; a variable of a type or of a
row is a type parameter; the kind of a requirement is a macro.
-}
varType :: [SyntaxNode] -> SyntaxNode -> (HlType, Bool)
varType above _ = case kindName <$> owner above of
  Just k
    | k `elem` ["Signature", "LocalSignature", "Equation"] -> (HlFunction, True)
    | k `elem` ["ArrowRow", "RowTail", "AType", "Data", "TypeAlias"] -> (HlTypeParameter, False)
    | k == "Req" -> (HlMacro, False)
    | k == "ArgNameE" -> (HlParameter, False)
    | k == "APat" -> (if inEquationPattern then HlParameter else HlVariable, False)
    | k == "Atom" -> (if headOfApplication then HlFunction else HlVariable, False)
  _ -> (HlVariable, False)
  where
    rest = dropWhile ((`elem` ["VarNameLoc", "VarName", "ConNameLoc", "QualVarLoc"]) . kindName) above
    -- the nearest Equation or Alt above is an Equation
    inEquationPattern = case [k | m <- rest, let k = kindName m, k `elem` ["Equation", "Alt"]] of
      "Equation" : _ -> True
      _ -> False
    headOfApplication = case rest of
      atom : app : _ ->
        kindName app == "App"
          && syntaxLabel atom == Just "f"
          && any (\c -> syntaxLabel c == Just "as") (syntaxChildren app)
      _ -> False

-- | An uppercase name: a type, or a constructor; declared in a data type or an alias.
conToken :: [SyntaxNode] -> SyntaxNode -> Highlight
conToken above n =
  let (s, e) = syntaxRange n
      (ty, decl) = fromMaybe (HlEnumMember, False) $ do
        o <- owner above
        pure $ case kindName o of
          "Data" -> (HlType, True)
          "TypeAlias" -> (HlType, True)
          "ConDecl" -> (HlEnumMember, True)
          "TyConLoc" -> (HlType, False)
          _ -> (HlEnumMember, False)
   in Highlight s e ty decl
