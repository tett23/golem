{- | golem new, inspect, fmt, plugin lock and fetch, and preflight, run as
a process in a temporary directory (golem-cli ADR 0001, ADR 0003, ADR
0006, golem-fmt ADR 0001, golem-plugin ADR 0002). Nothing connects to the
network: golem new runs with --no-fonts, and the plugin commands use URLs
that are rejected or artifacts that are already in the cache.
-}
module CommandsSpec (commandsTests) where

import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isInfixOf, isPrefixOf, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (CreateProcess (..), proc, readCreateProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

commandsTests :: TestTree
commandsTests =
  testGroup
    "commands on a project"
    [newTests, inspectTests, fmtTests, pluginTests, preflightTests]

-- ------------------------------------------------------------------ helpers

-- | Writes UTF-8 files, making their directories.
writeFiles :: FilePath -> [(FilePath, String)] -> IO ()
writeFiles dir = mapM_ $ \(p, c) -> do
  createDirectoryIfMissing True (takeDirectory (dir </> p))
  BS.writeFile (dir </> p) (TE.encodeUtf8 (T.pack c))

readUtf8 :: FilePath -> IO String
readUtf8 p = T.unpack . TE.decodeUtf8 <$> BS.readFile p

-- | Runs golem in a directory; exit code, stdout and stderr.
golemAt :: FilePath -> [String] -> IO (ExitCode, String, String)
golemAt dir args = readCreateProcessWithExitCode (proc "golem" args) {cwd = Just dir} ""

-- | Runs golem with the plugin cache (XDG_CACHE_HOME) in the given directory.
golemWithCache :: FilePath -> FilePath -> [String] -> IO (ExitCode, String, String)
golemWithCache cache dir args = do
  env <- getEnvironment
  let env' = ("XDG_CACHE_HOME", cache) : filter ((/= "XDG_CACHE_HOME") . fst) env
  readCreateProcessWithExitCode (proc "golem" args) {cwd = Just dir, env = Just env'} ""

-- | Every file under a directory, relative to it, sorted.
filesUnder :: FilePath -> IO [FilePath]
filesUnder root = sort <$> go ""
  where
    go rel = do
      names <- listDirectory (root </> rel)
      concat
        <$> mapM
          ( \n -> do
              let p = if null rel then n else rel </> n
              isDir <- doesDirectoryExist (root </> p)
              if isDir then go p else pure [p]
          )
          names

manifestWith :: String -> String
manifestWith chapters =
  "chapters = "
    <> chapters
    <> "\n\n[metadata]\nid = \"urn:uuid:11111111-2222-4333-8444-555555555555\"\ntitle = \"T\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"

-- ------------------------------------------------------------------ golem new (golem-cli ADR 0003, ADR 0006)

newTests :: TestTree
newTests =
  testGroup
    "golem new (golem-cli ADR 0003)"
    [ testCase "--no-fonts writes the five files of the template and exits with 0" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        (code, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        assertEqual err ExitSuccess code
        files <- filesUnder (tmp </> "book")
        files @?= [".gitignore", "chapters/01.gm", "manifest.toml", "preflight.toml", "style.toml"],
      testCase "--no-fonts names the Japanese font and its licence to place, with their URLs" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        (_, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        lines err
          @?= [ "フォントを取得しませんでした。次のファイルを置いてください。",
                "  book/fonts/NotoSerifJP-Regular.otf (https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/SubsetOTF/JP/NotoSerifJP-Regular.otf)",
                "  book/fonts/LICENSE-NotoSerifJP.txt (https://raw.githubusercontent.com/notofonts/noto-cjk/Serif2.003/Serif/LICENSE)"
              ],
      testCase "--language en --no-fonts names the Latin font and its licence" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        (_, _, err) <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        lines err
          @?= [ "フォントを取得しませんでした。次のファイルを置いてください。",
                "  book/fonts/SourceSerif4-Regular.otf (https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/OTF/SourceSerif4-Regular.otf)",
                "  book/fonts/LICENSE-SourceSerif4.md (https://raw.githubusercontent.com/adobe-fonts/source-serif/4.005R/LICENSE.md)"
              ],
      testCase "the manifest is in the language of the template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "ja", "--no-fonts"]
        _ <- golemAt tmp ["new", "en", "--language", "en", "--no-fonts"]
        ja <- readUtf8 (tmp </> "ja/manifest.toml")
        en <- readUtf8 (tmp </> "en/manifest.toml")
        (filter ("language = " `isPrefixOf`) (lines ja), filter ("language = " `isPrefixOf`) (lines en))
          @?= (["language = \"ja\""], ["language = \"en\""]),
      testCase "two projects get different ids" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "a", "--no-fonts"]
        _ <- golemAt tmp ["new", "b", "--no-fonts"]
        a <- filter ("id = \"urn:uuid:" `isPrefixOf`) . lines <$> readUtf8 (tmp </> "a/manifest.toml")
        b <- filter ("id = \"urn:uuid:" `isPrefixOf`) . lines <$> readUtf8 (tmp </> "b/manifest.toml")
        map length a @?= [length ("id = \"urn:uuid:" :: String) + 36 + 1]
        assertBool (show (a, b)) (a /= b),
      testCase "preflight.toml is based on print, with a Japanese header for ja (golem-cli ADR 0006)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--no-fonts"]
        rules <- lines <$> readUtf8 (tmp </> "book/preflight.toml")
        take 4 rules
          @?= [ "# golem preflight の設定です（入稿の前の検査）。",
                "# 書かなかった値は based-on の設定から引き継ぎます。",
                "# 印刷所から設定のファイルを受け取ったら、このファイルをそれに置き換えます。",
                "based-on = \"print\""
              ],
      testCase "preflight.toml has an English header for en (golem-cli ADR 0006)" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        rules <- lines <$> readUtf8 (tmp </> "book/preflight.toml")
        take 4 rules
          @?= [ "# The rules of golem preflight (the checks before handing off to the printer).",
                "# A value not written here comes from the rules of based-on.",
                "# When your printer gives you a file of rules, replace this file with it.",
                "based-on = \"print\""
              ],
      testCase "with the named font in place, golem check passes on the ja template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--no-fonts"]
        -- golem check looks for the font file and does not read it
        writeFiles (tmp </> "book") [("fonts/NotoSerifJP-Regular.otf", "font")]
        (code, _, err) <- golemAt (tmp </> "book") ["check"]
        (code, err) @?= (ExitSuccess, ""),
      testCase "with the named font in place, golem check passes on the en template" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        writeFiles (tmp </> "book") [("fonts/SourceSerif4-Regular.otf", "font")]
        (code, _, err) <- golemAt (tmp </> "book") ["check"]
        (code, err) @?= (ExitSuccess, ""),
      testCase "a directory that is not empty: 1, and its files are left alone" $ withSystemTempDirectory "golem-new" $ \tmp -> do
        writeFiles tmp [("book/notes.txt", "mine")]
        (code, _, err) <- golemAt tmp ["new", "book", "--no-fonts"]
        (code, err) @?= (ExitFailure 1, "ディレクトリが空ではありません: book\n")
        files <- filesUnder (tmp </> "book")
        files @?= ["notes.txt"]
    ]

-- ------------------------------------------------------------------ golem inspect (golem-cli ADR 0001)

inspectTests :: TestTree
inspectTests =
  testGroup
    "golem inspect (golem-cli ADR 0001)"
    [ testCase "the CST is the default, on stdout" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "本文。\n")]
        (code, out, err) <- golemAt tmp ["inspect", "a.gm"]
        (code, err) @?= (ExitSuccess, "")
        lines out
          @?= [ "NFile@0..10",
                "  NParagraph@0..10",
                "    KWhitespace@0..0 \"\"",
                "    KText@0..9 \"本文。\"",
                "    KNewline@9..10 \"\\n\"",
                "    KWhitespace@10..10 \"\""
              ],
      testCase "--as cst is the default" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "# 見出し\n\n本文。\n")]
        (_, byDefault, _) <- golemAt tmp ["inspect", "a.gm"]
        (code, cst, _) <- golemAt tmp ["inspect", "a.gm", "--as", "cst"]
        code @?= ExitSuccess
        cst @?= byDefault,
      testCase "--as ast shows the AST of the file" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("a.gm", "本文。\n")]
        (code, out, _) <- golemAt tmp ["inspect", "a.gm", "--as", "ast"]
        code @?= ExitSuccess
        assertBool out ("File {fileId = FileId 0, fileBlocks = [" `isPrefixOf` out && "Paragraph" `isInfixOf` out),
      testCase "--as ir shows the IR of the project and the size of its CBOR" $ withSystemTempDirectory "golem-inspect" $ \tmp -> do
        writeFiles tmp [("manifest.toml", manifestWith "[\"a.gm\"]"), ("a.gm", "本文。\n")]
        (code, out, _) <- golemAt tmp ["inspect", "a.gm", "--as", "ir"]
        code @?= ExitSuccess
        assertBool out ("Document {" `isPrefixOf` out)
        last (lines out) @?= "CBOR: 30 bytes"
    ]

