{- | Converts an Aozora Bunko text (ruby edition, UTF-8) into Golem source
(docs/adr/0023).

Handled: ruby 《》 and ｜, emphasis dots ［＃「…」に傍点］, tate-chu-yoko
［＃「…」は縦中横］, headings ［＃「…」は大／中／小見出し］, the gaiji used
in the text, and the colophon (kept at the end, as the Aozora terms ask).
Layout annotations (字下げ, 字詰め, 罫囲み, 地付き) are dropped.
Each paragraph is one line, for [source] paragraph-separator = "line"
(docs/adr/0013).

The rules are those of the Python script that this replaces, and give the
same bytes for the same input.

convertAozoraWith (aozora-prose and aozora-verse, docs/adr/0026) adds the
shapes of kenten, bold and italic, kunten, page breaks, kunojiten, more
gaiji names and headings over lines, and keeps the indents: as paragraph
styles indent-F-R in prose, as full-width spaces in verse.
-}
module Golem.Fixtures.Aozora (AozoraMode (..), convertAozora, convertAozoraWith) where

import Data.Char (chr, isAlphaNum, isAscii, isHexDigit)
import Data.List (findIndex, intercalate, isPrefixOf, stripPrefix, tails)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Fixtures.Python
import Numeric (readHex)
import Text.Read (readMaybe)

