module Bibliography0475RoundtripSpec (tests) where

import Control.Monad (forM_)
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyNames
import Golem.Assemble.BibliographyStyle qualified as D
import Golem.Project.BibliographyRequirements
import Golem.Project.Style (Dim, parseStyle, stBibliography)
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "root ADR 0475 TOML roundtrip"
    [ testCase "root ADR 0475 I1: Style rejects every missing mandatory key at runtime" $
        forM_ ["citation-mode", "citation", "citation-delimiter", "citation-sort", "sort", "hanging-indent", "year-suffix", "page-range", "range-delimiter"] $ \key ->
          let omitted = T.unlines [line | line <- T.lines source, not ((key <> "=") `T.isPrefixOf` line)]
           in case parseStyle (FileId 0) omitted of
                Left ds -> do
                  map (\d -> let DiagnosticCode code = diagCode d in code) ds @?= ["G03006"]
                  assertBool (T.unpack key) (all (T.isInfixOf key . diagMessage) ds)
                Right _ -> assertFailure ("missing key accepted: " <> T.unpack key),
      testCase "root ADR 0475 I1: Style rejects incomplete unused declarations" $
        case parseStyle (FileId 0) (T.replace "style='mine'" "style='golem'" (T.unlines [line | line <- T.lines source, not ("citation-mode=" `T.isPrefixOf` line)])) of
          Left ds -> assertBool "unused style path" (any (T.isInfixOf "mine" . diagMessage) ds)
          Right _ -> assertFailure "unused partial declaration accepted",
      testCase "root ADR 0475 A3: TOML names retain both controls through the canonical resolver" $ do
        style <- declaration source
        bibliographyRequiredChecks "mine" (BibliographyUse Nothing []) style @?= []
        names <- maybe (assertFailure "author" >> fail "author") pure (Map.lookup "author" (D.bsNames style))
        (options, extras) <- either (assertFailure . T.unpack) pure (resolveBibliographyNames names)
        formatBibliographyNamesWith extras options people @?= "Alpha, Ann; …; Gina Gamma"
        formatBibliographyNamesWith extras options (take 2 people) @?= "Alpha, Ann and Bea Beta"
        (D.bsCitationPrefix style, D.bsCitationSuffix style) @?= (Just "(", Just ")"),
      testCase "root ADR 0475 I2: no max means unlimited instead of a borrowed cap" $ do
        let names = raw {D.bnMax = Nothing, D.bnUseFirst = Nothing, D.bnUseLast = Nothing, D.bnEtAl = Nothing}
        (options, extras) <- either (assertFailure . T.unpack) pure (resolveBibliographyNames names)
        formatBibliographyNamesWith extras options people @?= "Alpha, Ann, Bea Beta, and Gina Gamma",
      testCase "root ADR 0475 I3: et-al is literal and the empty pair delimiter stays empty" $ do
        (options, extras) <- either (assertFailure . T.unpack) pure (resolveBibliographyNames raw {D.bnEtAl = Just "&[cite x]<>", D.bnPairDelimiter = Just ""})
        formatBibliographyNamesWith extras options people @?= "Alpha, Ann&[cite x]<>Gina Gamma"
        formatBibliographyNamesWith extras options (take 2 people) @?= "Alpha, AnnBea Beta",
      testCase "root ADR 0475 I1: canonical name resolution rejects invalid retention sums" $ do
        assertBool "overflow" (isLeft (resolveBibliographyNames raw {D.bnMax = Just 2147483647, D.bnUseFirst = Just 2147483647, D.bnUseLast = Just 1}))
        assertBool "no max" (isLeft (resolveBibliographyNames raw {D.bnMax = Nothing})),
      testCase "root ADR 0475 I2: short-name resolution needs no full-name defaults" $ do
        let names = D.emptyBibliographyNames {D.bnDelimiter = Just ", ", D.bnLastDelimiter = Just " & ", D.bnPairDelimiter = Just " and "}
        (options, extras) <- either (assertFailure . T.unpack) pure (resolveBibliographyShortNames names)
        formatShortNamesWith extras options (take 2 people) @?= "Alpha and Beta",
      testCase "root ADR 0475 A3: language overlay preserves explicit zero and empty new controls" $ do
        style <- declaration (source <> "\n[bibliography.styles.mine.languages.JA.names.author]\nuse-last=0\npair-delimiter=''\n")
        effective <- either (assertFailure . show) pure (D.bibliographyForLanguage "ja" style)
        let names = Map.lookup "author" (D.bsNames effective)
        fmap D.bnUseLast names @?= Just (Just 0)
        fmap D.bnPairDelimiter names @?= Just (Just ""),
      testCase "root ADR 0475 I1: TOML enforces new-key types and Int32 bounds" $
        mapM_
          ( \line -> case parseStyle (FileId 0) (source <> "\n[bibliography.styles.mine.names.short]\n" <> line <> "\n") of
              Left ds -> map (\d -> let DiagnosticCode code = diagCode d in code) ds @?= ["G03006"]
              Right _ -> assertFailure (T.unpack line)
          )
          ["use-last=-1", "use-last=2147483648", "pair-delimiter=1"]
    ]

raw :: D.BibliographyNames
raw = D.emptyBibliographyNames {D.bnOrder = Just "first-family-given", D.bnPartDelimiter = Just ", ", D.bnInitials = Just False, D.bnDelimiter = Just ", ", D.bnLastDelimiter = Just ", and ", D.bnPairDelimiter = Just " and ", D.bnMax = Just 2, D.bnUseFirst = Just 1, D.bnUseLast = Just 1, D.bnEtAl = Just "; …; "}

people :: [BibliographyName]
people = [PersonalName (Just "Alpha") (Just "Ann"), PersonalName (Just "Beta") (Just "Bea"), PersonalName (Just "Gamma") (Just "Gina")]

declaration :: Text -> IO (D.BibliographyStyle Dim)
declaration text = do
  style <- either (assertFailure . show) pure (parseStyle (FileId 0) text)
  maybe (assertFailure "declaration" >> fail "declaration") pure (Map.lookup "mine" (D.bibStyles (stBibliography style)))

source :: Text
source = T.unlines ["[bibliography]", "style='mine'", "[bibliography.styles.mine]", "citation-mode='numeric'", "citation=[]", "citation-delimiter=''", "citation-sort='written'", "sort=[]", "hanging-indent='0pt'", "year-suffix=false", "page-range='full'", "range-delimiter='–'", "citation-prefix='('", "citation-suffix=')'", "[bibliography.styles.mine.names.author]", "order='first-family-given'", "part-delimiter=', '", "initials=false", "delimiter=', '", "last-delimiter=', and '", "pair-delimiter=' and '", "max=2", "use-first=1", "use-last=1", "et-al='; …; '"]
