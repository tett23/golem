{- | The CBOR of the documents the generators make (golem-doc ADR 0001):
the schema/golem-doc.cddl of golem-doc takes them, they survive the round
trip, and their encoding is canonical. These properties of golem-doc are
here, not in the test suite of golem-doc, since that suite cannot depend
on this package, which depends on golem-doc (docs/adr/0197).
-}
module CborSpec (tests) where

import Data.ByteString qualified as BS
import Golem.Doc.Cbor
import Golem.DocGen (genDocument)
import Golem.TestSupport.ExternalTool (needsTool)
import Hedgehog
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.Hedgehog

{- | The external CDDL validator (golem-doc ADR 0001): GOLEM_CDDL or cddl
on PATH. A copy of the one of the test suite of golem-doc (docs/adr/0197).
-}
cddlValidator :: IO (Maybe FilePath)
cddlValidator = do
  env <- lookupEnv "GOLEM_CDDL"
  case env of
    Just p -> pure (Just p)
    Nothing -> findExecutable "cddl"

-- | The schema of golem-doc, from the directory of this package.
schema :: FilePath
schema = ".." </> "golem-doc" </> "schema" </> "golem-doc.cddl"

tests :: TestTree
tests =
  testGroup
    "golem-doc (ADR 0001)"
    [ needsTool "cddl" cddlValidator $ \cddl ->
        testProperty "CBOR conforms to the CDDL (the cddl CLI)" $ withTests 60 $ property $ do
          d <- forAll genDocument
          exe <- evalIO cddl
          (code, out, err) <- evalIO $ withSystemTempDirectory "golem-doc" $ \dir -> do
            let path = dir </> "doc.cbor"
            BS.writeFile path (encodeDocument d)
            readProcessWithExitCode exe ["--ci", "validate", "--cddl", schema, "--cbor", path] ""
          annotate (out <> err)
          code === ExitSuccess,
      testProperty "CBOR round trip" $ withTests 300 $ property $ do
        d <- forAll genDocument
        decodeDocument (encodeDocument d) === Right d,
      testProperty "encoding is canonical" $ property $ do
        d <- forAll genDocument
        let bs = encodeDocument d
        fmap encodeDocument (decodeDocument bs) === Right bs
    ]
