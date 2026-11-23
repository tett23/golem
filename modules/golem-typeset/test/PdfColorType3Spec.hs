{- | Type 3 glyphs declared with d0 in imported PDF figures (root ADR 0425):
their contents are collected and recoloured like the content of the figure,
while d1 glyphs keep painting the colour of the text.
-}
module PdfColorType3Spec (pdfColorType3Tests) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Maybe (fromMaybe)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Pdf qualified as P
import PdfColorShadingSpec (converted, dictOf, page, recolor, rejected)
import Test.Tasty
import Test.Tasty.HUnit

pdfColorType3Tests :: [TestTree]
pdfColorType3Tests =
  [ testCase "root ADR 0425 I11: a d0 glyph painting gray maps its content to the tone" $ do
      p <- converted (typed "BT /T3 1 Tf (a) Tj ET" [("a", "1 0 d0 .5 g 0 0 1 1 re f")] [])
      glyphs <- shownGlyphs p
      assertHas "glyph content" "0 0.5 0.5 0 k" (lookupGlyph "a" glyphs),
    testCase "root ADR 0425 I11: a d0 glyph painting red alone makes a figure of one colour" $ do
      p <- converted (typed "BT /T3 1 Tf (a) Tj ET" [("a", "1 0 d0 1 0 0 rg 0 0 1 1 re f")] [])
      glyphs <- shownGlyphs p
      assertHas "glyph content" "0 1 1 0 k" (lookupGlyph "a" glyphs),
    testCase "root ADR 0425 I11: a d0 glyph painting red beside a gray rectangle keeps the original colours" $
      recolor (typed ".5 g 0 0 1 1 re f BT /T3 1 Tf (a) Tj ET" [("a", "1 0 d0 1 0 0 rg 0 0 1 1 re f")] []) @?= Right Nothing,
    testCase "root ADR 0425 I11: a d0 glyph is collected even when no text shows it" $
      recolor (typed ".5 g 0 0 1 1 re f BT /T3 1 Tf (b) Tj ET" [("a", "1 0 d0 1 0 0 rg 0 0 1 1 re f"), ("b", "1 0 d0 0 0 1 1 re f")] []) @?= Right Nothing,
    testCase "root ADR 0425 I11: a d0 glyph without colour operators paints the inherited fill tone" $ do
      p <- converted (typed ".5 g BT /T3 1 Tf (a) Tj ET" [("a", "1 0 d0 0 0 1 1 re f")] [])
      assertHas "text fill" "0 0.5 0.5 0 k" (P.ipContent p),
    testCase "root ADR 0425 I11: the text fill of a font of only d0 glyphs is not a painted colour" $ do
      p <- converted (typed "1 0 0 rg BT /T3 1 Tf (a) Tj ET 0 g 0 0 1 1 re f" [("a", "1 0 d0 .25 g 0 0 1 1 re f")] [])
      glyphs <- shownGlyphs p
      assertHas "glyph content" "0 0.75 0.75 0 k" (lookupGlyph "a" glyphs),
    testCase "root ADR 0425 I11: a d1 glyph beside a d0 glyph still paints the text fill" $
      recolor (typed "1 0 0 rg BT /T3 1 Tf (ab) Tj ET" [("a", "1 0 d0 .25 g 0 0 1 1 re f"), ("b", "1 0 0 0 1 1 d1 0 0 1 1 re f")] []) @?= Right Nothing,
    testCase "root ADR 0425 I11: a d1 glyph keeps its content while the d0 glyph is mapped" $ do
      p <- converted (typed ".5 g BT /T3 1 Tf (ab) Tj ET" [("a", "1 0 d0 .25 g 0 0 1 1 re f"), ("b", "1 0 0 0 1 1 d1 0 0 1 1 re f")] [])
      glyphs <- shownGlyphs p
      assertHas "d0 glyph" "0 0.75 0.75 0 k" (lookupGlyph "a" glyphs)
      lookupGlyph "b" glyphs @?= "1 0 0 0 1 1 d1 0 0 1 1 re f",
    testCase "root ADR 0425 I11: a d0 glyph using the font's own ExtGState with BM Multiply is G08113" $
      rejected (typed "BT /T3 1 Tf (a) Tj ET" [("a", "1 0 d0 /M gs .5 g 0 0 1 1 re f")] [("ExtGState", P.ODict [("M", P.ODict [("BM", P.OName "Multiply")])])]),
    testCase "root ADR 0425 I11: a d0 glyph painting a gray Form of the font's resources maps the Form" $ do
      let original = typed "BT /T3 1 Tf (a) Tj ET" [("a", "1 0 d0 /F Do")] [("XObject", P.ODict [("F", P.ORef 30)])]
      p <- converted (original {P.ipObjects = P.ipObjects original <> [(30, P.OStream [("Subtype", P.OName "Form"), ("BBox", P.OArr (map P.OInt [0, 0, 1, 1]))] ".5 g 0 0 1 1 re f")]})
      glyphs <- shownGlyphs p
      let glyph = lookupGlyph "a" glyphs
      assertBool ("the glyph paints a converted Form: " <> show glyph) ("GolemFigureColor" `BS.isInfixOf` glyph)
      font <- shownFont p
      let forms = [body | Just (P.ODict resources) <- [lookup "Resources" font], Just table <- [lookup "XObject" resources], (_, P.ORef key) <- dictOf p table, key < 0, Just (P.OStream _ body) <- [lookup key (P.ipObjects p)]]
      assertBool ("converted Form: " <> show forms) (any ("0 0.5 0.5 0 k" `BS.isInfixOf`) forms),
    testCase "root ADR 0425 I11: a font selected in the page and shown in a Form maps its d0 glyph" $ do
      let original = typed "BT /T3 1 Tf /F Do ET" [("a", "1 0 d0 .5 g 0 0 1 1 re f")] []
          withForm = case P.ipResources original of
            P.ODict entries -> P.ODict (entries <> [("XObject", P.ODict [("F", P.ORef 30)])])
            other -> other
      p <- converted (original {P.ipResources = withForm, P.ipObjects = P.ipObjects original <> [(30, P.OStream [("Subtype", P.OName "Form"), ("BBox", P.OArr (map P.OInt [0, 0, 1, 1]))] "(a) Tj")]})
      glyphs <- shownGlyphs p
      assertHas "glyph content" "0 0.5 0.5 0 k" (lookupGlyph "a" glyphs)
  ]

