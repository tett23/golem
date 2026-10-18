{-# LANGUAGE MultiWayIf #-}

{- | SVG figures as drawings (golem-pdf ADR 0009): the static subset of
SVG 1.1 and SVG 2 in the table of the ADR, read into paths with their
paint, groups with a matrix and a clip. Whatever is outside the subset is
not ignored: every such element, attribute and value is collected, in
the order of the document, with its line and column. Text that is not
outlined is outside the subset.

The drawing is in the coordinates of the viewport, y downwards, from 0
to the width and the height ('svgSize', in CSS px). Numbers are rationals;
see "Golem.Svg.Number".
-}
module Golem.Svg
  ( Svg (..),
    DrawOp (..),
    Paint (..),
    Stroke (..),
    Color (..),
    FillRule (..),
    LineCap (..),
    LineJoin (..),
    Segment (..),
    Point,
    Matrix (..),
    ClipRect (..),
    SvgError (..),
    Unsupported (..),
    readSvg,
  )
where

import Data.Bifunctor (bimap)
import Data.ByteString (ByteString)
import Data.Char (isAlpha, isDigit, isSpace, toLower)
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty, nonEmpty)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Svg.Colors (namedColor)
import Golem.Svg.Css
import Golem.Svg.Number
import Golem.Svg.Xml

-- ------------------------------------------------------------------ the drawing

data Svg = Svg
  { -- | the width and the height of the viewport, in CSS px
    svgSize :: !(Rational, Rational),
    svgDrawing :: ![DrawOp]
  }
  deriving stock (Eq, Show)

data DrawOp
  = DPath !Paint ![Segment]
  | -- | a matrix, a clip in the coordinates of the group, the ops inside
    DGroup !Matrix !(Maybe ClipRect) ![DrawOp]
  deriving stock (Eq, Show)

-- | An sRGB colour, each component from 0 to 255.
data Color = Color !Int !Int !Int
  deriving stock (Eq, Show)

data FillRule = NonZero | EvenOdd
  deriving stock (Eq, Show)

data LineCap = CapButt | CapRound | CapSquare
  deriving stock (Eq, Show)

data LineJoin = JoinMiter | JoinRound | JoinBevel
  deriving stock (Eq, Show)

data Stroke = Stroke
  { stColor :: !Color,
    stWidth :: !Rational,
    stCap :: !LineCap,
    stJoin :: !LineJoin,
    stMiterLimit :: !Rational,
    -- | empty for a solid line
    stDash :: ![Rational],
    stDashOffset :: !Rational
  }
  deriving stock (Eq, Show)

data Paint = Paint
  { paFill :: !(Maybe Color),
    paFillRule :: !FillRule,
    paStroke :: !(Maybe Stroke)
  }
  deriving stock (Eq, Show)

type Point = (Rational, Rational)

data Segment
  = MoveTo !Point
  | LineTo !Point
  | CurveTo !Point !Point !Point
  | ClosePath
  deriving stock (Eq, Show)

-- | [a b c d e f]: (x, y) to (a x + c y + e, b x + d y + f).
data Matrix = Matrix !Rational !Rational !Rational !Rational !Rational !Rational
  deriving stock (Eq, Show)

data ClipRect = ClipRect !Rational !Rational !Rational !Rational
  deriving stock (Eq, Show)

-- | Something outside the subset: its name, where it is, and whether it is text.
data Unsupported = Unsupported
  { unName :: !Text,
    unLine :: !Int,
    unColumn :: !Int,
    unText :: !Bool
  }
  deriving stock (Eq, Show)

data SvgError
  = -- | the reason of G0810
    SvgMalformed !Text
  | -- | G0811
    SvgUnsupported !(NonEmpty Unsupported)
  deriving stock (Eq, Show)

identity :: Matrix
identity = Matrix 1 0 0 1 0 0

-- | m · n: n is applied first.
mul :: Matrix -> Matrix -> Matrix
mul (Matrix a b c d e f) (Matrix a' b' c' d' e' f') =
  Matrix (a * a' + c * b') (b * a' + d * b') (a * c' + c * d') (b * c' + d * d') (a * e' + c * f' + e) (b * e' + d * f' + f)

translate :: Rational -> Rational -> Matrix
translate = Matrix 1 0 0 1

scaleM :: Rational -> Rational -> Matrix
scaleM x y = Matrix x 0 0 y 0 0

apply :: Matrix -> Point -> Point
apply (Matrix a b c d e f) (x, y) = (a * x + c * y + e, b * x + d * y + f)

-- ------------------------------------------------------------------ reading

svgNs :: Text
svgNs = "http://www.w3.org/2000/svg"

readSvg :: ByteString -> Either SvgError Svg
readSvg bytes = do
  root <- either (Left . SvgMalformed) Right (parseXml bytes)
  if elNs root == svgNs && elName root == "svg" then Right () else Left (SvgMalformed "SVG のルートの要素がありません")
  let sheets = concatMap sheetOf (styleElements root)
      rules = [(specificity s, i, s, ds) | (i, Rule sels ds) <- zip [0 :: Int ..] (map fst sheets), s <- sels]
      env0 = Env rules (markerTable env0 root) defaultStyle
  (size, rootMatrix, rootClip, rootProbs) <- rootGeometry root
  let (probs, ops) = elementChildren env0 (cascade env0 defaultStyle root) root
      allProbs = rootProbs <> probs
      body = if rootMatrix == identity && isNothing rootClip then ops else [DGroup rootMatrix rootClip ops]
  case nonEmpty allProbs of
    Just us -> Left (SvgUnsupported us)
    Nothing -> Right (Svg size body)
  where
    sheetOf e = [(r, ()) | r <- fst (parseStylesheet (T.concat [t | NText t _ <- elChildren e]))]

