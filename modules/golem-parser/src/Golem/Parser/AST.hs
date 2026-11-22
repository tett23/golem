{- | The abstract syntax tree (golem-parser ADR 0005): the meaning of the
source before evaluation. Trivia is already removed; an escaped character
stays as 'Escaped', which the evaluation makes text with 'plainEscapes'
after it has read the separators (golem-parser ADR 0010). A
newline inside a paragraph or a prose slot stays as 'SoftBreak'; the
evaluation drops it except in the body of @style verse (docs/adr ADR 0003).
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
    plainEscapes,
    plainEscapesIn,
    shorthandsAsText,
    joinText,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Syntax.Span
import Numeric.Natural (Natural)

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
  | -- | the language, the arguments after it and the lines with their spans (golem-driver ADR 0023)
    CodeBlock (Maybe Text) [Located Argument] [Located Text]
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
  | -- | a character written after a backslash (golem-parser ADR 0010)
    Escaped Char
  | SoftBreak
  | -- | a backslash at the end of a line: the line breaks in the paragraph (docs/adr ADR 0016)
    HardBreak
  | Expr (Located Expr)
  | Command (Located Name) [Located Argument] [[Located Inline]]
  | ProofComment Text
  | {- | ##…## (golem-parser ADR 0011): the source text from the opening
    ## to the closing ## or to where it stopped without one
    -}
    NumberShorthand Text
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

{- | An expression. The three number literals are the three number types
(docs/adr ADR 0101): the parser makes 'ENat' of an integer literal and
'ERat' of a decimal or an exponent; 'EInt' comes from an S0 value put
back into an expression and from the output of a plugin.
-}
data Expr
  = ENat Natural
  | EInt Integer
  | ERat Rational
  | EString Text
  | EBool Bool
  | ENil
  | EArray [Located Expr]
  | EHash [(Text, Located Expr)]
  | EVar [Name]
  | ECall Name [Located Expr]
  | EUnary UnaryOp (Located Expr)
  | EBinary BinaryOp (Located Expr) (Located Expr)
  | -- | the closed range a...b, both ends included (docs/adr ADR 0113)
    ERange (Located Expr) (Located Expr)
  | EError
  deriving stock (Eq, Show)

data UnaryOp = Negate
  deriving stock (Eq, Show)

data BinaryOp = Add | Sub | Mul | Div | Mod | Pow | OpEq | OpNe | OpLt | OpLe | OpGt | OpGe
  deriving stock (Eq, Show)

{- | Escaped characters as text, joined with the text around them
(golem-parser ADR 0010). Only the top level of the inlines: the slots of
a command are made plain when the command is evaluated.
-}
plainEscapes :: [Located Inline] -> [Located Inline]
plainEscapes = joinText . map plain
  where
    plain = \case
      Located sp (Escaped c) -> Located sp (Text (T.singleton c))
      other -> other

{- | Every ##…## in the inlines, in the prose slots of the commands in
them and in their command arguments, as the text it was written with
(golem-parser ADR 0011), joined with the text around it.
-}
shorthandsAsText :: [Located Inline] -> [Located Inline]
shorthandsAsText = joinText . map (fmap inline)
  where
    inline = \case
      NumberShorthand t -> Text t
      Command n args slots -> Command n (map (fmap argument) args) (map shorthandsAsText slots)
      other -> other
    argument = \case
      Positional v -> Positional (value v)
      Keyword k v -> Keyword k (value v)
      other -> other
    value = \case
      CommandArg i -> CommandArg (fmap inline i)
      other -> other

{- | Neighbouring 'Text' joined into one, whose span covers both; 'Escaped' is not
joined (golem-parser ADR 0010).
-}
joinText :: [Located Inline] -> [Located Inline]
joinText (Located a (Text x) : Located b (Text y) : rest) =
  joinText (Located (mkSpan (spanFile a) (spanStart a) (spanEnd b)) (Text (x <> y)) : rest)
joinText (x : rest) = x : joinText rest
joinText [] = []

{- | The escaped characters that match made text, everywhere in a file:
in every block, slot and argument (golem-parser ADR 0010). The formatter
compares the ASTs with the escapes it may remove made text.
-}
plainEscapesIn :: (Char -> Bool) -> File -> File
plainEscapesIn p (File fid bs) = File fid (map (fmap block) bs)
  where
    block = \case
      Paragraph is -> Paragraph (inlines is)
      Heading l is -> Heading l (inlines is)
      BulletList items -> BulletList (map (map (fmap block)) items)
      OrderedList items -> OrderedList (map (map (fmap block)) items)
      DefList gs -> DefList [DefGroup (map inlines ts) (map (map (fmap block)) ds) | DefGroup ts ds <- gs]
      Table al h rows -> Table al (map inlines h) (map (map inlines) rows)
      BlockCommand n args body -> BlockCommand n (map (fmap argument) args) (map (fmap block) body)
      Attributed cs t -> Attributed (map (fmap block) cs) (fmap (fmap block) t)
      other -> other
    inlines = joinText . map (fmap inline)
    inline = \case
      Escaped c | p c -> Text (T.singleton c)
      Command n args slots -> Command n (map (fmap argument) args) (map inlines slots)
      other -> other
    argument = \case
      Positional v -> Positional (value v)
      Keyword k v -> Keyword k (value v)
      other -> other
    value = \case
      CommandArg i -> CommandArg (fmap inline i)
      other -> other
