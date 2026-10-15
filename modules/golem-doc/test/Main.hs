module Main (main) where

import AssembleSpec qualified
import BibliographySpec qualified
import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Gen
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Doc.Validate
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Hedgehog
import ListMarkersSpec qualified
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog

main :: IO ()
main = defaultMain tests

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

-- | The external CDDL validator (golem-doc ADR 0001): GOLEM_CDDL or cddl on PATH.
cddlValidator :: IO (Maybe FilePath)
cddlValidator = do
  env <- lookupEnv "GOLEM_CDDL"
  case env of
    Just p -> pure (Just p)
    Nothing -> findExecutable "cddl"

tests :: TestTree
tests =
  testGroup "golem-doc" [cbor, AssembleSpec.tests, BibliographySpec.tests, ListMarkersSpec.tests]

cbor :: TestTree
cbor =
  testGroup
    "golem-doc (ADR 0001)"
    [ testProperty "CBOR conforms to the CDDL (the cddl CLI, when installed)" $ withTests 60 $ property $ do
        d <- forAll genDocument
        validator <- evalIO cddlValidator
        case validator of
          Nothing -> success
          Just exe -> do
            (code, out, err) <- evalIO $ withSystemTempDirectory "golem-doc" $ \dir -> do
              let path = dir </> "doc.cbor"
              BS.writeFile path (encodeDocument d)
              readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
            annotate (out <> err)
            code === ExitSuccess,
      testCase "the cddl CLI rejects a document of another ABI version" $ do
        validator <- cddlValidator
        case validator of
          Nothing -> pure ()
          Just exe -> withSystemTempDirectory "golem-doc" $ \dir -> do
            let path = dir </> "bad.cbor"
            BS.writeFile path (BS.pack [0x83, 0x01, 0x00, 0x80])
            (code, _, _) <- readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
            assertBool "rejected" (code /= ExitSuccess),
      testProperty "CBOR round trip" $ withTests 300 $ property $ do
        d <- forAll genDocument
        decodeDocument (encodeDocument d) === Right d,
      testProperty "encoding is deterministic and canonical" $ property $ do
        d <- forAll genDocument
        let bs = encodeDocument d
        bs === encodeDocument d
        fmap encodeDocument (decodeDocument bs) === Right bs,
      testCase "small integers and floats use their shortest form" $ do
        BS.length (toStrictByteString (encodeTerm (TInteger 1))) @?= 1
        BS.length (toStrictByteString (encodeTerm (floatTerm 0.5))) @?= 3
        BS.length (toStrictByteString (encodeTerm (floatTerm 0.1))) @?= 9
        BS.length (toStrictByteString (encodeTerm (floatTerm 1.0e-7))) @?= 9
        BS.length (toStrictByteString (encodeTerm (floatTerm 100000.5))) @?= 5,
      testCase "ruby inside ruby is rejected by the decoder" $ do
        let spanT = TList [TInt 0, TInt 0, TInt 1]
            inner = TList [TInt 4, spanT, TList [TList [TList [], TNull]]]
            outer = TList [TInt 4, spanT, TList [TList [TList [inner], TString "よみ"]]]
            bytes = toStrictByteString (encodeTerm (TList [outer]))
        assertBool "rejected" (isLeft (decodeInlines bytes)),
      testCase "wrong ABI version is rejected" $ do
        let bytes = toStrictByteString (encodeTerm (TList [TInt 99, TInt 0, TList []]))
        assertBool "rejected" (isLeft (decodeDocument bytes)),
      testCase "a document of ABI version 2 is rejected (docs/adr ADR 0005)" $ do
        let bytes = toStrictByteString (encodeTerm (TList [TInt 2, TInt 0, TList []]))
        assertBool "rejected" (isLeft (decodeDocument bytes)),
      testCase "retired tags are rejected (docs/adr ADR 0005)" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            text = TList [TInt 0, spT, TString "a"]
            doc body = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, body]]]))
        assertBool "a styled paragraph" (not (isLeft (decodeDocument (doc (TList [TInt 10, TString "verse", TList [text]])))))
        assertBool "a body paragraph" (not (isLeft (decodeDocument (doc (TList [TInt 10, TNull, TList [text, TList [TInt 17, spT], text]])))))
        assertBool "paragraph 0" (isLeft (decodeDocument (doc (TList [TInt 0, TList [text]]))))
        assertBool "verse 9" (isLeft (decodeDocument (doc (TList [TInt 9, TList [TList [TList [text]]]]))))
        mapM_
          (\t -> assertBool ("inline " <> show t) (isLeft (decodeInlines (toStrictByteString (encodeTerm (TList [TList [TInt t, spT, TList [text]]]))))))
          [1, 2, 3],
      testCase "line breaks only between inlines at the top of a paragraph (docs/adr ADR 0005)" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
            para st is = Document (FileId 0) [Block sp Nothing (Paragraph st is)]
            a = Text sp "a"
            br = LineBreak sp
        validateDocument size [] (para (Just "verse") [a, br, a]) @?= []
        validateDocument size [] (para Nothing [CharStyle sp "strong" [a, br, a]]) @?= ["改行は段落の最上位のインラインの間にだけ置けます"]
        validateDocument size [] (para Nothing [br, a]) @?= ["改行は段落の最上位のインラインの間にだけ置けます"]
        validateDocument size [] (para Nothing [a, br]) @?= ["改行は段落の最上位のインラインの間にだけ置けます"]
        validateDocument size [] (para Nothing [a, br, br, a]) @?= ["改行は段落の最上位のインラインの間にだけ置けます"]
        validateDocument size [] (para (Just "body") [a]) @?= ["段落スタイル body は null で表します"]
        validateInlines size [] [a, br, a] @?= ["改行は段落の最上位のインラインの間にだけ置けます"],
      testCase "the ABI version is 6 and version 5 is rejected (golem-driver ADR 0023)" $ do
        abiVersion @?= 6
        let bytes = toStrictByteString (encodeTerm (TList [TInt 5, TInt 0, TList []]))
        assertBool "rejected" (isLeft (decodeDocument bytes)),
      testCase "a code block survives the CBOR round trip (golem-driver ADR 0023)" $ do
        let code =
              Code
                { codeLang = Just "haskell",
                  codeNumbers = Just True,
                  codeFile = Just "src/Main.hs",
                  codeCaption = Just [Text sp "設定の", CharStyle sp "code" [Text sp "x"]],
                  codeDiff = True,
                  codeLines =
                    [ CodeLine "a" (Just 10) (Just DiffAdded) True [1, 2],
                      CodeLine "b" Nothing (Just DiffRemoved) False [],
                      CodeLine "" (Just 11) (Just DiffContext) False [50]
                    ]
                }
            doc = Document (FileId 0) [Block sp (Just "l") (CodeBlock code)]
        decodeDocument (encodeDocument doc) @?= Right doc,
      testCase "aki survives the CBOR round trip as tag 18 (docs/adr ADR 0019)" $ do
        let is = [Aki sp (AkiZw (1 / 5)), Aki sp (AkiZw 0), Aki sp (AkiAbs 185795)]
        decodeInlines (encodeInlines is) @?= Right is
        let spT = TList [TInt 0, TInt 0, TInt 1]
            inl t = decodeInlines (toStrictByteString (encodeTerm (TList [t])))
        inl (TList [TInt 18, spT, TList [TInt 1, TInt 5], TNull]) @?= Right [Aki sp (AkiZw (1 / 5))]
        inl (TList [TInt 18, spT, TNull, TInt 65536]) @?= Right [Aki sp (AkiAbs 65536)]
        assertBool "both" (isLeft (inl (TList [TInt 18, spT, TList [TInt 1, TInt 5], TInt 65536])))
        assertBool "neither" (isLeft (inl (TList [TInt 18, spT, TNull, TNull])))
        assertBool "zero denominator" (isLeft (inl (TList [TInt 18, spT, TList [TInt 1, TInt 0], TNull]))),
      testCase "a negative aki is invalid (docs/adr ADR 0019)" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
        validateInlines size [] [Aki sp (AkiZw (1 / 5)), Aki sp (AkiAbs 10)] @?= []
        validateInlines size [] [Aki sp (AkiZw (-1))] @?= ["アキの量が負です"]
        validateInlines size [] [Aki sp (AkiAbs (-1))] @?= ["アキの量が負です"],
      testCase "every kind of forced break survives the CBOR round trip (docs/adr ADR 0017)" $ do
        let d = Document (FileId 0) [Block sp Nothing (ForcedBreak k) | k <- [minBound .. maxBound]]
        decodeDocument (encodeDocument d) @?= Right d
        [minBound .. maxBound :: BreakKind] @?= [BreakPage, BreakRecto, BreakVerso, BreakColumn],
      testCase "forced breaks only at the top of a document, without a label (docs/adr ADR 0017)" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
            brk = Block sp Nothing (ForcedBreak BreakPage)
            doc = Document (FileId 0)
            msgNested = "改ページは文書の最上位にだけ置けます"
            msgLabel = "改ページはラベルを持てません"
        validateDocument size [] (doc [brk]) @?= []
        validateDocument size [] (doc [Block sp Nothing (BulletList [ListItem Nothing [brk]])]) @?= [msgNested]
        validateDocument size [] (doc [Block sp Nothing (DefList [DefGroup [[]] [[brk]]])]) @?= [msgNested]
        validateDocument size [] (doc [Block sp Nothing (FigureBlock (Figure "a.png" Nothing "a" Nothing Nothing [brk]))]) @?= [msgNested]
        validateDocument size [] (doc [Block sp (Just "x") (ForcedBreak BreakRecto)]) @?= [msgLabel],
      testCase "trailing bytes are rejected" $
        assertBool "rejected" (isLeft (decodeInlines (encodeInlines [] <> "\0"))),
      testCase "validation: spans, deferred expressions, index levels" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
            e = DeferredExpr (AST.Located sp (AST.EVar ["doc", "chapters", "count"]))
        validateInlines size [] [Text (SrcSpan (FileId 0) 5 20) "x"] @?= ["ソース位置がファイルの範囲外です"]
        validateInlines size [] [Deferred sp e] @?= ["プラグインが新しい遅延式を作っています"]
        validateInlines size [e] [Deferred sp e] @?= []
        validateInlines size [] [IndexMark sp (IndexEntry ["a", "b", "c"] ["a", "b", "c"])] @?= ["索引の項目の段の数が不正です"]
    ]
