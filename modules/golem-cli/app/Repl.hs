module Repl (run) where

import Control.Exception (AsyncException (UserInterrupt), throwIO, try, tryJust)
import Control.Monad (when)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.Char (isAlphaNum, isControl, ord)
import Data.IORef
import Data.List (intercalate, isPrefixOf, nub, sort)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Data.Text.Lazy qualified as LT
import Data.Text.Lazy.IO qualified as LTIO
import Golem.Emet (Program, Result (..), SourceProblem (..), evaluateExpression, loadProgram, parseModule, readEmet, sessionPath, stepLimit)
import Golem.Emet.Ide (IdeKind (..), emetCompletions)
import Golem.Emet.Syntax (Decl (..), Equation (..), Loc (..), Module (..), Signature (..))
import Golem.Eval.Expr (valueText)
import Golem.Eval.Value (Value (..))
import Golem.Project.Files (Files (..), diskFiles)
import Golem.Project.Paths (PathError (Missing), resolveEntryInRoot)
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..), FileId (..), spanEnd, spanStart)
import Numeric (showHex)
import System.Console.Haskeline qualified as H
import System.Directory (doesDirectoryExist, getCurrentDirectory, listDirectory)
import System.Exit
import System.FilePath (addTrailingPathSeparator, splitFileName, takeExtension, (</>))
import System.IO
import System.IO.Error (tryIOError)

data Entry = Ready | More BS.ByteString [Diagnostic] | Declaration BS.ByteString

data Session = Session [(T.Text, BS.ByteString)] (Maybe Program)

declare :: Files -> IORef Session -> BS.ByteString -> IO Bool
declare files ref input = case readEmet (FileId 0) input >>= parseModule (FileId 0) of
  Left ds -> mapM_ report ds >> pure False
  Right (Module decls) -> do
    Session previous _ <- readIORef ref
    let item d =
          let (name, loc) = case d of
                DImport l raw _ -> ("import " <> raw, l)
                DSig sig -> (sigName sig, sigLoc sig)
                DEq eq -> (eqName eq, eqLoc eq)
                DData l _ n _ _ -> ("type " <> n, l)
                DType l _ n _ _ -> ("type " <> n, l)
           in (name, BS.take (locEnd loc - locStart loc) (BS.drop (locStart loc) input))
        additions = map item decls
        entries = filter ((`notElem` map fst additions) . fst) previous <> additions
        source = B8.unlines (map snd entries)
    next <- newIORef 1
    let readSource path
          | path == sessionPath = pure (Right (FileId 0, source))
          | otherwise =
              filesResolve files path >>= \case
                Left Missing -> pure (Left MissingFile)
                Left _ -> pure (Left OutsideRoot)
                Right rel ->
                  tryIOError (filesRead files rel) >>= \case
                    Left _ -> pure (Left MissingFile)
                    Right bytes -> do
                      fid <- atomicModifyIORef' next (\n -> (n + 1, FileId n))
                      pure (Right (fid, bytes))
    (ds, checked) <- loadProgram readSource [sessionPath]
    mapM_ report ds
    case checked of
      Nothing -> pure False
      Just program -> writeIORef ref (Session entries (Just program)) >> pure True

showResult :: Result -> String
showResult = \case
  RPrim (VString s) -> quoted '"' (T.unpack s)
  RPrim (VBool b) -> if b then "True" else "False"
  RPrim v -> T.unpack (valueText v)
  RChar c -> quoted '\'' [c]
  RCon c [] -> T.unpack c
  RCon c fields -> "(" <> unwords (T.unpack c : map showResult fields) <> ")"
  RList xs -> "[" <> intercalate ", " (map showResult xs) <> "]"
  RTuple xs -> "(" <> intercalate ", " (map showResult xs) <> ")"
  RFun -> "<function>"
  where
    quoted q cs = q : concatMap (escape q) cs ++ [q]
    escape q c | c == q || c == '\\' = ['\\', c]
    escape _ '\n' = "\\n"
    escape _ '\t' = "\\t"
    escape _ c | isControl c = "\\u{" <> showHex (ord c) "}"
    escape _ c = [c]

report :: Diagnostic -> IO ()
report d = do
  let DiagnosticCode code = diagCode d
      sp = diagSpan d
      site = T.pack (" [" ++ show (spanStart sp) ++ "," ++ show (spanEnd sp) ++ "): ")
  TIO.hPutStrLn stderr (code <> site <> diagMessage d)

submit :: Maybe Program -> Bool -> BS.ByteString -> IO (Bool, Entry)
submit session interactive input
  | BS.all (`elem` [32, 9, 10]) input = pure (True, Ready)
  | otherwise = case evaluateExpression session stepLimit input of
      Left ds
        | incomplete input ds -> pure (True, More input ds)
        | otherwise -> mapM_ report ds >> pure (False, Ready)
      Right value -> do
        when interactive (TIO.putStr "=> ")
        LTIO.hPutStrLn stdout (LT.pack (showResult value))
        hFlush stdout
        pure (True, Ready)

incomplete :: BS.ByteString -> [Diagnostic] -> Bool
incomplete input ds = not (null ds) && all atEnd ds
  where
    atEnd d =
      let DiagnosticCode code = diagCode d
          sp = diagSpan d
       in code `elem` ["E01100", "E01101"] && spanStart sp == BS.length input && spanEnd sp == BS.length input

