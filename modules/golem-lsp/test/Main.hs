module Main (main) where

import Control.Concurrent (forkIO)
import Control.Monad (void)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features
import Golem.Lsp.Server (serverDefinition)
import Golem.Lsp.Workspace
import Golem.Syntax
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Server (runServerWithHandles)
import Language.LSP.Test qualified as LT
import System.Directory (makeAbsolute)
import System.IO (hClose)
import System.Process (createPipe)
import Test.Tasty
import Test.Tasty.Golden (goldenVsString)
import Test.Tasty.HUnit

root :: FilePath
root = "test/fixtures/proj"

main :: IO ()
main = defaultMain tests

-- | Byte offset of the k-th byte inside the first occurrence of needle.
offsetIn :: Text -> Text -> Int -> Int
offsetIn src needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src))) + k

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
    [ testCase "definition: label across files, import path, namespaced variable" $ do
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
      testCase "with a syntax error, completion and definition still work elsewhere" $ do
        ws0 <- openWorkspace root
        ws <- updateFile ws0 "b.gm" "@label second\n# 次の章\n\n[ref-title intro]と[strong: 閉じない\n\n[ref-number \n"
        let src = textOf ws "b.gm"
        assertBool "has errors" (any ((== Error) . diagSeverity) (fromMaybe [] (Map.lookup "b.gm" (diagnosticsFor ws))))
        map locPath (definition ws "b.gm" (offsetIn src "intro]" 1)) @?= ["a.gm"]
        assertBool "labels" ("intro" `elem` map cmpLabel (completions ws "b.gm" (offsetIn src "[ref-number " 12))),
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
      goldenVsString "protocol: hover, definition, symbols, diagnostics" "test/golden/protocol.txt" protocol
    ]

-- | A client session against the server over pipes.
protocol :: IO BL.ByteString
protocol = do
  absRoot <- makeAbsolute root
  (serverIn, clientOut) <- createPipe
  (clientIn, serverOut) <- createPipe
  def <- serverDefinition
  void (forkIO (void (runServerWithHandles mempty mempty serverIn serverOut def)))
  out <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig LT.fullLatestClientCaps absRoot $ do
    doc <- LT.openDoc "a.gm" "golem"
    h <- LT.getHover doc (L.Position 5 18)
    defs <- LT.getDefinitions doc (L.Position 5 75)
    syms <- LT.getDocumentSymbols doc
    LT.changeDoc doc [L.TextDocumentContentChangeEvent (L.InR (L.TextDocumentContentChangeWholeDocument "# 見出し\n\n😀[strong: 閉じない\n"))]
    diags <- LT.waitForDiagnosticsSource "golem"
    pure
      [ "diagnostics: " <> show [(d ^. diagRange, d ^. diagCode) | d <- diags],
        "hover: " <> show (fmap hoverText h),
        "definition: " <> show (defTargets absRoot defs),
        "symbols: " <> concat [T.unpack n <> "(" <> T.unpack (T.intercalate "," cs) <> ")" | (n, cs) <- symbolNames syms]
      ]
  hClose clientOut
  pure (BL.fromStrict (TE.encodeUtf8 (T.pack (unlines out))))
  where
    (^.) x f = f x
    diagRange (L.Diagnostic r _ _ _ _ _ _ _ _) = r
    diagCode (L.Diagnostic _ _ c _ _ _ _ _ _) = c
    hoverText (L.Hover (L.InL (L.MarkupContent _ t)) _) = t
    hoverText _ = ""
    defTargets absRoot = \case
      L.InR (L.InL links) -> [(fmap (drop (length absRoot + 1)) (L.uriToFilePath u), r) | L.DefinitionLink (L.LocationLink _ u r _) <- links]
      _ -> []
    symbolNames = \case
      Right ds -> [(n, [c | L.DocumentSymbol c _ _ _ _ _ _ _ <- fromMaybe [] kids]) | L.DocumentSymbol n _ _ _ _ _ _ kids <- ds]
      Left _ -> []
