-- the enumerations are built in the tests that check them, and must not
-- be floated out into values that live as long as the program: those
-- would hold every input checked (docs/adr/0208)
{-# OPTIONS_GHC -fno-full-laziness -fno-cse #-}

{- | The label of a page in the mark of a citation kept with its value
(docs/adr/0277): C1 to C3 on marks after 'あ' set from none to a line's
worth of times, in lines of 8 to 14 em, horizontal and vertical; and L1
to L13 of docs/adr/0209 with C1 and C2 on every small input, a run of the
parts of 'parts' and of the marks of 'citeParts' after 'あ' and before
'い', in lines of 2 to 4 em, tier n holding the runs of n parts.

The mark is composed from the citation (an 'IR.Cite'); what it was
composed as before the ADR is the text of the mark ('citationText') set
as other text, which the composition of the citation then was.
-}
module CiteBreakEnum (citeBreakTests) where

import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.Citation (citationPieces, citationText)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.TestSupport.Enum
import LineBreakEnum (Setting (..), advance, composeEnv, normalSettings, paramsOf, parts, placings)
import LineBreakInvariants (Breach (..), Paragraph (..), breaches, bruteLimit)
import System.Environment (lookupEnv)
import Test.Tasty
import Test.Tasty.HUnit
import Text.Read (readMaybe)

-- | A citation of one key, numbered 1, at the page given, or at none.
citeOf :: Maybe IR.LocatorValue -> IR.Inline
citeOf v = IR.Cite sp [IR.CiteItem "a" (IR.Locator IR.LocatorPage <$> v) [] []]

-- | The number of the key of a citation: 1 for a, 2 for b, ….
numberOf :: Text -> Maybe Int
numberOf k = lookup k (zip ["a", "b", "c", "d"] [1, 2, 3, 4])

-- | The environment of a setting with the numbers of the keys.
envOf :: Bool -> Setting -> ComposeEnv
envOf vertical s = (composeEnv vertical s) {ceCiteNumber = \_ k -> numberOf k}

-- | The text of a citation: its mark.
markOf :: IR.Inline -> Text
markOf = \case
  IR.Cite _ is -> citationText (citationPieces [(i, numberOf (IR.citKey i)) | i <- is])
  IR.Text _ t -> t
  _ -> ""

-- | The marks with a page: one page, a range, a page of text and a value with a space.
locatedMarks :: [IR.Inline]
locatedMarks = map (citeOf . Just) [IR.LocNumber 5, IR.LocRange 5 7, IR.LocText "xii", IR.LocText "5 f."]

-- | The labels of a page.
isLabel :: Text -> Bool
isLabel t = t `elem` ["p.", "pp."]

-- | The characters of a box, nothing for a box of none.
charBox :: Item -> Maybe BoxContent
charBox = \case
  Box _ c | not (T.null (bcText c)) -> Just c
  _ -> Nothing

-- | What the line breaking reads of an item.
type Key = (Int, Sp, Sp, Sp, Text, Int, Int)

keyOf :: Item -> Key
keyOf = \case
  Box w c -> (0, w, 0, 0, bcText c, 0, 0)
  Glue w y z _ _ -> (1, w, y, z, "", 0, 0)
  Penalty w p h -> (2, w, 0, 0, "", p, hyphenKind h)
  where
    hyphenKind = \case
      NoHyphen -> 0
      PatternHyphen _ -> 1
      ExplicitHyphen -> 2
      WrapMark _ -> 3
      SoftHyphen _ -> 4

{- | C1 on the items: after each box of a label, a penalty of 10000 and a
glue, then a box; no other break between them.
-}
c1Items :: [Item] -> [Violation]
c1Items its =
  [ Violation "C1" ("after the label " <> show (bcText c) <> " come " <> show (map keyOf (take 3 rest)))
  | (Box _ c : rest) <- tailsOf its,
    isLabel (bcText c),
    not (held rest)
  ]
  where
    held = \case
      Penalty _ p NoHyphen : Glue _ y _ _ _ : Box {} : _ -> p >= infPenalty && y < filStretch
      _ -> False

-- | C1 on the lines: no line but the last ends with a label.
c1Lines :: [Line] -> [Violation]
c1Lines ls =
  [ Violation "C1" ("line " <> show (k + 1) <> " ends with the label " <> show (bcText c))
  | (k, l) <- zip [0 :: Int ..] (drop 1 (reverse ls)),
    Just c <- [lastChar l],
    isLabel (bcText c)
  ]
  where
    lastChar l = case reverse (mapMaybe charBox (lineItems l)) of
      c : _ -> Just c
      [] -> Nothing

{- | C2: the items are those of the text of the marks set as other text
(the composition before the ADR) with one penalty of 10000 put before the
glue after each label, and nothing else: the widths, the stretch and the
shrink as they were. Where the composition before already put one there
(a prohibition across the space, golem-layout ADR 0028), none is added.
-}
c2Items :: [Item] -> [Item] -> [Violation]
c2Items its before
  | map keyOf its /= map keyOf want = [Violation "C2" ("the items are " <> show (map keyOf its) <> ", not " <> show (map keyOf want))]
  | otherwise = []
  where
    want = held before
    held = \case
      b@(Box _ c) : rest@(Glue {} : _) | isLabel (bcText c) -> b : Penalty 0 infPenalty NoHyphen : held rest
      x : rest -> x : held rest
      [] -> []

tailsOf :: [a] -> [[a]]
tailsOf xs = case xs of
  [] -> []
  _ : rest -> xs : tailsOf rest

-- * the marks in lines of 8 to 14 em

-- | The inlines of a paragraph: 'あ' n times, the mark, and 'い' twice.
markParagraph :: Int -> IR.Inline -> [IR.Inline]
markParagraph n mark = [IR.Text sp (T.replicate n "あ") | n > 0] <> [mark, IR.Text sp "いい"]

-- | The same with the mark as text: the composition before the ADR.
asText :: [IR.Inline] -> [IR.Inline]
asText = map (\i -> case i of IR.Cite {} -> IR.Text sp (markOf i); _ -> i)

-- | The settings of the defaults.
plain :: Setting
plain = Setting True False False Nothing

-- | The items of a paragraph and those of it before the ADR.
itemsBoth :: Bool -> Setting -> [IR.Inline] -> ([Item], [Item])
itemsBoth vertical s is = let env = envOf vertical s in (fst (composeInlines env is), fst (composeInlines env (asText is)))

-- | Every mark of the unit tests broken in every line of 8 to 14 em after every number of 'あ'.
inLines :: [IR.Inline] -> ([Item] -> [Item] -> Breaks -> [Violation]) -> Assertion
inLines marks check =
  case [ (vertical, w, n, markOf m, vs)
       | m <- marks,
         vertical <- [False, True],
         w <- [8 .. 14 :: Int],
         n <- [0 .. w],
         let (its, before) = itemsBoth vertical plain (markParagraph n m)
             br = breakParagraph defaultParams (const (fromIntegral w * fs)) its
             vs = check its before br,
         not (null vs)
       ] of
    [] -> pure ()
    (vertical, w, n, m, vs) : _ -> assertFailure ((if vertical then "vertical, " else "horizontal, ") <> show w <> " em, " <> show n <> " あ, " <> show m <> ": " <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])

