{- | The kinds of an index mark (docs/adr/0265): I8 by the CBOR round trip
of every kind and every kind of reference, the CDDL, and the checks of
the output of a plugin.
-}
module IndexSpec (tests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Doc.Validate
import Golem.Syntax.Span
import Golem.TestSupport.ExternalTool (needsTool)
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

docOf :: [Inline] -> Document
docOf is = Document (FileId 0) [Block sp Nothing Nothing (Paragraph Nothing is)]

size :: FileId -> Maybe Int
size (FileId 0) = Just 10
size _ = Nothing

-- | The four kinds, a reference of each kind of one level and of two.
kinds :: [IndexKind]
kinds = [IndexPoint, IndexRangeBegin, IndexRangeEnd] <> [IndexSee k t | k <- [minBound .. maxBound], t <- [["組版"], ["組版", "和文組版"]]]

tests :: TestTree
tests =
  testGroup
    "the kinds of an index mark (docs/adr/0265)"
    [ testCase "I8: every kind and every kind of reference survives the CBOR round trip" $
        forM_ kinds $ \k -> forM_ [(["語"], ["ご"]), (["語", "副"], ["ご", "ふく"])] $ \(ts, rs) -> do
          let d = docOf [IndexMark sp (IndexEntry ts rs k)]
          decodeDocument (encodeDocument d) @?= Right d,
      testCase "I8: the kind is the fifth field of tag 14" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            inl t = decodeInlines (toStrictByteString (encodeTerm (TList [t])))
            mark k = TList [TInt 14, spT, TList [TString "a"], TList [TString "あ"], k]
        inl (mark (TList [TInt 0])) @?= Right [IndexMark sp (IndexEntry ["a"] ["あ"] IndexPoint)]
        inl (mark (TList [TInt 1])) @?= Right [IndexMark sp (IndexEntry ["a"] ["あ"] IndexRangeBegin)]
        inl (mark (TList [TInt 2])) @?= Right [IndexMark sp (IndexEntry ["a"] ["あ"] IndexRangeEnd)]
        inl (mark (TList [TInt 3, TInt 2, TList [TString "b", TString "c"]])) @?= Right [IndexMark sp (IndexEntry ["a"] ["あ"] (IndexSee SeeAlso ["b", "c"]))]
        assertBool "no kind" (isLeft (inl (TList [TInt 14, spT, TList [TString "a"], TList [TString "あ"]])))
        assertBool "kind 4" (isLeft (inl (mark (TList [TInt 4]))))
        assertBool "see kind 3" (isLeft (inl (mark (TList [TInt 3, TInt 3, TList [TString "b"]])))),
      testCase "I8: the checks of the output of a plugin reject a target of no level, three levels or an empty level" $ do
        let errs k = validateDocument size [] (docOf [IndexMark sp (IndexEntry ["a"] ["あ"] k)])
        forM_ kinds $ \k -> errs k @?= []
        errs (IndexSee SeeAuto []) @?= ["索引の参照先の段の数が不正です"]
        errs (IndexSee SeeOnly ["a", "b", "c"]) @?= ["索引の参照先の段の数が不正です"]
        errs (IndexSee SeeAlso ["a", ""]) @?= ["索引の参照先の段の数が不正です"],
      needsTool "cddl" cddlValidator $ \cddl ->
        testCase "I8: the cddl CLI takes every kind and rejects a target of three levels" $ do
          exe <- cddl
          let validate bs = withSystemTempDirectory "golem-doc" $ \dir -> do
                let path = dir </> "doc.cbor"
                BS.writeFile path bs
                (code, _, _) <- readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
                pure code
          forM_ kinds $ \k -> validate (encodeDocument (docOf [IndexMark sp (IndexEntry ["a"] ["あ"] k)])) >>= (@?= ExitSuccess)
          code <- validate (encodeDocument (docOf [IndexMark sp (IndexEntry ["a"] ["あ"] (IndexSee SeeAuto ["a", "b", "c"]))]))
          assertBool "three levels" (code /= ExitSuccess)
    ]
  where
    isLeft = either (const True) (const False)

cddlValidator :: IO (Maybe FilePath)
cddlValidator = do
  env <- lookupEnv "GOLEM_CDDL"
  case env of
    Just p -> pure (Just p)
    Nothing -> findExecutable "cddl"
