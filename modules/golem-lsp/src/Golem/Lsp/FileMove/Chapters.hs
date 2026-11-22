module Golem.Lsp.FileMove.Chapters
  ( transferChapters,
    ChapterTransfer (..),
    ByteEdit,
  )
where

import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.List (find)
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

{- | Transfer complete chapter occurrences. Text between the value spans is
assigned to the adjacent chapters, including comments after commas.
-}
transferChapters :: (FilePath -> Either String (Maybe (FilePath, FilePath))) -> Text -> Maybe Text -> Either String ([ByteEdit], [ByteEdit], [ChapterTransfer])
transferChapters moved source destination = do
  ChapterInput parsedSource (Array _ _ nodes tailText) editSource <- chapters source
  partitioned <- traverse (uncurry (splitNode moved parsedSource [])) (zip [0 ..] nodes)
  let (remaining, transferred, occurrences) = collect partitioned
  if null occurrences
    then pure ([], [], [])
    else do
      replaceDestination <- traverse (append transferred) destination
      pure (editSource (render remaining tailText), concat replaceDestination, occurrences)
  where
    append transferred text = do
      ChapterInput _ (Array _ _ existing ending) editDestination <- chapters text
      let existingNodes = [node | Parsed node _ _ <- existing]
          extra = case transferred of
            [] -> []
            firstNode : rest -> firstNode {before = "\n" <> before firstNode} : rest
      pure (editDestination (render (existingNodes <> extra) ending))

collect :: [(Maybe Node, Maybe Node, [ChapterTransfer])] -> ([Node], [Node], [ChapterTransfer])
collect triples =
  (catMaybes [a | (a, _, _) <- triples], catMaybes [b | (_, b, _) <- triples], concat [xs | (_, _, xs) <- triples])

splitNode :: (FilePath -> Either String (Maybe (FilePath, FilePath))) -> Text -> [Int] -> Int -> Parsed -> Either String (Maybe Node, Maybe Node, [ChapterTransfer])
splitNode moved source prefix i (Parsed node value nested) =
  case nested of
    Just (Array _ _ nodes tailText) -> do
      (remaining, transferred, occurrences) <- collect <$> traverse (uncurry (splitNode moved source indices)) (zip [0 ..] nodes)
      let kept = Just node {contents = render remaining tailText}
          taken = Just node {contents = render transferred tailText}
      pure $
        if null occurrences
          then (Just node, Nothing, [])
          else
            if null remaining
              then (Nothing, taken, occurrences)
              else (kept, Just (Node "" (render transferred "") ""), occurrences)
    Nothing -> do
      (pos, path) <- chapterPath value
      target <- moved (T.unpack path)
      case target of
        Nothing -> pure (Just node, Nothing, [])
        Just (workspaceNew, written) -> do
          let at = posIndex pos
              start = valueStart value
          end <- tokenEnd source at
          let updated = T.take (at - start) (contents node) <> quotedToml (T.pack written) <> T.drop (end - start) (contents node)
          pure (Nothing, Just node {contents = updated}, [ChapterTransfer (T.unpack path) workspaceNew indices])
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