-- * every small input

-- | A part of a run: text, or a citation.
data Part = PText !Text | PCite !IR.Inline
  deriving stock (Eq, Show)

-- | The marks of the runs: those with a page, and one of two numbers.
citeParts :: [Part]
citeParts = map PCite (locatedMarks <> [IR.Cite sp [IR.citeItem "a", IR.citeItem "c"]])

-- | A paragraph: its setting, its expansion, the width of its lines in em, and its parts.
data Input = Input
  { inSetting :: !Setting,
    inExpansion :: !Bool,
    inWidth :: !Int,
    inPre :: !Int,
    inRun :: ![Part],
    inPost :: !Int
  }
  deriving stock (Eq, Show)

-- | The text of a part: a citation its mark.
partText :: Part -> Text
partText = \case
  PText t -> t
  PCite c -> markOf c

{- | The inlines of an input: 'あ' before the run, the run in its language
span, consecutive text parts one text, 'い' after it.
-}
inputInlines :: Input -> [IR.Inline]
inputInlines i =
  [IR.Text sp (T.replicate (inPre i) "あ") | inPre i > 0]
    <> maybe run (\l -> [IR.Lang sp l run]) (sLang (inSetting i))
    <> [IR.Text sp (T.replicate (inPost i) "い") | inPost i > 0]
  where
    run = go (inRun i)
    go = \case
      [] -> []
      PCite c : rest -> c : go rest
      ps -> let (ts, rest) = span isText ps in IR.Text sp (T.concat (map partText ts)) : go rest
    isText = \case
      PText _ -> True
      _ -> False