convertAozora :: Text -> Either String Text
convertAozora src = do
  let lines' = T.splitOn "\n" (T.replace "\r\n" "\n" src)
  case lines' of
    _ : _ : _ -> Right ()
    _ -> Left "no title and author"
  -- skip the explanation of the notation between the dashed lines
  body <- case [i | (i, l) <- zip [0 :: Int ..] lines', "-------" `T.isPrefixOf` l] of
    _ : d : _ -> Right (drop (d + 1) lines')
    _ -> Left "no two dashed lines"
  colophonAt <- maybe (Left "no 底本：") Right (findIndex ("底本：" `T.isPrefixOf`) body)
  let (text, colophon) = splitAt colophonAt body
  paragraphs <- traverse paragraphOf (filter (not . T.null . pyStrip) text)
  pure
    ( joinParagraphs
        ( concat paragraphs
            <> ["@nonumber\n# 底本と作成者"]
            <> [textEscape (pyStrip l) | l <- colophon, not (T.null (pyStrip l))]
        )
        <> "\n"
    )
  where
    paragraphOf l = do
      (g, level) <- convertLine (T.unpack l)
      let g' = T.pack g
      pure $ case level of
        Just h -> ["@nonumber\n" <> T.replicate h "#" <> " " <> g']
        Nothing -> [g' | not (T.null (pyStrip g'))]

{- | Joins the blocks for paragraph-separator = "line": one newline between
paragraphs, a blank line before and after a heading (docs/adr/0013).
-}
joinParagraphs :: [Text] -> Text
joinParagraphs blocks = T.concat (zipWith sep (Nothing : map Just blocks) blocks)
  where
    sep Nothing b = b
    sep (Just prev) b
      | isHeading b || isHeading prev = "\n\n" <> b
      | otherwise = "\n" <> b
    isHeading = T.isPrefixOf "@nonumber\n"

gaijiNames :: Map.Map String String
gaijiNames =
  Map.fromList
    [ ("二の字点", "〻"),
      ("感嘆符疑問符", "⁉"),
      ("疑問符感嘆符", "⁈"),
      ("感嘆符二つ", "‼")
    ]

-- | The names of docs/adr/0026: JIS X 0213 1-2-54 and 1-2-55.
extendedGaijiNames :: Map.Map String String
extendedGaijiNames = Map.fromList [("始め二重括弧", "⦅"), ("終わり二重括弧", "⦆")]

data CharClass = Kanji | Katakana | Hiragana | Alnum | Other
  deriving stock (Eq)

isKanji :: Char -> Bool
isKanji c = ('\x4e00' <= c && c <= '\x9fff') || ('\x3400' <= c && c <= '\x4dbf') || c `elem` ("々〆ヶ〻※" :: String)

charClass :: Char -> CharClass
charClass c
  | isKanji c = Kanji
  | '\x30a0' <= c && c <= '\x30ff' = Katakana
  | '\x3040' <= c && c <= '\x309f' = Hiragana
  | (isAscii c && isAlphaNum c) || ('\xff10' <= c && c <= '\xff5a') = Alnum
  | otherwise = Other

slot :: String -> String
slot = concatMap $ \case
  '\\' -> "\\\\"
  '[' -> "\\["
  ']' -> "\\]"
  '|' -> "\\|"
  '/' -> "\\/"
  c -> [c]

textEscape :: Text -> Text
textEscape = T.replace "%%" "\\%%" . T.replace "[" "\\[" . T.replace "\\" "\\\\"

textEscapeS :: String -> String
textEscapeS = T.unpack . textEscape . T.pack

{- | @re.sub@ of a pattern that the matcher tries at each position, leftmost
first, with a replacement that may fail and carries a state.
-}
subM :: (String -> Maybe (a, String)) -> (s -> a -> Either String (s, String)) -> s -> String -> Either String (s, String)
subM match rep = go
  where
    go st [] = Right (st, [])
    go st s@(c : cs) = case match s of
      Just (a, rest) -> do
        (st', r) <- rep st a
        (st'', out) <- go st' rest
        pure (st'', r ++ out)
      Nothing -> fmap (c :) <$> go st cs

-- | An annotation @［＃「TARGET」SUFFIX@ at the start: TARGET and the rest.
quoted :: String -> String -> Maybe (String, String)
quoted suffix s = do
  r <- stripPrefix "［＃「" s
  let (target, r') = break (== '」') r
  rest <- stripPrefix ("」" ++ suffix) r'
  pure (target, rest)

-- | An annotation @PREFIX…］@ at the start: what is inside and the rest.
upToBracket :: String -> String -> Maybe (String, String)
upToBracket prefix s = do
  r <- stripPrefix prefix s
  case break (== '］') r of
    (inside, '］' : rest) -> Just (inside, rest)
    _ -> Nothing

gaiji :: Rules -> String -> Either String String
gaiji rules note = case Map.lookup (takeWhile (/= '、') note) names of
  Just g -> Right g
  Nothing -> case listToMaybe (mapMaybe codePoint (tails note)) of
    Just n
      | n > 0x10FFFF || (0xD800 <= n && n <= 0xDFFF) -> Left ("not a character: " ++ note)
      | otherwise -> Right [chr n]
    Nothing -> Right "〓"
  where
    names = if rules == Extended then gaijiNames <> extendedGaijiNames else gaijiNames
    codePoint t = do
      r <- stripPrefix "U+" t
      let hex = take 6 (takeWhile isHexDigit' r)
      case readHex hex of
        [(n, "")] | length hex >= 4 -> Just n
        _ -> Nothing
    isHexDigit' c = isAscii c && isHexDigit c

{- | @［＃「…」は(大|中|小)見出し］@ anywhere in the line: the heading's text
and level.
-}
heading :: String -> Maybe (String, Int)
heading line = listToMaybe (mapMaybe at (tails line))
  where
    at s = do
      r <- stripPrefix "［＃「" s
      let (target, r') = break (== '」') r
      r'' <- stripPrefix "」は" r'
      case r'' of
        size : r''' | "見出し］" `isPrefixOf` r''' -> (,) target <$> lookup size [('大', 1), ('中', 1), ('小', 2)]
        _ -> Nothing

-- | Kenten of a shape (Nothing: the default), tate-chu-yoko, bold, italic.
data Kind = Kenten (Maybe String) | Tcy | Bold | Italic

-- | The rules of aozora (docs/adr/0023) and the more of docs/adr/0026.
data Rules = Classic | Extended
  deriving stock (Eq)

-- | The Golem text of one line and its heading level, if any.
convertLine :: String -> Either String (String, Maybe Int)
convertLine line0 = do
  (s, level) <- convertLineWith Classic line0
  pure (T.unpack (escapeLineStart (T.pack s)), level)

{- | The Golem text of one line, not escaped at its start, and its heading
level, if any.
-}
convertLineWith :: Rules -> String -> Either String (String, Maybe Int)
convertLineWith rules line00 = do
  let line0 = if rules == Extended then kunojiten line00 else line00
  (_, line1) <- subM (upToBracket "※［＃") (\st note -> (,) st <$> gaiji rules note) () line0
  let (line2, level) = case heading line1 of
        Just (t, h) -> (t, Just h)
        Nothing -> (line1, Nothing)
  -- emphasis and tate-chu-yoko: mark the preceding text, ruby still raw
  (marks2, line4) <- case rules of
    Classic -> do
      (marks1, line3) <- subM (quoted "に傍点］") (mark (const (Kenten Nothing))) [] line2
      subM (quoted "は縦中横］") (mark (const Tcy)) marks1 line3
    Extended -> subM extendedMark (\marks (kind, target) -> mark (const kind) marks target) [] line2
  -- layout annotations are dropped; kunten (Extended) become raw markup
  (raws, line5) <- case rules of
    Classic -> subM (upToBracket "［＃") (\st _ -> Right (st, "")) [] line4
    Extended -> subM (upToBracket "［＃") kunten [] line4
  out <- tokens (reverse marks2) (reverse raws) [] line5
  pure (concatMap fst (reverse out), level)
  where
    mark kind marks target = Right ((kind target, target) : marks, "\0" ++ show (length marks) ++ "\0")
    kunten raws note = case kuntenOf note of
      Just k -> Right (("[style kunten: " ++ slot k ++ "]") : raws, "\1" ++ show (length raws) ++ "\1")
      Nothing -> Right (raws, "")

-- | The annotations on a quoted target of docs/adr/0026 and their kinds.
extendedMark :: String -> Maybe ((Kind, String), String)
extendedMark s = listToMaybe [((kind, target), rest) | (suffix, kind) <- marks, Just (target, rest) <- [quoted suffix s]]
  where
    marks =
      [ ("に傍点］", Kenten Nothing),
        ("に白ゴマ傍点］", Kenten (Just "open-sesame")),
        ("に丸傍点］", Kenten (Just "circle")),
        ("に白丸傍点］", Kenten (Just "open-circle")),
        ("に黒三角傍点］", Kenten (Just "triangle")),
        ("に白三角傍点］", Kenten (Just "open-triangle")),
        ("に二重丸傍点］", Kenten (Just "open-double-circle")),
        ("に蛇の目傍点］", Kenten (Just "double-circle")),
        ("は縦中横］", Tcy),
        ("は太字］", Bold),
        ("は斜体］", Italic),
        ("は同行大見出し］", Bold),
        ("は同行中見出し］", Bold),
        ("は同行小見出し］", Bold)
      ]

{- | The kaeriten (［＃レ］, ［＃一レ］, ...) and the okurigana of kunten
(［＃（ト）］) inside an annotation.
-}
kuntenOf :: String -> Maybe String
kuntenOf note
  | not (null note), all (`elem` ("一二三四上中下甲乙丙丁天地人レ" :: String)) note = Just note
  | '（' : r <- note, not (null r), last r == '）', not (null (init r)) = Just (init r)
  | otherwise = Nothing

-- | The kunojiten written with ／＼ and ／″＼.
kunojiten :: String -> String
kunojiten = \case
  '／' : '″' : '＼' : r -> "〴〵" ++ kunojiten r
  '／' : '＼' : r -> "〳〵" ++ kunojiten r
  c : r -> c : kunojiten r
  [] -> []

{- | The tokens of a line, last first: (Golem text, plain text). Raw markup
(kunten) is in the line as @\\1N\\1@ and has no plain text.
-}
tokens :: [(Kind, String)] -> [String] -> [(String, String)] -> String -> Either String [(String, String)]
tokens _ _ out [] = Right out
tokens marks raws out line@(c : rest)
  | c == '｜',
    '《' `elem` rest = do
      let (base, r) = break (== '《') rest
      (reading, r') <- closing (drop 1 r)
      (golem, plain) <- withRaws base
      tokens marks raws (("[ruby: " ++ golem ++ "|" ++ slot reading ++ "]", plain) : out) r'
  | c == '《' = do
      (reading, r') <- closing rest
      -- the base: the run of same-class characters just before
      let plainRev = concatMap (reverse . snd) out
          cls = maybe Other charClass (listToMaybe plainRev)
          n = length (takeWhile ((== cls) . charClass) plainRev)
          (baseRev, out') = takeBase n out
          base = reverse baseRev
          tok
            | null base = (textEscapeS ("《" ++ reading ++ "》"), "《" ++ reading ++ "》")
            | otherwise = ("[ruby: " ++ slot base ++ "|" ++ slot reading ++ "]", base)
      tokens marks raws (tok : out') r'
  | c == '\0' = do
      (number, r') <- case break (== '\0') rest of
        (d, _ : r') -> Right (d, r')
        _ -> Left ("no end of a mark: " ++ line)
      (kind, target) <- case readMaybe number of
        Just i | i >= 0, i < length marks -> Right (marks !! i)
        _ -> Left ("not a mark: " ++ number)
      let plainRev = concatMap (reverse . snd) out
      if reverse target `isPrefixOf` plainRev
        then
          let (taken, got, out') = takeTarget (length target) out
              inner = concatMap fst taken
              tok = case kind of
                Kenten Nothing -> ("[kenten: " ++ inner ++ "]", got)
                Kenten (Just shape) -> ("[kenten shape=" ++ shape ++ ": " ++ inner ++ "]", got)
                Tcy -> ("[tcy: " ++ slot got ++ "]", got)
                Bold -> ("[bold: " ++ inner ++ "]", got)
                Italic -> ("[italic: " ++ inner ++ "]", got)
           in tokens marks raws (tok : out') r'
        else tokens marks raws out r'
  | c == '\1' = do
      (raw, r') <- rawAt rest
      tokens marks raws ((raw, "") : out) r'
  | otherwise = tokens marks raws ((textEscapeS [c], [c]) : out) rest
  where
    closing s = case break (== '》') s of
      (inside, _ : r) -> Right (inside, r)
      _ -> Left ("no 》: " ++ line)
    rawAt s = case break (== '\1') s of
      (d, _ : r) | Just i <- readMaybe d, i >= 0, i < length raws -> Right (raws !! i, r)
      _ -> Left ("not raw markup: " ++ line)
    -- the base of a ruby with a bar: raw markup kept, the rest escaped
    withRaws s = case break (== '\1') s of
      (pre, []) -> Right (slot pre, pre)
      (pre, _ : r) -> do
        (raw, r') <- rawAt r
        (g, p) <- withRaws r'
        Right (slot pre ++ raw ++ g, pre ++ p)

-- | The extended converters of docs/adr/0026.
data AozoraMode = Prose | Verse
  deriving stock (Eq, Show)

-- | A line of the text after its indents and breaks are read.
data Item
  = -- | a paragraph or a line of verse: its indent (first line, rest)
    Para (Maybe (Int, Int)) String
  | Heading Int String
  | Break Text
  | Blank

{- | aozora-prose and aozora-verse (docs/adr/0026): the rules of aozora, more
annotations, and indents as paragraph styles (Prose) or full-width spaces in
stanzas (Verse).
-}
convertAozoraWith :: AozoraMode -> Text -> Either String Text
convertAozoraWith mode src = do
  let lines' = T.splitOn "\n" (T.replace "\r\n" "\n" src)
  case lines' of
    _ : _ : _ -> Right ()
    _ -> Left "no title and author"
  body <- case [i | (i, l) <- zip [0 :: Int ..] lines', "-------" `T.isPrefixOf` l] of
    _ : d : _ -> Right (drop (d + 1) lines')
    _ -> Left "no two dashed lines"
  colophonAt <- maybe (Left "no 底本：") Right (findIndex ("底本：" `T.isPrefixOf`) body)
  let (text, colophon) = splitAt colophonAt body
  items <- readItems (map T.unpack text)
  let colophonHeading = "@nonumber\n# 底本と作成者"
      colophonLines = [textEscape (pyStrip l) | l <- colophon, not (T.null (pyStrip l))]
  pure $ case mode of
    Prose -> joinParagraphs (concatMap proseBlock items <> [colophonHeading] <> colophonLines) <> "\n"
    Verse -> T.intercalate "\n\n" (verseBlocks items <> [colophonHeading, T.intercalate "\n" colophonLines]) <> "\n"
  where
    proseBlock = \case
      Para indent g -> [maybe "" (\(f, r) -> "@style indent-" <> showT f <> "-" <> showT r <> "\n") indent <> escapeLineStart (T.pack g)]
      Heading h g -> [headingBlock h g]
      Break b -> [b]
      Blank -> []
    verseBlocks = \case
      [] -> []
      items@(Para {} : _) ->
        let (stanza, rest) = span isPara items
         in ("@style verse\n" <> T.intercalate "\n" ["  " <> verseLine i g | Para i g <- stanza]) : verseBlocks rest
      Heading h g : rest -> headingBlock h g : verseBlocks rest
      Break b : rest -> b : verseBlocks rest
      Blank : rest -> verseBlocks rest
    isPara (Para _ _) = True
    isPara _ = False
    verseLine indent g = case indent of
      Just (f, _) | f > 0 -> T.replicate f "　" <> T.pack g
      _ -> escapeLineStart (T.pack g)
    headingBlock h g = "@nonumber\n" <> T.replicate h "#" <> " " <> T.pack g
    showT = T.pack . show

-- | The items of the lines, with the state of the indents and headings that span lines.
readItems :: [String] -> Either String [Item]
readItems = go Nothing
  where
    go _ [] = Right []
    go block (l : ls)
      | Just size <- headingStart l = do
          let (inside, rest) = break (isHeadingEnd size) ls
          (g, _) <- convertLineWith Extended (intercalate "　" [strip' x | x <- inside, not (null (strip' x))])
          (Heading (headingLevel size) g :) <$> go block (drop 1 rest)
      | strip' l `elem` ["［＃改ページ］"] = (Break "@page-break" :) <$> go block ls
      | strip' l `elem` ["［＃改丁］", "［＃改見開き］"] = (Break "@page-break recto" :) <$> go block ls
      | Just indent <- blockStart (strip' l) = go (Just indent) ls
      | strip' l == "［＃ここで字下げ終わり］" = go Nothing ls
      | otherwise = do
          let (lineIndent, l') = case lineStart l of
                Just (indent, r) -> (Just indent, r)
                Nothing -> (Nothing, l)
          (g, level) <- convertLineWith Extended l'
          let item = case level of
                Just h -> [Heading h g]
                Nothing
                  | not (null (strip' g)) -> [Para (maybe block Just lineIndent) g]
                  | null (strip' l) -> [Blank]
                  | otherwise -> []
          (item <>) <$> go block ls
    strip' = T.unpack . pyStrip . T.pack
    headingStart l = case strip' l of
      '［' : '＃' : 'こ' : 'こ' : 'か' : 'ら' : size : r | r == "見出し］", size `elem` ("大中小" :: String) -> Just size
      _ -> Nothing
    isHeadingEnd size l = strip' l == "［＃ここで" ++ [size] ++ "見出し終わり］"
    headingLevel size = if size == '小' then 2 else 1

{- | @［＃ここからN字下げ］@, @［＃ここからN字下げ、折り返してM字下げ］@ and
@［＃ここから改行天付き、折り返してM字下げ］@ alone on a line.
-}
blockStart :: String -> Maybe (Int, Int)
blockStart s = do
  r <- stripPrefix "［＃ここから" s
  (indent, rest) <- indentSpec r
  if rest == "］" then Just indent else Nothing

-- | @［＃N字下げ］@ or @［＃改行天付き、折り返してM字下げ］@ at the start of a line.
lineStart :: String -> Maybe ((Int, Int), String)
lineStart s = do
  r <- stripPrefix "［＃" s
  (indent, rest) <- indentSpec r
  rest' <- stripPrefix "］" rest
  Just (indent, rest')

-- | @N字下げ@, @N字下げ、折り返してM字下げ@, @改行天付き、折り返してM字下げ@.
indentSpec :: String -> Maybe ((Int, Int), String)
indentSpec s = case stripPrefix "改行天付き、折り返して" s of
  Just r -> do
    (m, r') <- number r
    r'' <- stripPrefix "字下げ" r'
    Just ((0, m), r'')
  Nothing -> do
    (n, r) <- number s
    r' <- stripPrefix "字下げ" r
    case stripPrefix "、折り返して" r' of
      Just r'' -> do
        (m, r''') <- number r''
        r4 <- stripPrefix "字下げ" r'''
        Just ((n, m), r4)
      Nothing -> Just ((n, n), r')
  where
    number t =
      let (ds, r) = span (`elem` ("0123456789０１２３４５６７８９" :: String)) t
       in if null ds then Nothing else Just (foldl (\a d -> a * 10 + digit d) 0 ds, r)
    digit d = fromMaybe 0 (lookup d (zip "0123456789" [0 ..] <> zip "０１２３４５６７８９" [0 ..]))
-- | Takes back up to n plain characters emitted as themselves, last first.
takeBase :: Int -> [(String, String)] -> (String, [(String, String)])
takeBase n out
  | n > 0, ((g, p@[ch]) : out') <- out, g == p = let (cs, out'') = takeBase (n - 1) out' in (ch : cs, out'')
  | otherwise = ([], out)

-- | Pulls tokens back out until their plain text is at least n characters.
takeTarget :: Int -> [(String, String)] -> ([(String, String)], String, [(String, String)])
takeTarget n = go [] ""
  where
    go taken got out
      | length got < n, (t@(_, p) : out') <- out = go (t : taken) (p ++ got) out'
      | otherwise = (taken, got, out)
