module Support
  ( load,
    loadMany,
    codes,
    codesOf,
    messages,
    call,
    callAt,
    callWith,
    callSpan,
    stepsOf,
    nat,
    int,
    rat,
    str,
    bool,
    chr,
    ok,
    failure,
    noDiagnostics,
    bodyOf,
  )
where

import Data.Functor.Identity (runIdentity)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet
import Golem.Emet.Syntax
import Golem.Eval.Value (Value (..))
import Golem.Syntax
import Test.Tasty.HUnit

{- | Loads main.emet of a project of these files (paths from the root),
each with its own file id, by their order.
-}
loadMany :: [(FilePath, Text)] -> ([Diagnostic], Maybe Program)
loadMany files = runIdentity (loadProgram source ["main.emet"])
  where
    table = Map.fromList [(p, (FileId i, TE.encodeUtf8 t)) | (i, (p, t)) <- zip [100 ..] files]
    source p = pure (maybe (Left MissingFile) Right (Map.lookup p table))

load :: Text -> ([Diagnostic], Maybe Program)
load src = loadMany [("main.emet", src)]

codes :: Text -> [Text]
codes = codesOf . load

codesOf :: ([Diagnostic], a) -> [Text]
codesOf (ds, _) = [c | DiagnosticCode c <- map diagCode ds]

messages :: Text -> [Text]
messages = map diagMessage . fst . load

-- | The span of the call of a .gm command, in a file of its own.
callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

-- | Calls a function of main.emet; fails the test when the source does not load.
call :: Text -> Text -> [Result] -> IO (Either Diagnostic Result)
call src = callAt [("main.emet", src)]

callAt :: [(FilePath, Text)] -> Text -> [Result] -> IO (Either Diagnostic Result)
callAt = callWith noHandlers

-- | 'callAt' with the handlers of the requirements (docs/adr/0161).
callWith :: Handlers -> [(FilePath, Text)] -> Text -> [Result] -> IO (Either Diagnostic Result)
callWith hs files f args = case loadMany files of
  (ds, Just p) | not (any isError ds) -> pure (callFunction hs p callSpan "main.emet" f args)
  (ds, _) -> assertFailure ("the source did not load: " <> show ds) >> fail "unreachable"

-- | The steps of a call of main.emet.
stepsOf :: Text -> Text -> [Result] -> IO (Either Diagnostic Result, Int)
stepsOf src f args = case load src of
  (ds, Just p) | not (any isError ds) -> pure (callFunctionCounted noHandlers p callSpan "main.emet" f args)
  (ds, _) -> assertFailure (show ds) >> fail "unreachable"

nat :: Integer -> Result
nat = RPrim . VNat . fromInteger

int :: Integer -> Result
int = RPrim . VInt

rat :: Rational -> Result
rat = RPrim . VRat

str :: Text -> Result
str = RPrim . VString

bool :: Bool -> Result
bool = RPrim . VBool

chr :: Char -> Result
chr = RChar

ok :: Either Diagnostic Result -> IO Result
ok = either (\d -> assertFailure (show d) >> fail "unreachable") pure

-- | The diagnostic of a call that fails.
failure :: Either Diagnostic Result -> IO Diagnostic
failure = either pure (\r -> assertFailure ("no error: " <> show r) >> fail "unreachable")

noDiagnostics :: Text -> Assertion
noDiagnostics src = case fst (load src) of
  [] -> pure ()
  ds -> assertFailure (T.unpack (T.unlines [c <> " " <> diagMessage d <> at d | d <- ds, let DiagnosticCode c = diagCode d]))
  where
    at d = " @" <> T.pack (show (spanStart (diagSpan d)))

-- | The expression of @f = <the text>@, parsed.
bodyOf :: Text -> IO Expr
bodyOf e = case parseModule (FileId 0) ("f = " <> e <> "\n") of
  Right (Module [DEq q]) | Plain x <- eqRhs q -> pure x
  r -> assertFailure (show r) >> fail "unreachable"