-- Haskeline supplies the prefix in reverse order, with the suffix left in the editor.
completeEntry :: FilePath -> Session -> Entry -> H.CompletionFunc IO
completeEntry root (Session declarations program) entry (back, _) = do
  let left = reverse back
      typed = T.pack left
      lead = T.stripStart typed
      source = B8.unlines (map snd declarations <> pending) <> TE.encodeUtf8 typed
      pending = case entry of Ready -> []; More src _ -> [src]; Declaration src -> [src]
      (nameRev, rest) = span (\c -> isAlphaNum c || c == '_') back
      name = reverse nameRev
      inType = "::" `T.isInfixOf` typed
      kinds k = if inType then k `elem` [IdeType, IdeRequirement] else k /= IdeType
      names = [T.unpack n | (n, k) <- emetCompletions program sessionPath (TE.decodeUtf8Lenient source) (BS.length source), kinds k]
      options prefix = map (\n -> H.Completion n n False) . sort . nub . filter (prefix `isPrefixOf`)
  case T.stripPrefix "import" lead >>= T.stripPrefix "\"" . T.stripStart of
    Just fragment | not (T.any (== '"') fragment) -> do
      let path = T.unpack fragment
          (dir, prefix) = splitFileName path
      resolved <- if null dir || dir == "./" then pure (Right ".") else resolveEntryInRoot root dir
      paths <- case resolved of
        Left _ -> pure []
        Right rel -> do
          listing <- tryIOError (listDirectory (root </> rel))
          fmap concat $
            mapM
              ( \n -> do
                  safe <- resolveEntryInRoot root (dir </> n)
                  case safe of
                    Left _ -> pure []
                    Right target -> do
                      directory <- doesDirectoryExist (root </> target)
                      pure [if directory then addTrailingPathSeparator n else n | directory || takeExtension n == ".emet"]
              )
              (either (const []) id listing)
      pure (drop (length prefix) back, options prefix paths)
    _
      | literalOrComment left -> pure (back, [])
      | otherwise -> pure (rest, options name names)
  where
    literalOrComment = outside
    outside [] = False
    outside ('-' : '-' : _) = True
    outside (c : cs) | c == '"' || c == '\'' = quoted c cs
    outside (_ : cs) = outside cs
    quoted _ [] = True
    quoted q ('\\' : _ : cs) = quoted q cs
    quoted q (c : cs) = if c == q then outside cs else quoted q cs

run :: IO ExitCode
run = do
  session <- newIORef (Session [] Nothing)
  root <- getCurrentDirectory
  let files = diskFiles root
  _ <- declare files session BS.empty
  inputTTY <- hIsTerminalDevice stdin
  promptTTY <- hIsTerminalDevice stderr
  let interactive = inputTTY && promptTTY
      interrupt UserInterrupt | interactive = Just ()
      interrupt _ = Nothing
      cancel ok = hPutStrLn stderr "" >> loop ok Ready
      finish ok = pure (if ok then ExitSuccess else ExitFailure 1)
      loop !ok entry = do
        current <- readIORef session
        let prompt = case entry of Ready -> "emet> "; _ -> "....> "
            settings = H.Settings (completeEntry root current entry) Nothing False
            terminal = try (H.runInputT settings (H.withInterrupt (H.getInputLine prompt)))
            lineInput
              | interactive = terminal >>= \case Left H.Interrupt -> throwIO UserInterrupt; Right line -> pure (TE.encodeUtf8 . T.pack <$> line)
              | otherwise = hIsEOF stdin >>= \eof -> if eof then pure Nothing else Just <$> B8.hGetLine stdin
        tryJust interrupt lineInput >>= \case
          Left () -> cancel ok
          Right line -> consume ok entry line
      consume !ok entry = \case
        Nothing -> case entry of
          Ready -> finish ok
          More _ ds -> mapM_ report ds >> finish False
          Declaration src -> declare files session src >>= finish . (ok &&)
        Just s -> case entry of
          Declaration src
            | B8.all (`elem` [' ', '\t']) s,
              Left ds <- readEmet (FileId 0) src >>= parseModule (FileId 0),
              incomplete src ds ->
                loop ok (Declaration (src <> "\n" <> s))
            | B8.all (`elem` [' ', '\t']) s -> commit ok src
            | otherwise -> loop ok (Declaration (src <> "\n" <> s))
          Ready | "import" : _ <- B8.words s -> commit ok s
          Ready | declarationStart s -> loop ok (Declaration s)
          _ -> do
            let input = case entry of More previous _ -> previous <> "\n" <> s; _ -> s
            Session _ program <- readIORef session
            tryJust interrupt (submit program interactive input) >>= \case
              Left () -> cancel ok
              Right (passed, next) -> loop (ok && passed) next
      commit ok src =
        tryJust interrupt (declare files session src) >>= \case
          Left () -> cancel ok
          Right passed -> loop (ok && passed) Ready
      declarationStart s = case B8.words s of
        word : _ | word `elem` ["pub", "data", "type"] -> True
        _ -> case B8.break (`elem` [' ', '\t', ':']) (B8.dropWhile (`elem` [' ', '\t']) s) of
          (name, rest) -> not (BS.null name) && "::" `BS.isPrefixOf` B8.dropWhile (`elem` [' ', '\t']) rest
  loop True Ready
