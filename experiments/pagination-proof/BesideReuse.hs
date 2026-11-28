{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM_, unless)
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
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "golem-built-firsts" $ \tmp -> do
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
  previous <- build original Nothing
  let variants =
        [ ("same", original),
          ("shorter", prefix <> "あ" <> suffix),
          ("figure", prefix <> "@nonumber\n@figure tiny.jpg alt=\"replacement\" wrap=start width=3zw" <> suffix),
          ("removed", prefix <> T.drop 2 suffix),
          ("control", prefix <> "@column-break" <> suffix)
        ]
  forM_ variants $ \(name, text) -> do
    cached <- build text (Just previous)
    fresh <- build text Nothing
    paragraphKeys cached
    paragraphKeys fresh
    unless (signature cached == signature fresh) (error ("reused/fresh mismatch " <> name))
    let priorBodies = F.cuBesides (F.bComposed previous)
        currentUnits = Map.fromList (F.bUnits cached)
        figuresAtOldKeys = [k | k <- Map.keys priorBodies, Just unit <- [Map.lookup k currentUnits], F.UFigure _ <- [F.uKind unit]]
    unless (name /= "figure" || not (null figuresAtOldKeys)) (error "figure mutation did not hit a prior body key")
    putStrLn ("root ADR 0352 I5 reuse: " <> name <> " units=" <> show (length (F.bUnits cached)) <> " old=" <> show (Map.keys priorBodies) <> " now=" <> show (Map.keys (F.cuBesides (F.bComposed cached))) <> " old-key-figures=" <> show figuresAtOldKeys)
  putStrLn "root ADR 0352 I5 reuse: 5 real-font cached/fresh comparisons passed"