-- | The violations of an input: L1 to L13 of docs/adr/0209, C1 and C2.
violations :: Input -> [Violation]
violations i =
  let env = envOf False (inSetting i)
      is = inputInlines i
      its = fst (composeInlines env is)
      before = fst (composeInlines env (asText is))
      ps = paramsOf (inSetting i) (inExpansion i) its
      width = fromIntegral (inWidth i) * fs
      br = breakParagraph ps (const width) its
      p =
        Paragraph
          { pText = T.replicate (inPre i) "あ" <> T.concat (map partText (inRun i)) <> T.replicate (inPost i) "い",
            pCode = "",
            pSize = fs,
            pWidth = width,
            pStrict = sStrict (inSetting i),
            pItems = its,
            pParams = ps,
            pBreaks = br,
            pAdvance = advance,
            pNumberUnit = 10000
          }
   in [Violation (show (breachOf b)) (show (breachLine b) <> ": " <> breachWhy b) | b <- breaches bruteLimit p] <> c1Items its <> c1Lines (brLines br) <> c2Items its before

-- | The inputs of a run: every setting of its normal form, placing in lines of 2 to 4 em and expansion.
inputsOf :: [Part] -> [Input]
inputsOf run =
  [ Input s e w pre run post
  | s <- normalSettings (map partText run),
    (pre, post, ws) <- placings 4,
    w <- ws,
    e <- [False, True]
  ]

{- | Every input whose run has a citation, tier n holding those of the runs
of n parts: the runs without one are those of docs/adr/0209.
-}
inputT :: Tiers Input
inputT =
  let Tiers xss = listsOf (Tiers [map PText parts <> citeParts])
   in Tiers (map (concatMap inputsOf . filter (any isCite)) xss)
  where
    isCite = \case
      PCite _ -> True
      _ -> False

{- | The parts of the runs: GOLEM_ENUM_CITE_DEPTH, or 'citePrDepth' on pull
requests.
-}
depthOf :: IO Int
depthOf =
  lookupEnv "GOLEM_ENUM_CITE_DEPTH" >>= \case
    Nothing -> pure citePrDepth
    Just "" -> pure citePrDepth
    Just s -> case readMaybe s of
      Just n | n >= 0 -> pure n
      _ -> assertFailure ("GOLEM_ENUM_CITE_DEPTH is not a whole number of 0 or more: " <> show s)

-- | The parts of the runs of pull requests.
citePrDepth :: Int
citePrDepth = 2

citeBreakTests :: TestTree
citeBreakTests =
  testGroup
    "the label of a page kept with its value (docs/adr/0277)"
    [ testCase "C1: no line ends with the label of a page, in lines of 8 to 14 em, horizontal and vertical" $
        inLines locatedMarks (\its _ br -> c1Items its <> c1Lines (brLines br)),
      testCase "C1: before the ADR, the marks of the unit tests broke after the label in some of these lines"
        $ assertBool "no input broke after the label"
        $ or
          [ not (null (c1Lines (brLines (breakParagraph defaultParams (const (fromIntegral w * fs)) before))))
          | m <- locatedMarks,
            vertical <- [False, True],
            w <- [8 .. 14 :: Int],
            n <- [0 .. w],
            let (_, before) = itemsBoth vertical plain (markParagraph n m)
          ],
      testCase "C2: the items are those before the ADR with a penalty of 10000 before the glue after the label, and only that" $
        inLines locatedMarks (\its before _ -> c2Items its before),
      testCase "C3: the items of a mark without a page are those before the ADR" $
        inLines [citeOf Nothing, IR.Cite sp (map IR.citeItem ["a", "b", "c"]), IR.Cite sp (map IR.citeItem ["a", "d"])] (\its before _ -> [Violation "C3" (show (map keyOf its)) | map keyOf its /= map keyOf before]),
      testCase "C3: a mark of two items, one with a page: the break after the separator ; stays" $ do
        let mark = IR.Cite sp [IR.CiteItem "a" (Just (IR.Locator IR.LocatorPage (IR.LocNumber 5))) [] [], IR.citeItem "b"]
            (its, before) = itemsBoth False plain [mark]
        markOf mark @?= "[1, p. 5; 2]"
        c2Items its before @?= []
        length [() | Box {} : Glue {} : _ <- tailsOf its] @?= 2,
      testCase "C2: a predicate test, the items before the ADR break C2 and C1" $ do
        let (_, before) = itemsBoth False plain (markParagraph 0 (citeOf (Just (IR.LocNumber 5))))
        map violationRule (c2Items before before) @?= ["C2"]
        map violationRule (c1Items before) @?= ["C1"],
      testCase "L1 to L13 of docs/adr/0209, C1 and C2 hold for every input up to GOLEM_ENUM_CITE_DEPTH parts" $ do
        depth <- depthOf
        case checkAllPar depth inputT violations of
          Failed k i vs -> assertFailure ("the smallest input that breaks an invariant has " <> show k <> " parts: " <> show i <> "\n" <> unlines [violationRule v <> ": " <> violationDetail v | v <- vs])
          Passed _ -> pure ()
    ]
