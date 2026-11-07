{-# LANGUAGE GADTs #-}

-- | The language server and the functions of .emet (docs/adr/0162, docs/adr/0170).
module FunctionsLspSpec (functionsLspTests) where

import Control.Concurrent (forkIO)
import Control.Monad (forM_, void)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString qualified as BS
import Data.Either (isRight)
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features
import Golem.Lsp.Server (runGolemLspWithHandles)
import Golem.Lsp.Workspace
import Golem.TestSupport.Gen (genText)
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Language.LSP.Protocol.Message qualified as M
import Language.LSP.Protocol.Types qualified as L
import Language.LSP.Test qualified as LT
import Support (codesOf)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose)
import System.IO.Temp (withSystemTempDirectory)
import System.Process (createPipe)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

bookEmet :: Text
bookEmet =
  T.unlines
    [ "import \"fn/lib.emet\"",
      "",
      "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
      "taxIncluded n = Inline.text (String.fromNat (twice n))",
      "",
      "pub block rule :: Blocks",
      "rule = Block.paragraph (Inline.text \"――\")",
      "",
      "pub fn total :: List Nat -> <file \"w.tsv\"> Nat",
      "total xs = List.length xs + String.length (File.read \"w.tsv\")",
      "",
      "pub filter tidy :: Blocks -> Blocks",
      "tidy bs = bs"
    ]

libEmet :: Text
libEmet = "pub twice :: Nat -> Nat\ntwice n = n * 2\n"

chapter :: Text
chapter = "@import fn/book.emet as book\n\n[book.tax-included 1000]\n\n@book.rule\n\n[= book.total([1])]\n"

manifestText :: Text
manifestText = manifestToml testManifest {tmChapters = ["a.gm"]} <> "\n[functions.requires]\nfile = [\"w.tsv\"]\n\n[[filters]]\nfunction = \"fn/book.emet\"\nfilter = \"tidy\"\nfiles = [\"a.gm\"]\n"

-- | A project of a.gm and the two .emet, the workspace opened on it.
withFunctions :: (FilePath -> Workspace -> IO a) -> IO a
withFunctions act = withSystemTempDirectory "golem-lsp-functions" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  let files =
        [ ("manifest.toml", TE.encodeUtf8 manifestText),
          ("a.gm", TE.encodeUtf8 chapter),
          ("fn/book.emet", TE.encodeUtf8 bookEmet),
          ("fn/lib.emet", TE.encodeUtf8 libEmet),
          ("w.tsv", "w\n")
        ]
  forM_ files $ \(p, bytes) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) bytes
  ws <- openWorkspace tmp
  act tmp ws

-- | The offset of a needle in a text, and a number of bytes further.
offsetIn :: Text -> Text -> Int -> Int
offsetIn text needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle text))) + k

