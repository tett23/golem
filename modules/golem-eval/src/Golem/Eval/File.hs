{- | File evaluation, S0 (golem-eval ADR 0002): one source file and its
imports become semantic IR. Values that need the whole document (S1) or
the layout (S2) are left as 'Ref' and 'Deferred' inlines.
-}
module Golem.Eval.File
  ( EvalContext (..),
    PluginHook (..),
    noPlugins,
    Usage (..),
    EvalResult (..),
    evalFile,
    builtinInlineCommands,
    overridableCommands,
    kentenShapes,
  )
where

import Control.Monad (forM, unless, when)
import Control.Monad.State.Strict
import Data.Char (isAsciiLower, isDigit)
import Data.List (nub)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.IR
import Golem.Eval.Expr
import Golem.Eval.Value
import Golem.Parser.AST qualified as A
import Golem.Syntax

-- | Plugin commands and filters, provided by golem-plugin.
data PluginHook = PluginHook
  { phCommands :: !(Set Text),
    phOverrides :: !(Set Text),
    -- | the output and the plugin's own diagnostics, or errors
    phCallCommand :: Text -> [Value] -> [[Inline]] -> SrcSpan -> Either [Diagnostic] ([Inline], [Diagnostic]),
    phApplyFilters :: FilePath -> Document -> Either [Diagnostic] (Document, [Diagnostic])
  }

noPlugins :: PluginHook
noPlugins = PluginHook Set.empty Set.empty (\n _ _ sp -> Left [diagnostic "G0222" Error sp ("未知のコマンドです: " <> n)]) (\_ d -> Right (d, []))

data EvalContext = EvalContext
  { ctxFile :: !FileId,
    ctxPath :: !FilePath,
    ctxProfile :: !Profile,
    ctxMeta :: !(Map Text Value),
    ctxImports :: !(Map FilePath (Map Text Value)), -- exported variables by file
    ctxSwatches :: !(Set Text),
    ctxCharStyles :: !(Set Text),
    ctxDefaultKenten :: !Text,
    ctxCiteKeys :: !(Set Text),
    ctxAssets :: !(Map FilePath (Maybe Text)), -- referenced files; Nothing = binary but present
    ctxPlugins :: !PluginHook
  }

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
    erDiagnostics :: ![Diagnostic]
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
    stDiags :: ![Diagnostic]
  }

type M = State St

report :: Diagnostic -> M ()
report d = modify' (\s -> s {stDiags = stDiags s <> [d]})

err :: Text -> SrcSpan -> Text -> M ()
err code sp msg = report (diagnostic code Error sp msg)

builtinInlineCommands :: [Text]
builtinInlineCommands =
  ["strong", "bold", "italic", "ruby", "kenten", "color", "style", "tcy", "number-text", "ref-number", "ref-title", "ref-page", "note", "sidenote", "index", "cite"]

-- | Built-in commands a plugin may override when the manifest says so.
overridableCommands :: [Text]
overridableCommands = ["strong", "bold", "italic", "ruby", "kenten", "color", "style", "tcy", "number-text"]

attributeCommands :: [Text]
attributeCommands = ["label", "toc-title", "number", "nonumber", "notoc"]

kentenShapes :: [Text]
kentenShapes = ["sesame", "open-sesame", "dot", "open-dot", "circle", "open-circle"]

reservedNames :: [Text]
reservedNames = ["doc", "meta", "true", "false", "nil"]

evalFile :: EvalContext -> A.File -> EvalResult
evalFile ctx (A.File fid blocks) =
  let st0 = St Map.empty (Map.singleton "meta" (ctxMeta ctx)) [] Set.empty Map.empty [] 0 0 []
      (bs, st) = runState (concat <$> mapM (evalBlock ctx) blocks) st0
      doc0 = Document fid bs
      (doc, filterDiags) = case phApplyFilters (ctxPlugins ctx) (ctxPath ctx) doc0 of
        Left ds -> (doc0, ds)
        Right (d, ws) -> (d, ws)
   in EvalResult
        { erDocument = doc,
          erExports = stVars st,
          erUsage = Usage (stDefined st) (stRefs st) (stNsRefs st) (stImports st),
          erDiagnostics = stDiags st <> filterDiags
        }

