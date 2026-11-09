{- | Completion in style.toml and preflight.toml, and TOML files that are
not read as sources (docs/adr ADR 0169). The candidates are written as
strings, not built from the schemas.
-}
module TomlSpec (tomlTests) where

import Data.ByteString qualified as BS
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.Text.IO qualified as TIO
import Golem.Lsp.Features
import Golem.Lsp.Toml
import Golem.Lsp.Workspace
import Support (codesOf)
import System.FilePath ((</>))
import Test.Tasty hiding (after)
import Test.Tasty.HUnit

root :: FilePath
root = "test/fixtures/proj"

-- | A text with the cursor at ▮: the text without it, and the byte offset of the cursor.
cursor :: Text -> (Text, Int)
cursor t =
  let (before, after) = T.breakOn "▮" t
   in (before <> T.drop 1 after, BS.length (TE.encodeUtf8 before))

labelsIn :: FilePath -> Text -> [Text]
labelsIn path t = let (src, off) = cursor t in map cmpLabel (tomlFileCompletions path src off)

contextOf :: Text -> Context
contextOf t = let (src, off) = cursor t in contextAt src off

-- | The candidates of a row are exactly these.
exactly :: FilePath -> Text -> [Text] -> TestTree
exactly path t want = testCase (show t) (labelsIn path t @?= want)

-- | The candidates of a row include some and exclude others.
including :: FilePath -> Text -> [Text] -> [Text] -> TestTree
including path t yes no = testCase (show t) $ do
  let got = labelsIn path t
  mapM_ (\x -> assertBool ("missing " <> T.unpack x <> " in " <> show got) (x `elem` got)) yes
  mapM_ (\x -> assertBool ("unexpected " <> T.unpack x <> " in " <> show got) (x `notElem` got)) no

