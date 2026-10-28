{- | The values of style.toml as the settings of golem-html (docs/adr ADR
0090): golem-html does not depend on golem-project, so golem-driver turns
the styles into the types of golem-html, with lengths as CSS strings.
-}
module Golem.Driver.Html
  ( htmlCharStyles,
    htmlParaStyles,
    htmlRule,
    htmlFeatures,
    rubyAlignCss,
    cssLength,
    cssFontSize,
  )
where

import Control.Monad (join)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Html
import Golem.Project.Style
import Golem.Syntax.Length qualified as L

-- | The character styles of a style, resolved for CSS (docs/adr ADR 0005).
htmlCharStyles :: Style -> Map Text HtmlCharStyle
htmlCharStyles style =
  Map.fromList
    [ (n, HtmlCharStyle (csFont d) (csSyntheticBold d == Just True) (csSyntheticItalic d == Just True) (csColor d) (htmlFeatures (csKerning d) (csTracking d) (csProportional d) (csBaselineShift d)) code background padding)
    | n <- Map.keys (stCharStyles style),
      Just d <- [charStyle style n],
      let code = isCodeCharStyle style n
          -- the background and the padding of inline code (golem-driver ADR 0029)
          background = if code then charStyleBackground style n else Nothing
          padding = if code then cssLength <$> csPadding d else Nothing
    ]

-- | The paragraph styles of a style, resolved for CSS (docs/adr ADR 0005, 0006).
htmlParaStyles :: Style -> Map Text HtmlParaStyle
htmlParaStyles style =
  Map.fromList
    [ ( n,
        HtmlParaStyle
          (psFont d)
          (psLineBreaks d == Just KeepLines)
          (fromMaybe 0 (psSpaceBetween d))
          (cssLength (fromMaybe (Zw 0) (psIndent d)))
          (cssLength (fromMaybe (Zw 0) (psFirstLineIndent d)))
          (htmlFeatures (psKerning d) (psTracking d) (psProportional d) (psBaselineShift d))
          (htmlRule style <$> join (psRuleBefore d))
          (htmlRule style <$> join (psRuleAfter d))
      )
    | n <- Map.keys (stParaStyles style),
      Just d <- [paraStyle style (Just n)]
    ]

{- | A rule of a paragraph style or a heading for CSS (golem-driver ADR
0027, 0028, 0035): zw of the length and the indents as em, the line style as one of the border styles of CSS
and the swatch as its RGB; a rule without a colour takes the colour of
the text. Without a length the block is as wide as the line, or as the
rest of the line when an indent is written.
-}
htmlRule :: Style -> RuleSpec -> HtmlRule
htmlRule style r =
  let start = case rsStartIndent r of
        Zw 0 -> Nothing
        d -> Just (cssLength d)
      end = cssLength <$> rsEndIndent r
      width = case rsLength r of
        Just l -> Just (cssLength l)
        Nothing -> if isJust start || isJust end then Nothing else Just "100%"
      border = case rsStyle r of
        RuleSolid -> "solid"
        RuleMulti _ -> "double"
        RuleDashed _ _ -> "dashed"
        RuleDotted _ -> "dotted"
        RuleJapaneseDots _ -> "dotted"
        RuleWavy -> "solid"
      colour = case rsColor r >>= (`Map.lookup` stSwatches style) of
        Just (Swatch cmyk) -> let (cr, cg, cb) = cmykToRgb cmyk in " rgb(" <> T.pack (show cr) <> ", " <> T.pack (show cg) <> ", " <> T.pack (show cb) <> ")"
        Nothing -> ""
      {- the spaces between the rule and the text (golem-driver ADR 0035): zw
      is a character of the size of the grid, in pt, or rem without one -}
      gridSize = case stPage style >>= pageGrid of
        Just Grid {gridFontSize = Abs fs} | fs > 0 -> Just fs
        _ -> Nothing
      space = \case
        Nothing -> "0"
        Just (Abs 0) -> "0"
        Just (Zw 0) -> "0"
        Just (Abs sp) -> cssLength (Abs sp)
        Just (Zw z) -> maybe (L.emText z <> "rem") (\fs -> cssLength (Abs (L.zwToSp fs z))) gridSize
   in HtmlRule
        { hrWidth = width,
          hrStartIndent = start,
          hrEndIndent = end,
          hrBorder = cssLength (Abs (rsWeight r)) <> " " <> border <> colour,
          hrOuter = space (rsSpaceBefore r),
          hrInner = space (rsSpaceAfter r)
        }

-- | The keys of the spacing of characters for CSS (docs/adr/0020).
htmlFeatures :: Maybe Kerning -> Maybe Int -> Maybe Bool -> Maybe Dim -> HtmlFeatures
htmlFeatures k t p b =
  HtmlFeatures
    { hfKerning =
        k >>= \case
          KernMetrics -> Just "metrics"
          KernJapaneseEqualWidth -> Just "japanese-equal-width"
          KernNone -> Just "none"
          KernOptical -> Nothing,
      hfTracking = t,
      hfProportional = p,
      hfBaselineShift = cssLength <$> b
    }

-- | A ruby alignment of style.toml as a CSS ruby-align value (golem-layout ADR 0009).
rubyAlignCss :: Text -> Text
rubyAlignCss = \case
  "1:2:1" -> "space-around"
  "0:1:0" -> "space-between"
  "start" -> "start"
  _ -> "center"

{- | A length of style.toml in CSS: zw as em, other units as pt, with at
most four decimals (docs/adr ADR 0103).
-}
cssLength :: Dim -> Text
cssLength = \case
  Zw r -> L.emText r <> "em"
  Abs sp -> L.ptText sp <> "pt"

{- | A size of style.toml as a CSS font-size (golem-driver ADR 0010): zw as
em, an absolute size as its ratio to an absolute grid size in em, pt
without one.
-}
cssFontSize :: Style -> Dim -> Text
cssFontSize style = \case
  Zw r -> L.emText r <> "em"
  Abs sp -> case stPage style >>= pageGrid of
    Just Grid {gridFontSize = Abs fs} | fs > 0 -> L.emText (toRational (unSp sp) / toRational (unSp fs)) <> "em"
    _ -> cssLength (Abs sp)