-- ------------------------------------------------------------------ styles

-- | The computed properties of an element, by name.
type Style = Map Text Text

defaultStyle :: Style
defaultStyle =
  Map.fromList
    [ ("fill", "black"),
      ("fill-rule", "nonzero"),
      ("stroke", "none"),
      ("stroke-width", "1"),
      ("stroke-linecap", "butt"),
      ("stroke-linejoin", "miter"),
      ("stroke-miterlimit", "4"),
      ("stroke-dasharray", "none"),
      ("stroke-dashoffset", "0"),
      ("visibility", "visible"),
      ("color", "black"),
      ("marker-start", "none"),
      ("marker-mid", "none"),
      ("marker-end", "none"),
      ("fill-opacity", "1"),
      ("stroke-opacity", "1")
    ]

inherited :: [Text]
inherited = Map.keys defaultStyle

-- | The properties Golem draws.
handled :: [Text]
handled = inherited <> ["display", "opacity", "rx", "ry", "marker", "overflow"]

-- | The properties that act only on text: skipped whatever their value.
textOnly :: [Text]
textOnly =
  [ "font-family",
    "font-size",
    "font-weight",
    "font-style",
    "font-variant",
    "font-stretch",
    "font-feature-settings",
    "font-variation-settings",
    "font",
    "text-anchor",
    "text-orientation",
    "dominant-baseline",
    "alignment-baseline",
    "baseline-shift",
    "writing-mode",
    "glyph-orientation-vertical",
    "letter-spacing",
    "word-spacing",
    "line-height",
    "inline-size",
    "shape-inside",
    "shape-padding"
  ]

isSkipped :: Text -> Bool
isSkipped p = p `elem` textOnly || "font-variant-" `T.isPrefixOf` p || "-" `T.isPrefixOf` p

-- | What the cascade needs: the rules of the style sheets and the markers.
data Env = Env
  { envRules :: ![((Int, Int, Int), Int, Selector, [(Text, Text)])],
    envMarkers :: !(Map Text (Element, Style)),
    envDefault :: !Style
  }

-- | The specified properties of an element, with where each came from.
specified :: Env -> Element -> [(Text, Text, Pos)]
specified env e =
  let presentation = [(atName a, T.strip (atValue a), atPos a) | a <- elAttrs e, atNs a == "", atName a `elem` handled || isSkipped (atName a)]
      classes = maybe [] T.words (attr "class" e)
      ident = attr "id" e
      matching = sortOn (\(sp, i, _, _) -> (sp, i)) [r | r@(_, _, s, _) <- envRules env, selects s (elName e) classes ident]
      fromSheet = [(p, v, elPos e) | (_, _, _, ds) <- matching, (p, v) <- ds]
      fromStyle = case [a | a <- elAttrs e, atNs a == "", atName a == "style"] of
        a : _ -> [(p, v, atPos a) | (p, v) <- fst (parseDeclarations (atValue a))]
        [] -> []
   in presentation <> fromSheet <> fromStyle

-- | The computed style of an element from its parent's.
cascade :: Env -> Style -> Element -> Style
cascade env parent e =
  let base = Map.filterWithKey (\k _ -> k `elem` inherited) parent
      set st (p, v, _)
        | v == "inherit" = maybe st (\pv -> Map.insert p pv st) (Map.lookup p parent)
        | p == "marker" = foldl (\s k -> Map.insert k v s) st ["marker-start", "marker-mid", "marker-end"]
        | otherwise = Map.insert p v st
   in foldl set base (specified env e)

-- | The problems of the properties of an element: unknown ones and values outside the subset.
propertyProblems :: Env -> Element -> [Unsupported]
propertyProblems env e =
  [ unsupportedAt p pos
  | (p, v, pos) <- specified env e,
    not (isSkipped p),
    v /= "inherit",
    p `notElem` handled || not (valueOk p v)
  ]
    <> [ unsupportedAt (cpName pr) (atPos a)
       | a <- elAttrs e,
         atNs a == "",
         atName a == "style",
         pr <- snd (parseDeclarations (atValue a))
       ]
  where
    valueOk p v = case p of
      "fill" -> isJust (paint v)
      "stroke" -> isJust (paint v)
      "color" -> isJust (color Nothing v)
      "fill-rule" -> v `elem` ["nonzero", "evenodd"]
      "stroke-width" -> isJust (lengthPx v)
      "stroke-dashoffset" -> isJust (lengthPx v)
      "stroke-linecap" -> v `elem` ["butt", "round", "square"]
      "stroke-linejoin" -> v `elem` ["miter", "round", "bevel"]
      "stroke-miterlimit" -> maybe False (>= 1) (parseNumber v)
      "stroke-dasharray" -> v == "none" || isJust (dashes v)
      "display" -> v `elem` ["none", "inline"]
      "visibility" -> v `elem` ["visible", "hidden"]
      "opacity" -> parseNumber v == Just 1
      "fill-opacity" -> parseNumber v == Just 1
      "stroke-opacity" -> parseNumber v == Just 1
      "rx" -> v == "auto" || isJust (lengthPx v)
      "ry" -> v == "auto" || isJust (lengthPx v)
      "overflow" -> v == "hidden"
      _ | p `elem` ["marker", "marker-start", "marker-mid", "marker-end"] -> v == "none" || isJust (markerRef v >>= \i -> Map.lookup i (envMarkers env))
      _ -> False

