{- | The abstract syntax of .emet (docs/adr/0160). Every node carries the
byte range of its source ('Loc'); the ranges take no part in equality, so
that two sources that differ in layout alone have equal trees (the fmt
property of docs/adr/0160).
-}
module Golem.Emet.Syntax
  ( Loc (..),
    (<->),
    Name,
    QName (..),
    qnameText,
    Module (..),
    Decl (..),
    Signature (..),
    Equation (..),
    Rhs (..),
    Guard (..),
    GuardCond (..),
    Where (..),
    Binding (..),
    ConDecl (..),
    TypeE (..),
    RowE (..),
    ReqE (..),
    Pat (..),
    Expr (..),
    Alt (..),
    BinOp (..),
    exprLoc,
    patLoc,
    rhsLoc,
    whereLoc,
    typeLoc,
    binOpText,
  )
where

import Data.Text (Text)
import Golem.Eval.Value (Value)

{- | A half-open range of UTF-8 bytes in one .emet file. Every range equals
every other one, so that trees compare by their shape alone.
-}
data Loc = Loc {locStart :: !Int, locEnd :: !Int}
  deriving stock (Show)

instance Eq Loc where
  _ == _ = True

-- | The range from the start of the first to the end of the second.
(<->) :: Loc -> Loc -> Loc
Loc s _ <-> Loc _ e = Loc s e

type Name = Text

{- | A name, with the built-in module it belongs to (@String.all@). The
names of an import have no module (docs/adr/0160).
-}
data QName = QName !(Maybe Name) !Name
  deriving stock (Eq, Ord, Show)

qnameText :: QName -> Text
qnameText (QName q n) = maybe n (\m -> m <> "." <> n) q

newtype Module = Module [Decl]
  deriving stock (Eq, Show)

data Decl
  = -- | the whole declaration, the path and the range of the path
    DImport !Loc !Text !Loc
  | DSig !Signature
  | DEq !Equation
  | {- | @pub@, the name, its parameters and the constructors in the order
    they are declared (the order a derived comparison would take)
    -}
    DData !Loc !Bool !Name ![Name] ![ConDecl]
  | -- | @pub@, the name, its parameters and the type it names
    DType !Loc !Bool !Name ![Name] !TypeE
  deriving stock (Eq, Show)

data Signature = Signature
  { sigLoc :: !Loc,
    sigPub :: !Bool,
    sigName :: !Name,
    sigNameLoc :: !Loc,
    -- | the row written right after @::@ (docs/adr/0161)
    sigRow :: !(Maybe RowE),
    sigType :: !TypeE
  }
  deriving stock (Eq, Show)

{- | One equation: the name, the patterns of the arguments, the right-hand
side and the @where@ blocks written after it. A function has at most one
@where@, after its last equation; the parser keeps every one so that the
checker can report the misplaced ones (E01103).
-}
data Equation = Equation
  { eqLoc :: !Loc,
    eqName :: !Name,
    eqNameLoc :: !Loc,
    eqPats :: ![Pat],
    eqRhs :: !Rhs,
    eqWheres :: ![Where]
  }
  deriving stock (Eq, Show)

data Rhs
  = Plain !Expr
  | -- | guards, each with the @where@ blocks written after it
    Guarded ![(Guard, [Where])]
  deriving stock (Eq, Show)

data Guard = Guard
  { guardLoc :: !Loc,
    guardCond :: !GuardCond,
    guardBody :: !Expr
  }
  deriving stock (Eq, Show)

data GuardCond = GOtherwise !Loc | GExpr !Expr
  deriving stock (Eq, Show)

data Where = Where !Loc ![Binding]
  deriving stock (Eq, Show)

-- | A binding of @where@: a signature, or an equation of a value or a local function.
data Binding
  = BSig !Signature
  | BEq !Equation
  deriving stock (Eq, Show)

-- | A constructor: positional fields, or named ones (a record).
data ConDecl
  = ConPos !Loc !Name ![TypeE]
  | ConRec !Loc !Name ![(Name, TypeE)]
  deriving stock (Eq, Show)

data TypeE
  = TCon !Loc !QName ![TypeE]
  | TVar !Loc !Name
  | -- | an arrow, with the row of requirements written after it (docs/adr/0161)
    TFun !TypeE !(Maybe RowE) !TypeE
  | -- | a tuple of two types or more
    TTuple !Loc ![TypeE]
  deriving stock (Eq, Show)

{- | A row of requirements (docs/adr/0161): @<file "a.tsv", file "b.tsv"|e>@,
or a variable alone (@e@ before a type). The requirements are in the
order they are written.
-}
data RowE = RowE
  { rowLoc :: !Loc,
    rowReqs :: ![ReqE],
    -- | the variable after @|@, or the variable alone, and its range
    rowTail :: !(Maybe (Name, Loc))
  }
  deriving stock (Eq, Show)

-- | A requirement as written: its kind and the string literals after it (@file "a.tsv"@).
data ReqE = ReqE
  { reqLoc :: !Loc,
    reqKind :: !Name,
    reqArgs :: ![Text]
  }
  deriving stock (Eq, Show)

