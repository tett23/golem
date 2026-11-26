-- | Notes whose bodies are blocks (docs/adr/0263).
module NoteSpec (tests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
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

para :: Maybe StyleRef -> [Inline] -> Block
para st is = Block sp Nothing Nothing (Paragraph st is)

docOf :: [Inline] -> Document
docOf is = Document (FileId 0) [Block sp Nothing Nothing (Paragraph Nothing is)]

size :: FileId -> Maybe Int
size (FileId 0) = Just 10
size _ = Nothing

tests :: TestTree
tests =
  testGroup
    "notes of blocks (docs/adr/0263)"
    [ testCase "I7: a note of one, two and three paragraphs and a sidenote survive the CBOR round trip" $
        mapM_
          (\d -> decodeDocument (encodeDocument d) @?= Right d)
          [ docOf [Note sp 1 Nothing (replicate k (para Nothing [Text sp "注"]))] | k <- [1, 2, 3]
          ]
          >> (decodeDocument (encodeDocument (docOf [Sidenote sp 1 Nothing [para Nothing [Text sp "傍"]]])) @?= Right (docOf [Sidenote sp 1 Nothing [para Nothing [Text sp "傍"]]])),
      testCase "notes are tags 23 and 24; 12 and 13 are retired" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            text = TList [TInt 0, spT, TString "a"]
            body = TList [TList [spT, TNull, TNull, TList [TInt 10, TNull, TList [text]]]]
            inl t = decodeInlines (toStrictByteString (encodeTerm (TList [t])))
        inl (TList [TInt 23, spT, TInt 1, body]) @?= Right [Note sp 1 Nothing [para Nothing [Text sp "a"]]]
        inl (TList [TInt 24, spT, TInt 1, body]) @?= Right [Sidenote sp 1 Nothing [para Nothing [Text sp "a"]]]
        inl (TList [TInt 12, spT, TInt 1, TList [text]]) @?= Left "スキーマに合いません: インラインの種類"
        inl (TList [TInt 13, spT, TInt 1, TList [text]]) @?= Left "スキーマに合いません: インラインの種類",
      testCase "I7: Validate rejects a footnote of no paragraph, a sidenote of other than one, a block other than a paragraph without a style" $ do
        let errs is = validateDocument size [] (docOf is)
            p = para Nothing [Text sp "a"]
        errs [Note sp 1 Nothing [p]] @?= []
        errs [Note sp 1 Nothing [p, p, p]] @?= []
        errs [Note sp 1 Nothing []] @?= ["脚注の本文は一つ以上の段落です"]
        errs [Sidenote sp 1 Nothing [p]] @?= []
        errs [Sidenote sp 1 Nothing []] @?= ["傍注の本文は段落をちょうど一つ持ちます"]
        errs [Sidenote sp 1 Nothing [p, p]] @?= ["傍注の本文は段落をちょうど一つ持ちます"]
        errs [Note sp 1 Nothing [para (Just "quote") [Text sp "a"]]] @?= ["注の本文には段落スタイルのない段落だけを置けます"]
        errs [Note sp 1 Nothing [Block sp Nothing Nothing (BulletList [])]] @?= ["注の本文には段落スタイルのない段落だけを置けます"]
        -- the inlines of a paragraph of a note are checked as those of a note were
        errs [Note sp 1 Nothing [para Nothing [Text sp "a", LineBreak sp, Text sp "b"]]] @?= ["改行は段落の最上位のインラインの間にだけ置けます"],
      testCase "root ADR 0412 I2: an endnote of one and two paragraphs survives the CBOR round trip as tag 26" $ do
        mapM_ (\d -> decodeDocument (encodeDocument d) @?= Right d) [docOf [Endnote sp 1 Nothing (replicate k (para Nothing [Text sp "後"]))] | k <- [1, 2]]
        let spT = TList [TInt 0, TInt 0, TInt 1]
            text = TList [TInt 0, spT, TString "a"]
            body = TList [TList [spT, TNull, TNull, TList [TInt 10, TNull, TList [text]]]]
        decodeInlines (toStrictByteString (encodeTerm (TList [TList [TInt 26, spT, TInt 3, body]]))) @?= Right [Endnote sp 3 Nothing [para Nothing [Text sp "a"]]],
      testCase "root ADR 0422: the label of a note survives the CBOR round trip after its body; a note without one keeps its bytes" $ do
        let body = [para Nothing [Text sp "a"]]
        mapM_ (\d -> decodeDocument (encodeDocument d) @?= Right d) [docOf [Note sp 1 (Just "x") body, Sidenote sp 2 (Just "y") body, Endnote sp 3 (Just "z") body]]
        let spT = TList [TInt 0, TInt 0, TInt 1]
            text = TList [TInt 0, spT, TString "a"]
            bodyT = TList [TList [spT, TNull, TNull, TList [TInt 10, TNull, TList [text]]]]
            bytes ts = toStrictByteString (encodeTerm (TList ts))
        decodeInlines (bytes [TList [TInt 23, spT, TInt 3, bodyT, TString "x"]]) @?= Right [Note sp 3 (Just "x") body]
        decodeInlines (bytes [TList [TInt 26, spT, TInt 3, bodyT, TString "x"]]) @?= Right [Endnote sp 3 (Just "x") body]
        decodeInlines (bytes [TList [TInt 24, spT, TInt 3, bodyT]]) @?= Right [Sidenote sp 3 Nothing body]
        -- without a label, the bytes of before: the tag, the span, the number and the body
        encodeInlines [Note sp 3 Nothing body] @?= bytes [TList [TInt 23, spT, TInt 3, bodyT]],
      testCase "root ADR 0412 I2: Validate rejects an endnote of no paragraph and a block other than a paragraph without a style" $ do
        let errs is = validateDocument size [] (docOf is)
            p = para Nothing [Text sp "a"]
        errs [Endnote sp 1 Nothing [p, p]] @?= []
        errs [Endnote sp 1 Nothing []] @?= ["章末の注の本文は一つ以上の段落です"]
        errs [Endnote sp 1 Nothing [para (Just "quote") [Text sp "a"]]] @?= ["注の本文には段落スタイルのない段落だけを置けます"],
      needsTool "cddl" cddlValidator $ \cddl ->
        testCase "the cddl CLI takes notes of tags 23 and 24 and rejects a note of no block" $ do
          exe <- cddl
          let validate bs = withSystemTempDirectory "golem-doc" $ \dir -> do
                let path = dir </> "doc.cbor"
                BS.writeFile path bs
                (code, _, _) <- readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
                pure code
          validate (encodeDocument (docOf [Note sp 1 Nothing [para Nothing [Text sp "a"], para Nothing []], Sidenote sp 1 Nothing [para Nothing []], Endnote sp 1 Nothing [para Nothing []]])) >>= (@?= ExitSuccess)
          code <- validate (encodeDocument (docOf [Note sp 1 Nothing []]))
          assertBool "empty" (code /= ExitSuccess)
    ]

cddlValidator :: IO (Maybe FilePath)
cddlValidator = do
  env <- lookupEnv "GOLEM_CDDL"
  case env of
    Just p -> pure (Just p)
    Nothing -> findExecutable "cddl"
