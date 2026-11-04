{-# LANGUAGE GADTs #-}

module Main (main) where

import Control.Concurrent (forkIO)
import Control.Monad (void)
import Data.Aeson qualified as J
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import EditingSpec (editingTests)
import Golem.Driver.Explain (codeDescriptionUrl)
import Golem.Eval.File (builtinInlineCommands)
import Golem.Lsp.Features
import Golem.Lsp.Server (lspSeverity, rewriteInitializeResponse, runGolemLspWithHandles)
import Golem.Lsp.Workspace
import Golem.Plugin (watToWasm)
import Golem.Plugin.Lock (defaultCacheDir, lockPlugins, renderLock)
import Golem.Syntax
import Golem.TestSupport.Env (withEnv)
import Golem.TestSupport.Gen (genText)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Hedgehog hiding (assert)
import Hedgehog qualified as H
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import StaleS1Spec (staleS1Tests)
import System.Directory (copyFile, createDirectoryIfMissing, doesDirectoryExist, listDirectory, makeAbsolute)
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import TableWatchSpec (tableWatchTests)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

root :: FilePath
root = "test/fixtures/proj"

main :: IO ()
main = do
  cacheHome <- lookupEnv "XDG_CACHE_HOME"
  defaultMain (dependentTestGroup "golem-lsp" AllFinish [tests, cacheHomeTests cacheHome])

{- | The tests that set XDG_CACHE_HOME, one at a time after the others, and
last a check that it is as it was when the suite started (docs/adr ADR
0072). The environment is one for the process, and tasty runs the other
tests at once.
-}
cacheHomeTests :: Maybe String -> TestTree
cacheHomeTests start =
  dependentTestGroup
    "XDG_CACHE_HOME (docs/adr ADR 0072)"
    AllFinish
    [ -- docs/adr ADR 0031
      testCase "completion: the commands of the plugins after the built-in ones, with a syntax error too" $
        withIdentityPlugin $ \tmp -> do
          ws0 <- openWorkspace tmp
          ws <- updateFile ws0 "b.gm" "本文。\n\n["
          let names = map cmpLabel (completions ws "b.gm" (BS.length (TE.encodeUtf8 "本文。\n\n[")))
          names @?= builtinInlineCommands <> ["broken"]
          ws' <- updateFile ws0 "b.gm" "本文。\n\n[b"
          assertBool "broken" ("broken" `elem` map cmpLabel (completions ws' "b.gm" (BS.length (TE.encodeUtf8 "本文。\n\n[b")))),
      testCase "XDG_CACHE_HOME is as it was when the suite started" $
        lookupEnv "XDG_CACHE_HOME" >>= (@?= start)
    ]

-- | Byte offset of the k-th byte inside the first occurrence of needle.
offsetIn :: Text -> Text -> Int -> Int
offsetIn src needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src))) + k

{- | The columns of a line that fall between two characters, from 0 to the
width of the line, in UTF-8 bytes or UTF-16 code units.
-}
characterBoundaries :: Encoding -> Text -> [Int]
characterBoundaries enc = scanl (+) 0 . map units . T.unpack
  where
    units ch = case enc of
      Utf8 -> BS.length (TE.encodeUtf8 (T.singleton ch))
      Utf16 -> if fromEnum ch > 0xFFFF then 2 else 1

textOf :: Workspace -> FilePath -> Text
textOf ws p = maybe "" srcText (sourceOf ws p)

at :: Workspace -> FilePath -> Text -> Int -> Int
at ws p = offsetIn (textOf ws p)

slice :: Workspace -> Location -> Text
slice ws (Location p s e) = TE.decodeUtf8 (BS.take (e - s) (BS.drop s (TE.encodeUtf8 (textOf ws p))))

