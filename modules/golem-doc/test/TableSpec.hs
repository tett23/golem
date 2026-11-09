-- | Tables with numbers, captions, column widths and a paragraph style (docs/adr/0262).
module TableSpec (tests) where

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

-- | A table of two columns with every field written.
full :: Table
full =
  Table
    { tableAligns = [AlignLeft, AlignRight],
      tableWidths = [ColumnZw (17 / 2), ColumnPercent 40],
      tableCaption = Just [Text sp "出力の形式"],
      tableNoNumber = True,
      tableStyle = Just "small-table",
      tableHeader = [[Text sp "形式"], [Text sp "用途"]],
      tableRows = [[[Text sp "PDF"], [Text sp "印刷"]]]
    }

docOf :: Table -> Document
docOf t = Document (FileId 0) [Block sp Nothing Nothing (TableBlock t)]

size :: FileId -> Maybe Int
size (FileId 0) = Just 10
size _ = Nothing

tests :: TestTree
tests =
  testGroup
    "tables (docs/adr/0262)"
    [ testCase "a table with every width, a caption, nonumber and a style survives the CBOR round trip" $ do
        decodeDocument (encodeDocument (docOf full)) @?= Right (docOf full)
        let widths = full {tableWidths = [ColumnAuto, columnAbsolute 655360]}
        decodeDocument (encodeDocument (docOf widths)) @?= Right (docOf widths)
        decodeDocument (encodeDocument (docOf (plainTable [AlignDefault] [[]] []))) @?= Right (docOf (plainTable [AlignDefault] [[]] [])),
      testCase "a table is tag 14 and tag 5 is retired" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            doc body = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TNull, body]]]))
            old = TList [TInt 5, TList [TInt 0], TList [TList []], TList []]
            new = TList [TInt 14, TList [TList [TInt 0], TList [], TNull, TBool False, TNull, TList [TList []], TList []]]
        decodeDocument (doc old) @?= Left "スキーマに合いません: ブロックの種類"
        decodeDocument (doc new) @?= Right (docOf (plainTable [AlignDefault] [[]] [])),
      testCase "a column width of another tag is rejected" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            doc w = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TNull, TList [TInt 14, TList [TList [TInt 0], TList [w], TNull, TBool False, TNull, TList [TList []], TList []]]]]]))
        decodeDocument (doc (TList [TInt 4])) @?= Left "スキーマに合いません: 列の幅"
        decodeDocument (doc (TList [TInt 2, TInt (-1)])) @?= Left "スキーマに合いません: 自然数",
      testCase "the invariants of a table each give one violation" $ do
        let errs t = validateDocument size [] (docOf t)
        errs full @?= []
        errs full {tableWidths = [ColumnAuto]} @?= ["表の列の幅の数が列の数と違います"]
        errs full {tableWidths = []} @?= []
        errs full {tableWidths = [ColumnZw 0, ColumnAuto]} @?= ["表の列の幅は 0 より大きい値です"]
        errs full {tableWidths = [columnAbsolute 0, ColumnAuto]} @?= ["表の列の幅は 0 より大きい値です"]
        errs full {tableWidths = [ColumnPercent (-1), ColumnAuto]} @?= ["表の列の幅は 0 より大きい値です"]
        errs full {tableCaption = Nothing} @?= ["キャプションのない表は番号を持たないので、@nonumber は要りません"]
        errs full {tableCaption = Nothing, tableNoNumber = False} @?= []
        errs full {tableStyle = Just "table"} @?= ["表の段落スタイル table は null で表します"]
        errs full {tableStyle = Just "body"} @?= []
        errs full {tableRows = [[[]]]} @?= ["表のセルの数が一致しません"],
      needsTool "cddl" cddlValidator $ \cddl ->
        testCase "the cddl CLI takes a table of tag 14 and rejects one of tag 5" $ do
          exe <- cddl
          let validate bs = withSystemTempDirectory "golem-doc" $ \dir -> do
                let path = dir </> "doc.cbor"
                BS.writeFile path bs
                (code, _, _) <- readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
                pure code
              spT = TList [TInt 0, TInt 0, TInt 1]
              old = toStrictByteString (encodeTerm (TList [TInt abiVersion, TInt 0, TList [TList [spT, TNull, TNull, TList [TInt 5, TList [TInt 0], TList [TList []], TList []]]]]))
          validate (encodeDocument (docOf full)) >>= (@?= ExitSuccess)
          validate (encodeDocument (docOf full {tableWidths = [ColumnAuto, columnAbsolute 65536], tableStyle = Nothing})) >>= (@?= ExitSuccess)
          code <- validate old
          assertBool "tag 5" (code /= ExitSuccess)
    ]

-- | The external CDDL validator (golem-doc ADR 0001): GOLEM_CDDL or cddl on PATH.
cddlValidator :: IO (Maybe FilePath)
cddlValidator = do
  env <- lookupEnv "GOLEM_CDDL"
  case env of
    Just p -> pure (Just p)
    Nothing -> findExecutable "cddl"