{- | A page showing text in the Type 3 font T3 (object 20), whose glyphs are
objects 21 onwards, with the font's own resources when given.
-}
typed :: ByteString -> [(T.Text, ByteString)] -> [(T.Text, P.ObjOf P.ObjNum)] -> P.ImportedPage
typed content glyphs own =
  let procs = zip [21 ..] glyphs
      font =
        P.ODict
          ( [ ("Type", P.OName "Font"),
              ("Subtype", P.OName "Type3"),
              ("FontBBox", P.OArr (map P.OInt [0, 0, 1, 1])),
              ("FontMatrix", P.OArr [P.OReal "0.001", P.OInt 0, P.OInt 0, P.OReal "0.001", P.OInt 0, P.OInt 0]),
              ("CharProcs", P.ODict [(name, P.ORef key) | (key, (name, _)) <- procs]),
              ("Encoding", P.ODict [("Type", P.OName "Encoding"), ("Differences", P.OArr (P.OInt 97 : [P.OName name | (_, (name, _)) <- procs]))]),
              ("FirstChar", P.OInt 97),
              ("LastChar", P.OInt (96 + fromIntegral (length procs))),
              ("Widths", P.OArr [P.OInt 1000 | _ <- procs])
            ]
              <> [("Resources", P.ODict own) | not (null own)]
          )
   in (page content)
        { P.ipResources = P.ODict [("Font", P.ODict [("T3", P.ORef 20)])],
          P.ipObjects = (20, font) : [(key, P.OStream [] body) | (key, (_, body)) <- procs]
        }

-- | The dictionary of the font that the last Tf of the page content selects.
shownFont :: P.ImportedPage -> IO [(T.Text, P.ObjOf P.ObjNum)]
shownFont p = case (P.contentOperations (P.ipContent p), P.ipResources p) of
  (Just operations, P.ODict resources) | (name : _) <- reverse [TE.decodeLatin1 (BS.drop 1 n) | ("Tf", [n, _]) <- operations] -> do
    let fonts = maybe [] (dictOf p) (lookup "Font" resources)
    case lookup name fonts of
      Just value -> pure (dictOf p value)
      Nothing -> assertFailure ("no font " <> show name <> " in " <> show fonts) >> pure []
  other -> assertFailure ("no Tf: " <> show other) >> pure []

-- | The glyph contents of the font shown, by glyph name.
shownGlyphs :: P.ImportedPage -> IO [(T.Text, ByteString)]
shownGlyphs p = do
  font <- shownFont p
  pure [(name, body) | Just procs <- [lookup "CharProcs" font], (name, P.ORef key) <- dictOf p procs, Just (P.OStream _ body) <- [lookup key (P.ipObjects p)]]

lookupGlyph :: T.Text -> [(T.Text, ByteString)] -> ByteString
lookupGlyph name = fromMaybe BS.empty . lookup name

assertHas :: String -> ByteString -> ByteString -> Assertion
assertHas label expected actual = assertBool (label <> ": expected " <> show expected <> " in " <> show actual) (expected `BS.isInfixOf` actual)