tests :: TestTree
tests =
  testGroup
    "golem-lsp (ADR 0001)"
    [ testCase "no codeDescription for a code outside docs/diagnostics.md (golem-cli ADR 0005)" $
        codeDescriptionUrl (DiagnosticCode "X001") @?= Nothing,
      testCase "definition: label across files, import path, namespaced variable" $ do
        ws <- openWorkspace root
        map (slice ws) (definition ws "a.gm" (at ws "a.gm" "second]" 1)) @?= ["second"]
        map locPath (definition ws "a.gm" (at ws "a.gm" "second]" 1)) @?= ["b.gm"]
        map locPath (definition ws "a.gm" (at ws "a.gm" "common/values.gm" 3)) @?= ["common/values.gm"]
        map (\l -> (locPath l, slice ws l)) (definition ws "a.gm" (at ws "a.gm" "values.version" 8)) @?= [("common/values.gm", "version")],
      testCase "references of a label cross files" $ do
        ws <- openWorkspace root
        let refs = references ws "b.gm" (at ws "b.gm" "intro]" 0)
        map locPath refs @?= ["a.gm", "b.gm", "b.gm"]
        map (slice ws) refs @?= ["intro", "intro", "intro"],
      testCase "rename rewrites every reference and refuses an existing name" $ do
        ws <- openWorkspace root
        case renameLabel ws "a.gm" (at ws "a.gm" "intro" 0) "opening" of
          Right edits -> map (\(l, t) -> (locPath l, slice ws l, t)) edits @?= [("a.gm", "intro", "opening"), ("b.gm", "intro", "opening"), ("b.gm", "intro", "opening")]
          Left e -> assertFailure (show e)
        renameLabel ws "a.gm" (at ws "a.gm" "intro" 0) "second" @?= Left (LabelExists "second")
        renameLabel ws "a.gm" (at ws "a.gm" "はじめに" 0) "x" @?= Left NotALabel,
      testCase "completion: commands, labels, import paths, swatches" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n[ref-title \n[co\n[color \n@import \n"
        let src = textOf ws "b.gm"
            names o = map cmpLabel (completions ws "b.gm" o)
        assertBool "labels" (all (`elem` names (offsetIn src "[ref-title " 11)) ["intro", "second"])
        assertBool "commands" ("color" `elem` names (offsetIn src "[co" 3))
        names (offsetIn src "[color " 7) @?= ["accent"]
        assertBool "paths" ("common/values.gm" `elem` names (offsetIn src "@import " 8)),
      testCase "completion: a project without plugins has the built-in names only" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "本文。\n\n["
        map cmpLabel (completions ws "b.gm" (BS.length (TE.encodeUtf8 "本文。\n\n["))) @?= builtinInlineCommands
        length builtinInlineCommands @?= 18,
      testCase "completion: paragraph and character styles (docs/adr ADR 0005)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n@style \n本文。\n\n[style \n"
        let src = textOf ws "b.gm"
            found = completions ws "b.gm"
        map cmpLabel (found (offsetIn src "@style " 7)) @?= ["body", "caption", "quote", "sidenote", "verse"]
        map cmpKind (found (offsetIn src "@style " 7)) @?= replicate 5 CkParaStyle
        map cmpLabel (found (offsetIn src "[style " 7)) @?= ["bold", "code", "italic", "strong", "url"],
      testCase "completion: the kinds of a page break (docs/adr ADR 0017)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n@page-break \n"
        let src = textOf ws "b.gm"
            found = completions ws "b.gm" (offsetIn src "@page-break " 12)
        map cmpLabel found @?= ["recto", "verso"]
        map cmpKind found @?= [CkSettingValue, CkSettingValue],
      testCase "completion: the signs of page-lines (docs/adr ADR 0030)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n@page-lines \n"
        let src = textOf ws "b.gm"
            found = completions ws "b.gm" (offsetIn src "@page-lines " 12)
        map cmpLabel found @?= ["+1", "-1"]
        map cmpKind found @?= [CkSettingValue, CkSettingValue],
      testCase "completion: @style-def (docs/adr ADR 0014)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@style-def paragraph letter\n@style-def paragraph memo\n\n@label second\n# 次の章\n\n@style-def \n\n@style-def paragraph letter \n\n@style-def paragraph letter based-on=\n\n@style \n\n@style-def character term font=\n"
        let src = textOf ws "b.gm"
            found = completions ws "b.gm"
        map cmpLabel (found (offsetIn src "@style-def \n" 11)) @?= ["character", "paragraph", "regex"]
        map cmpKind (found (offsetIn src "@style-def \n" 11)) @?= [CkStyleKind, CkStyleKind, CkStyleKind]
        let keys = found (offsetIn src "@style-def paragraph letter \n" 28)
        assertBool "keys" (all (`elem` map cmpLabel keys) ["based-on=", "indent="])
        assertBool "key kinds" (all ((== CkSettingKey) . cmpKind) keys)
        let bases = map cmpLabel (found (offsetIn src "based-on=\n" 9))
        assertBool (show bases) (all (`elem` bases) ["body", "verse", "quote", "memo"])
        assertBool "@style" ("letter" `elem` map cmpLabel (found (offsetIn src "@style \n" 7)))
        ws' <- updateFile ws "a.gm" (textOf ws "a.gm" <> "\n@style \n")
        let srcA = textOf ws' "a.gm"
        assertBool "not in another file" ("letter" `notElem` map cmpLabel (completions ws' "a.gm" (offsetIn srcA "@style \n" 7))),
      testCase "completion: @style-def regex (docs/adr ADR 0015)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@style-def paragraph letter\n\n@label second\n# 次の章\n\n@style-def regex \n\n@style-def regex body \n\n@style-def regex body pattern=x style=\n"
        let src = textOf ws "b.gm"
            found = completions ws "b.gm"
            paras = found (offsetIn src "@style-def regex \n" 17)
        assertBool (show paras) (all (`elem` map cmpLabel paras) ["body", "verse", "letter"])
        assertBool "paragraph kinds" (all ((== CkParaStyle) . cmpKind) paras)
        found (offsetIn src "@style-def regex body \n" 22) @?= [Completion "pattern=" CkSettingKey, Completion "style=" CkSettingKey]
        let chars = found (offsetIn src "style=\n" 6)
        map cmpLabel chars @?= ["bold", "code", "italic", "strong", "url"]
        assertBool "character kinds" (all ((== CkCharStyle) . cmpKind) chars),
      testCase "definition: the styles @style-def regex names (docs/adr ADR 0015)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@style-def character n synthetic-bold=true\n@style-def paragraph letter\n@style-def regex letter pattern=x style=n\n\n@label second\n# 次の章\n"
        let src = textOf ws "b.gm"
        map (slice ws) (definition ws "b.gm" (offsetIn src "letter pattern" 1)) @?= ["letter"]
        map (slice ws) (definition ws "b.gm" (offsetIn src "style=n\n" 1)) @?= ["n"],
      testCase "completion: @manifest (docs/adr ADR 0014)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n@manifest \n\n@manifest paragraph-separator=\n"
        let src = textOf ws "b.gm"
            found = completions ws "b.gm"
        found (offsetIn src "@manifest \n" 10) @?= [Completion "paragraph-separator=" CkSettingKey]
        found (offsetIn src "separator=\n" 10) @?= [Completion "blank-line" CkSettingValue, Completion "line" CkSettingValue],
      testCase "a file outside the project read in the line style has no G05001 (docs/adr ADR 0014)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "loose.gm" "@manifest paragraph-separator=line\n\nFull fathom five\nOf his bones\n"
        [c | d <- fromMaybe [] (Map.lookup "loose.gm" (diagnosticsFor ws)), let { DiagnosticCode c = diagCode d }] @?= []
        ws' <- updateFile ws0 "loose.gm" "Full fathom five\nOf his bones\n"
        [c | d <- fromMaybe [] (Map.lookup "loose.gm" (diagnosticsFor ws')), let { DiagnosticCode c = diagCode d }] @?= ["G05001"],
      -- golem-parser ADR 0009
      testCase "an empty expression outside the project is one G01020, and hover and completion still work" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "loose.gm" "[=]\n\n[= 1 + 2]\n\n[co\n"
        let src = textOf ws "loose.gm"
        filter (== "G01020") (codesOf ws "loose.gm") @?= ["G01020"]
        -- the evaluation diagnostics go with a syntax error
        filter (`notElem` ["G01017", "G01020"]) (codesOf ws "loose.gm") @?= []
        assertBool "hover" (isJust (hover ws "loose.gm" (offsetIn src "1 + 2" 0)))
        assertBool "completion" ("color" `elem` map cmpLabel (completions ws "loose.gm" (offsetIn src "[co" 3))),
      testCase "the reserved [! is published as the error G01100 (docs/adr ADR 0115)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n本文 [!foo bar] です。\n"
        [(c, diagSeverity d) | d <- fromMaybe [] (Map.lookup "b.gm" (diagnosticsFor ws)), let { DiagnosticCode c = diagCode d }, c == "G01100"] @?= [("G01100", Error)],
      testCase "a buffer with CR or a BOM is G01003 or G01002, in and outside the project" $ do
        ws0 <- openWorkspace root
        let cases = [("b.gm", "@label second\r\n# 次の章\n", "G01003"), ("b.gm", "\xFEFF@label second\n# 次の章\n", "G01002"), ("loose.gm", "本文\r\n", "G01003"), ("loose.gm", "\xFEFF本文\n", "G01002")]
        mapM_
          ( \(p, t, c) -> do
              ws <- updateFile ws0 p t
              assertBool (show (p, codesOf ws p)) (c `elem` codesOf ws p)
          )
          cases,
      testCase "definition: a style defined in the file (docs/adr ADR 0014)" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@style-def paragraph letter\n@style-def paragraph verse line-breaks=join\n\n@label second\n# 次の章\n\n@style letter\n本文。\n\n@style verse\n詩。\n\n@style quote\n引用。\n"
        let src = textOf ws "b.gm"
        definition ws "b.gm" (offsetIn src "letter\n本文" 1) @?= [Location "b.gm" (offsetIn src "letter\n@style-def" 0) (offsetIn src "letter\n@style-def" 6)]
        map (slice ws) (definition ws "b.gm" (offsetIn src "verse\n詩" 1)) @?= ["verse"]
        definition ws "b.gm" (offsetIn src "quote\n引用" 1) @?= []
        ws' <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n@style verse\n詩。\n"
        definition ws' "b.gm" (offsetIn (textOf ws' "b.gm") "verse\n詩" 1) @?= [],
      testCase "editing the file settings evaluates that file alone (docs/adr ADR 0014)" $ do
        ws0 <- openWorkspace root
        let n0 = wsFullEvaluations ws0
            rest = "@label second\n# 次の章\n\n[ref-title intro]と[ref-page intro]を見る。\n"
        ws1 <- updateFile ws0 "b.gm" ("@style-def paragraph letter indent=1zw\n\n" <> rest)
        ws2 <- updateFile ws1 "b.gm" ("@style-def paragraph letter indent=2zw\n\n" <> rest)
        ws3 <- updateFile ws2 "b.gm" ("@style-def paragraph letter indent=2zw\n" <> rest)
        ws4 <- updateFile ws3 "b.gm" ("@style-def paragraph letter indent=3zw\n@manifest title=x\n" <> rest)
        wsFullEvaluations ws4 @?= n0,
      testCase "with a syntax error, completion and definition still work elsewhere" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n[ref-title intro]と[strong: 閉じない\n\n[ref-number \n"
        let src = textOf ws "b.gm"
        assertBool "has errors" (any ((== Error) . diagSeverity) (fromMaybe [] (Map.lookup "b.gm" (diagnosticsFor ws))))
        map locPath (definition ws "b.gm" (offsetIn src "intro]" 1)) @?= ["a.gm"]
        assertBool "labels" ("intro" `elem` map cmpLabel (completions ws "b.gm" (offsetIn src "[ref-number " 12))),
      testCase "a missing font leaves the manuscript diagnostics in place (golem-project ADR 0004)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        mapM_ (\f -> createDirectoryIfMissing True (takeDirectory (tmp </> f)) >> copyFile (root </> f) (tmp </> f)) ["manifest.toml", "style.toml", "a.gm", "b.gm", "common/values.gm"]
        BS.appendFile (tmp </> "style.toml") "\n[fonts.body]\nja = \"fonts/missing.otf\"\n"
        BS.appendFile (tmp </> "b.gm") (TE.encodeUtf8 "\n[strong: 閉じない\n")
        ws <- openWorkspace tmp
        assertBool "evaluated" (isJust (wsEvaluated ws))
        let diags = diagnosticsFor ws
        assertBool "syntax error in b.gm" (any ((== Error) . diagSeverity) (fromMaybe [] (Map.lookup "b.gm" diags)))
        let codes = [c | d <- concat (Map.elems diags), let DiagnosticCode c = diagCode d]
        assertBool (show codes) (all (`notElem` codes) ["G03006", "G03010", "G08002"]),
      testCase "a missing import is reported on the file of the @import (golem-project ADR 0006)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        mapM_ (\f -> copyFile (root </> f) (tmp </> f)) ["manifest.toml", "b.gm"]
        BS.writeFile (tmp </> "a.gm") "@import nope.gm as x\n"
        ws <- openWorkspace tmp
        let codesIn p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]
        codesIn "a.gm" @?= ["G03002"]
        codesIn "manifest.toml" @?= [],
      testCase "a style.toml error is reported on style.toml (golem-project ADR 0006)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        mapM_ (\f -> createDirectoryIfMissing True (takeDirectory (tmp </> f)) >> copyFile (root </> f) (tmp </> f)) ["manifest.toml", "a.gm", "b.gm", "common/values.gm"]
        BS.writeFile (tmp </> "style.toml") "[page]\nunknown = 1\n"
        ws <- openWorkspace tmp
        let codesIn p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]
        codesIn "style.toml" @?= ["G03006"]
        codesIn "manifest.toml" @?= [],
      testCase "a project file publishes its diagnostics in the order of the codes (golem-syntax ADR 0003)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTitle = "LSP", tmLanguage = "en"})
        BS.writeFile (tmp </> "a.gm") "@label unused\n# A\n\nSee [ref-title nope].\n"
        BS.writeFile (tmp </> "manifest.toml") manifest
        ws <- openWorkspace tmp
        assertBool "evaluated" (isJust (wsEvaluated ws))
        -- the G05004 of line 1 after the G04003 of line 4, an error of the assembly that keeps the book for lint
        codesOf ws "a.gm" @?= ["G04003", "G05004"],
      testCase "a notice is published as Information (golem-syntax ADR 0002)" $ do
        lspSeverity Notice @?= L.DiagnosticSeverity_Information
        lspSeverity Warning @?= L.DiagnosticSeverity_Warning
        lspSeverity Error @?= L.DiagnosticSeverity_Error,
      testCase "an info is published as Hint (docs/adr 0104)" $
        lspSeverity Info @?= L.DiagnosticSeverity_Hint,
      testCase "the infos of silence-info are not published, the others are (docs/adr 0104)" $ do
        let sp = SrcSpan (FileId 0) 0 1
            i1 = infoDiagnostic "G07047" sp "i1"
            i2 = infoDiagnostic "G07048" sp "i2"
            n = notice "G07047" sp "n"
            n2 = notice "G02063" sp "n2"
            e = diagnostic "G01001" Error sp "e"
        publishable (Set.singleton (DiagnosticCode "G02063")) (Set.singleton (DiagnosticCode "G07047")) [i1, i2, n, n2, e] @?= [i2, n, e],
      testCase "the notices of silence-notices are not published, the others are (golem-syntax ADR 0002)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTitle = "LSP", tmLanguage = "en"})
            codes ws = [(c, diagSeverity d) | d <- concat (Map.elems (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]
        BS.writeFile (tmp </> "a.gm") "[tcy: 10]\n\n@number 1\n# A\n"
        BS.writeFile (tmp </> "manifest.toml") manifest
        ws0 <- openWorkspace tmp
        codes ws0 @?= [("G02063", Notice), ("G04007", Notice), ("G03023", Notice)]
        BS.writeFile (tmp </> "manifest.toml") (manifest <> "\n[diagnostics]\nsilence-notices = [\"G02063\"]\n")
        ws1 <- openWorkspace tmp
        codes ws1 @?= [("G04007", Notice), ("G03023", Notice)],
      testCase "completion: the keys of meta and the roles of the manifest (docs/adr ADR 0033)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTitle = "LSP", tmExtra = "\n[[metadata.creators]]\nname = \"A\"\nrole = \"author\"\n\n[[metadata.contributors]]\nname = \"B\"\nrole = \"cover-designer\"\n\n[[metadata.printings]]\nedition = 1\nprinting = 1\ndate = 2026-10-16\n"})
            src = "[= meta.]\n\n[= join(meta.roles., \"、\")]\n" :: Text
        BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 src)
        BS.writeFile (tmp </> "manifest.toml") manifest
        ws <- openWorkspace tmp
        let names o = map cmpLabel (completions ws "a.gm" o)
        names (offsetIn src "[= meta." 8) @?= ["creators", "date", "id", "language", "printing", "printings", "roles", "title"]
        names (offsetIn src "meta.roles." 11) @?= ["author", "cover_designer"],
      testCase "G05001 is not reported for the newlines of the line style (docs/adr ADR 0013)" $ withSystemTempDirectory "golem-lsp" $ \tmp -> do
        let manifest = TE.encodeUtf8 (manifestToml testManifest {tmTitle = "LSP", tmLanguage = "en"})
            g05001 ws = [c | d <- fromMaybe [] (Map.lookup "a.gm" (diagnosticsFor ws)), let DiagnosticCode c = diagCode d, c == "G05001"]
        BS.writeFile (tmp </> "a.gm") "Full fathom\nfive\n"
        BS.writeFile (tmp </> "manifest.toml") manifest
        ws0 <- openWorkspace tmp
        g05001 ws0 @?= ["G05001"]
        BS.writeFile (tmp </> "manifest.toml") (manifest <> "\n[source]\nparagraph-separator = \"line\"\n")
        ws1 <- openWorkspace tmp
        assertBool "evaluated" (isJust (wsEvaluated ws1))
        g05001 ws1 @?= [],
      testCase "only changes to headings, labels or exports re-evaluate the project" $ do
        ws0 <- openWorkspace root
        let n0 = wsFullEvaluations ws0
        ws1 <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n[ref-title intro]と[ref-page intro]を読む。\n"
        wsFullEvaluations ws1 @?= n0
        ws2 <- updateFile ws1 "b.gm" "@label second\n# 別の題\n\n[ref-title intro]と[ref-page intro]を読む。\n"
        wsFullEvaluations ws2 @?= n0 + 1
        ws3 <- updateFile ws2 "common/values.gm" "@set version = \"2.0\"\n"
        wsFullEvaluations ws3 @?= n0 + 2
        hover ws3 "a.gm" (at ws3 "a.gm" "values.version" 2) @?= Just "2.0",
      testCase "hover: S0 values, S1 values, and page numbers left to S2" $ do
        ws <- openWorkspace root
        hover ws "a.gm" (at ws "a.gm" "1 + 2" 0) @?= Just "3"
        hover ws "a.gm" (at ws "a.gm" "doc.chapters" 0) @?= Just "2"
        fmap (T.isInfixOf "S2") (hover ws "b.gm" (at ws "b.gm" "[ref-page" 2)) @?= Just True,
      testCase "outline and formatting" $ do
        ws0 <- openWorkspace root
        map (\o -> (olTitle o, map olTitle (olChildren o))) (outline ws0 "a.gm") @?= [("はじめに", ["節"])]
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n\n\n[ref-title   intro]と[ref-page intro]を見る。\n"
        formatting ws "b.gm" @?= Just "@label second\n# 次の章\n\n[ref-title intro]と[ref-page intro]を見る。\n",
      -- golem-parser ADR 0010
      testCase "outline: an escaped character is the character, without the backslash" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "# a\\[b\n"
        map olTitle (outline ws "b.gm") @?= ["a[b"],
      testCase "UTF-8 and UTF-16 positions on a line with Japanese and a 4-byte character" $ do
        ws <- openWorkspace root
        let src = textOf ws "a.gm"
            li = mkLineIndex src
            off = offsetIn src "[ref-number" 0
            LineCol l _ = toLineCol Utf8 li off
            lineStart = off - lcColumn (toLineCol Utf8 li off)
            prefix = TE.decodeUtf8 (BS.take (off - lineStart) (BS.drop lineStart (TE.encodeUtf8 src)))
        lcColumn (toLineCol Utf8 li off) @?= BS.length (TE.encodeUtf8 prefix)
        lcColumn (toLineCol Utf16 li off) @?= T.length prefix + 1 -- the emoji is a surrogate pair
        fromLineCol Utf8 li (LineCol l (lcColumn (toLineCol Utf8 li off))) @?= Just off
        fromLineCol Utf16 li (LineCol l (lcColumn (toLineCol Utf16 li off))) @?= Just off
        fromLineCol Utf16 li (LineCol l (lcColumn (toLineCol Utf16 li off) - 1)) @?= Nothing, -- inside the pair
      testCase "columns past the line end clamp to the line end (ADR 0003)" $ do
        let li = mkLineIndex "漢字\nab"
        fromLineCol Utf8 li (LineCol 0 7) @?= Just 6
        fromLineCol Utf8 li (LineCol 0 1000) @?= Just 6
        fromLineCol Utf16 li (LineCol 0 3) @?= Just 6
        fromLineCol Utf16 li (LineCol 0 1000) @?= Just 6
        fromLineCol Utf16 li (LineCol 0 2) @?= Just 6
        fromLineCol Utf8 li (LineCol 1 5) @?= Just 9
        fromLineCol Utf8 li (LineCol 2 0) @?= Nothing
        fromLineCol Utf16 li (LineCol 2 0) @?= Nothing
        fromLineCol Utf8 li (LineCol 0 1) @?= Nothing
        let emoji = mkLineIndex "😀a"
        fromLineCol Utf16 emoji (LineCol 0 1) @?= Nothing
        fromLineCol Utf16 emoji (LineCol 0 9) @?= Just 5,
      testProperty "a converted position lies within its line; only a position off the lines or inside a character has none (ADR 0003)" $ property $ do
        t <- forAll genText
        enc <- forAll (Gen.element [Utf8, Utf16])
        let li = mkLineIndex t
        l <- forAll (Gen.int (Range.linear (-1) (lineCount li)))
        c <- forAll (Gen.int (Range.linear 0 40))
        case fromLineCol enc li (LineCol l c) of
          Nothing -> do
            -- the columns between characters, counted from the text of the line (docs/adr/0066)
            let cols = characterBoundaries enc (T.splitOn "\n" t !! l)
            annotateShow cols
            H.assert (l < 0 || l >= lineCount li || (c < last cols && c `notElem` cols))
          Just o -> do
            let start = fromLineCol enc li (LineCol l 0)
            H.assert (maybe False (<= o) start)
            H.assert (maybe False (o <=) (lineEndOffset li l)),
      -- the oracle is independent of fromLineCol: the line end past the
      -- width, and within it the column back from the offset (docs/adr/0065)
      testProperty "past the line, fromLineCol is the line end; within it, the column comes back (ADR 0003)" $ property $ do
        t <- forAll genText
        enc <- forAll (Gen.element [Utf8, Utf16])
        let li = mkLineIndex t
        l <- forAll (Gen.int (Range.linear 0 (lineCount li - 1)))
        let end = fromMaybe 0 (lineEndOffset li l)
            width = lcColumn (toLineCol enc li end)
        c <- forAll (Gen.int (Range.linear 0 (width + 5)))
        case fromLineCol enc li (LineCol l c) of
          Just o
            | c > width -> o === end
            | otherwise -> toLineCol enc li o === LineCol l c
          Nothing -> H.assert (c <= width),
      testCase "the workspace keeps a line index per file and follows edits (ADR 0002)" $ do
        ws0 <- openWorkspace root
        lineCount (lineIndexOf ws0 "a.gm") @?= lineCount (mkLineIndex (textOf ws0 "a.gm"))
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n\n[ref-title intro]\n"
        lineCount (lineIndexOf ws "b.gm") @?= 6
        offsetToUtf8LineCol (lineIndexOf ws "b.gm") (offsetIn (textOf ws "b.gm") "intro" 0) @?= LineCol 4 11
        lineCount (lineIndexOf ws "nosuch.gm") @?= 1,
      testCase "the server prefers UTF-8 positions and falls back to UTF-16 (ADR 0002)" $ do
        chooseEncoding Nothing @?= Utf16
        chooseEncoding (Just []) @?= Utf16
        chooseEncoding (Just [L.PositionEncodingKind_UTF16]) @?= Utf16
        chooseEncoding (Just [L.PositionEncodingKind_UTF32]) @?= Utf16
        chooseEncoding (Just [L.PositionEncodingKind_UTF8]) @?= Utf8
        chooseEncoding (Just [L.PositionEncodingKind_UTF16, L.PositionEncodingKind_UTF8]) @?= Utf8
        encodingKind Utf8 @?= L.PositionEncodingKind_UTF8
        encodingKind Utf16 @?= L.PositionEncodingKind_UTF16,
      testCase "only the matching initialize response gets its positionEncoding replaced (ADR 0002)" $ do
        let resp = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-16\",\"hoverProvider\":true},\"serverInfo\":{\"name\":\"x\"}}}"
            expected = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-8\",\"hoverProvider\":true},\"serverInfo\":{\"name\":\"x\"}}}"
            decode = J.decode :: BL.ByteString -> Maybe J.Value
        (decode =<< rewriteInitializeResponse (M.IdInt 1) Utf8 resp) @?= decode expected
        rewriteInitializeResponse (M.IdInt 2) Utf8 resp @?= Nothing
        rewriteInitializeResponse (M.IdInt 1) Utf8 "{\"jsonrpc\":\"2.0\",\"method\":\"window/logMessage\",\"params\":{\"type\":3,\"message\":\"m\"}}" @?= Nothing
        rewriteInitializeResponse (M.IdInt 1) Utf8 "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32600,\"message\":\"m\"}}" @?= Nothing,
      withResource (session utf16Session) (const (pure ())) $ \s16 ->
        withResource (session utf8Session) (const (pure ())) $ \s8 ->
          testGroup
            "protocol"
            [ goldenVsString "protocol: hover, definition, symbols, diagnostics" "test/golden/protocol.txt" (render <$> s16),
              goldenVsString "protocol in utf-8 (ADR 0002)" "test/golden/protocol-utf8.txt" (render <$> s8),
              testCase "utf-8 columns of a diagnostic exceed utf-16 by the emoji's 2 units (ADR 0002)" $ do
                r16 <- s16
                r8 <- s8
                map (+ 2) (srMissingLabelColumns r16) @?= srMissingLabelColumns r8
                assertBool "has a G04003" (not (null (srMissingLabelColumns r8))),
              testCase "utf-8 hover inside a character returns null (ADR 0002)" $ do
                r8 <- s8
                srInsideHover r8 @?= Just Nothing,
              testCase "completion past the line end clamps to the line end (ADR 0003)" $ do
                r16 <- s16
                r8 <- s8
                srClampCompletions r16 @?= (["accent"], ["accent"])
                srClampCompletions r8 @?= (["accent"], ["accent"]),
              testCase "hover past the line end equals hover at the line end (ADR 0003)" $ do
                r16 <- s16
                r8 <- s8
                uncurry (@?=) (srClampHover r16)
                uncurry (@?=) (srClampHover r8)
            ],
      editingTests,
      tableWatchTests,
      staleS1Tests
    ]

data SessionSpec = SessionSpec
  { ssEncodings :: [L.PositionEncodingKind],
    ssHover :: L.Position,
    ssDefinition :: L.Position,
    ssInside :: Maybe L.Position
  }

-- | Positions on a.gm line 5, which has Japanese and an emoji before them.
utf16Session, utf8Session :: SessionSpec
utf16Session = SessionSpec [L.PositionEncodingKind_UTF16] (L.Position 5 18) (L.Position 5 75) Nothing
utf8Session = SessionSpec [L.PositionEncodingKind_UTF8, L.PositionEncodingKind_UTF16] (L.Position 5 22) (L.Position 5 97) (Just (L.Position 5 1))

data SessionResult = SessionResult
  { srLines :: [String],
    srMissingLabelColumns :: [L.UInt],
    srInsideHover :: Maybe (Maybe Text),
    -- | completions on b.gm "[color " at the line end and at column 1000
    srClampCompletions :: ([Text], [Text]),
    -- | hover on a.gm line 5 at column 1000 and at the line end
    srClampHover :: (Maybe Text, Maybe Text)
  }

render :: SessionResult -> BL.ByteString
render r = BL.fromStrict (TE.encodeUtf8 (T.pack (unlines (srLines r))))

withEncodings :: [L.PositionEncodingKind] -> L.ClientCapabilities -> L.ClientCapabilities
withEncodings encs (L.ClientCapabilities w t n win gen ex) =
  let L.GeneralClientCapabilities st re md _ = fromMaybe (L.GeneralClientCapabilities Nothing Nothing Nothing Nothing) gen
   in L.ClientCapabilities w t n win (Just (L.GeneralClientCapabilities st re md (Just encs))) ex

-- | A client session against the server over pipes.
session :: SessionSpec -> IO SessionResult
session spec = do
  absRoot <- makeAbsolute root
  aSource <- TE.decodeUtf8 <$> BS.readFile (root </> "a.gm")
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
  r <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig (withEncodings (ssEncodings spec) LT.fullLatestClientCaps) absRoot $ do
    initResp <- LT.initializeResponse
    doc <- LT.openDoc "a.gm" "golem"
    h <- LT.getHover doc (ssHover spec)
    inside <- traverse (fmap (fmap hoverText) . LT.getHover doc) (ssInside spec)
    let line5 = T.lines aSource !! 5
        line5End
          | L.PositionEncodingKind_UTF8 `elem` ssEncodings spec = BS.length (TE.encodeUtf8 line5)
          | otherwise = T.length line5 + T.count "😀" line5
    farHover <- fmap hoverText <$> LT.getHover doc (L.Position 5 1000)
    endHover <- fmap hoverText <$> LT.getHover doc (L.Position 5 (fromIntegral line5End))
    defs <- LT.getDefinitions doc (ssDefinition spec)
    syms <- LT.getDocumentSymbols doc
    refs <- LT.getReferences doc (L.Position 2 8) True
    LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "# 見出し\n\n😀[strong: 閉じない\n"))]
    diags <- LT.waitForDiagnosticsSource "golem"
    LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "😀[ref-title nosuch]\n"))]
    missing <- missingLabel (absRoot </> "a.gm")
    bdoc <- LT.openDoc "b.gm" "golem"
    LT.changeDoc bdoc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "[color \n"))]
    _ <- errorsFor (absRoot </> "b.gm")
    atEnd <- completionLabels <$> LT.getCompletions bdoc (L.Position 0 7)
    far <- completionLabels <$> LT.getCompletions bdoc (L.Position 0 1000)
    pure
      SessionResult
        { srLines =
            [ "diagnostics: " <> show [(d ^. diagRange, d ^. diagCode) | d <- diags],
              "codeDescription: " <> show [fmap (\(L.CodeDescription (L.Uri u)) -> u) (d ^. diagCodeDescription) | d <- diags],
              "hover: " <> show (fmap hoverText h),
              "definition: " <> show (defTargets absRoot defs),
              "symbols: " <> concat [T.unpack n <> "(" <> T.unpack (T.intercalate "," cs) <> ")" | (n, cs) <- symbolNames syms],
              "positionEncoding: " <> show (positionEncoding initResp),
              "references: " <> show [(fmap (drop (length absRoot + 1)) (L.uriToFilePath u), rng) | L.Location u rng <- refs],
              "missing label: " <> show [(d ^. diagRange, d ^. diagCode) | d <- missing]
            ]
              <> maybe [] (\i -> ["hover inside a character: " <> show i]) inside,
          srMissingLabelColumns = [c | d <- missing, let L.Range (L.Position _ c) _ = d ^. diagRange],
          srInsideHover = inside,
          srClampCompletions = (atEnd, far),
          srClampHover = (farHover, endHover)
        }
  hClose clientOut
  pure r
  where
    (^.) x f = f x
    diagRange (L.Diagnostic rng _ _ _ _ _ _ _ _) = rng
    diagCode (L.Diagnostic _ _ c _ _ _ _ _ _) = c
    diagCodeDescription (L.Diagnostic _ _ _ cd _ _ _ _ _) = cd
    startLine d = let L.Range (L.Position l _) _ = diagRange d in l
    hoverText (L.Hover (L.InL (L.MarkupContent _ t)) _) = t
    hoverText _ = ""
    positionEncoding (M.TResponseMessage _ _ res) = case res of
      Right (L.InitializeResult (L.ServerCapabilities pe _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _) _) -> pe
      Left _ -> Nothing
    defTargets absRoot = \case
      L.InR (L.InL links) -> [(fmap (drop (length absRoot + 1)) (L.uriToFilePath u), rng) | L.DefinitionLink (L.LocationLink _ u rng _) <- links]
      _ -> []
    symbolNames = \case
      Right ds -> [(n, [c | L.DocumentSymbol c _ _ _ _ _ _ _ <- fromMaybe [] kids]) | L.DocumentSymbol n _ _ _ _ _ _ kids <- ds]
      Left _ -> []
    completionLabels = map (\(L.CompletionItem lbl _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _) -> lbl)
    -- the diagnostics of the one-line b.gm: published for it, with
    -- nothing on a later line left over from its previous content
    errorsFor :: FilePath -> LT.Session [L.Diagnostic]
    errorsFor path = do
      msg <- LT.anyMessage
      case msg of
        M.FromServerMess M.SMethod_TextDocumentPublishDiagnostics (M.TNotificationMessage _ _ (L.PublishDiagnosticsParams u _ ds))
          | L.uriToFilePath u == Just path,
            all ((== 0) . startLine) ds ->
              pure ds
        _ -> errorsFor path
    -- the G04003 diagnostics published for the given file
    missingLabel :: FilePath -> LT.Session [L.Diagnostic]
    missingLabel path = do
      msg <- LT.anyMessage
      case msg of
        M.FromServerMess M.SMethod_TextDocumentPublishDiagnostics (M.TNotificationMessage _ _ (L.PublishDiagnosticsParams u _ ds))
          | L.uriToFilePath u == Just path,
            found@(_ : _) <- [d | d <- ds, diagCode d == Just (L.InR "G04003")] ->
              pure found
        _ -> missingLabel path

