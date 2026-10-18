-- | Contributors, printings and the publisher person in the outputs (docs/adr ADR 0033).
module ColophonSpec (colophonTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Driver.Pdf (pdfXPeople)
import Golem.Epub (packageDocument)
import Golem.Eval.Expr (Env (..), evalExpr)
import Golem.Eval.Value (Value (..))
import Golem.Parser (parseAst)
import Golem.Parser.AST
import Golem.Project (Manifest (..), Metadata, parseManifest)
import Golem.Syntax
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | [metadata] with a publisher person, creators, contributors and three printings.
colophonMeta :: Text
colophonMeta =
  T.unlines
    [ "chapters = [\"a.gm\"]",
      "",
      "[metadata]",
      "id = \"urn:uuid:11111111-2222-4333-8444-555555555555\"",
      "title = \"T\"",
      "language = \"ja\"",
      "date = 2026-10-11",
      "publisher = \"ゴーレム書房\"",
      "publisher-person = \"佐藤 一郎\"",
      "",
      "[[metadata.creators]]",
      "name = \"山田 太郎\"",
      "role = \"author\"",
      "",
      "[[metadata.creators]]",
      "name = \"株式会社甲印刷\"",
      "role = \"printer\"",
      "",
      "[[metadata.contributors]]",
      "name = \"鈴木 花子\"",
      "reading = \"すずき はなこ\"",
      "role = \"editor\"",
      "",
      "[[metadata.contributors]]",
      "name = \"田中 次郎\"",
      "role = \"author\"",
      "",
      "[[metadata.contributors]]",
      "name = \"高橋 三郎\"",
      "role = \"cover-designer\"",
      "",
      "[[metadata.contributors]]",
      "name = \"株式会社乙製本\"",
      "role = \"binder\"",
      "",
      "[[metadata.printings]]",
      "edition = 1",
      "printing = 1",
      "date = 2026-10-16",
      "",
      "[[metadata.printings]]",
      "edition = 1",
      "printing = 2",
      "date = 2027-04-01",
      "",
      "[[metadata.printings]]",
      "edition = 2",
      "printing = 1",
      "date = 2028-01-10",
      ""
    ]

-- | The manifest without publisher-person, contributors and printings.
plainMeta :: Text
plainMeta = T.unlines (takeWhile (/= "[[metadata.creators]]") (filter (/= "publisher-person = \"佐藤 一郎\"") (T.lines colophonMeta)))

metadataOf :: Text -> IO Metadata
metadataOf src = either (assertFailure . show) (pure . manifestMetadata) (parseManifest (FileId 0) (src <> "\n[targets.html]\n"))

-- | An expression evaluated with the meta of a manifest: the value or the code.
evalMeta :: Text -> Text -> IO (Either Text Value)
evalMeta manifest src = do
  md <- metadataOf manifest
  let env = Env Map.empty (Map.singleton "meta" (metadataValues md))
  case parseAst (FileId 0) ("[= " <> src <> "]\n") of
    (File _ [Located _ (Paragraph [Located _ (Expr e)])], _, []) ->
      pure (either (Left . (\(DiagnosticCode c) -> c) . diagCode) Right (evalExpr env e))
    other -> assertFailure (show other)

-- | The lines of a text that start with a prefix.
linesWith :: Text -> Text -> [Text]
linesWith prefix = filter (T.isPrefixOf prefix) . T.lines

colophonTests :: [TestTree]
colophonTests =
  [ testCase "meta.roles, meta.printing and meta.publisher_person" $ do
      let ev = evalMeta colophonMeta
      ev "meta.roles.editor" >>= (@?= Right (VArray [VString "鈴木 花子"]))
      ev "meta.roles.cover_designer" >>= (@?= Right (VArray [VString "高橋 三郎"]))
      ev "meta.roles.printer" >>= (@?= Right (VArray [VString "株式会社甲印刷"]))
      ev "join(meta.roles.author, \"、\")" >>= (@?= Right (VString "山田 太郎、田中 次郎"))
      ev "meta.printing.number" >>= (@?= Right (VInt 1))
      ev "meta.printing.edition" >>= (@?= Right (VInt 2))
      ev "meta.printing.year" >>= (@?= Right (VInt 2028))
      -- 2028-01-10: month and day differ, so a swap shows
      ev "meta.printing.month" >>= (@?= Right (VInt 1))
      ev "meta.printing.day" >>= (@?= Right (VInt 10))
      ev "meta.printing.date" >>= (@?= Right (VString "2028-01-10"))
      ev "len(meta.printings)" >>= (@?= Right (VInt 3))
      ev "meta.publisher_person" >>= (@?= Right (VString "佐藤 一郎")),
    testCase "a book without a publisher has its publisher person" $ do
      let noPublisher = T.unlines (filter (/= "publisher = \"ゴーレム書房\"") (T.lines colophonMeta))
      evalMeta noPublisher "meta.publisher_person" >>= (@?= Right (VString "佐藤 一郎")),
    testCase "a role without items, printing without printings and publisher_person without it are G0202" $ do
      evalMeta colophonMeta "meta.roles.binder" >>= (@?= Right (VArray [VString "株式会社乙製本"]))
      evalMeta colophonMeta "meta.roles.translator" >>= (@?= Left "G0202")
      evalMeta plainMeta "meta.printing" >>= (@?= Left "G0202")
      evalMeta plainMeta "meta.publisher_person" >>= (@?= Left "G0202"),
    testCase "EPUB: creators and contributors with their codes; no printer, binder, printings or publisher person" $ do
      md <- metadataOf colophonMeta
      let opf = packageDocument (epubConfig md Nothing False) ["a.xhtml"] []
      linesWith "<dc:creator" opf @?= ["<dc:creator id=\"creator1\">山田 太郎</dc:creator>"]
      linesWith "<dc:contributor" opf
        @?= [ "<dc:contributor id=\"contributor1\">鈴木 花子</dc:contributor>",
              "<dc:contributor id=\"contributor2\">田中 次郎</dc:contributor>",
              "<dc:contributor id=\"contributor3\">高橋 三郎</dc:contributor>"
            ]
      [l | l <- T.lines opf, "property=\"role\"" `T.isInfixOf` l]
        @?= [ "<meta refines=\"#creator1\" property=\"role\" scheme=\"marc:relators\">aut</meta>",
              "<meta refines=\"#contributor1\" property=\"role\" scheme=\"marc:relators\">edt</meta>",
              "<meta refines=\"#contributor2\" property=\"role\" scheme=\"marc:relators\">aut</meta>",
              "<meta refines=\"#contributor3\" property=\"role\" scheme=\"marc:relators\">cov</meta>"
            ]
      linesWith "<meta refines=\"#contributor1\" property=\"file-as\"" opf @?= ["<meta refines=\"#contributor1\" property=\"file-as\">すずき はなこ</meta>"]
      linesWith "<dc:publisher" opf @?= ["<dc:publisher>ゴーレム書房</dc:publisher>"]
      assertBool "no printer, binder or publisher person" (not (any (`T.isInfixOf` opf) ["印刷", "製本", "佐藤", "2026-10-16", "2028-01-10"])),
    testCase "EPUB: a translator is trl" $ do
      md <- metadataOf (T.replace "role = \"author\"" "role = \"translator\"" plainMeta <> "\n[[metadata.creators]]\nname = \"訳者\"\nrole = \"translator\"\n")
      linesWith "<meta refines=\"#creator1\" property=\"role\"" (packageDocument (epubConfig md Nothing False) [] [])
        @?= ["<meta refines=\"#creator1\" property=\"role\" scheme=\"marc:relators\">trl</meta>"],
    testCase "XMP: creators and contributors without the printer and the binder" $ do
      md <- metadataOf colophonMeta
      pdfXPeople md @?= (["山田 太郎"], ["鈴木 花子", "田中 次郎", "高橋 三郎"]),
    testCase "a book with contributors and printings: two builds give the same bytes" $ do
      let once = withSystemTempDirectory "golem-colophon" $ \tmp -> do
            BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 colophonMeta <> "[targets.pdf]\n\n[targets.html]\n\n[targets.text]\nvariants = [\"horizontal\"]\n")
            writeStyleWithFont tmp horizontalStyle
            BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 "[= join(meta.roles.editor, \"、\")]\n\n@printings\n")
            r <- build (defaultOptions tmp) {optTargets = Just [TargetPdf, TargetHtml, TargetText], optFonts = fakeProvider}
            filter isError (brDiagnostics r) @?= []
            buildFiles (tmp </> "build")
      a <- once
      b <- once
      assertBool "files" (Map.size a >= 3)
      a @?= b
  ]
