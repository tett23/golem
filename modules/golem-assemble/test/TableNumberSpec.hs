-- | Table numbers, [ref-number] and [ref-title] of tables (docs/adr/0262).
module TableNumberSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble
import Golem.Doc.IR
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

cfg :: AssembleConfig
cfg = AssembleConfig (Map.fromList [(1, "第{n}章")]) "図{chapter}-{n}" Map.empty NumberPerFile [] "リスト{chapter}-{n}" "表{chapter}-{n}" Map.empty 16

sp :: Int -> SrcSpan
sp s = mkSpan (FileId 1) s (s + 1)

noEval :: DocValues -> SrcSpan -> DeferredExpr -> Either Diagnostic Text
noEval _ _ _ = Right ""

codes :: [Diagnostic] -> [Text]
codes = map (\d -> let DiagnosticCode c = diagCode d in c)

-- | The kinds of block of the small documents.
data Kind = Chapter | Captioned | NoNumber | Plain | Fig | Listing
  deriving stock (Eq, Show, Enum, Bounded)

block :: Int -> Kind -> Block
block s = \case
  Chapter -> Block (sp s) Nothing Nothing (Heading 1 noHeadingAttrs [Text (sp s) "章"])
  Captioned -> table (Just [Text (sp s) "表題"]) False
  NoNumber -> table (Just [Text (sp s) "表題"]) True
  Plain -> table Nothing False
  Fig -> Block (sp s) Nothing Nothing (FigureBlock (Figure "a.png" Nothing "alt" Nothing Nothing [] Nothing False False))
  Listing -> Block (sp s) Nothing Nothing (CodeBlock (Code Nothing Nothing Nothing (Just [Text (sp s) "例"]) False [] False))
  where
    table cap nn = Block (sp s) Nothing Nothing (TableBlock (plainTable [AlignDefault] [[Text (sp s) "a"]] []) {tableCaption = cap, tableNoNumber = nn})

-- | Every sequence of the kinds of up to n blocks.
sequencesUpTo :: Int -> [[Kind]]
sequencesUpTo n = concatMap (\k -> sequenceA (replicate k [minBound .. maxBound])) [0 .. n]

-- | The table numbers of a document of the kinds, by the place of each block.
numbersOf :: [(Int, Kind)] -> Map.Map SrcSpan Text
numbersOf ks = bookTables (fst (assemble cfg {acTableFormat = "{n}"} noEval [Document (FileId 1) [block s k | (s, k) <- ks]]))

-- | The numbers I1 expects: 1, 2, ... for each captioned table without @nonumber, from 1 after each chapter heading.
expected :: [(Int, Kind)] -> Map.Map SrcSpan Text
expected = Map.fromList . go (0 :: Int)
  where
    go _ [] = []
    go n ((s, k) : rest) = case k of
      Chapter -> go 0 rest
      Captioned -> (sp s, T.pack (show (n + 1))) : go (n + 1) rest
      _ -> go n rest

tests :: TestTree
tests =
  testGroup
    "table numbers (docs/adr/0262)"
    [ testCase "I1: in every chapter the captioned tables without @nonumber take 1, 2, ... in order, every sequence of up to 5 blocks" $
        mapM_
          ( \ks ->
              let placed = zip [0, 2 ..] ks
               in assertEqual (show ks) (expected placed) (numbersOf placed)
          )
          (sequencesUpTo 5),
      testCase "I2: adding or removing figures, code blocks, @nonumber tables and plain tables changes no table number, every sequence of up to 5 blocks" $
        mapM_
          ( \ks ->
              let placed = zip [0, 2 ..] ks
                  kept = filter ((`elem` [Chapter, Captioned]) . snd) placed
               in assertEqual (show ks) (numbersOf kept) (numbersOf placed)
          )
          (sequencesUpTo 5),
      testCase "I3: [ref-number] of a numbered table is chapter-table, [ref-title] its caption without index marks" $ do
        let caption = [Text (sp 3) "出力の", IndexMark (sp 3) (IndexEntry ["形式"] ["けいしき"]), Text (sp 3) "形式"]
            tbl = (block 3 Captioned) {blockLabel = Just "t"}
            withCaption = tbl {blockBody = case blockBody tbl of TableBlock t -> TableBlock t {tableCaption = Just caption}; b -> b}
            refs = Block (sp 5) Nothing Nothing (Paragraph Nothing [Ref (sp 6) RefNumber "t", Ref (sp 7) RefTitle "t"])
            (book, ds) = assemble cfg noEval [Document (FileId 1) [block 0 Chapter, block 1 Captioned, withCaption, refs]]
        ds @?= []
        Map.elems (bookTables book) @?= ["表1-1", "表1-2"]
        case bookDocs book of
          [Document _ [_, _, _, Block _ _ _ (Paragraph Nothing is)]] ->
            is @?= [Resolved (sp 6) RefNumber "t" [Text (sp 6) "1-2"], Resolved (sp 7) RefTitle "t" [Text (sp 7) "出力の", Text (sp 7) "形式"]]
          other -> assertFailure (show other),
      testCase "I3: [ref-number] of a table without a number is one G04005, [ref-title] of one without a caption one G04006" $ do
        let lbl l b = b {blockLabel = Just l}
            refs = Block (sp 9) Nothing Nothing (Paragraph Nothing [Ref (sp 10) RefNumber "n", Ref (sp 11) RefTitle "n", Ref (sp 12) RefNumber "p", Ref (sp 13) RefTitle "p"])
            (_, ds) = assemble cfg noEval [Document (FileId 1) [block 0 Chapter, lbl "n" (block 1 NoNumber), lbl "p" (block 2 Plain), refs]]
        map (\d -> (codes [d], diagSpan d)) ds @?= [(["G04005"], sp 10), (["G04005"], sp 12), (["G04006"], sp 13)],
      testCase "G04004 for a table outside a chapter with a format of {chapter}, none with one without it" $ do
        let docs = [Document (FileId 1) [block 0 Captioned, block 1 Chapter, block 2 Captioned]]
            msg = "章の外にある図版、表、コードには、章番号を使う番号を振れません。章は番号を持つ階層 1 の見出しから始まります。番号を振らないなら @nonumber を付けます"
        [(codes [d], diagSpan d, diagMessage d) | d <- snd (assemble cfg noEval docs)] @?= [(["G04004"], sp 0, msg)]
        snd (assemble cfg {acTableFormat = "表{n}"} noEval docs) @?= []
        Map.elems (bookTables (fst (assemble cfg {acTableFormat = "表{n}"} noEval docs))) @?= ["表1", "表1"]
        snd (assemble cfg noEval [Document (FileId 1) [block 0 NoNumber, block 1 Plain]]) @?= [],
      testCase "G04100: a number the format cannot write, at the table; the table has no number text" $ do
        let (book, ds) = assemble cfg {acTableFormat = "表{n:iroha}"} noEval [Document (FileId 1) (block 0 Chapter : [block s Captioned | s <- [1 .. 48]])]
        [(codes [d], diagSpan d, diagMessage d) | d <- ds] @?= [(["G04100"], sp 48, "[tables] の number 表{n:iroha} の {n:iroha} では、48 を表せません")]
        Map.size (bookTables book) @?= 47
        Map.member (sp 48) (bookTables book) @?= False
    ]