functionsLspTests :: TestTree
functionsLspTests =
  testGroup
    "the functions of .emet (docs/adr/0162)"
    [ testCase "the project with functions has no diagnostics" $
        withFunctions $ \_ ws -> do
          codesOf ws "a.gm" @?= []
          codesOf ws "fn/book.emet" @?= [],
      testCase "completion in a .emet: the variables of the patterns, the names of a built-in module, the requirements" $
        withFunctions $ \_ ws -> do
          let names o = map cmpLabel (completions ws "fn/book.emet" o)
          assertBool "n and twice" (all (`elem` names (offsetIn bookEmet "(twice n)" 7)) ["n", "twice", "taxIncluded", "List"])
          assertBool "List.length" ("length" `elem` names (offsetIn bookEmet "List.length" 5))
          names (offsetIn bookEmet "<file" 1) @?= ["file"],
      testCase "completion in a .gm after a namespace of a .emet" $
        withFunctions $ \_ ws -> do
          let text = chapter <> "\n[book."
          ws' <- updateFile ws "a.gm" text
          map cmpLabel (completions ws' "a.gm" (BS.length (TE.encodeUtf8 text))) @?= ["tax-included"]
          let block = chapter <> "\n@book."
          ws'' <- updateFile ws "a.gm" block
          map cmpLabel (completions ws'' "a.gm" (BS.length (TE.encodeUtf8 block))) @?= ["rule"]
          let expr = chapter <> "\n[= book."
          ws3 <- updateFile ws "a.gm" expr
          map cmpLabel (completions ws3 "a.gm" (BS.length (TE.encodeUtf8 expr))) @?= ["total"],
      testCase "definition: from a command of .gm to the .emet, and in a .emet to an import" $
        withFunctions $ \_ ws -> do
          map locPath (definition ws "a.gm" (offsetIn chapter "book.tax-included" 6)) @?= ["fn/book.emet"]
          map locStart (definition ws "a.gm" (offsetIn chapter "book.tax-included" 6)) @?= [offsetIn bookEmet "taxIncluded ::" 0]
          map locPath (definition ws "a.gm" (offsetIn chapter "book.total" 6)) @?= ["fn/book.emet"]
          map locPath (definition ws "fn/book.emet" (offsetIn bookEmet "twice n" 1)) @?= ["fn/lib.emet"],
      testCase "references: the calls in .gm of a function of a .emet" $
        withFunctions $ \_ ws -> do
          map locPath (references ws "fn/book.emet" (offsetIn bookEmet "taxIncluded ::" 1)) @?= ["a.gm"]
          map locPath (references ws "a.gm" (offsetIn chapter "book.rule" 2)) @?= ["a.gm"],
      testCase "hover: the signature with its requirements in .gm, and the type in a .emet" $
        withFunctions $ \_ ws -> do
          hover ws "a.gm" (offsetIn chapter "book.total" 3) @?= Just "pub fn total :: List Nat -> <file \"w.tsv\"> Nat"
          hover ws "fn/book.emet" (offsetIn bookEmet "List.length" 6) @?= Just "length :: List a -> Nat"
          hover ws "fn/book.emet" (offsetIn bookEmet "twice n)" 1) @?= Just "twice :: Nat -> Nat",
      testCase "an edit of a .emet evaluates the .gm again, and its diagnostics are published" $
        withFunctions $ \_ ws -> do
          ws' <- updateFile ws "fn/book.emet" (T.replace "pub block rule" "pub block line" (T.replace "\nrule =" "\nline =" bookEmet))
          codesOf ws' "a.gm" @?= ["G02009"]
          ws'' <- updateFile ws "fn/book.emet" (bookEmet <> "\nbroken :: Nat\nbroken = \"x\"\n")
          codesOf ws'' "a.gm" @?= []
          assertBool "an error in the .emet" (not (null (codesOf ws'' "fn/book.emet"))),
      testCase "formatting of a .emet" $
        withFunctions $ \_ ws -> do
          ws' <- updateFile ws "fn/lib.emet" (libEmet <> "\n\n\n")
          formatting ws' "fn/lib.emet" @?= Just libEmet,
      renameTests,
      testCase "hover: the type of a local name in a .emet (docs/adr/0170)" $
        withFunctions $ \_ ws -> do
          hover ws "fn/book.emet" (offsetIn bookEmet "twice n" 6) @?= Just "n :: Nat"
          hover ws "fn/book.emet" (offsetIn bookEmet "xs +" 0) @?= Just "xs :: List Nat"
          ws' <- updateFile ws "fn/book.emet" (bookEmet <> "\nbroken :: Nat\nbroken = \"x\"\n")
          hover ws' "fn/book.emet" (offsetIn bookEmet "xs +" 0) @?= Nothing,
      tokenTests,
      sessionTests
    ]

-- | The texts of the files after the edits of a renaming.
applyAll :: [(Location, Text)] -> [(FilePath, Text)] -> [(FilePath, Text)]
applyAll edits files = [(p, apply t [(locStart l, locEnd l, n) | (l, n) <- edits, locPath l == p]) | (p, t) <- files]
  where
    apply t es =
      let bytes = TE.encodeUtf8 t
          go from = \case
            [] -> [BS.drop from bytes]
            (s, e, n) : rest -> BS.take (s - from) (BS.drop from bytes) : TE.encodeUtf8 n : go e rest
       in TE.decodeUtf8 (BS.concat (go 0 (sortOn (\(s, _, _) -> s) es)))

renameTests :: TestTree
renameTests =
  testGroup
    "renaming a name of a .emet (docs/adr/0170)"
    [ testCase "a pub fn: its declaration and the calls of the expressions of .gm" $
        withFunctions $ \_ ws -> do
          edits <- either (assertFailure . show) pure (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "total ::" 0) "amount")
          let rewritten = applyAll edits [("a.gm", chapter), ("fn/book.emet", bookEmet), ("manifest.toml", manifestText)]
          lookup "a.gm" rewritten @?= Just (T.replace "book.total(" "book.amount(" chapter)
          lookup "fn/book.emet" rewritten @?= Just (T.replace "total" "amount" bookEmet)
          lookup "manifest.toml" rewritten @?= Just manifestText,
      testCase "a pub inline with a string name: .gm keeps its name" $
        withFunctions $ \_ ws -> do
          edits <- either (assertFailure . show) pure (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "taxIncluded ::" 0) "withTax")
          map (locPath . fst) edits @?= ["fn/book.emet", "fn/book.emet"],
      testCase "a pub block without a string name: the commands of .gm" $
        withFunctions $ \_ ws -> do
          edits <- either (assertFailure . show) pure (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "rule ::" 0) "line")
          lookup "a.gm" (applyAll edits [("a.gm", chapter)]) @?= Just (T.replace "@book.rule" "@book.line" chapter),
      testCase "a pub filter without a string name: the filter of [[filters]]" $
        withFunctions $ \_ ws -> do
          edits <- either (assertFailure . show) pure (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "tidy ::" 0) "clean")
          lookup "manifest.toml" (applyAll edits [("manifest.toml", manifestText)]) @?= Just (T.replace "filter = \"tidy\"" "filter = \"clean\"" manifestText),
      testCase "a function imported: the file that declares it and the file that imports it" $
        withFunctions $ \_ ws -> do
          edits <- either (assertFailure . show) pure (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "twice n" 0) "double")
          applyAll edits [("fn/book.emet", bookEmet), ("fn/lib.emet", libEmet)] @?= [("fn/book.emet", T.replace "twice" "double" bookEmet), ("fn/lib.emet", T.replace "twice" "double" libEmet)],
      testCase "a name not of the rules of .gm for a command, a reserved word: an error" $
        withFunctions $ \_ ws -> do
          either renameMessage (const "") (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "rule ::" 0) "ruleTwo") @?= ".gm のコマンドの名前は、英小文字で始まり、英小文字と数字だけで書きます: ruleTwo"
          either renameMessage (const "") (renameEmet ws (Just manifestText) "fn/book.emet" (offsetIn bookEmet "xs =" 0) "case") @?= "予約語です: case",
      testCase "a file that does not check: the names of the program last checked" $
        withFunctions $ \_ ws -> do
          let broken = bookEmet <> "\nbroken :: Nat\nbroken = \"x\"\n"
          ws' <- updateFile ws "fn/book.emet" broken
          edits <- either (assertFailure . show) pure (renameEmet ws' (Just manifestText) "fn/book.emet" (offsetIn broken "total ::" 0) "amount")
          lookup "a.gm" (applyAll edits [("a.gm", chapter)]) @?= Just (T.replace "book.total(" "book.amount(" chapter)
    ]

