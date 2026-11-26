-- | The aliases of the names listed by @import in the language server (root ADR 0458).
module AliasLspSpec (aliasLspTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (nub, sort, sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Eval.File (EvalResult (..))
import Golem.Evaluate (Evaluated (..))
import Golem.Lsp.Features
import Golem.Lsp.Workspace
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.TestSupport.Manifest (TestManifest (..), manifestToml, testManifest)
import Support (codesOf)
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

bookEmet :: Text
bookEmet =
  T.unlines
    [ "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
      "taxIncluded n = Inline.text (String.fromNat n)",
      "",
      "pub block rule :: Blocks",
      "rule = Block.paragraph (Inline.text \"――\")",
      "",
      "pub fn total :: List Nat -> Nat",
      "total xs = List.length xs"
    ]

-- | v.gm: the variable price.
vText :: Text
vText = "@set price = 1\n"

-- | a.gm: each kind under an alias, and total under itself too.
aText :: Text
aText =
  T.concat
    [ "@import fn/book.emet { tax-included as tax, rule as line, total as sum, total }\n",
      "@import v.gm { price as cost }\n",
      "\n[tax 1000]\n",
      "\n@line\n",
      "\n[= sum([1]) + total([2]) + cost]\n"
    ]

-- | b.gm: lists price without an alias.
bText :: Text
bText = "@import v.gm { price }\n\n[= price]\n"

baseFiles :: [(FilePath, Text)]
baseFiles = [("a.gm", aText), ("b.gm", bText), ("v.gm", vText), ("fn/book.emet", bookEmet)]

withProject :: [(FilePath, Text)] -> (FilePath -> Workspace -> IO a) -> IO a
withProject files act = withSystemTempDirectory "golem-lsp-alias" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  writeAll tmp (("manifest.toml", manifestToml testManifest {tmChapters = ["a.gm", "b.gm"]}) : files)
  ws <- openWorkspace tmp
  act tmp ws

writeAll :: FilePath -> [(FilePath, Text)] -> IO ()
writeAll tmp files = forM_ files $ \(p, t) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) (TE.encodeUtf8 t)

-- | The offset of a needle in a text, and a number of bytes further.
offsetIn :: Text -> Text -> Int -> Int
offsetIn text needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle text))) + k

-- | A place of a needle of a file: from its offset to its end.
place :: FilePath -> Text -> Text -> Int -> Int -> (FilePath, Int, Int)
place p text needle k n = (p, offsetIn text needle k, offsetIn text needle k + n)

places :: [(Location, Text)] -> [(FilePath, Int, Int)]
places es = sort [(locPath l, locStart l, locEnd l) | (l, _) <- es]

locs :: [Location] -> [(FilePath, Int, Int)]
locs ls = sort (nub [(locPath l, locStart l, locEnd l) | l <- ls])

-- | The texts of the files after the edits.
applied :: [(FilePath, Text)] -> [(Location, Text)] -> [(FilePath, Text)]
applied files es = [(p, foldr edit t (sortOn (locStart . fst) [e | e@(l, _) <- es, locPath l == p])) | (p, t) <- files]
  where
    edit (l, new) t =
      let b = TE.encodeUtf8 t
       in TE.decodeUtf8 (BS.take (locStart l) b <> TE.encodeUtf8 new <> BS.drop (locEnd l) b)

-- | The codes of the diagnostics of the project and the documents of its files.
outcome :: Workspace -> ([Text], [String])
outcome ws = case wsEvaluated ws of
  Just ev -> (sort (nub [c | d <- evDiagnostics ev, let DiagnosticCode c = diagCode d]), map (show . erDocument) (Map.elems (evResults ev)))
  Nothing -> ([], [])

renamedAlias :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> IO [(Location, Text)]
renamedAlias ws style p off new = either (\e -> assertFailure (T.unpack (renameMessage e)) >> pure []) pure (renameAlias ws style p off new)

refusedAlias :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> Assertion
refusedAlias ws style p off new = case renameAlias ws style p off new of
  Left NotAnAlias -> assertFailure "not an alias"
  Left _ -> pure ()
  Right es -> assertFailure ("renamed: " <> show (places es))

