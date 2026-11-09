{- | The functions of a program as .gm uses them (docs/adr/0162): the table
of golem-eval of each module, whose calls give the values of .gm to the
functions and put back what they return, and the filters.

The values of .gm become values of .emet as the table of the ADR maps
them (golem-eval checks them first), the prose slots and the body become
values of the data types of the IR ('Golem.Emet.IR'), and what a
function returns is checked by the invariants of the IR as the output of
a plugin is (E06104).
-}
module Golem.Emet.Gm
  ( functionNamespaces,
    filterOf,
    filterFuel,
  )
where

import Data.Int (Int64)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Doc.Validate (validateBlocks, validateDocument, validateInlines)
import Golem.Emet
import Golem.Emet.IR
import Golem.Emet.Types (Ty (..))
import Golem.Eval.Functions
import Golem.Eval.Value (Value (..))
import Golem.Syntax

-- | The namespace of each module of the program, by its path.
functionNamespaces :: Handlers -> Program -> Map FilePath FunctionNamespace
functionNamespaces hs p =
  Map.mapWithKey
    ( \path exports ->
        FunctionNamespace
          { fnInline = Map.fromList [(exName e, inlineFunction hs p e) | e <- exports, exKind e == KindInline],
            fnBlock = Map.fromList [(exName e, blockFunction hs p e) | e <- exports, exKind e == KindBlock],
            fnExpr = Map.fromList [(exName e, f) | e <- exports, exKind e == KindFn, Just f <- [exprFunction hs p e]],
            fnOthers = Map.findWithDefault Map.empty path (programOthers p)
          }
    )
    (programExports p)

-- | What a function takes from .gm.
paramsOf :: Export -> Params
paramsOf e =
  Params
    [t | ArgPositional t <- exArgs e]
    (case [t | ArgVarargs t <- exArgs e] of t : _ -> Just t; [] -> Nothing)
    [KeywordParam n t d | ArgKeyword n t d <- exArgs e]

-- | A value of .gm as one of .emet.
toResult :: Value -> Result
toResult = \case
  VArray xs -> RList (map toResult xs)
  v -> RPrim v

-- | A value of .emet a pub fn returns as one of .gm.
fromResult :: Result -> Maybe Value
fromResult = \case
  RPrim v -> Just v
  RList xs -> VArray <$> traverse fromResult xs
  _ -> Nothing

{- | The arguments of a call in the order of the signature: the values of
.gm (the positional ones, the variable ones as one array, the keyword
ones), then the prose slots or the body.
-}
arguments :: Export -> [Value] -> [Enc Result] -> Enc [Result]
arguments e = go (exArgs e)
  where
    go [] _ _ = pure []
    go (a : as) vs rs = case a of
      ArgProse -> slot as vs rs
      ArgBody -> slot as vs rs
      _ -> case vs of
        v : more -> (toResult v :) <$> go as more rs
        [] -> go as [] rs
    slot as vs = \case
      r : more -> (:) <$> r <*> go as vs more
      [] -> go as vs []

