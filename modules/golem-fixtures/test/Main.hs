module Main (main) where

import Data.ByteString qualified as BS
import Data.Either (isLeft)
import Data.Text (Text)
import Data.Text qualified as T
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
        assertBool "not UTF-8" (isLeft (convertBytes Aozora (BS.pack [0x82, 0xa0]))),
      testGroup "gutenberg-text (docs/adr/0026)" (map textCaseOf textCases),
      testGroup "aozora-prose (docs/adr/0026)" (map (caseOf AozoraProse) aozoraProseCases),
      testGroup "aozora-verse (docs/adr/0026)" (map (caseOf AozoraVerse) aozoraVerseCases),
      testCase "the arguments of the converters (docs/adr/0026)" $ do
        converterNamed "aozora-prose" @?= Just AozoraProse
        converterNamed "aozora-verse" @?= Just AozoraVerse
        converterNamed "gutenberg-text" @?= Just (GutenbergText defaultTextOptions)
        parseArgs ["aozora", "in.txt", "out.gm"] @?= Right (Aozora, "in.txt", "out.gm")
        parseArgs ["gutenberg-text", "--verse", "--heading", "Fit the", "--heading", "CHAPTER", "--caps-heading", "2", "--start", "PREFACE", "--end", "THE END", "--notes", "NOTES", "--speakers", "--two-columns", "--numbered-headings", "--bold-equals", "in.txt", "out.gm"]
          @?= Right
            ( GutenbergText
                defaultTextOptions
                  { optVerse = True,
                    optHeadings = ["Fit the", "CHAPTER"],
                    optCapsHeading = Just 2,
                    optStart = Just "PREFACE",
                    optEnd = Just "THE END",
                    optNotes = Just "NOTES",
                    optSpeakers = True,
                    optTwoColumns = True,
                    optNumberedHeadings = True,
                    optBoldEquals = True
                  },
              "in.txt",
              "out.gm"
            )
        assertBool "an unknown option" (isLeft (parseArgs ["gutenberg-text", "--frob", "in.txt", "out.gm"]))
        assertBool "an option without its value" (isLeft (parseArgs ["gutenberg-text", "in.txt", "out.gm", "--heading"]))
        assertBool "a level that is not a number" (isLeft (parseArgs ["gutenberg-text", "--caps-heading", "x", "in.txt", "out.gm"]))
        assertBool "options of a converter without options" (isLeft (parseArgs ["aozora", "--verse", "in.txt", "out.gm"]))
        assertBool "no output" (isLeft (parseArgs ["gutenberg-text", "in.txt"]))
        assertBool "a start line that is not there" (isLeft (convertBytes (GutenbergText defaultTextOptions {optStart = Just "NOWHERE"}) (encodeUtf8 (gutenberg "Text.\n"))))
        assertBool "a notes line that is not there" (isLeft (convertBytes (GutenbergText defaultTextOptions {optNotes = Just "NOWHERE"}) (encodeUtf8 (gutenberg "Text.\n"))))
    ]

textCaseOf :: (String, TextOptions, Text, Text) -> TestTree
textCaseOf (name, opts, body, expected) =
  testCase name (convertBytes (GutenbergText opts) (encodeUtf8 (gutenberg body)) @?= Right (encodeUtf8 expected))

-- | A Project Gutenberg text with the body between its markers.
gutenberg :: Text -> Text
gutenberg body =
  "\65279\&The Project Gutenberg eBook of X\r\n\r\n*** START OF THE PROJECT GUTENBERG EBOOK X ***\r\n"
    <> T.replace "\n" "\r\n" body
    <> "*** END OF THE PROJECT GUTENBERG EBOOK X ***\r\nLicence\r\n"

