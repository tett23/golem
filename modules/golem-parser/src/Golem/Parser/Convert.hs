{- | Conversion from the peg-hs syntax tree to the Golem CST
(golem-parser ADR 0002). Rules without a Golem kind are flattened, so
the text of the tree is preserved.
-}
module Golem.Parser.Convert
  ( convert,
    kindForRule,
    kindForToken,
  )
where

import Data.Text (Text)
import Golem.Parser.CST
import Golem.Parser.Generated (nameOfSyntaxKind)
import Peg.Runtime.Syntax qualified as P

kindForRule :: Text -> Maybe SyntaxKind
kindForRule = \case
  "File" -> Just NFile
  "BlankLines" -> Just NBlankLines
  "Heading" -> Just NHeading
  "Paragraph" -> Just NParagraph
  "InlineCommand" -> Just NInlineCommand
  "Argument" -> Just NArgument
  "KeywordArgument" -> Just NKeywordArgument
  "SplatArgument" -> Just NSplatArgument
  "ProseSlot" -> Just NProseSlot
  "ExprCtx" -> Just NExpr
  "CompareExpr" -> Just NBinaryExpr
  "AddExpr" -> Just NBinaryExpr
  "MulExpr" -> Just NBinaryExpr
  "PowExpr" -> Just NBinaryExpr
  "UnaryExpr" -> Just NUnaryExpr
  "CallExpr" -> Just NCallExpr
  "NumberLiteral" -> Just NLiteral
  "StringLiteral" -> Just NLiteral
  "KeywordLiteral" -> Just NLiteral
  "VarExpr" -> Just NVarExpr
  "ArrayExpr" -> Just NArrayExpr
  "HashExpr" -> Just NHashExpr
  "HashEntry" -> Just NHashEntry
  "ParenExpr" -> Just NParenExpr
  "BlockGroup" -> Just NAttributed
  "BlockCommand" -> Just NBlockCommand
  "CommandBody" -> Just NCommandBody
  "BulletList" -> Just NBulletList
  "OrderedList" -> Just NOrderedList
  "ListItem" -> Just NListItem
  "DefList" -> Just NDefList
  "DefGroup" -> Just NDefGroup
  "DefTerm" -> Just NDefTerm
  "DefNew" -> Just NDefNew
  "DefBody" -> Just NDefBody
  "Table" -> Just NTable
  "TableRow" -> Just NTableRow
  "TableCell" -> Just NTableCell
  "TableDelimiter" -> Just NTableDelimiter
  "CodeBlock" -> Just NCodeBlock
  "HardBreak" -> Just NHardBreak
  "ERROR" -> Just NErrorNode
  _ -> Nothing

kindForToken :: Text -> SyntaxKind
kindForToken = \case
  "Text" -> KText
  "SlotText" -> KText
  "CellText" -> KText
  "Escape" -> KEscape
  "Backslash" -> KBackslash
  "Ws" -> KWhitespace
  "Ind" -> KWhitespace
  "Nl" -> KNewline
  "Comment" -> KComment
  "ProofComment" -> KProofComment
  "Ident" -> KIdent
  "ExprIdent" -> KIdent
  "SetIdent" -> KIdent
  "Word" -> KWord
  "Number" -> KNumber
  "StringLit" -> KString
  "Fence" -> KFence
  "CodeLine" -> KCodeText
  "Lang" -> KWord
  "LBr" -> KLBracket
  "RBr" -> KRBracket
  "ExprOpen" -> KExprOpen
  "Colon" -> KColon
  "Pipe" -> KPipe
  "Eq" -> KEquals
  "At" -> KAt
  "HashMark" -> KHash
  "BulletMark" -> KDash
  "OrderedMark" -> KPlus
  "TermMark" -> KEquals
  "NewDefMark" -> KNewDefMark
  "AddOp" -> KOperator
  "MulOp" -> KOperator
  "PowOp" -> KOperator
  "CmpOp" -> KOperator
  "NegOp" -> KOperator
  "Comma" -> KComma
  "LBrace" -> KLBrace
  "RBrace" -> KRBrace
  "LParen" -> KLParen
  "RParen" -> KRParen
  "Dot" -> KDot
  "Splat" -> KStar
  "Delim" -> KDelim
  "Keyword" -> KKeyword
  "Rest" -> KError
  "SkippedArgs" -> KError
  "SkippedExpr" -> KError
  "ERROR" -> KError
  _ -> KOperator

-- | Converts the root, which is always the File rule.
convert :: P.SyntaxNode -> Node
convert root
  | nameOfSyntaxKind (P.syntaxKind root) == "File" = node NFile (children root)
  | otherwise = node NFile (element (P.NodeElement root))
  where
    children n = concatMap element (P.syntaxChildrenWithTokens n)
    element = \case
      P.TokenElement t -> [token (kindForToken (nameOfSyntaxKind (P.tokenKind t))) (P.tokenText t)]
      P.NodeElement m ->
        let name = nameOfSyntaxKind (P.syntaxKind m)
         in case kindForRule name of
              Just k -> [ElemNode (node k (children m))]
              Nothing -> children m