unsupportedAt :: Text -> Pos -> Unsupported
unsupportedAt n (Pos l c) = Unsupported n l c False

attr :: Text -> Element -> Maybe Text
attr k e = case [atValue a | a <- elAttrs e, atNs a == "", atName a == k] of
  v : _ -> Just v
  [] -> Nothing

-- ------------------------------------------------------------------ values

paint :: Text -> Maybe (Maybe Text)
paint v
  | v `elem` ["none", "transparent"] = Just Nothing
  | v == "currentColor" = Just (Just v)
  | isJust (color Nothing v) = Just (Just v)
  | otherwise = Nothing

-- | A colour; @currentColor@ is the colour given.
color :: Maybe Color -> Text -> Maybe Color
color current v0 =
  let v = T.strip v0
   in if
        | v == "currentColor" -> current
        | Just h <- T.stripPrefix "#" v, T.length h == 3, T.all isHex h -> let [r, g, b] = map (\c -> 17 * hexDigit c) (T.unpack h) in Just (Color r g b)
        | Just h <- T.stripPrefix "#" v, T.length h == 6, T.all isHex h -> let pair i = 16 * hexDigit (T.index h i) + hexDigit (T.index h (i + 1)) in Just (Color (pair 0) (pair 2) (pair 4))
        | Just inner <- T.stripPrefix "rgb(" v >>= T.stripSuffix ")" ->
            case map T.strip (T.splitOn "," inner) of
              [r, g, b] -> Color <$> component r <*> component g <*> component b
              _ -> case T.words inner of
                [r, g, b] -> Color <$> component r <*> component g <*> component b
                _ -> Nothing
        | otherwise -> (\(r, g, b) -> Color r g b) <$> namedColor (T.toLower v)
  where
    isHex c = isDigit c || c `elem` ("abcdefABCDEF" :: String)
    hexDigit c
      | isDigit c = fromEnum c - fromEnum '0'
      | otherwise = fromEnum (toLower c) - fromEnum 'a' + 10
    component t
      | Just p <- T.stripSuffix "%" t = clamp . round . (* 255) . (/ 100) <$> parseNumber p
      | T.all isDigit t && not (T.null t) = clamp . round <$> parseNumber t
      | otherwise = Nothing
    clamp :: Integer -> Int
    clamp = fromInteger . max 0 . min 255

-- | A length in CSS px: a number, alone or with px.
lengthPx :: Text -> Maybe Rational
lengthPx v = parseNumber (fromMaybe v (T.stripSuffix "px" (T.strip v)))

-- | A length of the root: px, pt, pc, mm, cm and in.
rootLength :: Text -> Maybe Rational
rootLength v0 =
  let v = T.strip v0
      unit u k = (* k) <$> (T.stripSuffix u v >>= parseNumber)
   in listToMaybe (catMaybes [unit "pt" (4 / 3), unit "pc" 16, unit "mm" (96 / 254 * 10), unit "cm" (96 / 254 * 100), unit "in" 96, lengthPx v])

-- | A list of numbers separated by white space and commas.
numberList :: Text -> Maybe [Rational]
numberList t = traverse parseNumber (filter (not . T.null) (T.split (\c -> isSpace c || c == ',') t))

dashes :: Text -> Maybe [Rational]
dashes t =
  traverse lengthPx (filter (not . T.null) (T.split (\c -> isSpace c || c == ',') t)) >>= \ds ->
    if null ds || any (< 0) ds then Nothing else Just ds

markerRef :: Text -> Maybe Text
markerRef v = T.stripPrefix "url(#" (T.strip v) >>= T.stripSuffix ")" >>= \i -> if T.null i then Nothing else Just i

-- | The paint of an element from its computed style.
paintOf :: Style -> Paint
paintOf st =
  let get k = Map.findWithDefault (Map.findWithDefault "" k defaultStyle) k st
      current = color Nothing (get "color")
      num k = fromMaybe 0 (lengthPx (get k))
      fillC = color current =<< join' (paint (get "fill"))
      strokeC = color current =<< join' (paint (get "stroke"))
      width = num "stroke-width"
      dash = case get "stroke-dasharray" of
        "none" -> []
        d -> let ds = fromMaybe [] (dashes d) in if all (== 0) ds then [] else if odd (length ds) then ds <> ds else ds
   in Paint
        { paFill = fillC,
          paFillRule = if get "fill-rule" == "evenodd" then EvenOdd else NonZero,
          paStroke = case strokeC of
            Just c
              | width > 0 ->
                  Just
                    Stroke
                      { stColor = c,
                        stWidth = width,
                        stCap = case get "stroke-linecap" of "round" -> CapRound; "square" -> CapSquare; _ -> CapButt,
                        stJoin = case get "stroke-linejoin" of "round" -> JoinRound; "bevel" -> JoinBevel; _ -> JoinMiter,
                        stMiterLimit = fromMaybe 4 (parseNumber (get "stroke-miterlimit")),
                        stDash = dash,
                        stDashOffset = num "stroke-dashoffset"
                      }
            _ -> Nothing
        }
  where
    join' = \case
      Just (Just x) -> Just x
      _ -> Nothing

