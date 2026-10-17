{- | File evaluation, S0 (golem-eval ADR 0002): one source file and its
imports become semantic IR. Values that need the whole document (S1) or
the layout (S2) are left as 'Ref' and 'Deferred' inlines.
-}
module Golem.Eval.File
  ( EvalContext (..),
    Asset (..),
    PluginHook (..),
    PluginCommand (..),
    noPlugins,
    Usage (..),
    EvalResult (..),
    evalFile,
    builtinInlineCommands,
    overridableCommands,
    kentenShapes,
    joinSoftBreaks,
    splitLines,
    duplicateKeys,
  )
where

import Control.Monad (forM, unless)
import Control.Monad.State.Strict
import Data.Char (isAscii, isAsciiLower, isDigit)
import Data.Either (fromLeft, fromRight, isLeft)
import Data.List (mapAccumL, partition)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, mapMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Builtin
import Golem.Eval.Expr
import Golem.Eval.RegexStyle (applyRegexStyles, regexRules)
import Golem.Eval.Settings
import Golem.Eval.Value
import Golem.Parser.AST qualified as A
import Golem.Parser.SourceSettings
import Golem.Project.Imports (ImportSite (..), importSite)
import Golem.Project.Paths (PathError (..), pathErrorMessage)
import Golem.Project.Style (Dim (..), LineBreaks (..), LocalStyles (..), Style, kentenShapeNames, noLocalStyles, paraLineBreaks, parseAki, parseDim, withLocalStyles)
import Golem.Syntax

-- | The call of one plugin command.
newtype PluginCommand = PluginCommand
  { -- | the output and the plugin's own diagnostics, or errors
    pcCall :: [Value] -> [[Inline]] -> SrcSpan -> Either [Diagnostic] ([Inline], [Diagnostic])
  }

{- | Plugin commands and filters, provided by golem-plugin. The keys tell an
override of a built-in command from a command of its own (docs/adr ADR 0027).
-}
data PluginHook = PluginHook
  { phOverrides :: !(Map OverridableBuiltin PluginCommand),
    phCommands :: !(Map PluginCommandName PluginCommand),
    phApplyFilters :: FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic])
  }

noPlugins :: PluginHook
noPlugins = PluginHook Map.empty Map.empty (\_ d -> Right (d, []))

data EvalContext = EvalContext
  { ctxFile :: !FileId,
    ctxPath :: !FilePath,
    ctxProfile :: !Profile,
    ctxMeta :: !(Map Text Value),
    ctxImports :: !(Map FilePath (Map Text Value)), -- exported variables by file
    ctxSwatches :: !(Set Text),
    -- | the character styles, built-in ones included (docs/adr ADR 0005)
    ctxCharStyles :: !(Set Text),
    -- | the paragraph styles and whether they keep their lines (docs/adr ADR 0005)
    ctxParaStyles :: !(Map Text LineBreaks),
    ctxDefaultKenten :: !Text,
    ctxCiteKeys :: !(Set Text),
    -- | the files @figure, @table and @listing refer to; a path not in it is missing
    ctxAssets :: !(Map FilePath Asset),
    ctxPlugins :: !PluginHook,
    -- | how the file is read (docs/adr ADR 0013)
    ctxSource :: !SourceSettings,
    -- | style.toml as read, which the @style-def of a file is laid over (docs/adr ADR 0014)
    ctxStyle :: !Style
  }

-- | A file referenced by @figure, @table or @listing (golem-eval ADR 0003).
data Asset
  = -- | read as text, for a table or a listing
    AssetText !Text
  | -- | present, and not read
    AssetPresent
  | -- | a path that cannot be used: absolute, a URL, outside the root, or missing
    AssetInvalid !PathError
  deriving stock (Eq, Show)

data Usage = Usage
  { usageDefined :: ![(Text, SrcSpan)],
    usageReferenced :: !(Set Text),
    usageNamespaceRefs :: !(Map Text (Set Text)),
    usageImports :: ![(Text, FilePath, SrcSpan)]
  }
  deriving stock (Eq, Show)

data EvalResult = EvalResult
  { erDocument :: !Document,
    erExports :: !(Map Text Value),
    erUsage :: !Usage,
    erDiagnostics :: ![Diagnostic],
    -- | the settings that applied to the file (docs/adr ADR 0013)
    erSource :: !SourceSettings,
    -- | the styles the file defines (docs/adr ADR 0014)
    erStyles :: !LocalStyles,
    -- | the line of each @number by the span of the block it numbers (G0407, golem-syntax ADR 0002)
    erNumberSites :: !(Map SrcSpan SrcSpan)
  }

data St = St
  { stVars :: !(Map Text Value),
    stNamespaces :: !(Map Text (Map Text Value)),
    stDefined :: ![(Text, SrcSpan)],
    stRefs :: !(Set Text),
    stNsRefs :: !(Map Text (Set Text)),
    stImports :: ![(Text, FilePath, SrcSpan)],
    stNote :: !Int,
    stSidenote :: !Int,
    stDiags :: ![Diagnostic],
    -- | the line of each @number by the span of its block (G0407)
    stNumberSites :: !(Map SrcSpan SrcSpan)
  }

type M = State St

report :: Diagnostic -> M ()
report d = modify' (\s -> s {stDiags = stDiags s <> [d]})

err :: Text -> SrcSpan -> Text -> M ()
err code sp msg = report (diagnostic code Error sp msg)

builtinInlineCommands :: [Text]
builtinInlineCommands = map builtinName allBuiltins

-- | Built-in commands a plugin may override when the manifest says so.
overridableCommands :: [Text]
overridableCommands = [builtinName b | b@(Overridable _) <- allBuiltins]

attributeCommands :: [Text]
attributeCommands = ["label", "toc-title", "number", "nonumber", "notoc", "style", "caption"]

-- | The shapes of kenten (golem-driver ADR 0019); an unknown one is G0239.
kentenShapes :: [Text]
kentenShapes = kentenShapeNames

reservedNames :: [Text]
reservedNames = ["doc", "meta", "true", "false", "nil"]

evalFile :: EvalContext -> A.File -> EvalResult
evalFile ctx0 (A.File fid blocks0) =
  let -- the file settings (docs/adr ADR 0014): @manifest over the [source] of the context, and @style-def
      (header, rest) = fileHeader blocks0
      (source, settingDiags) = fileSettings sourceKeys (ctxSource ctx0) header
      (local, styleDiags) = fileStyles (ctxStyle ctx0) header
      ctx = (withFileStyles local ctx0) {ctxSource = source}
      blocks = map normalizeBlock (splitLines (ctxSource ctx) (ctxParaStyles ctx) rest)
      st0 = St Map.empty (Map.singleton "meta" (ctxMeta ctx)) [] Set.empty Map.empty [] 0 0 (settingDiags <> styleDiags) Map.empty
      (bs0, st) = runState (concat <$> mapM (evalBlock ctx) blocks) st0
      (bs, breakDiags) = nestedBreaks bs0
      doc0 = Document fid bs
      (doc, filterDiags) = case phApplyFilters (ctxPlugins ctx) (ctxPath ctx) doc0 of
        Left ds -> (doc0, ds)
        Right (d, ws) -> (d, ws <> unknownParaStyles ctx d)
      -- the regex styles last, so that the text of filters is matched too (docs/adr ADR 0015)
      rules = regexRules (withLocalStyles (ctxStyle ctx0) local)
   in EvalResult
        { erDocument = applyRegexStyles rules doc,
          erExports = stVars st,
          erUsage = Usage (stDefined st) (stRefs st) (stNsRefs st) (stImports st),
          erDiagnostics = stDiags st <> breakDiags <> filterDiags,
          erSource = ctxSource ctx,
          erStyles = local,
          erNumberSites = stNumberSites st
        }

{- | The context with the styles of the file over those of style.toml
(docs/adr ADR 0014): its character styles added, and whether each
paragraph style keeps its lines resolved again, as an override may change
the styles based on it.
-}
withFileStyles :: LocalStyles -> EvalContext -> EvalContext
withFileStyles local ctx
  | local == noLocalStyles = ctx
  | otherwise =
      ctx
        { ctxCharStyles = Set.union (Map.keysSet (lsCharStyles local)) (ctxCharStyles ctx),
          ctxParaStyles = Map.union (paraLineBreaks (withLocalStyles (ctxStyle ctx) local)) (ctxParaStyles ctx)
        }

-- ------------------------------------------------------------------ newlines

{- | 'A.SoftBreak' removed and the neighbouring 'A.Text' joined into one,
whose span covers both (docs/adr ADR 0003). Inlines nested in commands
are joined too.
-}
joinSoftBreaks :: [A.Located A.Inline] -> [A.Located A.Inline]
joinSoftBreaks = mergeLocated . dropSoft False . map nestedInline
  where
    -- 'A.HardBreak' stays (docs/adr ADR 0016), and so does a newline right
    -- after it: the line after the hard break is empty, which the
    -- evaluation reports
    dropSoft afterHard = \case
      [] -> []
      (x : rest)
        | isSoftBreak x && not afterHard -> dropSoft False rest
        | otherwise -> x : dropSoft (isHardBreak x) rest

isSoftBreak :: A.Located A.Inline -> Bool
isSoftBreak (A.Located _ A.SoftBreak) = True
isSoftBreak _ = False