-- ------------------------------------------------------------------ golem fmt over the project (golem-fmt ADR 0001)

-- | A project of two chapters; the second has two blank lines too many and trailing spaces.
fmtProject :: [(FilePath, String)]
fmtProject =
  [ ("manifest.toml", manifestWith "[\"chapters/01.gm\", \"chapters/02.gm\"]"),
    ("chapters/01.gm", "# はじめに\n\n本文。\n"),
    ("chapters/02.gm", "# 次に\n\n\n\n本文。  \n")
  ]

fmtTests :: TestTree
fmtTests =
  testGroup
    "golem fmt over the project (golem-fmt ADR 0001)"
    [ testCase "--check names only the unformatted chapter on stdout and exits with 1" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        (code, out, _) <- golemAt tmp ["fmt", "--check"]
        (code, out) @?= (ExitFailure 1, "chapters/02.gm\n"),
      testCase "--check leaves the file as it was" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        _ <- golemAt tmp ["fmt", "--check"]
        readUtf8 (tmp </> "chapters/02.gm") >>= (@?= "# 次に\n\n\n\n本文。  \n"),
      testCase "without --check, every chapter of the manifest is formatted in place and the exit code is 0" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        (code, out, err) <- golemAt tmp ["fmt"]
        (code, out, err) @?= (ExitSuccess, "", "")
        readUtf8 (tmp </> "chapters/02.gm") >>= (@?= "# 次に\n\n本文。\n"),
      testCase "a chapter already formatted is not rewritten" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        _ <- golemAt tmp ["fmt"]
        readUtf8 (tmp </> "chapters/01.gm") >>= (@?= "# はじめに\n\n本文。\n"),
      testCase "after golem fmt, --check passes with nothing on stdout" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        writeFiles tmp fmtProject
        _ <- golemAt tmp ["fmt"]
        (code, out, _) <- golemAt tmp ["fmt", "--check"]
        (code, out) @?= (ExitSuccess, ""),
      testCase "without a manifest: G0316 and 1" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        (code, _, err) <- golemAt tmp ["fmt"]
        code @?= ExitFailure 1
        assertBool err ("error[G0316]: manifest.toml がありません" `isInfixOf` err),
      testCase "a file that is not UTF-8 is left alone with 1" $ withSystemTempDirectory "golem-fmt" $ \tmp -> do
        BS.writeFile (tmp </> "b.gm") (BS.pack [0xff, 0xfe])
        (code, _, err) <- golemAt tmp ["fmt", "b.gm"]
        (code, err) @?= (ExitFailure 1, "b.gm: UTF-8 として読めないため整形しません\n")
        BS.readFile (tmp </> "b.gm") >>= (@?= BS.pack [0xff, 0xfe])
    ]