-- ------------------------------------------------------------------ the tree

styleElements :: Element -> [Element]
styleElements e =
  [c | NElement c <- elChildren e, elNs c == svgNs, elName c == "style"]
    <> concat [styleElements c | NElement c <- elChildren e, elNs c == svgNs, elName c `notElem` ["style", "text"]]

-- | The markers by id, with the style they inherit where they are.
markerTable :: Env -> Element -> Map Text (Element, Style)
markerTable env root = Map.fromList (go (cascade env defaultStyle root) root)
  where
    go st e =
      concat
        [ [(i, (c, cascade env st c)) | elName c == "marker", Just i <- [attr "id" c]] <> go (cascade env st c) c
        | NElement c <- elChildren e,
          elNs c == svgNs
        ]

-- | The attributes each element may have, apart from the core and presentation ones.
elementAttrs :: Text -> Maybe [Text]
elementAttrs = \case
  "g" -> Just ["transform"]
  "defs" -> Just []
  "style" -> Just ["type"]
  "marker" -> Just ["markerWidth", "markerHeight", "refX", "refY", "viewBox", "preserveAspectRatio", "orient", "markerUnits"]
  "rect" -> Just ["x", "y", "width", "height", "transform"]
  "circle" -> Just ["cx", "cy", "r", "transform"]
  "ellipse" -> Just ["cx", "cy", "transform"]
  "line" -> Just ["x1", "y1", "x2", "y2", "transform"]
  "polyline" -> Just ["points", "transform"]
  "polygon" -> Just ["points", "transform"]
  "path" -> Just ["d", "transform"]
  _ -> Nothing

-- | Problems of the attributes of an element: names not allowed.
attributeProblems :: [Text] -> Element -> [Unsupported]
attributeProblems allowed e =
  [ unsupportedAt (atName a) (atPos a)
  | a <- elAttrs e,
    let n = atName a,
    if atNs a == xmlNs then n /= "space" else atNs a == "" && not (ok n)
  ]
  where
    ok n = n `elem` (["id", "class", "style", "role"] <> allowed) || n `elem` handled || isSkipped n || "aria-" `T.isPrefixOf` n

-- | The children of an element, drawn, with their problems.
elementChildren :: Env -> Style -> Element -> ([Unsupported], [DrawOp])
elementChildren env st e =
  let results = [node c | NElement c <- elChildren e, elNs c == svgNs]
   in (concatMap fst results, concatMap snd results)
  where
    node = elementOps env st

-- | One element: its problems and what it draws.
elementOps :: Env -> Style -> Element -> ([Unsupported], [DrawOp])
elementOps env parent e
  | name `elem` ["title", "desc", "metadata"] = ([], [])
  | name `elem` ["text", "tspan", "textPath"] = ([Unsupported name l c True], [])
  | name == "style" = (attributeProblems ["type"] e <> sheetProblems, [])
  | otherwise = case elementAttrs name of
      Nothing -> ([unsupportedAt name (elPos e)], [])
      Just allowed ->
        let st = cascade env parent e
            probs = attributeProblems allowed e <> propertyProblems env e
            (tProbs, m) = case attr "transform" e of
              Nothing -> ([], identity)
              Just t -> maybe ([unsupportedAt "transform" (attrPos "transform")], identity) ([],) (parseTransform t)
            hidden = Map.lookup "display" st == Just "none" || attr "display" e == Just "none" || displayNone
            (childProbs, childOps) = elementChildren env st e
            (shapeProbs, shapeOps) = shape env st e
            ops
              | hidden = []
              | name == "g" = childOps
              | name `elem` ["defs", "marker"] = []
              | otherwise = shapeOps
            wrapped = if m == identity || null ops then ops else [DGroup m Nothing ops]
         in (probs <> tProbs <> shapeProbs <> childProbs, wrapped)
  where
    name = elName e
    Pos l c = elPos e
    attrPos k = case [atPos a | a <- elAttrs e, atName a == k] of
      p : _ -> p
      [] -> elPos e
    displayNone = any (\(p, v, _) -> p == "display" && v == "none") (specified env e)
    sheetProblems =
      let texts = [(t, p) | NText t p <- elChildren e]
       in case texts of
            [] -> []
            (_, Pos tl tc) : _ ->
              let css = T.concat (map fst texts)
               in [ Unsupported (cpName pr) (tl + T.count "\n" before) (if T.count "\n" before == 0 then tc + T.length before else T.length (snd (T.breakOnEnd "\n" before)) + 1) (cpText pr)
                  | pr <- snd (parseStylesheet css),
                    let before = T.take (cpOffset pr) css
                  ]

-- ------------------------------------------------------------------ shapes

num :: Element -> Text -> Rational
num e k = fromMaybe 0 (attr k e >>= lengthPx)