tokenTests :: TestTree
tokenTests =
  testGroup
    "semantic tokens of a .emet (docs/adr/0170)"
    [ testCase "columns after Japanese text in the negotiated unit" $ do
        let src = "f :: String\nf = \"あ😀\" ++ g\n"
            toks enc = [(l, c, n, t) | L.SemanticTokenAbsolute l c n t _ <- emetSemanticTokens enc src, l == 1]
        toks Utf8 @?= [(1, 0, 1, L.SemanticTokenTypes_Function), (1, 2, 1, L.SemanticTokenTypes_Operator), (1, 4, 9, L.SemanticTokenTypes_String), (1, 14, 2, L.SemanticTokenTypes_Operator), (1, 17, 1, L.SemanticTokenTypes_Variable)]
        toks Utf16 @?= [(1, 0, 1, L.SemanticTokenTypes_Function), (1, 2, 1, L.SemanticTokenTypes_Operator), (1, 4, 5, L.SemanticTokenTypes_String), (1, 10, 2, L.SemanticTokenTypes_Operator), (1, 13, 1, L.SemanticTokenTypes_Variable)],
      testCase "the names of declarations have the modifier declaration" $ do
        [m | L.SemanticTokenAbsolute 0 0 _ _ m <- emetSemanticTokens Utf8 "f :: Nat\nf = 1\n"] @?= [[L.SemanticTokenModifiers_Declaration]],
      testProperty "tokens are in document order, do not overlap, and encode with the default legend" . property $ do
        src <- forAll (Gen.choice [genText, genEmet])
        let ts = [(l, c, n, t, m) | L.SemanticTokenAbsolute l c n t m <- emetSemanticTokens Utf16 src]
            ordered = and (zipWith before ts (drop 1 ts))
            before (l1, c1, n1, _, _) (l2, c2, _, _, _) = l1 < l2 || (l1 == l2 && c1 + n1 <= c2)
        (ordered, all (\(_, _, n, _, _) -> n > 0) ts) === (True, True)
        isRight (L.makeSemanticTokens L.defaultSemanticTokensLegend [L.SemanticTokenAbsolute l c n t m | (l, c, n, t, m) <- ts]) === True
    ]
  where
    genEmet = T.unlines <$> Gen.list (Range.linear 0 20) (Gen.element (T.lines bookEmet <> T.lines libEmet <> ["  where {", "    g y = case y of {", "      Just z -> z -- コメント😀", "    }", "  }", "data T a = A | B { b :: Nat }", "f x = (x", "\"閉じない"]))

