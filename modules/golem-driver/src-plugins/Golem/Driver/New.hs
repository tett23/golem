{- | The template of `golem new` (golem-cli ADR 0003): a page, fonts and a
first chapter for Japanese or English, with the fonts fetched from tagged
releases and checked against fixed hashes.
-}
module Golem.Driver.New
  ( Language (..),
    templateFiles,
    FontSource (..),
    templateFonts,
    Entry (..),
    Argument (..),
    Conflict (..),
    Plan (..),
    NewError (..),
    planProject,
    targetEntries,
    createProject,
  )
where

import Control.Exception (IOException, try)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Containers.ListUtils (nubOrd)
import Data.Either (lefts, rights)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Plugin.Lock (Fetcher, hashHex)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, pathIsSymbolicLink)
import System.FilePath (splitDirectories, takeDirectory, (</>))

data Language = Japanese | English
  deriving stock (Eq, Show)

-- | The files of a new project, given the UUID of its id.
templateFiles :: Language -> Text -> [(FilePath, Text)]
templateFiles lang uuid =
  [ ("manifest.toml", manifest),
    ("style.toml", style),
    ("chapters/01.gm", chapter),
    ("preflight.toml", preflightToml lang),
    (".gitignore", "build/\n")
  ]
  where
    (code, title, chapter) = case lang of
      Japanese -> ("ja", "無題", "# はじめに\n\n本文。\n")
      English -> ("en", "Untitled", "# Introduction\n\nBody text.\n")
    manifest =
      T.unlines
        [ "chapters = [\"chapters/01.gm\"]",
          "",
          "[metadata]",
          "id = \"urn:uuid:" <> uuid <> "\"",
          "title = \"" <> title <> "\"",
          "language = \"" <> code <> "\"",
          "date = 2026-01-01",
          "",
          "[targets.html]",
          "",
          "[targets.text]",
          "variants = [\"horizontal\"]",
          "",
          "[source]",
          "paragraph-separator = \"line\""
        ]
    style = T.unlines $ case lang of
      Japanese ->
        page "A6" "right" "vertical" "3mm" "12.5Q" 38 16 "20H" "14mm" "14mm"
          <> fonts "# Noto Serif JP (Noto Serif CJK 2.003, Subset OTF), SIL Open Font License 1.1" "ja = \"fonts/NotoSerifJP-Regular.otf\""
          <> rest "第{n:kanji}章"
      English ->
        page "mass-market" "left" "horizontal" "0.125in" "9.5pt" 24 33 "12pt" "16mm" "15mm"
          <> fonts "# Source Serif 4 Regular (4.005R), SIL Open Font License 1.1" "latin = \"fonts/SourceSerif4-Regular.otf\""
          <> rest "Chapter {n}"
    -- the bleed is the usual one of the printers of the language
    -- (golem-pdf ADR 0010): 3mm in Japan, 0.125in in English
    page :: Text -> Text -> Text -> Text -> Text -> Int -> Int -> Text -> Text -> Text -> [Text]
    page size binding mode bleed fontSize chars lineCount pitch top gutter =
      [ "[page]",
        "size = \"" <> size <> "\"",
        "binding = \"" <> binding <> "\"",
        "writing-mode = \"" <> mode <> "\"",
        "bleed = \"" <> bleed <> "\"",
        "",
        "[page.grid]",
        "font-size = \"" <> fontSize <> "\"",
        "characters = " <> T.show chars,
        "lines = " <> T.show lineCount,
        "line-pitch = \"" <> pitch <> "\"",
        "columns = 1",
        "position = { top = \"" <> top <> "\", gutter = \"" <> gutter <> "\" }",
        "",
        "[masters.body]",
        "folio = { position = \"bottom-outside\", format = \"{n}\" }",
        ""
      ]
    fonts comment path = ["[fonts.body]", comment, path, ""]
    rest number =
      [ "[headings.1]",
        "number = \"" <> number <> "\""
      ]

