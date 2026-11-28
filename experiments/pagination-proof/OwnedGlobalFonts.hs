{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM, unless, when)
import Data.List (intercalate, mapAccumL)
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
  leanMode <- (== Just "1") <$> lookupEnv "OWNED_GLOBAL_LEAN"
  let report = if leanMode then hPutStrLn stderr else putStrLn
  when leanMode $ putStrLn "import OwnedGlobal\nopen BesideOwnedGlobal BesideOwnedRows BesideOwnedScan BesideOwnedFirst BesideFigureTable BesideJobValues BesideReuse BesideOwnership BesideProducer CausalFirstIds BesideClassifiedPrefix BesidePayloadRounds BesideStore\nprivate def kindAt (xs : List Kind) (key : Nat) : Option Kind := xs[key]?\nprivate def bodyAt (xs : List (Option Nat)) (key : Nat) : Option Nat := match xs[key]? with | none => none | some v => v\nprivate def skipAt (xs : List Bool) (key : Nat) : Bool := (xs[key]?).getD false\nprivate def replace (n _ : Nat) : Nat := n"
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
        let emptyNumbered = F.Numbered 0 [] Map.empty Map.empty Map.empty [] Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty Map.empty
            contributions table = snd (mapAccumL (\numbered unit -> let next = F.numberUnit (F.bFlowEnv built) table numbered unit in (next, F.nuNext next - F.nuNext numbered)) emptyNumbered units)
            initialContributions = contributions cu
            slotFor (key, unit) delta = case (F.uKind unit, Map.lookup key (F.cuFigures cu)) of
              (F.UTable _, _) -> ".table " <> show delta
              (F.UFigure _, Just (placed, errors, _, _)) | null errors, Just _ <- F.pfExclusion placed -> ".wrapped"
              _ -> ".ordinary " <> show delta
            sourceSlots = "[" <> intercalate ", " (zipWith slotFor units initialContributions) <> "]"
            bool True = "true"
            bool False = "false"
            sourceSkip = "skipAt [" <> intercalate ", " [bool (Set.member key (F.cuBesideControls cu)) | (key, _) <- units] <> "]"
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
              _ | isJust (F.besideControlFlow unit) -> ".control"
              _ -> ".other"
            oldKinds = "kindAt [" <> intercalate ", " (map (kind . snd) units) <> "]"
            observedBody = "bodyAt [" <> intercalate ", " [maybe "none" (\(c, _) -> "some " <> show (length (F.cLines c))) (Map.lookup key (F.cuBesides cu)) | (key, _) <- units] <> "]"
            oldBody = "(fromPairs sourceCache.pairs)"
            sourceOwners = [key | (key, (placed, [], _, _)) <- Map.toList (F.cuFigures cu), isJust (F.pfExclusion placed)]
            figureValue (placed, issues, _, _) = "some (" <> show (spanStart (F.pfSpan placed)) <> ", " <> bool (null issues && isJust (F.pfExclusion placed)) <> ")"
            figureValues = "[" <> intercalate ", " [maybe "none" figureValue (Map.lookup key (F.cuFigures cu)) | (key, _) <- units] <> "]"
        unless (length jobs == 3 && Map.size (F.cuFigures cu) == 2) (error "fixture must contain two figures and three owned paragraphs")
        when (Set.null (F.cuBesideControls cu)) (error "fixture must contain a control owned by a wrapped figure")
        unless (any (\((_, unit), delta) -> case F.uKind unit of F.UTable _ -> delta > 0; _ -> False) (zip units initialContributions)) (error "fixture must number a real table")
        unless (any (\((_, unit), delta) -> case F.uKind unit of F.UCode {} -> delta > 0; _ -> False) (zip units initialContributions)) (error "fixture must number real code lines")
        unless (any (\(_, unit) -> case F.uKind unit of F.UBreak _ -> True; _ -> False) units) (error "fixture must contain a page-break control")

        unless (all (\(key, _) -> case F.uKind <$> lookup key units of Just (F.UPara _) -> True; _ -> False) jobs) (error "fixture side bodies must be current paragraphs")
        unless (all (\(placed, _, _, _) -> spanStart (F.pfSpan placed) >= 0) (Map.elems (F.cuFigures cu))) (error "fixture figure offsets must be nonnegative")
        when leanMode $ do
          let owners = [key | (key, (placed, [], _, _)) <- Map.toList (F.cuFigures cu), isJust (F.pfExclusion placed)]
              leanJobs = "[" <> intercalate ", " ["⟨" <> show owner <> ", " <> show (length units - owner - 1) <> ", ()⟩" | owner <- owners] <> "]"
              pairs = [(key, length (F.cLines c)) | (key, (c, _)) <- jobs]
          putStrLn ("private noncomputable def sourceRound : PayloadRound Unit Nat := ⟨⟨(" <> oldKinds <> "), " <> show (length units) <> ", false, (fun _ => false), true, (fun _ => false), (fun _ _ => true), (fun _ state => state), (fun _ state => state), " <> leanJobs <> "⟩, (fun key _ => (" <> observedBody <> " key).getD 0)⟩")
          putStrLn "private noncomputable def sourceCache : PayloadCache Nat := nextPayloadCache none sourceRound"
          putStrLn ("example : sourceCache.pairs = " <> show pairs <> " := by decide")
          putStrLn ("private def sourceFigures : Nat → Option (Nat × Bool) := fun key => match (" <> figureValues <> " : List (Option (Nat × Bool)))[key]? with | none => none | some value => value")
          putStrLn "private def eligible (value : Nat × Bool) : Bool := value.2\nprivate def initializeJob (_ : Nat) (value : Nat × Bool) : Nat := value.1"
          mapM_ (\owner -> let (placed, _, _, _) = F.cuFigures cu Map.! owner in putStrLn ("private def figureJob" <> show owner <> " : ReuseJob Nat := ⟨" <> show owner <> ", " <> show (length units - owner - 1) <> ", " <> show (spanStart (F.pfSpan placed)) <> "⟩")) sourceOwners
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
                let changedBody = "(adjustBeside (replace " <> show n <> ") " <> show j <> " (fromPairs sourceCache.pairs))"
                    bodyName = "(fromPairs sourceCache.pairs)"
                    sourceJobExpr = "(valueJobs eligible initializeJob sourceCache.count (figurePairs sourceCache.kindAt sourceFigures 0 sourceCache.count))"
                    pairExpr table = "allPairs " <> table <> " sourceCache.kindAt sourceCache.count id (derivedStart " <> table <> " sourceCache.kindAt sourceCache.count 0 id (" <> sourceSkip <> ") " <> sourceSlots <> ") " <> sourceJobExpr
                    pairsAt table firsts = concat [snd (mapAccumL (\ident key -> let (c, _) = F.cuBesides table Map.! key in (ident + length (F.cLines c), (key, ident))) (firsts Map.! sourceOwner + 1) (F.besideParagraphs (F.cuUnits table) (F.cuBesides table) sourceOwner)) | sourceOwner <- sourceOwners]
                    oldPairs = pairsAt cu initial
                    nativePairs = pairsAt altered (F.bUnitFirsts rebuilt)
                    actualIdent = F.bUnitFirsts rebuilt Map.! j
                unless (all (\(key, ident) -> Map.lookup key (F.bUnitFirsts rebuilt) == Just ident) nativePairs) (error "native concatenated first IDs must agree with Built")
                putStrLn ("example : " <> pairExpr bodyName <> " = " <> show oldPairs <> " := by decide")
                putStrLn ("example : " <> pairExpr changedBody <> " = " <> show nativePairs <> " := by decide")
                putStrLn ("example : fromPairs (" <> pairExpr changedBody <> ") " <> show j <> " = some " <> show actualIdent <> " := by decide")
                putStrLn ("example : fromPairs (" <> pairExpr changedBody <> ") " <> show j <> " = fromPairs (" <> pairExpr bodyName <> ") " <> show j <> " := by exact root_adr0352_i5_reached_global_first_unchanged [sourceRound] sourceCache rfl sourceFigures eligible initializeJob " <> show j <> " 0 id (replace " <> show n <> ") (" <> sourceSkip <> ") " <> sourceSlots)
            _ -> error "expected one owner"
        report ("root ADR 0352 I5: " <> show (sum (map length checks)) <> " real-font Built renumberings preserve derived global owned first-ID lookups through reached caches and current figure jobs")
      _ -> error "fixture evaluation or geometry failed"