-- | The codes of the diagnostics of a file.
codesOf :: Workspace -> FilePath -> [Text]
codesOf ws p = [c | d <- fromMaybe [] (Map.lookup p (diagnosticsFor ws)), let DiagnosticCode c = diagCode d]

{- | The LSP fixture with the identity plugin of golem-plugin's tests
declared, locked and cached (docs/adr ADR 0031).
-}
withIdentityPlugin :: (FilePath -> IO a) -> IO a
withIdentityPlugin k = withSystemTempDirectory "golem-lsp-plugin" $ \tmp -> do
  let copyDir from to = do
        createDirectoryIfMissing True to
        entries <- listDirectory from
        mapM_ (\e -> doesDirectoryExist (from </> e) >>= \d -> if d then copyDir (from </> e) (to </> e) else copyFile (from </> e) (to </> e)) entries
  copyDir root tmp
  BS.appendFile (tmp </> "manifest.toml") "\n[plugins.identity]\nurl = \"https://example.com/identity.wasm\"\n"
  src <- TIO.readFile "../golem-plugin/test/plugins/identity.wat"
  wasm <- watToWasm src >>= either (assertFailure . T.unpack) pure
  withEnv "XDG_CACHE_HOME" (tmp </> "cache") $ do
    cache <- defaultCacheDir
    r <- lockPlugins (\u -> pure (if u == "https://example.com/identity.wasm" then Right wasm else Left "404")) cache (Map.fromList [("identity", "https://example.com/identity.wasm")])
    either (assertFailure . show) (TIO.writeFile (tmp </> "plugins.lock") . renderLock) r
    k tmp