-- ------------------------------------------------------------------ golem plugin lock / fetch (golem-plugin ADR 0002)

-- | The SHA-256 of "AAA".
hashOfAAA :: String
hashOfAAA = "cb1ad2119d8fafb69566510ee712661f9f14b83385006ef92aec47f523a38358"

-- | A lock that names one plugin by a URL that cannot be reached.
lockOfAAA :: String
lockOfAAA = "[plugins.a]\nurl = \"https://example.invalid/a.wasm\"\nsha256 = \"" <> hashOfAAA <> "\"\n"

-- | Runs golem in a project with a plugin cache of its own.
inPluginProject :: [(FilePath, String)] -> [(FilePath, BS.ByteString)] -> [String] -> (FilePath -> (ExitCode, String, String) -> IO ()) -> IO ()
inPluginProject files cached args check = withSystemTempDirectory "golem-plugin" $ \tmp -> do
  let cache = tmp </> "cache"
  createDirectoryIfMissing True (cache </> "golem/plugins")
  mapM_ (\(p, b) -> BS.writeFile (cache </> "golem/plugins" </> p) b) cached
  createDirectoryIfMissing True (tmp </> "project")
  writeFiles (tmp </> "project") files
  r <- golemWithCache cache (tmp </> "project") args
  check (tmp </> "project") r

