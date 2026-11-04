module Support
  ( load,
    loadMany,
    codes,
    messages,
    call,
    callAt,
    callSpan,
    nat,
    int,
    rat,
    str,
    bool,
    ok,
    noDiagnostics,
  )
where

import Data.Functor.Identity (runIdentity)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Eval.Value (Value (..))
import Golem.Gmx
import Golem.Syntax
import Test.Tasty.HUnit

{- | Loads main.gmx of a project of these files (paths from the root),
each with its own file id, by their order.
-}
loadMany :: [(FilePath, Text)] -> ([Diagnostic], Maybe Program)
loadMany files = runIdentity (loadProgram source ["main.gmx"])
  where
    table = Map.fromList [(p, (FileId i, TE.encodeUtf8 t)) | (i, (p, t)) <- zip [100 ..] files]
    source p = pure (maybe (Left MissingFile) Right (Map.lookup p table))

load :: Text -> ([Diagnostic], Maybe Program)
load src = loadMany [("main.gmx", src)]

codes :: Text -> [Text]
codes src = [c | DiagnosticCode c <- map diagCode (fst (load src))]

messages :: Text -> [Text]
messages = map diagMessage . fst . load

-- | The span of the call of a .gm command, in a file of its own.
callSpan :: SrcSpan
callSpan = mkSpan (FileId 1) 10 20

-- | Calls a function of main.gmx; fails the test when the source does not load.
call :: Text -> Text -> [Result] -> IO (Either Diagnostic Result)
call src = callAt [("main.gmx", src)]

callAt :: [(FilePath, Text)] -> Text -> [Result] -> IO (Either Diagnostic Result)
callAt files f args = case loadMany files of
  ([], Just p) -> pure (callFunction p callSpan "main.gmx" f args)
  (ds, _) -> assertFailure ("the source did not load: " <> show ds) >> fail "unreachable"

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

ok :: Either Diagnostic Result -> IO Result
ok = either (\d -> assertFailure (show d) >> fail "unreachable") pure

noDiagnostics :: Text -> Assertion
noDiagnostics src = case fst (load src) of
  [] -> pure ()
  ds -> assertFailure (T.unpack (T.unlines [c <> " " <> diagMessage d <> at d | d <- ds, let DiagnosticCode c = diagCode d]))
  where
    at d = " @" <> T.pack (show (spanStart (diagSpan d)))
