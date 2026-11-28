{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM, forM_, unless)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Evaluate
import Golem.Layout.KnuthPlass (Hyphen (..), Item (..), glue, isPatternHyphen)
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Project.Style (Sp (..))
import Golem.Syntax
import Golem.Typeset.Flow qualified as F
import Golem.Typeset.FontProvider (golemFontProvider)
import Golem.Typeset.Fonts (FontProvider (..), PdfInput (..))
import System.Directory (copyFile)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "golem-built-firsts" $ \tmp -> do
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
        unless (null (F.bErrors built)) (error (show (F.bErrors built)))
        let jobs = Map.toList (F.cuBesides cu)
        unless (length jobs == 3 && Map.size (F.cuFigures cu) == 2) (error "fixture must contain two figures and three owned paragraphs")
        putStrLn "import Pagination\nopen GolemPagination"
        counts <- forM jobs $ \(j, (old, _)) -> do
          let unit = F.cuUnits cu Map.! j
              size = length (F.cItems old)
              starts = [0, 1, size `div` 2, max 0 (size - 2)]
          forM starts $ \start -> forM [1, 2, 4] $ \divisor -> do
            let width = Sp (max 1 (unSp (F.feMeasure (F.bFlowEnv built)) `div` divisor))
                broken = F.rebreakComposed (F.bFlowEnv built) unit (const width) start old
                positions = F.cBreakPositions broken
            unless (length positions == length (F.cLines broken)) (error "line and break counts differ")
            forM_ positions $ \position -> do
              let next = F.itemAfterBreak old position
              unless (start <= position && position < size && start < next && next <= size) (error (show (start, position, next, size)))
              example old position next
            pure (length positions)
        firstSource <- case jobs of
          (_, (first, _)) : _ -> pure first
          [] -> error "fixture has no owned source"
        box <- case [item | item@Box {} <- F.cItems firstSource] of
          first : _ -> pure first
          [] -> error "fixture source has no box"
        let synthetic = firstSource {F.cItems = [box, glue 0 0 0, Penalty 0 0 NoHyphen, Penalty 0 10000 NoHyphen, box, Penalty 0 (-10000) NoHyphen]}
        forM_ [0 .. length (F.cItems synthetic) - 1] $ \position ->
          example synthetic position (F.itemAfterBreak synthetic position)
        putStrLn ("-- root ADR 0352 I4: 36 fresh suffixes, " <> show (sum [sum byWidth | byStart <- counts, byWidth <- byStart]) <> " selected offsets, and 6 synthetic skip boundaries")
      _ -> error "fixture evaluation or geometry failed"

example :: F.Composed -> Int -> Int -> IO ()
example source position next = putStrLn ("example : captionNextSourceStart [" <> joinComma (map kind (F.cItems source)) <> "] " <> show (position + 1) <> " = " <> show next <> " := by decide")
  where
    kind = \case
      Box {} -> ".box"
      Glue {} -> ".glue"
      Penalty _ value hyphen -> ".penalty (" <> show value <> ") " <> if isPatternHyphen hyphen then "true" else "false"
    joinComma [] = ""
    joinComma [x] = x
    joinComma (x : xs) = x <> "," <> joinComma xs
