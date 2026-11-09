{- | The sample library of .emet functions (test/fixtures/emet-samples):
twenty functions an editor or an operator of a Japanese book would write,
of every kind. The book builds without diagnostics, its plain text shows
what each function gives, and the IR has what the text does not show.
-}
module EmetSamplesSpec (emetSamplesTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Doc.IR
import Golem.Driver
import Golem.Eval.File (EvalResult (..))
import Golem.Project (Project (..), ProjectFailure (..), SourceFile (..))
import Golem.Syntax
import Support (copyTree)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

emetSamplesTests :: TestTree
emetSamplesTests =
  testGroup
    "the sample library of .emet functions (fixtures/emet-samples)"
    [ testCase "the book builds without diagnostics, and its plain text shows what each function gives" $
        withSamples $ \tmp -> do
          r <- build (defaultOptions tmp)
          map diagCode (brDiagnostics r) @?= []
          mapM_
            ( \(name, expected) -> do
                got <- TE.decodeUtf8 <$> BS.readFile (tmp </> "build" </> "text" </> "horizontal" </> name)
                T.lines got @?= expected
            )
            plainTexts,
      testCase "the IR of the functions whose output the plain text does not show" $
        withSamples $ \tmp -> do
          e <- evaluateProject Dev tmp >>= either (\f -> assertFailure (show (pfDiagnostics f)) >> fail "unreachable") pure
          map diagCode (evDiagnostics e) @?= []
          let numbers = inlinesOf (blocksOf e "numbers.gm")
              text = blocksOf e "text.gm"
              blocks = blocksOf e "blocks.gm"
              filters = blocksOf e "filters.gm"
          -- 7. auto-tcy: two digits as tate-chu-yoko
          [t | Tcy _ t <- numbers] @?= ["12"]
          -- 9. unit: a quarter-em aki between the value and the unit
          [a | Aki _ a <- numbers] @?= [AkiZw 0.25]
          -- 6. mono: a segment of ruby a character
          [map segment segs | Ruby _ _ segs <- inlinesOf text] @?= [[("漢", Just "かん"), ("字", Just "じ")]]
          -- 10. see: a reference to the page of a label
          [(k, l) | Ref _ k l <- inlinesOf text] @?= [(RefPage, "terms")]
          [l | Block _ (Just l) Nothing _ <- text] @?= ["terms"]
          -- 11. term: an index entry with its reading, and the index
          [(ieTerms i, ieReadings i) | IndexMark _ i <- inlinesOf text] @?= [(["組版"], ["くみはん"])]
          [() | Block _ _ _ (ChannelOutput IndexOutput) <- text] @?= [()]
          -- 12. box: the title and the body in their paragraph styles
          [(s, plainOf is) | Block _ _ _ (Paragraph s is) <- blocks]
            @?= [ (Just "box-title", "【注意】"),
                  (Just "box", "刷り直しのたびに奥付を確かめます。"),
                  (Just "box-title", "【コラム】"),
                  (Just "box", "活版の時代には、組版は職人の仕事でした。")
                ]
          -- 13. glossary: a definition list whose terms have ruby
          [[map segment segs | [Ruby _ _ segs] <- ts] | Block _ _ _ (DefList gs) <- blocks, DefGroup ts _ <- gs]
            @?= [[[("組版", Just "くみはん")]], [[("禁則", Just "きんそく")]], [[("校正", Just "こうせい")]]]
          -- 14. price-table: the numeric columns aligned right
          [as | Block _ _ _ (TableBlock Table {tableAligns = as}) <- blocks] @?= [[AlignDefault, AlignRight, AlignRight]]
          -- 15. checklist: a bullet list of four items
          [length items | Block _ _ _ (BulletList items) <- blocks] @?= [4]
          -- 18. first-ruby: the first occurrence of each word, the longest word first
          [map segment segs | Ruby _ _ segs <- inlinesOf filters]
            @?= [[("薔薇", Just "ばら")], [("檸檬水", Just "れもんすい")], [("檸檬", Just "れもん")], [("苺", Just "いちご")]]
          -- 20. halfwidth: the code block is left alone
          [map clText (codeLines c) | Block _ _ _ (CodeBlock c) <- filters] @?= [["ＧＯＬＥＭ"]]
    ]

withSamples :: (FilePath -> IO a) -> IO a
withSamples k = withSystemTempDirectory "golem-emet-samples" $ \tmp -> do
  copyTree "test/fixtures/emet-samples" tmp
  k tmp

-- | The lines of the plain text of each chapter, set horizontally.
plainTexts :: [(FilePath, [Text])]
plainTexts =
  [ ( "numbers.txt",
      [ "1\12288数",
        "",
        "税込みの価格は2178円です。",
        "",
        "総額は1,234,567円です。",
        "",
        "漢数字は千二百三十四、二万、二〇二六です。",
        "",
        "丸数字は③、⑳、(21)です。",
        "",
        "縦中横は12、二千二十六です。",
        "",
        "寸法は10mmです。",
        "",
        "範囲はpp. 12–15とp. 12です。"
      ]
    ),
    ( "dates.txt",
      [ "2\12288日付",
        "",
        "今年は令和八年、改元の年は令和元年、平成元年は平成元年一月八日、その前日は昭和六十四年一月七日です。",
        "",
        "発行日は2026年11月6日です。日付でない文字列は近刊のままです。"
      ]
    ),
    ( "text.txt",
      [ "3\12288文字",
        "",
        "漢字（かんじ）には一字ずつルビを付けます。",
        "",
        "この節は原稿用紙で1枚、8字です。",
        "",
        "組版の語は索引に載ります。",
        "",
        "用語は→ p.「」を見てください。"
      ]
    ),
    ( "blocks.txt",
      [ "4\12288ブロック",
        "",
        "【注意】",
        "",
        "刷り直しのたびに奥付を確かめます。",
        "",
        "【コラム】",
        "",
        "活版の時代には、組版は職人の仕事でした。",
        "",
        "組版（くみはん）",
        "\12288文字と図版をページに配置すること。",
        "禁則（きんそく）",
        "\12288行頭や行末に置けない文字を避ける規則。",
        "校正（こうせい）",
        "\12288校正刷りを原稿と突き合わせて誤りを正すこと。",
        "",
        "品名\t部数\t単価",
        "四六判並製\t3,000\t1,980",
        "A5判上製\t500\t12,800",
        "文庫\t20,000\t880",
        "",
        "・☐ 初校",
        "・☐ 再校",
        "・☐ 索引",
        "・☐ 奥付"
      ]
    ),
    ( "filters.txt",
      [ "5\12288フィルタ",
        "",
        "薔薇（ばら）の花と檸檬水（れもんすい）。薔薇も檸檬（れもん）も好きです。",
        "",
        "・檸檬の木と苺（いちご）の畑",
        "",
        "ここに書いてください。それはできる。",
        "",
        "GOLEM\12288" <> "2026年版を使います。",
        "",
        "ＧＯＬＥＭ"
      ]
    )
  ]

-- | The blocks of a file of the project.
blocksOf :: Evaluated -> FilePath -> [Block]
blocksOf e path = concat [docBlocks (erDocument r) | (fid, sf) <- Map.toList (projectSources (evProject e)), sfPath sf == path, Just r <- [Map.lookup fid (evResults e)]]

-- | Every inline of the blocks, in paragraphs, lists, definition lists and tables, and the inlines in them.
inlinesOf :: [Block] -> [Inline]
inlinesOf = concatMap (\(Block _ _ _ b) -> inBody b)
  where
    inBody = \case
      Paragraph _ is -> deep is
      Heading _ _ is -> deep is
      BulletList items -> concatMap (inlinesOf . itemBlocks) items
      OrderedList items -> concatMap (inlinesOf . itemBlocks) items
      DefList gs -> concat [concatMap deep ts <> concatMap inlinesOf ds | DefGroup ts ds <- gs]
      TableBlock Table {tableHeader = h, tableRows = rows} -> concatMap deep h <> concatMap (concatMap deep) rows
      _ -> []
    deep = concatMap (\i -> i : children i)
    children = \case
      Kenten _ _ xs -> deep xs
      Color _ _ xs -> deep xs
      CharStyle _ _ xs -> deep xs
      Note _ _ bs -> concatMap deep (noteParagraphs bs)
      Sidenote _ _ bs -> concatMap deep (noteParagraphs bs)
      _ -> []

-- | The base and the reading of a segment of ruby.
segment :: RubySegment -> (Text, Maybe Text)
segment (RubySegment base reading) = (T.concat [t | Text _ t <- base], reading)

plainOf :: [Inline] -> Text
plainOf is = T.concat [t | Text _ t <- is]
