-- | The indents, space-between and line-breaks of the paragraph styles caption and sidenote (docs/adr/0367).
module CaptionSidenoteParagraphsSpec (captionSidenoteParagraphsTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.Char (isDigit)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Layout.Japanese (BoxKind (..), boxKind)
import Golem.Layout.KnuthPlass (BoxContent (..), Item (..), Line (..))
import Golem.Layout.Paginate (PageOutAt (..), Slotted (..))
import Golem.LayoutSpec (PageGeometry (..), Rect (..))
import Golem.Length (Sp (..))
import Golem.Syntax (Diagnostic (..), DiagnosticCode (..))
import Golem.Typeset (CodeCaption (..), CodeInfo (..), PartLine (..), PdfLayout (..), PlacedFigure (..), PlacedSidenote (..))
import Support
import Test.Tasty
import Test.Tasty.HUnit

{- | The indents of a paragraph style in characters of its size: indent,
first-line-indent and end-indent.
-}
data Indents = Indents {inS :: Integer, inF :: Integer, inE :: Integer}
  deriving stock (Eq, Show)

-- | The keys of the indents, in the zw of the style.
indentKeys :: Indents -> BS.ByteString
indentKeys (Indents s f e) = BC.pack (concat ["indent = \"", show s, "zw\"\nfirst-line-indent = \"", show f, "zw\"\nend-indent = \"", show e, "zw\"\n"])

{- | A page of 12 characters of 10pt, a caption of 10pt and a sidenote of
8pt with the keys, and a sidenote column of 6zw.
-}
partsStyle :: BS.ByteString -> BS.ByteString -> BS.ByteString
partsStyle captionKeys sidenoteKeys =
  horizontalStyle
    <> "\n[paragraph-styles.caption]\nsize = \"10pt\"\n"
    <> captionKeys
    <> "\n[paragraph-styles.sidenote]\nsize = \"8pt\"\n"
    <> sidenoteKeys
    <> "\n[figures]\nnumber = \"F{n}\"\n\n[code]\nnumber = \"L{n}\"\n"
    <> "\n[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\n"

-- | An SVG of 300 by 100 with an unpainted frame.
wideSvg :: [(FilePath, BS.ByteString)]
wideSvg = [("images/wide.svg", TE.encodeUtf8 "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"300\" height=\"100\"><rect width=\"300\" height=\"100\" fill=\"none\"/></svg>")]

-- | A sidenote, a figure with a caption and a code block with a caption, each of several lines.
partsSource :: T.Text
partsSource =
  "本文[sidenote: "
    <> T.replicate 30 "注"
    <> "]。\n\n@figure images/wide.svg alt=\"t\"\n  "
    <> T.replicate 30 "図"
    <> "\n\n@caption "
    <> T.replicate 30 "表"
    <> "\n```\na\n```\n"

-- | The lines of the three parts of a layout: the caption of the figure, that of the code block and the sidenote.
partsOf :: PdfLayout -> ([PartLine], [PartLine], [PartLine])
partsOf pl =
  ( concatMap pfCaption (Map.elems (plFigures pl)),
    concat [ciCaption ci | ci <- Map.elems (plCodes pl), not (null (ciCaption ci))],
    concat [psLines ps | pss <- Map.elems (plSidenotes pl), ps <- pss]
  )

{- | Invariant 1 of docs/adr/0367 on the lines of one paragraph: line k
starts at the indent and the first-line indent when k is 0, at the indent
otherwise, and its usable width is the inner width less that and the end
indent.
-}
holds :: Sp -> Sp -> Indents -> [PartLine] -> Assertion
holds zw inner (Indents s f e) ls = do
  assertBool "several lines" (length ls > 1)
  forM_ (zip [0 :: Int ..] ls) $ \(k, l) -> do
    let start = fromInteger (if k == 0 then s + f else s) * zw
    (k, ptIndent l) @?= (k, start)
    (k, lineTarget (ptLine l)) @?= (k, inner - start - fromInteger e * zw)
    ptRow l @?= k

-- | Every combination of the indents, without a negative start.
allIndents :: [Indents]
allIndents = [Indents s f e | s <- [0, 1, 2], f <- [-1, 0, 1], s + f >= 0, e <- [0, 1]]

-- | The caption of a figure with the keys of caption and the paragraphs of its body.
captionOf :: BS.ByteString -> T.Text -> IO PlacedFigure
captionOf keys body = do
  (_, pl) <- layoutOk (partsStyle keys "") ("@figure images/wide.svg alt=\"t\"\n" <> body <> "\n") wideSvg
  case Map.elems (plFigures pl) of
    [pf] -> pure pf
    other -> assertFailure ("not one figure but " <> show (length other))

captionSidenoteParagraphsTests :: [TestTree]
captionSidenoteParagraphsTests =
  [ testCase "root ADR 0482 I3: table and code captions retain sidenote bodies" $
      forM_ ["@caption 表[sidenote: 傍注本文]\n| A |\n|---|\n| B |\n", "@caption コード[sidenote: 傍注本文]\n```text\ncode\n```\n"] $ \source -> do
        (_, pl) <- layoutOk (partsStyle "" "") ("# 章\n\n" <> source) []
        assertEqual "one caption sidenote is placed" 1 (sum (map length (Map.elems (plSidenotes pl)))),
    testCase "root ADR 0482 I3: wrapped caption sidenotes follow their own callmark rows" $
      forM_ ["| A |\n|---|\n| B |\n", "```text\ncode\n```\n"] $ \block -> do
        let source = "# 章\n\n@caption 表[sidenote: 一]" <> T.replicate 45 "字" <> "[sidenote: 二]\n" <> block
        (geom, pl) <- layoutOk (partsStyle "" "") source []
        case concat (Map.elems (plSidenotes pl)) of
          [first, second] -> assertBool "the second callmark is at least three caption lines later" (psTop second - psTop first >= 3 * pgLinePitch geom)
          notes -> assertFailure ("expected two sidenotes, got " <> show (length notes)),
    testCase "root ADR 0482 I1, I3: a split code block retains its caption sidenote once" $ do
      let source = "# 章\n\n@caption コード[sidenote: 注]\n```text\n" <> T.replicate 70 "x\n" <> "```\n"
      (_, pl) <- layoutOk (partsStyle "" "") source []
      assertBool "the block spans pages" (length (plPages pl) > 1)
      assertEqual "one caption sidenote across all parts" 1 (sum (map length (Map.elems (plSidenotes pl)))),
    testCase "root ADR 0482 I1, I3: caption sidenote calls and bodies keep page-local numbers" $
      forM_ ["| A |\n|---|\n| B |\n", "```text\ncode\n```\n"] $ \block ->
        forM_ [("page", ["1", "1"], ["1"]), ("book", ["1", "2"], ["2"])] $ \(mode, bodies, calls) -> do
          let source = "# 章\n\n本文[sidenote: 一]。\n\n@page-break\n\n@caption 表[sidenote: 二]\n" <> block
              style = partsStyle "" "" <> "\n[notes]\nnumbering = \"" <> mode <> "\"\n"
              marks line = [bcText c | Box _ c <- lineItems line, boxKind c == KindNoteMark]
          (_, pl) <- layoutOk style source []
          let captions = concatMap ccLines (Map.elems (plTableCaptions pl)) <> concatMap ciCaption (Map.elems (plCodes pl))
          assertEqual "caption calls neither disappear nor multiply" calls (concatMap (marks . ptLine) captions)
          assertEqual "body numbers match calls on each page" bodies ([T.takeWhile isDigit (T.concat [bcText c | Box _ c <- lineItems (ptLine first)]) | notes <- Map.elems (plSidenotes pl), note <- notes, first <- take 1 (psLines note)]),
    testCase "root ADR 0482 I3: free placement follows the caption face top" $
      forM_ ["| A |\n|---|\n| B |\n", "```text\ncode\n```\n"] $ \block -> do
        let source = "# 章\n\n@caption 表[sidenote: 注]\n" <> block
            style = replaceIn "[page.grid]" "[page.grid]\nalignment = \"free\"" (partsStyle "" "")
        (_, pl) <- layoutOk style source []
        let starts = [slot | page <- plPages pl, (slot, SLine lid) <- poSlots page, Map.member lid (plTableCaptions pl)] <> [slot | page <- plPages pl, (slot, SCode lid _ _) <- poSlots page, Just ci <- [Map.lookup lid (plCodes pl)], lid == ciFirst ci]
        assertEqual "one caption slot" 1 (length starts)
        assertEqual "10pt face within 15pt pitch" (map (+ Sp (5 * 65536 `div` 2)) starts) (map psTop (concat (Map.elems (plSidenotes pl)))),
    testCase "root ADR 0482 I4: oversized caption sidenotes retain G07033" $
      forM_ ["| A |\n|---|\n| B |\n", "```text\ncode\n```\n"] $ \block -> do
        let source = "# 章\n\n@caption 表[sidenote: " <> T.replicate 600 "字" <> "]\n" <> block
        result <- layoutMini (partsStyle "" "") source []
        case result of
          Left diagnostics -> assertBool (show diagnostics) (any ((== DiagnosticCode "G07033") . diagCode) diagnostics)
          Right _ -> assertFailure "an oversized caption sidenote must not disappear",
    testCase "ADR 0367 I1: inv1_caption_sidenote_paragraphs_property: the usable width of each line is the inner width less its indents" $
      forM_ allIndents $ \i -> do
        (geom, pl) <- layoutOk (partsStyle (indentKeys i) (indentKeys i)) partsSource wideSvg
        let (figure, code, sidenote) = partsOf pl
            measure = rectW (pgTypeArea geom)
            column = maybe 0 (rectW . fst) (pgSidenotes geom)
        holds (10 * pt) measure i figure
        holds (10 * pt) measure i code
        holds (8 * pt) column i sidenote,
    testCase "ADR 0367 I1: inv1_caption_sidenote_paragraphs_case_1: without indents every line takes the whole width" $ do
      (geom, pl) <- layoutOk (partsStyle "" "") partsSource wideSvg
      let (figure, code, sidenote) = partsOf pl
          measure = rectW (pgTypeArea geom)
          column = maybe 0 (rectW . fst) (pgSidenotes geom)
      map (lineTarget . ptLine) figure @?= map (const measure) figure
      map (lineTarget . ptLine) code @?= map (const measure) code
      map (lineTarget . ptLine) sidenote @?= map (const column) sidenote
      map ptIndent (figure <> code <> sidenote) @?= map (const 0) (figure <> code <> sidenote),
    testCase "ADR 0367 I1: inv1_caption_sidenote_paragraphs_case_2: a first-line indent of 1zw takes a character from the first line only" $ do
      (geom, pl) <- layoutOk (partsStyle "first-line-indent = \"1zw\"\n" "first-line-indent = \"1zw\"\n") partsSource wideSvg
      let (figure, code, sidenote) = partsOf pl
          measure = rectW (pgTypeArea geom)
          column = maybe 0 (rectW . fst) (pgSidenotes geom)
          firstOnly w zw ls = map (lineTarget . ptLine) ls @?= (w - zw) : map (const w) (drop 1 ls)
      firstOnly measure (10 * pt) figure
      firstOnly measure (10 * pt) code
      firstOnly column (8 * pt) sidenote,
    testCase "ADR 0367: the paragraphs of a caption are apart by space-between, and the caption takes the rows" $ do
      plain <- captionOf "" ":::\n一行目\n\n二行目\n:::\n"
      spaced <- captionOf "space-between = 1\n" ":::\n一行目\n\n二行目\n:::\n"
      map ptRow (pfCaption plain) @?= [0, 1]
      map ptRow (pfCaption spaced) @?= [0, 2]
      (pfCaptionSpan plain, pfCaptionSpan spaced) @?= (2, 3),
    testCase "ADR 0367: a caption whose style keeps its lines is one paragraph: no space-between inside, each line indented" $ do
      kept <- captionOf "line-breaks = \"keep\"\nspace-between = 1\nfirst-line-indent = \"1zw\"\n" ":::\n一行目\n二行目\n\n三行目\n:::\n"
      [(ptRow l, ptIndent l) | l <- pfCaption kept] @?= [(0, 10 * pt), (1, 10 * pt), (3, 10 * pt)]
      pfCaptionSpan kept @?= 4
      -- joined, the newline joins the lines into one
      joined <- captionOf "space-between = 1\nfirst-line-indent = \"1zw\"\n" "  一行目\n  二行目\n"
      [(ptRow l, ptIndent l) | l <- pfCaption joined] @?= [(0, 10 * pt)],
    testCase "ADR 0367: a hard break in a caption that joins its lines does not start a paragraph" $ do
      joined <- captionOf "first-line-indent = \"1zw\"\n" "  一行目\\\n  二行目\n"
      [(ptRow l, ptIndent l) | l <- pfCaption joined] @?= [(0, 10 * pt), (1, 0)]
  ]
