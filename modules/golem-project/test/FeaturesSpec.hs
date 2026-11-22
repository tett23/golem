-- | The OpenType features of roles and styles (docs/adr/0268).
module FeaturesSpec (tests) where

import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Project.Feature
import Golem.Project.Style
import Golem.Syntax
import Support (offsetOf)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "OpenType features (docs/adr/0268)"
    [ testCase "root ADR 0397 I6: free placement accepts dimensional paragraph spacing and line pitch" $
        mapM_ (\unit -> codes (parseStyle (FileId 0) (freeSource "free" ("[paragraph-styles.dialogue]\nline-pitch = \"18" <> unit <> "\"\nspace-between = \"6" <> unit <> "\"\nspace-before = 1\nspace-after = \"0" <> unit <> "\"\n"))) @?= []) ["mm", "pt", "Q", "H", "in", "zw"],
      testCase "root ADR 0397 A2: typed length and count references retain their units and source sites" $ do
        let source = freeSource "free" "[values.length]\npitch = \"18pt\"\ngap = \"6pt\"\n[values.count]\nrows = 2\n[paragraph-styles.dialogue]\nline-pitch = \"pitch\"\nspace-before = \"rows\"\nspace-between = \"gap\"\n"
        codes (parseStyle (FileId 0) source) @?= []
        sort [(kind, name) | (kind, name, _, _, False) <- layoutValueSites source] @?= sort [("length", "pitch"), ("length", "gap"), ("count", "rows")],
      testCase "root ADR 0397 A2: local styles resolve both length and count names and offer both in completion" $ do
        let source = freeSource "free" "[values.length]\npitch = \"18pt\"\ngap = \"6pt\"\n[values.count]\nrows = 2\n"
        style <- either (assertFailure . show) pure (parseStyle (FileId 0) source)
        case localStyleDefWithValues style ParagraphKind [("line-pitch", LocalWord "pitch"), ("space-before", LocalWord "rows")] of
          Right (Right def) -> do
            psLinePitch def @?= Just (PitchDim (Abs 1179648))
            psSpaceBefore def @?= Just 2
          result -> assertFailure (show result)
        layoutValueNames style ParagraphKind "space-between" @?= ["gap", "pitch", "rows"]
        case localStyleDefWithValues style ParagraphKind [("line-pitch", LocalWord "auto")] of
          Right (Right def) -> psLinePitch def @?= Just PitchAuto
          result -> assertFailure (show result),
      testCase "root ADR 0397 I6: the default grid mode rejects dimensional settings without a page grid" $
        mapM_ (\setting -> codes (parseStyle (FileId 0) ("[paragraph-styles.body]\n" <> setting <> "\n")) @?= ["G03006"]) ["line-pitch = \"18pt\"", "space-between = \"6pt\"", "space-before = \"6pt\"", "space-after = \"6pt\""],
      testCase "root ADR 0397 I6: grid rejects dimensional paragraph settings" $
        mapM_ (\setting -> codes (parseStyle (FileId 0) (freeSource "grid" ("[paragraph-styles.dialogue]\n" <> setting <> "\n"))) @?= ["G03006"]) ["line-pitch = \"18pt\"", "space-between = \"6pt\"", "space-before = \"6pt\"", "space-after = \"6pt\""],
      testCase "root ADR 0397 I6: free rejects zero pitch after sp rounding and negative spacing" $
        mapM_ (\setting -> codes (parseStyle (FileId 0) (freeSource "free" ("[paragraph-styles.dialogue]\n" <> setting <> "\n"))) @?= ["G03006"]) ["line-pitch = \"0pt\"", "line-pitch = \"0.00000001pt\"", "space-between = \"-1pt\""],
      testCase "root ADR 0384 I1: verse numbering interval is accepted" $
        codes (parseStyle (FileId 0) "[paragraph-styles.verse]\nline-number-interval = 5\n") @?= [],
      testCase "root ADR 0384 I1: interval inherits and a child can override it" $
        case parseStyle (FileId 0) "[paragraph-styles.verse]\nline-number-interval = 5\n[paragraph-styles.stanza]\nbased-on = \"verse\"\nline-number-interval = 2\n" of
          Left ds -> assertFailure (show ds)
          Right style -> do
            (paraStyle style (Just "verse") >>= psLineNumberInterval) @?= Just 5
            (paraStyle style (Just "stanza") >>= psLineNumberInterval) @?= Just 2,
      testCase "ADR 0378 I1: a role accepts punctuation-proportional without enabling any feature" $
        codes (parseStyle (FileId 0) "[fonts.body]\nja = \"a.otf\"\npunctuation-proportional = true\n") @?= [],
      testCase "I4: every form reads and its normal form reads back the same" $ do
        let forms = [("smcp", ("smcp", 1)), ("+smcp", ("smcp", 1)), ("-smcp", ("smcp", 0)), ("smcp=0", ("smcp", 0)), ("smcp=1", ("smcp", 1)), ("salt=2", ("salt", 2)), ("salt=65535", ("salt", 65535)), ("ss01", ("ss01", 1)), ("jp90", ("jp90", 1))]
        mapM_ (\(s, f) -> parseFeature s @?= Just f) forms
        mapM_ (\(_, f) -> parseFeature (featureText f) @?= Just f) forms
        mapM_ (\(_, f) -> let n = featureText f in featureText <$> parseFeature n @?= Just n) forms
        map (fmap featureText . parseFeature) ["+smcp", "smcp=0", "smcp=1", "salt=2"] @?= map Just ["smcp", "-smcp", "smcp", "salt=2"],
      testCase "I5: the strings that do not read" $
        mapM_ (\s -> parseFeature s @?= Nothing) bad,
      testCase "I5: each element that does not read is one G03124 at itself, in order" $ do
        let one s =
              let src = "[character-styles.x]\nfeatures = [\"smcp\", \"" <> s <> "\"]\n"
               in case parseStyle (FileId 0) src of
                    Left [d] -> do
                      diagCode d @?= DiagnosticCode "G03124"
                      spanStart (diagSpan d) @?= offsetOf src ("\"" <> s <> "\"]")
                      assertBool (T.unpack (diagMessage d)) (featureMessage s `T.isPrefixOf` diagMessage d)
                    r -> assertFailure (show (T.unpack s, r))
        mapM_ one (filter (not . T.any (== '"')) bad)
        let two = "[character-styles.x]\nfeatures = [\"smc\", \"liga\", \"kern[3:5]\"]\n"
        case parseStyle (FileId 0) two of
          Left ds -> do
            map diagCode ds @?= replicate 2 (DiagnosticCode "G03124")
            map (spanStart . diagSpan) ds @?= [offsetOf two "\"smc\"", offsetOf two "\"kern"]
          Right _ -> assertFailure "read",
      testCase "I5: the features of a role and of a paragraph style are checked too" $ do
        codes (parseStyle (FileId 0) "[fonts.body]\nja = \"a.otf\"\nfeatures = [\"palt\", \"aalt=on\"]\n") @?= ["G03124"]
        codes (parseStyle (FileId 0) "[paragraph-styles.x]\nfeatures = [\"tnum\", \"\"]\n") @?= ["G03124"]
        codes (parseStyle (FileId 0) "[character-styles.x]\nfeatures = \"smcp\"\n") @?= ["G03006"],
      testCase "I5: @style-def writes the elements in one string separated by commas" $ do
        localStyleDef CharacterKind [("features", LocalString "smcp,-liga")]
          @?= Right (Left noCharDef {csFeatures = [Feature "smcp" 1 SiteNone, Feature "liga" 0 SiteNone]})
        either (map fst) (const []) (localStyleDef CharacterKind [("features", LocalString "smcp,")]) @?= ["G03124"]
        either (map fst) (const []) (localStyleDef ParagraphKind [("features", LocalString "smc,kern[3:5]")]) @?= ["G03124", "G03124"],
      testCase "I3: the features of based-on are added after the parent's, the last value of a tag kept" $
        case parseStyle (FileId 0) "[character-styles.a]\nfeatures = [\"onum\", \"smcp\"]\n\n[character-styles.b]\nbased-on = \"a\"\nfeatures = [\"-smcp\", \"salt=2\"]\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            normalFeatureTexts (charFeatures s "b") @?= ["onum", "-smcp", "salt=2"]
            normalFeatureTexts (charFeatures s "a") @?= ["onum", "smcp"],
      testCase "I3: paragraph styles add theirs after the parent's" $
        case parseStyle (FileId 0) "[paragraph-styles.a]\nfeatures = [\"tnum\", \"lnum\"]\n\n[paragraph-styles.b]\nbased-on = \"a\"\nfeatures = [\"onum\", \"-tnum\"]\n" of
          Left ds -> assertFailure (show ds)
          Right s -> normalFeatureTexts (paraFeatures s (Just "b")) @?= ["lnum", "onum", "-tnum"],
      testCase "I3: a table of a built-in name and a @style-def of the same name add theirs after" $
        case parseStyle (FileId 0) "[character-styles.strong]\nfeatures = [\"smcp\"]\n\n[character-styles.c]\nfeatures = [\"onum\"]\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            normalFeatureTexts (charFeatures s "strong") @?= ["smcp"]
            let local = noLocalStyles {lsCharStyles = Map.fromList [("c", noCharDef {csFeatures = [Feature "c2sc" 1 SiteNone, Feature "onum" 0 SiteNone]})]}
            normalFeatureTexts (charFeatures (withLocalStyles s local) "c") @?= ["c2sc", "-onum"],
      testCase "I3: the normal list keeps the last value of each tag at its place" $ do
        normalFeatures [("smcp", 1), ("smcp", 1)] @?= [("smcp", 1)]
        normalFeatures [("smcp", 1), ("smcp", 0)] @?= [("smcp", 0)]
        normalFeatures [("smcp", 0), ("smcp", 1)] @?= [("smcp", 1)]
        normalFeatures [("onum", 1), ("smcp", 1), ("onum", 0)] @?= [("smcp", 1), ("onum", 0)]
        normalFeatures [] @?= [],
      testCase "a style without features has none, and its other keys read as before" $
        case parseStyle (FileId 0) "[character-styles.a]\nsize = \"1zw\"\n" of
          Left ds -> assertFailure (show ds)
          Right s -> do
            charFeatures s "a" @?= []
            (charStyle s "a" >>= csSize) @?= Just (Zw 1),
      testCase "each feature of style.toml knows its line and column" $
        case parseStyle (FileId 0) "[character-styles.a]\nfeatures = [\"onum\", \"smcp\"]\n" of
          Left ds -> assertFailure (show ds)
          Right s -> map ftSite (charFeatures s "a") @?= [SiteToml 2 13, SiteToml 2 21]
    ]

-- | The table of the strings that do not read (docs/adr/0268).
bad :: [Text]
bad = ["", "smc", "smcpx", "smcp=", "smcp=-1", "salt=65536", "kern[3:5]", "sm cp", "smcｐ", "aalt=on", "+-smcp", "smcp=1.5"]

codes :: Either [Diagnostic] a -> [Text]
codes = either (map ((\(DiagnosticCode c) -> c) . diagCode)) (const [])

-- A complete ordinary page, so each failure identifies the new setting.
freeSource :: Text -> Text -> Text
freeSource alignment settings = "[page]\nsize = \"A5\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 20\nlines = 20\nline-pitch = \"15pt\"\nposition = { top = \"20mm\", gutter = \"20mm\" }\nalignment = \"" <> alignment <> "\"\n" <> settings
