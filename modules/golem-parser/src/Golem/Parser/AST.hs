{- | The abstract syntax tree (golem-parser ADR 0005): the meaning of the
source before evaluation. Trivia and escapes are already resolved. A
newline inside a paragraph or a prose slot stays as 'SoftBreak'; the
evaluation drops it except in the body of @verse (docs/adr ADR 0003).
-}
module Golem.Parser.AST
  ( File (..),
    Located (..),
    Name,
    Block (..),
    ListItem,
    DefGroup (..),
    Alignment (..),
    Inline (..),
    Argument (..),
    ArgValue (..),
    Expr (..),
    UnaryOp (..),
    BinaryOp (..),
  )
where

import Data.Text (Text)
import Golem.Syntax.Span

data File = File {fileId :: !FileId, fileBlocks :: ![Located Block]}
  deriving stock (Eq, Show)

data Located a = Located {locSpan :: !SrcSpan, locValue :: !a}
  deriving stock (Eq, Show, Functor)

type Name = Text

data Block
  = Paragraph [Located Inline]
  | Heading !Int [Located Inline]
  | BulletList [ListItem]
  | OrderedList [ListItem]
  | DefList [DefGroup]
  | Table [Alignment] [[Located Inline]] [[[Located Inline]]]
  | CodeBlock (Maybe Text) Text
  | SetVar (Located Name) (Located Expr)
  | BlockCommand (Located Name) [Located Argument] [Located Block]
  | Attributed [Located Block] (Maybe (Located Block))
  | ErrorBlock
  deriving stock (Eq, Show)

-- | The first block of an item is the paragraph on the marker line.
type ListItem = [Located Block]

data DefGroup = DefGroup
  { dgTerms :: [[Located Inline]],
    dgDefs :: [[Located Block]]
  }
  deriving stock (Eq, Show)

data Alignment = AlignDefault | AlignLeft | AlignCenter | AlignRight
  deriving stock (Eq, Show)

data Inline
  = Text Text
  | SoftBreak
  | Expr (Located Expr)
  | Command (Located Name) [Located Argument] [[Located Inline]]
  | ProofComment Text
  | ErrorInline
  deriving stock (Eq, Show)

data Argument
  = Positional ArgValue
  | Keyword (Located Name) ArgValue
  | SplatPositional (Located Expr)
  | SplatKeyword (Located Expr)
  deriving stock (Eq, Show)

data ArgValue
  = Word Text
  | StringLit Text
  | ExprArg (Located Expr)
  | CommandArg (Located Inline)
  deriving stock (Eq, Show)

data Expr
  = EInt Integer
  | EFloat Double
  | EString Text
  | EBool Bool
  | ENil
  | EArray [Located Expr]
  | EHash [(Text, Located Expr)]
  | EVar [Name]
  | ECall Name [Located Expr]
  | EUnary UnaryOp (Located Expr)
  | EBinary BinaryOp (Located Expr) (Located Expr)
  | EError
  deriving stock (Eq, Show)

data UnaryOp = Negate
  deriving stock (Eq, Show)

data BinaryOp = Add | Sub | Mul | Div | Mod | Pow | OpEq | OpNe | OpLt | OpLe | OpGt | OpGe
  deriving stock (Eq, Show)
