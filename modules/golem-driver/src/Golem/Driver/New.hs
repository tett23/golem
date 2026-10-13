{- | The template of `golem new` (golem-cli ADR 0003): a page, fonts and a
first chapter for Japanese or English, with the fonts fetched from tagged
releases and checked against fixed hashes.
-}
module Golem.Driver.New
  ( Language (..),
    templateFiles,
    FontSource (..),
    templateFonts,
    createProject,
  )
where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.Either (lefts, rights)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Plugin.Lock (Fetcher, hashHex)
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.FilePath (takeDirectory, (</>))

data Language = Japanese | English
  deriving stock (Eq, Show)

-- | The files of a new project, given the UUID of its id.
templateFiles :: Language -> Text -> [(FilePath, Text)]
templateFiles lang uuid =
  [ ("manifest.toml", manifest),
    ("style.toml", style),
    ("chapters/01.gm", chapter),
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
          "variants = [\"horizontal\"]"
        ]
    style = T.unlines $ case lang of
      Japanese ->
        page "A6" "right" "vertical" "12.5Q" 38 16 "20H" "14mm" "14mm"
          <> fonts "# Noto Serif JP (Noto Serif CJK 2.003, Subset OTF), SIL Open Font License 1.1" "ja = \"fonts/NotoSerifJP-Regular.otf\""
          <> rest "第{n:kanji}章"
      English ->
        page "mass-market" "left" "horizontal" "9.5pt" 24 33 "12pt" "16mm" "15mm"
          <> fonts "# Source Serif 4 Regular (4.005R), SIL Open Font License 1.1" "latin = \"fonts/SourceSerif4-Regular.otf\""
          <> rest "Chapter {n}"
    page :: Text -> Text -> Text -> Text -> Int -> Int -> Text -> Text -> Text -> [Text]
    page size binding mode fontSize chars lines pitch top gutter =
      [ "[page]",
        "size = \"" <> size <> "\"",
        "binding = \"" <> binding <> "\"",
        "writing-mode = \"" <> mode <> "\"",
        "",
        "[page.grid]",
        "font-size = \"" <> fontSize <> "\"",
        "characters = " <> T.show chars,
        "lines = " <> T.show lines,
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

{- | Writes a project into an empty or missing directory. The fonts, if
given, are fetched and checked first; if any fails, nothing is written.
-}
createProject :: FilePath -> [(FilePath, Text)] -> Maybe (Fetcher, [FontSource]) -> IO (Either [Text] ())
createProject dir files fonts = do
  exists <- doesDirectoryExist dir
  nonEmpty <- if exists then not . null <$> listDirectory dir else pure False
  if nonEmpty
    then pure (Left ["ディレクトリが空ではありません: " <> T.pack dir])
    else do
      fetched <- maybe (pure []) (\(fetch, srcs) -> mapM (fetchOne fetch) srcs) fonts
      case lefts fetched of
        es@(_ : _) -> pure (Left es)
        [] -> do
          forM_ files $ \(p, t) -> write (dir </> p) >> TIO.writeFile (dir </> p) t
          forM_ (rights fetched) $ \(p, b) -> write (dir </> p) >> BS.writeFile (dir </> p) b
          pure (Right ())
  where
    write = createDirectoryIfMissing True . takeDirectory
    fetchOne fetch src = do
      r <- fetch (fsUrl src)
      pure $ case r of
        Left e -> Left (fsUrl src <> ": " <> e)
        Right b
          | hashHex b /= fsSha256 src -> Left (fsUrl src <> ": ハッシュが一致しません")
          | otherwise -> Right (fsPath src, b)
