module Main (main) where

import AssembleSpec qualified
import BibliographySpec qualified
import CborExprSpec qualified
import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Exception (ErrorCall, evaluate, try)
import CslSpec qualified
import Data.ByteString qualified as BS
import Gen
import Golem.Doc.Cbor
import Golem.Doc.IR
import Golem.Doc.Numerals (kanji)
import Golem.Doc.Validate
import Golem.Parser.AST qualified as AST
import Golem.Syntax.Span
import Golem.TestSupport.ExternalTool (needsTool)
import Golem.TestSupport.Skipped (defaultMainReportingSkips)
import Hedgehog
import ListMarkersSpec qualified
import NumberingSpec qualified
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
main = defaultMainReportingSkips (const tests)

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
  testGroup "golem-doc" [cbor, AssembleSpec.tests, BibliographySpec.tests, CslSpec.tests, ListMarkersSpec.tests, CborExprSpec.tests, NumberingSpec.tests, verticalNumbers, int64Tests]

-- | The integers of the IR are int64 (golem-doc ADR 0006).
int64Tests :: TestTree
int64Tests =
  testGroup
    "the integers of the IR are int64 (golem-doc ADR 0006)"
    [ testCase "the ends of int64 survive the CBOR round trip" $ do
        let is = [Number sp n Nothing | n <- [2 ^ (63 :: Int) - 1, negate (2 ^ (63 :: Int))]]
        decodeInlines (encodeInlines is) @?= Right is,
      testCase "a Number of 2^63 is out of range" $
        inl (TList [TInt 9, spT, TInteger (2 ^ (63 :: Int)), TNull]) @?= Left outOfRange,
      testCase "a Number of -2^63 - 1 is out of range" $
        inl (TList [TInt 9, spT, TInteger (negate (2 ^ (63 :: Int)) - 1), TNull]) @?= Left outOfRange,
      testCase "a Number as a bignum (tag 2 and 3) is out of range" $ do
        inl (TList [TInt 9, spT, TInteger (2 ^ (70 :: Int)), TNull]) @?= Left outOfRange
        inl (TList [TInt 9, spT, TInteger (negate (2 ^ (70 :: Int))), TNull]) @?= Left outOfRange,
      testCase "the start of a span at 2^64 + 5 is not read as 5" $
        inl (TList [TInt 0, TList [TInt 0, TInteger (2 ^ (64 :: Int) + 5), TInteger (2 ^ (64 :: Int) + 6)], TString "a"]) @?= Left outOfRange,
      testCase "the other integers: @number, aki, a code line, an expression" $ do
        let big = TInteger (2 ^ (63 :: Int))
            doc body = decodeDocument (toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, body]]])))
        doc (TList [TInt 1, TInt 1, TList [TNull, big, TBool False, TBool False], TList []]) @?= Left outOfRange
        doc (TList [TInt 6, TList [TNull, TNull, TNull, TNull, TBool False, TList [TList [TString "a", big, TNull, TBool False, TList []]]]]) @?= Left outOfRange
        inl (TList [TInt 18, spT, TNull, big]) @?= Left outOfRange
        inl (TList [TInt 18, spT, TList [TInt 1, big], TNull]) @?= Left outOfRange
        inl (TList [TInt 11, spT, TList [TInt 0, spT, big]]) @?= Left outOfRange,
      testCase "encoding an integer out of range is a bug of the host" $ do
        r <- try (evaluate (BS.length (encodeInlines [Number sp (2 ^ (63 :: Int)) Nothing])))
        case r of
          Left (_ :: ErrorCall) -> pure ()
          Right _ -> assertFailure "encoded",
      testCase "kanji up to the ends of int64" $ do
        kanji (2 ^ (63 :: Int) - 1) @?= "九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百七"
        kanji (negate (2 ^ (63 :: Int))) @?= "マイナス九百二十二京三千三百七十二兆三百六十八億五千四百七十七万五千八百八"
        kanji (10 ^ (16 :: Int)) @?= "一京"
    ]
  where
    spT = TList [TInt 0, TInt 0, TInt 1]
    inl t = decodeInlines (toStrictByteString (encodeTerm (TList [t])))
    outOfRange = "スキーマに合いません: 整数が範囲の外です"

