{- | The formats of style.toml with slots in braces (docs/adr/0177): the
mark of a note, the numbers of a list, a running head and the numbers of
headings, figures, code blocks and folios. One reader for all of them;
each format passes the table of its slot names.
-}
module Golem.Numerals.Format
  ( Slot (..),
    Piece (..),
    Braces (..),
    Legacy (..),
    parseFormat,
    singleNumber,
    escapeLiteral,
    MarkFormat (..),
    defaultMarkFormat,
    parseMarkFormat,
    renderMarkFormat,
    formatNumber,
    NumberSlotName (..),
    numberFormatSlots,
    parseNumberFormatText,
    formatUsesChapter,
  )
where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Numerals.Notation

-- | What a name in braces is, by the table of a format.
data Slot a
  = -- | a slot that writes text (a running head): no notation
    TextSlot a
  | -- | a number: @{<name>}@ or @{<name>:<notation>}@
    NumberSlot a
  | -- | a number in the notation of a sample (@{一}@ of [lists]): read, but to be retired (G03115)
    SampleSlot a Notation

-- | A piece of a format read: text, a text slot or a number slot with the notation written.
data Piece a
  = PLit !Text
  | PText a
  | PNumber a !(Maybe Notation)
  deriving stock (Eq, Show)

{- | How braces themselves are written: by the escapes only, or also as
@{{@ and @}}@, which are read but to be retired (G03114, G03116).
-}
data Braces = EscapesOnly | DoubledToo
  deriving stock (Eq, Show)

-- | A way of writing to be retired that a format uses.
data Legacy
  = -- | @{{@ or @}}@
    LegacyBraces
  | -- | a sample in braces (@{一}@), as written, and its notation
    LegacySample !Text !Notation
  deriving stock (Eq, Show)

{- | Reads a format: text, escapes (@\\{@, @\\}@, @\\\\@) and slots in
braces, a number slot with a notation after a colon. The table gives the
slot of a name, or the reason it is wrong. 'Left' is the reason, in
Japanese; the uses of the forms to be retired come with the pieces.
-}
parseFormat :: Braces -> (Text -> Either Text (Slot a)) -> Text -> Either Text ([Piece a], [Legacy])
parseFormat braces table = fmap finish . go [] [] . T.unpack
  where
    finish (ps, ls) = (merge (reverse ps), reverse ls)
    go ps ls = \case
      [] -> Right (ps, ls)
      '\\' : c : rest
        | c `elem` ("{}\\" :: String) -> go (PLit (T.singleton c) : ps) ls rest
        | otherwise -> Left ("\\ の後には {、}、\\ のどれかを書きます: \\" <> T.singleton c)
      ['\\'] -> Left "書式の末尾に \\ があります。文字の \\ は \\\\ と書きます"
      '{' : '{' : rest | braces == DoubledToo -> go (PLit "{" : ps) (LegacyBraces : ls) rest
      '}' : '}' : rest | braces == DoubledToo -> go (PLit "}" : ps) (LegacyBraces : ls) rest
      '{' : rest -> case break (`elem` ("{}\\" :: String)) rest of
        (name, '}' : after) -> do
          (p, l) <- slot (T.pack name)
          go (p : ps) (maybe ls (: ls) l) after
        _ -> Left "閉じていない { があります。文字の { は \\{ と書きます"
      '}' : _ -> Left "対応する { のない } があります。文字の } は \\} と書きます"
      c : rest -> go (PLit (T.singleton c) : ps) ls rest
    slot written =
      let (name, colon) = T.breakOn ":" written
          notationOf = T.drop 1 colon
       in if T.null written
            then Left "空の差し込み {} があります"
            else do
              s <- table name
              case s of
                TextSlot a
                  | T.null colon -> Right (PText a, Nothing)
                  | otherwise -> Left ("数でない差し込みには表記を書けません: {" <> written <> "}")
                NumberSlot a
                  | T.null colon -> Right (PNumber a Nothing, Nothing)
                  | otherwise -> case notationNamed notationOf of
                      Just n -> Right (PNumber a (Just n), Nothing)
                      Nothing -> Left ("表にない表記です: {" <> written <> "}。" <> T.intercalate "、" (map notationName notations) <> " のどれかを書きます")
                SampleSlot a n
                  | T.null colon -> Right (PNumber a (Just n), Just (LegacySample name n))
                  | otherwise -> Left ("表にない差し込みです: {" <> written <> "}")
    merge = \case
      PLit a : PLit b : rest -> merge (PLit (a <> b) : rest)
      x : rest -> x : merge rest
      [] -> []