-- | The completions at the end of a.gm with a text after it.
completedAfter :: Workspace -> Text -> IO [Text]
completedAfter ws more = do
  let text = aText <> more
  ws' <- updateFile ws "a.gm" text
  pure (sort (map cmpLabel (completions ws' "a.gm" (BS.length (TE.encodeUtf8 text)))))

-- | A running head of style.toml with a format.
runningHead :: Text -> Maybe Text
runningHead fmt = Just ("[masters.body]\nrunning-head = { position = \"top-outside\", format = \"" <> fmt <> "\" }\n")

-- | The places of the alias sum: in the list and in the call.
sumPlaces :: [(FilePath, Int, Int)]
sumPlaces = sort [place "a.gm" aText "sum," 0 3, place "a.gm" aText "sum([1])" 0 3]

aliasLspTests :: TestTree
aliasLspTests =
  testGroup
    "the aliases of the listed names (root ADR 0458)"
    [ testCase "root ADR 0458 I1: the project with aliases has no diagnostics" $
        withProject baseFiles $ \_ ws -> do
          codesOf ws "a.gm" @?= []
          codesOf ws "b.gm" @?= [],
      testCase "root ADR 0458: completion at the first piece of an item, none at the alias" $
        withProject baseFiles $ \_ ws -> do
          completedAfter ws "\n@import fn/book.emet { " >>= (@?= ["rule", "tax-included", "total"])
          completedAfter ws "\n@import fn/book.emet { rule as r, t" >>= (@?= ["rule", "tax-included", "total"])
          completedAfter ws "\n@import fn/book.emet { total as " >>= (@?= [])
          completedAfter ws "\n@import fn/book.emet { total as s" >>= (@?= [])
          completedAfter ws "\n@import v.gm { price as c" >>= (@?= []),
      testCase "root ADR 0458: completion without a namespace gives the aliases" $
        withProject baseFiles $ \_ ws -> do
          inline <- completedAfter ws "\n["
          assertBool "tax after [" ("tax" `elem` inline && "tax-included" `notElem` inline)
          block <- completedAfter ws "\n@"
          assertBool "line after @" ("line" `elem` block && "rule" `notElem` block)
          expr <- completedAfter ws "\n[= "
          assertBool "sum, total and cost in an expression" (all (`elem` expr) ["sum", "total", "cost"] && "price" `notElem` expr),
      testCase "root ADR 0458: definition from an alias and its references goes to the original name" $
        withProject baseFiles $ \_ ws -> do
          let at needle k = definition ws "a.gm" (offsetIn aText needle k)
          map locStart (at "tax 1000" 1) @?= [offsetIn bookEmet "taxIncluded ::" 0]
          map locStart (at "tax," 1) @?= [offsetIn bookEmet "taxIncluded ::" 0]
          map locPath (at "line\n" 1) @?= ["fn/book.emet"]
          map locStart (at "sum([1])" 1) @?= [offsetIn bookEmet "total ::" 0]
          map locStart (at "sum," 1) @?= [offsetIn bookEmet "total ::" 0]
          map (\l -> (locPath l, locStart l)) (at "cost]" 1) @?= [("v.gm", 5)]
          map (\l -> (locPath l, locStart l)) (at "cost }" 1) @?= [("v.gm", 5)],
      testCase "root ADR 0458: references from the definition include the references by an alias" $
        withProject baseFiles $ \_ ws -> do
          let starts p off = [(locPath l, locStart l) | l <- references ws p off]
              found = starts "fn/book.emet" (offsetIn bookEmet "total ::" 1)
          assertBool (show found) (all (`elem` found) [("a.gm", offsetIn aText "sum([1])" 0), ("a.gm", offsetIn aText "total([2])" 0), ("a.gm", offsetIn aText "sum," 0)])
          let vars = starts "v.gm" 5
          assertBool (show vars) (all (`elem` vars) [("a.gm", offsetIn aText "cost]" 0), ("a.gm", offsetIn aText "cost }" 0), ("b.gm", offsetIn bText "price]" 0)]),
      testCase "root ADR 0458: references from an alias: the alias, its references in the file, the original definition" $
        withProject baseFiles $ \_ ws -> do
          let decl = ("fn/book.emet", offsetIn bookEmet "total ::" 0, offsetIn bookEmet "total ::" 5)
          forM_ [offsetIn aText "sum," 1, offsetIn aText "sum([1])" 1] $ \off ->
            locs (references ws "a.gm" off) @?= sort (decl : sumPlaces)
          locs (references ws "a.gm" (offsetIn aText "cost]" 1)) @?= sort [("v.gm", 5, 10), place "a.gm" aText "cost }" 0 4, place "a.gm" aText "cost]" 0 4],
      testCase "root ADR 0458 I7: renaming the definition rewrites the original names of the lists, not the aliases" $
        withProject baseFiles $ \_ ws -> do
          edits <- either (assertFailure . show) pure (renameEmet ws Nothing "fn/book.emet" (offsetIn bookEmet "total ::" 0) "amount")
          lookup "a.gm" (applied [("a.gm", aText)] edits)
            @?= Just (T.replace "total as sum, total }" "amount as sum, amount }" (T.replace "total([2])" "amount([2])" aText))
          es <- either (\e -> assertFailure (T.unpack (renameMessage e)) >> pure []) pure (renameVariable ws Nothing "v.gm" 5 "worth")
          lookup "a.gm" (applied [("a.gm", aText)] es) @?= Just (T.replace "price as cost" "worth as cost" aText)
          lookup "b.gm" (applied [("b.gm", bText)] es) @?= Just (T.replace "price" "worth" bText),
      testCase "root ADR 0458 I7: renaming an alias writes only the alias and its references in the file" $
        withProject baseFiles $ \_ ws ->
          forM_ [offsetIn aText "sum," 1, offsetIn aText "sum([1])" 2] $ \off -> do
            es <- renamedAlias ws Nothing "a.gm" off "amount"
            places es @?= sumPlaces
            assertBool "a.gm alone" (all ((== "a.gm") . locPath . fst) es),
      testCase "root ADR 0458 I10: renaming an alias keeps the output and the codes" $
        -- new aliases of the same lengths, so that the spans of the output stay
        forM_ [("sum,", "add"), ("tax,", "fee"), ("line\n", "dash"), ("cost }", "fees")] $ \(needle, new) ->
          withProject baseFiles $ \tmp ws -> do
            es <- renamedAlias ws Nothing "a.gm" (offsetIn aText needle 1) new
            let before = outcome ws
                edited = applied baseFiles es
            assertBool "edited" (edited /= baseFiles)
            writeAll tmp edited
            ws' <- openWorkspace tmp
            outcome ws' @?= before,
      testCase "root ADR 0458 I11: a new alias of a wrong form or a reserved word is refused" $
        withProject baseFiles $ \_ ws -> do
          forM_ ["meta", "nil", "", "a.b", "tax-inc", "a b"] $ refusedAlias ws Nothing "a.gm" (offsetIn aText "sum," 1)
          forM_ ["Tax", "my_tax", "meta"] $ refusedAlias ws Nothing "a.gm" (offsetIn aText "tax," 1)
          forM_ ["my-cost", "vars"] $ refusedAlias ws Nothing "a.gm" (offsetIn aText "cost }" 1),
      testCase "root ADR 0458 I11: a new alias that clashes in the file is refused" $
        withProject baseFiles $ \_ ws -> do
          -- another alias, a built-in name of the expressions
          forM_ ["total", "cost", "join", "pi"] $ refusedAlias ws Nothing "a.gm" (offsetIn aText "sum," 1)
          -- a fixed built-in command, an overridable one (root ADR 0453)
          forM_ ["set", "frame", "toc", "separator"] $ refusedAlias ws Nothing "a.gm" (offsetIn aText "line\n" 1)
          forM_ ["link", "strong"] $ refusedAlias ws Nothing "a.gm" (offsetIn aText "tax," 1),
      testCase "root ADR 0458 I11: a new alias of a @set of the file, or a name written already, is refused" $ do
        let a = aText <> "\n@set fee = 1\n\n[= fee + extra]\n"
        withProject (("a.gm", a) : filter ((/= "a.gm") . fst) baseFiles) $ \_ ws ->
          forM_ ["fee", "extra"] $ refusedAlias ws Nothing "a.gm" (offsetIn a "cost }" 1),
      testCase "root ADR 0458 I11: the old or the new alias in a running head is refused" $
        withProject baseFiles $ \_ ws ->
          forM_ ["{set.cost}", "{set.worth}"] $ \fmt ->
            refusedAlias ws (runningHead fmt) "a.gm" (offsetIn aText "cost }" 1) "worth",
      testCase "root ADR 0458 I11: a file with a syntax error is refused" $ do
        let a = aText <> "\n[= (\n"
        withProject (("a.gm", a) : filter ((/= "a.gm") . fst) baseFiles) $ \_ ws ->
          refusedAlias ws Nothing "a.gm" (offsetIn a "sum," 1) "amount",
      testCase "root ADR 0458: a name that is no alias is left to the other renames" $
        withProject baseFiles $ \_ ws -> do
          case renameAlias ws Nothing "a.gm" (offsetIn aText "total([2])" 1) "x" of
            Left NotAnAlias -> pure ()
            r -> assertFailure (show (fmap places r))
          case renameAlias ws Nothing "b.gm" (offsetIn bText "price]" 1) "x" of
            Left NotAnAlias -> pure ()
            r -> assertFailure (show (fmap places r))
    ]