data Pat
  = PVar !Loc !Name
  | PWild !Loc
  | PNum !Loc !Value
  | PStr !Loc !Text
  | PChar !Loc !Char
  | PCon !Loc !QName ![Pat]
  | PList !Loc ![Pat]
  | -- | @(x : xs)@
    PCons !Loc !Pat !Pat
  | -- | a tuple of two patterns or more
    PTuple !Loc ![Pat]
  | PRec !Loc !QName ![(Name, Pat)]
  deriving stock (Eq, Show)

data BinOp
  = OpAdd
  | OpSub
  | OpMul
  | OpDiv
  | OpMod
  | OpPow
  | OpEq
  | OpNe
  | OpLt
  | OpLe
  | OpGt
  | OpGe
  | OpAnd
  | OpOr
  | OpAppend
  | -- | @:@ of lists
    OpCons
  deriving stock (Eq, Ord, Show, Enum, Bounded)

binOpText :: BinOp -> Text
binOpText = \case
  OpAdd -> "+"
  OpSub -> "-"
  OpMul -> "*"
  OpDiv -> "/"
  OpMod -> "%"
  OpPow -> "**"
  OpEq -> "=="
  OpNe -> "/="
  OpLt -> "<"
  OpLe -> "<="
  OpGt -> ">"
  OpGe -> ">="
  OpAnd -> "&&"
  OpOr -> "||"
  OpAppend -> "++"
  OpCons -> ":"

data Expr
  = EVar !Loc !QName
  | ECon !Loc !QName
  | ENum !Loc !Value
  | EStr !Loc !Text
  | EChar !Loc !Char
  | EList !Loc ![Expr]
  | -- | a tuple of two expressions or more
    ETuple !Loc ![Expr]
  | EApp !Expr !Expr
  | EBin !Loc !BinOp !Expr !Expr
  | ENeg !Loc !Expr
  | ECase !Loc !Expr ![Alt]
  | -- | @c ? a : b@
    ETernary !Loc !Expr !Expr !Expr
  | ERecord !Loc !QName ![(Name, Loc, Expr)]
  | EParen !Loc !Expr
  deriving stock (Show)

-- | Parentheses take no part in equality.
instance Eq Expr where
  a == b = case (unparen a, unparen b) of
    (EVar _ x, EVar _ y) -> x == y
    (ECon _ x, ECon _ y) -> x == y
    (ENum _ x, ENum _ y) -> x == y
    (EStr _ x, EStr _ y) -> x == y
    (EChar _ x, EChar _ y) -> x == y
    (EList _ xs, EList _ ys) -> xs == ys
    (ETuple _ xs, ETuple _ ys) -> xs == ys
    (EApp f x, EApp g y) -> f == g && x == y
    (EBin _ o x y, EBin _ p z w) -> o == p && x == z && y == w
    (ENeg _ x, ENeg _ y) -> x == y
    (ECase _ x as, ECase _ y bs) -> x == y && as == bs
    (ETernary _ c x y, ETernary _ d z w) -> c == d && x == z && y == w
    (ERecord _ c fs, ERecord _ d gs) -> c == d && fs == gs
    _ -> False
    where
      unparen = \case
        EParen _ e -> unparen e
        e -> e

data Alt = Alt
  { altLoc :: !Loc,
    altPat :: !Pat,
    altRhs :: !Rhs,
    altWheres :: ![Where]
  }
  deriving stock (Eq, Show)

exprLoc :: Expr -> Loc
exprLoc = \case
  EVar l _ -> l
  ECon l _ -> l
  ENum l _ -> l
  EStr l _ -> l
  EChar l _ -> l
  EList l _ -> l
  ETuple l _ -> l
  EApp f x -> exprLoc f <-> exprLoc x
  EBin l _ _ _ -> l
  ENeg l _ -> l
  ECase l _ _ -> l
  ETernary l _ _ _ -> l
  ERecord l _ _ -> l
  EParen l _ -> l

patLoc :: Pat -> Loc
patLoc = \case
  PVar l _ -> l
  PWild l -> l
  PNum l _ -> l
  PStr l _ -> l
  PChar l _ -> l
  PCon l _ _ -> l
  PList l _ -> l
  PCons l _ _ -> l
  PTuple l _ -> l
  PRec l _ _ -> l

typeLoc :: TypeE -> Loc
typeLoc = \case
  TCon l _ _ -> l
  TVar l _ -> l
  TFun a _ b -> typeLoc a <-> typeLoc b
  TTuple l _ -> l

rhsLoc :: Rhs -> Loc
rhsLoc = \case
  Plain e -> exprLoc e
  Guarded gs -> case (gs, reverse gs) of
    ((g, _) : _, (h, ws) : _) -> foldl (\l w -> l <-> whereLoc w) (guardLoc g <-> guardLoc h) ws
    _ -> Loc 0 0

whereLoc :: Where -> Loc
whereLoc (Where l _) = l