-- | E06104 at the call: an output against the invariants of the IR.
invalid :: SrcSpan -> Export -> Text -> Diagnostic
invalid sp e why = diagnostic "E06104" Error sp ("関数の出力が意味論 IR の規則に反しています（" <> exPath' <> " の " <> exFunction e <> "）: " <> why)
  where
    exPath' = T.pack (exPath e)

inlineFunction :: Handlers -> Program -> Export -> InlineFunction
inlineFunction hs p e = InlineFunction (paramsOf e) (length [() | ArgProse <- exArgs e]) (exSignature e) $ \vals slots sp ->
  let (args, carried) = runEnc (arguments e vals (map encodeInlines slots))
   in case callFunction hs p sp (exPath e) (exFunction e) args of
        Left d -> Left [d]
        Right r -> case decodeInlines carried sp r of
          Left why -> Left [invalid sp e why]
          Right out -> case validateInlines (const (Just maxBound)) (carriedDeferred carried) out of
            [] -> Right out
            errs -> Left [invalid sp e (T.intercalate "、" errs)]

blockFunction :: Handlers -> Program -> Export -> BlockFunction
blockFunction hs p e = BlockFunction (paramsOf e) (not (null [() | ArgBody <- exArgs e])) (exSignature e) $ \vals body sp ->
  let (args, carried) = runEnc (arguments e vals [encodeBlocks body | ArgBody <- exArgs e])
   in case callFunction hs p sp (exPath e) (exFunction e) args of
        Left d -> Left [d]
        Right r -> case decodeBlocks carried sp r of
          Left why -> Left [invalid sp e why]
          Right out ->
            let made = filter (`notElem` body) out
             in case concatMap blockKind made <> validateBlocks (const (Just maxBound)) (carriedDeferred carried) out of
                  [] -> Right out
                  errs -> Left [invalid sp e (T.intercalate "、" errs)]

exprFunction :: Handlers -> Program -> Export -> Maybe ExprFunction
exprFunction hs p e = case gmResult (exResult e) of
  Nothing -> Nothing
  Just t -> Just $ ExprFunction (paramsOf e) t (exSignature e) $ \vals sp ->
    let (args, _) = runEnc (arguments e vals [])
     in case callFunction hs p sp (exPath e) (exFunction e) args of
          Left d -> Left d
          Right r -> maybe (Left (diagnostic "E06101" Error sp ("pub fn が .gm の値に写せない値を返しました: " <> exFunction e))) Right (fromResult r)

-- | The type of the result of a pub fn as .gm sees it.
gmResult :: Ty -> Maybe ArgType
gmResult = \case
  TC "Nat" [] -> Just ArgNat
  TC "Int" [] -> Just ArgInt
  TC "Rat" [] -> Just ArgRat
  TC "String" [] -> Just ArgString
  TC "Bool" [] -> Just ArgBool
  TC "List" [t] -> ArgList <$> gmResult t
  _ -> Nothing

{- | The kinds of blocks a block command makes, at any depth, as those of
a plugin (docs/adr/0122): no heading, no list of a channel, no break and
no blank lines; and no figure, whose image the evaluation has not read.
-}
blockKind :: Block -> [Text]
blockKind (Block _ _ _ body) = case body of
  Paragraph _ _ -> []
  TableBlock _ -> []
  CodeBlock _ -> []
  BulletList items -> concatMap (concatMap blockKind . itemBlocks) items
  OrderedList items -> concatMap (concatMap blockKind . itemBlocks) items
  DefList gs -> concatMap (concatMap (concatMap blockKind) . dgDefs) gs
  Heading {} -> refuse "見出し"
  FigureBlock _ -> refuse "図版"
  ChannelOutput _ -> refuse "一覧の出力"
  ForcedBreak _ -> refuse "改ページ"
  PageControl _ -> refuse "改ページの制御"
  BlankLines _ -> refuse "行アキ"
  where
    refuse k = ["ブロックコマンドが返せないブロックです: " <> k]

{- | The most steps of a filter over a .gm of this many bytes (docs/adr/0162):
the limit of a command and 10000 steps for each byte, as the fuel of the
filters of plugins (docs/adr/0124). Found as an Integer, at most the
largest Int64, so that it does not wrap round where Int has 32 bits
(wasm32, docs/adr/0223).
-}
filterFuel :: Int -> Int64
filterFuel bytes = fromInteger (min (toInteger (maxBound :: Int64)) (toInteger stepLimit + 10000 * toInteger bytes))

{- | The filter of a name of a module of the program: given the size of the
.gm in bytes, the document of the file and what it returns. A node the
filter makes takes the top of the file; the output is checked as a
document (E06104), and a figure it did not get is refused, as its image
is not read.
-}
filterOf :: Handlers -> Program -> FilePath -> Text -> Maybe (Int -> Document -> Either [Diagnostic] Document)
filterOf hs p path name = case [e | e <- Map.findWithDefault [] path (programExports p), exKind e == KindFilter, exName e == name] of
  e : _ -> Just $ \bytes doc ->
    let top = mkSpan (docFile doc) 0 0
        (arg, carried) = runEnc (encodeBlocks (docBlocks doc))
     in case callFunctionLimited (filterFuel bytes) hs p top path (exFunction e) [arg] of
          Left d -> Left [d]
          Right r -> case decodeBlocks carried top r of
            Left why -> Left [invalid top e why]
            Right out ->
              let doc' = Document (docFile doc) out
                  figures = [b | b@(Block _ _ _ (FigureBlock _)) <- allBlocks (docBlocks doc)]
                  newFigures = [() | b@(Block _ _ _ (FigureBlock _)) <- allBlocks out, b `notElem` figures]
               in case ["フィルタが作った図版です" | not (null newFigures)] <> validateDocument (const (Just maxBound)) (carriedDeferred carried) doc' of
                    [] -> Right doc'
                    errs -> Left [invalid top e (T.intercalate "、" errs)]
  [] -> Nothing
  where
    allBlocks = concatMap (\b -> b : allBlocks (inner b))
    inner (Block _ _ _ body) = case body of
      BulletList items -> concatMap itemBlocks items
      OrderedList items -> concatMap itemBlocks items
      DefList gs -> concat (concatMap dgDefs gs)
      FigureBlock f -> figCaption f
      _ -> []
