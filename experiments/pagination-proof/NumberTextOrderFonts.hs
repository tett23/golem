{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Control.Monad (forM_, unless, when)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Evaluate
import Golem.Layout.Paginate (FlowAt (..), LineBox (..), RuledBodyAt (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset.Flow qualified as F
import Golem.Typeset.FontProvider (golemFontProvider)
import Golem.Typeset.Fonts (FontProvider (..), PdfInput (..))
import System.Directory (copyFile)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "golem-number-text-order" $ \tmp -> do
  writing <- maybe "horizontal" T.pack <$> lookupEnv "NUMBER_TEXT_ORDER_WRITING"
  alignment <- maybe "free" T.pack <$> lookupEnv "NUMBER_TEXT_ORDER_ALIGNMENT"
  TIO.writeFile (tmp </> "manifest.toml") "chapters = [\"a.gm\"]\n[metadata]\nid = \"urn:uuid:03520000-0000-4000-8000-000000000001\"\ntitle = \"0352 numbering fixture\"\nlanguage = \"ja\"\ndate = 2026-11-28\n[[metadata.creators]]\nname = \"Fixture\"\nrole = \"author\"\n[source]\nparagraph-separator = \"blank-line\"\n[targets.pdf]\n"
  TIO.writeFile (tmp </> "style.toml") $ T.replace "binding = \"left\"" (if writing == "vertical" then "binding = \"right\"" else "binding = \"left\"") $ T.replace "writing-mode = \"horizontal\"" ("writing-mode = \"" <> writing <> "\"") $ T.replace "alignment = \"free\"" ("alignment = \"" <> alignment <> "\"") "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 20\nlines = 20\nline-pitch = \"15pt\"\ncolumns = 1\nalignment = \"free\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n[fonts.body]\nja = \"NotoSerifJP-Regular.otf\"\n"
  TIO.appendFile (tmp </> "style.toml") "[fonts.caption]\nja = \"NotoSerifJP-Regular.otf\"\n[paragraph-styles.caption]\nfont = \"caption\"\n"
  TIO.appendFile (tmp </> "style.toml") "[color.swatches]\npale = { cmyk = [0,0,0,6] }\n[paragraph-styles.body]\npage-break = \"page\"\nkeep-with-next = 2\n[paragraph-styles.boxed]\nbackground = \"pale\"\npadding = \"2pt\"\n[paragraph-styles.ruled]\nrule-before = { weight = \"1pt\", space-after = \"2pt\" }\n"
  TIO.writeFile (tmp </> "a.gm") "検証用の段落です。\n\n@style boxed\n別の段落です。\n\n@style ruled\n罫線の段落です。\n"
  copyFile "modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "NotoSerifJP-Regular.otf")
  copyFile "modules/golem-pdf/test/fixtures/tiny.jpg" (tmp </> "tiny.jpg")
  evaluateProject Dev tmp >>= \case
    Left e -> error (show (pfDiagnostics e))
    Right e -> case (evBook e, pageGeometry (FileId 0) False (evStyle e)) of
      (Just book, Right geom) -> do
        fonts <- loadFonts golemFontProvider (diskFiles tmp) (evStyleFile e) (evStyle e) [] >>= either (error . show) pure
        let inp = PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) Map.empty (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)
            assumed = F.Assumed Map.empty Map.empty Map.empty Map.empty
        images <- Map.mapMaybe (either (const Nothing) Just) <$> F.loadFigures inp
        built <- F.buildFlow inp geom fonts images Nothing assumed
        let cu = F.bComposed built
            units = F.bUnits built
        unless (null (F.bErrors built)) (error (show (F.bErrors built)))
        let emptyNumbered = F.Numbered 0 [] Map.empty Map.empty Map.empty [] Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty
            singles = [(unit, composed) | (key, unit) <- units, Just composed <- [Map.lookup key (F.cuSingles cu)], F.UPara {} <- [F.uKind unit]]
            (base, template) = case singles of
              first : _ -> first
              [] -> error "missing paragraph fixture"
            box = case [value | (unit, _) <- singles, Just value <- [F.uBox unit]] of
              first : _ -> first
              [] -> error "missing boxed fixture"
            rules = case [F.uRules unit | (unit, _) <- singles, F.uRules unit /= (Nothing, Nothing)] of
              first : _ -> first
              [] -> error "missing ruled fixture"
            ind = case F.uKind base of F.UPara value -> value; _ -> error "paragraph required"
            forms = [("paragraph", F.UPara ind, (Nothing, Nothing)), ("heading", F.UHeading 1 "fixture" False, (Nothing, Nothing)), ("notes-title", F.UNotesTitle "fixture", (Nothing, Nothing)), ("term", F.UTerm ind, (Nothing, Nothing)), ("ruled-heading", F.UHeading 1 "fixture" True, rules), ("ruled-paragraph", F.UPara ind, rules), ("ruled-toc", F.UTocEntry 1 (F.uSpan base) ind 0, rules)]
            keep = F.keepOf base
            seed = F.numberText (F.bFlowEnv built) (False, False) (base {F.uStanza = Nothing, F.uBox = Nothing, F.uRules = (Nothing, Nothing)}) template emptyNumbered
            oldRows = flatten (F.nuFlow seed)
            prior = F.nuFlow seed
            priorCases = [("ordinary", prior), ("stanza", prior <> [FStanza keep [oldRows, oldRows]]), ("boxed-stanza", prior <> [FBoxed 97 0 0 [FStanza keep [oldRows, oldRows]]]), ("other-box", prior <> [FBoxed 97 0 0 [FParagraph keep oldRows]])]
        unless (isJust (fst (F.paraStartAndKeep base)) && snd (F.paraStartAndKeep base) == 2) (error "fixture must select both start and keep controls")
        when (null oldRows) (error "fixture must have composed rows")
        forM_ forms $ \(name, kind, selectedRules) ->
          forM_ [Nothing, Just box] $ \selectedBox ->
            forM_ [Nothing, Just 0, Just 1] $ \stanza ->
              forM_ priorCases $ \(historyName, history) ->
                forM_ [(False, False), (True, True)] $ \flags ->
                  forM_ [0, 1, 3] $ \count -> do
                    let composed = template {F.cLines = take count (cycle (F.cLines template)), F.cActualIndents = Nothing}
                        unit = base {F.uKind = kind, F.uRules = selectedRules, F.uBox = selectedBox, F.uStanza = stanza}
                        before = seed {F.nuNext = 11, F.nuFlow = history}
                        after = F.numberText (F.bFlowEnv built) flags unit composed before
                        expectedIds = map lbId (flatten history) <> [11 .. 11 + count - 1]
                        actualIds = map lbId (flatten (F.nuFlow after))
                        stored = [F.slLine (F.nuLines after Map.! key) | key <- [11 .. 11 + count - 1]]
                    unless (actualIds == expectedIds && stored == F.cLines composed && F.nuNext after == 11 + count) (error (show (name, historyName, stanza, flags, count, actualIds, expectedIds)))
                    unless (all (\(key, value) -> F.slLine (F.nuLines after Map.! key) == F.slLine value) (Map.toList (F.nuLines seed))) (error "changed prior row payload")
        putStrLn "root ADR 0352 I5: numberText seven forms x two boxes x three stanza states x four histories x two controls x three row counts = 1008 cases; payload/order/counter/prior rows preserved"
      (_, Left diagnostics) -> error (show diagnostics)
      (Nothing, _) -> error "fixture has no book"

-- The line projection of the supported source branches, not a paginator.
flatten :: [FlowAt a] -> [LineBox]
flatten = concatMap $ \case
  FParagraph _ rows -> rows
  FHeading {fhLines = rows} -> rows
  FDefTerm rows -> rows
  FStanza _ verses -> concat verses
  FRuled {frBody = RuledLines _ rows} -> rows
  FRuled {frBody = RuledHeading _ _ rows} -> rows
  FBoxed {fbBody = body} -> flatten body
  FSection {} -> []
  FKeepNext {} -> []
  _ -> error "unexpected flow in source projection"
