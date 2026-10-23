module Main (main) where

import ColophonSpec qualified
import Control.Monad (forM_, void)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NE
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Ratio ((%))
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.Assemble (NoteNumbering (..))
import Golem.Doc.ListMarkers (ListNumberStyle (..), NumberFormat (..))
import Golem.Parser.SourceSettings
import Golem.Project hiding (loadProject)
import Golem.Project qualified as P
import Golem.Project.Imports (ImportGraph (..), ImportSite (..), findCycles, topoOrder)
import Golem.Project.Paths
import Golem.Project.Style
import Golem.Syntax
import OutputCharsSpec qualified
import StylePositionSpec qualified
import System.Directory (createDirectoryIfMissing, createFileLink)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import TomlMessageSpec qualified

main :: IO ()
main = defaultMain tests

-- | The diagnostics of a failed load, without the sources (golem-project ADR 0006).
loadProject :: FilePath -> IO (Either [Diagnostic] Project)
loadProject = fmap (first pfDiagnostics) . P.loadProject

manifest :: [Text] -> Text
manifest chapters =
  T.unlines
    [ "chapters = [" <> T.intercalate ", " chapters <> "]",
      "",
      "[metadata]",
      "id = \"urn:uuid:00000000-0000-4000-8000-000000000000\"",
      "title = \"テスト\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      "",
      "[targets.html]"
    ]

withProject :: [(FilePath, Text)] -> (FilePath -> IO a) -> IO a
withProject files act = withSystemTempDirectory "golem" $ \root -> do
  mapM_ (\(p, c) -> createDirectoryIfMissing True (takeDirectory (root </> p)) >> TIO.writeFile (root </> p) c) files
  act root

-- | The manifest with a [source] table (and other text) after it.
manifestWith :: [Text] -> Text -> Text
manifestWith chapters extra = manifest chapters <> "\n" <> extra

-- | The separator of each file of the project, by path.
separators :: Project -> [(FilePath, ParagraphSeparator)]
separators p =
  [ (path, ssParagraphSeparator s)
  | (fid, s) <- Map.toList (projectSourceSettings p),
    Just path <- [lookupPath fid (projectFiles p)]
  ]

