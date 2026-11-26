-- | Renaming the variables of @set in the language server, and their references (root ADR 0454).
module SetRenameSpec (setRenameTests) where

import Control.Monad (forM_, void)
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
import System.Directory (canonicalizePath, createDirectoryIfMissing)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | F: the file that sets the variables.
fText :: Text
fText = "@import common/e.gm { rate }\n\n@set price = 1\n\n@set tax = 2\n\n[= price + tax + rate]\n"

-- | G: imports F with a namespace.
gText :: Text
gText = "@import common/f.gm * as ns\n\n[= ns.price]\n"

-- | H: lists price of F.
hText :: Text
hText = "@import common/f.gm { price }\n\n@set other = 1\n\n[= price + other]\n"

-- | H2: lists price of F, through a path with ./ (root ADR 0455).
h2Text :: Text
h2Text = "@import ./common/f.gm { price }\n\n[= price]\n"

-- | K: sets a price of its own.
kText :: Text
kText = "@set price = 5\n\n[= price]\n"

-- | The files of the project: the chapters, the variable files and the manifest.
baseFiles :: [(FilePath, Text)]
baseFiles =
  [ ("common/f.gm", fText),
    ("common/e.gm", "@set rate = 3\n"),
    ("g.gm", gText),
    ("h.gm", hText),
    ("h2.gm", h2Text),
    ("k.gm", kText)
  ]

chapters :: [Text]
chapters = ["g.gm", "h.gm", "h2.gm", "k.gm"]

-- | A project of the files, the workspace opened on it.
withProject :: [(FilePath, Text)] -> (FilePath -> Workspace -> IO a) -> IO a
withProject files act = withSystemTempDirectory "golem-lsp-set-rename" $ \tmp0 -> do
  tmp <- canonicalizePath tmp0
  writeAll tmp (("manifest.toml", manifestToml testManifest {tmChapters = chapters}) : files)
  ws <- openWorkspace tmp
  act tmp ws

writeAll :: FilePath -> [(FilePath, Text)] -> IO ()
writeAll tmp files = forM_ files $ \(p, t) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) (TE.encodeUtf8 t)

-- | The offset of a needle in a text, and a number of bytes further.
offsetIn :: Text -> Text -> Int -> Int
offsetIn text needle k = BS.length (TE.encodeUtf8 (fst (T.breakOn needle text))) + k

-- | The places a rename writes, sorted.
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

-- | The rename of a position, which must succeed.
renamed :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> IO [(Location, Text)]
renamed ws style p off new = either (\e -> assertFailure (T.unpack (renameMessage e)) >> pure []) pure (renameVariable ws style p off new)

-- | The message of a rename that must fail.
refused :: Workspace -> Maybe Text -> FilePath -> Int -> Text -> Assertion
refused ws style p off new = case renameVariable ws style p off new of
  Left NotAVariable -> assertFailure "not a variable"
  Left _ -> pure ()
  Right es -> assertFailure ("renamed: " <> show (places es))

-- | Every position of price of F, in the files that write it.
pricePositions :: [(FilePath, Int)]
pricePositions =
  [ ("common/f.gm", offsetIn fText "price = 1" 0),
    ("common/f.gm", offsetIn fText "price + tax" 1),
    ("g.gm", offsetIn gText "ns.price" 4),
    ("h.gm", offsetIn hText "{ price }" 2),
    ("h.gm", offsetIn hText "price + other" 0),
    ("h2.gm", offsetIn h2Text "{ price }" 3),
    ("h2.gm", offsetIn h2Text "[= price" 3)
  ]

