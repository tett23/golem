{- | The positions of the errors of the values of style.toml and
manifest.toml, and of the checks after reading style.toml (golem-project
ADR 0008). Each row is a fragment, the code, where the error must start
(the first occurrence of a needle, moved on by a number of bytes) and,
for some rows, the path at the end of the message.
-}
module StylePositionSpec (tests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Project
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Toml qualified
import Toml.Schema (Scope (..))
import Toml.Syntax (Position (..))

-- | A row: its name, the fragment, the code, the needle, the bytes after it, and the path the message ends with.
data Row = Row Text Text Text Text Int (Maybe Text)

-- | The byte offset of the first occurrence of a needle.
offsetOf :: Text -> Text -> Int
offsetOf src needle = BS.length (TE.encodeUtf8 (fst (T.breakOn needle src)))

-- | A page with a grid of 10pt, 40 characters, for the checks that need one.
grid :: Text
grid = "[page]\nsize = \"A5\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 40\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"14mm\", gutter = \"14mm\" }\n"

-- | The test of a row: the one diagnostic of the row's code starts at the needle.
rowTest :: Row -> TestTree
rowTest (Row name src code needle skip path) = testCase (T.unpack name) $
  case parseStyle (FileId 0) src of
    Right _ -> assertFailure "no error"
    Left ds -> case [d | d <- ds, diagCode d == DiagnosticCode code] of
      [] -> assertFailure ("no " <> T.unpack code <> ": " <> show [(diagCode d, diagMessage d) | d <- ds])
      ds' -> do
        let want = offsetOf src needle + skip
        assertBool
          ("expected " <> show want <> ", got " <> show [(spanStart (diagSpan d), diagMessage d) | d <- ds'])
          (any (\d -> spanStart (diagSpan d) == want) ds')
        mapM_ (\p -> assertBool (show (map diagMessage ds')) (any (\d -> ("(" <> p <> ")") `T.isSuffixOf` diagMessage d) ds')) path

-- | The errors Golem makes while reading the values (FromValue).
readingRows :: [Row]
readingRows =
  [ Row "code padding without a unit" "[paragraph-styles.code]\npadding = \"0\"\n" "G0306" "\"0\"" 0 (Just "paragraph-styles.code.padding"),
    Row "character style padding without a unit" "[character-styles.code]\npadding = \"0\"\n" "G0306" "\"0\"" 0 (Just "character-styles.code.padding"),
    Row "first-line-indent without a unit" "[paragraph-styles.body]\nfirst-line-indent = \"1\"\n" "G0306" "\"1\"" 0 (Just "paragraph-styles.body.first-line-indent"),
    Row "line-pitch without a unit" (T.replace "\"16pt\"" "\"20\"" grid) "G0306" "\"20\"" 0 (Just "page.grid.line-pitch"),
    Row "gutter without a unit" (T.replace "gutter = \"14mm\"" "gutter = \"14\"" grid) "G0306" "\"14\"" 0 Nothing,
    Row "columns without column-gap" (grid <> "columns = 2\n") "G0306" "columns = 2" 10 Nothing,
    Row "a bleed in zw" "[page]\nsize = \"A5\"\nbleed = \"1zw\"\n" "G0306" "\"1zw\"" 0 Nothing,
    Row "a page size that is a number" "[page]\nsize = 3\n" "G0317" "3" 0 Nothing,
    Row "a hidden folio pages outside the table" "[hidden-folio]\npages = \"some\"\n" "G0306" "\"some\"" 0 Nothing,
    Row "an aki rule value that is no dimension" "[aki-sets.mine]\nrules = [{ before = \"opening\", after = \"closing\", optimum = \"abc\" }]\n" "G0320" "\"abc\"" 0 Nothing,
    Row "an aki rule with an unknown class" "[aki-sets.mine]\nrules = [{ before = \"nothere\", after = \"closing\", optimum = \"四分\" }]\n" "G0320" "\"nothere\"" 0 Nothing,
    Row "a built-in aki set defined again" "[aki-sets.gyomatsu-yakumono-hankaku]\nbased-on = \"gyomatsu-yakumono-zenkaku\"\n" "G0320" "gyomatsu-yakumono-hankaku]" 0 Nothing,
    Row "a swatch with five numbers" "[color.swatches.red]\ncmyk = [0, 100, 100, 0, 0]\n" "G0306" "[0, 100" 0 Nothing,
    Row "the retired [emphasis]" "[emphasis]\nstrong = \"italic\"\n" "G0306" "emphasis]" 0 Nothing,
    Row "the retired [verse]" "[verse]\nindent = \"1zw\"\n" "G0306" "verse]" 0 Nothing,
    Row "an enumerated value outside the list" "[page]\nsize = \"A5\"\nbinding = \"top\"\n" "G0306" "\"top\"" 0 (Just "page.binding"),
    Row "space-between below 0" "[paragraph-styles.body]\nspace-between = -1\n" "G0306" "-1" 0 Nothing,
    Row "a kerning outside the list" "[character-styles.em]\nkerning = \"some\"\n" "G0321" "\"some\"" 0 (Just "character-styles.em.kerning"),
    Row "a heading of 0 lines" "[headings.1]\nlines = 0\n" "G0306" "0" 0 Nothing,
    Row "a heading level that is not 1 to 3" "[headings.4]\nsize = \"10pt\"\n" "G0306" "4]" 0 Nothing,
    Row "the retired font of [sidenotes]" "[sidenotes]\nwidth = \"20mm\"\ngap = \"3mm\"\nfont = \"x\"\n" "G0306" "\"x\"" 0 Nothing,
    Row "a position that is not a string" "[masters.body]\nfolio = { position = 3, format = \"{n}\" }\n" "G0318" "3" 0 Nothing,
    Row "a running head with even and no odd" "[masters.body]\nrunning-head = { position = \"top-outside\", even = \"title\" }\n" "G0314" "{ position" 0 Nothing,
    Row "a mark size of notes above 1zw" "[notes]\nmark-size = \"2zw\"\n" "G0306" "\"2zw\"" 0 Nothing,
    Row "a mark format of notes without {n}" "[notes]\nmark-format = \"x\"\n" "G0306" "\"x\"" 0 Nothing,
    Row "an unknown kind of [code.colors]" "[code.colors]\nnothere = \"x\"\n" "G0306" "\"x\"" 0 Nothing,
    Row "an empty array of bullets" "[lists]\nbullets = []\n" "G0322" "[]" 0 Nothing,
    Row "a negative gap of lists" "[lists]\ngap = \"-1mm\"\n" "G0322" "\"-1mm\"" 0 Nothing,
    Row "a length that is not a string" "[paragraph-styles.body]\nindent = 1\n" "G0306" "1" 0 Nothing,
    Row "an aki amount in a dimension" "[paragraph-styles.body]\nindent = \"四分\"\n" "G0320" "\"四分\"" 0 Nothing,
    Row "a rule with length and end-indent" "[paragraph-styles.body]\nrule-before = { length = \"10mm\", end-indent = \"1zw\" }\n" "G0306" "\"1zw\"" 0 Nothing
  ]

-- | The checks after reading ('styleChecks').
checkRows :: [Row]
checkRows =
  [ Row "a negative padding of code" "[paragraph-styles.code]\npadding = \"-1mm\"\n" "G0306" "\"-1mm\"" 0 Nothing,
    Row "a hidden folio gutter less than half the size (golem-driver ADR 0041)" "[hidden-folio]\nsize = \"6pt\"\ngutter = \"1pt\"\n" "G0329" "\"1pt\"" 0 Nothing,
    Row "a negative padding of a character style" "[character-styles.code]\npadding = \"-1mm\"\n" "G0306" "\"-1mm\"" 0 Nothing,
    Row "a key code does not take" "[paragraph-styles.code]\nindent = \"1zw\"\n" "G0306" "\"1zw\"" 0 Nothing,
    Row "a background outside code" "[color.swatches.x]\ncmyk = [0, 0, 0, 0]\n[paragraph-styles.body]\nbackground = \"x\"\n" "G0306" "background = \"x\"" 13 Nothing,
    Row "a padding of a character style outside code" "[character-styles.em]\npadding = \"1mm\"\n" "G0306" "\"1mm\"" 0 Nothing,
    Row "a border-width outside code" "[paragraph-styles.body]\nborder-width = \"1mm\"\n" "G0306" "\"1mm\"" 0 Nothing,
    Row "a border-width of code in zw" "[paragraph-styles.code]\nborder-width = \"1zw\"\n" "G0306" "\"1zw\"" 0 Nothing,
    Row "a style name with a capital" "[paragraph-styles.Body]\nindent = \"1zw\"\n" "G0306" "Body]" 0 Nothing,
    Row "a number format of a heading" "[headings.1]\nnumber = \"{x}\"\n" "G0306" "\"{x}\"" 0 Nothing,
    Row "a number of code without a placeholder" "[code]\nnumber = \"x\"\n" "G0306" "\"x\"" 0 Nothing,
    Row "a number format of figures" "[figures]\nnumber = \"{x}\"\n" "G0306" "\"{x}\"" 0 Nothing,
    Row "an explicit hyphen penalty out of range" "[composition]\nexplicit-hyphen-penalty = 10001\n" "G0306" "10001" 0 Nothing,
    Row "a rule of caption" "[paragraph-styles.caption]\nrule-after = { weight = \"1pt\" }\n" "G0306" "{ weight" 0 Nothing,
    Row "a rule of length 0 or less" (grid <> "[paragraph-styles.body]\nrule-before = { start-indent = \"50zw\" }\n") "G0306" "{ start-indent" 0 Nothing,
    Row "a font role not in [fonts] of a heading" "[headings.1]\nfont = \"nothere\"\n" "G0308" "\"nothere\"" 0 Nothing,
    Row "a font role not in [fonts] of a character style" "[character-styles.em]\nfont = \"nothere\"\n" "G0308" "\"nothere\"" 0 Nothing,
    Row "a font role not in [fonts] of a paragraph style" "[paragraph-styles.body]\nfont = \"nothere\"\n" "G0308" "\"nothere\"" 0 Nothing,
    Row "a paragraph style larger than the grid" (grid <> "[paragraph-styles.body]\nsize = \"30Q\"\n") "G0311" "\"30Q\"" 0 Nothing,
    Row "a size inherited by based-on, at the table of the style" (grid <> "[paragraph-styles.big]\nsize = \"30Q\"\n[paragraph-styles.child]\nbased-on = \"big\"\n") "G0311" "child]" 0 Nothing,
    Row "a first line out of the type area" "[paragraph-styles.quote]\nindent = \"0zw\"\nfirst-line-indent = \"-2zw\"\n" "G0312" "\"-2zw\"" 0 Nothing,
    Row "a based-on that does not exist" "[paragraph-styles.note]\nbased-on = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a based-on of a character style that does not exist" "[character-styles.em]\nbased-on = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "the based-on of body" "[paragraph-styles.body]\nbased-on = \"note\"\n" "G0313" "\"note\"" 0 Nothing,
    Row "code as a based-on" "[paragraph-styles.note]\nbased-on = \"code\"\n" "G0313" "\"code\"" 0 Nothing,
    Row "a cycle of based-on" "[paragraph-styles.a]\nbased-on = \"b\"\n[paragraph-styles.b]\nbased-on = \"a\"\n" "G0313" "\"b\"" 0 Nothing,
    Row "a colour that is no swatch" "[character-styles.em]\ncolor = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a border that is no swatch" "[paragraph-styles.code]\nborder = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a colour of the rule of notes" "[notes]\nrule = { length = \"10mm\", color = \"nothere\" }\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a colour of the rule of a heading" "[headings.1]\nrule-before = { color = \"nothere\" }\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a colour of the rule of a paragraph style" "[paragraph-styles.body]\nrule-after = { color = \"nothere\" }\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a colour of [code.colors]" "[code.colors]\nkeyword = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "an aki set that does not exist" "[paragraph-styles.body]\naki-set = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "the based-on of an aki set that does not exist" "[aki-sets.mine]\nbased-on = \"nothere\"\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "a pattern outside the dialect" "[character-styles.em]\nsynthetic-bold = true\n[paragraph-styles.body]\nregex-styles = [{ pattern = \"(?s)a\", style = \"em\" }]\n" "G0315" "\"(?s)a\"" 0 Nothing,
    Row "a character style of a regex style that does not exist" "[paragraph-styles.body]\nregex-styles = [{ pattern = \"a\", style = \"nothere\" }]\n" "G0313" "\"nothere\"" 0 Nothing,
    Row "optical kerning of a character style" "[character-styles.em]\nkerning = \"optical\"\n" "G0321" "\"optical\"" 0 Nothing,
    Row "optical kerning of a paragraph style" "[paragraph-styles.body]\nkerning = \"optical\"\n" "G0321" "\"optical\"" 0 Nothing
  ]

-- | The position a path finds in a TOML text.
positionIn :: Text -> [Scope] -> Maybe (Int, Int)
positionIn src path = case Toml.parse src of
  Right t -> (\(Position _ l c) -> (l, c)) <$> checkPosition t path
  Left _ -> Nothing

tests :: TestTree
tests =
  testGroup
    "positions of the errors of style.toml (golem-project ADR 0008)"
    [ testGroup "reading the values" (map rowTest readingRows),
      testGroup "the checks after reading" (map rowTest checkRows),
      testCase "two styles in a cycle are one G0313 at the based-on of the first" $
        case parseStyle (FileId 0) "[paragraph-styles.a]\nbased-on = \"b\"\n[paragraph-styles.b]\nbased-on = \"a\"\n" of
          Left ds -> length [d | d <- ds, diagCode d == DiagnosticCode "G0313"] @?= 1
          Right _ -> assertFailure "no error",
      testCase "a chapter that is a number is at the number" $ do
        let src = "chapters = [3]\n\n[metadata]\nid = \"urn:uuid:00000000-0000-4000-8000-000000000000\"\ntitle = \"t\"\nlanguage = \"ja\"\ndate = 2026-10-11\n\n[targets.html]\n"
        case parseManifest (FileId 0) src of
          Left [d] -> (diagCode d, spanStart (diagSpan d)) @?= (DiagnosticCode "G0301", offsetOf src "3]")
          other -> assertFailure (show (either (map diagMessage) (const []) other)),
      testCase "checkPosition: the value of the path" $
        positionIn "[a]\nb = 1\n" [ScopeKey "a", ScopeKey "b"] @?= Just (2, 5),
      testCase "checkPosition: the table of the path when the value is not there" $
        positionIn "[a]\nc = 1\n" [ScopeKey "a", ScopeKey "b"] @?= Just (1, 2),
      testCase "checkPosition: an element of an array" $
        positionIn "[a]\nr = [{ p = 1 }, { p = 2 }]\n" [ScopeKey "a", ScopeKey "r", ScopeIndex 1, ScopeKey "p"] @?= Just (2, 23),
      testCase "checkPosition: nothing when neither is there" $
        positionIn "[x]\nc = 1\n" [ScopeKey "a", ScopeKey "b"] @?= Nothing,
      testCase "the position of [index] columns is still known (G0744)" $
        case parseStyle (FileId 0) "[index]\ncolumns = 2\ncolumn-gap = \"1zw\"\n" of
          Right s -> fmap ixColumnsAt (stIndex s) @?= Just (offsetOf "[index]\ncolumns = 2\n" "2")
          Left ds -> assertFailure (show (map diagMessage ds)),
      testCase "a style with no error keeps no path" $
        fmap (Map.member "body" . stParaStyles) (parseStyle (FileId 0) "[paragraph-styles.body]\nindent = \"1zw\"\n") @?= Right True
    ]
