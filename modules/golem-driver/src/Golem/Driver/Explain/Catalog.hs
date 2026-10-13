{- | The form of docs/diagnostics.md, the explanations of the diagnostic
codes (golem-cli ADR 0005). A module of its own because Golem.Driver.Explain
calls 'parseCatalog' from Template Haskell when compiling.

The document is read line by line; only the lines that start with @## @,
@### @, @- 重大度: @ and @- 状態: @ (outside fenced code blocks) carry the
structure, so no Markdown parser is needed.
-}
module Golem.Driver.Explain.Catalog
  ( Status (..),
    Explanation (..),
    parseCatalog,
    severities,
  )
where

import Control.Monad (foldM_, unless, when)
import Data.Char (isDigit)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T

-- | Whether a code is still emitted or has been retired (it is never reused).
data Status = InUse | Retired
  deriving stock (Eq, Show)

-- | One section of docs/diagnostics.md.
data Explanation = Explanation
  { -- | such as @G0701@
    exCode :: !Text,
    -- | the paragraph after the heading
    exTitle :: !Text,
    exStatus :: !Status,
    -- | from the @## G0701@ line up to the next @## @ line, without the blank lines at the end
    exBody :: !Text
  }
  deriving stock (Eq, Show)

-- | The values of @- 重大度: @.
severities :: [Text]
severities = ["エラー", "警告", "dev では警告、prod ではエラー"]

-- | A line with its number, counted from 1.
type Numbered = (Int, Text)

{- | Checks every rule of the form of a section (heading, title, severity,
status, the three subsections in order, ascending codes without
duplicates) and returns the first broken rule with its line number.
-}
parseCatalog :: Text -> Either Text [Explanation]
parseCatalog doc = do
  let numbered = zip [1 ..] (T.lines doc)
      headings = [(n, l) | (n, l, False) <- withFence numbered, "## " `T.isPrefixOf` l]
      sections = splitSections numbered headings
  explanations <- mapM section sections
  foldM_ ascending Nothing (zip (map fst sections) explanations)
  pure explanations
  where
    ascending prev (n, e) = case prev of
      Just p
        | exCode e == p -> Left (at n (exCode e <> " が二度あります"))
        | exCode e < p -> Left (at n (exCode e <> " が " <> p <> " より後にあります。節はコードの昇順に並べます"))
      _ -> pure (Just (exCode e))

{- | The sections: from each @## @ line after the preamble to the next. The
preamble is everything before the first heading that is a code; its own
headings (such as the table of the code ranges) are not sections.
-}
splitSections :: [Numbered] -> [Numbered] -> [(Int, [Numbered])]
splitSections numbered headings =
  let starts = map fst (dropWhile (not . isCodeHeading . snd) headings)
      ends = drop 1 starts <> [maxBound]
   in [(s, [x | x@(n, _) <- numbered, n >= s, n < e]) | (s, e) <- zip starts ends]

isCodeHeading :: Text -> Bool
isCodeHeading l = maybe False isCode (T.stripPrefix "## " l)

isCode :: Text -> Bool
isCode t = T.length t == 5 && T.take 1 t == "G" && T.all isDigit (T.drop 1 t)

-- | Each line with whether it is inside a fenced code block.
withFence :: [Numbered] -> [(Int, Text, Bool)]
withFence = go False
  where
    go _ [] = []
    go inside ((n, l) : rest)
      | "```" `T.isPrefixOf` l = (n, l, True) : go (not inside) rest
      | otherwise = (n, l, inside) : go inside rest

at :: Int -> Text -> Text
at n msg = "docs/diagnostics.md の " <> T.pack (show n) <> " 行目: " <> msg

section :: (Int, [Numbered]) -> Either Text Explanation
section (h, ls) = do
  let heading = maybe "" snd (safeHead ls)
  code <- maybe (Left (at h "見出しは ## とコードだけにします")) Right (T.stripPrefix "## " heading >>= \c -> if isCode c then Just c else Nothing)
  let rest = drop 1 ls
      structural = [(n, l) | (n, l, False) <- withFence rest]
      subHeadings = [(n, T.drop 4 l) | (n, l) <- structural, "### " `T.isPrefixOf` l]
      firstSub = maybe maxBound fst (safeHead subHeadings)
      header = [(n, l) | (n, l) <- rest, n < firstSub]
  title <- titleOf code h header
  severity <- field code h "重大度" header
  unless (snd severity `elem` severities) $
    Left (at (fst severity) ("重大度は " <> T.intercalate "、" severities <> " のいずれかにします: " <> snd severity))
  (sn, statusText) <- field code h "状態" header
  status <- case statusText of
    "使用中" -> Right InUse
    "廃止" -> Right Retired
    other -> Left (at sn ("状態は 使用中 か 廃止 にします: " <> other))
  let names = map snd subHeadings
      full = ["意味", "主な原因", "直し方"]
      expected = case status of
        InUse -> [full]
        Retired -> [full, ["意味", "直し方"]]
  unless (names `elem` expected) $
    Left (at h (code <> " の小見出しは " <> T.intercalate "、" (map ("### " <>) full) <> " をこの順に置きます" <> retiredNote status))
  mapM_ (nonEmpty rest subHeadings) subHeadings
  pure
    Explanation
      { exCode = code,
        exTitle = title,
        exStatus = status,
        exBody = T.intercalate "\n" (map snd (dropTrailingBlank ls))
      }
  where
    retiredNote = \case
      Retired -> "（廃止したコードは ### 主な原因 を省けます）"
      InUse -> ""

-- | The paragraph after the heading.
titleOf :: Text -> Int -> [Numbered] -> Either Text Text
titleOf code h header =
  case dropWhile (T.null . T.strip . snd) header of
    (n, l) : more
      | isParagraph l ->
          pure (T.concat (map (T.strip . snd) ((n, l) : takeWhile (\(_, x) -> not (T.null (T.strip x)) && isParagraph x) more)))
    _ -> Left (at h (code <> " の見出しの次に、一行の題の段落を書きます"))
  where
    isParagraph l = not (any (`T.isPrefixOf` l) ["- ", "#", "```", "|"])

-- | The value of the one line @- name: value@ of the header.
field :: Text -> Int -> Text -> [Numbered] -> Either Text Numbered
field code h name header =
  case mapMaybe (\(n, l) -> (,) n . T.strip <$> T.stripPrefix ("- " <> name <> ": ") l) header of
    [x] -> pure x
    [] -> Left (at h (code <> " に - " <> name <> ": の行がありません"))
    _ : (n, _) : _ -> Left (at n (code <> " に - " <> name <> ": の行が二つあります"))

-- | A subsection has at least one line that is not blank.
nonEmpty :: [Numbered] -> [(Int, Text)] -> (Int, Text) -> Either Text ()
nonEmpty rest subHeadings (n, name) = do
  let next = case dropWhile ((<= n) . fst) subHeadings of
        (m, _) : _ -> m
        [] -> maxBound
      content = [l | (k, l) <- rest, k > n, k < next, not (T.null (T.strip l))]
  when (null content) $ Left (at n ("### " <> name <> " が空です"))

dropTrailingBlank :: [Numbered] -> [Numbered]
dropTrailingBlank = reverse . dropWhile (T.null . T.strip . snd) . reverse

safeHead :: [a] -> Maybe a
safeHead = \case
  x : _ -> Just x
  [] -> Nothing
