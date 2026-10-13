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
-}
module Golem.Fixtures.Aozora (convertAozora) where

import Data.Char (chr, isAlphaNum, isAscii, isHexDigit)
import Data.List (findIndex, isPrefixOf, stripPrefix, tails)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe, mapMaybe)
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

gaiji :: String -> Either String String
gaiji note = case Map.lookup (takeWhile (/= '、') note) gaijiNames of
  Just g -> Right g
  Nothing -> case listToMaybe (mapMaybe codePoint (tails note)) of
    Just n
      | n > 0x10FFFF || (0xD800 <= n && n <= 0xDFFF) -> Left ("not a character: " ++ note)
      | otherwise -> Right [chr n]
    Nothing -> Right "〓"
  where
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

data Kind = Kenten | Tcy

-- | The Golem text of one line and its heading level, if any.
convertLine :: String -> Either String (String, Maybe Int)
convertLine line0 = do
  (_, line1) <- subM (upToBracket "※［＃") (\st note -> (,) st <$> gaiji note) () line0
  let (line2, level) = case heading line1 of
        Just (t, h) -> (t, Just h)
        Nothing -> (line1, Nothing)
  -- emphasis and tate-chu-yoko: mark the preceding text, ruby still raw
  (marks1, line3) <- subM (quoted "に傍点］") (mark Kenten) [] line2
  (marks2, line4) <- subM (quoted "は縦中横］") (mark Tcy) marks1 line3
  (_, line5) <- subM (upToBracket "［＃") (\st _ -> Right (st, "")) () line4 -- layout annotations
  out <- tokens (reverse marks2) [] line5
  let s = concatMap fst (reverse out)
  pure (T.unpack (escapeLineStart (T.pack s)), level)
  where
    mark kind marks target = Right ((kind, target) : marks, "\0" ++ show (length marks) ++ "\0")

-- | The tokens of a line, last first: (Golem text, plain text).
tokens :: [(Kind, String)] -> [(String, String)] -> String -> Either String [(String, String)]
tokens _ out [] = Right out
tokens marks out line@(c : rest)
  | c == '｜',
    '《' `elem` rest = do
      let (base, r) = break (== '《') rest
      (reading, r') <- closing (drop 1 r)
      tokens marks (("[ruby: " ++ slot base ++ "|" ++ slot reading ++ "]", base) : out) r'
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
      tokens marks (tok : out') r'
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
              tok = case kind of
                Kenten -> ("[kenten: " ++ concatMap fst taken ++ "]", got)
                Tcy -> ("[tcy: " ++ slot got ++ "]", got)
           in tokens marks (tok : out') r'
        else tokens marks out r'
  | otherwise = tokens marks ((textEscapeS [c], [c]) : out) rest
  where
    closing s = case break (== '》') s of
      (inside, _ : r) -> Right (inside, r)
      _ -> Left ("no 》: " ++ line)

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