sourceTests :: TestTree
sourceTests =
  testGroup
    "[source] (docs/adr ADR 0013)"
    [ testCase "without [source] the settings are the default" $
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> do
              manifestSource (projectManifest p) @?= defaultSourceSettings
              separators p @?= [("a.gm", BlankLineSeparated)],
      testCase "paragraph-separator = \"line\" is read" $
        withProject [("manifest.toml", manifestWith ["\"a.gm\""] "[source]\nparagraph-separator = \"line\"\n"), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> ssParagraphSeparator (manifestSource (projectManifest p)) @?= LineSeparated,
      testCase "an invalid value and an unknown key are G03001" $ do
        withProject [("manifest.toml", manifestWith ["\"a.gm\""] "[source]\nparagraph-separator = \"lines\"\n"), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G03001"]) . codes
        withProject [("manifest.toml", manifestWith ["\"a.gm\""] "[source]\nparagraph-separators = \"line\"\n"), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G03001"]) . codes
        withProject [("manifest.toml", manifest ["{ file = \"a.gm\", paragraph-separator = \"lines\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G03001"]) . codes
        withProject [("manifest.toml", manifest ["{ file = \"a.gm\", unknown = \"x\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G03001"]) . codes,
      testCase "a chapter entry overrides [source]; imported files take [source]"
        $ withProject
          [ ("manifest.toml", manifestWith ["\"a.gm\"", "{ file = \"b.gm\", paragraph-separator = \"blank-line\" }"] "[source]\nparagraph-separator = \"line\"\n"),
            ("a.gm", "@import c.gm as c\n"),
            ("b.gm", "@import c.gm as c\n"),
            ("c.gm", "@set x = 1\n")
          ]
        $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> do
              separators p @?= [("a.gm", LineSeparated), ("b.gm", BlankLineSeparated), ("c.gm", LineSeparated)]
              map (\(_, m, es) -> (m, length es)) (chapterFiles (manifestChapters (projectManifest p))) @?= [(Nothing, 0), (Nothing, 1)],
      testCase "the same file twice with different settings is G03001" $ do
        withProject [("manifest.toml", manifest ["\"a.gm\"", "{ file = \"a.gm\", paragraph-separator = \"line\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G03001"]) . codes
        withProject [("manifest.toml", manifest ["\"a.gm\"", "{ file = \"a.gm\", paragraph-separator = \"blank-line\" }"]), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= []) . codes
    ]

-- | [diagnostics] silence-notices of the manifest (golem-syntax ADR 0002).
silenceTests :: TestTree
silenceTests =
  testGroup
    "[diagnostics] silence-notices (golem-syntax ADR 0002)"
    [ testCase "the codes of notices are read" $
        fmap manifestSilencedNotices (parse "[diagnostics]\nsilence-notices = [\"G02062\"]\n") @?= Right (Set.fromList [DiagnosticCode "G02062"]),
      testCase "without [diagnostics] and with an empty array nothing is silenced" $ do
        fmap manifestSilencedNotices (parse "") @?= Right Set.empty
        fmap manifestSilencedNotices (parse "[diagnostics]\nsilence-notices = []\n") @?= Right Set.empty,
      testCase "a code that is no notice, or no code, is G03024 at the element" $
        mapM_
          ( \c -> do
              let extra = "[diagnostics]\nsilence-notices = [\"G02062\", \"" <> c <> "\"]\n"
                  src = manifestWith ["\"a.gm\""] extra
                  at = BS.length (TE.encodeUtf8 (fst (T.breakOn ("\"" <> c <> "\"") src)))
              case parseManifest (FileId 0) src of
                Left [d] -> (diagCode d, spanStart (diagSpan d)) @?= (DiagnosticCode "G03024", at)
                other -> assertFailure (T.unpack c <> ": " <> show (codes other))
          )
          ["G01001", "G02005", "G02048", "G99999", "G0262", "all", "g02062"],
      testCase "a code of four digits is G03024 with the form of a code (docs/adr 0061)" $
        case parse "[diagnostics]\nsilence-notices = [\"G0262\"]\n" of
          Left [d] -> do
            diagCode d @?= DiagnosticCode "G03024"
            assertBool (T.unpack (diagMessage d)) ("診断のコードは G と 5 桁の数字で書きます: G0262" `T.isInfixOf` diagMessage d)
          other -> assertFailure (show (codes other)),
      testCase "a string instead of an array is G03001" $
        codes (parse "[diagnostics]\nsilence-notices = \"all\"\n") @?= ["G03001"],
      testCase "an unknown key of [diagnostics] is G03001" $
        codes (parse "[diagnostics]\nsilence-warnings = [\"G02005\"]\n") @?= ["G03001"]
    ]
  where
    parse extra = parseManifest (FileId 0) (manifestWith ["\"a.gm\""] extra)

-- | The running head of a master page (golem-driver ADR 0014).
runningHeadTests :: TestTree
runningHeadTests =
  testGroup
    "running heads (golem-driver ADR 0014)"
    [ testCase "content is both pages" $
        runningHead "content = \"heading.1.short\""
          @?= Right (Just (RunningHeadDef "top-outside" (one [ref (RefHeading 1 HeadShort PickFirst)]) (one [ref (RefHeading 1 HeadShort PickFirst)]))),
      testCase "even and odd" $ do
        runningHead "even = \"title\", odd = \"heading.2.numbered.last\""
          @?= Right (Just (RunningHeadDef "top-outside" (one [ref (RefHeading 2 HeadNumbered PickLast)]) (one [ref (RefMeta "title")])))
        fmap (fmap rhOdd) (runningHead "content = \"none\"") @?= Right (Just RunningNone)
        fmap (fmap rhEven) (runningHead "content = \"heading.3.short.last\"") @?= Right (Just (one [ref (RefHeading 3 HeadShort PickLast)])),
      testCase "wrong values are G03014" $ do
        codes (runningHead "content = \"heading.0.short\"") @?= ["G03014"]
        codes (runningHead "content = \"heading.1.long\"") @?= ["G03014"]
        codes (runningHead "content = \"chapter\"") @?= ["G03014"]
        codes (runningHead "even = \"title\", odd = \"heading.x.short\"") @?= ["G03014"],
      testCase "content with even or odd, one of even and odd, or none is G03014" $ do
        codes (runningHead "content = \"title\", odd = \"title\"") @?= ["G03014"]
        codes (runningHead "even = \"title\"") @?= ["G03014"]
        codes (runningHead "odd = \"title\"") @?= ["G03014"]
        codes (runningHead "") @?= ["G03014"],
      testCase "the message names the value and the vocabulary" $ do
        let ms = messages (runningHead "content = \"chapter\"")
        assertBool (show ms) (any ("heading.<階層>.short" `T.isInfixOf`) ms && any ("chapter" `T.isInfixOf`) ms),
      -- golem-driver ADR 0022: formats
      testCase "a format of one line (ADR 0022)" $
        fmap (fmap rhOdd) (runningHead "content = [\"{meta.title}　{heading.1.numbered}\"]")
          @?= Right (Just (one [ref (RefMeta "title"), PartText "　", ref (RefHeading 1 HeadNumbered PickFirst)])),
      testCase "a format of two lines (ADR 0022)" $
        fmap (fmap rhOdd) (runningHead "content = [\"{meta.title}\", \"{heading.1.short}\"]")
          @?= Right (Just (RunningLines ([ref (RefMeta "title")] :| [[ref (RefHeading 1 HeadShort PickFirst)]]))),
      testCase "?, .last and number (ADR 0022)" $ do
        parseRunningFormat "{heading.2.short.last?}" @?= Right [PartRef (RefHeading 2 HeadShort PickLast) True]
        parseRunningFormat "{heading.1.number}" @?= Right [ref (RefHeading 1 HeadNumber PickFirst)]
        parseRunningFormat "{heading.1.number.last}" @?= Right [ref (RefHeading 1 HeadNumber PickLast)],
      testCase "variables (ADR 0022)" $ do
        parseRunningFormat "{set.revision}" @?= Right [ref (RefVar ["revision"])]
        parseRunningFormat "{set.values.price}" @?= Right [ref (RefVar ["values", "price"])],
      testCase "{{ and }} are braces (ADR 0022)" $
        fmap (fmap rhOdd) (runningHead "content = [\"{{書名}}\"]") @?= Right (Just (one [PartText "{書名}"])),
      testCase "the vocabulary is read as formats (ADR 0022)" $ do
        fmap (fmap rhOdd) (runningHead "content = \"heading.1.short\"") @?= Right (Just (RunningLines ([PartRef (RefHeading 1 HeadShort PickFirst) False] :| [])))
        fmap (fmap rhOdd) (runningHead "content = \"title\"") @?= Right (Just (one [ref (RefMeta "title")]))
        fmap (fmap rhOdd) (runningHead "content = \"none\"") @?= Right (Just RunningNone),
      testCase "a string and an array together (ADR 0022)" $
        runningHead "even = \"title\", odd = [\"{heading.1.short}\"]"
          @?= Right (Just (RunningHeadDef "top-outside" (one [ref (RefHeading 1 HeadShort PickFirst)]) (one [ref (RefMeta "title")]))),
      testCase "wrong formats are G03014 at the value (ADR 0022)" $
        forM_
          [ "[\"{heading.1.short\"]",
            "[\"a}b\"]",
            "[\"{}\"]",
            "[\"{heading.0.short}\"]",
            "[\"{heading.1.long}\"]",
            "[\"{meta.author}\"]",
            "[\"{meta.creators}\"]",
            "[\"{chapter}\"]",
            "[]",
            "[\"\"]",
            "[\"a\\nb\"]",
            "[1]",
            "\"{meta.title}　{heading.1.short}\""
          ]
          ( \v -> do
              let src = "[masters.body]\nrunning-head = { position = \"top-outside\", content = " <> v <> " }\n"
                  at = T.length "[masters.body]\nrunning-head = { position = \"top-outside\", content = "
              case parseStyle (FileId 0) src of
                Left [d] -> (diagCode d, spanStart (diagSpan d)) @?= (DiagnosticCode "G03014", at)
                other -> assertFailure (T.unpack v <> ": " <> show (codes other))
          ),
      testCase "a format in a string points to arrays (ADR 0022)" $ do
        let ms = messages (runningHead "content = \"{meta.title}　{heading.1.short}\"")
        assertBool (show ms) (any ("配列" `T.isInfixOf`) ms),
      testCase "an unknown position of a running head or a folio is G03018 (golem-driver ADR 0016)" $ do
        let st = parseStyle (FileId 0) "[masters.body]\nrunning-head = { position = \"middle\", content = \"title\" }\n"
        codes st @?= ["G03018"]
        map (T.isPrefixOf "未知の位置です: middle") (messages st) @?= [True]
        let fo = parseStyle (FileId 0) "[masters.body]\nfolio = { position = \"middle\", format = \"{n}\" }\n"
        codes fo @?= ["G03018"]
        map (T.isPrefixOf "未知の位置です: middle") (messages fo) @?= [True]
        case fo of
          Left [d] -> spanStart (diagSpan d) @?= T.length "[masters.body]\nfolio = { position = "
          other -> assertFailure (show other)
        codes (parseStyle (FileId 0) "[masters.body]\nfolio = { position = \"bottom-center\", format = \"{n}\" }\n") @?= [],
      testCase "the running-head of a heading is retired (G03019)" $ do
        let r = parseStyle (FileId 0) "[headings.1]\nrunning-head = true\n"
        codes r @?= ["G03019"]
        assertBool (show (messages r)) (any ("[masters." `T.isInfixOf`) (messages r))
    ]
  where
    runningHead kv =
      (\s -> Map.lookup "body" (stMasters s) >>= mdRunningHead)
        <$> parseStyle (FileId 0) ("[masters.body]\nrunning-head = { position = \"top-outside\"" <> (if T.null kv then "" else ", " <> kv) <> " }\n")
    messages = either (map diagMessage) (const [])
    one ps = RunningLines (ps :| [])
    ref r = PartRef r False

msgs :: Either [Diagnostic] a -> [Text]
msgs = either (map diagMessage) (const [])

-- | The 1-based line of the start of a diagnostic in a source.
lineOf :: Text -> Diagnostic -> Int
lineOf src d = T.count "\n" (T.take (spanStart (diagSpan d)) src) + 1

-- | The messages of the TOML files in Japanese (golem-project ADR 0007).
tomlMessageTests :: TestTree
tomlMessageTests =
  testGroup
    "TOML messages in Japanese (golem-project ADR 0007)"
    [ testCase "an unknown key of style.toml names the full path at its line" $ do
        let src = "[page]\nsize = \"A6\"\nbindng = \"left\"\n"
        case parseStyle (FileId 0) src of
          Left [d] -> do
            diagCode d @?= DiagnosticCode "G03006"
            diagMessage d @?= "知らないキーです: page.bindng"
            lineOf src d @?= 3
          r -> assertFailure (show r),
      testCase "a missing table of manifest.toml" $
        withProject [("manifest.toml", "chapters = [\"a.gm\"]\n\n[targets.html]\n"), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03001"]
          msgs r @?= ["必須のキーがありません: metadata"],
      testCase "a missing key of [metadata]" $
        withProject [("manifest.toml", T.replace "title = \"テスト\"\n" "" (manifest ["\"a.gm\""])), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03001"]
          msgs r @?= ["必須のキーがありません: metadata.title"],
      -- the ADR's example is bleed = 3, but a dimension says 長さは文字列で書きます
      -- by Golem's own fail (ADR 0006); binding is read by toml-parser's FromValue
      testCase "a value of the wrong type" $
        msgs (parseStyle (FileId 0) "[page]\nsize = \"A6\"\nbinding = 3\n") @?= ["page.binding には文字列を書きます（整数が書かれています）"],
      testCase "a page size that is neither a name nor a table" $ do
        let r = parseStyle (FileId 0) "[page]\nsize = 3\n"
        assertBool (show (msgs r)) (not (null (msgs r)) && all ("判型の名前か { width = ..., height = ... } を書きます" `T.isPrefixOf`) (msgs r)),
      testCase "a chapter that is not a path names chapters[0]" $
        withProject [("manifest.toml", T.replace "chapters = [\"a.gm\"]" "chapters = [3]" (manifest ["\"a.gm\""])), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          assertBool (show (msgs r)) (not (null (msgs r)) && all ("chapters[0]" `T.isInfixOf`) (msgs r)),
      testCase "a table written twice is at the second table" $ do
        let src = "[page]\nsize = \"A6\"\n\n[page]\nbleed = \"3mm\"\n"
        case parseStyle (FileId 0) src of
          Left [d] -> do
            diagCode d @?= DiagnosticCode "G03006"
            diagMessage d @?= "TOML の誤りです: 閉じた表にキーを足しています: page"
            lineOf src d @?= 4
          r -> assertFailure (show r),
      -- toml-parser reports a string that runs into a newline as the end of the
      -- line; a string that runs into the end of the file is unterminated
      testCase "an unterminated string is at its line" $ do
        let src = "[page]\nsize = \"A6\"\n\n[x]\ntitle = \"abc"
        case parseStyle (FileId 0) src of
          Left [d] -> do
            diagMessage d @?= "TOML の誤りです: 文字列が閉じていません"
            lineOf src d @?= 5
          r -> assertFailure (show r),
      testCase "a line that ends after =" $ do
        let ms = msgs (parseStyle (FileId 0) "[x]\ntitle = \n")
        assertBool (show ms) (not (null ms) && all (\m -> "TOML の誤りです: " `T.isPrefixOf` m && "行末" `T.isInfixOf` m) ms),
      testCase "a leading zero" $ do
        let ms = msgs (parseStyle (FileId 0) "n = 012\n")
        assertBool (show ms) (not (null ms) && all ("整数の先頭に 0 は書けません" `T.isInfixOf`) ms)
    ]

-- | The diagnostics of the project stage (ADR 0006).
diagnosticCodeTests :: TestTree
diagnosticCodeTests =
  testGroup
    "project diagnostic codes (ADR 0006)"
    [ testCase "no manifest.toml is G03016" $
        withProject [("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03016"]
          msgs r @?= ["manifest.toml がありません"],
      testCase "a missing import is G03002 at the @import" $
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import c.gm as c\n@import nope.gm as x\n"), ("c.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03002"]
          msgs r @?= ["ファイルがありません: nope.gm"]
          either (map (\d -> (spanFile (diagSpan d), spanStart (diagSpan d)))) (const []) r @?= [(FileId 1, 18)],
      testCase "absolute paths and links out of the root are G03003" $ do
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import /abs.gm as x\n")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03003"]
          msgs r @?= ["絶対パスは使えません: /abs.gm"]
        withSystemTempDirectory "golem-outside" $ \outside -> do
          TIO.writeFile (outside </> "x.gm") ""
          withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import x.gm as x\n")] $ \root -> do
            createFileLink (outside </> "x.gm") (root </> "x.gm")
            r <- loadProject root
            codes r @?= ["G03003"]
            msgs r @?= ["プロジェクトルートの外を指しています: x.gm"],
      testCase "a cycle of three files" $
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import b.gm as b\n"), ("b.gm", "@import c.gm as c\n"), ("c.gm", "@import a.gm as a\n")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03005"]
          msgs r @?= ["import が循環しています: a.gm → b.gm → c.gm → a.gm"]
          either (map (length . diagRelated)) (const []) r @?= [3],
      testCase "an empty [targets] is G03001" $
        withProject [("manifest.toml", T.replace "[targets.html]" "[targets]" (manifest ["\"a.gm\""])), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03001"]
          msgs r @?= ["出力ターゲットが一つもありません"],
      testCase "a TOML syntax error in manifest.toml is G03001" $
        withProject [("manifest.toml", "chapters = [\n"), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03001"]
          assertBool (show (msgs r)) (all ("TOML の誤りです: " `T.isPrefixOf`) (msgs r)),
      testCase "an empty path is not shown" $
        withProject [("manifest.toml", "chapters = [\"a.gm\"]\n\n[targets.html]\n"), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03001"]
          assertBool (show (msgs r)) (any ("必須のキーがありません: metadata" `T.isSuffixOf`) (msgs r))
          assertBool (show (msgs r)) (not (any ("()" `T.isInfixOf`) (msgs r))),
      testCase "a chapter that is not a path, table or array" $
        withProject [("manifest.toml", T.replace "chapters = [\"a.gm\"]" "chapters = [1]" (manifest ["\"a.gm\""])), ("a.gm", "")] $ \root -> do
          r <- loadProject root
          codes r @?= ["G03001"]
          msgs r @?= ["章は、ファイルのパス、表、配列のどれかで書きます (chapters[0])"],
      testCase "a malformed @import is G03009" $
        mapM_
          ( \src -> withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", src), ("x.gm", "")] $ \root -> do
              r <- loadProject root
              assertEqual (T.unpack src) ["G03009"] (codes r)
              assertEqual (T.unpack src) ["@import は「@import パス as 名前空間」の形で書きます"] (msgs r)
          )
          [ "@import x.gm\n",
            "@import x.gm as\n",
            "@import [= 1] as x\n",
            "@import x.gm as x extra\n",
            "@import x.gm\n@label a\n# 見出し\n"
          ],
      testCase "a TOML syntax error in style.toml is G03006" $ do
        let r = parseStyle (FileId 0) "[page\n"
        codes r @?= ["G03006"]
        assertBool (show (msgs r)) (all ("TOML の誤りです: " `T.isPrefixOf`) (msgs r)),
      testCase "the messages Golem writes are Japanese" $ do
        let has src m = let ms = msgs (parseStyle (FileId 0) src) in assertBool (show ms) (any (m `T.isInfixOf`) ms)
            grid extra = "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n" <> extra
        has "[toc]\nleader = \"dash\"\n" "leader に使えない値です: dash（dots, none のどれか）"
        has (grid "columns = 2\n") "columns が 2 以上のときは column-gap が要ります"
        has "[paragraph-styles.x]\nspace-between = -1\n" "space-between は 0 以上です"
        has "[paragraph-styles.x]\nfirst-line-indent = \"abc\"\n" "長さの書き方が不正です: abc（1zw や -1zw のように書きます）"
        has "[page]\nsize = \"A6\"\nbleed = \"abc\"\n" "長さの書き方が不正です: abc（13Q や 20mm のように書きます）"
        has "[page]\nsize = \"A6\"\nbleed = 3\n" "長さは文字列で書きます"
        has "[color.swatches]\na = { cmyk = [0, 0, 0, 101] }\n" "cmyk は 0 から 100 までの整数四つです"
        has "[headings.4]\n" "見出しの段は 1、2、3 のどれかです: 4",
      testCase "the checks after reading" $ do
        msgs (parseStyle (FileId 0) "[figures]\nnumber = \"{x}\"\n") @?= ["番号の書式が不正です: {x}"]
        msgs (parseStyle (FileId 0) "[character-styles.Bad]\nsynthetic-bold = true\n") @?= ["スタイルの名前は英小文字で始まり、英小文字、数字、- だけからなります: Bad"]
        msgs (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = 10001\n") @?= ["explicit-hyphen-penalty は -9999 から 10000 までです: 10001"]
        -- a negative overhang cannot be written as a dimension, so the check after reading is not reached
        msgs (parseStyle (FileId 0) "[composition.ruby]\noverhang = \"-1zw\"\n") @?= ["長さの書き方が不正です: -1zw（13Q や 20mm のように書きます） (composition.ruby.overhang)"]
        -- an unknown page size is G03017 at the value since golem-project ADR 0005
        let r = parseStyle (FileId 0) "[page]\nsize = \"Z9\"\n"
        codes r @?= ["G03017"]
        assertBool (show (msgs r)) (all ("未知の判型です: Z9" `T.isPrefixOf`) (msgs r))
    ]

codes :: Either [Diagnostic] a -> [Text]
codes = either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const [])

tests :: TestTree
tests =
  testGroup
    "golem-project"
    [ -- golem-parser ADR 0011
      testCase "[numbers] vertical takes auto and auto-digits" $ do
        let vertical src = stNumbersVertical <$> parseStyle (FileId 0) src
        vertical "[numbers]\nvertical = \"auto\"\n" @?= Right "auto"
        vertical "[numbers]\nvertical = \"auto-digits\"\n" @?= Right "auto-digits"
        case vertical "[numbers]\nvertical = \"automatic\"\n" of
          Left _ -> pure ()
          Right v -> assertFailure (show v),
      testCase "normalisation" $ do
        normalizeRelative "./a/../b/c.gm" @?= Right "b/c.gm"
        normalizeRelative "../x.gm" @?= Left EscapesRoot
        normalizeRelative "/etc/passwd" @?= Left Absolute
        normalizeRelative "https://example.com/a.gm" @?= Left Url,
      testCase "loads chapters and imports in a deterministic order"
        $ withProject
          [ ("manifest.toml", manifest ["\"ch/01.gm\"", "[\"ch/02.gm\", { file = \"ch/03.gm\", master = \"body\" }]"]),
            ("ch/01.gm", "@import common/v.gm as v\n\n本文。\n"),
            ("ch/02.gm", "@import common/v.gm as v\n@import common/w.gm as w\n"),
            ("ch/03.gm", "三。\n"),
            ("common/v.gm", "@import common/w.gm as w\n@set x = 1\n"),
            ("common/w.gm", "@set y = 2\n")
          ]
        $ \root -> do
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> do
              map snd (fileTableEntries (projectFiles p)) @?= ["manifest.toml", "ch/01.gm", "ch/02.gm", "ch/03.gm", "common/v.gm", "common/w.gm"]
              map snd (projectChapters p) @?= [Nothing, Nothing, Just "body"]
              -- w before v (dependency), v before the chapters importing it
              let order = projectOrder p
                  pos f = length (takeWhile (/= f) order)
              assertBool "w before v" (pos (FileId 5) < pos (FileId 4))
              assertBool "v before ch/01" (pos (FileId 4) < pos (FileId 1)),
      testCase "import cycles are reported with their path"
        $ withProject
          [ ("manifest.toml", manifest ["\"a.gm\""]),
            ("a.gm", "@import b.gm as b\n"),
            ("b.gm", "@import a.gm as a\n")
          ]
        $ \root -> do
          r <- loadProject root
          codes r @?= ["G03005"]
          case r of
            Left [d] -> length (diagRelated d) @?= 2
            _ -> pure (),
      testCase "self import is a cycle" $
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import a.gm as a\n")] $ \root ->
          loadProject root >>= (@?= ["G03005"]) . codes,
      testCase "missing files, escaping paths, URLs" $ do
        withProject [("manifest.toml", manifest ["\"nope.gm\""])] $ \root -> loadProject root >>= (@?= ["G03002"]) . codes
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import ../x.gm as x\n")] $ \root -> loadProject root >>= (@?= ["G03003"]) . codes
        withProject [("manifest.toml", manifest ["\"a.gm\""]), ("a.gm", "@import \"https://e.com/x.gm\" as x\n")] $ \root -> loadProject root >>= (@?= ["G03003"]) . codes,
      testCase "case-only differences are errors"
        $ withProject
          [ ("manifest.toml", manifest ["\"a.gm\"", "\"b.gm\""]),
            ("a.gm", "@import Common.gm as c\n"),
            ("b.gm", "@import common.gm as c\n"),
            ("Common.gm", "@set x = 1\n"),
            ("common.gm", "@set x = 1\n")
          ]
        $ \root -> do
          r <- loadProject root
          -- the written paths are compared on every file system (ADR 0006)
          codes r @?= ["G03004"]
          msgs r @?= ["大文字と小文字だけが異なるパスです: common.gm と Common.gm"],
      testCase "symbolic links are resolved to the same file"
        $ withProject
          [ ("manifest.toml", manifest ["\"a.gm\"", "\"b.gm\""]),
            ("a.gm", "@import real.gm as r\n"),
            ("b.gm", "@import link.gm as r\n"),
            ("real.gm", "@set x = 1\n")
          ]
        $ \root -> do
          createFileLink (root </> "real.gm") (root </> "link.gm")
          r <- loadProject root
          case r of
            Left ds -> assertFailure (show ds)
            Right p -> length (fileTableEntries (projectFiles p)) @?= 4,
      testCase "unknown manifest keys and missing id are errors" $ do
        withProject [("manifest.toml", manifest ["\"a.gm\""] <> "\n[extra]\nx = 1\n"), ("a.gm", "")] $ \root -> loadProject root >>= (@?= ["G03001"]) . codes
        withProject [("manifest.toml", T.replace "id = " "idd = " (manifest ["\"a.gm\""])), ("a.gm", "")] $ \root -> loadProject root >>= (@?= True) . (not . null) . codes,
      sourceTests,
      diagnosticCodeTests,
      tomlMessageTests,
      TomlMessageSpec.tests,
      ColophonSpec.tests,
      OutputCharsSpec.tests,
      StylePositionSpec.tests,
      testCase "dimensions" $ do
        parseDim "1pt" @?= Just (Abs 65536)
        parseDim "25.4mm" @?= Just (Abs (72 * 65536))
        parseDim "4Q" @?= Just (Abs (round (72 * 65536 / (25.4 :: Rational))))
        parseDim "1H" @?= parseDim "0.25mm"
        parseDim "2zw" @?= Just (Zw 2)
        parseDim "3em" @?= Nothing,
      testCase "the inch unit (golem-project ADR 0010)" $ do
        parseDim "1in" @?= Just (Abs (72 * 65536))
        parseDim "0.125in" @?= Just (Abs (9 * 65536))
        parseDim "8.5in" @?= parseDim "612pt"
        parseDim "0.1in" @?= Just (Abs (round (72 * 65536 / (10 :: Rational))))
        fmap (\case Abs x -> x < 0; Zw _ -> False) (parseSignedDim "-0.5in") @?= Just True
        parseSignedDim "-0.5in" @?= Just (Abs (-(36 * 65536)))
        parseDim "1 in" @?= Nothing
        parseDim "1In" @?= Nothing,
      testCase "style.toml from the specification" $
        case parseStyle (FileId 0) specStyle of
          Left ds -> assertFailure (show ds)
          Right s -> do
            Map.keys (stHeadings s) @?= [1, 2]
            fmap pageSizeSpec (stPage s) @?= Just (NamedSize "B6")
            Map.lookup "accent" (stSwatches s) @?= Just (Swatch (0, 80, 100, 0)),
      testCase "mass-market paperback size (ADR 0003)" $ do
        pageSize "mass-market" @?= Just (10795 / 100, 174625 / 1000)
        pageSize "A6" @?= Just (105, 148),
      testCase "style.toml errors" $ do
        codes (parseStyle (FileId 0) "[page]\nsize = \"B6\"\nunknown = 1\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[emphasis]\nstrong = \"underline\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[color.swatches]\na = { cmyk = [0, 0, 0, 101] }\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[figures]\nnumber = \"{x}\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[frames]\nx = 1\n") @?= ["G03006"],
      testCase "the lines of a heading (golem-driver ADR 0032)" $ do
        let linesOf src = either (const Nothing) (\s -> Just (hsLines <$> Map.lookup 2 (stHeadings s))) (parseStyle (FileId 0) src)
        linesOf "[headings.2]\nlines = 3\n" @?= Just (Just (Just 3))
        linesOf "[headings.2]\nnumber = \"{n}\"\n" @?= Just (Just Nothing)
        mapM_
          (\v -> codes (parseStyle (FileId 0) ("[headings.2]\nlines = " <> v <> "\n")) @?= ["G03006"])
          ["0", "-1", "1.5", "\"3\""],
      testCase "the placement of notes (golem-driver ADR 0026)" $ do
        fmap stNotesPlacement (parseStyle (FileId 0) "") @?= Right PlaceFoot
        fmap stNotesPlacement (parseStyle (FileId 0) "[notes]\nplacement = \"chapter-end\"\n") @?= Right PlaceChapterEnd
        codes (parseStyle (FileId 0) "[notes]\nchapter-end-title = \"注\"\n") @?= ["G03006"],
      testCase "the size and format of note marks (golem-driver ADR 0025)" $ do
        let notes src = either (const Nothing) (\s -> Just (stNotesMarkSize s, stNotesMarkFormat s)) (parseStyle (FileId 0) src)
            sizeOf v = fst <$> notes ("[notes]\nmark-size = \"" <> v <> "\"\n")
            formatOf v = snd <$> notes ("[notes]\nmark-format = \"" <> v <> "\"\n")
        notes "" @?= Just (Zw (1 % 2), "*{n}")
        sizeOf "0.65zw" @?= Just (Zw (65 % 100))
        sizeOf "6pt" @?= parseDim "6pt"
        sizeOf "8Q" @?= parseDim "8Q"
        sizeOf "1zw" @?= Just (Zw 1)
        mapM_ (\v -> codes (parseStyle (FileId 0) ("[notes]\nmark-size = \"" <> v <> "\"\n")) @?= ["G03006"]) ["0zw", "1.5zw", "abc", "0pt"]
        mapM_ (\v -> formatOf v @?= Just v) ["注{n}", "{n})", "{n}"]
        mapM_ (\v -> codes (parseStyle (FileId 0) ("[notes]\nmark-format = \"" <> v <> "\"\n")) @?= ["G03006"]) ["注", "{n}-{n}"],
      indentTests,
      listTests,
      characterFeatureTests,
      codeStyleTests,
      captionSidenoteTests,
      testCase "side of [sidenotes] takes only outside, the default (golem-project ADR 0009)" $ do
        let sn = "[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\n"
            sidenotesOf t = either (const Nothing) stSidenotes (parseStyle (FileId 0) t)
        sidenotesOf (sn <> "side = \"outside\"\n") @?= sidenotesOf sn
        assertBool "without side" (isJust (sidenotesOf sn))
        codes (parseStyle (FileId 0) (sn <> "side = \"inside\"\n")) @?= ["G03006"]
        msgs (parseStyle (FileId 0) (sn <> "side = \"inside\"\n")) @?= ["side に使えない値です: inside（outside のどれか） (sidenotes.side)"]
        codes (parseStyle (FileId 0) (sn <> "side = 1\n")) @?= ["G03006"],
      testCase "the sidenote font and size are the paragraph style sidenote (golem-driver ADR 0011)" $ do
        let retired = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
            hasIt ms = assertBool (show ms) (not (null ms) && all (\m -> "G03006" `T.isPrefixOf` m) ms && any ("[paragraph-styles.sidenote]" `T.isInfixOf`) ms)
        hasIt (retired (parseStyle (FileId 0) "[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\nsize = \"8pt\"\n"))
        hasIt (retired (parseStyle (FileId 0) "[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\nfont = \"note\"\n"))
        case parseStyle (FileId 0) "[fonts.note]\nlatin = \"n.otf\"\n\n[paragraph-styles.sidenote]\nfont = \"note\"\nsize = \"8pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (paraStyle s (Just "sidenote") >>= psFont) @?= Just "note"
            (paraStyle s (Just "sidenote") >>= psSize) @?= Just (Abs (8 * 65536))
        codes (parseStyle (FileId 0) "[paragraph-styles.sidenote]\nfont = \"nope\"\n") @?= ["G03008"],
      testCase "a caption style (golem-driver ADR 0010)" $ do
        case parseStyle (FileId 0) "[fonts.caption]\nlatin = \"c.otf\"\n\n[paragraph-styles.caption]\nfont = \"caption\"\nsize = \"8pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (paraStyle s (Just "caption") >>= psFont) @?= Just "caption"
            (paraStyle s (Just "caption") >>= psSize) @?= Just (Abs (8 * 65536))
        codes (parseStyle (FileId 0) "[figures]\ncaption = \"x\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[figures.caption]\nfont = \"body\"\n") @?= ["G03006"],
      testCase "[composition] kenten takes the ten shapes (golem-driver ADR 0019)" $ do
        let kentenOf = fmap (compKenten . stComposition) . parseStyle (FileId 0)
        kentenOf "" @?= Right "sesame"
        kentenOf "[composition]\nkenten = \"triangle\"\n" @?= Right "triangle"
        codes (parseStyle (FileId 0) "[composition]\nkenten = \"star\"\n") @?= ["G03006"]
        kentenShapeNames @?= ["sesame", "open-sesame", "dot", "open-dot", "circle", "open-circle", "double-circle", "open-double-circle", "triangle", "open-triangle"],
      testCase "explicit-hyphen-penalty (golem-layout ADR 0008)" $ do
        fmap (compExplicitHyphenPenalty . stComposition) (parseStyle (FileId 0) "") @?= Right 50
        fmap (compExplicitHyphenPenalty . stComposition) (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = 100\n") @?= Right 100
        fmap (compExplicitHyphenPenalty . stComposition) (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = -9999\n") @?= Right (-9999)
        codes (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = -10000\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[composition]\nexplicit-hyphen-penalty = 10001\n") @?= ["G03006"],
      testCase "[composition.ruby] (golem-layout ADR 0009)" $ do
        let rubyOf = fmap (compRuby . stComposition) . parseStyle (FileId 0)
        rubyOf "" @?= Right (RubyStyleDef "center" "1:2:1" "1:2:1" (Zw 0.5) "kana")
        rubyOf "[composition.ruby]\nmono-align = \"start\"\ngroup-align = \"0:1:0\"\nbase-spacing = \"center\"\noverhang = \"1zw\"\noverhang-onto = \"none\"\n"
          @?= Right (RubyStyleDef "start" "0:1:0" "center" (Zw 1) "none")
        rubyOf "[composition.ruby]\ngroup-align = \"center\"\n" @?= Right (RubyStyleDef "center" "center" "1:2:1" (Zw 0.5) "kana")
        codes (parseStyle (FileId 0) "[composition.ruby]\ngroup-align = \"justify\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[composition.ruby]\nmono-align = \"1:2:1\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[composition.ruby]\noverhang = \"-1zw\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[composition.ruby]\nposition = \"mono-center\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[composition]\nruby = { position = \"mono-center\", overhang = \"1zw\" }\n") @?= ["G03006"],
      testCase "[notes] numbering (golem-driver ADR 0018)" $ do
        fmap stNotesNumbering (parseStyle (FileId 0) "") @?= Right NumberPerChapter
        fmap stNotesNumbering (parseStyle (FileId 0) "[notes]\nplacement = \"page-foot\"\n") @?= Right NumberPerChapter
        fmap stNotesNumbering (parseStyle (FileId 0) "[notes]\nnumbering = \"file\"\n") @?= Right NumberPerFile
        fmap stNotesNumbering (parseStyle (FileId 0) "[notes]\nnumbering = \"chapter\"\n") @?= Right NumberPerChapter
        fmap stNotesNumbering (parseStyle (FileId 0) "[notes]\nnumbering = \"book\"\n") @?= Right NumberPerBook
        codes (parseStyle (FileId 0) "[notes]\nnumbering = \"page\"\n") @?= ["G03006"],
      testCase "the rule spec, read apart from its users (golem-driver ADR 0024)" $ do
        parseRuleSpec (FileId 0) "length = \"30mm\"\nweight = \"0.5pt\"\n" @?= Right (RuleSpec (parseDim "30mm") 32768 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True)
        -- whether length is required is for the user to decide
        parseRuleSpec (FileId 0) "weight = \"1pt\"\n" @?= Right (RuleSpec Nothing 65536 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True)
        parseRuleSpec (FileId 0) "" @?= Right (RuleSpec Nothing 19661 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True)
        parseRuleSpec (FileId 0) "space-before = \"0pt\"\nspace-after = \"1zw\"\n" @?= Right (RuleSpec Nothing 19661 (Just (Abs 0)) (Just (Zw 1)) Nothing RuleSolid (Zw 0) Nothing True)
        codes (parseRuleSpec (FileId 0) "weight = \"1zw\"\n") @?= ["G03006"]
        codes (parseRuleSpec (FileId 0) "weight = \"0pt\"\n") @?= ["G03006"]
        codes (parseRuleSpec (FileId 0) "space-before = \"-1pt\"\n") @?= ["G03006"]
        codes (parseRuleSpec (FileId 0) "length = \"0zw\"\n") @?= ["G03006"],
      testCase "[notes.rule] (golem-driver ADR 0024)" $ do
        let ruleOf = fmap stNotesRule . parseStyle (FileId 0)
        ruleOf "" @?= Right Nothing
        ruleOf "[notes]\nplacement = \"page-foot\"\n" @?= Right Nothing
        ruleOf "[notes.rule]\nlength = \"10zw\"\n" @?= Right (Just (RuleSpec (Just (Zw 10)) 19661 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True))
        ruleOf "[notes.rule]\nlength = \"30mm\"\nweight = \"0.5pt\"\n" @?= Right (Just (RuleSpec (parseDim "30mm") 32768 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True))
        ruleOf "[notes.rule]\nlength = \"10zw\"\nspace-before = \"1zw\"\nspace-after = \"0.5zw\"\n" @?= Right (Just (RuleSpec (Just (Zw 10)) 19661 (Just (Zw 1)) (Just (Zw 0.5)) Nothing RuleSolid (Zw 0) Nothing True))
        -- the side not written is 0
        ruleOf "[notes.rule]\nlength = \"10zw\"\nspace-after = \"5pt\"\n" @?= Right (Just (RuleSpec (Just (Zw 10)) 19661 (Just (Abs 0)) (Just (Abs (5 * 65536))) Nothing RuleSolid (Zw 0) Nothing True))
        -- a rule with chapter-end notes is not an error
        ruleOf "[notes]\nplacement = \"chapter-end\"\n\n[notes.rule]\nlength = \"10zw\"\n" @?= Right (Just (RuleSpec (Just (Zw 10)) 19661 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True))
        codes (parseStyle (FileId 0) "[notes.rule]\nweight = \"0.3pt\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"abc\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"0mm\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"10zw\"\nweight = \"1zw\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"10zw\"\nspace-before = \"-1pt\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"10zw\"\nspace-after = \"abc\"\n") @?= ["G03006"],
      testCase "the colour and the style of a rule (golem-driver ADR 0028)" $ do
        let rule = parseRuleSpec (FileId 0)
            pt x = round (x * 65536 :: Rational)
        fmap (\r -> (rsColor r, rsStyle r)) (rule "") @?= Right (Nothing, RuleSolid)
        fmap rsStyle (rule "style = \"dashed\"\nweight = \"0.5pt\"\n") @?= Right (RuleDashed (pt 1.5) (pt 1))
        fmap rsStyle (rule "style = \"dashed\"\nweight = \"0.5pt\"\ndash = \"3pt\"\ngap = \"1.5pt\"\n") @?= Right (RuleDashed (pt 3) (pt 1.5))
        fmap rsStyle (rule "style = \"dotted\"\nweight = \"1pt\"\n") @?= Right (RuleDotted (pt 2))
        fmap rsStyle (rule "style = \"japanese-dots\"\nweight = \"1pt\"\n") @?= Right (RuleJapaneseDots (pt 1))
        fmap rsStyle (rule "style = \"dotted\"\nweight = \"1pt\"\ngap = \"4pt\"\n") @?= Right (RuleDotted (pt 4))
        forM_
          [ ("thin-thin", [1, 1, 1]),
            ("thick-thick", [2, 1, 2]),
            ("thick-thin", [2, 1, 1]),
            ("thin-thick", [1, 1, 2]),
            ("thick-thin-thick", [2, 1, 1, 1, 2]),
            ("thin-thick-thin", [1, 1, 2, 1, 1]),
            ("triple", [1, 1, 1, 1, 1])
          ]
          $ \(name, ratios) -> fmap rsStyle (rule ("style = \"" <> name <> "\"\n")) @?= Right (RuleMulti ratios)
        fmap rsStyle (rule "style = \"wavy\"\n") @?= Right RuleWavy
        fmap rsColor (rule "color = \"accent\"\n") @?= Right (Just "accent")
        forM_
          [ "style = \"straight-hash\"\n",
            "style = \"double\"\n",
            "style = \"dashed\"\ndash = \"1zw\"\n",
            "style = \"dashed\"\ngap = \"0pt\"\n",
            "style = \"dashed\"\ndash = \"abc\"\n",
            "dash = \"3pt\"\n",
            "style = \"solid\"\ndash = \"3pt\"\n",
            "style = \"dotted\"\ndash = \"3pt\"\n",
            "style = \"thin-thin\"\ngap = \"1pt\"\n",
            "style = \"wavy\"\ngap = \"1pt\"\n",
            "color = 3\n"
          ]
          $ \src -> codes (rule src) @?= ["G03006"]
        let swatch = "[color.swatches]\naccent = { cmyk = [0, 100, 100, 0] }\n\n"
        fmap (fmap rsColor . stNotesRule) (parseStyle (FileId 0) (swatch <> "[notes.rule]\nlength = \"10zw\"\ncolor = \"accent\"\n")) @?= Right (Just (Just "accent"))
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"10zw\"\ncolor = \"accent\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[notes.rule]\nlength = \"10zw\"\nstyle = \"double\"\n") @?= ["G03006"],
      testCase "paragraph style rules (golem-driver ADR 0027)" $ do
        let rulesOf n src = fmap (\st -> paraRules st (Just n)) (parseStyle (FileId 0) src)
            plain w = RuleSpec Nothing w Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True
        rulesOf "section" "[paragraph-styles.section]\nrule-before = { weight = \"0.5pt\" }\n" @?= Right (Just (plain 32768), Nothing)
        rulesOf "lead" "[paragraph-styles.lead]\nrule-after = { length = \"10zw\", space-before = \"0.5zw\" }\n"
          @?= Right (Nothing, Just (plain 19661) {rsLength = Just (Zw 10), rsSpaceBefore = Just (Zw 0.5)})
        let parent = "[paragraph-styles.section]\nrule-before = { weight = \"0.5pt\", space-before = \"1zw\" }\n\n"
        fmap fst (rulesOf "sub" (parent <> "[paragraph-styles.sub]\nbased-on = \"section\"\n")) @?= Right (Just (plain 32768) {rsSpaceBefore = Just (Zw 1)})
        fmap fst (rulesOf "sub" (parent <> "[paragraph-styles.sub]\nbased-on = \"section\"\nrule-before = { weight = \"1pt\" }\n")) @?= Right (Just (plain 65536))
        fmap fst (rulesOf "sub" (parent <> "[paragraph-styles.sub]\nbased-on = \"section\"\nrule-before = false\n")) @?= Right Nothing
        forM_
          [ "[paragraph-styles.a]\nrule-before = true\n",
            "[paragraph-styles.a]\nrule-before = { weight = \"1zw\" }\n",
            "[paragraph-styles.a]\nrule-before = { colour = \"x\" }\n",
            "[paragraph-styles.caption]\nrule-before = { weight = \"1pt\" }\n",
            "[paragraph-styles.sidenote]\nrule-after = { weight = \"1pt\" }\n",
            "[paragraph-styles.code]\nrule-before = { weight = \"1pt\" }\n",
            "[paragraph-styles.a]\nrule-before = { length = \"10zw\", end-indent = \"1zw\" }\n",
            "[notes.rule]\nlength = \"10zw\"\nkeep-in-column = false\n",
            "[notes.rule]\nlength = \"10zw\"\nstart-indent = \"1zw\"\n",
            "[notes.rule]\nlength = \"10zw\"\nend-indent = \"1zw\"\n"
          ]
          $ \src -> codes (parseStyle (FileId 0) src) @?= ["G03006"]
        -- 40 characters a line: 30zw from the start and 10zw from the end leave nothing
        let grid = "[page]\nsize = \"A5\"\n\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 40\nlines = 30\nline-pitch = \"17pt\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n"
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.a]\nrule-before = { start-indent = \"30zw\", end-indent = \"10zw\" }\n")) @?= ["G03006"]
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.a]\nrule-before = { start-indent = \"29zw\", end-indent = \"10zw\" }\n")) @?= []
        rulesOf "a" "[paragraph-styles.a]\nrule-before = { start-indent = \"-2zw\", end-indent = \"-2zw\", keep-in-column = false }\n"
          @?= Right (Just (plain 19661) {rsStartIndent = Zw (-2), rsEndIndent = Just (Zw (-2)), rsKeepInColumn = False}, Nothing)
        -- the colour and the style of ADR 0028 on paragraph rules
        let swatch = "[color.swatches]\naccent = { cmyk = [0, 100, 100, 0] }\n\n"
        fmap (fmap rsColor . fst) (rulesOf "a" (swatch <> "[paragraph-styles.a]\nrule-before = { color = \"accent\", style = \"dotted\" }\n")) @?= Right (Just (Just "accent"))
        codes (parseStyle (FileId 0) "[paragraph-styles.a]\nrule-before = { color = \"accent\" }\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[headings.1]\nrule-after = { color = \"accent\" }\n") @?= ["G03013"],
      testCase "heading rules (golem-driver ADR 0027)" $ do
        let headingOf src = fmap (Map.lookup 2 . stHeadings) (parseStyle (FileId 0) src)
        fmap (fmap hsRuleAfter) (headingOf "[headings.2]\nrule-after = { space-before = \"0.25zw\" }\n")
          @?= Right (Just (Just (RuleSpec Nothing 19661 (Just (Zw 0.25)) Nothing Nothing RuleSolid (Zw 0) Nothing True)))
        fmap (fmap hsRuleBefore) (headingOf "[headings.2]\nrule-before = false\n") @?= Right (Just Nothing)
        codes (parseStyle (FileId 0) "[headings.2]\nrule-before = true\n") @?= ["G03006"],
      testCase "the spaces of a rule in mm (golem-driver ADR 0035)" $ do
        let mm r = Abs (round (r * 72 * 65536 / 25.4 :: Rational))
            spaces r = (rsSpaceBefore r, rsSpaceAfter r)
        fmap (fmap spaces . fst . (`paraRules` Just "sec")) (parseStyle (FileId 0) "[paragraph-styles.sec]\nrule-before = { space-before = \"3mm\", space-after = \"1.5mm\" }\n")
          @?= Right (Just (Just (mm 3), Just (mm 1.5)))
        fmap (fmap (fmap rsSpaceBefore . hsRuleAfter) . Map.lookup 2 . stHeadings) (parseStyle (FileId 0) "[headings.2]\nrule-after = { space-before = \"2mm\" }\n")
          @?= Right (Just (Just (Just (mm 2)))),
      testCase "[toc] leader (golem-driver ADR 0009)" $ do
        fmap stTocLeader (parseStyle (FileId 0) "[toc]\nleader = \"none\"\n") @?= Right "none"
        fmap stTocLeader (parseStyle (FileId 0) "") @?= Right "dots"
        codes (parseStyle (FileId 0) "[toc]\nleader = \"dash\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[toc]\nfont = \"body\"\n") @?= ["G03006"],
      testCase "a heading font must name a font role (golem-driver ADR 0003)" $ do
        codes (parseStyle (FileId 0) "[headings.1]\nfont = \"nope\"\n") @?= ["G03008"]
        codes (parseStyle (FileId 0) "[fonts.heading]\nlatin = \"h.otf\"\n\n[headings.1]\nfont = \"heading\"\n") @?= [],
      testCase "a style loads although the files it names do not exist (ADR 0004)" $
        void (loadStyle (FileId 0) (Just "[fonts.body]\nja = \"fonts/none.otf\"\n\n[color]\nintent = \"icc/none.icc\"\n")) @?= Right (),
      testCase "a style's font files are listed by role name, Japanese before Latin (ADR 0004)" $
        fmap fontFiles (loadStyle (FileId 0) (Just "[fonts.mono]\nlatin = \"m.otf\"\n\n[fonts.body]\nja = \"b.otf\"\nlatin = \"l.otf\"\n"))
          @?= Right [("body", "b.otf"), ("body", "l.otf"), ("mono", "m.otf")],
      testCase "character style fonts name font roles (golem-driver ADR 0004)" $
        codes (parseStyle (FileId 0) "[character-styles.term]\nfont = \"nope\"\n") @?= ["G03008"],
      styleTests,
      runningHeadTests,
      localStyleTests,
      akiTests,
      regexStyleTests,
      testCase "[page] bleed (golem-pdf ADR 0004)" $ do
        fmap (fmap pageBleed . stPage) (parseStyle (FileId 0) "[page]\nsize = \"A6\"\nbleed = \"3mm\"\n") @?= Right (Just 557314)
        fmap (fmap pageBleed . stPage) (parseStyle (FileId 0) "[page]\nsize = \"A6\"\n") @?= Right (Just 0)
        codes (parseStyle (FileId 0) "[page]\nsize = \"A6\"\nbleed = \"1zw\"\n") @?= ["G03006"],
      testGroup "page size by dimensions (ADR 0005)" pageSizeTests,
      silenceTests,
      indexStyleTests,
      hiddenFolioTests,
      findCycleTests,
      testCase "marks is not a key of the manifest (golem-pdf ADR 0004)" $
        withProject [("manifest.toml", manifest ["\"a.gm\""] <> "\n[targets.pdf]\nmarks = \"japanese\"\n"), ("a.gm", "")] $ \root ->
          loadProject root >>= (@?= ["G03001"]) . codes
    ]

-- | The paths findCycles returns are non-empty (docs/adr ADR 0027).
findCycleTests :: TestTree
findCycleTests =
  testGroup
    "findCycles (docs/adr ADR 0027)"
    [ testCase "a self-import is one path of length 1" $
        paths [(1, [1])] @?= [[1]],
      testCase "a -> b -> a is one path of length 2" $
        paths [(1, [2]), (2, [1])] @?= [[1, 2]],
      testCase "a -> b -> c -> a is one path of length 3" $
        paths [(1, [2]), (2, [3]), (3, [1])] @?= [[1, 2, 3]],
      testCase "a graph without cycles has none" $
        paths [(1, [2, 3]), (2, [3]), (3, [])] @?= [],
      testCase "the files before a cycle are not in its path" $
        paths [(1, [2]), (2, [3]), (3, [2])] @?= [[2, 3]],
      testCase "each import site along a path is the one that leaves its file" $
        map (map (\(FileId f, s) -> (f, isPath s)) . NE.toList) (findCycles (graph [(1, [2]), (2, [3]), (3, [2])])) @?= [[(2, "3"), (3, "2")]],
      testCase "two cycles through one file are two paths, in the order of the edges" $
        paths [(1, [3, 2]), (2, [1]), (3, [1])] @?= [[1, 3], [1, 2]],
      testCase "topoOrder: a file after the files it imports, ties by file id; a cycle at the end" $ do
        order [(1, [3]), (2, []), (3, [])] @?= [2, 3, 1]
        order [(1, []), (2, [1]), (3, [1, 2])] @?= [1, 2, 3]
        order [(3, []), (2, [3]), (1, [2])] @?= [3, 2, 1]
        order [(1, [2]), (2, [1]), (3, [])] @?= [3, 1, 2]
    ]
  where
    site t = ImportSite (T.pack (show t)) "x" (mkSpan (FileId 0) 0 0)
    graph es = ImportGraph (Map.fromList [(FileId f, [(FileId t, site t) | t <- ts]) | (f, ts) <- es])
    order :: [(Int, [Int])] -> [Int]
    order = map (\(FileId f) -> f) . topoOrder . graph
    paths :: [(Int, [Int])] -> [[Int]]
    paths = map (map (\(FileId f, _) -> f) . NE.toList) . findCycles . graph

-- | [hidden-folio] (golem-driver ADR 0021).
hiddenFolioTests :: TestTree
hiddenFolioTests =
  testGroup
    "[hidden-folio] (golem-driver ADR 0021)"
    [ testCase "the defaults without [hidden-folio]" $
        fmap stHiddenFolio (parseStyle (FileId 0) "") @?= Right (HiddenFolio True HiddenUnnumbered (Abs (6 * 65536)) (Abs 278657) False),
      testCase "the four keys are read" $
        fmap stHiddenFolio (parseStyle (FileId 0) "[hidden-folio]\nenabled = false\npages = \"all\"\nsize = \"8Q\"\ngutter = \"2mm\"\n")
          @?= Right (HiddenFolio False HiddenAll (Abs 371543) (Abs 371543) True),
      testCase "zw, a size or gutter of 0 or less, an unknown pages and an unknown key are G03006" $
        mapM_
          (\body -> codes (parseStyle (FileId 0) ("[hidden-folio]\n" <> body <> "\n")) @?= ["G03006"])
          ["size = \"1zw\"", "gutter = \"-1mm\"", "size = \"0pt\"", "pages = \"blank\"", "font = \"body\"", "gutter = \"1zw\"", "size = \"abc\""],
      testCase "a gutter less than half the size is G03029 at gutter, with the values to fix (golem-driver ADR 0041)" $ do
        let src = "[hidden-folio]\nsize = \"6pt\"\ngutter = \"2pt\"\n"
        case parseStyle (FileId 0) src of
          Left [d] -> do
            diagCode d @?= DiagnosticCode "G03029"
            diagMessage d @?= "[hidden-folio] の gutter（0.71mm）が size（2.12mm）の半分（1.06mm）より小さいため、隠しノンブルの数字が仕上がりの線を越えます（gutter を 1.06mm 以上にするか、size を 1.41mm 以下にします）"
            spanStart (diagSpan d) @?= T.length "[hidden-folio]\nsize = \"6pt\"\ngutter = "
            map fst (diagFacts d) @?= ["gutter", "size", "min-gutter", "max-size"]
          other -> assertFailure (show (void other)),
      testCase "a size of 8mm with the default gutter is G03029 at size (golem-driver ADR 0041)" $
        case parseStyle (FileId 0) "[hidden-folio]\nsize = \"8mm\"\n" of
          Left [d] -> (diagCode d, spanStart (diagSpan d)) @?= (DiagnosticCode "G03029", T.length "[hidden-folio]\nsize = ")
          other -> assertFailure (show (void other)),
      testCase "the gutter and the size the message names pass, 0.01mm past them do not (golem-driver ADR 0041)" $
        forM_ [("6pt", "2pt"), ("8mm", "1.5mm"), ("13Q", "1mm"), ("7pt", "0.5mm")] $ \(size, gutter) -> do
          let style s g = "[hidden-folio]\nsize = \"" <> s <> "\"\ngutter = \"" <> g <> "\"\n"
          (minGutter, maxSize) <- case parseStyle (FileId 0) (style size gutter) of
            Left [d] | diagCode d == DiagnosticCode "G03029" -> pure (bounds (diagMessage d))
            other -> assertFailure (show (void other))
          codes (parseStyle (FileId 0) (style size (mmText minGutter))) @?= []
          codes (parseStyle (FileId 0) (style (mmText maxSize) gutter)) @?= []
          codes (parseStyle (FileId 0) (style size (mmText (minGutter - 1 % 100)))) @?= ["G03029"]
          codes (parseStyle (FileId 0) (style (mmText (maxSize + 1 % 100)) gutter)) @?= ["G03029"],
      testCase "a gutter of exactly half the size is no error (golem-driver ADR 0041)" $
        codes (parseStyle (FileId 0) "[hidden-folio]\nsize = \"6pt\"\ngutter = \"3pt\"\n") @?= [],
      testCase "G03029 also when the hidden folio is not enabled (golem-driver ADR 0041)" $
        codes (parseStyle (FileId 0) "[hidden-folio]\nenabled = false\nsize = \"6pt\"\ngutter = \"2pt\"\n") @?= ["G03029"],
      testCase "a gutter in zw is still G03006, not G03029 (golem-driver ADR 0041)" $
        codes (parseStyle (FileId 0) "[hidden-folio]\nsize = \"6pt\"\ngutter = \"1zw\"\n") @?= ["G03006"],
      testCase "G03029 comes with the other checks; a schema error stops the reading (golem-driver ADR 0041)" $ do
        let hf = "[hidden-folio]\nsize = \"6pt\"\ngutter = \"2pt\"\n"
            grid = "[page]\nsize = \"A5\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 40\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"14mm\", gutter = \"14mm\" }\n"
        Set.fromList (codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.body]\nsize = \"30Q\"\n" <> hf))) @?= Set.fromList ["G03011", "G03029"]
        codes (parseStyle (FileId 0) (hf <> "font = \"body\"\n")) @?= ["G03006"]
    ]
  where
    -- the gutter and the size in mm the message of G03029 names
    bounds m = (mmIn "gutter を " m, mmIn "size を " m)
    mmIn key m = case T.breakOn "mm" (T.drop (T.length key) (snd (T.breakOn key m))) of
      (n, _) -> case T.splitOn "." n of
        [i, f] -> fromInteger (read (T.unpack i)) + read (T.unpack f) % 100
        _ -> error (T.unpack m)
    -- a length in mm to two decimals
    mmText :: Rational -> Text
    mmText r =
      let c = round (r * 100) :: Integer
       in T.pack (show (c `div` 100) <> "." <> (if c `mod` 100 < 10 then "0" else "") <> show (c `mod` 100) <> "mm")

-- | [index] (docs/adr ADR 0025).
indexStyleTests :: TestTree
indexStyleTests =
  testGroup
    "[index] (docs/adr ADR 0025)"
    [ testCase "columns and column-gap are read" $ do
        let src = "[index]\ncolumns = 2\ncolumn-gap = \"2zw\"\n"
        fmap stIndex (parseStyle (FileId 0) src) @?= Right (Just (IndexStyle (Just 2) (Just (Zw 2)) (T.length "[index]\ncolumns = ")))
        fmap (fmap ixColumnGap . stIndex) (parseStyle (FileId 0) "[index]\ncolumns = 2\n") @?= Right (Just Nothing)
        fmap stIndex (parseStyle (FileId 0) "") @?= Right Nothing,
      testCase "a columns that is not an integer of 1 or more is G03025 at the value" $
        mapM_
          ( \v -> do
              let src = "[index]\ncolumns = " <> v <> "\n"
                  r = parseStyle (FileId 0) src
              codes r @?= ["G03025"]
              either (map (spanStart . diagSpan)) (const []) r @?= [T.length "[index]\ncolumns = "]
          )
          ["0", "-1", "1.5", "\"2\""],
      testCase "a column-gap that is negative or not a dimension is G03025" $ do
        codes (parseStyle (FileId 0) "[index]\ncolumns = 2\ncolumn-gap = \"-1zw\"\n") @?= ["G03025"]
        codes (parseStyle (FileId 0) "[index]\ncolumns = 2\ncolumn-gap = \"abc\"\n") @?= ["G03025"],
      testCase "an unknown key of [index] is G03006" $
        codes (parseStyle (FileId 0) "[index]\ncolums = 2\n") @?= ["G03006"]
    ]

-- | Character and paragraph styles (docs/adr ADR 0005).
styleTests :: TestTree
styleTests =
  testGroup
    "character and paragraph styles (docs/adr ADR 0005)"
    [ testCase "the built-in styles" $ do
        s <- parsed ""
        (charStyle s "strong" >>= csSyntheticBold) @?= Just True
        (charStyle s "italic" >>= csSyntheticItalic) @?= Just True
        (charStyle s "bold" >>= csSyntheticBold) @?= Just True
        charStyle s "nope" @?= Nothing
        (paraStyle s (Just "verse") >>= psLineBreaks) @?= Just KeepLines
        (paraStyle s (Just "verse") >>= psSpaceBetween) @?= Just 1
        (paraStyle s Nothing >>= psLineBreaks) @?= Just JoinLines
        (paraStyle s Nothing >>= psSpaceBetween) @?= Just 0
        paraStyle s (Just "nope") @?= Nothing
        noBase (paraStyle s (Just "caption")) @?= noBase (paraStyle s Nothing)
        noBase (paraStyle s (Just "sidenote")) @?= noBase (paraStyle s Nothing)
        Map.keys (stParaStyles s) @?= ["body", "caption", "code", "sidenote", "verse"]
        Map.keys (stCharStyles s) @?= ["bold", "code", "italic", "strong", "url"],
      testCase "a user definition overrides the keys it writes" $ do
        s <- parsed "[paragraph-styles.caption]\nsize = \"0.8zw\"\n"
        (paraStyle s (Just "caption") >>= psSize) @?= Just (Zw (4 / 5))
        (paraStyle s (Just "caption") >>= psLineBreaks) @?= Just JoinLines
        t <- parsed "[character-styles.strong]\nbased-on = \"italic\"\n"
        (charStyle t "strong" >>= csSyntheticItalic) @?= Just True
        (charStyle t "strong" >>= csSyntheticBold) @?= Nothing
        u <- parsed "[fonts.gothic]\nja = \"g.otf\"\n\n[character-styles.bold]\nfont = \"gothic\"\n"
        (charStyle u "bold" >>= csFont) @?= Just "gothic"
        (charStyle u "bold" >>= csSyntheticBold) @?= Just True
        (charStyle u "strong" >>= csFont) @?= Just "gothic",
      testCase "a new paragraph style is based on body" $ do
        s <- parsed "[fonts.heading]\nlatin = \"h.otf\"\n\n[paragraph-styles.quote]\nfont = \"heading\"\nspace-between = 2\n"
        (paraStyle s (Just "quote") >>= psFont) @?= Just "heading"
        (paraStyle s (Just "quote") >>= psSpaceBetween) @?= Just 2
        (paraStyle s (Just "quote") >>= psLineBreaks) @?= Just JoinLines
        t <- parsed "[character-styles.term]\ncolor = \"accent\"\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
        (charStyle t "term" >>= csColor) @?= Just "accent",
      testCase "references between styles (G03013)" $ do
        codes (parseStyle (FileId 0) "[character-styles.a]\nbased-on = \"nope\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[character-styles.a]\nbased-on = \"b\"\n\n[character-styles.b]\nbased-on = \"a\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[paragraph-styles.a]\nbased-on = \"a\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nbased-on = \"verse\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[character-styles.term]\ncolor = \"accent\"\n") @?= ["G03013"],
      testCase "a paragraph style larger than the grid (G03011)" $ do
        let grid = "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n"
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.big]\nsize = \"2zw\"\n")) @?= ["G03011"]
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.small]\nsize = \"0.9zw\"\n")) @?= []
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.big]\nsize = \"14Q\"\n")) @?= ["G03011"],
      testCase "a paragraph style font must name a font role (G03008)" $
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nfont = \"nope\"\n") @?= ["G03008"],
      testCase "names and values (G03006)" $ do
        codes (parseStyle (FileId 0) "[character-styles.Term]\nsize = \"1zw\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nline-breaks = \"x\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nspace-between = -1\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nleading = 1\n") @?= ["G03006"],
      testCase "retired keys name what replaces them" $ do
        messages (parseStyle (FileId 0) "[emphasis]\nstrong = \"bold\"\n") `hasAll` ["G03006", "character-styles"]
        messages (parseStyle (FileId 0) "[verse]\nstanza-gap = 1\n") `hasAll` ["G03006", "paragraph-styles.verse"]
    ]
  where
    parsed src = either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) src)
    noBase = fmap (\d -> d {psBasedOn = Nothing})
    messages = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
    hasAll ms needles = assertBool (show ms) (not (null ms) && all (\n -> any (n `T.isInfixOf`) ms) needles)

