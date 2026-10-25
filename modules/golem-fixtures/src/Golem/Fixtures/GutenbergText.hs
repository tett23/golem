{- | Converts a Project Gutenberg text that is not a play of the Cambridge
Shakespeare (plain text, UTF-8) into Golem source (docs/adr/0026).

The body is split into blocks at blank lines, and each block is judged by
its shape, in this order: a heading by its prefix (--heading), the two
columns of an example (--two-columns), a speech (--speakers), a heading of
capitals (--caps-heading), a numbered heading (--numbered-headings), verse,
a quotation (an indented block) and a paragraph. The rules guess from the
shape of the lines, so they are tuned to the texts of the fixtures.
-}
module Golem.Fixtures.GutenbergText
  ( TextOptions (..),
    defaultTextOptions,
    convertText,
  )
where

import Data.Char (isDigit, isLetter, isLower, isUpper)
import Data.List (mapAccumL)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Fixtures.Python

-- | The options of gutenberg-text (docs/adr/0026).
data TextOptions = TextOptions
  { -- | the body starts at the line equal to this
    optStart :: Maybe Text,
    -- | the body ends before the line equal to this
    optEnd :: Maybe Text,
    -- | blocks starting with one of these are headings of level 1
    optHeadings :: [Text],
    -- | the level of the headings of one line of capitals
    optCapsHeading :: Maybe Int,
    -- | blocks starting with "N. " are headings of level 2
    optNumberedHeadings :: Bool,
    -- | blocks starting with "NAME. " are speeches
    optSpeakers :: Bool,
    -- | short or indented blocks are verse
    optVerse :: Bool,
    -- | a block indented by two followed by one indented by four is a row
    optTwoColumns :: Bool,
    -- | the notes follow the line equal to this
    optNotes :: Maybe Text,
    -- | =...= is bold
    optBoldEquals :: Bool
  }
  deriving stock (Eq, Show)

defaultTextOptions :: TextOptions
defaultTextOptions = TextOptions Nothing Nothing [] Nothing False False False False Nothing False

type Notes = Map.Map Text Text

convertText :: TextOptions -> Text -> Either String Text
convertText opts src = do
  afterStart <- case T.breakOn "*** START OF THE PROJECT GUTENBERG EBOOK" src of
    (_, r) | not (T.null r) -> Right (drop 1 (T.splitOn "\n" r))
    _ -> Left "no START OF THE PROJECT GUTENBERG EBOOK"
  let body0 = takeWhile (not . ("*** END OF THE PROJECT GUTENBERG EBOOK" `T.isPrefixOf`)) afterStart
  body1 <- maybe (Right body0) (\s -> snd <$> splitAtLine True s body0) (optStart opts)
  (body2, noteLines) <- maybe (Right (body1, [])) (\m -> splitAtLine False m body1) (optNotes opts)
  body3 <- maybe (Right body2) (\e -> fst <$> splitAtLine False e body2) (optEnd opts)
  let notes = Map.fromList (concatMap (noteOf opts) (toBlocks noteLines))
  pure (T.intercalate "\n\n" (convertBlocks opts notes (toBlocks body3)) <> "\n")

{- | The lines before and after the first line equal to the text (stripped);
the line itself starts the second part if asked, else it is dropped.
-}
splitAtLine :: Bool -> Text -> [Text] -> Either String ([Text], [Text])
splitAtLine keep marker ls = case break ((== marker) . pyStrip) ls of
  (before, l : after) -> Right (before, if keep then l : after else after)
  _ -> Left ("no line " <> show (T.unpack marker))