isHardBreak :: A.Located A.Inline -> Bool
isHardBreak (A.Located _ A.HardBreak) = True
isHardBreak _ = False

mergeLocated :: [A.Located A.Inline] -> [A.Located A.Inline]
mergeLocated (A.Located a (A.Text x) : A.Located b (A.Text y) : rest) =
  mergeLocated (A.Located (mkSpan (spanFile a) (spanStart a) (spanEnd b)) (A.Text (x <> y)) : rest)
mergeLocated (x : rest) = x : mergeLocated rest
mergeLocated [] = []

-- | The newlines inside an inline (its slots and arguments) are dropped.
nestedInline :: A.Located A.Inline -> A.Located A.Inline
nestedInline (A.Located sp i) = A.Located sp $ case i of
  A.Command n args slots -> A.Command n (map normalizeArg args) (map joinSoftBreaks slots)
  other -> other

normalizeArg :: A.Located A.Argument -> A.Located A.Argument
normalizeArg (A.Located sp a) = A.Located sp $ case a of
  A.Positional v -> A.Positional (argV v)
  A.Keyword k v -> A.Keyword k (argV v)
  other -> other
  where
    argV = \case
      A.CommandArg x -> A.CommandArg (nestedInline x)
      v -> v

{- | Every inline sequence of a block with its newlines dropped, except the
paragraphs a paragraph style is given to (the body of @style and the
target of an attribute group with @style), which keep them at the top
level (docs/adr ADR 0005).
-}
normalizeBlock :: A.Located A.Block -> A.Located A.Block
normalizeBlock (A.Located sp b) = A.Located sp $ case b of
  A.Paragraph is -> A.Paragraph (joinSoftBreaks is)
  A.Heading l is -> A.Heading l (joinSoftBreaks is)
  A.BulletList items -> A.BulletList (map (map normalizeBlock) items)
  A.OrderedList items -> A.OrderedList (map (map normalizeBlock) items)
  A.DefList gs -> A.DefList [A.DefGroup (map joinSoftBreaks ts) (map (map normalizeBlock) ds) | A.DefGroup ts ds <- gs]
  A.Table al h rows -> A.Table al (map joinSoftBreaks h) (map (map joinSoftBreaks) rows)
  A.BlockCommand n@(A.Located _ "style") args body -> A.BlockCommand n (map normalizeArg args) (map styledBody body)
  A.BlockCommand n args body -> A.BlockCommand n (map normalizeArg args) (map normalizeBlock body)
  A.Attributed cs t
    | any isStyleCommand cs -> A.Attributed (map normalizeBlock cs) (styledBody <$> t)
    | otherwise -> A.Attributed (map normalizeBlock cs) (normalizeBlock <$> t)
  other -> other
  where
    styledBody = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (map nestedInline is))
      other -> normalizeBlock other

isStyleCommand :: A.Located A.Block -> Bool
isStyleCommand = \case
  A.Located _ (A.BlockCommand (A.Located _ "style") _ _) -> True
  _ -> False

-- ------------------------------------------------------------------ the line style

{- | The line style (docs/adr ADR 0013): a paragraph is split at its
top-level 'A.SoftBreak' into paragraphs, one per line. An attribute goes
to the first of them. The paragraphs of a style that keeps its lines are
left alone, and so are headings, terms, tables and code. The blank-line
style changes nothing.
-}
splitLines :: SourceSettings -> Map Text LineBreaks -> [A.Located A.Block] -> [A.Located A.Block]
splitLines source paraStyles
  | ssParagraphSeparator source == BlankLineSeparated = id
  | otherwise = concatMap splitBlock
  where
    splitBlock lb@(A.Located sp b) = case b of
      A.Paragraph is -> splitParagraph is
      A.Attributed cmds (Just (A.Located _ (A.Paragraph is)))
        | any keepsLines cmds -> [lb]
        | otherwise -> case splitParagraph is of
            first@(A.Located fsp _) : rest -> A.Located (mkSpan (spanFile sp) (spanStart sp) (spanEnd fsp)) (A.Attributed (map inside cmds) (Just first)) : rest
            [] -> [A.Located sp (A.Attributed (map inside cmds) Nothing)]
      _ -> [inside lb]
    -- a block that is not split itself, with the blocks inside it split
    inside lb@(A.Located sp b) = A.Located sp $ case b of
      A.BulletList items -> A.BulletList (map (concatMap splitBlock) items)
      A.OrderedList items -> A.OrderedList (map (concatMap splitBlock) items)
      A.DefList gs -> A.DefList [A.DefGroup ts (map (concatMap splitBlock) ds) | A.DefGroup ts ds <- gs]
      A.BlockCommand n args body
        | keepsLines lb -> b
        | otherwise -> A.BlockCommand n args (concatMap splitBlock body)
      A.Attributed cmds t -> A.Attributed (map inside cmds) (inside <$> t)
      other -> other
    -- @style with the name of a style that keeps its lines
    keepsLines = \case
      A.Located _ (A.BlockCommand (A.Located _ "style") [A.Located _ (A.Positional (A.Word n))] _) -> Map.lookup n paraStyles == Just KeepLines
      _ -> False