-- | [lists] (golem-driver ADR 0013).
listTests :: TestTree
listTests =
  testGroup
    "[lists] (golem-driver ADR 0013)"
    [ testCase "bullets, numbers and gap are read" $
        case parseStyle (FileId 0) "[lists]\nbullets = [\"・\", \"◦\"]\nnumbers = [\"{n}.\", \"({a})\"]\ngap = \"0.5zw\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            lsBullets (stLists s) @?= "・" :| ["◦"]
            lsNumbers (stLists s) @?= Just (NumberFormat "" NsBook "." :| [NumberFormat "(" NsLowerAlpha ")"])
            lsGap (stLists s) @?= Just (Zw (1 / 2)),
      testCase "without [lists]: the bullet ・, no numbers and no gap" $
        case parseStyle (FileId 0) "" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            lsBullets (stLists s) @?= "・" :| []
            lsNumbers (stLists s) @?= Nothing
            lsGap (stLists s) @?= Nothing,
      testCase "errors of [lists] are G03022 and name the key" $ do
        let g03022 src key = do
              let ms = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const []) (parseStyle (FileId 0) src)
              assertBool (show ms) (not (null ms) && all ("G03022 [lists] の " `T.isPrefixOf`) ms && any (("[lists] の " <> key <> " が正しくありません") `T.isInfixOf`) ms)
        g03022 "[lists]\nbullets = []\n" "bullets"
        g03022 "[lists]\nbullets = [\"・\", \"\"]\n" "bullets"
        g03022 "[lists]\nnumbers = []\n" "numbers"
        g03022 "[lists]\nnumbers = [\"{n}\", \"x\"]\n" "numbers"
        g03022 "[lists]\nnumbers = [\"{n}{n}\"]\n" "numbers"
        g03022 "[lists]\nnumbers = [\"{x}\"]\n" "numbers"
        g03022 "[lists]\nnumbers = [\"\"]\n" "numbers"
        g03022 "[lists]\ngap = \"-1zw\"\n" "gap"
        g03022 "[lists]\ngap = \"wide\"\n" "gap",
      testCase "literal braces in a number format" $
        case parseStyle (FileId 0) "[lists]\nnumbers = [\"{{{n}}}\"]\n" of
          Left ds -> assertFailure (show ds)
          Right s -> lsNumbers (stLists s) @?= Just (NumberFormat "{" NsBook "}" :| [])
    ]

