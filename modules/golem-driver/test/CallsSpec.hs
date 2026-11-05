{- | The functions of .emet in a book (docs/adr/0162): commands, the
expression context, filters, the data types of the IR, and the errors of
an .emet that does not load.
-}
module CallsSpec (callsTests) where

import Control.Monad (forM)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Doc.IR
import Golem.Driver
import Golem.Emet.IR (decodeBlocks, decodeInlines, encodeBlocks, encodeInlines, runEnc)
import Golem.Eval.File (EvalResult (..))
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Syntax
import Hedgehog (forAll, property, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import IRGen (genDocument, genInline)
import Support
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, listDirectory)
import System.FilePath (takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.Hedgehog (testProperty)

book :: Text
book =
  T.unlines
    [ "pub inline \"tax-included\" taxIncluded :: Nat -> Inlines",
      "taxIncluded n = Inline.text (String.fromNat (div (n * 11) 10) ++ \"円\")",
      "",
      "pub inline price :: Nat -> (tax :: Bool = True) -> (unit :: String = \"円\") -> Inlines",
      "price n tax unit = Inline.text (String.fromNat n ++ unit ++ (tax ? \"（税込）\" : \"\"))",
      "",
      "pub inline \"emph-twice\" emphTwice :: Inlines -> Inlines",
      "emphTwice xs = Inline.style \"strong\" (xs ++ xs)",
      "",
      "pub inline \"first-text\" firstText :: Inlines -> Inlines",
      "firstText (Inline.Text s : _) = Inline.text (\"[\" ++ s ++ \"]\")",
      "firstText _ = []",
      "",
      "pub inline tags :: String -> Varargs String -> Inlines",
      "tags sep words = Inline.text (String.join sep words)",
      "",
      "pub block \"word-table\" wordTable :: String -> Blocks -> Blocks",
      "wordTable name body = Block.paragraph (Inline.text name) ++ body",
      "",
      "pub block rule :: Blocks",
      "rule = Block.paragraph (Inline.text \"――\")",
      "",
      "pub block heading :: Blocks",
      "heading = [Block.Heading 1 (Block.HeadingAttrs Nothing Nothing False False) (Inline.text \"見出し\")]",
      "",
      "pub block styled :: Blocks",
      "styled = Block.styled \"nonexistent\" (Inline.text \"x\")",
      "",
      "pub fn total :: List Nat -> Nat",
      "total xs = List.foldl add 0 xs",
      "  where {",
      "    add a b = a + b",
      "  }",
      "",
      "pub fn sum :: Varargs Nat -> Nat",
      "sum xs = total xs",
      "",
      "pub helper :: Nat",
      "helper = 1"
    ]

-- | A project of chapters, with files of .emet and more, and lines added to the manifest.
withBook :: [(FilePath, Text)] -> [(FilePath, Text)] -> Text -> (FilePath -> IO a) -> IO a
withBook chapters files extra k =
  withChapters "" chapters [] $ \tmp -> do
    TIO.appendFile (tmp </> "manifest.toml") ("\n" <> extra)
    mapM_ (\(p, t) -> createDirectoryIfMissing True (takeDirectory (tmp </> p)) >> BS.writeFile (tmp </> p) (TE.encodeUtf8 t)) files
    k tmp

evaluated :: FilePath -> IO Evaluated
evaluated tmp = evaluateProject Dev tmp >>= either (\f -> assertFailure (show (pfDiagnostics f)) >> fail "unreachable") pure

-- | The codes of the evaluation, without the notice of no style.toml.
codesIn :: Evaluated -> [Text]
codesIn e = [c | d <- evDiagnostics e, let DiagnosticCode c = diagCode d, c /= "G03023"]

-- | The blocks of a file of the project.
blocksOf :: Evaluated -> FilePath -> [Block]
blocksOf e path = concat [docBlocks (erDocument r) | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == path, Just r <- [Map.lookup fid (evResults e)]]

-- | The texts of the paragraphs of a file, a paragraph a list.
texts :: Evaluated -> FilePath -> [[Text]]
texts e path = [concatMap inlineTexts is | Block _ _ (Paragraph _ is) <- blocksOf e path]
  where
    inlineTexts = \case
      Text _ t -> [t]
      CharStyle _ _ xs -> concatMap inlineTexts xs
      _ -> []

imported :: Text -> Text
imported body = "@import functions/book.emet as book\n\n" <> body

-- | The files under a folder and their bytes, by their paths from it.
filesUnder :: FilePath -> IO [(FilePath, BS.ByteString)]
filesUnder dir = do
  entries <- sort <$> listDirectory dir
  concat
    <$> forM
      entries
      ( \e -> do
          isDir <- doesDirectoryExist (dir </> e)
          if isDir then map (first (e </>)) <$> filesUnder (dir </> e) else (\b -> [(e, b)]) <$> BS.readFile (dir </> e)
      )

callsTests :: TestTree
callsTests =
  testGroup
    "the functions of .emet in a book (docs/adr/0162)"
    [ testProperty "the data types of the IR give back any IR, with its spans, labels and numbers of notes" $ property $ do
        doc <- forAll genDocument
        let sp = mkSpan (FileId 9) 1 2
            (r, carried) = runEnc (encodeBlocks (docBlocks doc))
        decodeBlocks carried sp r === Right (docBlocks doc)
        is <- forAll (Gen.list (Range.linear 0 5) genInline)
        let (ri, ci) = runEnc (encodeInlines is)
        decodeInlines ci sp ri === Right is,
      testCase "the fixture of the functions builds the same bytes and diagnostics, twice, in parallel and in sequence" $ do
        runs <- forM [True, True, False] $ \par -> withSystemTempDirectory "golem-functions" $ \tmp -> do
          copyTree "test/fixtures/functions" tmp
          r <- build (defaultOptions tmp) {optParallel = par}
          outs <- filesUnder (tmp </> "build")
          pure ([(diagCode d, diagSpan d, diagMessage d) | d <- brDiagnostics r], outs)
        case runs of
          run0 : rest -> do
            [c | (c, _, _) <- fst run0, c /= DiagnosticCode "G03023"] @?= []
            assertBool "outputs" (not (null (snd run0)))
            mapM_ (@?= run0) rest
          [] -> assertFailure "no run",
      testCase "an inline command of a namespace is the inlines the function returns, at the call" $
        withBook [("a.gm", imported "[book.tax-included 1000]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          texts e "a.gm" @?= [["1100円"]]
          let start = BS.length (TE.encodeUtf8 (imported ""))
          [(spanStart sp, spanEnd sp) | Block _ _ (Paragraph _ is) <- blocksOf e "a.gm", Text sp _ <- is] @?= [(start, start + T.length "[book.tax-included 1000]")],
      testCase "the namespace is the file's: a file without @import has G02022" $
        withBook [("a.gm", imported "[book.tax-included 1000]\n"), ("b.gm", "[book.tax-included 1000]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["G02022"],
      testCase "a prose slot is the Inlines of the function, a note in it stays a note, and its text can be matched" $
        withBook [("a.gm", imported "[book.emph-twice: 本文[note: 注]]\n\n[book.first-text: 語[note: 注]]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          texts e "a.gm" @?= [["本文", "本文"], ["[語]"]]
          length [() | Block _ _ (Paragraph _ [CharStyle _ _ xs]) <- blocksOf e "a.gm", Note {} <- xs] @?= 2,
      testCase "the body of a block command, and @label on the first block it returns" $
        withBook [("a.gm", imported "@label words\n@book.word-table 語彙\n  本体。\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          [(l, t) | Block _ l (Paragraph _ [Text _ t]) <- take 2 (blocksOf e "a.gm")] @?= [(Just "words", "語彙"), (Nothing, "本体。")],
      testCase "keyword arguments: the defaults, the values given, and G02119" $
        withBook [("a.gm", imported "[book.price 1000]\n\n[book.price 1000 tax=false unit=\" 円\"]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          texts e "a.gm" @?= [["1000円（税込）"], ["1000 円"]],
      testCase "the errors of the arguments of .gm" $
        withBook [("a.gm", imported "[book.price 1000 rate=1]\n\n[book.tax-included]\n\n[book.tax-included abc]\n\n[book.emph-twice]\n\n@book.rule\n  本体\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["G02119", "G02120", "G02121", "G02122", "G02123"],
      testCase "pub fn in the expression context; a function that is no pub fn is G02002, which tells why" $
        withBook [("a.gm", imported "[= book.total([1, 2])]、[= book.sum(1, 2, 3)]、[= book.sum()]\n\n[= book.helper()]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["G02002"]
          take 1 (texts e "a.gm") @?= [["3、6、0"]]
          assertBool "pub fn" (any (("pub fn" `T.isInfixOf`) . diagMessage) (evDiagnostics e)),
      testCase "variable arguments" $
        withBook [("a.gm", imported "[book.tags ・ 組版 校正]\n\n[book.tags ・]x\n\n[book.tags]\n\n[book.tags ・ 1]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["G02120", "G02121"]
          take 2 (texts e "a.gm") @?= [["組版・校正"], ["x"]],
      testCase "a block command that returns a heading is E06104; a paragraph style that is not defined is G02047" $
        withBook [("a.gm", imported "@book.heading\n\n@book.styled\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["E06104", "G02047"],
      testCase "a .emet with an error of types: no G02022, G02009 or G02002 through its namespace" $
        withBook [("a.gm", imported "[book.x 1]\n\n@book.y\n\n[= book.z(1)]\n")] [("functions/book.emet", "pub inline f :: Nat -> Inlines\nf n = n\n")] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["E02101"],
      testCase "a filter of a .emet, with a ruby in a ruby, is E06104 at the top of the file"
        $ withBook
          [("a.gm", "本文。\n")]
          [("functions/f.emet", "pub filter nest :: Blocks -> Blocks\nnest bs = bs ++ Block.paragraph [Inline.Ruby [Inline.RubySegment (Inline.ruby \"a\" \"b\") Nothing]]\n")]
          "[[filters]]\nfunction = \"functions/f.emet\"\nfilter = \"nest\"\nfiles = [\"a.gm\"]\n"
        $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["E06104"]
          [spanStart (diagSpan d) | d <- evDiagnostics e, diagCode d == DiagnosticCode "E06104"] @?= [0],
      testCase "a filter of a .emet rewrites the document; a node it makes is at the top of the file"
        $ withBook
          [("a.gm", "本文。\n")]
          [("functions/f.emet", "pub filter \"add-end\" addEnd :: Blocks -> Blocks\naddEnd bs = bs ++ Block.paragraph (Inline.text \"終\")\n")]
          "[[filters]]\nfunction = \"functions/f.emet\"\nfilter = \"add-end\"\nfiles = [\"a.gm\"]\n"
        $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          texts e "a.gm" @?= [["本文。"], ["終"]]
          [spanStart sp | Block sp _ (Paragraph _ [Text _ "終"]) <- blocksOf e "a.gm"] @?= [0]
          [spanStart sp | Block sp _ (Paragraph _ [Text _ "本文。"]) <- blocksOf e "a.gm"] @?= [0]
          [spanEnd sp > 0 | Block sp _ (Paragraph _ [Text _ "本文。"]) <- blocksOf e "a.gm"] @?= [True],
      testCase "plugin and function both, or neither, in [[filters]] are G03001" $ do
        withBook [("a.gm", "x\n")] [] "[[filters]]\nplugin = \"p\"\nfunction = \"f.emet\"\nfilter = \"x\"\nfiles = [\"a.gm\"]\n" $ \tmp ->
          evaluateProject Dev tmp >>= \case
            Left f -> [c | DiagnosticCode c <- map diagCode (pfDiagnostics f)] @?= ["G03001"]
            Right _ -> assertFailure "no error"
        withBook [("a.gm", "x\n")] [] "[[filters]]\nfilter = \"x\"\nfiles = [\"a.gm\"]\n" $ \tmp ->
          evaluateProject Dev tmp >>= \case
            Left f -> [c | DiagnosticCode c <- map diagCode (pfDiagnostics f)] @?= ["G03001"]
            Right _ -> assertFailure "no error",
      testCase "a filter the .emet has not is G03001; a .emet of [[filters]] that is missing is G03002" $ do
        withBook [("a.gm", "x\n")] [("f.emet", "pub filter k :: Blocks -> Blocks\nk bs = bs\n")] "[[filters]]\nfunction = \"f.emet\"\nfilter = \"nothing\"\nfiles = [\"a.gm\"]\n" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["G03001"]
        withBook [("a.gm", "x\n")] [] "[[filters]]\nfunction = \"none.emet\"\nfilter = \"k\"\nfiles = [\"a.gm\"]\n" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["G03002"],
      testCase "a requirement of a .emet of [[filters]] not in [functions.requires] is E05104 in a build"
        $ withBook
          [("a.gm", "x\n")]
          [("f.emet", "pub filter k :: Blocks -> <file \"w.tsv\"> Blocks\nk bs = bs ++ Block.paragraph (Inline.text (File.read \"w.tsv\"))\n"), ("w.tsv", "w\n")]
          "[[filters]]\nfunction = \"f.emet\"\nfilter = \"k\"\nfiles = [\"a.gm\"]\n"
        $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["E05104"],
      testCase "a requirement of a .emet of @import not in [functions.requires] is E05104 in a build" $
        withBook [("a.gm", imported "[book.w]\n")] [("functions/book.emet", "pub inline w :: <file \"w.tsv\"> Inlines\nw = Inline.text (File.read \"w.tsv\")\n"), ("w.tsv", "w\n")] "" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= ["E05104"],
      testCase "File.read of a file of [functions.requires] in a command" $
        withBook [("a.gm", imported "[book.w]\n")] [("functions/book.emet", "pub inline w :: <file \"w.tsv\"> Inlines\nw = Inline.text (String.trim (File.read \"w.tsv\"))\n"), ("w.tsv", "語\n")] "[functions.requires]\nfile = [\"w.tsv\"]\n" $ \tmp -> do
          e <- evaluated tmp
          codesIn e @?= []
          texts e "a.gm" @?= [["語"]],
      testCase "the .emet the project uses are watched with the files of @table" $
        withBook [("a.gm", imported "[book.tax-included 1]\n")] [("functions/book.emet", book)] "" $ \tmp -> do
          e <- evaluated tmp
          assertBool (show (evTableFiles e)) ("functions/book.emet" `elem` evTableFiles e),
      testCase "the diagnostics of a .emet point into it" $
        withBook [("a.gm", imported "[book.x]\n")] [("functions/book.emet", "pub inline f :: Nat -> Inlines\nf n = n\n")] "" $ \tmp -> do
          e <- evaluated tmp
          sort [siPath si | d <- evDiagnostics e, diagCode d == DiagnosticCode "E02101", Just si <- [Map.lookup (spanFile (diagSpan d)) (evAssetSources e)]] @?= ["functions/book.emet"]
    ]