-- | A shape: its problems (geometry values) and its path, with markers.
shape :: Env -> Style -> Element -> ([Unsupported], [DrawOp])
shape env st e = case elName e of
  "rect" ->
    let x = num e "x"
        y = num e "y"
        w = num e "width"
        h = num e "height"
        given k = case Map.lookup k st of
          Just v | v /= "auto" -> lengthPx v
          _ -> attr k e >>= lengthPx
        (rx0, ry0) = case (given "rx", given "ry") of
          (Just a, Just b) -> (a, b)
          (Just a, Nothing) -> (a, a)
          (Nothing, Just b) -> (b, b)
          (Nothing, Nothing) -> (0, 0)
        rx = min (w / 2) (max 0 rx0)
        ry = min (h / 2) (max 0 ry0)
     in geometry ["x", "y", "width", "height"] $
          if w <= 0 || h <= 0 then [] else draw (roundedRect x y w h rx ry)
  "circle" ->
    let r = num e "r"
     in geometry ["cx", "cy", "r"] (if r <= 0 then [] else draw (ellipse (num e "cx") (num e "cy") r r))
  "ellipse" ->
    let rx = fromMaybe 0 (lookupLen "rx")
        ry = fromMaybe 0 (lookupLen "ry")
     in geometry ["cx", "cy"] (if rx <= 0 || ry <= 0 then [] else draw (ellipse (num e "cx") (num e "cy") rx ry))
  "line" -> geometry ["x1", "y1", "x2", "y2"] (drawMarked [MoveTo (num e "x1", num e "y1"), LineTo (num e "x2", num e "y2")])
  "polyline" -> poly False
  "polygon" -> poly True
  "path" -> case parsePath (fromMaybe "" (attr "d" e)) of
    Just segs -> ([], drawMarked segs)
    Nothing -> ([unsupportedAt "d" (attrPos "d")], [])
  _ -> ([], [])
  where
    p = paintOf st
    visible = Map.findWithDefault "visible" "visibility" st == "visible"
    draw segs = [DPath p segs | visible, not (null segs)]
    drawMarked segs = draw segs <> if visible then markers env st segs else []
    lookupLen k = case Map.lookup k st of
      Just v | v /= "auto" -> lengthPx v
      _ -> attr k e >>= lengthPx
    attrPos k = case [atPos a | a <- elAttrs e, atName a == k] of
      q : _ -> q
      [] -> elPos e
    geometry ks ops = ([unsupportedAt k (attrPos k) | k <- ks, Just v <- [attr k e], isNothing (lengthPx v)], ops)
    poly closed = case attr "points" e >>= numberList of
      Just ns | even (length ns), (x0 : y0 : rest) <- ns -> ([], drawMarked (MoveTo (x0, y0) : map LineTo (pairs rest) <> [ClosePath | closed]))
      Just [] -> ([], [])
      _ -> ([unsupportedAt "points" (attrPos "points")], [])
    pairs = \case
      a : b : r -> (a, b) : pairs r
      _ -> []

-- | The distance of the control points of a quarter of a circle of radius 1.
kappa :: Rational
kappa = roundTo (4 / 3 * (sqrtR 2 - 1))

ellipse :: Rational -> Rational -> Rational -> Rational -> [Segment]
ellipse cx cy rx ry =
  let kx = kappa * rx
      ky = kappa * ry
   in [ MoveTo (cx + rx, cy),
        CurveTo (cx + rx, cy + ky) (cx + kx, cy + ry) (cx, cy + ry),
        CurveTo (cx - kx, cy + ry) (cx - rx, cy + ky) (cx - rx, cy),
        CurveTo (cx - rx, cy - ky) (cx - kx, cy - ry) (cx, cy - ry),
        CurveTo (cx + kx, cy - ry) (cx + rx, cy - ky) (cx + rx, cy),
        ClosePath
      ]

roundedRect :: Rational -> Rational -> Rational -> Rational -> Rational -> Rational -> [Segment]
roundedRect x y w h rx ry
  | rx == 0 || ry == 0 = [MoveTo (x, y), LineTo (x + w, y), LineTo (x + w, y + h), LineTo (x, y + h), ClosePath]
  | otherwise =
      let kx = kappa * rx
          ky = kappa * ry
          r = x + w
          b = y + h
       in [ MoveTo (x + rx, y),
            LineTo (r - rx, y),
            CurveTo (r - rx + kx, y) (r, y + ry - ky) (r, y + ry),
            LineTo (r, b - ry),
            CurveTo (r, b - ry + ky) (r - rx + kx, b) (r - rx, b),
            LineTo (x + rx, b),
            CurveTo (x + rx - kx, b) (x, b - ry + ky) (x, b - ry),
            LineTo (x, y + ry),
            CurveTo (x, y + ry - ky) (x + rx - kx, y) (x + rx, y),
            ClosePath
          ]

-- ------------------------------------------------------------------ path data

data PTok = PCmd !Char | PNum !Rational
  deriving stock (Eq, Show)

