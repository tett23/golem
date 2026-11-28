{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM, forM_, replicateM, unless, when)
import Data.List (intercalate)
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
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "golem-built-firsts" $ \tmp -> do
  coverage <- (== Just "1") <$> lookupEnv "BESIDE_COVERAGE"
  adjustment <- (== Just "1") <$> lookupEnv "BESIDE_ADJUSTMENT"
  when (coverage && adjustment) (error "choose one observation mode")
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
        let jobs = Map.toList (F.cuBesides cu)
        unless (length jobs == 3 && Map.size (F.cuFigures cu) == 2) (error "fixture must contain two figures and three owned paragraphs")
        body <- case [(u, c) | (j, (c, _)) <- jobs, Just u <- [Map.lookup j (F.cuUnits cu)]] of
          first : _ -> pure first
          [] -> error "fixture has no paragraph prototype"
        figure <- case [u | (_, u) <- units, F.UFigure _ <- [F.uKind u]] of
          first : _ -> pure first
          [] -> error "fixture has no figure prototype"
        putStrLn ((if adjustment then "import BesideAdjustment" else if coverage then "import BesideCoverage" else "import BesideOwnership") <> "\nopen BesideOwnership")
        let patterns = concat [replicateM n [P, C, X, M, Q] | n <- [0 .. 4]]
            maps tags =
              let pairs = zip [1 ..] tags
                  unitFor = \case
                    P -> Just (fst body)
                    C -> Just ((fst body) {F.uKind = F.UGap 0})
                    Q -> Just ((fst body) {F.uKind = F.UGap 0})
                    X -> Just figure
                    M -> Nothing
                  allUnits = Map.insert 0 figure (Map.fromList [(key, u) | (key, tag) <- pairs, Just u <- [unitFor tag]])
                  allBeside = Map.fromList [(key, (snd body, 0)) | (key, tag) <- pairs, tag == P || tag == Q]
               in (allUnits, allBeside)
            actual owner tags = let (us, bs) = maps tags in F.besideParagraphs us bs owner
        count <- forM patterns $ \tags -> do
          example 1 tags (actual 0 tags)
          when coverage (coverageExamples tags (actual 0 tags))
          when adjustment $ do
            let (us, bs) = maps tags
            forM_ [0 .. length tags + 1] $ \target -> do
              let changed = Map.adjust (\(c, offset) -> (c {F.cLines = []}, offset)) target bs
                  original = F.besideParagraphs us bs 0
                  updated = F.besideParagraphs us changed 0
              unless
                (Map.keys bs == Map.keys changed && original == updated)
                (error "rebreaking changed the side-job domain or selected keys")
              adjustmentExample tags target (Map.map (length . F.cLines . fst) bs) updated
          forM_ [0 .. length tags] $ \splitAt -> do
            let before = take splitAt tags
                after = drop splitAt tags
                joined = before <> [X] <> after
                barrier = length before + 1
                first = actual 0 joined
                second = actual barrier joined
            unless (all (\a -> all (a <) second) first) (error "owner keys overlap or are out of source order")
            example 1 joined first
            example (barrier + 1) after second
          pure (1 + 2 * (length tags + 1))
        putStrLn ("-- root ADR 0352 I5: " <> show (length patterns) <> " guard maps and " <> show (sum count) <> " native scans")
      _ -> error "fixture evaluation or geometry failed"

data Tag = P | C | X | M | Q deriving (Eq)

example :: Int -> [Tag] -> [Int] -> IO ()
example start tags result = putStrLn ("example : scan " <> show start <> " [" <> intercalate "," (map flags tags) <> "] = " <> show result <> " := by decide")
  where
    flags P = "⟨true,false⟩"
    flags C = "⟨false,true⟩"
    flags Q = "⟨true,true⟩"
    flags X = "⟨false,false⟩"
    flags M = "⟨false,false⟩"

-- Every eligible row is selected, controls are skipped, and barriers stop later rows.
coverageExamples :: [Tag] -> [Int] -> IO ()
coverageExamples tags selected = forM_ (zip [0 ..] tags) $ \(index, tag) -> do
  let key = index + 1
      clear = all (\t -> t == P || t == C || t == Q) (take index tags)
      eligible = tag == P || tag == Q
      expected = clear && eligible
      actual = key `elem` selected
  unless (actual == expected) (error "beside membership differs from eligible-prefix characterization")
  putStrLn ("example : (" <> show key <> " ∈ scan 1 [" <> intercalate "," (map flags tags) <> "]) ↔ " <> (if actual then "True" else "False") <> " := by decide")
  where
    flags P = "⟨true,false⟩"
    flags C = "⟨false,true⟩"
    flags Q = "⟨true,true⟩"
    flags X = "⟨false,false⟩"
    flags M = "⟨false,false⟩"

-- A payload update may remove every row but does not remove its map key.
adjustmentExample :: [Tag] -> Int -> Map.Map Int Int -> [Int] -> IO ()
adjustmentExample tags target counts selected =
  putStrLn
    ( "example : scan 1 (classes (adjustBeside (fun (_ : Nat) => 0) "
        <> show target
        <> " (fun _k : Nat => "
        <> lookupExpr (Map.toAscList counts)
        <> ")) (fun _k : Nat => "
        <> controlExpr
        <> ") 1 "
        <> show (length tags)
        <> ") = "
        <> show selected
        <> " := by decide"
    )
  where
    lookupExpr [] = "none"
    lookupExpr ((key, count) : rest) = "if _k = " <> show key <> " then some " <> show count <> " else " <> lookupExpr rest
    controls = [key | (key, tag) <- zip [1 :: Int ..] tags, tag == C || tag == Q]
    controlExpr = "decide (_k ∈ (" <> show controls <> " : List Nat))"
