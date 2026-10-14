{- | Converts a Shakespeare play of the Project Gutenberg Cambridge edition
(plain text, UTF-8) into Golem source (docs/adr/0023).

Kept: the list of characters and the play to the end of the epilogue.
Dropped: the Gutenberg header and licence, the transcriber's note, the
title page, footnotes and textual notes, line numbers.

Verse becomes @style verse (docs/adr ADR 0003, 0005). The source marks
verse only by its line breaks, which prose also has where it was wrapped,
so verse is guessed: a speech of two lines or more whose every line after
the first starts a half line, is a stage direction, or starts with a
capital, and a song indented as a whole. Short prose speeches of
capitalised lines are taken for verse.

The rules are those of the Python script that this replaces, and give the
same bytes for the same input.
-}
module Golem.Fixtures.Gutenberg (convertPlay) where

import Data.Char (isUpperCase)
import Data.List (findIndex, mapAccumL)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Fixtures.Python

convertPlay :: Text -> Either String Text
convertPlay src = do
  afterStart <- case T.splitOn "*** START OF THE PROJECT GUTENBERG EBOOK" src of
    _ : s : _ -> Right s
    _ -> Left "no START OF THE PROJECT GUTENBERG EBOOK"
  let body = fst (T.breakOn "*** END OF THE PROJECT GUTENBERG EBOOK" afterStart)
      lines' = drop 1 (T.splitOn "\n" body)
  start <- maybe (Left "no DRAMATIS PERSON") Right (findIndex ("DRAMATIS PERSON" `T.isPrefixOf`) lines')
  end <- maybe (Left "no NOTES.") Right (findIndex ((== "NOTES.") . pyStrip) lines')
  let blocks = toBlocks (take (end - start) (drop start lines'))
  pure (T.intercalate "\n\n" (convertBlocks blocks) <> "\n")

-- | Blocks of lines between blank lines, each line without trailing space.
toBlocks :: [Text] -> [[Text]]
toBlocks = filter (not . null) . go []
  where
    go cur [] = [reverse cur]
    go cur (l : ls)
      | T.null (pyStrip l) = reverse cur : go [] ls
      | otherwise = go (pyRStrip l : cur) ls

data St = St {inDramatis :: Bool, inNotes :: Bool}

convertBlocks :: [[Text]] -> [Text]
convertBlocks = concat . snd . mapAccumL block (St False False)

block :: St -> [Text] -> (St, [Text])
block st [] = (st, [])
block st b@(b0 : bs)
  -- textual notes run from "Notes: ..." to the next act, scene or epilogue
  | "Notes:" `T.isPrefixOf` first = (st {inNotes = True}, [])
  | inNotes st && not (endsNotes first && noIndent) = (st, [])
  | otherwise = afterNotes (st {inNotes = False})
  where
    first = pyStrip b0
    noIndent = T.length b0 == T.length (pyLStrip b0)
    afterNotes s
      -- footnotes and textual notes
      | first == "Footnotes:" || isFootnote b0 = (s, [])
      | "DRAMATIS PERSON" `T.isPrefixOf` first = (s {inDramatis = True}, ["@nonumber\n# Dramatis Personæ"])
      | first == "THE TEMPEST." = (s, [])
      | Just n <- actNumber first = (s {inDramatis = False}, ["@nonumber\n# Act " <> n])
      | Just (n, r) <- sceneHeading first,
        noIndent =
          let rest = pyStrip (T.unwords (r : map pyStrip bs))
           in (s, ("@nonumber\n## Scene " <> n) : [paragraph rest | not (T.null rest)])
      | first == "EPILOGUE." =
          (s, "@nonumber\n# Epilogue" : [paragraph (T.unwords (map pyStrip bs)) | not (null bs)])
      | "SCENE--" `T.isPrefixOf` first = (s, [paragraph (T.replace "--" "—" first)])
      -- one character per line: a list
      | inDramatis s = (s, [T.intercalate "\n" ["- " <> inline False (dropNoteRefs (pyStrip x)) | x <- b]])
      | isVerse b = (s, [verse b])
      | otherwise = (s, [prose b])

-- | A speech or a stage direction in prose.
prose :: [Text] -> Text
prose b@(b0 : _)
  | Just (name, rest) <- speaker text,
    T.length b0 == T.length (pyLStrip b0),
    "." `T.isSuffixOf` name =
      -- a speech: the speaker's name, then the words
      pyRStrip ("[strong: " <> inline True name <> "] " <> inline False rest)
  | otherwise = paragraph text
  where
    text = T.replace "--" "—" (collapseSpace (T.unwords (map (pyStrip . stripLineNumber) b)))
prose [] = ""

-- | @^(ACT [IVX]+\.|SCENE [IVX]+\.|EPILOGUE\.)@
endsNotes :: Text -> Bool
endsNotes s =
  romanDot "ACT " || romanDot "SCENE " || "EPILOGUE." `T.isPrefixOf` s
  where
    romanDot p = case T.stripPrefix p s of
      Just r -> let (n, r') = T.span isRoman r in not (T.null n) && "." `T.isPrefixOf` r'
      Nothing -> False

isRoman :: Char -> Bool
isRoman c = c `elem` ['I', 'V', 'X']

-- | @^ACT ([IVX]+)\.$@
actNumber :: Text -> Maybe Text
actNumber s = do
  r <- T.stripPrefix "ACT " s
  let (n, r') = T.span isRoman r
  if not (T.null n) && r' == "." then Just n else Nothing

-- | @^SCENE ([IVX]+)\.\s*(.*)$@
sceneHeading :: Text -> Maybe (Text, Text)
sceneHeading s = do
  r <- T.stripPrefix "SCENE " s
  let (n, r') = T.span isRoman r
  r'' <- T.stripPrefix "." r'
  if T.null n then Nothing else Just (n, pyLStrip r'')

-- | @^\s+\d+(-\d+)?:@
isFootnote :: Text -> Bool
isFootnote s =
  let (sp, r) = T.span isPySpace s
      (d, r') = T.span isPyDecimal r
   in not (T.null sp)
        && not (T.null d)
        && ( ":" `T.isPrefixOf` r'
               || case T.stripPrefix "-" r' of
                 Just r'' -> let (d', r''') = T.span isPyDecimal r'' in not (T.null d') && ":" `T.isPrefixOf` r'''
                 Nothing -> False
           )

-- | @re.sub(r"\[\d+\]", "", s)@: the marks of the notes.
dropNoteRefs :: Text -> Text
dropNoteRefs s = case T.breakOn "[" s of
  (pre, r) | T.null r -> pre
  (pre, r) ->
    let (d, r') = T.span isPyDecimal (T.drop 1 r)
     in case T.stripPrefix "]" r' of
          Just r'' | not (T.null d) -> pre <> dropNoteRefs r''
          _ -> pre <> "[" <> dropNoteRefs (T.drop 1 r)

-- | @re.sub(r"\s{2,}\d+\s*$", "", line)@: the line number at the end.
stripLineNumber :: Text -> Text
stripLineNumber line =
  let (r1, _) = spanEnd isPySpace line
      (r2, d) = spanEnd isPyDecimal r1
      (r3, sp) = spanEnd isPySpace r2
   in if not (T.null d) && T.length sp >= 2 then r3 else line
  where
    spanEnd p t = (T.dropWhileEnd p t, T.takeWhileEnd p t)

-- | @^_([^_]+)_\s*(.*)$@: the speaker's name and the rest.
speaker :: Text -> Maybe (Text, Text)
speaker s = do
  r <- T.stripPrefix "_" s
  let (name, r') = T.break (== '_') r
  r'' <- T.stripPrefix "_" r'
  if T.null name then Nothing else Just (name, pyLStrip r'')

-- | @^\[_[^_]*_\]?$@: a stage direction alone.
stageOnly :: Text -> Bool
stageOnly s = case T.stripPrefix "[_" s of
  Just r ->
    let (_, r') = T.break (== '_') r
     in r' == "_" || r' == "_]"
  Nothing -> False

indentOf :: Text -> Int
indentOf l = T.length (T.takeWhile (== ' ') l)

{- | Whether a line after the first is a line of verse: a half line, a stage
direction alone, or a capital after a stage direction, quotes and
apostrophes.
-}
verseContinues :: Text -> Bool
verseContinues line
  | indentOf line >= 4 = True
  | stageOnly s = True
  | otherwise = case T.uncons (T.dropWhile (`elem` ("\"“”‘’'" :: String)) (dropLeadingDirection s)) of
      Just (c, _) -> isUpperCase c
      Nothing -> False
  where
    s = pyStrip (stripLineNumber line)

-- | @re.sub(r"^\[_[^\]]*\]\s*", "", s)@
dropLeadingDirection :: Text -> Text
dropLeadingDirection s = case T.stripPrefix "[_" s of
  Just r -> case T.break (== ']') r of
    (_, r') | Just r'' <- T.stripPrefix "]" r' -> pyLStrip r''
    _ -> s
  Nothing -> s

{- | Speeches and their continuations of two lines or more whose lines are
verse, and songs and masque speeches indented as a whole.
-}
isVerse :: [Text] -> Bool
isVerse b@(first : rest@(_ : _))
  | indentOf first == 0 =
      let speech = maybe False (("." `T.isSuffixOf`) . fst) (speaker first)
          continuation = not ("_" `T.isPrefixOf` first) && not ("[" `T.isPrefixOf` first)
          -- a song after a stage direction on its first line: "[_Sings._ The master, ..."
          sung =
            "[_" `T.isPrefixOf` first
              && not (stageOnly (pyStrip (stripLineNumber first)))
              && all ((>= 4) . indentOf) rest
       in ((speech || continuation) && all verseContinues rest) || sung
  | indentOf first == 2,
    Just (name, _) <- speaker (pyStrip first),
    "." `T.isSuffixOf` name =
      all ((>= 4) . indentOf) rest
  | indentOf first >= 4,
    not (any (`T.isPrefixOf` pyStrip first) ["_", "["]) =
      all ((>= 4) . indentOf) b
  | otherwise = False
isVerse _ = False

{- | @style verse: one line of source per line of verse, the speaker's name
on the first; italic is closed at the end of each line and opened again.
-}
verse :: [Text] -> Text
verse b =
  "@style verse\n" <> T.intercalate "\n" (concat (snd (mapAccumL line False (zip [0 :: Int ..] lines'))))
  where
    lines' = [T.replace "--" "—" (collapseSpace (pyStrip (stripLineNumber l))) | l <- b]
    line italic (i, l) =
      let (prefix, l') = case speaker l of
            Just (name, rest) | i == 0, "." `T.isSuffixOf` name -> ("[strong: " <> inline True name <> "] ", rest)
            _ -> ("", l)
          (s, italic') = inlineFrom italic False l'
          s' = pyRStrip (prefix <> s)
       in (italic', ["  " <> escapeLineStart s' | not (T.null s')])

-- | A paragraph: inline text, escaped at the start of the line.
paragraph :: Text -> Text
paragraph = escapeLineStart . inline False

{- | @_x_@ toggles italic; @[@ is escaped; @%%@ is escaped. In a slot, @]@
and @|@ are escaped too.
-}
inline :: Bool -> Text -> Text
inline inSlot = fst . inlineFrom False inSlot

{- | 'inline' starting in the given italic state; returns the text and the
italic state at its end, so that italic can continue on the next line.
-}
inlineFrom :: Bool -> Bool -> Text -> (Text, Bool)
inlineFrom italic0 inSlot text =
  (T.replace "%%" "\\%%" (T.concat (zipWith flush states pieces)), final)
  where
    pieces = T.splitOn "_" text
    states = iterate not italic0
    final = states !! (length pieces - 1)
    flush italic s
      | T.null s = ""
      | italic =
          -- spaces at the edges stay outside: the ends of a slot are not text
          let lead = T.takeWhile (== ' ') s
              stripped = T.dropWhile (== ' ') s
              trail = if T.null stripped then s else T.takeWhileEnd (== ' ') s
              core = escapeSlot (T.dropAround (== ' ') s)
           in lead <> (if T.null core then "" else "[italic: " <> core <> "]") <> trail
      | inSlot = escapeSlot s
      | otherwise = T.replace "[" "\\[" (T.replace "\\" "\\\\" s)
    escapeSlot = T.replace "|" "\\|" . T.replace "]" "\\]" . T.replace "[" "\\[" . T.replace "\\" "\\\\"
