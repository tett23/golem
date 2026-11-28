{-# LANGUAGE GHC2021 #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

-- Root ADR 0352: read-only private-source observation; see check-built-first-ids.sh.
module Main where

import Control.Monad (forM, forM_, replicateM, unless)
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import Data.Maybe (isNothing)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Evaluate
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Project.Style (Dim (..), RuleSpec (..), RuleStyle (..))
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
        unless (null (F.bErrors built)) (error (show (F.bErrors built)))
        let units = F.bUnits built
            cu = F.bComposed built
            fe = F.bFlowEnv built
        body <- case [u | (_, u) <- units, F.uRules u == (Nothing, Nothing), isNothing (F.uBox u), F.UPara _ <- [F.uKind u]] of
          first : _ -> pure first
          [] -> error "fixture has no eligible paragraph"
        figure <- case [u | (_, u) <- units, F.UFigure _ <- [F.uKind u]] of
          first : _ -> pure first
          [] -> error "fixture has no figure"
        pf <- case Map.elems (F.cuFigures cu) of
          (placed, _, _, _) : _ -> pure placed
          [] -> error "fixture has no placed figure"
        let patterns = concat [replicateM n [P, C, X, M, R, B] | n <- [0 .. 4]]
            rule = RuleSpec Nothing 1 Nothing Nothing Nothing RuleSolid (Zw 0) Nothing True
            box = F.UnitBox Nothing 0 Nothing 0 RuleSolid [] 0 0 0
            unitFor tag = case tag of
              P -> Just body
              C -> Just (body {F.uKind = F.UGap 0})
              X -> Just figure
              M -> Nothing
              R -> Just (body {F.uRules = (Just rule, Nothing)})
              B -> Just (body {F.uBox = Just box})
        putStrLn "import ProducedPayloadKeys\nopen BesidePayload BesideProducer BesideStore"
        totals <- forM patterns $ \tags -> do
          let positions = zip [1 ..] tags
              unitAt = Map.insert 0 figure (Map.fromList [(key, u) | (key, tag) <- positions, Just u <- [unitFor tag]])
              owners = 0 : [key | (key, X) <- positions]
          results <- forM owners $ \owner -> do
            paragraphs <- F.composeBeside fe (F.bWidths built) unitAt owner pf
            let keys = map fst paragraphs
            unless
              (all (\key -> lookup key positions == Just P) keys)
              (error "fresh producer emitted a key that is not an eligible paragraph")
            unless
              (all (> owner) keys && and (zipWith (<) keys (drop 1 keys)) && all (\other -> other <= owner || all (< other) keys) owners)
              (error ("fresh producer crossed its source-key interval: " <> show (owner, owners, keys)))
            producerExample tags owner paragraphs
            pure paragraphs
          let allKeys = map fst (concat results)
              storedKeys = Map.keys (Map.fromList (concat results))
          unless
            (allKeys == storedKeys && all (`notElem` storedKeys) owners)
            (error "fresh jobs overlap or own a figure key")
          gatherExample tags owners (concat results)
          pure (length owners, length allKeys)
        putStrLn ("-- root ADR 0352 I5: " <> show (length patterns) <> " typed unit maps; " <> show (sum (map fst totals)) <> " native fresh jobs; " <> show (sum (map snd totals)) <> " owned paragraph keys")
      _ -> error "fixture evaluation or geometry failed"

data Tag = P | C | X | M | R | B deriving (Eq)

kindExpr :: [Tag] -> String
kindExpr tags = "(fun k : Nat => if k = 0 then some Kind.figure else " <> go (zip [1 :: Int ..] tags) <> ")"
  where
    go [] = "none"
    go ((key, tag) : later) = "if k = " <> show key <> " then " <> kind tag <> " else " <> go later
    kind P = "some Kind.paragraph"
    kind C = "some Kind.control"
    kind X = "some Kind.figure"
    kind M = "none"
    kind R = "some Kind.paragraph"
    kind B = "some Kind.paragraph"

callbacks :: [Tag] -> String
callbacks tags =
  let eligible = [key | (key, P) <- zip [1 :: Int ..] tags]
   in "true (fun (_ : Unit) => false) (fun (k : Nat) (_ : Unit) => decide (k ∈ (" <> show eligible <> " : List Nat))) (fun _ (_ : Unit) => ()) (fun _ (_ : Unit) => ()) "

pairExpr :: [(Int, (F.Composed, Int))] -> String
pairExpr pairs = "([" <> intercalate ", " ["(" <> show key <> ", (" <> show (length (F.cLines composed)) <> ", " <> show off <> "))" | (key, (composed, off)) <- pairs] <> "] : List (Nat × (Nat × Nat)))"

payloadExpr :: [(Int, (F.Composed, Int))] -> String
payloadExpr [] = "(fun (_k : Nat) (_ : Unit) => (0, 0))"
payloadExpr pairs = "(fun (k : Nat) (_ : Unit) => " <> go pairs <> ")"
  where
    go [] = "(0, 0)"
    go ((key, (composed, off)) : later) = "if k = " <> show key <> " then (" <> show (length (F.cLines composed)) <> ", " <> show off <> ") else " <> go later

producerExample :: [Tag] -> Int -> [(Int, (F.Composed, Int))] -> IO ()
producerExample tags owner pairs = do
  unless (all (\(_, (_, off)) -> off >= 0) pairs) (error "fixture offset must be nonnegative")
  putStrLn ("example : composePayloads " <> callbacks tags <> kindExpr tags <> " " <> payloadExpr pairs <> " " <> show (owner + 1) <> " () " <> show (length tags - owner + 1) <> " = " <> pairExpr pairs <> " := by decide")

gatherExample :: [Tag] -> [Int] -> [(Int, (F.Composed, Int))] -> IO ()
gatherExample tags owners pairs = do
  let job owner = "⟨" <> show owner <> ", " <> show (length tags - owner + 1) <> ", ()⟩"
      expr = "collectPayloads false true 0 " <> show (length tags + 1) <> " (fun _ => (none : Option (Nat × Nat))) (fun _ => none) " <> kindExpr tags <> " (fun _ => true) " <> callbacks tags <> payloadExpr pairs <> " [" <> intercalate ", " (map job owners) <> "]"
  putStrLn ("example : " <> expr <> " = " <> pairExpr pairs <> " := by decide")
  putStrLn ("example : readPairs (pairKeys (" <> expr <> ")) (fromPairs (" <> expr <> ")) = " <> pairExpr pairs <> " := by decide")
