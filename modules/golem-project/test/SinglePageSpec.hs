-- | Mode validation before page contents are considered (root ADR 0400).
module SinglePageSpec (tests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Style
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

page :: Text -> Text -> Text
page extra position = "[page]\nsize = \"A4\"\n" <> extra <> "[page.grid]\nfont-size = \"10pt\"\ncharacters = 30\nlines = 30\nline-pitch = \"16pt\"\nposition = { top = \"20mm\", " <> position <> " }\n"

single :: Text
single = page "layout = \"single\"\n" "left = \"25mm\""

errors :: Text -> [(DiagnosticCode, Int)]
errors src = either (map (\d -> (diagCode d, spanStart (diagSpan d)))) (const []) (parseStyle (FileId 0) src)

valid :: Text -> Assertion
valid src = case parseStyle (FileId 0) src of
  Right _ -> pure ()
  Left ds -> assertFailure (show ds)

at :: Text -> Text -> Text -> Assertion
at src code needle = errors src @?= [(DiagnosticCode code, offsetOf src needle)]

tests :: TestTree
tests =
  testGroup
    "root ADR 0400"
    [ testCase "I1: omitted and explicit facing modes agree" $
        parseStyle (FileId 0) (page "" "gutter = \"25mm\"") @?= parseStyle (FileId 0) (page "layout = \"facing\"\n" "gutter = \"25mm\""),
      testCase "I4: left and right anchors are accepted independently" $
        forM_ ["left", "right"] $
          \side -> valid (page "layout = \"single\"\n" (side <> " = \"25mm\"")),
      testCase "I4: a grid is optional for outputs without page geometry" $
        valid "[page]\nsize = \"A4\"\nlayout = \"single\"\n",
      testCase "I4: an unknown layout is rejected at its value" $ do
        let src = "[page]\nsize = \"A4\"\nlayout = \"singles\"\n"
        at src "G03006" "\"singles\"",
      testCase "I4: binding is forbidden even without a grid" $ do
        let src = "[page]\nsize = \"A4\"\nlayout = \"single\"\nbinding = \"right\"\n"
        at src "G03006" "\"right\"",
      testCase "I4: both and missing physical anchors point to the position table" $
        forM_ ["left = \"25mm\", right = \"20mm\"", ""] $ \pos -> do
          let src = page "layout = \"single\"\n" pos
          at src "G03006" "{ top",
      testCase "I4: a gutter is forbidden in single mode" $ do
        let src = page "layout = \"single\"\n" "left = \"25mm\", gutter = \"20mm\""
        at src "G03006" "\"20mm\" }",
      testCase "I4: physical anchors are forbidden in facing mode" $
        forM_ ["left", "right"] $ \side -> do
          let src = page "layout = \"facing\"\n" ("gutter = \"20mm\", " <> side <> " = \"25mm\"")
          at src "G03006" "\"25mm\"",
      testCase "I4: single rejects unused relative master positions" $
        forM_ ["running-head", "folio"] $ \kind -> do
          let src = single <> "[masters.unused]\n" <> kind <> " = { position = \"top-outside\", " <> (if kind == "folio" then "format = \"{n}\"" else "content = \"title\"") <> " }\n"
          at src "G03018" "\"top-outside\"",
      testCase "I4: each independent forbidden master value is reported at its source" $ do
        let src = single <> "[masters.one]\nrunning-head = { position = \"top-inside\", content = \"title\" }\nfolio = { position = \"bottom-outside\", format = \"{n}\" }\n[masters.two]\nrunning-head = { position = \"top-outside\", content = \"title\" }\nfolio = { position = \"bottom-inside\", format = \"{n}\" }\n"
        errors src @?= [(DiagnosticCode "G03018", offsetOf src value) | value <- ["\"top-inside\"", "\"bottom-outside\"", "\"top-outside\"", "\"bottom-inside\""]],
      testCase "I4: physical and central positions work for either master element" $
        forM_ ["facing", "single"] $ \mode -> forM_ ["running-head", "folio"] $ \kind -> forM_ ["top-left", "top-right", "bottom-left", "bottom-right", "top-center", "bottom-center"] $ \pos ->
          valid (page ("layout = \"" <> mode <> "\"\n") (if mode == "single" then "left = \"25mm\"" else "gutter = \"25mm\"") <> "[masters.default]\n" <> kind <> " = { position = \"" <> pos <> "\", " <> (if kind == "folio" then "format = \"{n}\"" else "content = \"title\"") <> " }\n"),
      testCase "I4: sidenotes require an explicit physical side" $ do
        let src = single <> "[sidenotes]\nwidth = \"10mm\"\ngap = \"2mm\"\n"
        at src "G03006" "sidenotes]"
        at (src <> "side = \"outside\"\n") "G03006" "\"outside\""
        forM_ ["left", "right"] $ \side -> valid (src <> "side = \"" <> side <> "\"\n"),
      testCase "I4: a forbidden inherited alignment is reported only at its defining source" $
        forM_ ["horizontal", "vertical"] $ \wm -> do
          let src = T.replace "layout = \"single\"" ("layout = \"single\"\nwriting-mode = \"" <> wm <> "\"") single <> "[paragraph-styles.unused]\nalign = \"towards-spine\"\n[paragraph-styles.child]\nbased-on = \"unused\"\n[paragraph-styles.grandchild]\nbased-on = \"child\"\n"
          at src "G03006" "\"towards-spine\"",
      testCase "I7: explicit hidden folios are rejected and false is accepted" $ do
        let src = single <> "[hidden-folio]\nenabled = true\n"
        at src "G03006" "true"
        valid (T.replace "true" "false" src)
    ]
