{- | golem new in a directory without a project (docs/adr/0273): the
invariants I1 to I8, checked on every small table of entries for
'planProject' and on the rows of the boundary table on the file system for
'createProject'.
-}
module NewPlanSpec (newPlanTests) where

import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.Containers.ListUtils (nubOrd)
import Data.Either (isLeft)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List (sort, (\\))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Golem.Driver.New
import Golem.Plugin.Lock (hashHex)
import Golem.TestSupport.Enum
import Support (uuid0)
import System.Directory
  ( createDirectory,
    createDirectoryIfMissing,
    createDirectoryLink,
    createFileLink,
    doesDirectoryExist,
    getSymbolicLinkTarget,
    listDirectory,
    pathIsSymbolicLink,
  )
import Data.List (isPrefixOf)
import System.FilePath (splitDirectories, takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- ------------------------------------------------------------------ the inputs of planProject

-- | The paths of the template whose entries the enumeration varies.
templatePaths :: [FilePath]
templatePaths =
  [ "manifest.toml",
    "style.toml",
    "chapters",
    "chapters/01.gm",
    "preflight.toml",
    ".gitignore",
    "fonts",
    "fonts/NotoSerifJP-Regular.otf",
    "fonts/LICENSE-NotoSerifJP.txt"
  ]

-- | The fonts of the Japanese template, with the hash of the fake bytes the fake fetcher gives.
fonts :: [FontSource]
fonts = [s {fsSha256 = hashHex fontBytes} | s <- templateFonts Japanese]

fontBytes :: BS.ByteString
fontBytes = "FONT"

-- | The paths golem new writes (W), with or without fonts.
writesFor :: Bool -> [FilePath]
writesFor noFonts = map fst (templateFiles Japanese uuid0) <> (if noFonts then [] else map fsPath fonts)

data Input = Input {inTarget :: Argument, inEntries :: [(FilePath, Entry)], inNoFonts :: Bool}
  deriving stock (Show)

entryOf :: Input -> FilePath -> Entry
entryOf i p = fromMaybe NoEntry (lookup p (inEntries i))

-- | Entries below which other entries can be.
holdsEntries :: Entry -> Bool
holdsEntries e = e == Directory || e == SymbolicLink True

-- | The proper ancestors of a relative path, outermost first.
ancestorsOf :: FilePath -> [FilePath]
ancestorsOf p = init (scanl1 (</>) (splitDirectories p))

-- | A link to a file and a link that leads nowhere are both @SymbolicLink False@.
kinds :: [Entry]
kinds = [NoEntry, RegularFile, Directory, SymbolicLink True, SymbolicLink False]

entryKinds :: Tiers Entry
entryKinds = Tiers [kinds]

targets :: Tiers Argument
targets = Tiers [[Argument NoEntry, Argument Directory, Argument RegularFile, Argument (SymbolicLink True), Argument (SymbolicLink False), BelowNonDirectory]]

{- | Every target, every kind of the nine paths and with and without fonts,
but the tables the file system cannot have: an entry below a target, or
below an entry, that cannot hold entries. The tables are built from the
entries that can hold others down, not filtered from every table, so that
each value is made once.
-}
inputs :: Tiers Input
inputs = mapT (\((t, es), nf) -> Input t es nf) ((tables \/ empties) >< bools)
  where
    holding = filterT holds targets
    holds = \case
      Argument e -> holdsEntries e
      BelowNonDirectory -> False
    -- below a target that holds nothing, there is nothing
    empties = mapT (,[(p, NoEntry) | p <- templatePaths]) (filterT (not . holds) targets)
    tables = mapT (\(t, ((m, s), (cs, (pf, (g, fs))))) -> (t, [("manifest.toml", m), ("style.toml", s)] <> cs <> [("preflight.toml", pf), (".gitignore", g)] <> fs)) (holding >< (entryKinds >< entryKinds) >< (chapters >< entryKinds >< entryKinds >< fontsGroup))
    chapters = group "chapters" ["chapters/01.gm"]
    fontsGroup = group "fonts" ["fonts/NotoSerifJP-Regular.otf", "fonts/LICENSE-NotoSerifJP.txt"]
    -- the parent, then the children only when it holds entries
    group parent children =
      Tiers [[(parent, k) : zip children ks | k <- kinds, ks <- if holdsEntries k then mapM (const kinds) children else [map (const NoEntry) children]]]

plan :: Input -> Either [Conflict] Plan
plan i = planProject (writesFor (inNoFonts i)) (inTarget i) (inEntries i)

-- | What docs/adr/0273 says the result is, from the input alone.
expected :: Input -> Either [Conflict] Plan
expected i
  | not targetOk = Left [NotADirectory]
  | not (null projects) = Left (map ProjectExists projects)
  | not (null taken) = Left (map PathTaken taken)
  | otherwise = Right (Plan [p | p <- w, not (kept && p == ".gitignore")] kept)
  where
    w = writesFor (inNoFonts i)
    targetOk = inTarget i `elem` [Argument NoEntry, Argument Directory, Argument (SymbolicLink True)]
    projects = [p | p <- ["manifest.toml", "style.toml"], entryOf i p /= NoEntry]
    checkedPaths = w \\ ["manifest.toml", "style.toml", ".gitignore"]
    blocked = [a | a <- nubOrd (concatMap ancestorsOf checkedPaths), entryOf i a `notElem` [NoEntry, Directory]]
    taken = sort (blocked <> [p | p <- checkedPaths, not (any (`elem` blocked) (ancestorsOf p)), entryOf i p /= NoEntry])
    kept = entryOf i ".gitignore" /= NoEntry

{- | I3: an error exactly when the argument is not a directory, a project
file is there, or a checked path or a directory on the way is taken. The
other entries of the directory (@others@) never count.
-}
i3 :: Input -> Bool -> Either [Conflict] Plan -> [Violation]
i3 i _others r = [Violation "I3" (show r) | isLeft r /= isLeft (expected i)]

-- | I5: the codes and their paths, in order; G03134 only when the run succeeds.
i5 :: Input -> Either [Conflict] Plan -> [Violation]
i5 i r =
  [Violation "I5" (show (r, expected i)) | r /= expected i]
    <> [Violation "I5: G03132 in the order of the bytes of the paths" (show r) | Left cs <- [r], let ps = [p | PathTaken p <- cs], ps /= sort ps]

-- | I6: the same input gives the same result, and the order of the table does not matter.
i6 :: Input -> [Violation]
i6 i =
  [Violation "I6: twice" "" | plan i /= plan i]
    <> [Violation "I6: reversed" (show (plan i, r)) | let r = plan i {inEntries = reverse (inEntries i)}, r /= plan i]

-- | I8: with --no-fonts, the entries of fonts and below it change nothing.
i8 :: Input -> [Violation]
i8 i =
  [ Violation "I8" (show (plan i, plan cleared))
  | inNoFonts i,
    let cleared = i {inEntries = [(p, if "fonts" `elem` take 1 (splitDirectories p) then NoEntry else e) | (p, e) <- inEntries i]},
    plan cleared /= plan i
  ]

checked :: String -> (Input -> [Violation]) -> Assertion
checked rule check = case checkAllPar 0 inputs check of
  Passed n -> assertBool (rule <> ": the values checked: " <> show n) (n > 100000)
  Failed t x vs -> assertFailure (rule <> ": the value of tier " <> show t <> ": " <> show x <> "\n" <> unlines (map show vs))

-- | The rule before docs/adr/0273: a directory with anything in it is an error.
oldRule :: Input -> Bool -> Either [Conflict] Plan
oldRule i hasOthers
  | hasOthers || any ((/= NoEntry) . snd) (inEntries i) = Left [PathTaken "."]
  | otherwise = expected i

planTests :: [TestTree]
planTests =
  [ testCase "I3: an error only for a target that is not a directory, a project, or a taken path" $ checked "I3" (\i -> i3 i True (plan i)),
    testCase "I5: G03133 alone, G03131 for each project file, G03132 for each taken path in order, G03134 on success" $ checked "I5" (\i -> i5 i (plan i)),
    testCase "I6: the result is a function of the kinds of the entries" $ checked "I6" i6,
    testCase "I8: --no-fonts does not look at fonts" $ checked "I8" i8,
    testCase "I3: the rule that a directory must be empty breaks I3 for a directory of other files" $ do
      let i = Input (Argument Directory) [(p, NoEntry) | p <- templatePaths] False
      assertBool "the old rule is flagged" (not (null (i3 i True (oldRule i True))))
      i3 i True (plan i) @?= []
  ]

-- ------------------------------------------------------------------ on the file system

-- | An entry of a tree: a file and the hash of its bytes, a directory, or a link and its target.
data Node = File T.Text | Dir | Link FilePath
  deriving stock (Eq, Show)

-- | Every entry under a directory, without following links, by path relative to it.
snapshot :: FilePath -> IO (Map.Map FilePath Node)
snapshot root = Map.fromList <$> go ""
  where
    go rel = do
      names <- listDirectory (root </> rel)
      concat
        <$> forM
          (sort names)
          ( \n -> do
              let r = if null rel then n else rel </> n
                  p = root </> r
              link <- pathIsSymbolicLink p
              if link
                then (\t -> [(r, Link t)]) <$> getSymbolicLinkTarget p
                else do
                  d <- doesDirectoryExist p
                  if d
                    then ((r, Dir) :) <$> go r
                    else (\b -> [(r, File (hashHex b))]) <$> BS.readFile p
          )

data Outcome = Outcome {oResult :: Either NewError Plan, oBefore, oAfter :: Map.Map FilePath Node, oFetches :: Int}

-- | Runs createProject on @arg@ in a temporary directory prepared by @setup@.
runIn :: (FilePath -> IO ()) -> FilePath -> Bool -> Bool -> (FilePath -> Outcome -> IO a) -> IO a
runIn setup arg noFonts fetchFails k = withSystemTempDirectory "golem-new" $ \tmp -> do
  setup tmp
  calls <- newIORef (0 :: Int)
  let fetch _ = do
        atomicModifyIORef' calls (\n -> (n + 1, ()))
        pure (if fetchFails then Left "offline" else Right fontBytes)
  before <- snapshot tmp
  r <- createProject (tmp </> arg) (templateFiles Japanese uuid0) (if noFonts then Nothing else Just (fetch, fonts))
  afterRun <- snapshot tmp
  n <- readIORef calls
  k tmp (Outcome r before afterRun n)

-- | The bytes of a project made in an empty directory, by path.
reference :: Bool -> IO (Map.Map FilePath BS.ByteString)
reference noFonts = withSystemTempDirectory "golem-new-ref" $ \tmp -> do
  _ <- createProject (tmp </> "p") (templateFiles Japanese uuid0) (if noFonts then Nothing else Just (\_ -> pure (Right fontBytes), fonts))
  Map.fromList <$> forM (writesFor noFonts) (\p -> (p,) <$> BS.readFile (tmp </> "p" </> p))

-- | I1: every entry that was there before is there after, the same.
i1 :: Outcome -> Assertion
i1 o = forM_ (Map.toList (oBefore o)) $ \(p, n) -> Map.lookup p (oAfter o) @?= Just n

-- | I2: after an error the tree is as before, and nothing was fetched.
i2 :: Outcome -> Assertion
i2 o = do
  oAfter o @?= oBefore o
  oFetches o @?= 0

{- | I4: the new entries are the files of the plan under @at@ and the
directories that hold them, with the bytes of a project in an empty directory.
-}
i4 :: FilePath -> FilePath -> Bool -> Outcome -> Assertion
i4 tmp at noFonts o = case oResult o of
  Left e -> assertFailure ("an error: " <> show e)
  Right p -> do
    let new = Map.difference (oAfter o) (oBefore o)
        files = [f | (f, File _) <- Map.toList new]
        dirs = [d | (d, Dir) <- Map.toList new]
        wanted = sort [at </> f | f <- planWrites p]
    sort files @?= wanted
    forM_ dirs $ \d -> assertBool ("a directory that holds no written file: " <> d) (any ((d <> "/") `isPrefixOf`) wanted)
    ref <- reference noFonts
    forM_ (planWrites p) $ \f -> BS.readFile (tmp </> at </> f) >>= (@?= ref Map.! f)

-- | Writes files (with their directories) under a directory.
put :: FilePath -> [(FilePath, BS.ByteString)] -> IO ()
put root fs = forM_ fs $ \(p, b) -> createDirectoryIfMissing True (takeDirectory (root </> p)) >> BS.writeFile (root </> p) b

-- | What a row expects: the conflicts, or success and whether .gitignore is kept.
data Expect = Fails [Conflict] | Succeeds Bool | FetchFails

data Row = Row {rName :: String, rSetup :: FilePath -> IO (), rArg :: FilePath, rAt :: FilePath, rNoFonts :: Bool, rFetchFails :: Bool, rExpect :: Expect}

row :: String -> (FilePath -> IO ()) -> Expect -> Row
row name setup = Row name setup "book" "book" False False

others :: [(FilePath, BS.ByteString)]
others = [(".git/HEAD", "ref: refs/heads/main\n"), ("README.md", "# book\n"), ("01-intro.md", "# Intro\n"), ("images/.keep", "")]

inBook :: [(FilePath, BS.ByteString)] -> FilePath -> IO ()
inBook fs tmp = createDirectory (tmp </> "book") >> put (tmp </> "book") fs

boundaryRows :: [Row]
boundaryRows =
  [ row "no target" (const (pure ())) (Succeeds False),
    (row "no directory on the way" (const (pure ())) (Succeeds False)) {rArg = "a/b/c", rAt = "a/b/c"},
    row "an empty directory" (inBook []) (Succeeds False),
    row "other files only" (inBook others) (Succeeds False),
    row ".md in chapters" (inBook [("chapters/01-intro.md", "# Intro\n")]) (Succeeds False),
    row "manifest.toml" (inBook [("manifest.toml", "x")]) (Fails [ProjectExists "manifest.toml"]),
    row "style.toml only" (inBook [("style.toml", "x")]) (Fails [ProjectExists "style.toml"]),
    row "manifest.toml, style.toml and other template files" (inBook [("manifest.toml", "x"), ("style.toml", "x"), ("preflight.toml", "x"), ("chapters/01.gm", "x"), (".gitignore", "x")]) (Fails [ProjectExists "manifest.toml", ProjectExists "style.toml"]),
    row "manifest.toml a link that leads nowhere" (\t -> inBook [] t >> createFileLink "nowhere" (t </> "book/manifest.toml")) (Fails [ProjectExists "manifest.toml"]),
    row "chapters/01.gm" (inBook [("chapters/01.gm", "mine")]) (Fails [PathTaken "chapters/01.gm"]),
    row "chapters a file" (inBook [("chapters", "x")]) (Fails [PathTaken "chapters"]),
    row "chapters a link to a directory" (\t -> createDirectory (t </> "elsewhere") >> inBook [] t >> createDirectoryLink "../elsewhere" (t </> "book/chapters")) (Fails [PathTaken "chapters"]),
    row "preflight.toml a directory" (\t -> inBook [] t >> createDirectory (t </> "book/preflight.toml")) (Fails [PathTaken "preflight.toml"]),
    row "chapters/01.gm and preflight.toml" (inBook [("preflight.toml", "x"), ("chapters/01.gm", "x")]) (Fails [PathTaken "chapters/01.gm", PathTaken "preflight.toml"]),
    row ".gitignore" (inBook [(".gitignore", "node_modules/\n")]) (Succeeds True),
    row ".gitignore and manifest.toml" (inBook [(".gitignore", "x"), ("manifest.toml", "x")]) (Fails [ProjectExists "manifest.toml"]),
    row ".gitignore and chapters/01.gm" (inBook [(".gitignore", "x"), ("chapters/01.gm", "x")]) (Fails [PathTaken "chapters/01.gm"]),
    row "a font" (inBook [("fonts/NotoSerifJP-Regular.otf", "x")]) (Fails [PathTaken "fonts/NotoSerifJP-Regular.otf"]),
    (row "a font, --no-fonts" (inBook [("fonts/NotoSerifJP-Regular.otf", "x")]) (Succeeds False)) {rNoFonts = True},
    row "fonts a file" (inBook [("fonts", "x")]) (Fails [PathTaken "fonts"]),
    (row "fonts a file, --no-fonts" (inBook [("fonts", "x")]) (Succeeds False)) {rNoFonts = True},
    (row "other files, and the fetch fails" (inBook others) FetchFails) {rFetchFails = True},
    row "the argument a file" (\t -> BS.writeFile (t </> "book") "x") (Fails [NotADirectory]),
    (row "the argument a link to a directory" (\t -> createDirectory (t </> "real") >> createDirectoryLink "real" (t </> "book")) (Succeeds False)) {rAt = "real"},
    row "the argument a link to a file" (\t -> BS.writeFile (t </> "afile") "x" >> createFileLink "afile" (t </> "book")) (Fails [NotADirectory]),
    row "the argument a link that leads nowhere" (\t -> createFileLink "nowhere" (t </> "book")) (Fails [NotADirectory]),
    (row "the argument below a file" (\t -> BS.writeFile (t </> "afile") "x") (Fails [NotADirectory])) {rArg = "afile/book", rAt = "afile/book"}
  ]

checkRow :: Row -> TestTree
checkRow r = testCase ("I1, I2, I4, I5: " <> rName r) $ runIn (rSetup r) (rArg r) (rNoFonts r) (rFetchFails r) $ \tmp o -> do
  i1 o
  case rExpect r of
    Fails cs -> do
      oResult o @?= Left (Conflicts cs)
      i2 o
    FetchFails -> do
      assertBool "a fetch error" (case oResult o of Left (FetchFailed _) -> True; _ -> False)
      oAfter o @?= oBefore o
    Succeeds kept -> do
      fmap planKeepsGitignore (oResult o) @?= Right kept
      i4 tmp (rAt r) (rNoFonts r) o

-- | I7: other entries change neither the result nor the files written.
i7 :: String -> [(FilePath, BS.ByteString)] -> TestTree
i7 name fs = testCase ("I7: other entries change nothing: " <> name) $ do
  let written tmp o = case oResult o of
        Right p -> forM (planWrites p) (\f -> (f,) <$> BS.readFile (tmp </> "book" </> f))
        Left _ -> pure []
  (r0, w0) <- runIn (inBook fs) "book" False False (\tmp o -> (oResult o,) <$> written tmp o)
  (r1, w1) <- runIn (inBook (fs <> others <> [("chapters/01-intro.md", "# Intro\n")])) "book" False False (\tmp o -> (oResult o,) <$> written tmp o)
  r1 @?= r0
  w1 @?= w0

fileSystemTests :: [TestTree]
fileSystemTests =
  map checkRow boundaryRows
    <> [ i7 "an empty directory" [],
         i7 ".gitignore" [(".gitignore", "x")],
         i7 "chapters/01.gm" [("chapters/01.gm", "x")],
         i7 "manifest.toml" [("manifest.toml", "x")]
       ]

newPlanTests :: TestTree
newPlanTests = testGroup "golem new in a directory without a project (docs/adr/0273)" (planTests <> fileSystemTests)