-- The expected outputs of gutenberg-text, aozora-prose and aozora-verse were
-- written by hand from the rules of docs/adr/0026.
textCases :: [(String, TextOptions, Text, Text)]
textCases =
  [ ( "headings, speakers and paragraphs",
      defaultTextOptions {optStart = Just "CHAPTER I", optHeadings = ["CHAPTER"], optCapsHeading = Just 2, optSpeakers = True},
      "Title page\n          \nCHAPTER I\n\nTHE LANDING\n\nSome prose that is\nwrapped over lines -- with a dash.\n\nDIO. What from?\n\nFR. and DIO. Brekekekex, ko-ax.\n\nXAN.\n\nO thrice unlucky\n",
      "@nonumber\n# CHAPTER I\n\n@nonumber\n## THE LANDING\n\nSome prose that is wrapped over lines — with a dash.\n\n[strong: DIO.] What from?\n\n[strong: FR. and DIO.] Brekekekex, ko-ax.\n\n[strong: XAN.]\n\nO thrice unlucky\n"
    ),
    ( "verse of short or indented lines, its indents and wrapped lines",
      defaultTextOptions {optVerse = True, optSpeakers = True},
      "Girt with a boyish garb for boyish task,\n    Eager she wields her _spade: yet\nloves_ as well\n\n     \8220Just the place for a Snark!\8221 the Bellman cried,\n          As he landed his crew with care;\n\n  DIO. Hang you, and your ko-axing too! There's nothing but ko-ax with\n  you.\n  O tuneful race\n\n          \8220Then the bowsprit got mixed.\8221\n",
      "@style verse\n  Girt with a boyish garb for boyish task,\n  [aki 2zw]Eager she wields her [italic: spade: yet]\n  [italic: loves] as well\n\n@style verse\n  \8220Just the place for a Snark!\8221 the Bellman cried,\n  [aki 2.5zw]As he landed his crew with care;\n\n@style verse\n  [strong: DIO.] Hang you, and your ko-axing too! There's nothing but ko-ax with you.\n  O tuneful race\n\n@style quote\n\8220Then the bowsprit got mixed.\8221\n"
    ),
    ( "verse guessed in prose, quotes, escapes and the end",
      defaultTextOptions {optEnd = Just "STOP"},
      "  There's a dark lantern of the spirit,\n  Which none see by but those who bear it,\n  BUTLER.\n\n  Nether Stowey, where Coleridge wrote _The Rime of the Ancient Long\n  Mariner_, is a few miles from Bridgewater.\n\n[Illustration: A boat]\n\n# not a heading, 50%% and back\\slash [x]\n\n  STOP  \n\nDropped.\n",
      "@style verse\n  There's a dark lantern of the spirit,\n  Which none see by but those who bear it,\n  BUTLER.\n\n@style quote\nNether Stowey, where Coleridge wrote [italic: The Rime of the Ancient Long Mariner], is a few miles from Bridgewater.\n\n\\[Illustration: A boat]\n\n\\# not a heading, 50\\%% and back\\\\slash \\[x]\n"
    ),
    ( "two columns, numbered headings and bold",
      defaultTextOptions {optTwoColumns = True, optNumberedHeadings = True, optBoldEquals = True, optCapsHeading = Just 1},
      "II. ELEMENTARY RULES\n\n13. Omit needless words.\n\n    1. Indented rule    7\n\n=Participle for verbal noun.= See _here_.\n\n  Do you mind me asking\n  a question?\n\n    Do you mind my asking a | question?\n\n  the question as to whether\n\n    whether (the question whether)\n\nText after.\n",
      "@nonumber\n# II. ELEMENTARY RULES\n\n@nonumber\n## 13. Omit needless words.\n\n@style quote\n1. Indented rule 7\n\n[bold: Participle for verbal noun.] See [italic: here].\n\n| | |\n|---|---|\n| Do you mind me asking a question? | Do you mind my asking a \\| question? |\n| the question as to whether | whether (the question whether) |\n\nText after.\n"
    ),
    ( "notes moved to their marks",
      defaultTextOptions {optNotes = Just "NOTES"},
      "Mr Flosky,[1] a gentleman _of note_.[2] And [3] stays.\n\nTHE END\n\nNOTES\n\nCHAPTER I\n\n[1] _Mr Flosky_: A corruption [Greek: philoschios],\na lover.\n\n[2] Two | bars.\n",
      "Mr Flosky,[note: [italic: Mr Flosky]: A corruption \\[Greek: philoschios\\], a lover.] a gentleman [italic: of note].[note: Two \\| bars.] And \\[3] stays.\n\nTHE END\n"
    )
  ]

-- | An Aozora Bunko text with its notation section and a colophon.
aozora :: Text -> Text
aozora body =
  T.replace "\n" "\r\n" $
    "題\n作者\n\n-------------------------------------------------------\n【テキスト中に現れる記号について】\n-------------------------------------------------------\n\n"
      <> body
      <> "\n底本：「本」\n"

