{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (foldM_, forM_, unless, when)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
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
  leanMode <- (== Just "1") <$> lookupEnv "DERIVED_JOBS_LEAN"
  let report = if leanMode then hPutStrLn stderr else putStrLn
  when leanMode $ putStrLn "import DerivedJobs\nopen BesideReuse BesideProducer BesidePayloadRounds BesideDerivedJobs\nprivate def kindAt (xs : List Kind) (key : Nat) : Option Kind := xs[key]?\nprivate def extraAt (xs : List Bool) (key : Nat) : Bool := (xs[key]?).getD false\nprivate def halt (_ : Unit) : Bool := false\nprivate def allowed (_ : Nat) (_ : Unit) : Bool := true\nprivate def step (_ : Nat) (s : Unit) : Unit := s\nprivate def payloadAt (xs : List (Nat × (Nat × Nat))) (key : Nat) (_ : Unit) : Nat × Nat := (BesideStore.fromPairs xs key).getD (0, 0)\nprivate def pairsOf (cache : Option (PayloadCache (Nat × Nat))) : List (Nat × (Nat × Nat)) := match cache with | none => [] | some c => c.pairs"
  TIO.writeFile (tmp </> "manifest.toml") "chapters = [\"a.gm\"]\n[metadata]\nid = \"urn:uuid:03520000-0000-4000-8000-000000000001\"\ntitle = \"0352 numbering fixture\"\nlanguage = \"ja\"\ndate = 2026-11-28\n[[metadata.creators]]\nname = \"Fixture\"\nrole = \"author\"\n[source]\nparagraph-separator = \"blank-line\"\n[targets.pdf]\n"
  TIO.writeFile (tmp </> "style.toml") "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nalignment = \"free\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n[fonts.body]\nja = \"NotoSerifJP-Regular.otf\"\n"
  let para = T.replicate 25 "あ"
      prefix = "前文です。\n\n@nonumber\n@figure tiny.jpg alt=\"fixture\" wrap=start width=3zw\n\n"
      suffix = "\n\n" <> T.replicate 13 "い" <> "\n\n@nonumber\n@figure tiny.jpg alt=\"second\" wrap=start width=3zw\n\n" <> T.replicate 5 "う" <> "\n"
      original = prefix <> para <> suffix
  TIO.writeFile (tmp </> "a.gm") original
  copyFile "modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" (tmp </> "NotoSerifJP-Regular.otf")
  copyFile "modules/golem-pdf/test/fixtures/tiny.jpg" (tmp </> "tiny.jpg")
  let prepare text = do
        TIO.writeFile (tmp </> "a.gm") text
        evaluated <- evaluateProject Dev tmp >>= either (error . show . pfDiagnostics) pure
        case (evBook evaluated, pageGeometry (FileId 0) False (evStyle evaluated)) of
          (Just book, Right geom) -> do
            fonts <- loadFonts golemFontProvider (diskFiles tmp) (evStyleFile evaluated) (evStyle evaluated) [] >>= either (error . show) pure
            let inp = PdfInput (diskFiles tmp) (evProject evaluated) (evStyle evaluated) book False [] Map.empty Nothing (localStylesOf evaluated) Map.empty (evStyleFile evaluated) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject evaluated)))) (evStyleText evaluated)
            images <- Map.mapMaybe (either (const Nothing) Just) <$> F.loadFigures inp
            pure (inp, geom, fonts, images)
          _ -> error "fixture failed geometry or book"
      build text previous = do
        (inp, geom, fonts, images) <- prepare text
        built <- F.buildFlow inp geom fonts images previous (F.Assumed Map.empty Map.empty Map.empty Map.empty)
        unless (null (F.bErrors built)) (error (show (F.bErrors built)))
        pure built
      signature built = (Map.map (length . F.cLines . fst) (F.cuBesides (F.bComposed built)), F.bUnitFirsts built)
      paragraphKeys built = do
        let units = Map.fromList (F.bUnits built)
        forM_ (Map.keys (F.cuBesides (F.bComposed built))) $ \key ->
          case F.uKind <$> Map.lookup key units of
            Just (F.UPara _) -> pure ()
            _ -> error ("nonparagraph cached key " <> show key)
      emitRound index previous built = when leanMode $ do
        let units = F.bUnits built
            oldUnits = maybe Map.empty (Map.fromList . F.bUnits) previous
            widthsSame = maybe False ((== F.bWidths built) . F.bWidths) previous
            extra = [maybe False (\old -> unit == old && not (F.refersToPage unit)) (Map.lookup key oldUnits) | (key, unit) <- units]
            kind unit = case F.uKind unit of
              F.UPara _ -> ".paragraph"
              F.UFigure _ -> ".figure"
              _ | isJust (F.besideControlFlow unit) -> ".control"
              _ -> ".other"
            bool b = if b then "true" else "false"
            owners = [key | (key, (placed, [], _, _)) <- Map.toList (F.cuFigures (F.bComposed built)), isJust (F.pfExclusion placed)]
            kindList = "[" <> intercalate ", " (map (kind . snd) units) <> "]"
            selectedList = "[" <> intercalate ", " [bool (key `elem` owners) | (key, _) <- units] <> "]"
            derivedJobs = "jobsFrom (kindAt " <> kindList <> ") (extraAt " <> selectedList <> ") (fun _ => ()) " <> show (length units) <> " 0 " <> show (length units)
            expectedJobs = "[" <> intercalate ", " ["(" <> show owner <> ", " <> show (length units - owner - 1) <> ")" | owner <- owners] <> "]"
            priorRounds = intercalate ", " ["r" <> show n | n <- [0 .. index]]
        unless (Map.null (F.asCuts (F.feAssumed (F.bFlowEnv built)))) (error "fixture unexpectedly has assumed cuts")
        let pairs = [(key, (length (F.cLines composed), offset)) | (key, (composed, offset)) <- Map.toList (F.cuBesides (F.bComposed built))]
            pairText (key, (rows, offset)) = "(" <> show key <> ", (" <> show rows <> ", " <> show offset <> "))"
            pairsText = "[" <> intercalate ", " (map pairText pairs) <> "]"
        unless (all (\(_, (_, offset)) -> offset >= 0) pairs) (error "negative beside offset")
        putStrLn ("private noncomputable def c" <> show index <> " : Round Unit := ⟨kindAt [" <> intercalate ", " (map (kind . snd) units) <> "], " <> show (length units) <> ", " <> bool widthsSame <> ", extraAt [" <> intercalate ", " (map bool extra) <> "], true, halt, allowed, step, step, " <> derivedJobs <> "⟩")
        putStrLn ("example : (c" <> show index <> ".jobs.map (fun job => (job.owner, job.fuel))) = " <> expectedJobs <> " := by decide")
        putStrLn ("private noncomputable def r" <> show index <> " : PayloadRound Unit (Nat × Nat) := ⟨c" <> show index <> ", payloadAt " <> pairsText <> "⟩")
        putStrLn ("example : pairsOf (runPayloadRounds none [" <> priorRounds <> "]) = " <> pairsText <> " := by decide")
  previous <- build original Nothing
  emitRound (0 :: Int) Nothing previous
  let variants =
        [ ("same", original),
          ("shorter", prefix <> "あ" <> suffix),
          ("figure", prefix <> "@nonumber\n@figure tiny.jpg alt=\"replacement\" wrap=start width=3zw" <> suffix),
          ("removed", prefix <> T.drop 2 suffix),
          ("control", prefix <> "@column-break" <> suffix)
        ]
  foldM_
    ( \previousRound (index, (name, text)) -> do
        cached <- build text (Just previousRound)
        fresh <- build text Nothing
        paragraphKeys cached
        paragraphKeys fresh
        unless (signature cached == signature fresh) (error ("reused/fresh mismatch " <> name))
        let priorBodies = F.cuBesides (F.bComposed previousRound)
            currentUnits = Map.fromList (F.bUnits cached)
            figuresAtOldKeys = [k | k <- Map.keys priorBodies, Just unit <- [Map.lookup k currentUnits], F.UFigure _ <- [F.uKind unit]]
        unless (name /= "figure" || not (null figuresAtOldKeys)) (error "figure mutation did not hit a prior body key")
        report ("root ADR 0352 I5 reuse: " <> name <> " units=" <> show (length (F.bUnits cached)) <> " old=" <> show (Map.keys priorBodies) <> " now=" <> show (Map.keys (F.cuBesides (F.bComposed cached))) <> " old-key-figures=" <> show figuresAtOldKeys)
        emitRound index (Just previousRound) cached
        pure cached
    )
    previous
    (zip [1 ..] variants)
  report "root ADR 0352 I5 reuse rounds: 6 real-font rounds derive ordered figure jobs and preserve payloads"