{- | The tokens of path data; flags of arcs are read as numbers of one digit,
so that @1010@ after the angle of an arc is the two flags and 10. The
command and the count of numbers after it say where the flags are: the
fourth and fifth of each seven numbers of an arc.
-}
pathTokens :: Text -> Maybe [PTok]
pathTokens t0 = go ' ' (0 :: Int) (T.dropWhile sep t0)
  where
    sep c = isSpace c || c == ','
    go cmd n t = case T.uncons t of
      Nothing -> Just []
      Just (c, r)
        | isAlpha c && c `elem` ("MmLlHhVvCcSsQqTtAaZz" :: String) -> (PCmd c :) <$> go c 0 (T.dropWhile sep r)
        | toLower cmd == 'a' && n `mod` 7 `elem` [3, 4] && c `elem` ("01" :: String) -> (PNum (if c == '1' then 1 else 0) :) <$> go cmd (n + 1) (T.dropWhile sep r)
        | otherwise -> case numberPrefix t of
            Just (v, r') -> (PNum v :) <$> go cmd (n + 1) (T.dropWhile sep r')
            Nothing -> Nothing

-- | Path data as absolute segments; arcs as curves.
parsePath :: Text -> Maybe [Segment]
parsePath d = pathTokens d >>= \ts -> if null ts then Just [] else run ts
  where
    run ts = go ts Nothing (0, 0) (0, 0) Nothing []
    -- tokens, the command, the current point, the start of the subpath, the last control point, the segments
    go ts cmd cur start ctl acc = case ts of
      [] -> Just (reverse acc)
      PCmd c : rest
        | c `elem` ("Zz" :: String) -> go rest (Just c) start start Nothing (ClosePath : acc)
        | otherwise -> args c rest cur start ctl acc
      PNum _ : _ -> case cmd of
        Just c | c `notElem` ("Zz" :: String) -> args (if c == 'M' then 'L' else if c == 'm' then 'l' else c) ts cur start ctl acc
        _ -> Nothing
    args c ts cur@(cx, cy) start ctl acc =
      let rel = c `elem` ("mlhvcsqta" :: String)
          at (x, y) = if rel then (cx + x, cy + y) else (x, y)
          nums n = let (xs, rest) = splitAt n ts in if length xs == n && all isNum xs then Just ([v | PNum v <- xs], rest) else Nothing
          isNum = \case PNum _ -> True; _ -> False
       in case toLower c of
            'm' -> nums 2 >>= \([x, y], rest) -> let p = at (x, y) in go rest (Just c) p p Nothing (MoveTo p : acc)
            'l' -> nums 2 >>= \([x, y], rest) -> let p = at (x, y) in go rest (Just c) p start Nothing (LineTo p : acc)
            'h' -> nums 1 >>= \([x], rest) -> let p = (if rel then cx + x else x, cy) in go rest (Just c) p start Nothing (LineTo p : acc)
            'v' -> nums 1 >>= \([y], rest) -> let p = (cx, if rel then cy + y else y) in go rest (Just c) p start Nothing (LineTo p : acc)
            'c' -> nums 6 >>= \([a, b, e, f, x, y], rest) -> let c2 = at (e, f); p = at (x, y) in go rest (Just c) p start (Just (Left c2)) (CurveTo (at (a, b)) c2 p : acc)
            's' ->
              nums 4 >>= \([e, f, x, y], rest) ->
                let c1 = case ctl of Just (Left q) -> reflect q cur; _ -> cur
                    c2 = at (e, f)
                    p = at (x, y)
                 in go rest (Just c) p start (Just (Left c2)) (CurveTo c1 c2 p : acc)
            'q' -> nums 4 >>= \([a, b, x, y], rest) -> let q = at (a, b); p = at (x, y) in go rest (Just c) p start (Just (Right q)) (quad cur q p : acc)
            't' ->
              nums 2 >>= \([x, y], rest) ->
                let q = case ctl of Just (Right q0) -> reflect q0 cur; _ -> cur
                    p = at (x, y)
                 in go rest (Just c) p start (Just (Right q)) (quad cur q p : acc)
            'a' ->
              nums 7 >>= \([rx, ry, phi, fa, fs, x, y], rest) ->
                if (fa /= 0 && fa /= 1) || (fs /= 0 && fs /= 1)
                  then Nothing
                  else let p = at (x, y) in go rest (Just c) p start Nothing (reverse (arc cur rx ry phi (fa == 1) (fs == 1) p) <> acc)
            _ -> Nothing
    reflect (qx, qy) (px, py) = (2 * px - qx, 2 * py - qy)
    quad (x0, y0) (qx, qy) (x, y) = CurveTo (x0 + 2 / 3 * (qx - x0), y0 + 2 / 3 * (qy - y0)) (x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y)) (x, y)