pluginTests :: TestTree
pluginTests =
  testGroup
    "golem plugin lock and fetch (golem-plugin ADR 0002)"
    [ testCase "lock with no plugin declared writes an empty plugins.lock and exits with 0" $
        inPluginProject [("manifest.toml", manifestWith "[]")] [] ["plugin", "lock"] $ \dir (code, _, err) -> do
          (code, err) @?= (ExitSuccess, "")
          BS.readFile (dir </> "plugins.lock") >>= (@?= ""),
      testCase "lock with an HTTP URL: 1, and plugins.lock is left as it was"
        $ inPluginProject
          [ ("manifest.toml", manifestWith "[]" <> "\n[plugins.ruby]\nurl = \"http://example.invalid/a.wasm\"\n"),
            ("plugins.lock", lockOfAAA)
          ]
          []
          ["plugin", "lock"]
        $ \dir (code, _, err) -> do
          (code, err) @?= (ExitFailure 1, "ruby: HTTPS の URL だけを使えます: http://example.invalid/a.wasm\n")
          readUtf8 (dir </> "plugins.lock") >>= (@?= lockOfAAA),
      testCase "fetch without plugins.lock has nothing to do and exits with 0" $
        inPluginProject [("manifest.toml", manifestWith "[]")] [] ["plugin", "fetch"] $ \_ (code, _, err) ->
          (code, err) @?= (ExitSuccess, ""),
      testCase "fetch with a plugins.lock that is not TOML: G0611 at its place in plugins.lock" $
        inPluginProject [("manifest.toml", manifestWith "[]"), ("plugins.lock", "[plugins.a\n")] [] ["plugin", "fetch"] $ \_ (code, _, err) -> do
          code @?= ExitFailure 1
          take 1 (lines err) @?= ["plugins.lock:1:11: error[G0611]: TOML の誤りです: ここに行末は書けません"],
      testCase "fetch of an artifact already in the cache needs no network" $
        inPluginProject [("manifest.toml", manifestWith "[]"), ("plugins.lock", lockOfAAA)] [(hashOfAAA <> ".wasm", "AAA")] ["plugin", "fetch"] $ \_ (code, _, err) ->
          (code, err) @?= (ExitSuccess, ""),
      testCase "fetch of an artifact missing from the cache downloads it, and an HTTP URL is refused" $
        inPluginProject [("manifest.toml", manifestWith "[]"), ("plugins.lock", "[plugins.a]\nurl = \"http://example.invalid/a.wasm\"\nsha256 = \"" <> hashOfAAA <> "\"\n")] [] ["plugin", "fetch"] $ \_ (code, _, err) ->
          (code, err) @?= (ExitFailure 1, "a: HTTPS の URL だけを使えます: http://example.invalid/a.wasm\n"),
      testCase "fetch does not take a cached artifact whose hash differs from plugins.lock"
        $ inPluginProject
          [("manifest.toml", manifestWith "[]"), ("plugins.lock", "[plugins.a]\nurl = \"http://example.invalid/a.wasm\"\nsha256 = \"" <> hashOfAAA <> "\"\n")]
          [(hashOfAAA <> ".wasm", "BBB")]
          ["plugin", "fetch"]
        $ \_ (code, _, err) ->
          -- the cached bytes are refused, so fetch goes to the URL, which is refused in turn
          (code, err) @?= (ExitFailure 1, "a: HTTPS の URL だけを使えます: http://example.invalid/a.wasm\n")
    ]

-- ------------------------------------------------------------------ golem preflight (golem-cli ADR 0006)

preflightTests :: TestTree
preflightTests =
  testGroup
    "golem preflight (golem-cli ADR 0006)"
    [ testCase "no PDF made: 1, and no summary line" $ withSystemTempDirectory "golem-preflight" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        (code, _, err) <- golemAt (tmp </> "book") ["preflight"]
        code @?= ExitFailure 1
        assertBool err ("error[G0802]" `isInfixOf` err)
        assertBool err (not ("プリフライト（" `isInfixOf` err)),
      testCase "the summary of a new project names its preflight.toml, based on print, and counts the errors" $ withSystemTempDirectory "golem-preflight" $ \tmp -> do
        _ <- golemAt tmp ["new", "book", "--language", "en", "--no-fonts"]
        font <- BL.readFile "../golem-font/test/fonts/SourceSansPro-Regular.otf"
        createDirectoryIfMissing True (tmp </> "book/fonts")
        BL.writeFile (tmp </> "book/fonts/SourceSerif4-Regular.otf") font
        (code, _, err) <- golemAt (tmp </> "book") ["preflight"]
        -- the template has no bleed (G0910) and no output intent (G0914)
        code @?= ExitFailure 1
        let summary = last (lines err)
        assertBool summary ("プリフライト（設定: preflight.toml、基にした設定: print）: エラー 2、警告 0。" `isPrefixOf` summary)
    ]
