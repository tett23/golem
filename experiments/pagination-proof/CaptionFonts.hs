-- Root ADR 0352: the caption rows of the table of boundary inputs, with
-- the advances of real fonts.  golem-typeset lays out a figure of a tall
-- image (1 by 3) with the caption "F1" and k Ms in Source Sans Pro and
-- Source Serif, as golem-driver's FigureSpec.hs does, on columns of 1 to
-- 4 lines.  For each, this prints a line "in fig ..." with the measured
-- items of the caption, the parameters of the breaker and the sizes of
-- the column, the input of CaptionValues.lean, and the line "out ..."
-- golem-typeset gives: the pass, the breaks and the demerits of the
-- caption, the grid lines it takes, and the image lines, the size along
-- and across the lines of the image, or G07038.
--
-- The items are those of the caption's lines as golem-typeset placed
-- them, with the forced break at the end.  A line keeps its items and
-- the penalty it ends at when that penalty has a width; the script stops
-- unless every break is such a penalty followed by a box, so that no item
-- is lost between two lines, and unless golem-layout's breakParagraph
-- gives the placed lines again from these items and parameters.
module Main (main) where

import Control.Monad (forM, unless)
import Data.ByteString qualified as BS
import Data.List (intercalate)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.KnuthPlass
import Golem.Layout.Paginate (HeadingBlock (..), headingBlock)
import Golem.Project.Style (Composition (..), LineAdjustment (..), ParaStyleDef (..), Style (..), dimToSp, paraStyle)
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.Typeset (PartLine (..), PdfInput (..), PdfLayout (..), PlacedFigure (..), layoutPdf)
import Support (figStyle, miniManifest, realProvider, withMiniInput)
import System.Exit (die)

pt :: Sp
pt = 65536

-- | The image of the figure: 100 by 300, across the lines 3 for 1 along them.
image :: (FilePath, BS.ByteString)
image = ("images/tall.svg", TE.encodeUtf8 "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"300\"><rect width=\"100\" height=\"300\" fill=\"none\"/></svg>")

-- | FigureSpec.hs's pageStyle "horizontal" "left" 12 capacity 1 20 20, with the caption in the font.
style :: Int -> BS.ByteString
style capacity =
  figStyle
    ( TE.encodeUtf8
        ( T.concat
            [ "[page]\nsize = { width = \"300pt\", height = \"400pt\" }\nbinding = \"left\"\nwriting-mode = \"horizontal\"\n\n",
              "[page.grid]\nfont-size = \"10pt\"\ncharacters = 12\nlines = ",
              T.pack (show capacity),
              "\nline-pitch = \"15pt\"\ncolumns = 1\nposition = { top = \"20pt\", gutter = \"20pt\" }\n"
            ]
        )
    )
    <> "\n[fonts.body]\nlatin = \"fonts/latin.otf\"\n\n[fonts.caption]\nlatin = \"fonts/latin.otf\"\n\n[paragraph-styles.caption]\nfont = \"caption\"\n"

-- | The figure and the caption of k Ms; its number makes it "F1　" and the Ms.
source :: Int -> T.Text
source k = "@figure images/tall.svg alt=\"t\"\n  " <> T.replicate k "M" <> "\n\n"

-- | The layout, or its error codes, and the parameters of the breaker for the caption.
layout :: BS.ByteString -> Int -> Int -> IO (Either [DiagnosticCode] PlacedFigure, Params)
layout font capacity k = do
  r <- withMiniInput realProvider miniManifest (style capacity) (source k) [image, ("fonts/latin.otf", font)] $ \inp geom fonts -> do
    placed <- layoutPdf inp geom fonts
    pure (placed, captionParams (piStyle inp))
  case r of
    Left ds -> die ("the project does not evaluate: " <> show ds)
    Right (Left ds, ps) -> pure (Left (map diagCode ds), ps)
    Right (Right pl, ps) -> case Map.elems (plFigures pl) of
      [pf] -> pure (Right pf, ps)
      other -> die ("not one figure but " <> show (length other))

-- | kpParams and adjustedParams of golem-typeset for the paragraph style caption, at 10pt.
captionParams :: Style -> Params
captionParams st =
  let comp = stComposition st
      caption = paraStyle st (Just "caption")
   in defaultParams
        { pPretolerance = compPretolerance comp,
          pTolerance = compTolerance comp,
          pEmergencyStretch = dimToSp (10 * pt) (compEmergencyStretch comp),
          pExpansion = compExpansion comp,
          pProtrusion = compProtrusion comp || compHanging comp,
          pPullInFirst = (caption >>= psLineAdjustment) /= Just Balanced
        }

