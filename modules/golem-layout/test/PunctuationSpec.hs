{- | Punctuation at the line edges and the class names of aki rules:
the protrusion table of Latin punctuation (golem-layout ADR 0005),
hanging Japanese punctuation (golem-layout ADR 0002), and the names
style.toml's aki rules may use (docs/adr ADR 0019).
-}
module PunctuationSpec (punctuationTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Aki (AkiPos (..), akiPositions)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Project.Style (akiClassNames)
import Test.Tasty
import Test.Tasty.HUnit

punctuationTests :: TestTree
punctuationTests =
  testGroup
    "punctuation at the line edges and aki class names"
    [ testGroup "the protrusion table: (start, end) in permille (golem-layout ADR 0005)" protrusionTableTests,
      testGroup "hanging punctuation (golem-layout ADR 0002)" hangingTests,
      testGroup "the class names of aki rules (docs/adr ADR 0019)" akiNameTests
    ]

protrusionTableTests :: [TestTree]
protrusionTableTests =
  [ testCase (name <> " (" <> [c] <> ")") (protrusionRatio c @?= expected)
  | (name, c, expected) <-
      [ ("hyphen-minus", '-', (0, 700)),
        ("hyphen", '‐', (0, 700)),
        ("en dash", '–', (0, 500)),
        ("em dash", '—', (0, 200)),
        ("comma", ',', (0, 700)),
        ("full stop", '.', (0, 700)),
        ("semicolon", ';', (0, 500)),
        ("colon", ':', (0, 500)),
        ("exclamation mark", '!', (0, 200)),
        ("question mark", '?', (0, 200)),
        ("left double quotation mark", '“', (700, 0)),
        ("left single quotation mark", '‘', (700, 0)),
        ("right double quotation mark", '”', (0, 700)),
        ("right single quotation mark", '’', (0, 700)),
        ("quotation mark", '"', (500, 500)),
        ("apostrophe", '\'', (500, 500)),
        ("a letter does not protrude", 'a', (0, 0)),
        ("a digit does not protrude", '1', (0, 0)),
        ("a Japanese full stop does not protrude", '。', (0, 0)),
        ("a Japanese comma does not protrude", '、', (0, 0))
      ]
  ]

-- | The end protrusion of the box of the character after あ.
hangOf :: Bool -> Char -> [Sp]
hangOf hanging c =
  let env = (defaultComposeEnv fs) {ceHanging = hanging}
      items = fst (composeInlines env [IR.Text sp (T.pack ['あ', c])])
   in [bcProtrudeEnd bc | Box _ bc <- items, bcText bc == T.singleton c]

hangingTests :: [TestTree]
hangingTests =
  [ testCase (name <> " (" <> [c] <> ")") (hangOf True c @?= expected)
  | (name, c, expected) <-
      -- a full stop or comma is a half em wide (its half em of space is glue): 5pt = 327680sp
      [ ("an ideographic full stop hangs its width", '。', [327680]),
        ("an ideographic comma hangs its width", '、', [327680]),
        ("a fullwidth full stop hangs its width", '．', [327680]),
        ("a fullwidth comma hangs its width", '，', [327680]),
        ("a closing bracket does not hang", '」', [0]),
        ("a middle dot does not hang", '・', [0]),
        ("an exclamation mark does not hang", '！', [0]),
        ("the long vowel mark does not hang", 'ー', [0])
      ]
  ]
    <> [testCase "without hanging-punctuation a full stop does not hang" (hangOf False '。' @?= [0])]

akiNameTests :: [TestTree]
akiNameTests =
  [ testCase (T.unpack name) (akiPositions name @?= expected)
  | (name, expected) <-
      [ ("opening", [AkiChar Opening]),
        ("closing", [AkiChar Closing]),
        ("hyphen", [AkiChar Hyphen]),
        ("dividing", [AkiChar Dividing]),
        ("middle-dot", [AkiChar MiddleDot]),
        ("full-stop", [AkiChar FullStop]),
        ("comma", [AkiChar Comma]),
        ("inseparable", [AkiChar Inseparable]),
        ("iteration", [AkiChar Iteration]),
        ("prolonged-sound", [AkiChar ProlongedSound]),
        ("small-kana", [AkiChar SmallKana]),
        ("ideographic-space", [AkiChar IdeographicSpace]),
        ("kana", [AkiChar Kana]),
        ("ideograph", [AkiChar Ideograph]),
        ("western", [AkiChar Western]),
        ("line-start", [AkiLineStart]),
        ("paragraph-start", [AkiParagraphStart]),
        ("line-end", [AkiLineEnd])
      ]
  ]
    <> [ testCase "japanese is every class but western" $
           akiPositions "japanese"
             @?= map
               AkiChar
               [ Opening,
                 Closing,
                 Hyphen,
                 Dividing,
                 MiddleDot,
                 FullStop,
                 Comma,
                 Inseparable,
                 Iteration,
                 ProlongedSound,
                 SmallKana,
                 IdeographicSpace,
                 Kana,
                 Ideograph
               ],
         testCase "an unknown name, or a name in another case, stands for nothing" $
           map akiPositions ["latin", "Opening", ""] @?= [[], [], []],
         testCase "every class name style.toml accepts stands for some class" $
           [name | name <- akiClassNames, null (akiPositions name)] @?= ([] :: [Text])
       ]
