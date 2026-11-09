-- | The position of characters: superscript and subscript (docs/adr/0269).
module PositionSpec (tests) where

import Data.Text (Text)
import Golem.Project.Position
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "superscript and subscript (docs/adr/0269)"
    [ testCase "position = \"superscript\" is read" $
        case parseStyle (FileId 0) "[character-styles.x]\nposition = \"superscript\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> (charStyle s "x" >>= csPosition) @?= Just PositionSuperscript,
      testCase "every value is read; another is G03006" $ do
        mapM_ (\(v, p) -> either (const Nothing) (\s -> charStyle s "x" >>= csPosition) (parseStyle (FileId 0) ("[character-styles.x]\nposition = \"" <> v <> "\"\n")) @?= Just p) positionValues
        codes (parseStyle (FileId 0) "[character-styles.x]\nposition = \"super\"\n") @?= ["G03006"],
      testCase "the built-in superscript and subscript; a table of the same name keeps position" $ do
        (charStyle defaultStyle "superscript" >>= csPosition) @?= Just PositionSuperscript
        (charStyle defaultStyle "subscript" >>= csPosition) @?= Just PositionSubscript
        case parseStyle (FileId 0) "[character-styles.superscript]\nsize = \"0.5zw\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            (charStyle s "superscript" >>= csPosition) @?= Just PositionSuperscript
            (charStyle s "superscript" >>= csSize) @?= Just (Zw 0.5),
      testCase "@style-def takes position" $
        localStyleDef CharacterKind [("position", LocalWord "subscript")] @?= Right (Left noCharDef {csPosition = Just PositionSubscript}),
      testCase "G03125: the mark style that resolves to superscript" $ do
        codes (parseStyle (FileId 0) "[character-styles.m]\nbased-on = \"superscript\"\n\n[notes]\nmark-style = \"m\"\n") @?= ["G03125"]
        codes (parseStyle (FileId 0) "[notes]\nmark-style = \"superscript\"\n") @?= ["G03125"],
      testCase "G03125: note-mark itself without mark-style" $
        codes (parseStyle (FileId 0) "[character-styles.note-mark]\nposition = \"subscript\"\n") @?= ["G03125"],
      testCase "G03125 is at the value of position, with the message of the ADR" $
        case parseStyle (FileId 0) "[character-styles.m]\nposition = \"superscript\"\n\n[notes]\nmark-style = \"m\"\n" of
          Left [d] -> do
            diagCode d @?= DiagnosticCode "G03125"
            spanStart (diagSpan d) @?= 32
            diagMessage d @?= "注の印の文字スタイル m の position は \"normal\" だけを書けます（印の位置は [notes] で決まります）"
          r -> assertFailure (show r),
      testCase "no G03125 for normal, for body-mark-style, nor without position" $ do
        codes (parseStyle (FileId 0) "[character-styles.m]\nposition = \"normal\"\n\n[notes]\nmark-style = \"m\"\n") @?= []
        codes (parseStyle (FileId 0) "[notes]\nbody-mark-style = \"superscript\"\n") @?= []
        codes (parseStyle (FileId 0) "[notes]\nmark-style = \"bold\"\n") @?= []
    ]

codes :: Either [Diagnostic] a -> [Text]
codes = either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const [])
