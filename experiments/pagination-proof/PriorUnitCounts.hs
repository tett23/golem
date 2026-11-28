{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM, unless, when)
import Data.List (intercalate, mapAccumL)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Evaluate
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
main = withSystemTempDirectory "golem-built-firsts" $ \tmp -> do
  leanMode <- (== Just "1") <$> lookupEnv "PRIOR_COUNTS_LEAN"
  let report = if leanMode then hPutStrLn stderr else putStrLn
  when leanMode $ putStrLn "import PriorUnitCounts\nopen BesideReuse BesideOwnership BesideProducer CausalFirstIds\nprivate def kindAt (xs : List Kind) (key : Nat) : Option Kind := xs[key]?\nprivate def bodyAt (xs : List (Option Nat)) (key : Nat) : Option Nat := match xs[key]? with | none => none | some v => v\nprivate def replace (n _ : Nat) : Nat := n"
  TIO.writeFile (tmp </> "manifest.toml") "chapters = [\"a.gm\"]\n[metadata]\nid = \"urn:uuid:03520000-0000-4000-8000-000000000001\"\ntitle = \"0352 numbering fixture\"\nlanguage = \"ja\"\ndate = 2026-11-28\n[[metadata.creators]]\nname = \"Fixture\"\nrole = \"author\"\n[source]\nparagraph-separator = \"blank-line\"\n[targets.pdf]\n"
  TIO.writeFile (tmp </> "style.toml") "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nalignment = \"free\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n[fonts.body]\nja = \"NotoSerifJP-Regular.otf\"\n"
  TIO.writeFile (tmp </> "a.gm") ("前文です。\n\n@nonumber\n@figure tiny.jpg alt=\"fixture\" wrap=start width=3zw\n\n" <> T.replicate 25 "あ" <> "\n\n" <> T.replicate 13 "い" <> "\n\n@nonumber\n@figure tiny.jpg alt=\"second\" wrap=start width=3zw\n\n" <> T.replicate 5 "う" <> "\n")
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
            contributions table = snd (mapAccumL (\numbered unit -> let next = F.numberUnit (F.bFlowEnv built) table numbered unit in (next, F.nuNext next - F.nuNext numbered)) emptyNumbered units)
            initialContributions = contributions cu
            prefixParts owner =
              [ case (F.uKind unit, Map.lookup key (F.cuFigures cu)) of
                  (F.UFigure _, Just (placed, errors, _, _)) | null errors, Just _ <- F.pfExclusion placed -> (1, Just key)
                  _ -> (delta, Nothing)
              | ((key, unit), delta) <- take owner (zip units initialContributions)
              ]
            projected table = map (\(fixed, owner) -> fixed + maybe 0 (\i -> sum [length (F.cLines body) | key <- F.besideParagraphs (F.cuUnits table) (F.cuBesides table) i, let (body, _) = F.cuBesides table Map.! key]) owner)
        unless (map fst units == [0 .. length units - 1]) (error "fixture indices must be contiguous")
        let initial = F.bUnitFirsts built
            jobs = Map.toList (F.cuBesides cu)
            kind unit = case F.uKind unit of
              F.UPara _ -> ".paragraph"
              F.UFigure _ -> ".figure"
              _ -> ".other"
            oldKinds = "kindAt [" <> intercalate ", " (map (kind . snd) units) <> "]"
            oldBody = "bodyAt [" <> intercalate ", " [maybe "none" (\(c, _) -> "some " <> show (length (F.cLines c))) (Map.lookup key (F.cuBesides cu)) | (key, _) <- units] <> "]"
            leanParts parts = "[" <> intercalate ", " ["(" <> show fixed <> ", " <> maybe "none" (("some " <>) . show) owner <> ")" | (fixed, owner) <- parts] <> "]"
        unless (length jobs == 3 && Map.size (F.cuFigures cu) == 2) (error "fixture must contain two figures and three owned paragraphs")
        checks <- forM jobs $ \(j, (old, off)) -> forM [0, 1, 3, 7] $ \n -> do
          let altered = cu {F.cuBesides = Map.insert j (old {F.cLines = take n (cycle (F.cLines old))}, off) (F.cuBesides cu)}
              rebuilt = F.numberComposedFlow inp geom (F.bFlowEnv built) units (F.bWidths built) altered
              expected = Map.mapWithKey (\i ident -> ident + if i > j then n - length (F.cLines old) else 0) initial
              owners = [i | i <- Map.keys (F.cuFigures cu), j `elem` F.besideParagraphs (F.cuUnits cu) (F.cuBesides cu) i]
              modelFirst = case owners of
                [owner] ->
                  let prefix = takeWhile (/= j) (F.besideParagraphs (F.cuUnits cu) (F.cuBesides cu) owner)
                   in initial Map.! owner + 1 + sum [length (F.cLines c) | k <- prefix, let (c, _) = F.cuBesides cu Map.! k]
                _ -> error "owned paragraph must have exactly one owner"
              okay = F.bUnitFirsts rebuilt == expected && Map.lookup j (F.bUnitFirsts rebuilt) == Just modelFirst
          unless okay (error (show (j, n, expected, F.bUnitFirsts rebuilt, modelFirst)))
          case owners of
            [owner] -> do
              let parts = prefixParts owner
                  oldCounts = take owner initialContributions
                  newCounts = take owner (contributions altered)
              unless (oldCounts == newCounts && projected cu parts == oldCounts && projected altered parts == newCounts) (error ("outer unit contribution mismatch " <> show (j, n, parts, oldCounts, newCounts)))
              when leanMode $ do
                let changedBody = "(adjustBeside (replace " <> show n <> ") " <> show j <> " (" <> oldBody <> "))"
                    contributionsExpr = "unitContributions " <> changedBody <> " (" <> oldKinds <> ") " <> show (length units) <> " id " <> leanParts parts
                    selected = F.besideParagraphs (F.cuUnits cu) (F.cuBesides cu) owner
                    beforeKeys = takeWhile (/= j) selected
                    afterKeys = drop 1 (dropWhile (/= j) selected)
                    rowCounts keys = "(countsFor " <> show keys <> " (rowCount id " <> changedBody <> "))"
                putStrLn ("example : " <> contributionsExpr <> " = " <> show newCounts <> " := by decide")
                putStrLn ("example : besideFromTwoPass (" <> contributionsExpr <> ") [] " <> rowCounts beforeKeys <> " " <> rowCounts afterKeys <> " (rowCount id " <> changedBody <> " " <> show j <> ") 0 = some " <> show (F.bUnitFirsts rebuilt Map.! j) <> " := by decide")
            _ -> error "expected one owner"
        report ("root ADR 0352 I5: " <> show (sum (map length checks)) <> " real-font Built renumberings preserve all outer prefix contribution counts")
      _ -> error "fixture evaluation or geometry failed"