{- | preflight.toml (golem-cli ADR 0006): based on print, with the main
values of print as comments, in the language of the template. The keys
and values are the same in both languages.
-}
preflightToml :: Language -> Text
preflightToml lang =
  T.unlines $
    head'
      <> [ "based-on = \"print\"",
           name,
           ""
         ]
      <> examplesIntro
      <> [ "#",
           "# [image-resolution]",
           "# color = { error-below = 150, warning-below = 300 }",
           "# gray = { error-below = 150, warning-below = 300 }",
           "# bitmap = { error-below = 600, warning-below = 1200 }",
           "#",
           "# [image-color-space]",
           "# severity = \"warning\"",
           "# allowed = [\"cmyk\", \"gray\"]",
           "#",
           "# [bleed-size]",
           "# severity = \"error\"",
           "# min = \"3mm\"",
           "#",
           "# [live-area]",
           "# severity = \"warning\"",
           "# distance = \"3mm\"",
           "#",
           "# [ink-coverage]",
           "# severity = \"warning\"",
           "# max = 350",
           "",
           pageCountIntro,
           "# [page-count]",
           "# severity = \"error\"",
           "# multiple-of = 16",
           "",
           monoIntro,
           "# [cmy-plates]",
           "# severity = \"error\"",
           "#",
           "# [image-color-space]",
           "# allowed = [\"gray\"]"
         ]
  where
    (head', name, examplesIntro, pageCountIntro, monoIntro) = case lang of
      Japanese ->
        ( [ "# golem preflight の設定です（入稿の前の検査）。",
            "# 書かなかった値は based-on の設定から引き継ぎます。",
            "# 印刷所から設定のファイルを受け取ったら、このファイルをそれに置き換えます。"
          ],
          "# name = \"○○印刷 オフセット\"",
          [ "# 次の行は print の主な値を書き写したものです。",
            "# 行頭の # を外して、印刷所の求める値に書き換えます。"
          ],
          "# ページ数を折の単位にそろえる印刷所では、次の行の # を外します（print では off です）。",
          "# 墨一色で刷る本では、次の行の # を外します。C、M、Y の版に出る色と、グレースケールでない図版を見つけます。"
        )
      English ->
        ( [ "# The rules of golem preflight (the checks before handing off to the printer).",
            "# A value not written here comes from the rules of based-on.",
            "# When your printer gives you a file of rules, replace this file with it."
          ],
          "# name = \"Example Printing, offset\"",
          [ "# The lines below copy the main values of print.",
            "# Take the # off the start of a line and write the value your printer asks for."
          ],
          "# If your printer wants the pages in multiples of a signature, take the # off the lines below (off in print).",
          "# For a book printed in black alone, take the # off the lines below. They find colours on the C, M and Y plates, and figures that are not grayscale."
        )

-- | A file to fetch into a new project.
data FontSource = FontSource {fsPath :: !FilePath, fsUrl :: !Text, fsSha256 :: !Text}
  deriving stock (Eq, Show)

-- | The body font of the template and its licence, from tagged releases.
templateFonts :: Language -> [FontSource]
templateFonts = \case
  Japanese ->
    [ FontSource
        "fonts/NotoSerifJP-Regular.otf"
        "https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/SubsetOTF/JP/NotoSerifJP-Regular.otf"
        "2c9a12dbd4f2408c4610c7ee84a108b62d7236c3775baed618c64d9cb44b2f04",
      FontSource
        "fonts/LICENSE-NotoSerifJP.txt"
        "https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/LICENSE"
        "6a73f9541c2de74158c0e7cf6b0a58ef774f5a780bf191f2d7ec9cc53efe2bf2"
    ]
  English ->
    [ FontSource
        "fonts/SourceSerif4-Regular.otf"
        "https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/OTF/SourceSerif4-Regular.otf"
        "edf160d0d584deee8a3bb2c3371b2a7624ca63580fbe02c57c1f4c91e84d8787",
      FontSource
        "fonts/LICENSE-SourceSerif4.md"
        "https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/LICENSE.md"
        "75784a295293a8992f5a8d99210566e0064a012e6dab6731305e3787f15896c7"
    ]

-- | The kind of an entry, as lstat sees it (docs/adr/0273).
data Entry
  = NoEntry
  | RegularFile
  | Directory
  | -- | whether it leads to a directory
    SymbolicLink !Bool
  deriving stock (Eq, Ord, Show)

-- | The argument of golem new: its entry, or a path below an entry that is not a directory.
data Argument = Argument !Entry | BelowNonDirectory
  deriving stock (Eq, Ord, Show)

-- | Why golem new writes nothing (docs/adr/0273); the paths are relative to the argument.
data Conflict
  = -- | G03133: the argument is not a directory and cannot be made one
    NotADirectory
  | -- | G03131: manifest.toml or style.toml is there
    ProjectExists !FilePath
  | -- | G03132: a path of the template, or a directory on the way to one, is taken
    PathTaken !FilePath
  deriving stock (Eq, Ord, Show)

-- | What golem new writes: the paths, and whether an existing .gitignore was kept (G03134).
data Plan = Plan {planWrites :: [FilePath], planKeepsGitignore :: !Bool}
  deriving stock (Eq, Show)

-- | Why golem new failed: the checks of docs/adr/0273, or the fonts.
data NewError = Conflicts [Conflict] | FetchFailed [Text]
  deriving stock (Eq, Show)

{- | Whether golem new may write the project (docs/adr/0273): from the paths
it writes (W), the entry of the argument, and the entries of the paths of
the template and of the directories on the way to them, relative to the
argument (a path missing from the table has no entry). The checks run in
order, and an error skips the later ones: the argument (G03133), a project
(G03131), and the paths of the template (G03132, all of them at once, in
the order of their bytes). An existing .gitignore is kept and not written.
-}
planProject :: [FilePath] -> Argument -> [(FilePath, Entry)] -> Either [Conflict] Plan
planProject writes argument table
  | not (argumentHolds argument) = Left [NotADirectory]
  | not (null projects) = Left (map ProjectExists projects)
  | not (null taken) = Left (map PathTaken taken)
  | otherwise = Right (Plan [p | p <- writes, not (kept && p == gitignore)] kept)
  where
    entries = Map.fromList table
    entry p = Map.findWithDefault NoEntry p entries
    projects = [p | p <- projectFiles, p `elem` writes, entry p /= NoEntry]
    checked = [p | p <- writes, p `notElem` gitignore : projectFiles]
    -- a directory on the way that is not a directory, outermost only
    blocked = [a | a <- nubOrd (concatMap ancestors checked), entry a `notElem` [NoEntry, Directory]]
    outermost = [a | a <- blocked, not (any (`elem` blocked) (ancestors a))]
    taken = sort (outermost <> [p | p <- checked, not (any (`elem` blocked) (ancestors p)), entry p /= NoEntry])
    kept = gitignore `elem` writes && entry gitignore /= NoEntry

-- | The files that make a directory a project (G03131).
projectFiles :: [FilePath]
projectFiles = ["manifest.toml", "style.toml"]

gitignore :: FilePath
gitignore = ".gitignore"

-- | An argument golem new can write into: none yet, a directory, or a link to one.
argumentHolds :: Argument -> Bool
argumentHolds = \case
  Argument e -> e `elem` [NoEntry, Directory, SymbolicLink True]
  BelowNonDirectory -> False

-- | The proper ancestors of a path, outermost first.
ancestors :: FilePath -> [FilePath]
ancestors p = init (scanl1 (</>) (splitDirectories p))

{- | The entries that 'planProject' reads (docs/adr/0273): the argument, and,
when it is a directory, the paths it writes and the directories on the way,
each by lstat. Nothing lists a directory, so the other entries of the
argument are never read.
-}
targetEntries :: FilePath -> [FilePath] -> IO (Argument, [(FilePath, Entry)])
targetEntries dir writes = do
  e <- entryAt dir
  argument <- case e of
    NoEntry -> do
      above <- mapM entryAt (ancestors dir)
      pure (if all (`elem` [NoEntry, Directory, SymbolicLink True]) above then Argument NoEntry else BelowNonDirectory)
    _ -> pure (Argument e)
  table <-
    if argumentHolds argument && e /= NoEntry
      then mapM (\p -> (p,) <$> entryAt (dir </> p)) (nubOrd (concatMap (\p -> ancestors p <> [p]) writes))
      else pure []
  pure (argument, table)

-- | The entry at a path, without following a link at its end; a path that cannot be read has none.
entryAt :: FilePath -> IO Entry
entryAt p =
  try (pathIsSymbolicLink p) >>= \case
    Left (_ :: IOException) -> pure NoEntry
    Right True -> SymbolicLink <$> doesDirectoryExist p
    Right False -> (\d -> if d then Directory else RegularFile) <$> doesDirectoryExist p

{- | Writes a project into a directory without one (docs/adr/0273). The
fonts, if given, are fetched and checked first; if any check or fetch
fails, nothing is written.
-}
createProject :: FilePath -> [(FilePath, Text)] -> Maybe (Fetcher, [FontSource]) -> IO (Either NewError Plan)
createProject dir files fonts = do
  let writes = map fst files <> maybe [] (map fsPath . snd) fonts
  (target, entries) <- targetEntries dir writes
  case planProject writes target entries of
    Left cs -> pure (Left (Conflicts cs))
    Right plan -> do
      fetched <- maybe (pure []) (\(fetch, srcs) -> mapM (fetchOne fetch) srcs) fonts
      case lefts fetched of
        es@(_ : _) -> pure (Left (FetchFailed es))
        [] -> do
          let wanted p = p `elem` planWrites plan
          -- UTF-8 whatever the locale (docs/adr/0002-determinism.md)
          forM_ [(p, TE.encodeUtf8 t) | (p, t) <- files, wanted p] $ \(p, b) -> write (dir </> p) >> BS.writeFile (dir </> p) b
          forM_ [(p, b) | (p, b) <- rights fetched, wanted p] $ \(p, b) -> write (dir </> p) >> BS.writeFile (dir </> p) b
          pure (Right plan)
  where
    write = createDirectoryIfMissing True . takeDirectory
    fetchOne fetch src = do
      r <- fetch (fsUrl src)
      pure $ case r of
        Left e -> Left (fsUrl src <> ": " <> e)
        Right b
          | hashHex b /= fsSha256 src -> Left (fsUrl src <> ": ハッシュが一致しません")
          | otherwise -> Right (fsPath src, b)