-- | The places of price of F.
pricePlaces :: [(FilePath, Int, Int)]
pricePlaces =
  sort
    [ ("common/f.gm", offsetIn fText "price = 1" 0, offsetIn fText "price = 1" 5),
      ("common/f.gm", offsetIn fText "price + tax" 0, offsetIn fText "price + tax" 5),
      ("g.gm", offsetIn gText "ns.price" 3, offsetIn gText "ns.price" 8),
      ("h.gm", offsetIn hText "{ price }" 2, offsetIn hText "{ price }" 7),
      ("h.gm", offsetIn hText "price + other" 0, offsetIn hText "price + other" 5),
      ("h2.gm", offsetIn h2Text "{ price }" 2, offsetIn h2Text "{ price }" 7),
      ("h2.gm", offsetIn h2Text "[= price" 3, offsetIn h2Text "[= price" 8)
    ]

setRenameTests :: TestTree
setRenameTests =
  testGroup
    "renaming the variables of @set (root ADR 0454)"
    [ testCase "root ADR 0454 I1, I3: a variable F alone uses: its @set and its reference" $
        withProject baseFiles $ \tmp ws -> do
          let off = offsetIn fText "tax = 2" 0
          es <- renamed ws Nothing "common/f.gm" off "fee"
          places es @?= sort [("common/f.gm", off, off + 3), ("common/f.gm", offsetIn fText "+ tax" 2, offsetIn fText "+ tax" 5)]
          places es @?= locs (references ws "common/f.gm" off)
          sameOutcome tmp ws es,
      testCase "root ADR 0454 I1: a variable set twice (G02024): both @set and the reference" $ do
        let f = "@set dup = 1\n\n@set dup = 2\n\n[= dup]\n"
        withProject [("common/f.gm", f), ("g.gm", "@import common/f.gm * as ns\n"), ("h.gm", "一。\n"), ("h2.gm", "一。\n"), ("k.gm", "一。\n")] $ \_ ws -> do
          es <- renamed ws Nothing "common/f.gm" 5 "twin"
          places es @?= sort [("common/f.gm", 5, 8), ("common/f.gm", offsetIn f "dup = 2" 0, offsetIn f "dup = 2" 3), ("common/f.gm", offsetIn f "[= dup" 3, offsetIn f "[= dup" 6)]
          places es @?= locs (references ws "common/f.gm" 5),
      testCase "root ADR 0454 I1, I2, I3: from every position of price of F, the same places in F, G, H and H2" $
        withProject baseFiles $ \tmp ws -> do
          forM_ pricePositions $ \(p, off) -> do
            es <- renamed ws Nothing p off "worth"
            places es @?= pricePlaces
            places es @?= locs (references ws p off)
          es <- renamed ws Nothing "h.gm" (offsetIn hText "{ price }" 2) "worth"
          sameOutcome tmp ws es,
      testCase "root ADR 0454 I5: a rename of price of F leaves the price of K" $
        withProject baseFiles $ \_ ws -> do
          es <- renamed ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0) "worth"
          assertBool "K" (all (\(l, _) -> locPath l /= "k.gm") es)
          es' <- renamed ws Nothing "k.gm" 5 "worth"
          map (locPath . fst) es' @?= ["k.gm", "k.gm"],
      testCase "root ADR 0454 I4: a new name that is a reserved word or cannot be a name is refused" $
        withProject baseFiles $ \_ ws ->
          forM_ ["meta", "vars", "nil", "", "a b", "ns.x"] $ refused ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0),
      testCase "root ADR 0454 I4: in F, a new name of another variable, a name F lists, or a built-in name is refused" $
        withProject baseFiles $ \_ ws ->
          forM_ ["tax", "rate", "pi", "join"] $ refused ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0),
      testCase "root ADR 0454 I4: in H, a new name of a variable H sets is refused" $
        withProject baseFiles $ \_ ws ->
          refused ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0) "other",
      testCase "root ADR 0454 I4: an H with G02274 for price is refused" $ do
        let h = "@import common/f.gm { price }\n\n@set price = 2\n"
        withProject (("h.gm", h) : filter ((/= "h.gm") . fst) baseFiles) $ \_ ws ->
          refused ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0) "worth",
      testCase "root ADR 0454 I4: F sets pi and H lists it (G02277): refused" $ do
        let f = "@set pi = 3\n"
            h = "@import common/f.gm { pi }\n"
        withProject [("common/f.gm", f), ("g.gm", "一。\n"), ("h.gm", h), ("h2.gm", "一。\n"), ("k.gm", "一。\n")] $ \_ ws ->
          refused ws Nothing "common/f.gm" 5 "tau",
      testCase "root ADR 0454 I4: {set.price} or {set.worth} in the running heads of style.toml: refused" $
        withProject baseFiles $ \_ ws ->
          forM_ ["{set.price}", "{set.worth}", "{set.ns.price}", "{set.ns.worth}"] $ \fmt ->
            refused ws (Just ("[masters.body]\nrunning-head = { position = \"top-outside\", format = \"" <> fmt <> "\" }\n")) "common/f.gm" (offsetIn fText "price = 1" 0) "worth",
      testCase "root ADR 0463: {set.price} or {set.worth} in title-format of style.toml: refused" $
        withProject baseFiles $ \_ ws ->
          forM_ ["{set.price}", "{set.worth}", "{set.ns.price}", "{set.ns.worth}"] $ \fmt ->
            refused ws (Just ("[headings.1]\ntitle-format = \"" <> fmt <> "{title}\"\n")) "common/f.gm" (offsetIn fText "price = 1" 0) "worth",
      testCase "root ADR 0463: {set.price} or {set.worth} in title-format of @style-def: refused" $
        forM_ ["{set.price}", "{set.worth}", "{set.ns.price}"] $ \fmt ->
          withProject (("k.gm", "@style-def paragraph caption title-format=\"" <> fmt <> "\"\n\n" <> kText) : filter ((/= "k.gm") . fst) baseFiles) $ \_ ws ->
            case renameVariable ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0) "worth" of
              Left (TitleFormatVariable "k.gm" _) -> pure ()
              r -> assertFailure (show (fmap places r)),
      testCase "root ADR 0463: title-format without {set.*} does not refuse the rename" $
        withProject baseFiles $ \_ ws ->
          void $ renamed ws (Just "[headings.1]\ntitle-format = \"{number}{title}\"\n") "common/f.gm" (offsetIn fText "price = 1" 0) "worth",
      testCase "root ADR 0454 I3, I4: a reference to the new name, which the rename would make point at the variable, is refused" $ do
        withProject (("h2.gm", h2Text <> "\n[= worth]\n") : filter ((/= "h2.gm") . fst) baseFiles) $ \_ ws ->
          refused ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0) "worth"
        withProject (("g.gm", gText <> "\n[= ns.worth]\n") : filter ((/= "g.gm") . fst) baseFiles) $ \_ ws ->
          refused ws Nothing "common/f.gm" (offsetIn fText "price = 1" 0) "worth",
      testCase "root ADR 0454 I4: [= pi] is no variable of @set" $
        withProject [("common/f.gm", "@set x = 1\n"), ("g.gm", "[= pi]\n"), ("h.gm", "一。\n"), ("h2.gm", "一。\n"), ("k.gm", "一。\n")] $ \_ ws ->
          case renameVariable ws Nothing "g.gm" 3 "tau" of
            Left (NotASetVariable _) -> pure ()
            r -> assertFailure (show (fmap places r)),
      testCase "root ADR 0454 I4: a label is not a variable" $
        withProject baseFiles $ \_ ws ->
          case renameVariable ws Nothing "g.gm" 0 "x" of
            Left NotAVariable -> pure ()
            r -> assertFailure (show (fmap places r))
    ]
  where
    -- the project after the edits gives the same codes and the same documents (I3)
    sameOutcome tmp ws es = do
      let before = outcome ws
          edited = applied baseFiles es
      writeAll tmp edited
      ws' <- openWorkspace tmp
      outcome ws' @?= before
      assertBool "edited" (edited /= baseFiles)