-- | A note @[N] text@: its number and its text, rendered for a slot.
noteOf :: TextOptions -> [Text] -> [(Text, Text)]
noteOf opts b = case T.stripPrefix "[" (joined b) of
  Just r
    | (n, r') <- T.span isDigit r,
      not (T.null n),
      Just body <- T.stripPrefix "]" r' ->
        [(n, render opts True Map.empty (pyLStrip body))]
  _ -> []

convertBlocks :: TextOptions -> Notes -> [[Text]] -> [Text]
convertBlocks opts notes = go
  where
    go [] = []
    go bs
      | optTwoColumns opts, (rows@(_ : _), rest) <- rowsOf bs = table rows : go rest
    go (b : rest) = block b <> go rest
    rowsOf (l : r : rest)
      | minIndent l == 2,
        minIndent r == 4 =
          let (rows, rest') = rowsOf rest in ((l, r) : rows, rest')
    rowsOf bs = ([], bs)
    table rows =
      T.intercalate "\n" ("| | |" : "|---|---|" : ["| " <> cell l <> " | " <> cell r <> " |" | (l, r) <- rows])
    cell = render opts True notes . joined
    block [] = []
    block b@(b0 : bs)
      | any (`T.isPrefixOf` first) (optHeadings opts) = [heading 1 b]
      | optSpeakers opts, Just (name, rest) <- speaker first = speech name rest b
      | Just n <- optCapsHeading opts, null bs, isCaps first = [heading n b]
      | optNumberedHeadings opts, length b <= 3, minIndent b == 0, numbered first = [heading 2 b]
      | isVerse opts b = [verse opts notes Nothing b]
      | minIndent b >= 2 = ["@style quote\n" <> paragraph (joined b)]
      | otherwise = [paragraph (joined b)]
      where
        first = pyStrip b0
    -- a speech: the speaker's name, then the words in prose or verse
    speech name rest b
      | T.null rest = strong name : if null more then [] else block more
      | isVerse opts b = [verse opts notes (Just name) b]
      | otherwise = [strong name <> " " <> render opts False notes (joined (rest : more))]
      where
        more = drop 1 b
    strong name = "[strong: " <> escapeSlot name <> "]"
    heading n b = "@nonumber\n" <> T.replicate n "#" <> " " <> render opts False notes (joined b)
    paragraph = escapeLineStart . render opts False notes

-- | The lines of a block joined by spaces, with @--@ made a dash.
joined :: [Text] -> Text
joined = T.replace "--" "—" . collapseSpace . T.unwords . map pyStrip

minIndent :: [Text] -> Int
minIndent [] = 0
minIndent b = minimum (map indentOf b)

-- | One line of no lowercase letters and two letters or more.
isCaps :: Text -> Bool
isCaps t = T.length (T.filter isLetter t) >= 2 && not (T.any isLower t)

-- | @^[0-9]+\. @
numbered :: Text -> Bool
numbered t = let (d, r) = T.span isDigit t in not (T.null d) && ". " `T.isPrefixOf` r

{- | @NAME. rest@: a name of capitals (and "and") up to its last word ending
with a full stop, of two capitals or more.
-}
speaker :: Text -> Maybe (Text, Text)
speaker s =
  case [i | (i, w) <- zip [0 :: Int ..] nameWords, "." `T.isSuffixOf` w] of
    [] -> Nothing
    is ->
      let name = T.unwords (take (last is + 1) nameWords)
       in if T.length (T.filter isUpper name) >= 2
            then Just (name, pyStrip (T.drop (T.length name) s))
            else Nothing
  where
    nameWords = takeWhile isNameWord (T.splitOn " " s)
    isNameWord w =
      w == "and"
        || let core = fromMaybe w (T.stripSuffix "." w)
            in not (T.null core) && T.any isUpper core && T.all (\c -> isUpper c || c `elem` ("'’-" :: String)) core

{- | Two lines or more of verse. With --verse: lines all short or all
indented. Without: all indented, all starting with a capital, and not
wrapped prose (some line before the last is short).
-}
isVerse :: TextOptions -> [Text] -> Bool
isVerse opts b
  | length b < 2 = False
  | optVerse opts = all ((< 60) . T.length . pyStrip) b || all ((>= 2) . indentOf) b
  | otherwise = all ((>= 2) . indentOf) b && all startsUpper b && any ((< 60) . T.length . pyStrip) (init b)
  where
    startsUpper l = case T.uncons (T.dropWhile (`elem` ("\"“”‘’'(_[" :: String)) (pyStrip l)) of
      Just (c, _) -> isUpper c
      Nothing -> False

{- | @style verse: one line per line, a line after a long one and starting
in lowercase joined to it (the source wrapped it), the indent beyond the
shallowest line as [aki], two spaces to 1zw. The speaker's name, if any,
starts the first line and is set apart in [strong].
-}
verse :: TextOptions -> Notes -> Maybe Text -> [Text] -> Text
verse opts notes name b =
  "@style verse\n" <> T.intercalate "\n" ["  " <> l | l <- rendered, not (T.null l)]
  where
    lines' = foldl join' [] b
    join' acc l = case acc of
      _ | null acc -> [(indentOf l, pyStrip l)]
      _
        | (i, prev) <- last acc,
          T.length prev >= 66,
          Just (c, _) <- T.uncons (pyStrip l),
          isLower c ->
            init acc <> [(i, prev <> " " <> pyStrip l)]
      _ -> acc <> [(indentOf l, pyStrip l)]
    base = minimum (map fst lines')
    rendered = snd (mapAccumL line (False, False) (zip [0 :: Int ..] lines'))
    line st (k, (i, l)) =
      let (prefix, l') = case name of
            Just n | k == 0 -> ("[strong: " <> escapeSlot n <> "] ", pyStrip (T.drop (T.length n) l))
            _ -> ("", l)
          (body, st') = renderFrom opts False notes st (T.replace "--" "—" (collapseSpace l'))
          aki = akiOf (i - base)
          text
            | T.null prefix && T.null aki = escapeLineStart body
            | otherwise = prefix <> aki <> body
       in (st', pyRStrip text)

-- | [aki] of n spaces, two spaces to 1zw.
akiOf :: Int -> Text
akiOf n
  | n <= 0 = ""
  | even n = "[aki " <> T.pack (show (n `div` 2)) <> "zw]"
  | otherwise = "[aki " <> T.pack (show (n `div` 2)) <> ".5zw]"

data Tok = C Char | Raw Text

-- | Inline text: _italic_, =bold= (--bold-equals) and note marks.
render :: TextOptions -> Bool -> Notes -> Text -> Text
render opts inSlot notes = fst . renderFrom opts inSlot notes (False, False)

{- | The rendering of a text from a state of (italic, bold), and the state at
its end, so that styles continue on the next line of verse.
-}
renderFrom :: TextOptions -> Bool -> Notes -> (Bool, Bool) -> Text -> (Text, (Bool, Bool))
renderFrom opts inSlot notes st0 text = (T.concat (map group' (groupRuns styled)), final)
  where
    (final, styled) = mapAccumL step st0 (tokens (T.unpack text))
    step st@(it, bd) = \case
      Left '_' -> ((not it, bd), Nothing)
      Left _ -> ((it, not bd), Nothing)
      Right t -> (st, Just (st, t))
    tokens = \case
      [] -> []
      '_' : r -> Left '_' : tokens r
      '=' : r | optBoldEquals opts -> Left '=' : tokens r
      '[' : r
        | (d@(_ : _), ']' : r') <- span isDigit r,
          Just n <- Map.lookup (T.pack d) notes ->
            Right (Raw ("[note: " <> n <> "]")) : tokens r'
      c : r -> Right (C c) : tokens r
    groupRuns = foldr add [] . concatMap (maybe [] pure)
      where
        add (s, t) ((s', ts) : rest) | s == s' = (s, t : ts) : rest
        add (s, t) rest = (s, [t]) : rest
    group' ((it, bd), toks)
      | not it && not bd = plain inSlot toks
      | otherwise =
          let lead = takeWhile isSpace' toks
              rest = dropWhile isSpace' toks
              core = reverse (dropWhile isSpace' (reverse rest))
              trail = if null rest then [] else reverse (takeWhile isSpace' (reverse rest))
              inner = plain True core
              wrapped
                | null core = ""
                | otherwise = wrap bd "bold" (wrap it "italic" inner)
           in plain inSlot lead <> wrapped <> plain inSlot trail
    isSpace' (C ' ') = True
    isSpace' _ = False
    wrap on name t = if on then "[" <> name <> ": " <> t <> "]" else t
    -- characters escaped, runs of them with %% escaped; raw markup as it is
    plain slot = T.concat . map piece . segments
      where
        piece (Left cs) = T.replace "%%" "\\%%" (T.concat (map (esc slot) cs))
        piece (Right raw) = raw
    segments = foldr seg []
      where
        seg (C c) (Left cs : rest) = Left (c : cs) : rest
        seg (C c) rest = Left [c] : rest
        seg (Raw t) rest = Right t : rest
    esc slot c = case c of
      '\\' -> "\\\\"
      '[' -> "\\["
      ']' | slot -> "\\]"
      '|' | slot -> "\\|"
      _ -> T.singleton c
