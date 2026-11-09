-- | The underline and the strikethrough of character styles (docs/adr/0270).
module UnderlineSpec (tests) where

import Data.Text (Text)
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

underlineOf :: Text -> Maybe (Maybe DecorationSpec)
underlineOf src = either (const Nothing) (\s -> charStyle s "x" >>= csUnderline) (parseStyle (FileId 0) ("[color.swatches]\nred = { cmyk = [0, 100, 100, 0] }\n\n[character-styles.x]\n" <> src))

codes :: Text -> [Text]
codes src = either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const []) (parseStyle (FileId 0) ("[character-styles.x]\n" <> src))

tests :: TestTree
tests =
  testGroup
    "underline and strikethrough (docs/adr/0270)"
    [ testCase "true is the default line, the same as {}" $ do
        underlineOf "underline = true\n" @?= Just (Just defaultDecoration)
        underlineOf "underline = {}\n" @?= Just (Just defaultDecoration)
        defaultDecoration @?= DecorationSpec (Zw 0.05) (Abs 0) ("solid", Nothing) Nothing Nothing Nothing,
      testCase "false is the inner Nothing" $
        underlineOf "underline = false\n" @?= Just Nothing,
      testCase "weight in zw and dashed: the dash from the weight" $
        case underlineOf "underline = { weight = \"0.08zw\", style = \"dashed\" }\n" of
          Just (Just d) -> do
            dsWeight d @?= Zw 0.08
            decorationStyle 655360 d @?= (52429, RuleDashed (3 * 52429) (2 * 52429))
          other -> assertFailure (show other),
      testCase "offset, color and strikethrough are read" $
        either (const Nothing) (\s -> charStyle s "x" >>= csStrikethrough) (parseStyle (FileId 0) "[color.swatches]\nred = { cmyk = [0, 100, 100, 0] }\n\n[character-styles.x]\nstrikethrough = { weight = \"0.5pt\", color = \"red\", offset = \"-0.05zw\" }\n")
          @?= Just (Just (DecorationSpec (Abs 32768) (Zw (-0.05)) ("solid", Nothing) Nothing Nothing (Just "red"))),
      testCase "the keys of the length and the place of a rule, true-likes and an offset that does not read are G03006" $ do
        mapM_
          (\src -> codes src @?= ["G03006"])
          [ "underline = { length = \"1zw\" }\n",
            "underline = { space-before = \"1pt\" }\n",
            "underline = { keep-in-column = true }\n",
            "underline = { start-indent = \"1zw\" }\n",
            "underline = \"yes\"\n",
            "underline = 1\n",
            "underline = { offset = \"abc\" }\n",
            "strikethrough = { weight = \"0pt\" }\n",
            "underline = { style = \"solid\", dash = \"1pt\" }\n"
          ],
      testCase "a color that is not a swatch is G03013" $
        codes "underline = { color = \"nowhere\" }\n" @?= ["G03013"],
      testCase "@style-def takes true and false, not a table" $ do
        localStyleDef CharacterKind [("underline", LocalWord "true")] @?= Right (Left noCharDef {csUnderline = Just (Just defaultDecoration)})
        localStyleDef CharacterKind [("strikethrough", LocalWord "false")] @?= Right (Left noCharDef {csStrikethrough = Just Nothing})
        either (map fst) (const []) (localStyleDef CharacterKind [("underline", LocalString "{}")]) @?= ["G03006"],
      testCase "the child's value replaces the parent's" $
        either (const Nothing) (\s -> charStyle s "y" >>= csUnderline) (parseStyle (FileId 0) "[character-styles.x]\nunderline = { weight = \"1pt\" }\n\n[character-styles.y]\nbased-on = \"x\"\nunderline = { style = \"wavy\" }\n")
          @?= Just (Just defaultDecoration {dsStyle = ("wavy", Nothing)}),
      testCase "the rules of paragraphs still refuse zw in the weight" $
        either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const []) (parseStyle (FileId 0) "[paragraph-styles.x]\nrule-before = { weight = \"0.1zw\" }\n") @?= ["G03006"]
    ]
