-- | itemNumbers and the number formats of lists (golem-driver ADR 0013).
module ListMarkersSpec (tests) where

import Golem.Doc.IR
import Golem.Doc.ListMarkers
import Golem.Syntax.Span
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

item :: Maybe Integer -> ListItem
item n = ListItem n [Block sp Nothing (Paragraph Nothing [Text sp "x"])]

tests :: TestTree
tests =
  testGroup
    "lists (golem-driver ADR 0013)"
    [ testCase "itemNumbers counts from 1, and on from @number" $ do
        itemNumbers [item Nothing, item Nothing, item Nothing] @?= [1, 2, 3]
        itemNumbers [item Nothing, item (Just 10), item Nothing] @?= [1, 10, 11],
      testCase "formatListNumber writes a number in each notation, or cannot" $ do
        formatListNumber NsArabic 3 @?= Just "3"
        formatListNumber NsKanji 3 @?= Just "三"
        formatListNumber NsCircled 3 @?= Just "③"
        formatListNumber NsCircled 21 @?= Just "㉑"
        formatListNumber NsCircled 50 @?= Just "㊿"
        formatListNumber NsCircled 51 @?= Nothing
        formatListNumber NsLowerAlpha 3 @?= Just "c"
        formatListNumber NsLowerAlpha 27 @?= Just "aa"
        formatListNumber NsUpperAlpha 52 @?= Just "AZ"
        formatListNumber NsUpperRoman 3 @?= Just "III"
        formatListNumber NsLowerRoman 1994 @?= Just "mcmxciv"
        formatListNumber NsUpperRoman 0 @?= Nothing
        formatListNumber NsUpperRoman 4000 @?= Nothing
        formatListNumber NsAiueo 3 @?= Just "ウ"
        formatListNumber NsAiueo 46 @?= Just "ン"
        formatListNumber NsAiueo 47 @?= Nothing
        formatListNumber NsIroha 3 @?= Just "ハ"
        formatListNumber NsIroha 47 @?= Just "ス"
        formatListNumber NsIroha 48 @?= Nothing,
      testCase "a number format has one placeholder and doubles literal braces; each error names its reason" $ do
        parseNumberFormat "{n}." @?= Right (NumberFormat "" NsBook ".")
        parseNumberFormat "({a})" @?= Right (NumberFormat "(" NsLowerAlpha ")")
        parseNumberFormat "{{{n}}}" @?= Right (NumberFormat "{" NsBook "}")
        parseNumberFormat "第{一}" @?= Right (NumberFormat "第" NsKanji "")
        parseNumberFormat "x" @?= Left "番号の差し込みがありません"
        parseNumberFormat "{n}{n}" @?= Left "番号の差し込みが二つ以上あります"
        parseNumberFormat "{x}" @?= Left "表にない差し込みです: {x}"
        parseNumberFormat "{n" @?= Left "{ が閉じていません。差し込みでない { は {{ と書きます"
        parseNumberFormat "{n}}" @?= Left "対応する { のない } があります。差し込みでない } は }} と書きます",
      testCase "renderNumberFormat writes a format back" $
        mapM_ (\f -> fmap renderNumberFormat (parseNumberFormat f) @?= Right f) ["{n}.", "({a})", "{{{n}}}", "{①}", "{イ}"],
      testCase "a list deeper than the given styles keeps the last style" $
        map (atDepth (pure 'a' <> pure 'b')) [1, 2, 3] @?= "abb",
      testCase "numbered items are listed with their numbers and depths, at their first blocks" $ do
        let inner = Block sp Nothing (OrderedList [item (Just 5)])
            second = SrcSpan (FileId 0) 3 4
            outer = Block sp Nothing (OrderedList [item Nothing, ListItem Nothing [Block second Nothing (Paragraph Nothing []), inner]])
        listSites [outer] @?= [ListSite 1 1 sp, ListSite 1 2 second, ListSite 2 5 sp]
    ]
