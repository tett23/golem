module Main (main) where

import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text.Encoding (encodeUtf8)
import Golem.Fixtures
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main = defaultMain tests

tests :: TestTree
tests =
  testGroup
    "golem-fixtures (docs/adr/0023)"
    [ testGroup "gutenberg-play" (map (caseOf GutenbergPlay) playCases),
      testGroup "aozora" (map (caseOf Aozora) aozoraCases),
      testCase "the names of the converters" $ do
        converterNamed "gutenberg-play" @?= Just GutenbergPlay
        converterNamed "aozora" @?= Just Aozora
        converterNamed "python" @?= Nothing,
      testCase "a text that is not the expected one is an error" $ do
        assertBool "no Gutenberg markers" (isLeft (convertBytes GutenbergPlay "no markers\n"))
        assertBool "no dashed lines" (isLeft (convertBytes Aozora "title\nauthor\n"))
        assertBool "not UTF-8" (isLeft (convertBytes Aozora (BS.pack [0x82, 0xa0])))
    ]

-- The expected outputs were made by applying the Python scripts that these
-- converters replace (scripts/fixtures/gutenberg_play_to_gm.py and
-- aozora_to_gm.py) to the inputs.
caseOf :: Converter -> (String, Text, Text) -> TestTree
caseOf conv (name, input, expected) =
  testCase name (convertBytes conv (encodeUtf8 input) @?= Right (encodeUtf8 expected))