-- | The vertical style of the numbers of a book (golem-parser ADR 0011).
verticalNumbers :: TestTree
verticalNumbers =
  testGroup
    "verticalStyleOf (golem-parser ADR 0011)"
    [ testCase "auto: two digits or fewer in tate-chu-yoko, the others in kanji" $ do
        map (verticalStyleOf (VerticalAuto StyleKanji)) [0, 9, 10, 99] @?= replicate 4 StyleTcy
        map (verticalStyleOf (VerticalAuto StyleKanji)) [100, -1] @?= [StyleKanji, StyleKanji],
      testCase "auto-digits: three digits in kanji digits" $
        verticalStyleOf (VerticalAuto StyleKanjiDigits) 100 @?= StyleKanjiDigits,
      testCase "a fixed style for every number" $
        mapM_ (\st -> map (verticalStyleOf (VerticalFixed st)) [-1, 0, 9, 99, 100, 12345] @?= replicate 6 st) [minBound .. maxBound],
      testCase "the names of [numbers] vertical" $
        map verticalNumbersNamed ["kanji", "kanji-digits", "tcy", "auto", "auto-digits"]
          @?= [VerticalFixed StyleKanji, VerticalFixed StyleKanjiDigits, VerticalFixed StyleTcy, VerticalAuto StyleKanji, VerticalAuto StyleKanjiDigits]
    ]