-- | Paragraph indents (docs/adr ADR 0006).
indentTests :: TestTree
indentTests =
  testGroup
    "paragraph indents (docs/adr ADR 0006)"
    [ testCase "the defaults of body and verse" $ do
        s <- parsed ""
        indents (paraStyle s Nothing) @?= Just (Zw 0, Zw 0)
        indents (paraStyle s (Just "verse")) @?= Just (Zw 2, Zw (-2)),
      testCase "a key not written is inherited" $ do
        s <- parsed "[paragraph-styles.quote]\nindent = \"2zw\"\n"
        indents (paraStyle s (Just "quote")) @?= Just (Zw 2, Zw 0),
      testCase "signed dimensions" $ do
        parseSignedDim "-1.5zw" @?= Just (Zw (-(3 / 2)))
        fmap (\case Abs x -> x < 0; Zw _ -> False) (parseSignedDim "-3mm") @?= Just True
        parseSignedDim "2zw" @?= Just (Zw 2)
        parseSignedDim "--1zw" @?= Nothing
        parseSignedDim "-zw" @?= Nothing,
      testCase "a first line outside the type area (G03012)" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"-1zw\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"1zw\"\nfirst-line-indent = \"-2zw\"\n") @?= ["G03012"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"2zw\"\nfirst-line-indent = \"-2zw\"\n") @?= []
        let grid = "[page]\nsize = \"B6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n\n"
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.quote]\nindent = \"1mm\"\nfirst-line-indent = \"-1zw\"\n")) @?= ["G03012"]
        codes (parseStyle (FileId 0) (grid <> "[paragraph-styles.quote]\nindent = \"4mm\"\nfirst-line-indent = \"-1zw\"\n")) @?= [],
      testCase "[verse] is retired" $
        messages (parseStyle (FileId 0) "[verse]\nindent = \"0zw\"\n") `hasAll` ["G03006", "[paragraph-styles.verse]"]
    ]
  where
    indents = fmap (\d -> (fromMaybe (Zw 99) (psIndent d), fromMaybe (Zw 99) (psFirstLineIndent d)))
    parsed src = either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) src)
    messages = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
    hasAll ms needles = assertBool (show ms) (not (null ms) && all (\n -> any (n `T.isInfixOf`) ms) needles)

