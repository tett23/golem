module Golem.Lsp.FileMove.Chapters
  ( transferChapters,
    ChapterTransfer (..),
    ByteEdit,
    Placement (..),
    Partition,
    Node,
    partitionChapters,
    partitionOutgoing,
    partitionTransfers,
    rebuildChapters,
  )
where

import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.List (find, nub)
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.FileRename (quotedToml)
import Golem.Project.Manifest (readTomlTable)
import Prettyprinter (layoutCompact)
import Prettyprinter.Render.Text (renderStrict)
import Toml.Pretty (prettyValue)
import Toml.Semantics (Table' (..), Value' (..))
import Toml.Syntax (parseRawToml)
import Toml.Syntax.Lexer (Context (..), Token (..), scanToken)
import Toml.Syntax.Position (Located (..), Position (..), startPos)
import Toml.Syntax.Types (Expr (..), Val (..))

type ByteEdit = (Int, Int, Text)

data ChapterTransfer = ChapterTransfer
  { chapterOld :: !FilePath,
    chapterNew :: !FilePath,
    chapterIndices :: ![Int]
  }
  deriving stock (Eq, Show)

data Node = Node
  { before :: !Text,
    contents :: !Text,
    after :: !Text
  }

data Array = Array !Int !Int ![Parsed] !Text

data ChapterInput = ChapterInput !Text !Array !(Text -> [ByteEdit])

data Parsed = Parsed !Node !(Val Position) !(Maybe Array)

-- | Where one chapter entry goes when a manifest is planned for moves.
data Placement d
  = -- | The entry stays as it is.
    Keep
  | -- | The entry stays in this manifest under a new written path.
    Rewrite !FilePath
  | {- | The entry leaves for the destination @d@. The 'Int' orders the
    entries appended to a destination; then the workspace path after the
    move and the path written in the destination manifest.
    -}
    Transfer !d !Int !FilePath !FilePath

-- | A manifest's chapters split into the entries that stay and those that leave.
data Partition d = Partition
  { remainingNodes :: ![Node],
    tailText :: !Text,
    editArray :: !(Text -> [ByteEdit]),
    partitionOutgoing :: ![(d, Int, Node)],
    partitionTransfers :: ![(d, Int, ChapterTransfer)]
  }

{- | Transfer complete chapter occurrences. Text between the value spans is
assigned to the adjacent chapters, including comments after commas.
-}
transferChapters :: (FilePath -> Either String (Maybe (FilePath, FilePath))) -> Text -> Maybe Text -> Either String ([ByteEdit], [ByteEdit], [ChapterTransfer])
transferChapters moved source destination = do
  part <- partitionChapters (\path -> path >>= fmap (maybe Keep (uncurry (Transfer () 0))) . moved) source
  if null (partitionTransfers part)
    then pure ([], [], [])
    else do
      replaceDestination <- traverse (append [node | (_, _, node) <- partitionOutgoing part]) destination
      pure (rebuildChapters part [], concat replaceDestination, [transfer | (_, _, transfer) <- partitionTransfers part])
  where
    append transferred text = do
      existing <- partitionChapters (const (Right Keep)) text
      pure (rebuildChapters (existing :: Partition ()) transferred)

{- | Split a manifest's chapters by the placement of each entry. The
classifier receives the entry's path, or why the entry has none.
-}
partitionChapters :: (Eq d) => (Either String FilePath -> Either String (Placement d)) -> Text -> Either String (Partition d)
partitionChapters classify source = do
  ChapterInput parsedSource (Array _ _ nodes ending) edit <- chapters source
  parts <- traverse (uncurry (splitNode classify parsedSource [])) (zip [0 ..] nodes)
  pure
    Partition
      { remainingNodes = catMaybes [kept | Split kept _ _ _ <- parts],
        tailText = ending,
        editArray = edit,
        partitionOutgoing = concat [taken | Split _ taken _ _ <- parts],
        partitionTransfers = concat [occurrences | Split _ _ occurrences _ <- parts]
      }

{- | The edits that replace the chapters array with the entries that stay,
followed by the incoming entries in the given order.
-}
rebuildChapters :: Partition d -> [Node] -> [ByteEdit]
rebuildChapters part incoming = editArray part (render (remainingNodes part <> extra) (tailText part))
  where
    extra = case incoming of
      [] -> []
      firstNode : rest -> firstNode {before = "\n" <> before firstNode} : rest

data Split d = Split !(Maybe Node) ![(d, Int, Node)] ![(d, Int, ChapterTransfer)] !Bool