-- ------------------------------------------------------------------ blocks

env :: M Env
env = gets (\s -> Env (stVars s) (stNamespaces s))

block :: SrcSpan -> BlockBody -> Block
block sp = Block sp Nothing

evalBlock :: EvalContext -> A.Located A.Block -> M [Block]
evalBlock ctx (A.Located sp b) = case b of
  A.Paragraph is -> one . Paragraph <$> evalInlines ctx False is
  A.Heading l is -> one . Heading l noHeadingAttrs <$> evalInlines ctx True is
  A.BulletList items -> one . BulletList <$> mapM (fmap (ListItem Nothing) . evalBlocks ctx) items
  A.OrderedList items -> one . OrderedList <$> mapM (fmap (ListItem Nothing) . evalBlocks ctx) items
  A.DefList gs -> one . DefList <$> mapM (\(A.DefGroup ts ds) -> DefGroup <$> mapM (evalInlines ctx False) ts <*> mapM (evalBlocks ctx) ds) gs
  A.Table al h rows -> do
    h' <- mapM (evalInlines ctx False) h
    rows' <- mapM (mapM (evalInlines ctx False)) rows
    pure [block sp (Table (map alignment al) h' rows')]
  A.CodeBlock lang t -> pure [block sp (CodeBlock lang t)]
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
  A.BlockCommand name args body -> standalone ctx sp name args body
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
    case map A.locValue args of
      [A.Positional p, A.Positional (A.Word "as"), A.Positional (A.Word ns)] -> do
        let path = argText p
        if ns `elem` reservedNames
          then err "G0223" sp ("予約語は名前空間に使えません: " <> ns)
          else do
            let vals = fromMaybe Map.empty (Map.lookup (T.unpack path) (ctxImports ctx))
            modify' (\s -> s {stNamespaces = Map.insert ns vals (stNamespaces s), stImports = stImports s <> [(ns, T.unpack path, sp)]})
      _ -> err "G0309" sp "@import は「@import パス as 名前空間」の形で書きます"
    pure []
  "toc" -> do
    kw <- keywords ctx args
    let depth = maybe (Just 2) (intOf . argValueRaw) (lookup "depth" kw)
    case depth of
      Just d | d >= 1 && d <= 3 -> pure [block sp (ChannelOutput (TocOutput (fromInteger d)))]
      _ -> err "G0225" sp "@toc の depth は 1 から 3 の整数です" >> pure []
  "index" -> pure [block sp (ChannelOutput IndexOutput)]
  "bibliography" -> pure [block sp (ChannelOutput BibliographyOutput)]
  "figure" -> figure ctx sp args body
  "table" -> csvTable ctx sp args
  "listing" -> listing ctx sp args
  _
    | name `elem` attributeCommands -> err "G0210" sp ("@" <> name <> " の後にブロックがありません") >> pure []
    | otherwise -> err "G0209" nsp ("未知のブロックコマンドです: @" <> name) >> pure []

