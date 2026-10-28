{- | The lossless concrete syntax tree (golem-parser ADR 0001).

Nodes carry only their width; absolute positions are computed while
walking the tree. The only way to build a node is 'node', which computes
the width from the children, so widths are always consistent.
-}
module Golem.Parser.CST
  ( SyntaxKind (..),
    Token (..),
    Node,
    nodeKind,
    nodeWidth,
    nodeChildren,
    Element (..),
    node,
    token,
    elementWidth,
    render,
    Positioned (..),
    withPositions,
    tokens,
    pretty,
  )
where

import Data.ByteString qualified as BS
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Syntax.Span

data SyntaxKind
  = -- tokens
    KText
  | KEscape
  | KWhitespace
  | KNewline
  | KComment
  | KProofComment
  | KLBracket
  | KRBracket
  | KColon
  | KPipe
  | KEquals
  | KAt
  | KHash
  | KDash
  | KPlus
  | KIdent
  | KNumber
  | KString
  | KOperator
  | KComma
  | KLBrace
  | KRBrace
  | KLParen
  | KRParen
  | KDot
  | KStar
  | KFence
  | KCodeText
  | KWord
  | KExprOpen
  | KNewDefMark
  | KDelim
  | KKeyword
  | KBackslash
  | -- | the ## of ##…## (golem-parser ADR 0011)
    KNumberMark
  | -- | what is between the ## of ##…##
    KNumberBody
  | KError
  | -- nodes
    NFile
  | NParagraph
  | NHeading
  | NBulletList
  | NOrderedList
  | NListItem
  | NDefList
  | NDefTerm
  | NDefBody
  | NTable
  | NTableRow
  | NTableDelimiter
  | NCodeBlock
  | NBlockCommand
  | NAttributed
  | NCommandBody
  | NBlankLines
  | NDefGroup
  | NDefNew
  | NTableCell
  | NInlineCommand
  | NExpr
  | NProseSlot
  | NArgument
  | NKeywordArgument
  | NSplatArgument
  | NBinaryExpr
  | NUnaryExpr
  | NCallExpr
  | NLiteral
  | NVarExpr
  | NArrayExpr
  | NHashExpr
  | NHashEntry
  | NParenExpr
  | -- | the closed range a...b (docs/adr ADR 0113)
    NRangeExpr
  | NHardBreak
  | -- | ##…## (golem-parser ADR 0011)
    NNumberShorthand
  | NErrorNode
  deriving stock (Eq, Ord, Show, Enum, Bounded)

data Token = Token
  { tokKind :: !SyntaxKind,
    tokText :: !Text
  }
  deriving stock (Eq, Show)

data Node = Node
  { nodeKind :: !SyntaxKind,
    nodeWidth :: !Int,
    nodeChildren :: ![Element]
  }
  deriving stock (Eq, Show)

data Element = ElemNode !Node | ElemToken !Token
  deriving stock (Eq, Show)

utf8Length :: Text -> Int
utf8Length = BS.length . TE.encodeUtf8

elementWidth :: Element -> Int
elementWidth (ElemNode n) = nodeWidth n
elementWidth (ElemToken t) = utf8Length (tokText t)

-- | The only node constructor: the width is computed from the children.
node :: SyntaxKind -> [Element] -> Node
node k cs = Node k (sum (map elementWidth cs)) cs

token :: SyntaxKind -> Text -> Element
token k t = ElemToken (Token k t)

render :: Node -> Text
render = T.concat . map tokText . tokens

-- | All tokens in order.
tokens :: Node -> [Token]
tokens n = concatMap go (nodeChildren n)
  where
    go (ElemToken t) = [t]
    go (ElemNode m) = tokens m

-- | An element together with its absolute span.
data Positioned = Positioned
  { posSpan :: !SrcSpan,
    posKind :: !SyntaxKind,
    posDepth :: !Int,
    posText :: !(Maybe Text) -- tokens only
  }
  deriving stock (Eq, Show)

-- | Pre-order list of every node and token with absolute spans.
withPositions :: FileId -> Node -> [Positioned]
withPositions fid = goNode 0 0
  where
    goNode depth start n =
      Positioned (mkSpan fid start (start + nodeWidth n)) (nodeKind n) depth Nothing
        : goChildren (depth + 1) start (nodeChildren n)
    goChildren _ _ [] = []
    goChildren depth start (e : es) =
      let here = case e of
            ElemNode m -> goNode depth start m
            ElemToken t ->
              [Positioned (mkSpan fid start (start + utf8Length (tokText t))) (tokKind t) depth (Just (tokText t))]
       in here <> goChildren depth (start + elementWidth e) es

-- | Indented debug form used by golden tests and @golem inspect@.
pretty :: Node -> Text
pretty root = T.unlines (map line (withPositions (FileId 0) root))
  where
    line p =
      T.replicate (2 * posDepth p) " "
        <> T.pack (show (posKind p))
        <> "@"
        <> T.pack (show (spanStart (posSpan p)))
        <> ".."
        <> T.pack (show (spanEnd (posSpan p)))
        <> maybe "" (\t -> " \"" <> T.concatMap esc t <> "\"") (posText p)
    esc '\n' = "\\n"
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = T.singleton c