splitNode :: (Eq d) => (Either String FilePath -> Either String (Placement d)) -> Text -> [Int] -> Int -> Parsed -> Either String (Split d)
splitNode classify source prefix i (Parsed node value nested) =
  case nested of
    Just (Array _ _ nodes ending) -> do
      parts <- traverse (uncurry (splitNode classify source indices)) (zip [0 ..] nodes)
      let remaining = catMaybes [kept | Split kept _ _ _ <- parts]
          taken = concat [t | Split _ t _ _ <- parts]
          occurrences = concat [o | Split _ _ o _ <- parts]
          changed = or [c | Split _ _ _ c <- parts]
          groups = [(d, minimum [k | (d', k, _) <- taken, d' == d], [n | (d', _, n) <- taken, d' == d]) | d <- nub [d | (d, _, _) <- taken]]
      pure $
        if null occurrences
          then Split (Just (if changed then node {contents = render remaining ending} else node)) [] [] changed
          else case groups of
            [(d, k, transferred)]
              | null remaining -> Split Nothing [(d, k, node {contents = render transferred ending})] occurrences True
            _ ->
              Split
                (if null remaining then Nothing else Just node {contents = render remaining ending})
                [(d, k, Node "" (render transferred "") "") | (d, k, transferred) <- groups]
                occurrences
                True
    Nothing -> case chapterPath value of
      Left reason -> do
        placement <- classify (Left reason)
        case placement of
          Keep -> pure (Split (Just node) [] [] False)
          _ -> Left reason
      Right (pos, path) -> do
        placement <- classify (Right (T.unpack path))
        let written new = do
              let at = posIndex pos
                  start = valueStart value
              end <- tokenEnd source at
              pure (T.take (at - start) (contents node) <> quotedToml (T.pack new) <> T.drop (end - start) (contents node))
        case placement of
          Keep -> pure (Split (Just node) [] [] False)
          Rewrite new -> do
            updated <- written new
            pure (Split (Just node {contents = updated}) [] [] True)
          Transfer d k workspaceNew new -> do
            updated <- written new
            pure (Split Nothing [(d, k, node {contents = updated})] [(d, k, ChapterTransfer (T.unpack path) workspaceNew indices)] True)
  where
    indices = prefix <> [i]

chapterPath :: Val Position -> Either String (Position, Text)
chapterPath (ValString pos path) = Right (pos, path)
chapterPath (ValTable _ vals) =
  case find ((== ["file"]) . map snd . NE.toList . fst) vals of
    Just (_, ValString pos path) -> Right (pos, path)
    _ -> Left "chapter table has no file string"
chapterPath _ = Left "invalid chapter entry"

chapters :: Text -> Either String ChapterInput
chapters source = do
  exprs <- first locThing (parseRawToml source)
  case [v | KeyValExpr key v <- takeWhile keyValue exprs, names key == ["chapters"]] of
    [ValArray pos values] -> do
      array@(Array start end _ _) <- parseArray source (posIndex pos) values
      pure (ChapterInput source array (pure . byteEdit source start end))
    [] -> arrayTables source exprs
    _ -> Left "expected one top-level chapters array"
  where
    keyValue (KeyValExpr _ _) = True
    keyValue _ = False

names :: NE.NonEmpty (Position, Text) -> [Text]
names = map snd . NE.toList

-- TOML array tables are the same chapter values in a different spelling.
-- Convert just the chapter sections to an array, leaving other sections in place.
arrayTables :: Text -> [Expr Position] -> Either String ChapterInput
arrayTables source expressions = do
  MkTable table <- maybe (Left "invalid manifest TOML") Right (readTomlTable source)
  items <- case Map.lookup "chapters" table of
    Just (_, List' _ values) -> Right values
    _ -> Left "manifest does not contain a chapters array"
  ranges <- sectionRanges (runs expressions)
  if null ranges || length ranges /= length items
    then Left "could not locate chapter table sections"
    else do
      withComments <- traverse (uncurry comments) ranges
      let values = zipWith (\comment item -> comment <> renderStrict (layoutCompact (prettyValue item))) withComments items
          normalized = "[" <> T.intercalate ",\n" values <> "]"
      raw <- first locThing (parseRawToml ("chapters = " <> normalized))
      case raw of
        [KeyValExpr _ (ValArray at values')] -> do
          let parsed = "chapters = " <> normalized
          array <- parseArray parsed (posIndex at) values'
          pure (ChapterInput parsed array (write ranges))
        _ -> Left "could not represent chapter tables"
  where
    runs [] = []
    runs (expression : rest) = case expression of
      ArrayTableExpr key
        | names key == ["chapters"] ->
            let (body, afterSection) = span belongs rest
             in (expression, body) : runs afterSection
      _ -> runs rest
    belongs (KeyValExpr _ _) = True
    belongs (TableExpr key) = take 1 (names key) == ["chapters"]
    belongs (ArrayTableExpr key) = take 1 (names key) == ["chapters"] && length key > 1
    sectionRanges = traverse $ \(header, body) -> do
      end <- case reverse body of
        KeyValExpr _ v : _ -> tokenEnd source (valueStart v)
        lastExpr : _ -> pure (exprIndex lastExpr)
        [] -> pure (exprIndex header)
      pure (withLeadingComments (lineStart (exprIndex header)), lineEnd end)
    exprIndex =
      posIndex . fst . NE.head . \case
        KeyValExpr key _ -> key
        TableExpr key -> key
        ArrayTableExpr key -> key
    lineStart index =
      let prefix = T.take index source
       in index - T.length (T.takeWhileEnd (/= '\n') prefix)
    withLeadingComments index =
      let preceding = reverse (T.lines (T.take index source))
          attached = takeWhile (T.isPrefixOf "#" . T.stripStart) preceding
       in index - sum (map ((+ 1) . T.length) attached)
    lineEnd index =
      let rest = T.drop index source
          (line, ending) = T.breakOn "\n" rest
       in index + T.length line + if T.null ending then 0 else 1
    comments a b = scanComments (T.take (b - a) (T.drop a source))
    write ranges replacement =
      case ranges of
        (0, firstEnd) : rest -> byteEdit source 0 firstEnd ("chapters = " <> replacement <> "\n") : deletes rest
        _ -> byteEdit source 0 0 ("chapters = " <> replacement <> "\n") : deletes ranges
    deletes = map (\(a, b) -> byteEdit source a b "")

-- A lexer token may include arbitrary string contents. Read comments only in
-- the trivia the lexer skipped before the next token.
scanComments :: Text -> Either String Text
scanComments section = T.concat <$> go (Located startPos section)
  where
    go cursor = do
      (Located at token, next) <- lexToken cursor
      let count = posIndex at - posIndex (locPosition cursor)
          trivia = T.take count (locThing cursor)
          notes = [line <> "\n" | raw <- T.lines trivia, let line = T.stripStart raw, "#" `T.isPrefixOf` line]
      rest <- case token of
        TokEOF -> Right []
        _ -> go next
      pure (notes <> rest)

parseArray :: Text -> Int -> [Val Position] -> Either String Array
parseArray source start values = do
  end <- tokenEnd source start
  (nodes, ending) <- go (start + 1) (end - 1) values
  pure (Array start end nodes ending)
  where
    go offset close [] = Right ([], chunk offset close)
    go offset close (value : rest) = do
      let at = valueStart value
      end <- tokenEnd source at
      let next = case rest of
            [] -> close
            nextValue : _ -> valueStart nextValue
          (sameLine, restTrivia) = T.breakOn "\n" (chunk end next)
          sameLineWithoutComma = dropComma sameLine
          attaches = "#" `T.isPrefixOf` T.stripStart sameLineWithoutComma
          afterText = if attaches then sameLineWithoutComma else ""
          nextOffset = if attaches then next - T.length restTrivia else end
          leading = dropComma (chunk offset at)
      nested <- case value of
        ValArray _ children -> Just <$> parseArray source at children
        _ -> Right Nothing
      (remaining, ending) <- go nextOffset close rest
      pure (Parsed (Node leading (chunk at end) afterText) value nested : remaining, dropComma ending)
    chunk a b = T.take (b - a) (T.drop a source)
    dropComma text =
      let (space, suffix) = T.span (\c -> c == ' ' || c == '\t' || c == '\r' || c == '\n') text
       in maybe text (space <>) (T.stripPrefix "," suffix)

render :: [Node] -> Text -> Text
render nodes ending = "[" <> T.concat (zipWith entry nodes (map (const True) (drop 1 nodes) <> [False])) <> cleanEnding <> "]"
  where
    entry node more = before node <> contents node <> (if more then "," else "") <> after node <> if T.null (after node) then "" else "\n"
    cleanEnding
      | null nodes && T.all (\c -> c == '\n' || c == '\r' || c == '\t' || c == ' ') ending = ""
      | otherwise = ending

valueStart :: Val Position -> Int
valueStart =
  posIndex . \case
    ValInteger pos _ -> pos
    ValFloat pos _ -> pos
    ValArray pos _ -> pos
    ValTable pos _ -> pos
    ValBool pos _ -> pos
    ValString pos _ -> pos
    ValTimeOfDay pos _ -> pos
    ValZonedTime pos _ -> pos
    ValLocalTime pos _ -> pos
    ValDay pos _ -> pos

{- | Reuse the TOML lexer so quotes, multiline strings and bracket-like
comments cannot be mistaken for punctuation.
-}
tokenEnd :: Text -> Int -> Either String Int
tokenEnd source start = do
  (Located _ token, remaining) <- lexToken (Located startPos {posIndex = start} (T.drop start source))
  seek (opens token) remaining
  where
    opens TokSquareO = 1 :: Int
    opens TokCurlyO = 1
    opens TokSquareC = -1
    opens TokCurlyC = -1
    opens _ = 0
    seek 0 remaining = Right (posIndex (locPosition remaining))
    seek depth input = do
      (Located _ token, remaining) <- lexToken input
      case token of
        TokEOF -> Left "unterminated chapter value"
        _ -> seek (depth + opens token) remaining

lexToken :: Located Text -> Either String (Located Token, Located Text)
lexToken input = case scanToken ValueContext input of
  Right token -> Right token
  Left _ -> first locThing (scanToken TableContext input)

byteEdit :: Text -> Int -> Int -> Text -> ByteEdit
byteEdit text start end replacement = (byte start, byte end, replacement)
  where
    byte index = BS.length (TE.encodeUtf8 (T.take index text))