specStyle :: Text
specStyle =
  T.unlines
    [ "[page]",
      "size = \"B6\"",
      "binding = \"right\"",
      "writing-mode = \"vertical\"",
      "",
      "[page.grid]",
      "font-size = \"13Q\"",
      "characters = 42",
      "lines = 16",
      "line-pitch = \"22H\"",
      "columns = 1",
      "column-gap = \"2zw\"",
      "position = { top = \"18mm\", gutter = \"20mm\" }",
      "",
      "[fonts.body]",
      "ja = \"fonts/a.otf\"",
      "latin = \"fonts/b.otf\"",
      "features = [\"palt\"]",
      "",
      "[fonts.heading]",
      "ja = \"fonts/c.otf\"",
      "",
      "[character-styles.term]",
      "font = \"heading\"",
      "color = \"accent\"",
      "",
      "[paragraph-styles.quote]",
      "font = \"heading\"",
      "size = \"0.9zw\"",
      "",
      "[headings.1]",
      "font = \"heading\"",
      "size = \"20Q\"",
      "number = \"第{n:kanji}章\"",
      "page-break = \"recto\"",
      "",
      "[headings.2]",
      "number = \"{1}.{n}\"",
      "",
      "[composition]",
      "kinsoku = \"strict\"",
      "hanging-punctuation = true",
      "kenten = \"sesame\"",
      "tolerance = 200",
      "protrusion = true",
      "expansion = { limit = 20, step = 5 }",
      "",
      "[composition.ruby]",
      "mono-align = \"center\"",
      "group-align = \"1:2:1\"",
      "base-spacing = \"1:2:1\"",
      "overhang = \"0.5zw\"",
      "overhang-onto = \"kana\"",
      "",
      "[numbers]",
      "vertical = \"kanji\"",
      "",
      "[notes]",
      "placement = \"page-foot\"",
      "",
      "[sidenotes]",
      "side = \"outside\"",
      "width = \"14zw\"",
      "gap = \"2zw\"",
      "marker = \"number\"",
      "",
      "[paragraph-styles.sidenote]",
      "font = \"body\"",
      "size = \"11Q\"",
      "",
      "[figures]",
      "number = \"図{chapter}-{n}\"",
      "",
      "[color]",
      "intent = \"icc/JapanColor2001Coated.icc\"",
      "",
      "[color.swatches]",
      "accent = { cmyk = [0, 80, 100, 0] }",
      "",
      "[masters.body]",
      "running-head = { position = \"top-outside\", content = \"heading.1.short\" }",
      "folio = { position = \"bottom-outside\", format = \"{n}\" }"
    ]

{- | Kerning, tracking, proportional metrics and baseline shift (docs/adr/0020).
| The paragraph style code and the character style code (golem-driver ADR 0017).
-}