-- | The codes of the diagnostics of a file.
tomlTests :: TestTree
tomlTests =
  testGroup
    "style.toml and preflight.toml (docs/adr ADR 0169)"
    [ testGroup
        "the context of the cursor"
        [ testCase "a header" $ contextOf "[paragraph-styles.bo▮" @?= AtHeader ["paragraph-styles"] "bo",
          testCase "a key under a header, with the keys written" $ contextOf "[page]\nsize = \"B6\"\nbi▮" @?= AtKey ["page"] ["size"] "bi",
          testCase "a key of an inline table" $ contextOf "[page]\ngrid = { font-size = \"10pt\", ch▮" @?= AtKey ["page", "grid"] ["font-size"] "ch",
          testCase "a value outside a string" $ contextOf "[page]\nbinding = ri▮" @?= AtValue ["page", "binding"] False Bare "ri",
          testCase "a value in a basic string" $ contextOf "[page]\nbinding = \"ri▮" @?= AtValue ["page", "binding"] False Basic "ri",
          testCase "a value in a literal string" $ contextOf "[page]\nbinding = 'ri▮" @?= AtValue ["page", "binding"] False Literal "ri",
          testCase "an element of an array" $ contextOf "[font-formats]\nallowed = [\"cff\", ▮" @?= AtValue ["font-formats", "allowed"] True Bare "",
          testCase "a dotted key" $ contextOf "[page]\ngrid.lines = 3\ngrid.▮" @?= AtKey ["page", "grid"] [] "",
          testCase "after a value" $ contextOf "[page]\nbinding = \"right\" ▮" @?= Nowhere,
          testCase "in a comment" $ contextOf "[page]\n# binding = ▮" @?= Nowhere,
          testCase "in a multi-line string" $ contextOf "[page]\nbinding = '''\n▮" @?= Nowhere,
          testCase "a string with an escaped quote is closed where it ends" $ contextOf "[page]\nsize = \"a\\\"b\"\nbinding = ▮" @?= AtValue ["page", "binding"] False Bare "",
          testCase "a quoted key of a header is one step" $ contextOf "[fonts.\"a.b\"]\n▮" @?= AtKey ["fonts", "a.b"] [] "",
          testCase "the defined paths" $
            definedPaths "[page]\nsize = \"B6\"\ngrid = { lines = 3 }\n[fonts.heading]\nja = \"a.otf\"\n"
              @?= [["page"], ["page", "size"], ["page", "grid"], ["page", "grid", "lines"], ["fonts"], ["fonts", "heading"], ["fonts", "heading", "ja"]]
        ],
      testGroup
        "style.toml"
        [ including "style.toml" "[▮" ["page", "fonts", "character-styles", "paragraph-styles", "color"] ["emphasis", "verse"],
          exactly "style.toml" "[paragraph-styles.quote]\n[paragraph-styles.▮" ["body", "caption", "code", "sidenote", "verse", "quote"],
          including "style.toml" "[page]\nbinding = \"right\"\n▮" ["size", "writing-mode", "grid", "bleed"] ["binding"],
          exactly "style.toml" "[page]\nbinding = ▮" ["\"right\"", "\"left\""],
          exactly "style.toml" "[page]\nbinding = \"▮" ["right", "left"],
          exactly "style.toml" "[character-styles.em]\nsynthetic-bold = ▮" ["true", "false"],
          exactly "style.toml" "[paragraph-styles.quote]\nbased-on = ▮" ["\"body\"", "\"caption\"", "\"sidenote\"", "\"verse\""],
          exactly "style.toml" "[fonts.heading]\nja = \"a.otf\"\n[character-styles.em]\nfont = ▮" ["\"heading\""],
          exactly "style.toml" "[color.swatches]\naccent = { cmyk = [0, 80, 100, 0] }\n[character-styles.em]\ncolor = ▮" ["\"accent\""],
          exactly "style.toml" "[character-styles.em]\n[paragraph-styles.body]\nregex-styles = [\n  { pattern = 'x', style = ▮" ["\"bold\"", "\"code\"", "\"italic\"", "\"no-break\"", "\"note-mark\"", "\"strong\"", "\"subscript\"", "\"superscript\"", "\"url\"", "\"em\""],
          exactly "style.toml" "[page]\n# binding = ▮" [],
          exactly "style.toml" "[page]\nbinding = \"\"\"\n▮" [],
          exactly "style.toml" "[page]\nsize = \n[page.grid]\n▮" ["font-size", "characters", "lines", "line-pitch", "columns", "column-gap", "position"],
          exactly "style.toml" "# 日本語のコメント😀\n[page]\nbinding = ▮" ["\"right\"", "\"left\""],
          exactly "style.toml" "[page]\nsize = { width = \"100mm\", ▮" ["height"],
          exactly "style.toml" "[headings.1]\nrunning-head = ▮" [],
          including "style.toml" "[headings.1]\n▮" ["font", "page-break", "rule-before"] ["running-head"],
          exactly "style.toml" "[paragraph-styles.body]\nrule-before = ▮" ["false"],
          -- docs/adr/0189
          exactly "style.toml" "[paragraph-styles.quote]\nalign = ▮" ["\"left\"", "\"center\"", "\"right\"", "\"left-justified\"", "\"center-justified\"", "\"right-justified\"", "\"fully-justified\"", "\"towards-spine\"", "\"away-from-spine\""],
          including "style.toml" "[paragraph-styles.quote]\n▮" ["align", "space-before", "space-after", "end-indent"] [],
          exactly "style.toml" "[character-styles.em]\nbackground = ▮" ["false"],
          exactly "style.toml" "[color.swatches.a]\ncmyk = [0, 0, 0, 0]\n[character-styles.em]\nbackground = ▮" ["\"a\"", "false"],
          exactly "style.toml" "[aki-sets.mine]\nrules = [{ before = [▮" ["\"opening\"", "\"closing\"", "\"hyphen\"", "\"dividing\"", "\"middle-dot\"", "\"full-stop\"", "\"comma\"", "\"inseparable\"", "\"iteration\"", "\"prolonged-sound\"", "\"small-kana\"", "\"ideographic-space\"", "\"kana\"", "\"ideograph\"", "\"western\"", "\"japanese\"", "\"line-start\"", "\"paragraph-start\""],
          exactly "style.toml" "[aki-sets.mine]\nbased-on = ▮" ["\"gyomatsu-yakumono-hankaku\"", "\"gyomatsu-yakumono-zenkaku\""],
          exactly "style.toml" "[page]\nbleed = ▮" [],
          testCase "the kinds of the candidates" $ do
            let kinds t = let (src, off) = cursor t in map cmpKind (tomlFileCompletions "style.toml" src off)
            take 1 (kinds "[▮") @?= [CkTable]
            take 1 (kinds "[page]\n▮") @?= [CkSettingKey]
            kinds "[page]\nbinding = ▮" @?= [CkSettingValue, CkSettingValue]
            kinds "[color.swatches.a]\ncmyk = [0, 0, 0, 0]\n[character-styles.em]\ncolor = ▮" @?= [CkSwatch]
            take 1 (kinds "[character-styles.em]\nbased-on = ▮") @?= [CkCharStyle]
            take 1 (kinds "[paragraph-styles.em]\nbased-on = ▮") @?= [CkParaStyle]
        ],
      testGroup
        "preflight.toml"
        [ exactly "preflight.toml" "based-on = ▮" ["\"basic\"", "\"print\"", "\"none\""],
          exactly "preflight.toml" "[type-size]\nseverity = ▮" ["\"error\"", "\"warning\"", "\"off\""],
          exactly "preflight.toml" "[font-formats]\nallowed = [▮" ["\"cff\"", "\"cff2\"", "\"truetype\""],
          exactly "preflight.toml" "[font-formats]\nallowed = ▮" [],
          including "preflight.toml" "[▮" ["glyph-missing", "bleed-size", "stroke-weight"] ["image-unplaceable", "based-on", "name"],
          exactly "preflight.toml" "[image-resolution]\ncolor = { ▮" ["error-below", "warning-below"]
        ],
      testGroup
        "the workspace"
        [ testCase "style.toml in the editor is not read as a source" $ do
            ws0 <- openWorkspace root
            ws <- updateFile ws0 "style.toml" "[page]\nsize = \"B6\"\n"
            assertBool "no source" (isNothing (sourceOf ws "style.toml"))
            -- read as a source, [page] was G02022, an unknown command
            codesOf ws "style.toml" @?= [],
          testCase "manifest.toml in the editor is not read as a source" $ do
            ws0 <- openWorkspace root
            text <- TIO.readFile (root </> "manifest.toml")
            ws <- updateFile ws0 "manifest.toml" text
            assertBool "no source" (isNothing (sourceOf ws "manifest.toml"))
            codesOf ws "manifest.toml" @?= [],
          testCase "completion in the edited style.toml of the root" $ do
            ws0 <- openWorkspace root
            ws <- updateFile ws0 "style.toml" "[page]\nbinding = "
            map cmpLabel (completions ws "style.toml" (BS.length (TE.encodeUtf8 "[page]\nbinding = "))) @?= ["\"right\"", "\"left\""],
          testCase "no completion in a style.toml below the root, nor in manifest.toml" $ do
            ws0 <- openWorkspace root
            ws1 <- updateFile ws0 "sub/style.toml" "["
            ws <- updateFile ws1 "manifest.toml" "["
            completions ws "sub/style.toml" 1 @?= []
            completions ws "manifest.toml" 1 @?= []
        ]
    ]