cbor :: TestTree
cbor =
  testGroup
    "golem-doc (ADR 0001)"
    [ needsTool "cddl" cddlValidator $ \cddl ->
        testProperty "CBOR conforms to the CDDL (the cddl CLI)" $ withTests 60 $ property $ do
          d <- forAll genDocument
          exe <- evalIO cddl
          (code, out, err) <- evalIO $ withSystemTempDirectory "golem-doc" $ \dir -> do
            let path = dir </> "doc.cbor"
            BS.writeFile path (encodeDocument d)
            readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
          annotate (out <> err)
          code === ExitSuccess,
      needsTool "cddl" cddlValidator $ \cddl ->
        testCase "the cddl CLI rejects a document of another ABI version" $ do
          exe <- cddl
          (code, _, _) <- withSystemTempDirectory "golem-doc" $ \dir -> do
            let path = dir </> "bad.cbor"
            BS.writeFile path (BS.pack [0x83, 0x01, 0x00, 0x80])
            readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
          assertBool "rejected" (code /= ExitSuccess),
      testProperty "CBOR round trip" $ withTests 300 $ property $ do
        d <- forAll genDocument
        decodeDocument (encodeDocument d) === Right d,
      testProperty "encoding is canonical" $ property $ do
        d <- forAll genDocument
        let bs = encodeDocument d
        fmap encodeDocument (decodeDocument bs) === Right bs,
      testCase "small integers use their shortest form" $
        BS.length (toStrictByteString (encodeTerm (TInteger 1))) @?= 1,
      testCase "ruby inside ruby is rejected by the decoder" $ do
        let zeroSpan = TList [TInt 0, TInt 0, TInt 1]
            inner = TList [TInt 4, zeroSpan, TList [TList [TList [], TNull]]]
            outer = TList [TInt 4, zeroSpan, TList [TList [TList [inner], TString "よみ"]]]
            bytes = toStrictByteString (encodeTerm (TList [outer]))
        decodeInlines bytes @?= Left "ルビの中にルビがあります"
        -- the same ruby at the top level is accepted
        decodeInlines (toStrictByteString (encodeTerm (TList [inner]))) @?= Right [Ruby sp () [RubySegment [] Nothing]]
        -- a ruby whose base has a ruby is rejected however deep the inner one is
        let deep = TList [TInt 4, zeroSpan, TList [TList [TList [TList [TInt 7, zeroSpan, TString "strong", TList [inner]]], TString "よみ"]]]
        decodeInlines (toStrictByteString (encodeTerm (TList [deep]))) @?= Left "ルビの中にルビがあります",
      testCase "wrong ABI version is rejected" $ do
        let bytes = toStrictByteString (encodeTerm (TList [TInt 99, TInt 0, TList []]))
        decodeDocument bytes @?= Left "ABI のバージョンが異なります: 99",
      testCase "a document of ABI version 2 is rejected (docs/adr ADR 0005)" $ do
        let bytes = toStrictByteString (encodeTerm (TList [TInt 2, TInt 0, TList []]))
        decodeDocument bytes @?= Left "ABI のバージョンが異なります: 2",
      testCase "retired tags are rejected (docs/adr ADR 0005)" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            text = TList [TInt 0, spT, TString "a"]
            doc body = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, body]]]))
            one body = Right (Document (FileId 0) [Block sp Nothing body])
        decodeDocument (doc (TList [TInt 10, TString "verse", TList [text]])) @?= one (Paragraph (Just "verse") [Text sp "a"])
        decodeDocument (doc (TList [TInt 10, TNull, TList [text, TList [TInt 17, spT], text]])) @?= one (Paragraph Nothing [Text sp "a", LineBreak sp, Text sp "a"])
        decodeDocument (doc (TList [TInt 0, TList [text]])) @?= Left "スキーマに合いません: ブロックの種類"
        decodeDocument (doc (TList [TInt 9, TList [TList [TList [text]]]])) @?= Left "スキーマに合いません: ブロックの種類"
        mapM_
          (\t -> decodeInlines (toStrictByteString (encodeTerm (TList [TList [TInt t, spT, TList [text]]]))) @?= Left "スキーマに合いません: インラインの種類")
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
      testCase "the ABI version is 8 and version 7 is rejected (docs/adr ADR 0101)" $ do
        abiVersion @?= 8
        let bytes = toStrictByteString (encodeTerm (TList [TInt 7, TInt 0, TList []]))
        decodeDocument bytes @?= Left "ABI のバージョンが異なります: 7"
        -- the next version is not accepted either
        decodeDocument (toStrictByteString (encodeTerm (TList [TInt 9, TInt 0, TList []]))) @?= Left "ABI のバージョンが異なります: 9",
      testCase "a figure with its page and rotate survives the CBOR round trip (golem-pdf ADR 0008, golem-driver ADR 0034)" $ do
        let fig = Figure "images/a.pdf" (Just "images/a.png") "alt" Nothing Nothing [] (Just 3) True
            doc = Document (FileId 1) [Block (mkSpan (FileId 1) 0 1) Nothing (FigureBlock fig)]
        decodeDocument (encodeDocument doc) @?= Right doc,
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
        inl (TList [TInt 18, spT, TList [TInt 1, TInt 5], TInt 65536]) @?= Left "スキーマに合いません: インラインの種類"
        inl (TList [TInt 18, spT, TNull, TNull]) @?= Left "スキーマに合いません: 整数"
        inl (TList [TInt 18, spT, TList [TInt 1, TInt 0], TNull]) @?= Left "スキーマに合いません: アキの分母"
        inl (TList [TInt 18, spT, TList [TInt 1, TInt (-5)], TNull]) @?= Left "スキーマに合いません: アキの分母"
        -- the numerator and the denominator are read in lowest terms
        inl (TList [TInt 18, spT, TList [TInt 2, TInt 10], TNull]) @?= Right [Aki sp (AkiZw (1 / 5))],
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
        validateDocument size [] (doc [Block sp Nothing (FigureBlock (Figure "a.png" Nothing "a" Nothing Nothing [brk] Nothing False))]) @?= [msgNested]
        validateDocument size [] (doc [Block sp (Just "x") (ForcedBreak BreakRecto)]) @?= [msgLabel],
      testCase "every page control survives the CBOR round trip (docs/adr ADR 0030)" $ do
        let d = Document (FileId 0) [Block sp Nothing (PageControl c) | c <- [NoBreak, NeedLines 5, AdjustLines 1, AdjustLines (-2)]]
        decodeDocument (encodeDocument d) @?= Right d,
      testCase "page controls only at the top of a document, without a label, with valid counts (docs/adr ADR 0030)" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
            ctl = Block sp Nothing (PageControl NoBreak)
            doc = Document (FileId 0)
        validateDocument size [] (doc [ctl, Block sp Nothing (PageControl (NeedLines 1)), Block sp Nothing (PageControl (AdjustLines (-1)))]) @?= []
        validateDocument size [] (doc [Block sp Nothing (BulletList [ListItem Nothing [ctl]])]) @?= ["改ページの制御は文書の最上位にだけ置けます"]
        validateDocument size [] (doc [Block sp (Just "x") (PageControl NoBreak)]) @?= ["改ページの制御はラベルを持てません"]
        validateDocument size [] (doc [Block sp Nothing (PageControl (NeedLines 0))]) @?= ["@need-lines の行数は 1 以上です"]
        validateDocument size [] (doc [Block sp Nothing (PageControl (AdjustLines 0))]) @?= ["@page-lines の増減は 0 でない整数です"],
      testCase "blank lines survive the CBOR round trip as tag 13 (docs/adr ADR 0046)" $ do
        let d = Document (FileId 0) [Block sp Nothing (BlankLines n) | n <- [1, 9223372036854775807]]
            spT = TList [TInt 0, TInt 0, TInt 1]
        decodeDocument (encodeDocument d) @?= Right d
        decodeDocument (toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TList [TInt 13, TInt 2]]]])))
          @?= Right (Document (FileId 0) [Block sp Nothing (BlankLines 2)]),
      testCase "blank lines only at the top of a document, without a label, of one line or more (docs/adr ADR 0046)" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
            blank = Block sp Nothing (BlankLines 1)
            doc = Document (FileId 0)
        validateDocument size [] (doc [blank, Block sp Nothing (BlankLines 3)]) @?= []
        validateDocument size [] (doc [Block sp Nothing (BlankLines 0)]) @?= ["行アキの行数は 1 以上です"]
        validateDocument size [] (doc [Block sp Nothing (BulletList [ListItem Nothing [blank]])]) @?= ["行アキは文書の最上位にだけ置けます"]
        validateDocument size [] (doc [Block sp (Just "x") (BlankLines 1)]) @?= ["行アキはラベルを持てません"],
      testCase "trailing bytes are rejected" $
        decodeInlines (encodeInlines [] <> "\0") @?= Left "CBOR の後に余分なバイト列があります",
      testCase "an enumeration out of its range is rejected (forced breaks)" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            doc body = decodeDocument (toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, body]]])))
        doc (TList [TInt 11, TInt 3]) @?= Right (Document (FileId 0) [Block sp Nothing (ForcedBreak BreakColumn)])
        doc (TList [TInt 11, TInt 4]) @?= Left "スキーマに合いません: 列挙の範囲"
        doc (TList [TInt 11, TInt (-1)]) @?= Left "スキーマに合いません: 列挙の範囲",
      testCase "a span that ends before it starts, or starts before 0, is rejected" $ do
        let inl t = decodeInlines (toStrictByteString (encodeTerm (TList [t])))
        inl (TList [TInt 0, TList [TInt 0, TInt 3, TInt 3], TString "a"]) @?= Right [Text (SrcSpan (FileId 0) 3 3) "a"]
        inl (TList [TInt 0, TList [TInt 0, TInt 3, TInt 2], TString "a"]) @?= Left "スキーマに合いません: 位置の範囲"
        inl (TList [TInt 0, TList [TInt 0, TInt (-1), TInt 2], TString "a"]) @?= Left "スキーマに合いません: 位置の範囲",
      testCase "validation: spans, deferred expressions, index levels" $ do
        let size (FileId 0) = Just 10
            size _ = Nothing
            e = DeferredExpr (AST.Located sp (AST.EVar ["doc", "chapters", "count"]))
        validateInlines size [] [Text (SrcSpan (FileId 0) 5 20) "x"] @?= ["ソース位置がファイルの範囲外です"]
        validateInlines size [] [Deferred sp e] @?= ["プラグインが新しい遅延式を作っています"]
        validateInlines size [e] [Deferred sp e] @?= []
        validateInlines size [] [IndexMark sp (IndexEntry ["a", "b", "c"] ["a", "b", "c"])] @?= ["索引の項目の段の数が不正です"]
    ]