{- | caption and sidenote take from body only the keys their layout uses
(golem-driver ADR 0043).
-}
captionSidenoteTests :: TestTree
captionSidenoteTests =
  testGroup
    "caption and sidenote (golem-driver ADR 0043)"
    [ testCase "an indent of caption and a first-line-indent of sidenote are G03006, by name and key" $ do
        let r1 = parseStyle (FileId 0) "[paragraph-styles.caption]\nindent = \"1zw\"\n"
        codes r1 @?= ["G03006"]
        assertBool (show (messages r1)) (any (\m -> "caption" `T.isInfixOf` m && "indent" `T.isInfixOf` m) (messages r1))
        let r2 = parseStyle (FileId 0) "[paragraph-styles.sidenote]\nfirst-line-indent = \"1zw\"\n"
        codes r2 @?= ["G03006"]
        assertBool (show (messages r2)) (any (\m -> "sidenote" `T.isInfixOf` m && "first-line-indent" `T.isInfixOf` m) (messages r2)),
      testCase "a non-zero indent or first-line-indent of caption and sidenote is G03006" $
        forM_ ["caption", "sidenote"] $ \n ->
          forM_ ["indent = \"1zw\"", "indent = \"1mm\"", "first-line-indent = \"-1zw\""] $ \kv ->
            codes (parseStyle (FileId 0) ("[paragraph-styles." <> n <> "]\n" <> kv <> "\n")) @?= ["G03006"],
      testCase "a zero indent of caption and sidenote is no error but the notice G03100, at the value" $
        forM_ ["caption", "sidenote"] $ \n ->
          forM_ [("indent", "0zw"), ("first-line-indent", "0mm"), ("first-line-indent", "-0pt")] $ \(k, v) -> do
            let src = "[paragraph-styles." <> n <> "]\n" <> k <> " = \"" <> v <> "\"\n"
            codes (parseStyle (FileId 0) src) @?= []
            [(diagCode d, diagSeverity d, diagMessage d, spanStart (diagSpan d)) | d <- styleNotices (FileId 0) src]
              @?= [(DiagnosticCode "G03100", Notice, "キャプションと傍注は字下げを掛けないので、" <> n <> "." <> k <> " = \"" <> v <> "\" は効果がありません", BS.length (TE.encodeUtf8 (fst (T.breakOn "\"" src))))],
      testCase "no G03100 for a non-zero indent, for body, or without the keys" $ do
        styleNotices (FileId 0) "[paragraph-styles.caption]\nindent = \"1zw\"\n" @?= []
        styleNotices (FileId 0) "[paragraph-styles.body]\nindent = \"0zw\"\n" @?= []
        styleNotices (FileId 0) "[paragraph-styles.caption]\nsize = \"9pt\"\n" @?= []
        styleNotices (FileId 0) "not toml = = \n" @?= [],
      testCase "the keys caption and sidenote use are not errors" $
        forM_ ["caption", "sidenote"] $ \n ->
          forM_ ["size = \"9pt\"", "based-on = \"body\"", "line-breaks = \"keep\"", "space-between = 1", "aki-set = \"gyomatsu-yakumono-zenkaku\"", "kerning = \"none\"", "tracking = 10", "proportional-metrics = true", "baseline-shift = \"1pt\"", "regex-styles = []"] $ \kv ->
            codes (parseStyle (FileId 0) ("[paragraph-styles." <> n <> "]\n" <> kv <> "\n")) @?= [],
      testCase "font and size of caption are not errors" $
        codes (parseStyle (FileId 0) "[fonts.cap]\nja = \"c.otf\"\n\n[paragraph-styles.caption]\nfont = \"cap\"\nsize = \"9pt\"\n") @?= [],
      testCase "caption and sidenote do not take the indents of body" $ do
        s <- styleOf "[paragraph-styles.body]\nindent = \"2zw\"\nfirst-line-indent = \"1zw\"\n"
        forM_ ["caption", "sidenote"] $ \n -> do
          (paraStyle s (Just n) >>= psIndent) @?= Just (Zw 0)
          (paraStyle s (Just n) >>= psFirstLineIndent) @?= Just (Zw 0),
      testCase "@style-def paragraph caption: a non-zero indent is G03006, a zero one and size are not" $ do
        base <- styleOf ""
        let checks kvs = case localStyleDef ParagraphKind kvs of
              Right (Right d) -> pure [c | (c, _, _) <- checkLocalStyles base noLocalStyles {lsParaStyles = Map.fromList [("caption", d)]}]
              other -> assertFailure (show other) >> pure []
        checks [("indent", LocalWord "1zw")] >>= (@?= ["G03006"])
        checks [("indent", LocalWord "0zw")] >>= (@?= [])
        checks [("size", LocalWord "9pt")] >>= (@?= [])
    ]
  where
    styleOf t = either (\ds -> assertFailure (show ds) >> pure defaultStyle) pure (parseStyle (FileId 0) t)
    messages = either (map diagMessage) (const [])

codeStyleTests :: TestTree
codeStyleTests =
  testGroup
    "code (golem-driver ADR 0017)"
    [ testCase "[paragraph-styles.code] reads font, size, background and padding" $ do
        s <- styleOf "[fonts.mono]\nlatin = \"m.otf\"\n\n[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[paragraph-styles.code]\nfont = \"mono\"\nsize = \"11Q\"\nbackground = \"code-bg\"\npadding = \"1zw\"\n"
        let d = paraStyle s (Just "code")
        (d >>= psFont) @?= Just "mono"
        (d >>= psSize) @?= parseDim "11Q"
        (d >>= psBackground) @?= Just "code-bg"
        (d >>= psPadding) @?= Just (Zw 1),
      testCase "the defaults of code: font code, padding 0.5zw, no background" $ do
        s <- styleOf ""
        let d = paraStyle s (Just "code")
        (d >>= psFont) @?= Just "code"
        (d >>= psPadding) @?= Just (Zw 0.5)
        (d >>= psBackground) @?= Nothing
        (charStyle s "code" >>= csFont) @?= Just "code",
      testCase "code without [fonts.code] is not G03008; another role that is missing is" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.code]\nsize = \"11Q\"\n") @?= []
        codes (parseStyle (FileId 0) "[paragraph-styles.code]\nfont = \"mono\"\n") @?= ["G03008"]
        codes (parseStyle (FileId 0) "[character-styles.code]\nfont = \"mono\"\n") @?= ["G03008"],
      testCase "code takes only font, size, background and padding (G03006)" $
        forM_ ["based-on = \"body\"", "indent = \"1zw\"", "line-breaks = \"keep\"", "regex-styles = []"] $ \kv -> do
          let r = parseStyle (FileId 0) ("[paragraph-styles.code]\n" <> kv <> "\n")
          codes r @?= ["G03006"]
          assertBool (show (messages r)) (any ("font、size、background、padding" `T.isInfixOf`) (messages r)),
      testCase "background and padding only in code (G03006)" $ do
        let r1 = parseStyle (FileId 0) "[color.swatches]\nbg = { cmyk = [0, 0, 0, 8] }\n\n[paragraph-styles.quote]\nbackground = \"bg\"\n"
        codes r1 @?= ["G03006"]
        assertBool (show (messages r1)) (any ("code" `T.isInfixOf`) (messages r1))
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\npadding = \"1zw\"\n") @?= ["G03006"],
      testCase "based-on = \"code\" is G03013" $
        codes (parseStyle (FileId 0) "[paragraph-styles.x]\nbased-on = \"code\"\n") @?= ["G03013"],
      testCase "a missing swatch is G03013; a padding that is negative or not a dimension G03006" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.code]\nbackground = \"nope\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[paragraph-styles.code]\npadding = \"-1zw\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.code]\npadding = \"abc\"\n") @?= ["G03006"],
      testCase "a size larger than the grid is G03011" $
        codes (parseStyle (FileId 0) "[page]\nsize = \"A5\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 30\nlines = 20\nline-pitch = \"22H\"\nposition = { top = \"20mm\", gutter = \"20mm\" }\n\n[paragraph-styles.code]\nsize = \"14Q\"\n") @?= ["G03011"],
      testCase "@style-def paragraph code: the four keys only" $ do
        base <- styleOf ""
        case localStyleDef ParagraphKind [("size", LocalWord "10Q")] of
          Right (Right d) -> do
            [c | (c, _, _) <- checkLocalStyles base noLocalStyles {lsParaStyles = Map.fromList [("code", d)]}] @?= []
            (paraStyle (withLocalStyles base noLocalStyles {lsParaStyles = Map.fromList [("code", d)]}) (Just "code") >>= psSize) @?= parseDim "10Q"
          other -> assertFailure (show other)
        case localStyleDef ParagraphKind [("indent", LocalWord "1zw")] of
          Right (Right d) -> [c | (c, _, _) <- checkLocalStyles base noLocalStyles {lsParaStyles = Map.fromList [("code", d)]}] @?= ["G03006"]
          other -> assertFailure (show other),
      testCase "a user's [character-styles.code] keeps the built-in font" $ do
        s <- styleOf "[color.swatches]\nx = { cmyk = [90, 50, 0, 20] }\n\n[character-styles.code]\ncolor = \"x\"\n"
        (charStyle s "code" >>= csFont) @?= Just "code"
        (charStyle s "code" >>= csColor) @?= Just "x",
      testCase "a character style based on code is a code style" $ do
        s <- styleOf "[character-styles.path]\nbased-on = \"code\"\n"
        isCodeCharStyle s "path" @?= True
        isCodeCharStyle s "code" @?= True
        isCodeCharStyle s "strong" @?= False,
      -- the background and the padding of inline code (golem-driver ADR 0029)
      testCase "[character-styles.code] background and the default padding 0.25zw" $ do
        s <- styleOf "[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[character-styles.code]\nbackground = \"code-bg\"\n"
        (charStyle s "code" >>= csBackground) @?= Just (Just "code-bg")
        charStyleBackground s "code" @?= Just "code-bg"
        (charStyle s "code" >>= csPadding) @?= Just (Zw 0.25),
      testCase "the background of character style code defaults to that of paragraph style code" $ do
        s <- styleOf "[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[paragraph-styles.code]\nbackground = \"code-bg\"\n"
        charStyleBackground s "code" @?= Just "code-bg"
        s' <- styleOf ""
        charStyleBackground s' "code" @?= Nothing,
      testCase "background = false: no background; true is G03006" $ do
        s <- styleOf "[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n\n[paragraph-styles.code]\nbackground = \"code-bg\"\n\n[character-styles.code]\nbackground = false\n"
        charStyleBackground s "code" @?= Nothing
        codes (parseStyle (FileId 0) "[character-styles.code]\nbackground = true\n") @?= ["G03006"],
      testCase "a padding without a background is no diagnostic" $ do
        s <- styleOf "[character-styles.code]\npadding = \"0.5zw\"\n"
        (charStyle s "code" >>= csPadding) @?= Just (Zw 0.5),
      testCase "a style based on code inherits background and padding and may override them" $ do
        s <- styleOf "[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\nother = { cmyk = [0, 0, 0, 20] }\n\n[character-styles.code]\nbackground = \"code-bg\"\n\n[character-styles.path]\nbased-on = \"code\"\n\n[character-styles.file]\nbased-on = \"code\"\nbackground = \"other\"\n"
        charStyleBackground s "path" @?= Just "code-bg"
        charStyleBackground s "file" @?= Just "other"
        (charStyle s "path" >>= csPadding) @?= Just (Zw 0.25),
      testCase "background and padding on a style that is not code are G03006" $ do
        codes (parseStyle (FileId 0) "[color.swatches]\nbg = { cmyk = [0, 0, 0, 8] }\n\n[character-styles.term]\nbackground = \"bg\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[character-styles.term]\npadding = \"1zw\"\n") @?= ["G03006"],
      testCase "a missing background swatch is G03013; a negative or unreadable padding G03006" $ do
        codes (parseStyle (FileId 0) "[character-styles.code]\nbackground = \"none-such\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[character-styles.code]\npadding = \"-1pt\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[character-styles.code]\npadding = \"abc\"\n") @?= ["G03006"],
      testCase "@style-def character code background=code-bg" $ do
        base <- styleOf "[color.swatches]\ncode-bg = { cmyk = [0, 0, 0, 8] }\n"
        case localStyleDef CharacterKind [("background", LocalWord "code-bg"), ("padding", LocalWord "0.5zw")] of
          Right (Left d) -> do
            let ls = noLocalStyles {lsCharStyles = Map.fromList [("code", d)]}
            [c | (c, _, _) <- checkLocalStyles base ls] @?= []
            charStyleBackground (withLocalStyles base ls) "code" @?= Just "code-bg"
            (charStyle (withLocalStyles base ls) "code" >>= csPadding) @?= Just (Zw 0.5)
          other -> assertFailure (show other),
      -- golem-doc ADR 0005
      testCase "the built-in url has no keys; a user's font overrides only the font" $ do
        s <- styleOf ""
        Map.lookup "url" (stCharStyles s) @?= Just noCharDef
        isUrlCharStyle s "url" @?= True
        isCodeCharStyle s "url" @?= False
        u <- styleOf "[fonts.code]\nlatin = \"m.otf\"\n\n[character-styles.url]\nfont = \"code\"\n\n[character-styles.link]\nbased-on = \"url\"\n"
        Map.lookup "url" (stCharStyles u) @?= Just noCharDef {csFont = Just "code"}
        isUrlCharStyle u "link" @?= True
        isUrlCharStyle u "code" @?= False
        isCodeCharStyle u "url" @?= False,
      -- golem-driver ADR 0023
      testCase "[code] and [code.colors]: every key is read" $ do
        s <- styleOf (swatches <> "\n[code]\nnumber = \"リスト{n}\"\nline-numbers = true\nline-number-color = \"gray\"\nhighlight = \"hl\"\nadded = \"add\"\nremoved = \"del\"\nwrap-mark = \"↩\"\ncontinued = \"（次ページに続く）\"\n\n[code.colors]\nkeyword = \"kw\"\ncomment = \"gray\"\ndata-type = \"kw\"\n")
        stCode s
          @?= CodeStyle
            { cdNumber = "リスト{n}",
              cdLineNumbers = True,
              cdLineNumberColor = Just "gray",
              cdHighlight = Just "hl",
              cdAdded = Just "add",
              cdRemoved = Just "del",
              cdWrapMark = "↩",
              cdContinued = "（次ページに続く）",
              cdColors = Map.fromList [("comment", "gray"), ("data-type", "kw"), ("keyword", "kw")]
            },
      testCase "[code]: the defaults" $ do
        s <- styleOf ""
        stCode s @?= defaultCodeStyle
        cdNumber defaultCodeStyle @?= "リスト{chapter}-{n}"
        cdLineNumbers defaultCodeStyle @?= False
        (cdLineNumberColor defaultCodeStyle, cdHighlight defaultCodeStyle, cdAdded defaultCodeStyle, cdRemoved defaultCodeStyle) @?= (Nothing, Nothing, Nothing, Nothing)
        (cdWrapMark defaultCodeStyle, cdContinued defaultCodeStyle) @?= ("", "")
        cdColors defaultCodeStyle @?= Map.empty,
      testCase "[code]: a wrong line-numbers, an unknown key, an unknown token kind and a number without a placeholder are G03006" $ do
        codes (parseStyle (FileId 0) "[code]\nline-numbers = \"yes\"\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[code]\nnumbers = true\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) (swatches <> "\n[code.colors]\nkeywords = \"kw\"\n")) @?= ["G03006"]
        codes (parseStyle (FileId 0) "[code]\nnumber = \"リスト\"\n") @?= ["G03006"],
      testCase "[code]: a swatch that is not there is G03013" $ do
        codes (parseStyle (FileId 0) "[code]\nhighlight = \"nope\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[code.colors]\nkeyword = \"nope\"\n") @?= ["G03013"],
      testCase "border and border-width of code; not in another style, not in zw" $ do
        s <- styleOf (swatches <> "\n[paragraph-styles.code]\nborder = \"black\"\nborder-width = \"0.5pt\"\n")
        let d = paraStyle s (Just "code")
        (d >>= psBorder) @?= Just "black"
        (d >>= psBorderWidth) @?= parseDim "0.5pt"
        codes (parseStyle (FileId 0) (swatches <> "\n[paragraph-styles.quote]\nborder = \"black\"\n")) @?= ["G03006"]
        codes (parseStyle (FileId 0) (swatches <> "\n[paragraph-styles.code]\nborder-width = \"1zw\"\n")) @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.code]\nborder = \"nope\"\n") @?= ["G03013"],
      testCase "@style-def paragraph code takes border and border-width" $ do
        base <- styleOf swatches
        case localStyleDef ParagraphKind [("border", LocalWord "black"), ("border-width", LocalWord "1pt")] of
          Right (Right d) -> do
            [c | (c, _, _) <- checkLocalStyles base noLocalStyles {lsParaStyles = Map.fromList [("code", d)]}] @?= []
            (paraStyle (withLocalStyles base noLocalStyles {lsParaStyles = Map.fromList [("code", d)]}) (Just "code") >>= psBorder) @?= Just "black"
          other -> assertFailure (show other)
    ]
  where
    styleOf t = either (\ds -> assertFailure (show ds) >> pure defaultStyle) pure (parseStyle (FileId 0) t)
    messages = either (map diagMessage) (const [])
    swatches = "[color.swatches]\ngray = { cmyk = [0, 0, 0, 60] }\nhl = { cmyk = [0, 0, 20, 0] }\nadd = { cmyk = [20, 0, 20, 0] }\ndel = { cmyk = [0, 20, 20, 0] }\nkw = { cmyk = [100, 50, 0, 0] }\nblack = { cmyk = [0, 0, 0, 100] }\n"