{- | The one number slot of a format and the text around it: the text
before, the slot, its notation and the text after.
-}
singleNumber :: [Piece a] -> Either Text (Text, a, Maybe Notation, Text)
singleNumber ps = case [() | PNumber {} <- ps] of
  [_] ->
    let (before, rest) = break isNumber ps
     in case rest of
          PNumber a n : after -> Right (literal before, a, n, literal after)
          _ -> Left "番号の差し込みがありません"
  [] -> Left "番号の差し込みがありません"
  _ -> Left "番号の差し込みが二つ以上あります"
  where
    isNumber = \case
      PNumber {} -> True
      _ -> False
    literal xs = T.concat [t | PLit t <- xs]

-- | Text as a format writes it: @{@, @}@ and @\\@ escaped.
escapeLiteral :: Text -> Text
escapeLiteral = T.concatMap (\c -> if c `elem` ("{}\\" :: String) then T.pack ['\\', c] else T.singleton c)

{- | The format of the mark of a note (@[notes] mark-format@): the text
before the number, its notation and the text after it. @{n}@ is Arabic
(golem-driver ADR 0025).
-}
data MarkFormat = MarkFormat
  { mfPrefix :: !Text,
    mfNotation :: !Notation,
    mfSuffix :: !Text
  }
  deriving stock (Eq, Show)

-- | @*{n}@.
defaultMarkFormat :: MarkFormat
defaultMarkFormat = MarkFormat "*" arabic ""

-- | Reads @[notes] mark-format@: exactly one @{n}@ or @{n:<notation>}@.
parseMarkFormat :: Text -> Either Text MarkFormat
parseMarkFormat t = do
  (ps, _) <- parseFormat EscapesOnly table t
  (pre, (), n, suf) <- singleNumber ps
  pure (MarkFormat pre (fromMaybe arabic n) suf)
  where
    table = \case
      "n" -> Right (NumberSlot ())
      name -> Left ("表にない差し込みです: {" <> name <> "}。注の番号は {n} か {n:<表記>} と書きます")

-- | The mark format as style.toml writes it.
renderMarkFormat :: MarkFormat -> Text
renderMarkFormat (MarkFormat pre n suf) =
  escapeLiteral pre <> "{n" <> (if n == arabic then "" else ":" <> notationName n) <> "}" <> escapeLiteral suf

-- | What the slots of a number format of a heading, a figure, a code block or a folio write.
data NumberSlotName = SlotOwn | SlotLevel Int | SlotChapter
  deriving stock (Eq, Show)

-- | The slots of the number formats: @{n}@, @{1}@, @{2}@ and @{chapter}@.
numberFormatSlots :: Text -> Either Text (Slot NumberSlotName)
numberFormatSlots = \case
  "n" -> Right (NumberSlot SlotOwn)
  "1" -> Right (NumberSlot (SlotLevel 0))
  "2" -> Right (NumberSlot (SlotLevel 1))
  "chapter" -> Right (NumberSlot SlotChapter)
  name -> Left ("表にない差し込みです: {" <> name <> "}。{n}、{1}、{2}、{chapter} のどれかを書きます")

-- | Reads a number format; 'Left' is the reason, in Japanese.
parseNumberFormatText :: Text -> Either Text [Piece NumberSlotName]
parseNumberFormatText t = fst <$> parseFormat EscapesOnly numberFormatSlots t

-- | Whether a number format has a slot of the chapter (G04004).
formatUsesChapter :: Text -> Bool
formatUsesChapter t = either (const False) (any isChapter) (parseNumberFormatText t)
  where
    isChapter = \case
      PNumber SlotChapter _ -> True
      _ -> False

{- | Fills a number format: the own number (the last of the levels), the
numbers of the levels and that of the chapter, each in its notation,
Arabic without one. A slot without its number writes nothing; a number
its notation cannot write is written in Arabic numerals. A format that
does not read is its text.
-}
formatNumber :: Text -> [Integer] -> Maybe Integer -> Text
formatNumber fmt levels chapter = case parseNumberFormatText fmt of
  Left _ -> fmt
  Right ps -> T.concat (map fill ps)
  where
    own = if null levels then 0 else last levels
    fill = \case
      PLit t -> t
      PText _ -> ""
      PNumber s n -> maybe "" (written n) (value s)
    value = \case
      SlotOwn -> Just own
      SlotLevel i -> case drop i levels of
        (x : _) -> Just x
        [] -> Nothing
      SlotChapter -> chapter
    written n k = case n of
      Nothing -> T.pack (show k)
      Just x -> fromMaybe (T.pack (show k)) (writeNumber x k)