attributed :: EvalContext -> SrcSpan -> [A.Located A.Block] -> Maybe (A.Located A.Block) -> M [Block]
attributed ctx sp cmds target = case target of
  Nothing
    | (not . any isAttr) cmds -> concat <$> mapM (evalBlock ctx) cmds
    | otherwise -> err "G0210" sp "属性の後にブロックがありません" >> concat <$> mapM (evalBlock ctx) (filter (not . isAttr) cmds)
  Just t -> do
    let nonAttrs = filter (not . isAttr) cmds
        names = [n | A.Located _ (A.BlockCommand (A.Located _ n) _ _) <- cmds]
    unless (null nonAttrs) $ err "G0211" sp "属性のまとまりに属性でないコマンドがあります"
    when (length names /= length (nub names)) $ err "G0212" sp "同じ属性を二度書いています"
    targetBlocks <- evalBlock ctx t
    case targetBlocks of
      [Block bsp _ body] -> do
        (label, body') <- foldM' (applyAttr ctx) (Nothing, body) [c | c <- cmds, isAttr c]
        pure [Block bsp label body']
      other -> pure other
  where
    isAttr (A.Located _ (A.BlockCommand (A.Located _ n) _ _)) = n `elem` attributeCommands
    isAttr _ = False
    foldM' f z = foldl (\acc x -> acc >>= \a -> f a x) (pure z)

applyAttr :: EvalContext -> (Maybe Text, BlockBody) -> A.Located A.Block -> M (Maybe Text, BlockBody)
applyAttr ctx (label, body) (A.Located sp cmd) = case cmd of
  A.BlockCommand (A.Located _ name) args _ -> case (name, body) of
    ("label", _) -> case map A.locValue args of
      [A.Positional (A.Word l)] | validLabel l -> pure (Just l, body)
      _ -> err "G0226" sp "@label にはラベルの名前を一つ書きます" >> pure (label, body)
    ("toc-title", Heading l a is) -> do
      t <- evalInlines ctx True [A.Located sp (A.Text (T.unwords (map (argText . positional) args)))]
      pure (label, Heading l a {haTocTitle = Just t} is)
    ("number", Heading l a is) -> withNumber $ \n -> Heading l a {haNumber = Just n} is
    ("number", OrderedList (ListItem _ bs : rest)) -> withNumber $ \n -> OrderedList (ListItem (Just n) bs : rest)
    ("nonumber", Heading l a is) -> pure (label, Heading l a {haNoNumber = True} is)
    ("notoc", Heading l a is) -> pure (label, Heading l a {haNoToc = True} is)
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

validLabel :: Text -> Bool
validLabel l = not (T.null l) && T.all (\c -> c `elem` ("-_" :: String) || isAsciiLower c || isDigit c) l

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
          isPdf = ".pdf" `T.isSuffixOf` T.toLower path
      fine <- ok
      caption <- evalBlocks ctx body
      case look "alt" of
        Nothing -> err "G0228" sp "図版には alt の代替テキストが必要です" >> pure []
        Just alt
          | isPdf && isNothing web -> err "G0229" sp "PDF の図版には web の代替画像が必要です" >> pure []
          | not fine -> pure []
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
                  | otherwise -> pure [block sp (FigureBlock (Figure path web alt wr (look "width") caption))]
    _ -> err "G0232" sp "@figure には画像のパスを一つ書きます" >> pure []
  where
    check p
      | Map.member (T.unpack p) (ctxAssets ctx) = pure True
      | otherwise = err "G0233" sp ("ファイルがありません: " <> p) >> pure False

csvTable :: EvalContext -> SrcSpan -> [A.Located A.Argument] -> M [Block]
csvTable ctx sp args = do
  kw <- keywords ctx args
  case argText <$> lookup "src" kw of
    Nothing -> err "G0234" sp "@table には src が必要です" >> pure []
    Just src -> case Map.lookup (T.unpack src) (ctxAssets ctx) of
      Just (Just content) -> case parseCsv content of
        (h : rows)
          | all ((== length h) . length) rows ->
              let cell t = [Text sp t]
               in pure [block sp (Table (map (const AlignDefault) h) (map cell h) (map (map cell) rows))]
        [] -> err "G0235" sp "CSV が空です" >> pure []
        _ -> err "G0235" sp "CSV の行ごとのセルの数が一致しません" >> pure []
      _ -> err "G0233" sp ("ファイルがありません: " <> src) >> pure []

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
  let src = case [v | A.Located _ (A.Positional v) <- args] of
        (v : _) -> Just (argText v)
        [] -> argText <$> lookup "src" kw
  case src of
    Nothing -> err "G0236" sp "@listing にはファイルのパスが必要です" >> pure []
    Just p -> case Map.lookup (T.unpack p) (ctxAssets ctx) of
      Just (Just content) -> do
        let ls = T.lines content
        case argText <$> lookup "lines" kw of
          Nothing -> pure [block sp (CodeBlock Nothing (T.intercalate "\n" ls))]
          Just r -> case map (fmap fst . decimalInt) (T.splitOn "-" r) of
            [Just a, Just b]
              | a >= 1 && b >= a && b <= length ls ->
                  pure [block sp (CodeBlock Nothing (T.intercalate "\n" (take (b - a + 1) (drop (a - 1) ls))))]
            _ -> err "G0237" sp ("lines の範囲が不正です: " <> r) >> pure []
      _ -> err "G0233" sp ("ファイルがありません: " <> p) >> pure []
  where
    decimalInt x = if not (T.null x) && T.all isDigit x then Just (read (T.unpack x) :: Int, ()) else Nothing

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
evalInlines ctx inHeading is = mergeText . concat <$> mapM (evalInline ctx inHeading) is

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
  A.Command (A.Located nsp name) args slots
    | name `Set.member` phOverrides (ctxPlugins ctx) -> plugin
    | name `elem` builtinInlineCommands -> builtin ctx inHeading sp name args slots
    | name `Set.member` phCommands (ctxPlugins ctx) -> plugin
    | otherwise -> err "G0222" nsp ("未知のコマンドです: " <> name) >> pure []
    where
      plugin = do
        vals <- forM args $ \(A.Located _ a) -> case a of
          A.Positional v -> argValue ctx v
          A.Keyword _ v -> argValue ctx v
          _ -> pure (Right VNil)
        slots' <- mapM (evalInlines ctx inHeading) slots
        case sequence vals of
          Left d -> report d >> pure []
          Right vs -> case phCallCommand (ctxPlugins ctx) name vs slots' sp of
            Left ds -> mapM_ report ds >> pure []
            Right (out, ds) -> mapM_ report ds >> pure out

builtin :: EvalContext -> Bool -> SrcSpan -> Text -> [A.Located A.Argument] -> [[A.Located A.Inline]] -> M [Inline]
builtin ctx inHeading sp name args slots = do
  kw <- keywords ctx args
  let pos = [v | A.Located _ (A.Positional v) <- args]
      oneSlot k = case slots of
        [s] -> evalInlines ctx inHeading s >>= k
        _ -> err "G0238" sp (name <> " には散文スロットが一つ必要です") >> pure []
      noS1 k
        | inHeading = err "G0214" sp "見出しの中では相互参照を使えません" >> pure []
        | otherwise = k
  case name of
    "strong" -> oneSlot (pure . pure . Strong sp)
    "bold" -> oneSlot (pure . pure . Bold sp)
    "italic" -> oneSlot (pure . pure . Italic sp)
    "kenten" -> do
      let shape = argText <$> lookup "shape" kw
      case shape of
        Just s | s `notElem` kentenShapes -> err "G0239" sp ("未知の圏点の形です: " <> s) >> pure []
        _ -> oneSlot (pure . pure . Kenten sp shape)
    "color" -> case pos of
      [v] | argText v `Set.member` ctxSwatches ctx -> oneSlot (pure . pure . Color sp (argText v))
      [v] -> err "G0217" sp ("style.toml にないスウォッチです: " <> argText v) >> pure []
      _ -> err "G0217" sp "color にはスウォッチの名前を一つ書きます" >> pure []
    "style" -> case pos of
      [v] | argText v `Set.member` ctxCharStyles ctx -> oneSlot (pure . pure . CharStyle sp (argText v))
      [v] -> err "G0218" sp ("style.toml にない文字スタイルです: " <> argText v) >> pure []
      _ -> err "G0218" sp "style には文字スタイルの名前を一つ書きます" >> pure []
    "tcy" -> oneSlot $ \case
      [Text _ t] -> pure [Tcy sp t]
      [] -> pure []
      _ -> err "G0240" sp "縦中横の中身は地の文に限ります" >> pure []
    "number-text" -> case pos of
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
      _ -> err "G0219" sp "number-text には数を一つ書きます" >> pure []
    "ref-number" -> noS1 (refTo RefNumber pos)
    "ref-title" -> noS1 (refTo RefTitle pos)
    "ref-page" -> noS1 (refTo RefPage pos)
    "note" -> oneSlot $ \body -> do
      n <- gets ((+ 1) . stNote)
      modify' (\s -> s {stNote = n})
      pure [Note sp n body]
    "sidenote" -> oneSlot $ \body -> do
      n <- gets ((+ 1) . stSidenote)
      modify' (\s -> s {stSidenote = n})
      pure [Sidenote sp n body]
    "index" -> case slots of
      [s] -> do
        body <- evalInlines ctx inHeading s
        case (plainText body, argText <$> lookup "reading" kw) of
          (_, Nothing) -> err "G0220" sp "索引には reading が必要です" >> pure []
          (Nothing, _) -> err "G0241" sp "索引の語は地の文に限ります" >> pure []
          (Just term, Just reading) ->
            let ts = T.splitOn "/" term
                rs = T.splitOn "/" reading
             in if length ts > 2 || length ts /= length rs || any T.null (ts <> rs)
                  then err "G0242" sp "索引の語と読みの段の数が不正です" >> pure []
                  else pure [IndexMark sp (IndexEntry ts rs)]
      _ -> err "G0238" sp "index には散文スロットが一つ必要です" >> pure []
    "cite" -> case pos of
      [v] | argText v `Set.member` ctxCiteKeys ctx -> pure [Cite sp (argText v)]
      [v] -> err "G0221" sp ("書誌データにないキーです: " <> argText v) >> pure []
      _ -> err "G0221" sp "cite には書誌データのキーを一つ書きます" >> pure []
    "ruby" -> ruby ctx sp slots
    _ -> err "G0222" sp ("未知のコマンドです: " <> name) >> pure []
  where
    refTo k = \case
      [v] | validLabel (argText v) -> pure [Ref sp k (argText v)]
      _ -> err "G0226" sp "参照にはラベルの名前を一つ書きます" >> pure []

plainText :: [Inline] -> Maybe Text
plainText is = T.concat <$> traverse (\case Text _ t -> Just t; _ -> Nothing) is

ruby :: EvalContext -> SrcSpan -> [[A.Located A.Inline]] -> M [Inline]
ruby ctx sp = \case
  [baseSlot, readingSlot] -> do
    base <- evalInlines ctx False baseSlot
    reading <- evalInlines ctx False readingSlot
    case (traverse noRuby base, plainText reading) of
      (Nothing, _) -> err "G0216" sp "ルビの中にルビは入れられません" >> pure []
      (_, Nothing) -> err "G0243" sp "ルビの読みは地の文に限ります" >> pure []
      (Just nb, Just r) -> do
        let baseSegs = splitSegments nb
            readSegs = T.splitOn "/" r
        if length baseSegs == 1
          then pure [Ruby sp () [RubySegment nb (Just r)]]
          else
            if length baseSegs /= length readSegs
              then err "G0215" sp "モノルビの対象と読みのセグメントの数が一致しません" >> pure []
              else pure [Ruby sp () [RubySegment b (if T.null rd then Nothing else Just rd) | (b, rd) <- zip baseSegs readSegs]]
  _ -> err "G0238" sp "ruby には散文スロットが二つ必要です" >> pure []

-- | Split a ruby base at '/' inside its top-level text.
splitSegments :: [InlineNoRuby] -> [[InlineNoRuby]]
splitSegments = foldr step [[]]
  where
    step (Text s t) (cur : rest) =
      let parts = T.splitOn "/" t
          pieces = [[Text s p | not (T.null p)] | p <- parts]
       in case pieces of
            [] -> cur : rest
            _ -> init pieces <> [last pieces <> cur] <> rest
    step x (cur : rest) = (x : cur) : rest
    step _ [] = [[]]

-- ------------------------------------------------------------------ arguments

keywords :: EvalContext -> [A.Located A.Argument] -> M [(Text, A.ArgValue)]
keywords _ args = pure [(k, v) | A.Located _ (A.Keyword (A.Located _ k) v) <- args]

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
