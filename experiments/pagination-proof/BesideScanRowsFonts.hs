{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM_, unless, when)
import Data.List (intercalate, mapAccumL)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Set qualified as Set
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Evaluate
import Golem.Layout.Paginate (FlowAt (..), LineBox (..))
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
  leanMode <- (== Just "1") <$> lookupEnv "BESIDE_SCAN_ROWS_LEAN"
  let report = if leanMode then hPutStrLn stderr else putStrLn
  when leanMode $ putStrLn "import BesideScanRows\nopen BesideScanRows BesideWrappedRowFold NumberedPayload BesideOwnership CausalFirstIds\nprivate def bodyAt (xs : List (Option (List Nat))) (key : Nat) : Option (List Nat) := match xs[key]? with | none => none | some value => value"
  TIO.writeFile (tmp </> "manifest.toml") "chapters = [\"a.gm\"]\n[metadata]\nid = \"urn:uuid:03520000-0000-4000-8000-000000000001\"\ntitle = \"0352 numbering fixture\"\nlanguage = \"ja\"\ndate = 2026-11-28\n[[metadata.creators]]\nname = \"Fixture\"\nrole = \"author\"\n[source]\nparagraph-separator = \"blank-line\"\n[targets.pdf]\n"
  TIO.writeFile (tmp </> "style.toml") "[page]\nsize = \"A5\"\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n[page.grid]\nfont-size = \"10pt\"\ncharacters = 20\nlines = 30\nline-pitch = \"15pt\"\ncolumns = 1\nalignment = \"free\"\nposition = { top = \"18mm\", gutter = \"20mm\" }\n[fonts.body]\nja = \"NotoSerifJP-Regular.otf\"\n"
  TIO.appendFile (tmp </> "style.toml") "[fonts.caption]\nja = \"NotoSerifJP-Regular.otf\"\n[paragraph-styles.caption]\nfont = \"caption\"\n"
  TIO.writeFile (tmp </> "a.gm") ("前文です。\n\n| a | b |\n|---|---|\n| x | y |\n\n```\nあ\nい\n```\n\n@page-break\n\n@nonumber\n@figure tiny.jpg alt=\"fixture\" wrap=start width=5zw\n  検証用の図。\n\n" <> T.replicate 25 "あ" <> "\n\n@column-break\n\n" <> T.replicate 13 "い" <> "\n\n@nonumber\n@figure tiny.jpg alt=\"second\" wrap=start width=5zw\n  検証用の図。\n\n" <> T.replicate 5 "う" <> "\n")
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
            jobKeys = Map.keys (F.cuBesides cu)
            owners = [key | (key, (placed, [], _, _)) <- Map.toList (F.cuFigures cu), isJust (F.pfExclusion placed)]
            controls = Set.toList (F.cuBesideControls cu)
            rowTokens key table = [key * 100 + k `mod` 3 | k <- [0 .. length (F.cLines (fst (F.cuBesides table Map.! key))) - 1]]
            bodyExpr table = "(bodyAt [" <> intercalate ", " [if Map.member key (F.cuBesides table) then "some " <> show (rowTokens key table) else "none" | (key, _) <- units] <> "])"
            boxesOf = \case
              FWrapped {fwBeside = rows} -> rows
              FContinued _ rows -> rows
              _ -> error "numberFigure emitted an unexpected flow"
        unless (map fst units == [0 .. length units - 1]) (error "fixture unit indices must be dense and nonnegative")
        unless (length jobKeys == 3 && length owners == 2 && Map.size (F.cuFigures cu) == 2 && not (null controls)) (error "fixture must contain two wrapped figures, three bodies and a wrapped control")
        when (any (null . F.pfCaption . firstPlaced) (Map.elems (F.cuFigures cu))) (error "fixture captions must be present")
        let (firstKey, secondKey, thirdKey) = case jobKeys of
              [first, second, third] -> (first, second, third)
              _ -> error "fixture must contain exactly three body keys"
            controlKey = case controls of
              first : _ -> first
              [] -> error "fixture must contain a wrapped control"
            plan = [(firstKey, 0), (secondKey, 3), (thirdKey, 7), (firstKey, 1), (999, 2), (controlKey, 4), (secondKey, 0)]
            update table (key, count) = table {F.cuBesides = Map.adjust (\(composed, off) -> let (template, _) = F.cuBesides cu Map.! key in (composed {F.cLines = take count (cycle (F.cLines template)), F.cActualIndents = Nothing}, off)) key (F.cuBesides table)}
            histories = scanl update cu plan
        forM_ (zip [0 :: Int ..] histories) $ \(history, current) -> do
          let builtNow = F.numberComposedFlow inp geom (F.bFlowEnv built) units (F.bWidths built) current
          unless (Map.keys (F.cuBesides current) == jobKeys) (error "history changed the body domain")
          forM_ owners $ \owner -> do
            let keys = F.besideParagraphs (F.cuUnits current) (F.cuBesides current) owner
                chunks = [F.cLines (fst (F.cuBesides current Map.! key)) | key <- keys]
                sourceChunks = [F.cLines composed | (_, composed, _, _, _) <- F.besideRows (F.bFlowEnv built) current owner]
                figure = F.cuFigures current Map.! owner
                unit = F.cuUnits current Map.! owner
                prefix = foldl (F.numberUnit (F.bFlowEnv built) current) emptyNumbered (takeWhile ((< owner) . fst) units)
                cases = [("isolated-0", emptyNumbered), ("isolated-3", emptyNumbered {F.nuNext = 3}), ("isolated-17", emptyNumbered {F.nuNext = 17}), ("source-prefix", prefix)]
            unless (chunks == sourceChunks) (error "candidate body rows differ from numberFigure's paragraph order")
            unless (F.nuNext prefix == F.bUnitFirsts builtNow Map.! owner && null (F.nuErrors prefix)) (error "source prefix does not match the current Built first ID")
            forM_ cases $ \(label, prior) -> do
              let first = F.nuNext prior
                  after = F.numberFigure (F.bFlowEnv built) current owner unit figure prior
                  newFlows = drop (length (F.nuFlow prior)) (F.nuFlow after)
                  boxes = concatMap boxesOf newFlows
                  actualIds = map lbId boxes
                  prefixIds = Map.keys (F.nuLines prior)
                  priorFigureIds = Map.keys (F.nuFigures prior)
                  expectedRows = concat chunks
                  prefixRows = map F.slLine (Map.elems (F.nuLines prior))
                  expectedCounter = first + 1 + length expectedRows
                  ownerFirst = F.bUnitFirsts builtNow Map.! owner
                  table = [(key, first + (F.bUnitFirsts builtNow Map.! key) - ownerFirst) | key <- keys]
                  folded = snd (mapAccumL (\ident (key, rows) -> (ident + length rows, (key, ident))) (first + 1) (zip keys chunks))
                  keyedExpr = "[" <> intercalate ", " ["(" <> show key <> ", " <> show (rowTokens key current) <> ")" | key <- keys] <> "]"
                  tokens = concatMap (`rowTokens` current) keys
                  oldPairs = zip prefixIds [20000 .. 20000 + length prefixIds - 1]
                  newPairs = zip actualIds tokens
                  allPairs = oldPairs <> newPairs
                  body = bodyExpr current
                  wrapped = "wrappedRows " <> show first <> " " <> show keys <> " " <> body
                  chunksExpr = "(chunksFor " <> show keys <> " " <> body <> ")"
              unless (first >= 0 && all (< first) prefixIds && all (>= 0) keys) (error "source ID range cannot be projected to Nat")
              unless (all (< first) priorFigureIds && Map.keys (F.nuFigures after) == priorFigureIds <> [first] && fmap F.pfSpan (Map.lookup first (F.nuFigures after)) == Just (F.pfSpan (firstPlaced figure))) (error "reserved figure ID did not retain the current figure exactly once")
              case newFlows of
                FWrapped {fwId = ident} : _ -> unless (ident == first) (error "wrapped flow has the wrong figure ID")
                _ -> error "wrapped flow must begin with its figure"

              unless (F.nuNext after == expectedCounter && actualIds == [first + 1 .. expectedCounter - 1]) (error "wrapped figure fold changed its reserved ID or row count")
              unless (Map.keys (F.nuLines after) == prefixIds <> actualIds && map F.slLine (Map.elems (F.nuLines after)) == prefixRows <> expectedRows) (error "wrapped fold lost, duplicated or reordered a composed row")
              unless (null (F.nuErrors after)) (error (show (F.nuErrors after)))
              unless (all (\key -> F.bUnitFirsts builtNow Map.! key >= ownerFirst + 1) keys && table == folded) (error "Built beside first IDs disagree with the row fold")
              when leanMode $ do
                putStrLn ("-- history=" <> show history <> " owner=" <> show owner <> " case=" <> label)
                putStrLn ("example : (scan " <> show (first + 1) <> " " <> keyedExpr <> ").2 = " <> show table <> " := by decide")
                putStrLn ("example : (scan " <> show (first + 1) <> " " <> keyedExpr <> ").1 = " <> show (F.nuNext after) <> " := by decide")
                putStrLn ("example : (" <> wrapped <> ").next = " <> show (F.nuNext after) <> " := by decide")
                putStrLn ("example : (" <> wrapped <> ").rows = " <> show newPairs <> " := by decide")
                putStrLn ("example : (runChunks (⟨" <> show (first + 1) <> ", " <> show oldPairs <> "⟩ : RowState Nat) " <> chunksExpr <> ").rows = " <> show allPairs <> " := by decide")
                putStrLn ("example : " <> wrapped <> " = ⟨" <> show first <> " + (1 + ownedRows (countsFor " <> show keys <> " (rowCount List.length " <> body <> "))), numberRows (" <> show first <> " + 1) (flatten " <> chunksExpr <> ")⟩ := root_adr0352_i5_wrapped_derived_contribution " <> show keys <> " " <> body <> " " <> show first)
        report "root ADR 0352 I5: 64 captioned wrapped folds agree with their Built beside first-ID tables; 16 use the actual source prefix; ordered payload and prior rows are retained"
      _ -> error "fixture evaluation or geometry failed"
  where
    firstPlaced (placed, _, _, _) = placed