characterFeatureTests :: TestTree
characterFeatureTests =
  testGroup
    "character features (docs/adr/0020)"
    [ testCase "a character style reads kerning, tracking, proportional-metrics and baseline-shift" $
        case parseStyle (FileId 0) "[character-styles.tight]\nkerning = \"none\"\ntracking = -50\nproportional-metrics = true\nbaseline-shift = \"1pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            let cs = charStyle s "tight"
            fmap csKerning cs @?= Just (Just KernNone)
            fmap csTracking cs @?= Just (Just (-50))
            fmap csProportional cs @?= Just (Just True)
            fmap csBaselineShift cs @?= Just (Just (Abs 65536)),
      testCase "the other kerning values and a negative baseline shift are read" $
        case parseStyle (FileId 0) "[character-styles.a]\nkerning = \"metrics\"\n\n[character-styles.b]\nkerning = \"japanese-equal-width\"\nbaseline-shift = \"-0.5zw\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (charStyle s "a" >>= csKerning) @?= Just KernMetrics
            (charStyle s "b" >>= csKerning) @?= Just KernJapaneseEqualWidth
            (charStyle s "b" >>= csBaselineShift) @?= Just (Zw (-(1 / 2))),
      testCase "wrong values are G03021" $ do
        let g03021 src = codes (parseStyle (FileId 0) src) @?= ["G03021"]
        g03021 "[character-styles.a]\nkerning = \"optical\"\n"
        g03021 "[character-styles.a]\nkerning = \"auto\"\n"
        g03021 "[character-styles.a]\ntracking = 10001\n"
        g03021 "[character-styles.a]\ntracking = -1001\n"
        g03021 "[character-styles.a]\nbaseline-shift = \"up\"\n"
        g03021 "[paragraph-styles.a]\nkerning = \"optical\"\n"
        g03021 "[paragraph-styles.a]\ntracking = 10001\n"
        g03021 "[paragraph-styles.a]\nbaseline-shift = \"up\"\n",
      testCase "optical kerning names v1" $
        assertBool "message" (any ("v1 ではオプティカルカーニングを使えません" `T.isInfixOf`) (msgs (parseStyle (FileId 0) "[character-styles.a]\nkerning = \"optical\"\n"))),
      testCase "the bounds of tracking are allowed" $ do
        codes (parseStyle (FileId 0) "[character-styles.a]\ntracking = 10000\n") @?= []
        codes (parseStyle (FileId 0) "[character-styles.a]\ntracking = -1000\n") @?= [],
      testCase "paragraph styles inherit the keys through based-on; body defaults to metrics, 0, false, 0" $
        case parseStyle (FileId 0) "[paragraph-styles.a]\nkerning = \"none\"\ntracking = 20\n\n[paragraph-styles.b]\nbased-on = \"a\"\nbaseline-shift = \"1pt\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            let b = paraStyle s (Just "b")
            fmap psKerning b @?= Just (Just KernNone)
            fmap psTracking b @?= Just (Just 20)
            fmap psProportional b @?= Just (Just False)
            fmap psBaselineShift b @?= Just (Just (Abs 65536))
            let body = paraStyle s Nothing
            fmap psKerning body @?= Just (Just KernMetrics)
            fmap psTracking body @?= Just (Just 0)
            fmap psProportional body @?= Just (Just False)
            fmap psBaselineShift body @?= Just (Just (Abs 0)),
      testCase "@style-def takes the same keys; their errors are G03021" $ do
        localStyleDef CharacterKind [("kerning", LocalWord "none"), ("tracking", LocalWord "-50"), ("proportional-metrics", LocalWord "true"), ("baseline-shift", LocalWord "1pt")]
          @?= Right (Left noCharDef {csKerning = Just KernNone, csTracking = Just (-50), csProportional = Just True, csBaselineShift = Just (Abs 65536)})
        either (map fst) (const []) (localStyleDef ParagraphKind [("kerning", LocalWord "auto")]) @?= ["G03021"]
        [c | (c, _, _) <- checkLocalStyles defaultStyle noLocalStyles {lsCharStyles = Map.fromList [("a", noCharDef {csKerning = Just KernOptical})]}] @?= ["G03021"]
        either (map fst) (const []) (localStyleDef CharacterKind [("tracking", LocalWord "20000")]) @?= ["G03021"]
        either (map fst) (const []) (localStyleDef CharacterKind [("colour", LocalWord "x")]) @?= ["G03006"]
        -- a rule is a table, which @style-def cannot write (golem-driver ADR 0027)
        either (map fst) (const []) (localStyleDef ParagraphKind [("rule-before", LocalWord "x")]) @?= ["G03006"]
    ]

-- | Aki amounts and aki sets (docs/adr ADR 0019).
akiTests :: TestTree
akiTests =
  testGroup
    "aki amounts and aki sets (docs/adr ADR 0019)"
    [ testCase "an aki amount is a name, an amount in zw or a percentage" $ do
        map parseAki ["ベタ", "全角", "二分", "三分", "四分", "五分", "六分", "八分", "二分四分", "0.2zw", "12.5%"]
          @?= map Just [0, 1, 1 / 2, 1 / 3, 1 / 4, 1 / 5, 1 / 6, 1 / 8, 3 / 4, 1 / 5, 1 / 8]
        map parseAki ["-1zw", "1mm", "十分"] @?= [Nothing, Nothing, Nothing],
      testCase "[aki-sets.<name>] and the aki-set of a paragraph style are read" $
        case parseStyle (FileId 0) wideWaou of
          Left ds -> assertFailure (show ds)
          Right s -> do
            fmap asBasedOn (Map.lookup "wide-waou" (stAkiSets s)) @?= Just (Just "gyomatsu-yakumono-hankaku")
            fmap asRules (Map.lookup "wide-waou" (stAkiSets s))
              @?= Just
                [ AkiRuleDef ["japanese"] ["western"] (1 / 4) (1 / 3) (1 / 2),
                  AkiRuleDef ["western"] ["japanese"] (1 / 4) (1 / 3) (1 / 2)
                ]
            (paraStyle s Nothing >>= psAkiSet) @?= Just "wide-waou"
            (paraStyle s (Just "caption") >>= psAkiSet) @?= Just "wide-waou",
      testCase "body uses gyomatsu-yakumono-hankaku by default; minimum and maximum default to optimum" $ do
        case parseStyle (FileId 0) "" of
          Left ds -> assertFailure (show ds)
          Right s -> (paraStyle s (Just "verse") >>= psAkiSet) @?= Just "gyomatsu-yakumono-hankaku"
        case parseStyle (FileId 0) "[aki-sets.a]\nrules = [{ before = [\"kana\", \"ideograph\"], after = \"line-end\", optimum = \"25%\" }]\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            fmap asBasedOn (Map.lookup "a" (stAkiSets s)) @?= Just Nothing
            fmap asRules (Map.lookup "a" (stAkiSets s)) @?= Just [AkiRuleDef ["kana", "ideograph"] ["line-end"] (1 / 4) (1 / 4) (1 / 4)],
      testCase "errors of aki amounts and aki sets are G03020" $ do
        let rule r = "[aki-sets.a]\nrules = [" <> r <> "]\n"
        codes (parseStyle (FileId 0) (rule "{ before = \"kana\", after = \"kana\", optimum = \"四分\", minimum = \"二分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) (rule "{ before = \"kana\", after = \"kana\", optimum = \"四分\", maximum = \"八分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) (rule "{ before = \"kanji\", after = \"kana\", optimum = \"四分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) (rule "{ before = \"line-end\", after = \"kana\", optimum = \"四分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) (rule "{ before = \"kana\", after = \"line-start\", optimum = \"四分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) (rule "{ before = \"kana\", after = \"paragraph-start\", optimum = \"四分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) (rule "{ before = \"kana\", after = \"kana\", optimum = \"十分\" }")) @?= ["G03020"]
        codes (parseStyle (FileId 0) "[aki-sets.gyomatsu-yakumono-hankaku]\nrules = []\n") @?= ["G03020"]
        codes (parseStyle (FileId 0) "[aki-sets.gyomatsu-yakumono-zenkaku]\n") @?= ["G03020"]
        let ms = either (map diagMessage) (const []) (parseStyle (FileId 0) (rule "{ before = \"kanji\", after = \"kana\", optimum = \"四分\" }"))
        assertBool (show ms) (not (null ms) && all ("アキの量の指定が正しくありません: " `T.isPrefixOf`) ms),
      testCase "an aki name in another dimension is G03020" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"二分\"\n") @?= ["G03020"]
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"wide\"\n") @?= ["G03006"],
      testCase "references to aki sets are G03013" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\naki-set = \"nope\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[aki-sets.a]\nbased-on = \"nope\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[aki-sets.a]\nbased-on = \"b\"\n\n[aki-sets.b]\nbased-on = \"a\"\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[aki-sets.a]\nbased-on = \"gyomatsu-yakumono-zenkaku\"\n\n[paragraph-styles.quote]\naki-set = \"a\"\n") @?= [],
      testCase "a paragraph style of a file may name an aki set" $ do
        base <- either (\ds -> assertFailure (show ds) >> error "unreachable") pure (parseStyle (FileId 0) wideWaou)
        localStyleDef ParagraphKind [("aki-set", LocalWord "wide-waou")] @?= Right (Right noParaDef {psAkiSet = Just "wide-waou"})
        [(c, n) | (c, n, _) <- checkLocalStyles base (LocalStyles Map.empty (Map.fromList [("q", noParaDef {psAkiSet = Just "nope"})]) Map.empty)] @?= [("G03013", "q")]
        [(c, n) | (c, n, _) <- checkLocalStyles base (LocalStyles Map.empty (Map.fromList [("q", noParaDef {psAkiSet = Just "wide-waou"})]) Map.empty)] @?= []
    ]
  where
    wideWaou =
      T.unlines
        [ "[aki-sets.wide-waou]",
          "based-on = \"gyomatsu-yakumono-hankaku\"",
          "rules = [",
          "  { before = \"japanese\", after = \"western\", optimum = \"三分\", minimum = \"四分\", maximum = \"二分\" },",
          "  { before = \"western\", after = \"japanese\", optimum = \"三分\", minimum = \"四分\", maximum = \"二分\" },",
          "]",
          "",
          "[paragraph-styles.body]",
          "aki-set = \"wide-waou\""
        ]

-- | Regex styles (docs/adr ADR 0015).
regexStyleTests :: TestTree
regexStyleTests =
  testGroup
    "regex styles (docs/adr ADR 0015)"
    [ testCase "regex-styles is read as an array of tables" $ do
        s <- styleOf "[paragraph-styles.body]\nregex-styles = [{ pattern = '[0-9]+', style = \"bold\" }]\n"
        (paraStyle s Nothing >>= psRegexStyles) @?= Just [RegexStyleDef "[0-9]+" "bold"],
      testCase "regex-styles is inherited through based-on, and replaced as a whole" $ do
        s <- styleOf (body <> "[paragraph-styles.quote]\nindent = \"1zw\"\n")
        (paraStyle s (Just "quote") >>= psRegexStyles) @?= Just [RegexStyleDef "[0-9]+" "bold"]
        e <- styleOf (body <> "[paragraph-styles.quote]\nregex-styles = []\n")
        (paraStyle e (Just "quote") >>= psRegexStyles) @?= Just []
        o <- styleOf (body <> "[paragraph-styles.quote]\nregex-styles = [{ pattern = 'x', style = \"italic\" }]\n")
        (paraStyle o (Just "quote") >>= psRegexStyles) @?= Just [RegexStyleDef "x" "italic"],
      testCase "the built-in paragraph styles have no regex styles" $ do
        s <- styleOf ""
        mapM_ (\n -> (paraStyle s (Just n) >>= psRegexStyles) @?= Nothing) ["body", "verse", "caption", "sidenote"],
      testCase "the keys of a regex style (G03006)" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ style = \"bold\" }]\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = 'a' }]\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = 'a', style = \"bold\", colour = \"x\" }]\n") @?= ["G03006"]
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = 1, style = \"bold\" }]\n") @?= ["G03006"],
      testCase "a pattern outside the dialect is G03015, an unknown character style G03013" $ do
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = '\\1', style = \"bold\" }]\n") @?= ["G03015"]
        codes (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = 'a', style = \"nope\" }]\n") @?= ["G03013"]
        codes (parseStyle (FileId 0) "[character-styles.n]\nsynthetic-bold = true\n\n[paragraph-styles.body]\nregex-styles = [{ pattern = 'a', style = \"n\" }]\n") @?= [],
      testCase "the message of G03015 names the style, the place in the array and the offset" $
        messages (parseStyle (FileId 0) "[paragraph-styles.quote]\nregex-styles = [{ pattern = 'a', style = \"bold\" }, { pattern = 'ab\\1', style = \"bold\" }]\n")
          @?= ["G03015 正規表現を解釈できません: 後方参照は使えません（quote の 2 番目の正規表現の 3 字目）"],
      testCase "the message of G03013 for a regex style" $
        messages (parseStyle (FileId 0) "[paragraph-styles.body]\nregex-styles = [{ pattern = 'a', style = \"nope\" }]\n")
          @?= ["G03013 style.toml のスタイルの参照が不正です: 正規表現スタイルの文字スタイルがありません: nope"],
      testCase "a regex style of a file goes after style.toml's, and reaches the styles based on it" $ do
        base <- styleOf (body <> "[paragraph-styles.quote]\nindent = \"1zw\"\n")
        let ls = noLocalStyles {lsRegexStyles = Map.fromList [("body", [RegexStyleDef "x" "italic"])]}
            s = withLocalStyles base ls
        (paraStyle s Nothing >>= psRegexStyles) @?= Just [RegexStyleDef "[0-9]+" "bold", RegexStyleDef "x" "italic"]
        (paraStyle s (Just "quote") >>= psRegexStyles) @?= Just [RegexStyleDef "[0-9]+" "bold", RegexStyleDef "x" "italic"]
        (paraStyle base (Just "quote") >>= psRegexStyles) @?= Just [RegexStyleDef "[0-9]+" "bold"],
      testCase "a regex style of a file does not reach a style with its own regex-styles" $ do
        base <- styleOf (body <> "[paragraph-styles.quote]\nregex-styles = [{ pattern = 'q', style = \"bold\" }]\n")
        let s = withLocalStyles base noLocalStyles {lsRegexStyles = Map.fromList [("body", [RegexStyleDef "x" "italic"])]}
        (paraStyle s (Just "quote") >>= psRegexStyles) @?= Just [RegexStyleDef "q" "bold"],
      testCase "a regex style of a file can use a character style of the file" $ do
        base <- styleOf ""
        let ls = noLocalStyles {lsCharStyles = Map.fromList [("n", noCharDef)], lsRegexStyles = Map.fromList [("body", [RegexStyleDef "a" "n"])]}
        checkLocalRegexStyles base ls @?= [],
      testCase "the errors of a file's regex styles, each at its place" $ do
        base <- styleOf body
        let ls = noLocalStyles {lsRegexStyles = Map.fromList [("body", [RegexStyleDef "a" "bold", RegexStyleDef "\\1" "bold", RegexStyleDef "b" "nope"]), ("nope", [RegexStyleDef "a" "bold"])]}
        [(n, i, c) | (n, i, c, _) <- checkLocalRegexStyles base ls] @?= [("body", 1, "G03015"), ("body", 2, "G03013"), ("nope", 0, "G03013")],
      testCase "the errors of a file's regex styles are not reported twice" $ do
        base <- styleOf body
        checkLocalStyles base noLocalStyles {lsRegexStyles = Map.fromList [("body", [RegexStyleDef "\\1" "bold"])]} @?= [],
      testCase "a regex style in a file takes exactly a pattern and a style" $ do
        localRegexStyleDef [("pattern", LocalString "[0-9]+"), ("style", LocalWord "bold")] @?= Right (RegexStyleDef "[0-9]+" "bold")
        assertBool "missing style" (isLeftE (localRegexStyleDef [("pattern", LocalString "a")]))
        assertBool "missing pattern" (isLeftE (localRegexStyleDef [("style", LocalWord "bold")]))
        assertBool "unknown key" (isLeftE (localRegexStyleDef [("pattern", LocalString "a"), ("style", LocalWord "bold"), ("colour", LocalWord "x")]))
        regexStyleKeys @?= ["pattern", "style"],
      testCase "regex-styles cannot be written in @style-def paragraph" $
        assertBool "G03006" (isLeftE (localStyleDef ParagraphKind [("regex-styles", LocalString "x")]))
    ]
  where
    body = "[paragraph-styles.body]\nregex-styles = [{ pattern = '[0-9]+', style = \"bold\" }]\n\n"
    styleOf t = either (\ds -> assertFailure (show ds) >> pure defaultStyle) pure (parseStyle (FileId 0) t)
    messages = either (map (\d -> let DiagnosticCode c = diagCode d in c <> " " <> diagMessage d)) (const [])
    isLeftE = either (const True) (const False)