{- | An elliptical arc as curves of 90 degrees or less (SVG 1.1 F.6), ending
exactly at its end point.
-}
arc :: Point -> Rational -> Rational -> Rational -> Bool -> Bool -> Point -> [Segment]
arc p0@(x1, y1) rx0 ry0 phi large sweep p1@(x2, y2)
  | p0 == p1 = []
  | rx0 == 0 || ry0 == 0 = [LineTo p1]
  | otherwise =
      let cphi = cosDeg phi
          sphi = sinDeg phi
          dx = (x1 - x2) / 2
          dy = (y1 - y2) / 2
          x1' = cphi * dx + sphi * dy
          y1' = negate sphi * dx + cphi * dy
          rxa = abs rx0
          rya = abs ry0
          lambda = x1' * x1' / (rxa * rxa) + y1' * y1' / (rya * rya)
          (rx, ry) = if lambda > 1 then let s = sqrtR lambda in (roundTo (rxa * s), roundTo (rya * s)) else (rxa, rya)
          num' = rx * rx * ry * ry - rx * rx * y1' * y1' - ry * ry * x1' * x1'
          den = rx * rx * y1' * y1' + ry * ry * x1' * x1'
          coef = (if large /= sweep then 1 else -1) * (if den == 0 then 0 else sqrtR (max 0 (num' / den)))
          cx' = roundTo (coef * rx * y1' / ry)
          cy' = roundTo (negate coef * ry * x1' / rx)
          cx = cphi * cx' - sphi * cy' + (x1 + x2) / 2
          cy = sphi * cx' + cphi * cy' + (y1 + y2) / 2
          theta1 = atan2Deg ((y1' - cy') / ry) ((x1' - cx') / rx)
          theta2 = atan2Deg ((negate y1' - cy') / ry) ((negate x1' - cx') / rx)
          delta0 = theta2 - theta1
          delta
            | sweep && delta0 < 0 = delta0 + 360
            | not sweep && delta0 > 0 = delta0 - 360
            | otherwise = delta0
          n = max 1 (ceiling (abs delta / 90 - 1 / 1000000)) :: Integer
          step = delta / fromInteger n
          k = roundTo (4 / 3 * tanDeg (step / 4))
          pointAt t = let (ct, st) = (cosDeg t, sinDeg t) in (cx + cphi * rx * ct - sphi * ry * st, cy + sphi * rx * ct + cphi * ry * st)
          derivAt t = let (ct, st) = (cosDeg t, sinDeg t) in (negate (cphi * rx * st) - sphi * ry * ct, negate (sphi * rx * st) + cphi * ry * ct)
          segment i =
            let ta = theta1 + step * fromInteger i
                tb = ta + step
                (ax, ay) = if i == 0 then p0 else pointAt ta
                (bx, by) = if i == n - 1 then p1 else pointAt tb
                (dax, day) = derivAt ta
                (dbx, dby) = derivAt tb
             in CurveTo (ax + k * dax, ay + k * day) (bx - k * dbx, by - k * dby) (bx, by)
       in map segment [0 .. n - 1]

-- ------------------------------------------------------------------ transforms

parseTransform :: Text -> Maybe Matrix
parseTransform t0 = go identity (T.strip t0)
  where
    go m t
      | T.null t = Just m
      | otherwise = do
          let (name, rest) = T.span isAlpha t
          inner <- T.stripPrefix "(" (T.stripStart rest)
          let (argsText, after) = T.breakOn ")" inner
          if T.null after then Nothing else Just ()
          args <- numberList argsText
          f <- case (name, args) of
            ("matrix", [a, b, c, d, e, f']) -> Just (Matrix a b c d e f')
            ("translate", [x]) -> Just (translate x 0)
            ("translate", [x, y]) -> Just (translate x y)
            ("scale", [x]) -> Just (scaleM x x)
            ("scale", [x, y]) -> Just (scaleM x y)
            ("rotate", [a]) -> Just (rotation a)
            ("rotate", [a, x, y]) -> Just (translate x y `mul` rotation a `mul` translate (negate x) (negate y))
            ("skewX", [a]) -> Just (Matrix 1 0 (tanDeg a) 1 0 0)
            ("skewY", [a]) -> Just (Matrix 1 (tanDeg a) 0 1 0 0)
            _ -> Nothing
          go (m `mul` f) (T.dropWhile (\c -> isSpace c || c == ',') (T.drop 1 after))
    rotation a = let (c, s) = (cosDeg a, sinDeg a) in Matrix c s (negate s) c 0 0

-- ------------------------------------------------------------------ the root and the viewBox

{- | The size of the root, the matrix of its viewBox and the clip of a
slice, and the problems of its attributes.
-}
rootGeometry :: Element -> Either SvgError ((Rational, Rational), Matrix, Maybe ClipRect, [Unsupported])
rootGeometry root = do
  let attrPos k = case [atPos a | a <- elAttrs root, atName a == k] of
        q : _ -> q
        [] -> elPos root
      lenProb k = [unsupportedAt k (attrPos k) | Just v <- [attr k root], isNothing (rootLength v)]
      vb =
        attr "viewBox" root >>= numberList >>= \case
          [x, y, w, h] | w > 0 && h > 0 -> Just (x, y, w, h)
          _ -> Nothing
      vbProb = [unsupportedAt "viewBox" (attrPos "viewBox") | isJust (attr "viewBox" root), isNothing vb]
      w0 = attr "width" root >>= rootLength
      h0 = attr "height" root >>= rootLength
      allowed = ["width", "height", "viewBox", "preserveAspectRatio", "version", "x", "y"]
      probs = attributeProblems allowed root <> lenProb "width" <> lenProb "height" <> vbProb
  size <- case (w0, h0, vb) of
    (Just w, Just h, _) | w > 0 && h > 0 -> Right (w, h)
    (Just w, Nothing, Just (_, _, vw, vh)) | w > 0 -> Right (w, w * vh / vw)
    (Nothing, Just h, Just (_, _, vw, vh)) | h > 0 -> Right (h * vw / vh, h)
    (Nothing, Nothing, Just (_, _, vw, vh)) -> Right (vw, vh)
    _ -> if null probs then Left (SvgMalformed "SVG の大きさがありません") else Right (1, 1)
  let (m, clip) = case vb of
        Nothing -> (identity, Nothing)
        Just box -> viewBoxMatrix (fromMaybe "" (attr "preserveAspectRatio" root)) box size
  Right (size, m, clip, probs)

-- | The matrix of a viewBox into a viewport of a size, by preserveAspectRatio, and the clip of slice.
viewBoxMatrix :: Text -> (Rational, Rational, Rational, Rational) -> (Rational, Rational) -> (Matrix, Maybe ClipRect)
viewBoxMatrix par (vx, vy, vw, vh) (w, h) =
  let ws = T.words par
      align = case ws of
        a : _ -> a
        [] -> "xMidYMid"
      slice = "slice" `elem` ws
      sx = w / vw
      sy = h / vh
   in if align == "none"
        then (scaleM sx sy `mul` translate (negate vx) (negate vy), Nothing)
        else
          let s = if slice then max sx sy else min sx sy
              offset' frac total used = case frac of
                "Min" -> 0
                "Max" -> total - used
                _ -> (total - used) / 2
              xa = T.take 3 (T.drop 1 align)
              ya = T.take 3 (T.drop 5 align)
              tx = offset' xa w (vw * s)
              ty = offset' ya h (vh * s)
           in (translate tx ty `mul` scaleM s s `mul` translate (negate vx) (negate vy), if slice then Just (ClipRect 0 0 w h) else Nothing)

-- ------------------------------------------------------------------ markers

-- | The vertices of a path with the direction in and the direction out.
vertices :: [Segment] -> [(Point, Maybe Point, Maybe Point)]
vertices = go (0, 0) (0, 0) []
  where
    go cur start acc = \case
      [] -> finish acc
      MoveTo p : rest -> go p p ((p, Nothing, Nothing) : acc) rest
      LineTo p : rest -> go p start ((p, Just (sub p cur), Nothing) : setOut (sub p cur) acc) rest
      CurveTo c1 c2 p : rest ->
        let din = firstNonZero [sub p c2, sub p c1, sub p cur]
            dout = firstNonZero [sub c1 cur, sub c2 cur, sub p cur]
         in go p start ((p, Just din, Nothing) : setOut dout acc) rest
      ClosePath : rest -> go start start ((start, Just (sub start cur), Nothing) : setOut (sub start cur) acc) rest
    setOut d = \case
      (p, i, Nothing) : r -> (p, i, Just d) : r
      other -> other
    finish = reverse
    sub (a, b) (c, d) = (a - c, b - d)
    firstNonZero ds = case filter (/= (0, 0)) ds of
      d : _ -> d
      [] -> (0, 0)

unit :: Point -> Point
unit v@(x, y) = let n = norm v in if n == 0 then (0, 0) else (roundTo (x / n), roundTo (y / n))

-- | The markers of a path (SVG 1.1 11.6): start, mid and end.
markers :: Env -> Style -> [Segment] -> [DrawOp]
markers env st segs =
  let vs = vertices segs
      lastI = length vs - 1
      which i
        | i == 0 = "marker-start"
        | i == lastI = "marker-end"
        | otherwise = "marker-mid"
      strokeWidth = fromMaybe 1 (Map.lookup "stroke-width" st >>= lengthPx)
   in concat
        [ placeMarker m mst strokeWidth i p din dout
        | (i, (p, din, dout)) <- zip [0 :: Int ..] vs,
          Just ref <- [Map.lookup (which i) st >>= markerRef],
          Just (m, mst) <- [Map.lookup ref (envMarkers env)]
        ]
  where
    placeMarker m mst sw i p din dout =
      let orient = fromMaybe "0" (attr "orient" m)
          dirIn = unit <$> din
          dirOut = unit <$> dout
          tangent = case (dirIn, dirOut) of
            (Just a, Just b) -> let s = unit (bimap (fst a +) (snd a +) b) in if s == (0, 0) then b else s
            (Just a, Nothing) -> a
            (Nothing, Just b) -> b
            _ -> (1, 0)
          (dx, dy) = case orient of
            "auto" -> tangent
            "auto-start-reverse" -> if i == 0 then bimap negate negate tangent else tangent
            o -> let a = fromMaybe 0 (parseNumber (fromMaybe o (T.stripSuffix "deg" o))) in (cosDeg a, sinDeg a)
          rot = if (dx, dy) == (0, 0) then identity else Matrix dx dy (negate dy) dx 0 0
          len k d = fromMaybe d (attr k m >>= lengthPx)
          mw = len "markerWidth" 3
          mh = len "markerHeight" 3
          s = if attr "markerUnits" m == Just "userSpaceOnUse" then 1 else sw
          vb = case attr "viewBox" m >>= numberList of
            Just [x, y, w, h] | w > 0 && h > 0 -> fst (viewBoxMatrix (fromMaybe "" (attr "preserveAspectRatio" m)) (x, y, w, h) (mw, mh))
            _ -> identity
          (rx, ry) = apply vb (len "refX" 0, len "refY" 0)
          outer = uncurry translate p `mul` rot `mul` scaleM s s `mul` translate (negate rx) (negate ry)
          (_, inner) = elementChildren env mst m
       in [DGroup outer (Just (ClipRect 0 0 mw mh)) [DGroup vb Nothing inner] | not (null inner)]
