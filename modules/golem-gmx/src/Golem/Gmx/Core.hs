{- | The checked program (docs/adr/0148): every name is resolved, records
are positional, and @True@ and @False@ are the values of the expression
context. The evaluator runs this form.
-}
module Golem.Gmx.Core
  ( GKey,
    CExpr (..),
    CAlt (..),
    CRhs (..),
    CPat (..),
    CEq (..),
    CBind (..),
    CFun (..),
    Global (..),
  )
where

import Data.Text (Text)
import Golem.Eval.Value (Value)
import Golem.Gmx.Syntax (BinOp, Loc, Name)

-- | A top-level function: the path of its module and its name.
type GKey = (FilePath, Name)

data CExpr
  = CLocal !Name
  | CGlobal !Loc !GKey
  | -- | a constructor and its arity
    CConV !Name !Int
  | CLit !Value
  | CList ![CExpr]
  | -- | the application of a function to one argument or more
    CApp !Loc !CExpr ![CExpr]
  | CBin !Loc !BinOp !CExpr !CExpr
  | CNeg !Loc !CExpr
  | CCase !CExpr ![CAlt]
  | CTern !CExpr !CExpr !CExpr
  deriving stock (Show)

data CAlt = CAlt !CPat !CRhs
  deriving stock (Show)

-- | A body, or guards (Nothing for otherwise) and their bodies.
data CRhs = CPlain !CExpr | CGuards ![(Maybe CExpr, CExpr)]
  deriving stock (Show)

data CPat
  = CPVar !Name
  | CPWild
  | CPLit !Value
  | CPCon !Name ![CPat]
  | CPList ![CPat]
  deriving stock (Show)

data CEq = CEq ![CPat] !CRhs
  deriving stock (Show)

{- | A binding of @where@: a value (arity 0, strict or @lazy@) or a local
function.
-}
data CBind = CBind
  { cbName :: !Name,
    cbLazy :: !Bool,
    cbArity :: !Int,
    cbEqs :: ![CEq],
    -- | the line of the binding, from 1
    cbLine :: !Int
  }
  deriving stock (Show)

data CFun = CFun
  { cfName :: !Name,
    cfPath :: !FilePath,
    -- | the line of the declaration, from 1
    cfLine :: !Int,
    cfArity :: !Int,
    cfEqs :: ![CEq],
    cfWhere :: ![CBind]
  }
  deriving stock (Show)

-- | A top-level function: written in .gmx, or a primitive of a built-in module.
data Global
  = GFun !CFun
  | GPrim !Text !Int
  deriving stock (Show)