{- | The lines of a paragraph as paragraphs: spaces and tabs at the start of
each line are not text (the ideographic space is), and a line left empty
is dropped.
-}
splitParagraph :: [A.Located A.Inline] -> [A.Located A.Block]
splitParagraph = concatMap paragraph . chunks
  where
    chunks xs = case break isSoftBreak xs of
      (l, []) -> [l]
      (l, _ : rest) -> l : chunks rest
    -- the escapes are text before the spaces are dropped (golem-parser ADR 0010)
    paragraph l = case trimStart (A.plainEscapes l) of
      [] -> []
      is@(A.Located first _ : _) ->
        let A.Located lastSp _ = last is
         in [A.Located (mkSpan (spanFile first) (spanStart first) (spanEnd lastSp)) (A.Paragraph is)]
    trimStart = \case
      (A.Located tsp (A.Text t) : rest) ->
        let t' = T.dropWhile (\c -> c == ' ' || c == '\t') t
            -- the characters dropped are one byte each
            tsp' = mkSpan (spanFile tsp) (spanStart tsp + T.length t - T.length t') (spanEnd tsp)
         in [A.Located tsp' (A.Text t') | not (T.null t')] <> rest
      is -> is

-- ------------------------------------------------------------------ blocks

env :: M Env
env = gets (\s -> Env (stVars s) (stNamespaces s))

block :: SrcSpan -> BlockBody -> Block
block sp = Block sp Nothing

evalBlock :: EvalContext -> A.Located A.Block -> M [Block]
evalBlock ctx (A.Located sp b) = case b of
  -- items, definitions and captions break their lines by the same rule (docs/adr ADR 0016)
  A.Paragraph is -> styledParagraph ctx sp Nothing is
  A.Heading l is -> one . Heading l noHeadingAttrs <$> evalInlines ctx True is
  A.BulletList items -> one . BulletList <$> mapM (fmap (ListItem Nothing) . evalBlocks ctx) items
  A.OrderedList items -> one . OrderedList <$> mapM (fmap (ListItem Nothing) . evalBlocks ctx) items
  A.DefList gs -> one . DefList <$> mapM (\(A.DefGroup ts ds) -> DefGroup <$> mapM (evalInlines ctx False) ts <*> mapM (evalBlocks ctx) ds) gs
  A.Table al h rows -> do
    h' <- mapM (evalInlines ctx False) h
    rows' <- mapM (mapM (evalInlines ctx False)) rows
    pure [block sp (Table (map alignment al) h' rows')]
  A.CodeBlock lang args0 ls -> do
    args <- uniqueKeys args0
    ca <- codeArgs ctx sp [] args
    c <- codeOf ca Nothing lang [(lsp, t) | A.Located lsp t <- ls]
    pure [block sp (CodeBlock c)]
  A.SetVar (A.Located nsp n) e -> do
    defined <- gets (Map.member n . stVars)
    if n `elem` reservedNames
      then err "G0223" nsp ("予約語は変数の名前に使えません: " <> n)
      else
        if defined
          then err "G0224" nsp ("変数を二度定義しています: " <> n)
          else do
            noteRefs e
            en <- env
            case evalExpr en e of
              Left d -> report d
              Right v -> modify' (\s -> s {stVars = Map.insert n v (stVars s), stDefined = stDefined s <> [(n, nsp)]})
    pure []
  A.BlockCommand name@(A.Located _ n) args body
    -- @manifest and @style-def read their own arguments (G0252)
    | n `elem` settingCommands -> standalone ctx sp name args body
    | otherwise -> uniqueKeys args >>= \args' -> standalone ctx sp name args' body
  A.Attributed cmds target -> attributed ctx sp cmds target
  A.ErrorBlock -> pure []
  where
    one x = [block sp x]

evalBlocks :: EvalContext -> [A.Located A.Block] -> M [Block]
evalBlocks ctx bs = concat <$> mapM (evalBlock ctx) bs

alignment :: A.Alignment -> Alignment
alignment = \case
  A.AlignDefault -> AlignDefault
  A.AlignLeft -> AlignLeft
  A.AlignCenter -> AlignCenter
  A.AlignRight -> AlignRight

-- A block command that is not an attribute of another block.
standalone :: EvalContext -> SrcSpan -> A.Located A.Name -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
standalone ctx sp (A.Located nsp name) args body = case name of
  "import" -> do
    -- the same check as the project's (golem-project ADR 0006); G0223 points at the namespace
    case (importSite sp (map A.locValue args), args) of
      (Right (ImportSite path ns _), [_, _, A.Located nssp _]) -> do
        if ns `elem` reservedNames
          then err "G0223" nssp ("予約語は名前空間に使えません: " <> ns)
          else do
            let vals = fromMaybe Map.empty (Map.lookup (T.unpack path) (ctxImports ctx))
            modify' (\s -> s {stNamespaces = Map.insert ns vals (stNamespaces s), stImports = stImports s <> [(ns, T.unpack path, sp)]})
      (Left d, _) -> report d
      -- importSite accepts three arguments only
      (Right _, _) -> pure ()
    pure []
  "toc" -> do
    kw <- keywords ctx args
    let depth = maybe (Just 2) (intOf . argValueRaw) (lookup "depth" kw)
    case depth of
      Just d | d >= 1 && d <= 3 -> pure [block sp (ChannelOutput (TocOutput (fromInteger d)))]
      _ -> err "G0225" sp "@toc の depth は 1 から 3 の整数です" >> pure []
  "index" -> pure [block sp (ChannelOutput IndexOutput)]
  "bibliography" -> pure [block sp (ChannelOutput BibliographyOutput)]
  "printings" -> printingsBlock ctx sp args body
  "page-break" -> forcedBreak sp name args body
  "column-break" -> forcedBreak sp name args body
  "figure" -> figure ctx sp args body
  "table" -> csvTable ctx sp args
  "listing" -> listing ctx sp args
  "style" -> styleBody ctx sp (maximum (spanEnd nsp : map (spanEnd . A.locSpan) args)) args body
  -- the file settings are read before the blocks; elsewhere they are errors (docs/adr ADR 0014)
  _ | name `elem` settingCommands -> misplacedSetting sp >> pure []
  _
    | name `elem` attributeCommands -> err "G0210" sp ("@" <> name <> " の後にブロックがありません") >> pure []
    | otherwise -> err "G0209" nsp ("未知のブロックコマンドです: @" <> name) >> pure []

{- | An attribute group and the block it applies to. Without a block after
it, a last block command that is not an attribute (a figure, @style with a
body) is the target (docs/adr ADR 0005).
-}
attributed :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributed ctx sp cmds0 target
  -- a file setting inside an attribute group is out of place (docs/adr ADR 0014)
  | any isSettingCommand cmds0 = do
      mapM_ (misplacedSetting . A.locSpan) (filter isSettingCommand cmds0)
      case (filter (not . isSettingCommand) cmds0, target) of
        ([], Just t) -> evalBlock ctx t
        ([], Nothing) -> pure []
        (cmds, _) -> attributed ctx sp cmds target
  | otherwise = attributedWith ctx sp cmds0 target

-- | G0249: @manifest or @style-def after the file settings (docs/adr ADR 0014).
misplacedSetting :: SrcSpan -> M ()
misplacedSetting sp = err "G0249" sp "@manifest と @style-def はファイルの最初に置きます"

attributedWith :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributedWith ctx sp cmds target
  -- the breaks of the group go before its target; the attributes skip them (docs/adr ADR 0017)
  | (breaks@(_ : _), rest) <- partition isBreakCommand cmds = do
      bs <- concat <$> mapM (evalBlock ctx) breaks
      others <- case (rest, target) of
        ([], Just t) -> evalBlock ctx t
        ([], Nothing) -> pure []
        _ -> attributedWith ctx sp rest target
      pure (bs <> others)
  | otherwise = attributedGroup ctx sp cmds target

isBreakCommand :: A.Located A.Block -> Bool
isBreakCommand = \case
  A.Located _ (A.BlockCommand (A.Located _ n) _ _) -> n `elem` ["page-break", "column-break"]
  _ -> False

attributedGroup :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributedGroup ctx sp cmds target = case target of
  Nothing
    | (not . any isAttr) cmds -> concat <$> mapM (evalBlock ctx) cmds
    | (lastCmd : before) <- reverse cmds,
      not (isAttr lastCmd),
      isBlockCommand lastCmd,
      all isAttr before ->
        withAttrs (reverse before) lastCmd
    | not (isAttr (last cmds)) && isBlockCommand (last cmds) ->
        err "G0211" sp "属性のまとまりに属性でないコマンドがあります" >> concat <$> mapM (evalBlock ctx) (filter (not . isAttr) cmds)
    | otherwise -> err "G0210" sp "属性の後にブロックがありません" >> concat <$> mapM (evalBlock ctx) (filter (not . isAttr) cmds)
  -- the commands that are not attributes are evaluated as well, in order (golem-eval ADR 0003)
  Just t -> do
    let nonAttrs = filter (not . isAttr) cmds
    unless (null nonAttrs) $ err "G0211" sp "属性のまとまりに属性でないコマンドがあります"
    before <- concat <$> mapM (evalBlock ctx) nonAttrs
    (before <>) <$> withAttrs (filter isAttr cmds) t
  where
    isAttr c@(A.Located _ (A.BlockCommand (A.Located _ n) _ body)) = n `elem` attributeCommands && not (isStyleCommand c && not (null body))
    isAttr _ = False
    isBlockCommand = \case
      A.Located _ (A.BlockCommand {}) -> True
      _ -> False
    foldM' f z = foldl (\acc x -> acc >>= \a -> f a x) (pure z)
    withAttrs attrs0 t = do
      attrs <- mapM uniqueAttrKeys attrs0
      -- every line of an attribute already given (golem-eval ADR 0003)
      let named = [(n, asp) | A.Located asp (A.BlockCommand (A.Located _ n) _ _) <- attrs]
          repeated = [asp | (i, (n, asp)) <- zip [0 :: Int ..] named, n `elem` map fst (take i named)]
      mapM_ (\asp -> err "G0212" asp "同じ属性を二度書いています") repeated
      targetBlocks <- case (t, [c | c <- attrs, isStyleCommand c]) of
        (A.Located psp (A.Paragraph is), A.Located csp (A.BlockCommand _ args _) : _) -> styleName ctx csp args >>= \n -> styledParagraph ctx psp n is
        (A.Located tsp (A.Paragraph is), []) -> evalBlock ctx (A.Located tsp (A.Paragraph is))
        -- @style applies to every paragraph of @printings (docs/adr ADR 0033)
        (A.Located _ (A.BlockCommand (A.Located _ "printings") _ _), A.Located csp (A.BlockCommand _ args _) : _) -> do
          n <- styleName ctx csp args
          let styled b = case blockBody b of
                Paragraph _ is -> b {blockBody = Paragraph n is}
                _ -> b
          map styled <$> evalBlock ctx t
        (other, _) -> evalBlock ctx (joinTarget other)
      case targetBlocks of
        (Block bsp _ body : rest) -> do
          -- where G0407 points: the @number line (golem-syntax ADR 0002)
          case [asp | ("number", asp) <- named] of
            (asp : _) -> modify' (\s -> s {stNumberSites = Map.insert bsp asp (stNumberSites s)})
            [] -> pure ()
          (label, body') <- foldM' (applyAttr ctx) (Nothing, body) attrs
          pure (Block bsp label body' : rest)
        [] -> pure []
    -- a target that is not a paragraph keeps no newlines
    joinTarget = \case
      A.Located tsp (A.Paragraph is) -> A.Located tsp (A.Paragraph (joinSoftBreaks is))
      other -> other

{- | @printings: one paragraph for each printing of meta.printings, as
@2026年10月16日　初版第1刷発行@; the year in kanji-digits, the other
numbers by the default of [numbers]. G0276 for a book not in Japanese,
without printings, or with arguments or a body (docs/adr ADR 0033).
-}
printingsBlock :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
printingsBlock ctx sp args body
  | not (null args) || not (null body) = err "G0276" sp "@printings は引数も本体も取りません" >> pure []
  | Map.lookup "language" (ctxMeta ctx) /= Just (VString "ja") = err "G0276" sp "@printings は日本語の本（language = \"ja\"）でだけ使えます" >> pure []
  | Just (VArray ps@(_ : _)) <- Map.lookup "printings" (ctxMeta ctx) = pure (mapMaybe line ps)
  | otherwise = err "G0276" sp "マニフェストに [[metadata.printings]] がありません" >> pure []
  where
    line = \case
      VHash h
        | Just [e, n, y, m, d] <- traverse (\k -> case Map.lookup k h of Just (VInt i) -> Just i; _ -> Nothing) ["edition", "number", "year", "month", "day"] ->
            Just . block sp . Paragraph Nothing $
              [num y (Just StyleKanjiDigits), txt "年", num m Nothing, txt "月", num d Nothing, txt "日\x3000"]
                <> (if e == 1 then [txt "初版"] else [txt "第", num e Nothing, txt "版"])
                <> [txt "第", num n Nothing, txt "刷発行"]
      _ -> Nothing
    num = Number sp
    txt = Text sp

-- | @page-break and @column-break (docs/adr ADR 0017).
forcedBreak :: SrcSpan -> Text -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
forcedBreak sp name args body
  | not (null body) = err "G0258" sp "@page-break と @column-break は本体を持てません" >> pure []
  | otherwise = case (name, map A.locValue args) of
      ("page-break", []) -> ok BreakPage
      ("page-break", [A.Positional (A.Word "recto")]) -> ok BreakRecto
      ("page-break", [A.Positional (A.Word "verso")]) -> ok BreakVerso
      ("column-break", []) -> ok BreakColumn
      ("column-break", _) -> err "G0258" sp "@column-break は引数を取りません" >> pure []
      _ -> err "G0258" sp "@page-break の引数は recto か verso です" >> pure []
  where
    ok k = pure [block sp (ForcedBreak k)]

{- | Forced breaks below the top of the document are dropped with G0259
(docs/adr ADR 0017).
-}
nestedBreaks :: [Block] -> ([Block], [Diagnostic])
nestedBreaks bs = let (ds, bs') = concat <$> traverse top bs in (bs', ds)
  where
    top b = case blockBody b of
      ForcedBreak _ -> ([], [b])
      _ -> inner b
    -- the diagnostics and what is left of a block below the top
    inner :: Block -> ([Diagnostic], [Block])
    inner b@(Block sp lbl body) = case body of
      ForcedBreak _ -> ([diagnostic "G0259" Error sp "@page-break と @column-break は文書の最上位にだけ置けます"], [])
      BulletList items -> rebuild BulletList <$> traverse item items
      OrderedList items -> rebuild OrderedList <$> traverse item items
      DefList gs -> rebuild DefList <$> traverse (\(DefGroup ts ds) -> DefGroup ts <$> traverse nested ds) gs
      FigureBlock f -> rebuild (\c -> FigureBlock f {figCaption = c}) <$> nested (figCaption f)
      _ -> ([], [b])
      where
        rebuild f x = [Block sp lbl (f x)]
    item (ListItem n bs') = ListItem n <$> nested bs'
    nested bs' = concat <$> traverse inner bs'

applyAttr :: EvalContext -> (Maybe Text, BlockBody) -> A.Located A.Block -> M (Maybe Text, BlockBody)
applyAttr ctx (label, body) (A.Located sp cmd) = case cmd of
  A.BlockCommand (A.Located _ name) args _ -> case (name, body) of
    ("label", _) -> case map A.locValue args of
      [A.Positional (A.Word l)] | validLabel l -> pure (Just l, body)
      _ -> err "G0226" sp "@label にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます" >> pure (label, body)
    ("toc-title", Heading l a is) -> do
      t <- evalInlines ctx True [A.Located sp (A.Text (T.unwords (map (argText . positional) args)))]
      pure (label, Heading l a {haTocTitle = Just t} is)
    ("number", Heading l a is) -> withNumber $ \n -> Heading l a {haNumber = Just n} is
    ("number", OrderedList (ListItem _ bs : rest)) -> withNumber $ \n -> OrderedList (ListItem (Just n) bs : rest)
    ("nonumber", Heading l a is) -> pure (label, Heading l a {haNoNumber = True} is)
    ("notoc", Heading l a is) -> pure (label, Heading l a {haNoToc = True} is)
    -- the style of a paragraph is applied when the paragraph is evaluated
    ("style", Paragraph {}) -> pure (label, body)
    -- the caption of a code block: the rest of the line, inlines included (golem-driver ADR 0023)
    ("caption", CodeBlock c)
      | null args -> err "G0269" sp "@caption には本文を書きます" >> pure (label, body)
      | otherwise -> do
          is <- evalInlines ctx False (captionInlines args)
          pure (label, CodeBlock c {codeCaption = Just is})
    _ -> err "G0213" sp ("@" <> name <> " はこのブロックには付けられません") >> pure (label, body)
    where
      withNumber f = case map A.locValue args of
        [A.Positional v] | Just n <- intOf (argValueRaw v) -> pure (label, f n)
        _ -> err "G0227" sp "@number には整数を一つ書きます" >> pure (label, body)
  _ -> pure (label, body)
  where
    positional = \case
      A.Located _ (A.Positional v) -> v
      A.Located _ (A.Keyword _ v) -> v
      A.Located _ _ -> A.Word ""

{- | The arguments of @caption as inlines (golem-driver ADR 0023): words
and strings are text, commands and expressions are themselves, a space
between two arguments.
-}
captionInlines :: [A.Located A.Argument] -> [A.Located A.Inline]
captionInlines args = concat (zipWith (\i a -> [space a | i > (0 :: Int)] <> one a) [0 ..] args)
  where
    space (A.Located asp _) = A.Located (mkSpan (spanFile asp) (spanStart asp) (spanStart asp)) (A.Text " ")
    one (A.Located asp a) = case a of
      A.Positional v -> value asp v
      A.Keyword (A.Located _ k) v -> A.Located asp (A.Text (k <> "=")) : value asp v
      _ -> []
    value asp = \case
      A.Word t -> [A.Located asp (A.Text t)]
      A.StringLit t -> [A.Located asp (A.Text t)]
      A.CommandArg i -> [i]
      A.ExprArg e -> [A.Located asp (A.Expr e)]

validLabel :: Text -> Bool
validLabel l = not (T.null l) && T.all (\c -> c `elem` ("-_" :: String) || isAsciiLower c || isDigit c) l

-- ------------------------------------------------------------------ paragraph styles

{- | The name of the paragraph style of @style; G0247 and body when it is
not one name. code is the style of code blocks: G0266 and body
(golem-driver ADR 0017).
-}
styleName :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M (Maybe Text)
styleName _ sp = \case
  [A.Located _ (A.Positional (A.Word "code"))] -> err "G0266" sp "code はコードブロックの段落スタイルです。コードは ``` か @listing で書きます" >> pure Nothing
  [A.Located _ (A.Positional (A.Word n))] -> pure (Just n)
  _ -> err "G0247" sp "@style には段落スタイルの名前を一つ書きます" >> pure Nothing

{- | The body form of @style (docs/adr ADR 0005): every paragraph of the
body in the style.
-}
styleBody :: EvalContext -> SrcSpan -> Int -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
styleBody ctx sp headerEnd args body
  -- no body at all, or a body of comments only (the command spans more than its line)
  | null body && spanEnd sp <= headerEnd + 1 = err "G0210" sp "@style の後にブロックがありません" >> pure []
  | null body = err "G0246" sp "@style の本体に段落がありません" >> pure []
  | not (null others) = mapM_ (\osp -> err "G0245" osp "@style の本体には段落だけを置けます。段落は空行で区切ります") others >> pure []
  | otherwise = do
      name <- styleName ctx sp args
      bs <- concat <$> mapM (\(psp, is) -> styledParagraph ctx psp name is) paragraphs
      case bs of
        [] -> err "G0246" sp "@style の本体に段落がありません" >> pure []
        _ -> pure bs
  where
    paragraphs = [(psp, is) | A.Located psp (A.Paragraph is) <- body]
    others = [bsp | A.Located bsp b <- body, not (isParagraph b), not (isErrorBlock b)]
    isParagraph = \case
      A.Paragraph _ -> True
      _ -> False
    isErrorBlock = \case
      A.ErrorBlock -> True
      _ -> False

{- | A paragraph in a paragraph style (docs/adr ADR 0005). An unknown style
is G0247 and the paragraph is body. With line-breaks = "keep" each line
of the source is a line, joined by 'LineBreak'; a paragraph with no line
left is dropped.
-}
styledParagraph :: EvalContext -> SrcSpan -> Maybe Text -> [A.Located A.Inline] -> M [Block]
styledParagraph ctx sp mname is = case mname of
  Nothing -> joined Nothing
  Just name -> case Map.lookup name (ctxParaStyles ctx) of
    Nothing -> err "G0247" sp ("定義されていない段落スタイルです: " <> name) >> joined Nothing
    Just JoinLines -> joined (styleOf name)
    Just KeepLines -> do
      mapM_ escapedIndent (linesOf Nothing is)
      mapM_ (escapedTrailing . snd) (linesOf Nothing is)
      ls <- filter (not . null . snd) <$> mapM (\(bsp, l) -> (bsp,) <$> evalInlines ctx False (A.plainEscapes (trimLine l))) (linesOf Nothing is)
      pure $ case ls of
        [] -> []
        ((_, first) : rest) -> [block sp (Paragraph (styleOf name) (first <> concat [LineBreak bsp : l | (bsp, l) <- rest]))]
  where
    styleOf n = if n == "body" then Nothing else Just n
    {- G0264: an escaped space or tab at the start of a line is dropped
    as the plain ones are (golem-syntax ADR 0002). The line starts with
    the escape (golem-parser ADR 0010). -}
    escapedIndent = \case
      (_, A.Located tsp (A.Escaped c) : _)
        | c == ' ' || c == '\t' ->
            report (notice "G0264" (mkSpan (spanFile tsp) (spanStart tsp) (spanStart tsp + 1)) "行頭のエスケープした空白は無視されます。字下げには全角の空白を使います")
      _ -> pure ()
    {- G0279: an escaped space or tab among the spaces and tabs at the end
    of a line is dropped as well (golem-parser ADR 0012); one notice at
    the first such escape. A line of blanks only is the indent of G0264. -}
    escapedTrailing l = case [tsp | A.Located tsp (A.Escaped _) <- reverse (takeWhile blankEnd (reverse l))] of
      (tsp : _) | not (all blankEnd l) -> report (notice "G0279" (mkSpan (spanFile tsp) (spanStart tsp) (spanStart tsp + 1)) "行末のエスケープした空白は無視されます")
      _ -> pure ()
    joined st = (\x -> [block sp (Paragraph st x)]) <$> hardLines ctx sp is
    -- lines with the span of the newline before each (the first has none);
    -- a hard break is a newline here (docs/adr ADR 0016)
    linesOf before xs = case break (\x -> isSoftBreak x || isHardBreak x) xs of
      (l, []) -> [(fromMaybe sp before, l)]
      (l, A.Located bsp _ : rest) -> (fromMaybe sp before, l) : linesOf (Just bsp) rest

{- | The inlines of a paragraph that joins its lines, broken at its hard
breaks (docs/adr ADR 0016): the lines joined by 'LineBreak'. A line left
empty, or whose first source line has nothing in it, is G0257; an empty
line goes with the break before it.
-}
hardLines :: EvalContext -> SrcSpan -> [A.Located A.Inline] -> M [Inline]
hardLines ctx sp is = do
  let ls = splitHard Nothing is
  evaluated <- mapM (\(bsp, l) -> (bsp,l,) <$> evalInlines ctx False (joinSoftBreaks l)) ls
  let breaks = [bsp | (Just bsp, _, _) <- evaluated]
      -- where an empty line is reported: the break before it, or after it for the first line
      at = \case
        Just bsp -> bsp
        Nothing -> case breaks of
          (b : _) -> b
          [] -> sp
      emptyStart = \case
        (A.Located _ A.SoftBreak : _) -> True
        _ -> False
      bad (_, l, x) = null x || emptyStart l
  unless (null breaks) $
    mapM_ (\(bsp, _, _) -> err "G0257" (at bsp) "強制改行の前後に文字がありません") (filter bad evaluated)
  pure $ case [(bsp, x) | (bsp, _, x) <- evaluated, not (null x)] of
    [] -> []
    ((_, first) : rest) -> first <> concat [maybe [] (pure . LineBreak) bsp <> x | (bsp, x) <- rest]
  where
    splitHard before xs = case break isHardBreak xs of
      (l, []) -> [(before, l)]
      (l, A.Located bsp _ : rest) -> (before, l) : splitHard (Just bsp) rest

-- | Paragraph styles a filter made up (docs/adr ADR 0005).
unknownParaStyles :: EvalContext -> Document -> [Diagnostic]
unknownParaStyles ctx (Document _ bs) = concatMap go bs
  where
    go (Block sp _ body) = case body of
      Paragraph (Just n) _ | Map.notMember n (ctxParaStyles ctx) -> [diagnostic "G0247" Error sp ("定義されていない段落スタイルです: " <> n)]
      BulletList items -> concatMap (concatMap go . itemBlocks) items
      OrderedList items -> concatMap (concatMap go . itemBlocks) items
      DefList gs -> concatMap (concatMap (concatMap go) . dgDefs) gs
      FigureBlock f -> concatMap go (figCaption f)
      _ -> []

{- | Spaces and tabs at the start and the end of a line are not text,
escaped ones included (golem-parser ADR 0012). It runs before
'A.plainEscapes', so that the 'A.Text' it cuts has no escape in it and its
span shrinks by the characters cut.
-}
trimLine :: [A.Located A.Inline] -> [A.Located A.Inline]
trimLine = trimEnd . trimStart
  where
    trimStart = \case
      (x : rest) | blankEnd x -> trimStart rest
      (A.Located tsp (A.Text t) : rest) ->
        let t' = T.dropWhile isSpaceTab t
            tsp' = mkSpan (spanFile tsp) (spanStart tsp + T.length t - T.length t') (spanEnd tsp)
         in [A.Located tsp' (A.Text t') | not (T.null t')] <> rest
      is -> is
    trimEnd is = case reverse is of
      (x : rest) | blankEnd x -> trimEnd (reverse rest)
      (A.Located tsp (A.Text t) : rest) ->
        let t' = T.dropWhileEnd isSpaceTab t
            tsp' = mkSpan (spanFile tsp) (spanStart tsp) (spanEnd tsp - (T.length t - T.length t'))
         in reverse rest <> [A.Located tsp' (A.Text t') | not (T.null t')]
      _ -> is

-- | A text of spaces and tabs only, or an escaped space or tab.
blankEnd :: A.Located A.Inline -> Bool
blankEnd = \case
  A.Located _ (A.Text t) -> T.all isSpaceTab t
  A.Located _ (A.Escaped c) -> isSpaceTab c
  _ -> False

isSpaceTab :: Char -> Bool
isSpaceTab c = c == ' ' || c == '\t'

-- ------------------------------------------------------------------ figures, tables, listings

figure :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> [A.Located A.Block] -> M [Block]
figure ctx sp args body = do
  kw <- keywords ctx args
  let pos = [v | A.Located _ (A.Positional v) <- args]
      look k = argText <$> lookup k kw
  case pos of
    [src] -> do
      let path = argText src
          web = look "web"
          ok = and <$> sequence [check path, maybe (pure True) check web]
          isPdf = extension path == ".pdf"
      -- the formats by the extension, the same for every output (golem-pdf ADR 0008, 0009)
      formats <-
        and
          <$> sequence
            [ if extension path `elem` [".pdf", ".png", ".jpg", ".jpeg", ".svg"] then pure True else err "G0274" sp ("図版の形式は PDF、PNG、JPEG、SVG です: " <> path) >> pure False,
              case web of
                Just w | extension w `notElem` [".png", ".jpg", ".jpeg", ".svg"] -> err "G0273" sp ("web の代替画像は PNG、JPEG、SVG です: " <> w) >> pure False
                _ -> pure True
            ]
      page <- case look "page" of
        Nothing -> pure (Right Nothing)
        Just p
          | isPdf, not (T.null p), T.all isDigit p, T.length p <= 9, let n = read (T.unpack p), n >= 1 -> pure (Right (Just n))
          | otherwise -> err "G0275" sp ("page は PDF の図版のページを 1 から数えた整数で書きます: " <> p) >> pure (Left ())
      fine <- (&& formats) <$> ok
      caption <- evalBlocks ctx . concat =<< mapM unstyled body
      case look "alt" of
        Nothing -> err "G0228" sp "図版には alt の代替テキストが必要です" >> pure []
        Just alt
          | isPdf && isNothing web -> err "G0229" sp "PDF の図版には web の代替画像が必要です" >> pure []
          | not fine || isLeft page -> pure []
          | otherwise -> do
              wrap <- case look "wrap" of
                Nothing -> pure (Right Nothing)
                Just "start" -> pure (Right (Just WrapStart))
                Just "end" -> pure (Right (Just WrapEnd))
                Just w -> pure (Left w)
              case wrap of
                Left w -> err "G0230" sp ("wrap は start か end です: " <> w) >> pure []
                Right wr
                  | isJust wr && isNothing (look "width") -> err "G0231" sp "回り込む図版には width が必要です" >> pure []
                  | otherwise -> pure [block sp (FigureBlock (Figure path web alt wr (look "width") caption (fromRight Nothing page)))]
    _ -> err "G0232" sp "@figure には画像のパスを一つ書きます" >> pure []
  where
    check p = isJust <$> asset ctx sp p
    -- the extension in lower case, with its dot
    extension p = case T.breakOnEnd "." p of
      (before, after) | not (T.null before), not ("/" `T.isInfixOf` after) -> "." <> T.toLower after
      _ -> ""
    -- a caption has no paragraph style of its own (docs/adr ADR 0005, golem-driver ADR 0010)
    noStyle csp = err "G0213" csp "@style は図版のキャプションには付けられません"
    unstyled = \case
      A.Located asp (A.Attributed cs t) | any isStyleCommand cs -> do
        mapM_ (\(A.Located csp _) -> noStyle csp) (filter isStyleCommand cs)
        let rest = filter (not . isStyleCommand) cs
            t' = joinParagraph <$> t
        pure $ case rest of
          [] -> maybe [] pure t'
          _ -> [A.Located asp (A.Attributed rest t')]
      A.Located bsp (A.BlockCommand (A.Located _ "style") _ inner) -> noStyle bsp >> pure (map joinParagraph inner)
      other -> pure [other]
    joinParagraph = \case
      A.Located psp (A.Paragraph is) -> A.Located psp (A.Paragraph (joinSoftBreaks is))
      other -> other

csvTable :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
csvTable ctx sp args = do
  kw <- keywords ctx args
  case argText <$> lookup "src" kw of
    Nothing -> err "G0234" sp "@table には src が必要です" >> pure []
    Just src ->
      asset ctx sp src >>= \case
        Just (AssetText content) -> case parseCsv content of
          (h : rows)
            | all ((== length h) . length) rows ->
                let cell t = [Text sp t]
                 in pure [block sp (Table (map (const AlignDefault) h) (map cell h) (map (map cell) rows))]
          [] -> err "G0235" sp "CSV が空です" >> pure []
          _ -> err "G0235" sp "CSV の行ごとのセルの数が一致しません" >> pure []
        Just _ -> missing sp src >> pure []
        Nothing -> pure []

{- | The file a path refers to. A path that cannot be used is reported, and
gives nothing.
-}
asset :: EvalContext -> SrcSpan -> Text -> M (Maybe Asset)
asset ctx sp p = case Map.lookup (T.unpack p) (ctxAssets ctx) of
  Nothing -> missing sp p >> pure Nothing
  Just (AssetInvalid Missing) -> missing sp p >> pure Nothing
  -- G0260: a path that cannot be used, worded as G0303 (golem-eval ADR 0003)
  Just (AssetInvalid e) -> err "G0260" sp (T.pack (pathErrorMessage e) <> ": " <> p) >> pure Nothing
  Just a -> pure (Just a)

-- | G0233: a file that is not there.
missing :: SrcSpan -> Text -> M ()
missing sp p = err "G0233" sp ("ファイルがありません: " <> p)

-- | RFC 4180: comma-separated, double-quoted fields with "" escapes.
parseCsv :: Text -> [[Text]]
parseCsv t = filter (/= [""]) (rows (T.unpack (T.replace "\r\n" "\n" t)))
  where
    rows s = case field s of
      (f, ',' : rest) -> case rows rest of
        (r : rs) -> (f : r) : rs
        [] -> [[f]]
      (f, '\n' : rest) -> [f] : rows rest
      (f, _) -> [[f]]
    field ('"' : s) = quoted s ""
    field s = let (a, b) = break (`elem` (",\n" :: String)) s in (T.pack a, b)
    quoted ('"' : '"' : s) acc = quoted s ('"' : acc)
    quoted ('"' : s) acc = (T.pack (reverse acc), s)
    quoted (c : s) acc = quoted s (c : acc)
    quoted [] acc = (T.pack (reverse acc), [])

listing :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
listing ctx sp args = do
  kw <- keywords ctx args
  -- G0265: the path as src= is to be retired (golem-syntax ADR 0002)
  mapM_
    (\asp -> report (notice "G0265" asp "@listing の src= は廃止予定です。パスを最初の引数に書きます"))
    [asp | A.Located asp (A.Keyword (A.Located _ "src") _) <- args]
  let src = case [v | A.Located _ (A.Positional v) <- args] of
        (v : _) -> Just (argText v)
        [] -> argText <$> lookup "src" kw
  case src of
    Nothing -> err "G0236" sp "@listing にはファイルのパスが必要です" >> pure []
    Just p ->
      asset ctx sp p >>= \case
        Just (AssetText content) -> do
          let ls = T.lines content
              -- the arguments of a code block, and lang (golem-driver ADR 0023)
              codeArgsOf = [a | a@(A.Located _ (A.Keyword (A.Located _ k) _)) <- args, k `notElem` ["src", "lines"]]
              code start xs = do
                ca <- codeArgs ctx sp ["lang"] codeArgsOf
                c <- codeOf ca start (caLang ca) [(sp, x) | x <- xs]
                pure [block sp (CodeBlock c)]
          case argText <$> lookup "lines" kw of
            Nothing -> code Nothing ls
            Just r -> case map (fmap fst . decimalInt) (T.splitOn "-" r) of
              [Just a, Just b]
                | a >= 1 && b >= a && b <= length ls -> code (Just (toInteger a)) (take (b - a + 1) (drop (a - 1) ls))
              _ -> err "G0237" sp ("lines の範囲が不正です: " <> r) >> pure []
        Just _ -> missing sp p >> pure []
        Nothing -> pure []
  where
    decimalInt x = if not (T.null x) && T.all isDigit x then Just (read (T.unpack x) :: Int, ()) else Nothing

-- ------------------------------------------------------------------ code blocks (golem-driver ADR 0023)

-- | The arguments of a code block, as read.
data CodeArgs = CodeArgs
  { -- | true or false, or the number of the first line
    caNumbers :: !(Maybe (Either Bool Integer)),
    caFile :: !(Maybe Text),
    -- | the ranges of highlight=, and where the argument is
    caHighlight :: !(Maybe (SrcSpan, [(Integer, Integer)])),
    caDiff :: !Bool,
    caCallouts :: !Bool,
    -- | lang=, of @listing only
    caLang :: !(Maybe Text)
  }

-- | The keys a code block takes; @listing takes lang too.
codeKeys :: [Text]
codeKeys = ["numbers", "file", "highlight", "diff", "callouts"]

{- | The arguments of a code block (golem-driver ADR 0023): keyword
arguments of 'codeKeys' and @extra@. Another key, a wrong value and a
positional argument are G0269.
-}
codeArgs :: EvalContext -> SrcSpan -> [Text] -> [A.Located A.Argument] -> M CodeArgs
codeArgs ctx _ extra = foldl (\m a -> m >>= \acc -> step acc a) (pure (CodeArgs Nothing Nothing Nothing False False Nothing))
  where
    step acc (A.Located asp a) = case a of
      A.Keyword (A.Located _ k) v
        | k `elem` codeKeys <> extra -> do
            t <- scalar v
            case t >>= reading asp k of
              Just f -> pure (f acc)
              Nothing -> err "G0269" asp (k <> " の値が正しくありません: " <> fromMaybe "" t) >> pure acc
        | otherwise -> err "G0269" asp ("コードブロックに書けないキーです: " <> k <> "。numbers、file、highlight、diff、callouts（@listing では lang も）を書けます") >> pure acc
      _ -> err "G0269" asp "コードブロックの開始の行には、言語の名前とキーワード引数だけを書けます" >> pure acc
    scalar = \case
      A.Word t -> pure (Just t)
      A.StringLit t -> pure (Just t)
      v@(A.ExprArg _) ->
        argValue ctx v >>= \case
          Right (VInt n) -> pure (Just (T.pack (show n)))
          Right (VString s) -> pure (Just s)
          Right (VBool b) -> pure (Just (if b then "true" else "false"))
          Right _ -> pure Nothing
          Left d -> report d >> pure Nothing
      A.CommandArg _ -> pure Nothing
    bool = \case
      "true" -> Just True
      "false" -> Just False
      _ -> Nothing
    reading asp k t = case k of
      "numbers" -> case bool t of
        Just b -> Just (\c -> c {caNumbers = Just (Left b)})
        Nothing -> (\n c -> c {caNumbers = Just (Right n)}) <$> natural t
      "file" -> Just (\c -> c {caFile = Just t})
      "highlight" -> (\rs c -> c {caHighlight = Just (asp, rs)}) <$> traverse range (T.splitOn "," t)
      "diff" -> (\b c -> c {caDiff = b}) <$> bool t
      "callouts" -> (\b c -> c {caCallouts = b}) <$> bool t
      "lang" | not (T.null t) -> Just (\c -> c {caLang = Just t})
      _ -> Nothing
    natural t = if not (T.null t) && T.all isDigit t then Just (read (T.unpack t)) else Nothing
    range r = case T.splitOn "-" r of
      [a] -> (\n -> (n, n)) <$> natural a
      [a, b] -> do
        x <- natural a
        y <- natural b
        if x <= y then Just (x, y) else Nothing
      _ -> Nothing

{- | The code of lines with their spans (golem-driver ADR 0023): the diff
marks and the callouts taken off, each line numbered from the first
number, a removed line not counted, and the lines of highlight marked.
@start@ is the first line of lines= of @listing.
-}
codeOf :: CodeArgs -> Maybe Integer -> Maybe Text -> [(SrcSpan, Text)] -> M Code
codeOf ca start lang ls = do
  marked <- mapM diffOf ls
  withCallouts <- mapM calloutsOf marked
  let first = case caNumbers ca of
        Just (Right n) -> n
        _ -> fromMaybe 1 start
      numbered = snd (mapAccumL number first withCallouts)
      number n (t, d, cs)
        | d == Just DiffRemoved = (n, CodeLine t Nothing d False cs)
        | otherwise = (n + 1, CodeLine t (Just n) d False cs)
      present = Set.fromList [n | CodeLine {clNumber = Just n} <- numbered]
  hl <- case caHighlight ca of
    Nothing -> pure Set.empty
    Just (asp, rs) -> do
      mapM_ (\n -> err "G0269" asp ("highlight の行 " <> T.pack (show n) <> " はこのコードにありません")) [n | (a, b) <- rs, n <- take 1 [x | x <- [a .. b], x `Set.notMember` present]]
      -- only the lines the code has, however wide a range is (docs/adr ADR 0035)
      pure (Set.filter (\n -> any (\(a, b) -> a <= n && n <= b) rs) present)
  pure
    Code
      { codeLang = lang,
        codeNumbers = fromLeft True <$> caNumbers ca,
        codeFile = caFile ca,
        codeCaption = Nothing,
        codeDiff = caDiff ca,
        codeLines = [l {clHighlight = maybe False (`Set.member` hl) (clNumber l)} | l <- numbered]
      }
  where
    diffOf (lsp, t)
      | not (caDiff ca) = pure (lsp, t, Nothing)
      | otherwise = case T.uncons t of
          Nothing -> pure (lsp, t, Just DiffContext)
          Just ('+', rest) -> pure (lsp, rest, Just DiffAdded)
          Just ('-', rest) -> pure (lsp, rest, Just DiffRemoved)
          Just (' ', rest) -> pure (lsp, rest, Just DiffContext)
          Just _ -> err "G0269" lsp "diff=true のコードの行は +、-、空白のどれかで始めます" >> pure (lsp, t, Just DiffContext)
    calloutsOf (lsp, t, d)
      | not (caCallouts ca) = pure (t, d, [])
      | otherwise = do
          let (t', ns) = lineCallouts t
              bad = [n | n <- ns, n < 1 || n > 50]
          mapM_ (\n -> err "G0269" lsp ("注釈の印の番号は 1 から 50 までです: " <> T.pack (show n))) bad
          pure (t', d, [fromInteger n | n <- ns, n >= 1, n <= 50])

{- | The callouts at the end of a line (golem-driver ADR 0023): each @<N>@
after the text, with the spaces before them taken off; a line without
one is left as it is.
-}
lineCallouts :: Text -> (Text, [Integer])
lineCallouts t = case go (T.dropWhileEnd isBlank t) [] of
  (_, []) -> (t, [])
  r -> r
  where
    isBlank c = c == ' ' || c == '\t'
    go s acc = case T.stripSuffix ">" s of
      Just s1 ->
        let (pre, digits) = T.breakOnEnd "<" s1
         in if T.null pre || T.null digits || not (T.all isDigit digits)
              then (s, acc)
              else go (T.dropWhileEnd isBlank (T.dropEnd 1 pre)) (read (T.unpack digits) : acc)
      Nothing -> (s, acc)

-- ------------------------------------------------------------------ inlines

noteRefs :: A.Located A.Expr -> M ()
noteRefs e = do
  let names = freeNames e
  modify' (\s -> s {stRefs = Set.union (stRefs s) (Set.fromList names)})
  let nsRefs = nsRefsOf e
  modify' (\s -> s {stNsRefs = Map.unionWith Set.union (stNsRefs s) nsRefs})
  where
    nsRefsOf (A.Located _ x) = case x of
      A.EVar (ns : n : _) -> Map.singleton ns (Set.singleton n)
      A.EArray xs -> Map.unionsWith Set.union (map nsRefsOf xs)
      A.EHash kvs -> Map.unionsWith Set.union (map (nsRefsOf . snd) kvs)
      A.ECall _ xs -> Map.unionsWith Set.union (map nsRefsOf xs)
      A.EUnary _ a -> nsRefsOf a
      A.EBinary _ a b -> Map.unionWith Set.union (nsRefsOf a) (nsRefsOf b)
      _ -> Map.empty

evalInlines :: EvalContext -> Bool -> [A.Located A.Inline] -> M [Inline]
evalInlines ctx inHeading is = mergeText . concat <$> mapM (evalInline ctx inHeading) (A.plainEscapes is)

mergeText :: [Inline] -> [Inline]
mergeText (Text a x : Text b y : rest) = mergeText (Text (mkSpan (spanFile a) (spanStart a) (spanEnd b)) (x <> y) : rest)
mergeText (x : rest) = x : mergeText rest
mergeText [] = []

-- | Whether an expression needs document structure (refers to doc).
usesDoc :: A.Located A.Expr -> Bool
usesDoc e = "doc" `elem` freeNames e

-- | Replace S0 names by their values so that only doc stays free.
substitute :: Env -> A.Located A.Expr -> A.Located A.Expr
substitute en le@(A.Located sp e) = case e of
  A.EVar ("doc" : _) -> le
  A.EVar _ -> either (const le) (valueToExpr le) (evalExpr en le)
  A.EArray xs -> A.Located sp (A.EArray (map (substitute en) xs))
  A.EHash kvs -> A.Located sp (A.EHash [(k, substitute en v) | (k, v) <- kvs])
  A.ECall f xs -> A.Located sp (A.ECall f (map (substitute en) xs))
  A.EUnary o a -> A.Located sp (A.EUnary o (substitute en a))
  A.EBinary o a b -> A.Located sp (A.EBinary o (substitute en a) (substitute en b))
  _ -> le

evalInline :: EvalContext -> Bool -> A.Located A.Inline -> M [Inline]
evalInline ctx inHeading (A.Located sp i) = case i of
  A.Text t -> pure [Text sp t]
  -- evalInlines has made it text already; this is for safety (golem-parser ADR 0010)
  A.Escaped c -> pure [Text sp (T.singleton c)]
  A.SoftBreak -> pure []
  -- the hard breaks of a paragraph are split off before; this one is in a prose slot
  A.HardBreak -> err "G0256" sp "強制改行は段落の中にだけ書けます。コマンドの中では使えません" >> pure []
  A.ErrorInline -> pure []
  A.ProofComment t
    | ctxProfile ctx == Prod -> report (diagnostic "G0205" Warning sp "校正用のコメントが残っています") >> pure []
    | otherwise -> pure [ProofComment sp t]
  A.Expr e -> do
    noteRefs e
    en <- env
    if usesDoc e
      then
        if inHeading
          then err "G0214" sp "見出しの中では doc を参照できません" >> pure []
          else pure [Deferred sp (DeferredExpr (substitute en e))]
      else case evalExpr en e >>= embedValue sp of
        Left d -> report d >> pure []
        Right t -> pure [Text sp t]
  A.Command n args slots -> uniqueKeys args >>= \args' -> evalCommand ctx inHeading sp n args' slots

-- | An inline command, its repeated keys dropped (golem-parser ADR 0013).
evalCommand :: EvalContext -> Bool -> SrcSpan -> A.Located A.Name -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
evalCommand ctx inHeading sp (A.Located nsp name) args slots
  | Just (Overridable o) <- parsed, Just pc <- Map.lookup o (phOverrides (ctxPlugins ctx)) = plugin pc
  | Just b <- parsed = builtin ctx inHeading sp b args slots
  | Just pc <- pluginCommandName name >>= (`Map.lookup` phCommands (ctxPlugins ctx)) = plugin pc
  | otherwise = err "G0222" nsp ("未知のコマンドです: " <> name) >> pure []
  where
    parsed = parseBuiltin name
    plugin pc = do
      vals <- forM args $ \(A.Located _ a) -> case a of
        A.Positional v -> argValue ctx v
        A.Keyword _ v -> argValue ctx v
        _ -> pure (Right VNil)
      slots' <- mapM (evalInlines ctx inHeading) slots
      case sequence vals of
        Left d -> report d >> pure []
        Right vs -> case pcCall pc vs slots' sp of
          Left ds -> mapM_ report ds >> pure []
          Right (out, ds) -> mapM_ report ds >> pure out

{- | A built-in command. A command that takes no prose slot ('takesNoSlot',
golem-eval ADR 0003) reports a slot as G0238, before the arguments, and
after G0214 for a reference in a heading.
-}
builtin :: EvalContext -> Bool -> SrcSpan -> BuiltinInline -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
builtin ctx inHeading sp b args slots
  | inHeading && b `elem` map Fixed [BRefNumber, BRefTitle, BRefPage] = err "G0214" sp "見出しの中では相互参照を使えません" >> pure []
  | takesNoSlot b && not (null slots) = err "G0238" sp (builtinName b <> " は散文スロットを取りません") >> pure []
  | otherwise = builtinWith ctx inHeading sp b args slots

builtinWith :: EvalContext -> Bool -> SrcSpan -> BuiltinInline -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
builtinWith ctx inHeading sp b args slots = do
  kw <- keywords ctx args
  let pos = [v | A.Located _ (A.Positional v) <- args]
      oneSlot k = case slots of
        [s] -> evalInlines ctx inHeading s >>= k
        _ -> err "G0238" sp (builtinName b <> " には散文スロットが一つ必要です") >> pure []
  case b of
    -- the built-in character styles (docs/adr ADR 0005)
    Overridable BStrong -> oneSlot (pure . pure . CharStyle sp "strong")
    Overridable BBold -> oneSlot (pure . pure . CharStyle sp "bold")
    Overridable BItalic -> oneSlot (pure . pure . CharStyle sp "italic")
    -- [code: ...] is [style code: ...] (golem-driver ADR 0017)
    Overridable BCode -> oneSlot (pure . pure . CharStyle sp "code")
    Overridable BKenten -> do
      let shape = argText <$> lookup "shape" kw
      case shape of
        Just s | s `notElem` kentenShapes -> err "G0239" sp ("未知の圏点の形です: " <> s) >> pure []
        -- without a shape, the default of style.toml (golem-driver ADR 0019)
        _ -> oneSlot (pure . pure . Kenten sp (Just (fromMaybe (ctxDefaultKenten ctx) shape)))
    Overridable BColor -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxSwatches ctx -> oneSlot (pure . pure . Color sp n)
      [v] | Just n <- nameArg v -> err "G0217" sp ("style.toml にないスウォッチです: " <> n) >> pure []
      _ -> err "G0217" sp "color にはスウォッチの名前を一つ書きます" >> pure []
    Overridable BStyle -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxCharStyles ctx -> oneSlot (pure . pure . CharStyle sp n)
      [v] | Just n <- nameArg v -> err "G0218" sp ("定義されていない文字スタイルです: " <> n) >> pure []
      _ -> err "G0218" sp "style には文字スタイルの名前を一つ書きます" >> pure []
    Overridable BTcy -> oneSlot $ \case
      [Text _ t]
        -- G0263: a number reads better as a number (golem-syntax ADR 0002)
        | not (T.null t) && T.all isDigit t && T.all isAscii t -> report (notice "G0263" sp ("数の縦中横は [number-text " <> t <> " style=tcy] でも書けます")) >> pure [Tcy sp t]
        | otherwise -> pure [Tcy sp t]
      [] -> pure []
      _ -> err "G0240" sp "縦中横の中身は地の文に限ります" >> pure []
    Overridable BNumberText -> case pos of
      [v] -> do
        val <- argValue ctx v
        let st = argText <$> lookup "style" kw
        case (val, st) of
          (Right (VInt n), Nothing) -> pure [Number sp n Nothing]
          (Right (VInt n), Just s)
            | Just ns <- lookup s [("kanji", StyleKanji), ("kanji-digits", StyleKanjiDigits), ("tcy", StyleTcy)] -> pure [Number sp n (Just ns)]
            | otherwise -> err "G0219" sp ("style は kanji、kanji-digits、tcy のいずれかです: " <> s) >> pure []
          (Left d, _) -> report d >> pure []
          _ -> err "G0219" sp "number-text に渡せるのは整数だけです" >> pure []
      _ -> err "G0219" sp "number-text には整数を一つ書きます" >> pure []
    Fixed BRefNumber -> refTo RefNumber pos
    Fixed BRefTitle -> refTo RefTitle pos
    Fixed BRefPage -> refTo RefPage pos
    Fixed BNote -> oneSlot $ \body -> do
      n <- gets ((+ 1) . stNote)
      modify' (\s -> s {stNote = n})
      pure [Note sp n body]
    Fixed BSidenote -> oneSlot $ \body -> do
      n <- gets ((+ 1) . stSidenote)
      modify' (\s -> s {stSidenote = n})
      pure [Sidenote sp n body]
    Fixed BIndex -> case slots of
      [s] -> do
        -- the levels are split at the / written in the slot (golem-parser ADR 0010)
        levels <- mapM (evalInlines ctx inHeading) (splitSlot '/' s)
        case (traverse plainText levels, argText <$> lookup "reading" kw) of
          (_, Nothing) -> err "G0220" sp "索引には reading が必要です" >> pure []
          (Nothing, _) -> err "G0241" sp "索引の語は地の文に限ります" >> pure []
          (Just ts, Just reading) ->
            let rs = T.splitOn "/" reading
             in if length ts > 2 || length ts /= length rs || any T.null (ts <> rs)
                  then err "G0242" sp "索引の語と読みの段の数が不正です" >> pure []
                  else pure [IndexMark sp (IndexEntry ts rs)]
      _ -> err "G0238" sp "index には散文スロットが一つ必要です" >> pure []
    Fixed BCite -> case pos of
      [v] | Just n <- nameArg v, n `Set.member` ctxCiteKeys ctx -> pure [Cite sp n]
      [v] | Just n <- nameArg v -> err "G0221" sp ("書誌データにないキーです: " <> n) >> pure []
      _ -> err "G0221" sp "cite には書誌データのキーを一つ書きます" >> pure []
    Overridable BRuby -> ruby ctx sp slots
    Fixed BAki -> aki sp args slots
  where
    refTo k = \case
      [v] | validLabel (argText v) -> pure [Ref sp k (argText v)]
      _ -> err "G0226" sp "参照にはラベルの名前を一つ書きます。名前は英小文字、数字、-、_ で書きます" >> pure []

{- | @[aki 量]@ (docs/adr ADR 0019): one amount, an aki name, zw, a
percentage or an absolute dimension, and no prose slot; otherwise G0255.
-}
aki :: SrcSpan -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
aki sp args slots = case (args, slots) of
  (_, _ : _) -> wrong "aki は散文スロットを取りません"
  ([A.Located _ (A.Positional v)], []) -> case nameArg v of
    Just t
      | Just a <- amount t -> pure [Aki sp a]
      | otherwise -> wrong ("アキの量を読めません: " <> t)
    Nothing -> wrong "aki には量を一つ書きます"
  _ -> wrong "aki には量を一つ書きます"
  where
    amount t = case (parseAki t, parseDim t) of
      (Just r, _) -> Just (AkiZw r)
      (_, Just (Abs x)) -> Just (AkiAbs x)
      _ -> Nothing
    wrong why = err "G0255" sp (why <> "。" <> akiAmounts) >> pure []

-- | What the amount of an [aki] may be (the message of G0255).
akiAmounts :: Text
akiAmounts = "量には、ベタ、全角、二分、三分、四分、五分、六分、八分、二分四分のどれか、0.2zw のような zw、25% のような百分率、1mm のような寸法のどれかを書きます"

plainText :: [Inline] -> Maybe Text
plainText is = T.concat <$> traverse (\case Text _ t -> Just t; _ -> Nothing) is

ruby :: EvalContext -> SrcSpan -> [[A.Located A.Inline]] -> M [Inline]
ruby ctx sp = \case
  [baseSlot, readingSlot] -> do
    -- the segments are split at the / written in the slots, before they
    -- are evaluated (golem-parser ADR 0010)
    base <- mapM (evalInlines ctx False) (splitSlot '/' baseSlot)
    reading <- mapM (evalInlines ctx False) (splitSlot '/' readingSlot)
    case (traverse (traverse noRuby) base, traverse plainText reading) of
      (Nothing, _) -> err "G0216" sp "ルビの中にルビは入れられません" >> pure []
      (_, Nothing) -> err "G0243" sp "ルビの読みは地の文に限ります" >> pure []
      (Just baseSegs, Just readSegs)
        -- a reading split by '/' needs a base split as many times (golem-eval ADR 0003)
        | length baseSegs /= length readSegs -> err "G0215" sp "モノルビの対象と読みのセグメントの数が一致しません" >> pure []
        | [nb] <- baseSegs, [r] <- readSegs -> pure [Ruby sp () [RubySegment nb (Just r)]]
        | otherwise -> pure [Ruby sp () [RubySegment b (if T.null rd then Nothing else Just rd) | (b, rd) <- zip baseSegs readSegs]]
  _ -> err "G0238" sp "ruby には散文スロットが二つ必要です" >> pure []

{- | A slot split at a character in its top-level text; escaped characters
and nested commands are not split (golem-parser ADR 0010). A piece keeps
the span of the text it was cut from.
-}
splitSlot :: Char -> [A.Located A.Inline] -> [[A.Located A.Inline]]
splitSlot c = foldr step [[]]
  where
    step (A.Located s (A.Text t)) (cur : rest) =
      let pieces = [[A.Located s (A.Text p) | not (T.null p)] | p <- T.split (== c) t]
       in init pieces <> [last pieces <> cur] <> rest
    step x (cur : rest) = (x : cur) : rest
    step _ [] = [[]]

-- ------------------------------------------------------------------ arguments

{- | G0277 for each keyword argument whose key a keyword argument before it
already has (golem-parser ADR 0013). A keyword splat is not expanded yet,
so it has no keys.
-}
duplicateKeys :: [A.Located A.Argument] -> [Diagnostic]
duplicateKeys args = [diagnostic "G0277" Error asp ("同じキーを二度書いています: " <> k) | (asp, k) <- repeatedKeys args]

-- | The keyword arguments whose key comes before them, with their keys.
repeatedKeys :: [A.Located A.Argument] -> [(SrcSpan, Text)]
repeatedKeys args = [(asp, k) | (i, (asp, k)) <- zip [0 :: Int ..] keyed, k `elem` map snd (take i keyed)]
  where
    keyed = [(asp, k) | A.Located asp (A.Keyword (A.Located _ k) _) <- args]

{- | The arguments with 'duplicateKeys' reported and every repeated keyword
argument dropped: the first of each key is used.
-}
uniqueKeys :: [A.Located A.Argument] -> M [A.Located A.Argument]
uniqueKeys args = do
  mapM_ report (duplicateKeys args)
  let repeated = map fst (repeatedKeys args)
  pure [a | a@(A.Located asp _) <- args, asp `notElem` repeated]

-- | 'uniqueKeys' on the arguments of an attribute.
uniqueAttrKeys :: A.Located A.Block -> M (A.Located A.Block)
uniqueAttrKeys = \case
  A.Located sp (A.BlockCommand n args body) -> (\args' -> A.Located sp (A.BlockCommand n args' body)) <$> uniqueKeys args
  other -> pure other

keywords :: EvalContext -> [A.Located A.Argument] -> M [(Text, A.ArgValue)]
keywords _ args = pure [(k, v) | A.Located _ (A.Keyword (A.Located _ k) v) <- args]

-- | A name written as a word or a string literal.
nameArg :: A.ArgValue -> Maybe Text
nameArg = \case
  A.Word t -> Just t
  A.StringLit t -> Just t
  _ -> Nothing

argText :: A.ArgValue -> Text
argText = \case
  A.Word t -> t
  A.StringLit t -> t
  _ -> ""

argValueRaw :: A.ArgValue -> Value
argValueRaw = \case
  A.Word t
    | not (T.null t), T.all isDigit t -> VInt (read (T.unpack t))
    | otherwise -> VString t
  A.StringLit t -> VString t
  _ -> VNil

argValue :: EvalContext -> A.ArgValue -> M (Either Diagnostic Value)
argValue _ = \case
  A.ExprArg e -> do
    noteRefs e
    en <- env
    pure (evalExpr en e)
  v -> pure (Right (argValueRaw v))

intOf :: Value -> Maybe Integer
intOf = \case
  VInt n -> Just n
  _ -> Nothing
