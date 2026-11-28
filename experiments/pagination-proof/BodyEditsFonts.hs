{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM_, unless, when)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
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
  leanMode <- (== Just "1") <$> lookupEnv "BODY_EDITS_LEAN"
  let report = if leanMode then hPutStrLn stderr else putStrLn
  when leanMode $ putStrLn "import BodyEdits\nopen BesideBodyEdits BesideOwnership BesideProducer BesideReuse BesidePayloadRounds BesideStore\nprivate def kindAt (xs : List Kind) (key : Nat) : Option Kind := xs[key]?\nprivate def bodyAt (xs : List (Option Nat)) (key : Nat) : Option Nat := match xs[key]? with | none => none | some value => value"
  TIO.writeFile (tmp </> "manifest.toml") "chapters = [\"a.gm\"]\n[metadata]\nid = \"urn:uuid:03520000-0000-4000-8000-000000000001\"\ntitle = \"0352 numbering fixture\"\nlanguage = \"ja\"\ndate = 2026-11-28\n[[metadata.creators]]\nname = \"Fixture\"\nrole = \"author\"\n[source]\nparagraph-separator = \"blank-line\"\n[targets.pdf]\n"
  TIO.writeFile (tmp </> "style.toml") "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nalignment = \"free\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n[fonts.body]\nja = \"NotoSerifJP-Regular.otf\"\n"
  TIO.writeFile (tmp </> "a.gm") ("前文です。\n\n| a | b |\n|---|---|\n| x | y |\n\n```\nあ\nい\n```\n\n@page-break\n\n@nonumber\n@figure tiny.jpg alt=\"fixture\" wrap=start width=3zw\n\n" <> T.replicate 25 "あ" <> "\n\n@column-break\n\n" <> T.replicate 13 "い" <> "\n\n@nonumber\n@figure tiny.jpg alt=\"second\" wrap=start width=3zw\n\n" <> T.replicate 5 "う" <> "\n")
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
        let kind unit = case F.uKind unit of
              F.UPara _ -> ".paragraph"
              F.UFigure _ -> ".figure"
              _ | isJust (F.besideControlFlow unit) -> ".control"
              _ -> ".other"
            bool True = "true"
            bool False = "false"
            sourceKinds = "kindAt [" <> intercalate ", " (map (kind . snd) units) <> "]"
            bodyExpr table = "bodyAt [" <> intercalate ", " [maybe "none" (\(c, _) -> "some " <> show (length (F.cLines c))) (Map.lookup key (F.cuBesides table)) | (key, _) <- units] <> "]"
            pairs table = [(key, length (F.cLines c)) | (key, (c, _)) <- Map.toList (F.cuBesides table)]
            owners = [key | (key, (placed, [], _, _)) <- Map.toList (F.cuFigures cu), isJust (F.pfExclusion placed)]
            sourceJobs = "[" <> intercalate ", " ["⟨" <> show owner <> ", " <> show (length units - owner - 1) <> ", ()⟩" | owner <- owners] <> "]"
            plan = [(5, 0), (7, 3), (9, 7), (5, 1), (999, 2), (6, 4), (7, 0)]
            update table (key, count) = table {F.cuBesides = Map.adjust (\(c, off) -> let (template, _) = F.cuBesides cu Map.! key in (c {F.cLines = take count (cycle (F.cLines template))}, off)) key (F.cuBesides table)}
            histories = scanl update cu plan
            editsExpr changes = "[" <> intercalate ", " ["⟨" <> show key <> ", fun _ => " <> show count <> "⟩" | (key, count) <- changes] <> "]"
        unless (map fst units == [0 .. length units - 1] && owners == [4, 8] && Map.keys (F.cuBesides cu) == [5, 7, 9]) (error "history fixture indices must retain the two figures and three owned paragraphs")
        when (Set.null (F.cuBesideControls cu)) (error "history fixture must contain an owned control")
        when (any (null . F.cLines . fst) (Map.elems (F.cuBesides cu))) (error "initial row templates must be nonempty")
        when leanMode $ do
          putStrLn ("private noncomputable def sourceRound : PayloadRound Unit Nat := ⟨⟨(" <> sourceKinds <> "), " <> show (length units) <> ", false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), " <> sourceJobs <> "⟩, (fun key _ => (" <> bodyExpr cu <> " key).getD 0)⟩")
          putStrLn "private noncomputable def sourceCache : PayloadCache Nat := nextPayloadCache none sourceRound"
          putStrLn ("example : sourceCache.pairs = " <> show (pairs cu) <> " := by decide")
        forM_ (zip [0 :: Int ..] histories) $ \(index, table) -> do
          unless (Map.keys (F.cuBesides table) == Map.keys (F.cuBesides cu)) (error "history changed the domain")
          unless (all (\owner -> F.besideParagraphs (F.cuUnits table) (F.cuBesides table) owner == F.besideParagraphs (F.cuUnits cu) (F.cuBesides cu) owner) owners) (error "history changed the selected keys")
          when leanMode $ do
            let edits = editsExpr (take (fromIntegral index) plan)
                updated = "(applyEdits (fromPairs sourceCache.pairs) " <> edits <> ")"
                nativeClasses = "[" <> intercalate ", " ["⟨" <> bool (Map.member key (F.cuBesides table)) <> ", " <> bool (isJust (F.besideControlFlow unit)) <> "⟩" | (key, unit) <- units] <> "]"
            putStrLn ("example : readPairs (List.range sourceCache.count) " <> updated <> " = " <> show (pairs table) <> " := by decide")
            putStrLn ("example : classes " <> updated <> " (controlAt sourceCache.kindAt) 0 sourceCache.count = " <> nativeClasses <> " := by decide")
            forM_ owners $ \owner -> putStrLn ("example : candidateKeys " <> updated <> " sourceCache.kindAt " <> show owner <> " sourceCache.count = " <> show (F.besideParagraphs (F.cuUnits table) (F.cuBesides table) owner) <> " := by decide")
            putStrLn ("example (owner : Nat) : candidateKeys " <> updated <> " sourceCache.kindAt owner sourceCache.count = candidateKeys (fromPairs sourceCache.pairs) sourceCache.kindAt owner sourceCache.count := by exact root_adr0352_i5_body_edits_selected " <> edits <> " (fromPairs sourceCache.pairs) sourceCache.kindAt owner sourceCache.count")
            putStrLn ("example (key : Nat) (present : (" <> updated <> " key).isSome = true) : sourceCache.kindAt key = some .paragraph := by exact root_adr0352_i5_reached_body_edits_typed [sourceRound] sourceCache rfl " <> edits <> " key present")
        report ("root ADR 0352 I5: " <> show (length histories) <> " real-font states along seven sequential value-only edits preserve body domains, classes, selected keys, and paragraph typing")
      _ -> error "fixture evaluation or geometry failed"