-- | Styles defined in a file (docs/adr ADR 0014).
localStyleTests :: TestTree
localStyleTests =
  testGroup
    "styles defined in a file (docs/adr ADR 0014)"
    [ testCase "the words and strings of a style defined in a file are read as TOML values" $ do
        localStyleDef ParagraphKind [("based-on", LocalWord "body"), ("indent", LocalWord "2zw"), ("line-breaks", LocalWord "keep"), ("space-between", LocalWord "1")]
          @?= Right (Right noParaDef {psBasedOn = Just "body", psIndent = Just (Zw 2), psLineBreaks = Just KeepLines, psSpaceBetween = Just 1})
        localStyleDef CharacterKind [("synthetic-bold", LocalWord "true")] @?= Right (Left noCharDef {csSyntheticBold = Just True})
        let bad k xs = assertBool (show xs) (isLeftE (localStyleDef k xs))
        bad CharacterKind [("synthetic-bold", LocalString "true")]
        bad ParagraphKind [("space-between", LocalString "1")]
        bad CharacterKind [("colour", LocalWord "x")]
        bad ParagraphKind [("line-breaks", LocalWord "x")]
        bad ParagraphKind [("space-between", LocalWord "-1")],
      testCase "every key of charStyleKeys and paraStyleKeys is known" $ do
        let valueOf = \case
              "synthetic-bold" -> "true"
              "synthetic-italic" -> "true"
              "line-breaks" -> "keep"
              "space-between" -> "1"
              "size" -> "1zw"
              "indent" -> "1zw"
              "first-line-indent" -> "1zw"
              "kerning" -> "none"
              "tracking" -> "10"
              "proportional-metrics" -> "true"
              "baseline-shift" -> "1pt"
              "aki-set" -> "gyomatsu-yakumono-hankaku"
              "padding" -> "1zw"
              "border-width" -> "1pt"
              _ -> "x"
            known k key = not (isLeftE (localStyleDef k [(key, LocalWord (valueOf key))]))
        assertBool "char" (all (known CharacterKind) charStyleKeys)
        assertBool "para" (all (known ParagraphKind) paraStyleKeys)
        assertBool "a made-up key is unknown" (not (known ParagraphKind "colour")),
      testCase "a local style inherits a style.toml style through based-on" $ do
        base <- styleOf "[paragraph-styles.quote]\nindent = \"3zw\"\nspace-between = 2\n"
        let s = withLocalStyles base (localPara [("letter", noParaDef {psBasedOn = Just "quote"})])
        fmap psIndent (paraStyle s (Just "letter")) @?= Just (Just (Zw 3))
        fmap psSpaceBetween (paraStyle s (Just "letter")) @?= Just (Just 2),
      testCase "styles defined in a file get the checks of style.toml" $ do
        base <- styleOf "[page]\nsize = \"A6\"\n\n[page.grid]\nfont-size = \"13Q\"\ncharacters = 20\nlines = 10\nline-pitch = \"20H\"\nposition = { top = \"10mm\", gutter = \"10mm\" }\n\n[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n"
        let chk ls = [(c, n) | (c, n, _) <- checkLocalStyles base ls]
        chk (localPara [("Letter", noParaDef)]) @?= [("G03006", "Letter")]
        chk (localPara [("a", noParaDef {psBasedOn = Just "nope"})]) @?= [("G03013", "a")]
        assertBool "cycle" (("G03013", "a") `elem` chk (localPara [("a", noParaDef {psBasedOn = Just "b"}), ("b", noParaDef {psBasedOn = Just "a"})]))
        chk (localChar [("t", noCharDef {csFont = Just "nope"})]) @?= [("G03008", "t")]
        chk (localChar [("t", noCharDef {csColor = Just "nope"})]) @?= [("G03013", "t")]
        chk (localChar [("t", noCharDef {csColor = Just "accent"})]) @?= []
        chk (localPara [("a", noParaDef {psSize = Just (Zw 2)})]) @?= [("G03011", "a")]
        chk (localPara [("a", noParaDef {psIndent = Just (Zw 1), psFirstLineIndent = Just (Zw (-2))})]) @?= [("G03012", "a")],
      testCase "errors style.toml has by itself are not reported for styles defined in a file" $ do
        let base = defaultStyle {stParaStyles = Map.insert "q" noParaDef {psBasedOn = Just "nope"} (stParaStyles defaultStyle)}
        [c | (c, _, _) <- checkLocalStyles base (localPara [("letter", noParaDef)])] @?= [],
      testCase "an override changes only the keys it writes, in its file" $ do
        base <- styleOf "[fonts.heading]\nlatin = \"h.otf\"\n\n[paragraph-styles.quote]\nfont = \"heading\"\n"
        let s = withLocalStyles base (localPara [("quote", noParaDef {psIndent = Just (Zw 1)})])
        fmap psFont (paraStyle s (Just "quote")) @?= Just (Just "heading")
        fmap psIndent (paraStyle s (Just "quote")) @?= Just (Just (Zw 1))
        fmap psIndent (paraStyle base (Just "quote")) @?= Just (Just (Zw 0)),
      testCase "overriding body changes the styles based on it" $ do
        base <- styleOf "[paragraph-styles.quote]\nspace-between = 1\n"
        let s = withLocalStyles base (localPara [("body", noParaDef {psIndent = Just (Zw 1)})])
        fmap psIndent (paraStyle s (Just "quote")) @?= Just (Just (Zw 1)),
      testCase "based-on cycles through overrides are G03013" $ do
        let chk b ls = [(c, n) | (c, n, _) <- checkLocalStyles b ls]
        base <- styleOf "[paragraph-styles.quote]\nindent = \"1zw\"\n"
        assertBool "self" (("G03013", "quote") `elem` chk base (localPara [("quote", noParaDef {psBasedOn = Just "quote"})]))
        ab <- styleOf "[paragraph-styles.a]\nbased-on = \"b\"\n\n[paragraph-styles.b]\nindent = \"1zw\"\n"
        assertBool "through style.toml" (("G03013", "b") `elem` chk ab (localPara [("b", noParaDef {psBasedOn = Just "a"})]))
        assertBool "body" (("G03013", "body") `elem` chk base (localPara [("body", noParaDef {psBasedOn = Just "quote"})])),
      testCase "an override of body can make a style.toml style hang out (G03012)" $ do
        base <- styleOf "[paragraph-styles.quote]\nspace-between = 1\n"
        assertBool "quote" (("G03012", "quote") `elem` [(c, n) | (c, n, _) <- checkLocalStyles base (localPara [("body", noParaDef {psFirstLineIndent = Just (Zw (-1))})])]),
      testCase "a table written twice in style.toml is a TOML error (G03006)" $
        codes (parseStyle (FileId 0) "[paragraph-styles.quote]\nindent = \"1zw\"\n\n[paragraph-styles.quote]\nindent = \"2zw\"\n") @?= ["G03006"]
    ]
  where
    styleOf t = either (\ds -> assertFailure (show ds) >> pure defaultStyle) pure (parseStyle (FileId 0) t)
    localPara xs = noLocalStyles {lsParaStyles = Map.fromList xs}
    localChar xs = noLocalStyles {lsCharStyles = Map.fromList xs}
    isLeftE = either (const True) (const False)

pageSizeTests :: [TestTree]
pageSizeTests =
  [ testCase "width and height are dimensions" $ do
      trim "{ width = \"148mm\", height = \"210mm\" }" @?= Right (Just (abs' "148mm", abs' "210mm"))
      trim "{ width = \"396pt\", height = \"612pt\" }" @?= Right (Just (396 * 65536, 612 * 65536))
      trim "{ width = \"100mm\", height = \"600Q\" }" @?= Right (Just (abs' "100mm", abs' "600Q"))
      trim "{ width = \"210mm\", height = \"148mm\" }" @?= Right (Just (abs' "210mm", abs' "148mm")),
    testCase "a page given in inches (golem-project ADR 0010)" $
      trim "{ width = \"5.5in\", height = \"8.5in\" }" @?= trim "{ width = \"396pt\", height = \"612pt\" }",
    testCase "a page given by dimensions is the same as the named size" $
      trim "{ width = \"107.95mm\", height = \"174.625mm\" }" @?= trim "\"mass-market\"",
    testCase "the named sizes are the table in sp" $
      sequence_
        [ trim ("\"" <> n <> "\"") @?= Right (Just (mm w, mm h))
        | n <- ["A4", "A5", "A6", "B5", "B6", "四六判", "mass-market"],
          Just (w, h) <- [pageSize n]
        ],
    testCase "菊判 and 新書判" $ do
      trim "\"菊判\"" @?= trim "{ width = \"150mm\", height = \"220mm\" }"
      trim "\"新書判\"" @?= trim "{ width = \"103mm\", height = \"182mm\" }"
      assertBool "菊判" (isRight (trim "\"菊判\""))
      assertBool "新書判" (isRight (trim "\"新書判\"")),
    testCase "errors are G03017" $ do
      g03017 "\"148mm x 210mm\"" "未知の判型です: 148mm x 210mm。表にない判型は size = { width = \"…\", height = \"…\" } で書きます"
      g03017 "\"A3\"" "未知の判型です: A3"
      -- a name with x is no longer left to the PDF's G07001 (golem-driver ADR 0016)
      g03017 "\"148x210\"" "未知の判型です: 148x210"
      g03017 "\"菊版\"" "未知の判型です: 菊版"
      g03017 "\"新書版\"" "未知の判型です: 新書版"
      g03017 "{ width = \"148mm\" }" "判型の width と height はどちらも必須です"
      g03017 "{ width = \"148mm\", height = \"210mm\", depth = \"1mm\" }" "depth"
      g03017 "{ width = \"10zw\", height = \"210mm\" }" "判型には zw を使えません"
      g03017 "{ width = \"0mm\", height = \"210mm\" }" "判型の幅と高さは 0 より大きい寸法です"
      g03017 "{ width = \"148\", height = \"210mm\" }" "長さの書き方が不正です: 148",
    testCase "G03017 is at the value of size" $
      case parseStyle (FileId 0) "[page]\nsize = \"A3\"\n" of
        Left [d] -> spanStart (diagSpan d) @?= 14
        r -> assertFailure (show r)
  ]
  where
    src v = "[page]\nsize = " <> v <> "\n"
    trim v = fmap (fmap pageTrimSize . stPage) (parseStyle (FileId 0) (src v))
    abs' t = case parseDim t of
      Just (Abs x) -> x
      d -> error (show d)
    mm x = round (x * 72 * 65536 / (254 / 10) :: Rational)
    isRight = either (const False) (const True)
    g03017 v needle = case parseStyle (FileId 0) (src v) of
      Left ds -> do
        map (\d -> let DiagnosticCode c = diagCode d in c) ds @?= ["G03017"]
        assertBool (show (map diagMessage ds)) (any ((needle `T.isInfixOf`) . diagMessage) ds)
      Right _ -> assertFailure ("not an error: " <> T.unpack v)