-- | The items of the placed lines, with the forced break at the end.
itemsOf :: [Line] -> IO [Item]
itemsOf ls = do
  let joins = zip ls (drop 1 ls)
      broken (l, next) = case (reverse (lineItems l), lineItems next) of
        (Penalty w _ _ : _, Box {} : _) -> w > 0
        _ -> False
  unless (all broken joins) (die "a break is not a penalty with a width before a box")
  pure (concatMap lineItems ls <> [Penalty 0 (-infPenalty) NoHyphen])

flag :: Bool -> String
flag b = if b then "1" else "0"

sp :: Sp -> String
sp = show . unSp

-- | The items as CheckCaptionAssembly.hs --values writes them.
itemToken :: Item -> String
itemToken = \case
  Box w c -> intercalate ":" ["b", sp w, sp (bcProtrudeStart c), sp (bcProtrudeEnd c), sp (bcEdgeStart c), sp (bcEdgeEnd c)]
  Glue w y z _ _ -> intercalate ":" ["g", sp w, sp y, sp z]
  Penalty w p h -> intercalate ":" ["p", sp w, show p, flag (flagged h), hyphenEnd h]
  where
    flagged = \case
      PatternHyphen _ -> True
      ExplicitHyphen -> True
      SoftHyphen _ -> True
      _ -> False
    hyphenEnd = \case
      PatternHyphen q -> sp q
      SoftHyphen q -> sp q
      _ -> "-"

-- | The text of the boxes of each line, and its ratio, to compare lines.
lineKey :: Line -> ([T.Text], Rational, Sp)
lineKey l = ([bcText c | Box _ c <- lineItems l], lineRatio l, lineOverflow l)

main :: IO ()
main = do
  sans <- BS.readFile "modules/golem-font/test/fonts/SourceSansPro-Regular.otf"
  serif <- BS.readFile "modules/golem-font/test/fonts/SourceSerifVariable-Roman.ttf"
  let measure = 120 * pt
      body = 10 * pt
      pitch = 15 * pt
  rows <- fmap concat . forM [("sans", sans), ("serif", serif)] $ \(name, font) ->
    fmap concat . forM [10 .. 14] $ \k -> do
      -- the caption as placed in a column of 4 lines, where it always leaves the image a line
      (wide, ps) <- layout font 4 k
      pf4 <- either (\ds -> die (name <> " " <> show k <> ": " <> show ds)) pure wide
      let placed = map ptLine (pfCaption pf4)
      unless (pExpansion ps == Nothing) (die "the glyphs expand")
      unless (all ((== measure) . lineTarget) placed) (die "a line is not as long as the measure")
      items <- itemsOf placed
      let again = breakParagraph ps (const measure) items
      unless (map lineKey (brLines again) == map lineKey placed) (die (name <> " " <> show k <> ": breakParagraph breaks the items otherwise"))
      unless (hbSpan (headingBlock body pitch body (length placed) 1) == pfCaptionSpan pf4) (die "the caption span is not headingBlock's")
      forM [1 .. 4] $ \capacity -> do
        (result, _) <- if capacity == 4 then pure (wide, ps) else layout font capacity k
        let fig = case result of
              Left codes -> unwords [show (pfCaptionSpan pf4), unwords [c | DiagnosticCode t <- codes, let c = T.unpack t]]
              Right pf -> unwords [show (pfCaptionSpan pf), intercalate ":" [show (pfImageLines pf), sp (pfAlong pf), sp (pfAcross pf)]]
            input =
              unwords
                ( ["fig", show capacity, sp body, sp pitch, sp body, sp measure, "3", "1"]
                    <> [show (brPass again), show (pLinePenalty ps), show (pAdjDemerits ps), show (pDoubleHyphenDemerits ps)]
                    <> [sp (pEndStretch ps), sp (pEmergencyStretch ps), flag (pPullInFirst ps), flag (pProtrusion ps)]
                    <> [show (pPretolerance ps), show (pTolerance ps), sp measure]
                    <> map itemToken items
                )
            output = unwords [show (brPass again), intercalate "," (map show (brPositions again)), show (brDemerits again), fig]
        pure (name <> " " <> show k <> " " <> show capacity, input, output)
  mapM_ (\(label, i, o) -> putStrLn ("-- " <> label) >> putStrLn ("in " <> i) >> putStrLn ("out " <> o)) rows