-- | A client session against the server over pipes, in the project of the functions.
sessionTests :: TestTree
sessionTests =
  testCase "a session: semantic tokens, symbols, hover and renaming of a .emet" $
    withFunctions $ \dir _ -> do
      (serverIn, clientOut) <- createPipe
      (clientIn, serverOut) <- createPipe
      void (forkIO (void (runGolemLspWithHandles serverIn serverOut)))
      (tokens, names, hovered, renamedFiles) <- LT.runSessionWithHandles clientOut clientIn LT.defaultConfig LT.fullLatestClientCaps dir $ do
        doc <- LT.openDoc "fn/book.emet" "emet"
        rsp <- LT.request M.SMethod_TextDocumentSemanticTokensFull (L.SemanticTokensParams Nothing Nothing doc)
        let tokens = case rsp of
              M.TResponseMessage _ _ (Right (L.InL (L.SemanticTokens _ ds))) -> length ds `div` 5
              _ -> 0
        syms <- LT.getDocumentSymbols doc
        let names = case syms of
              Right ds -> [n | L.DocumentSymbol n _ _ _ _ _ _ _ <- ds]
              Left _ -> []
        h <- LT.getHover doc (L.Position 3 12)
        let hovered = case h of
              Just (L.Hover (L.InL (L.MarkupContent _ t)) _) -> Just t
              _ -> Nothing
        edit <- LT.request M.SMethod_TextDocumentRename (L.RenameParams Nothing doc (L.Position 8 7) "amount")
        let renamedFiles = case edit of
              M.TResponseMessage _ _ (Right (L.InL (L.WorkspaceEdit (Just changes) _ _))) -> [drop (length dir + 1) p | u <- Map.keys changes, Just p <- [L.uriToFilePath u]]
              _ -> []
        liftIO (pure ())
        pure (tokens, names, hovered, sortOn id renamedFiles)
      hClose clientOut
      assertBool "tokens" (tokens > 10)
      names @?= ["fn/lib.emet", "taxIncluded", "rule", "total", "tidy"]
      hovered @?= Just "n :: Nat"
      renamedFiles @?= ["a.gm", "fn/book.emet"]