aozoraProseCases :: [(String, Text, Text)]
aozoraProseCases =
  [ ( "indents, emphasis, kunten, breaks and dropped annotations",
      aozora "［＃５字下げ］一［＃「一」は中見出し］\n［＃ここから５字下げ］\nホテルの帳場。\n［＃ここで字下げ終わり］\n［＃ここから改行天付き、折り返して１字下げ］\nさと　　船はもう［＃「もう」に白丸傍点］著いた。\n［＃ここで字下げ終わり］\n［＃改行天付き、折り返して２字下げ］とみ　　ひゆう［＃「ひゆう」に傍点］。\n［＃３字下げ］三字［＃「三字」は太字］下げの行\n［＃ここから２字下げ、折り返して３字下げ］\n奉［＃レ］答［＃二］高季迪［＃一］と、｜奉［＃レ］答《こたえ》、一［＃（ト）］。\n［＃ここで字下げ終わり］\nたま／＼、／″＼、※［＃始め二重括弧、1-2-54］一※［＃終わり二重括弧、1-2-55］\n傍線［＃「傍線」に傍線］と［＃地付き］地付き、＊［＃「＊」は行右小書き］\n［＃改ページ］\n［＃ここから中見出し］\n春と修羅\n　　（mental sketch）\n［＃ここで中見出し終わり］\nパート五［＃「パート五」は同行小見出し］の行\n［＃改丁］\n最後\n",
      "@nonumber\n# 一\n\n@style indent-5-5\nホテルの帳場。\n@style indent-0-1\nさと　　船は[kenten shape=open-circle: もう]著いた。\n@style indent-0-2\nとみ　　[kenten: ひゆう]。\n@style indent-3-3\n[bold: 三字]下げの行\n@style indent-2-3\n奉[style kunten: レ]答[style kunten: 二]高季迪[style kunten: 一]と、[ruby: 奉[style kunten: レ]答|こたえ]、一[style kunten: ト]。\nたま〳〵、〴〵、⦅一⦆\n傍線と地付き、＊\n@page-break\n\n@nonumber\n# 春と修羅　（mental sketch）\n\n[bold: パート五]の行\n@page-break recto\n最後\n\n@nonumber\n# 底本と作成者\n\n底本：「本」\n"
    ),
    ( "the shapes of kenten",
      aozora "あ［＃「あ」に白ゴマ傍点］い［＃「い」に丸傍点］う［＃「う」に黒三角傍点］え［＃「え」に白三角傍点］お［＃「お」に二重丸傍点］か［＃「か」に蛇の目傍点］き［＃「き」に×傍点］く［＃「く」は斜体］\n",
      "[kenten shape=open-sesame: あ][kenten shape=circle: い][kenten shape=triangle: う][kenten shape=open-triangle: え][kenten shape=open-double-circle: お][kenten shape=double-circle: か]き[italic: く]\n\n@nonumber\n# 底本と作成者\n\n底本：「本」\n"
    )
  ]

aozoraVerseCases :: [(String, Text, Text)]
aozoraVerseCases =
  [ ( "stanzas, indents of full-width spaces, headings and breaks",
      aozora "［＃ページの左右中央］\n　　心象スケツチ［＃「心象スケツチ」は１段階小さな文字］\n　　春と修羅\n［＃改丁］\n\n［＃２字下げ］序［＃「序」は大見出し］\n\nわたくしといふ現象は\n［＃２字下げ］仮定された\n［＃ここから３字下げ］\n有機交流電燈の\nひとつの\n［＃ここで字下げ終わり］\n\n東海《とうかい》の小島\n［＃地付き］（一九二二、一、六）\n#行頭\n",
      "@style verse\n  　　心象スケツチ\n  　　春と修羅\n\n@page-break recto\n\n@nonumber\n# 序\n\n@style verse\n  わたくしといふ現象は\n  　　仮定された\n  　　　有機交流電燈の\n  　　　ひとつの\n\n@style verse\n  [ruby: 東海|とうかい]の小島\n  （一九二二、一、六）\n  \\#行頭\n\n@nonumber\n# 底本と作成者\n\n底本：「本」\n"
    )
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