playCases :: [(String, Text, Text)]
playCases =
  [ ( "speaker names and italic",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.[1]\13\&\nPROSPERO, the right Duke of Milan.\13\&\n\13\&\nACT I.\13\&\n\13\&\n_Alon._ Good boatswain, have _care_. Where's the master?\13\&\n\13\&\n_Boats._ Do you not hear him? You mar our labour: keep _your\13\&\ncabins_: you do assist the storm.\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n- PROSPERO, the right Duke of Milan.\n\n@nonumber\n# Act I\n\n[strong: Alon.] Good boatswain, have [italic: care]. Where's the master?\n\n[strong: Boats.] Do you not hear him? You mar our labour: keep [italic: your cabins]: you do assist the storm.\n"
    ),
    ( "verse speeches of two lines or more, and a prose speech",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.\13\&\n\13\&\nACT I.\13\&\n\13\&\n_Pros._ Thou poisonous slave, got by the devil himself\13\&\nUpon thy wicked dam, come forth!\13\&\n                                  Come, thou tortoise! when?\13\&\n\13\&\n_Gon._ I have great comfort from this fellow: methinks he hath\13\&\nno drowning mark upon him; his complexion is perfect gallows.\13\&\n\13\&\n_Ari._ [_Aside_] Thou dost; and I will tell thee\13\&\n[_Exit._]\13\&\n[_Within_] 'Tis \"Well\" so.\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n\n@nonumber\n# Act I\n\n@style verse\n  [strong: Pros.] Thou poisonous slave, got by the devil himself\n  Upon thy wicked dam, come forth!\n  Come, thou tortoise! when?\n\n[strong: Gon.] I have great comfort from this fellow: methinks he hath no drowning mark upon him; his complexion is perfect gallows.\n\n@style verse\n  [strong: Ari.] \\[[italic: Aside]] Thou dost; and I will tell thee\n  \\[[italic: Exit.]]\n  \\[[italic: Within]] 'Tis \"Well\" so.\n"
    ),
    ( "indented songs and masque speeches",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.\13\&\n\13\&\nACT IV.\13\&\n\13\&\n    Full fathom five thy father lies;\13\&\n      Of his bones are coral made;\13\&\n\13\&\n  _Iris._ Ceres, most bounteous lady, thy rich leas\13\&\n    Of wheat, rye, barley, vetches, oats, and pease;\13\&\n\13\&\n[_Sings._ The master, the swabber, the boatswain, and I,\13\&\n    The gunner, and his mate,\13\&\n\13\&\n    _Ceres._ not a song\13\&\n    second line\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n\n@nonumber\n# Act IV\n\n@style verse\n  Full fathom five thy father lies;\n  Of his bones are coral made;\n\n@style verse\n  [strong: Iris.] Ceres, most bounteous lady, thy rich leas\n  Of wheat, rye, barley, vetches, oats, and pease;\n\n@style verse\n  \\[[italic: Sings.] The master, the swabber, the boatswain, and I,\n  The gunner, and his mate,\n\n[italic: Ceres.] not a song second line\n"
    ),
    ( "line numbers, dashes and special line starts",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.\13\&\n\13\&\nACT I.\13\&\n\13\&\n_Pros._ My brother and thy uncle, call'd Antonio,--   70\13\&\nI pray thee, mark me,--that a brother should   \13\&\nBe so perfidious!--he whom next thyself    75\13\&\n\13\&\n# not a heading, nor - a list\13\&\n\13\&\n_Stand._ word 1990\13\&\n=lowercase continuation\13\&\n\13\&\n+ plus in a paragraph  12\13\&\n\13\&\n_Pros._ One\13\&\n|Two\13\&\nThree --  4\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n\n@nonumber\n# Act I\n\n@style verse\n  [strong: Pros.] My brother and thy uncle, call'd Antonio,—\n  I pray thee, mark me,—that a brother should\n  Be so perfidious!—he whom next thyself\n\n\\# not a heading, nor - a list\n\n[strong: Stand.] word 1990 =lowercase continuation\n\n\\+ plus in a paragraph\n\n[strong: Pros.] One |Two Three —\n"
    ),
    ( "stage directions",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.\13\&\n\13\&\nACT I.\13\&\n\13\&\n[_Enter Mariners, wet._]\13\&\n\13\&\n[_Exeunt._\13\&\n\13\&\n[_A confused noise within: 'Mercy on us!'--'We split!'_]\13\&\n\13\&\n_Enter_ PROSPERO _and_ MIRANDA [and %%] back\\slash.\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n\n@nonumber\n# Act I\n\n\\[[italic: Enter Mariners, wet.]]\n\n\\[[italic: Exeunt.]\n\n\\[[italic: A confused noise within: 'Mercy on us!'—'We split!']]\n\n[italic: Enter] PROSPERO [italic: and] MIRANDA \\[and \\%%] back\\\\slash.\n"
    ),
    ( "acts, scenes and notes",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO.[12]\13\&\n\13\&\nSCENE--A ship at Sea: an uninhabited Island.\13\&\n\13\&\nTHE TEMPEST.\13\&\n\13\&\nACT I.\13\&\n\13\&\nSCENE I. _On a ship at sea: a tempestuous noise\13\&\nof thunder and lightning heard._\13\&\n\13\&\n_Mast._ Boatswain!\13\&\n\13\&\nFootnotes:\13\&\n\13\&\n   1: A footnote.\13\&\n\13\&\n  12-14: Another.\13\&\n\13\&\nNotes: I. 1.\13\&\n\13\&\nnote text\13\&\n\13\&\nSCENE II. in the notes\13\&\n\13\&\n  ACT II. indented\13\&\n\13\&\nACT II.\13\&\n\13\&\nSCENE II.\13\&\nAnother part of the island.\13\&\n\13\&\nSCENE III.\13\&\n\13\&\nEPILOGUE.\13\&\nSPOKEN BY PROSPERO.\13\&\n  Now my charms\13\&\n\13\&\nEPILOGUE.\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO.\n\nSCENE—A ship at Sea: an uninhabited Island.\n\n@nonumber\n# Act I\n\n@nonumber\n## Scene I\n\n[italic: On a ship at sea: a tempestuous noise of thunder and lightning heard.]\n\n[strong: Mast.] Boatswain!\n\n@nonumber\n## Scene II\n\nin the notes\n\nACT II. indented\n\n@nonumber\n# Act II\n\n@nonumber\n## Scene II\n\nAnother part of the island.\n\n@nonumber\n## Scene III\n\n@nonumber\n# Epilogue\n\nSPOKEN BY PROSPERO. Now my charms\n\n@nonumber\n# Epilogue\n"
    ),
    ( "italic across the lines of verse",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.\13\&\n\13\&\nACT I.\13\&\n\13\&\n_Ari._ _Full fathom five thy father lies;\13\&\nOf his bones are coral made_; and _then_\13\&\nThose are _pearls [x] that | were\13\&\nHis eyes:_\13\&\n  _ _  \13\&\n_Stand._ More\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n\n@nonumber\n# Act I\n\n[strong: Ari.] [italic: Full fathom five thy father lies; Of his bones are coral made]; and [italic: then] Those are [italic: pearls \\[x\\] that \\| were His eyes:]    [italic: Stand.] More\n"
    ),
    ( "verse with italic over the line ends",
      "\65279\&The Project Gutenberg eBook of The Tempest\13\&\n\13\&\n*** START OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nTitle page\13\&\n\13\&\nDRAMATIS PERSONÆ.\13\&\n\13\&\nALONSO, King of Naples.\13\&\n\13\&\nACT I.\13\&\n\13\&\n_Ari._ _Full fathom five thy father lies;\13\&\nOf his bones are coral made;_ and _then\13\&\n    _ _\13\&\nThose are pearls [x] that | were_ his eyes.\13\&\n  And %%% 3\13\&\n\13\&\nNOTES.\13\&\n\13\&\nA note.\13\&\n*** END OF THE PROJECT GUTENBERG EBOOK THE TEMPEST ***\13\&\nLicence\13\&\n",
      "@nonumber\n# Dramatis Personæ\n\n- ALONSO, King of Naples.\n\n@nonumber\n# Act I\n\n@style verse\n  [strong: Ari.] [italic: Full fathom five thy father lies;]\n  [italic: Of his bones are coral made;] and [italic: then]\n  [italic: Those are pearls \\[x\\] that \\| were] his eyes.\n  And \\%%% 3\n"
    )
  ]

aozoraCases :: [(String, Text, Text)]
aozoraCases =
  [ ( "ruby on kanji, after hiragana, and with a bar",
      "蟹工船\13\&\n小林多喜二\13\&\n\13\&\n-------------------------------------------------------\13\&\n【テキスト中に現れる記号について】\13\&\n\13\&\n《》：ルビ\13\&\n-------------------------------------------------------\13\&\n\13\&\nこれは漢字《かんじ》です。\13\&\n｜青い空《あおいそら》と、カタカナ《かたかな》とABC《エービーシー》。\13\&\n《よみ》だけ、「《かぎ》」、ａｂ１《ぜんかく》、\\《x》\13\&\n々《のま》と※印《こめじるし》\13\&\n\13\&\n底本：「蟹工船・党生活者」新潮文庫\13\&\n入力：入力者\13\&\n",
      "これは[ruby: 漢字|かんじ]です。\n[ruby: 青い空|あおいそら]と、[ruby: カタカナ|かたかな]と[ruby: ABC|エービーシー]。\n《よみ》だけ[ruby: 、「|かぎ]」、[ruby: ａｂ１|ぜんかく]、\\\\《x》\n[ruby: 々|のま]と[ruby: ※印|こめじるし]\n\n@nonumber\n# 底本と作成者\n\n底本：「蟹工船・党生活者」新潮文庫\n入力：入力者\n"
    ),
    ( "emphasis dots and tate-chu-yoko",
      "蟹工船\13\&\n小林多喜二\13\&\n\13\&\n-------------------------------------------------------\13\&\n【テキスト中に現れる記号について】\13\&\n\13\&\n《》：ルビ\13\&\n-------------------------------------------------------\13\&\n\13\&\nそれは重要［＃「重要」に傍点］だ。\13\&\n蟹工船《かにこうせん》だ［＃「蟹工船《かにこうせん》だ」に傍点］。\13\&\n１２［＃「１２」は縦中横］日、ない［＃「ある」に傍点］。\13\&\n!?［＃「!?」は縦中横］\13\&\n\13\&\n底本：「蟹工船・党生活者」新潮文庫\13\&\n入力：入力者\13\&\n",
      "それは[kenten: 重要]だ。\n[ruby: 蟹工船|かにこうせん]だ。\n[tcy: １２]日、ない。\n[tcy: !?]\n\n@nonumber\n# 底本と作成者\n\n底本：「蟹工船・党生活者」新潮文庫\n入力：入力者\n"
    ),
    ( "headings of three sizes",
      "蟹工船\13\&\n小林多喜二\13\&\n\13\&\n-------------------------------------------------------\13\&\n【テキスト中に現れる記号について】\13\&\n\13\&\n《》：ルビ\13\&\n-------------------------------------------------------\13\&\n\13\&\n一［＃「一」は大見出し］\13\&\n本文\13\&\n二［＃「二」は中見出し］\13\&\n［＃５字下げ］三［＃「三」は小見出し］\13\&\n次の段落\13\&\n\13\&\n底本：「蟹工船・党生活者」新潮文庫\13\&\n入力：入力者\13\&\n",
      "@nonumber\n# 一\n\n本文\n\n@nonumber\n# 二\n\n@nonumber\n## 三\n\n次の段落\n\n@nonumber\n# 底本と作成者\n\n底本：「蟹工船・党生活者」新潮文庫\n入力：入力者\n"
    ),
    ( "gaiji",
      "蟹工船\13\&\n小林多喜二\13\&\n\13\&\n-------------------------------------------------------\13\&\n【テキスト中に現れる記号について】\13\&\n\13\&\n《》：ルビ\13\&\n-------------------------------------------------------\13\&\n\13\&\n時々※［＃二の字点、1-2-22］、※［＃感嘆符疑問符、1-8-78］※［＃「てへん＋劣」、U+6318、111-3］※［＃「口＋世」、第3水準1-15-3］※［＃「x」、U+12、U+1F600］\13\&\n\13\&\n底本：「蟹工船・党生活者」新潮文庫\13\&\n入力：入力者\13\&\n",
      "時々〻、⁉挘〓😀\n\n@nonumber\n# 底本と作成者\n\n底本：「蟹工船・党生活者」新潮文庫\n入力：入力者\n"
    ),
    ( "layout annotations are dropped, paragraphs on one line each",
      "蟹工船\13\&\n小林多喜二\13\&\n\13\&\n-------------------------------------------------------\13\&\n【テキスト中に現れる記号について】\13\&\n\13\&\n《》：ルビ\13\&\n-------------------------------------------------------\13\&\n\13\&\n［＃３字下げ］一\13\&\n\13\&\n　　ここから本文。\13\&\n［＃ここから２字下げ］\13\&\n［＃地付き］終り\13\&\n-ハイフン、#シャープ、[角括弧]、%%パーセント、|縦線\13\&\n　\13\&\n最後\13\&\n\13\&\n底本：「蟹工船・党生活者」新潮文庫\13\&\n入力：入力者\13\&\n",
      "一\n　　ここから本文。\n終り\n\\-ハイフン、#シャープ、\\[角括弧]、%%パーセント、|縦線\n最後\n\n@nonumber\n# 底本と作成者\n\n底本：「蟹工船・党生活者」新潮文庫\n入力：入力者\n"
    ),
    ( "the colophon section",
      "蟹工船\13\&\n小林多喜二\13\&\n\13\&\n-------------------------------------------------------\13\&\n【テキスト中に現れる記号について】\13\&\n\13\&\n《》：ルビ\13\&\n-------------------------------------------------------\13\&\n\13\&\n本文\13\&\n\13\&\n底本：「蟹工船」新潮文庫\13\&\n　\13\&\n入力：誰か\13\&\n校正：[誰か]\13\&\n",
      "本文\n\n@nonumber\n# 底本と作成者\n\n底本：「蟹工船」新潮文庫\n入力：誰か\n校正：\\[誰か]\n"
    )
  ]
