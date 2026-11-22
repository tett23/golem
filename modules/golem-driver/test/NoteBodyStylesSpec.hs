-- | The paragraph styles of the bodies of notes and of the title of their list (docs/adr/0366).
module NoteBodyStylesSpec (noteBodyStylesTests) where

import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as BC
import Data.List (nub, sort)
import Data.Text qualified as T
import Support
import Test.Tasty
import Test.Tasty.HUnit

-- | Where the PDF sets the notes.
data Placement = PageFoot | ChapterEnd
  deriving stock (Eq, Show)

-- | The keys of [notes] of a book: placement, body-style and heading-style.
data NoteKeys = NoteKeys {nkPlacement :: Placement, nkBody :: Maybe T.Text, nkHeading :: Maybe T.Text}
  deriving stock (Eq, Show)

{- | A style with a sidenote column in 7pt, the paragraph styles small (8pt)
and mid (9pt), and [notes] of the keys.
-}
styleOf :: NoteKeys -> BS.ByteString
styleOf k =
  horizontalStyle
    <> "\n[paragraph-styles.small]\nsize = \"8pt\"\n\n[paragraph-styles.mid]\nsize = \"9pt\"\n\n[paragraph-styles.sidenote]\nsize = \"7pt\"\n"
    <> "\n[notes]\nplacement = "
    <> (if nkPlacement k == ChapterEnd then "\"chapter-end\"" else "\"page-foot\"")
    <> "\n"
    <> BS.concat ["body-style = \"" <> BC.pack (T.unpack n) <> "\"\n" | Just n <- [nkBody k]]
    <> BS.concat ["heading-style = \"" <> BC.pack (T.unpack n) <> "\"\n" | Just n <- [nkHeading k]]
    <> "\n[sidenotes]\nwidth = \"6zw\"\ngap = \"1zw\"\n"

-- | The body, a note and a sidenote: 本 in the body, 甲 in the note, 乙 in the sidenote, 注 the title of the list.
source :: T.Text
source = "本文[note: 甲。]本[sidenote: 乙]。\n"

{- | The sizes in pt of the text of each kind in the PDF of the keys: the
body, the mark in the text, the note, the sidenote and the title of the
list (none when the notes are at the foot of the page).
-}
data Sizes = Sizes {szBody :: [Rational], szMark :: [Rational], szNote :: [Rational], szSidenote :: [Rational], szTitle :: [Rational]}
  deriving stock (Eq, Show)

sizesOf :: NoteKeys -> IO Sizes
sizesOf = sizesOfStyle . styleOf

sizesOfStyle :: BS.ByteString -> IO Sizes
sizesOfStyle style = do
  content <- miniPdf fakeProvider True style source [] >>= fmap BS.concat . inflateAll
  let ds = drawnGlyphs content
      at c = sort (nub [ptToRational (dSize d) | d <- ds, dGlyph d == fromEnum c])
  pure (Sizes (at '本') (at '*') (at '甲') (at '乙') (at '注'))

-- | Every combination of the keys.
allKeys :: [NoteKeys]
allKeys = [NoteKeys p b h | p <- [PageFoot, ChapterEnd], b <- [Nothing, Just "small"], h <- [Nothing, Just "mid"]]

noteBodyStylesTests :: [TestTree]
noteBodyStylesTests =
  [ testCase "root ADR 0404 I1, I3: placement overrides style only the selected note body" $ do
      let overrides = "\n[notes.footnote]\nbody-style = \"small\"\n[notes.chapter-end]\nbody-style = \"mid\"\nheading-style = \"small\"\n"
      foot <- sizesOfStyle (styleOf (NoteKeys PageFoot Nothing Nothing) <> overrides)
      end <- sizesOfStyle (styleOf (NoteKeys ChapterEnd Nothing Nothing) <> overrides)
      (szNote foot, szNote end, szTitle end) @?= ([8], [9], [8])
      (szBody foot, szBody end, szSidenote foot, szSidenote end) @?= ([10], [10], [7], [7])
      szMark foot @?= [5, 8]
      szMark end @?= [5, 9],
    testCase "root ADR 0404 I1: footnote-only override leaves chapter-end body at the default" $ do
      let overrides = "\n[notes.footnote]\nbody-style = \"small\"\n"
      foot <- sizesOfStyle (styleOf (NoteKeys PageFoot Nothing Nothing) <> overrides)
      end <- sizesOfStyle (styleOf (NoteKeys ChapterEnd Nothing Nothing) <> overrides)
      (szNote foot, szNote end) @?= ([8], [10]),
    testCase "ADR 0366 I1: inv1_note_body_styles_property: each key changes only the text it names" $ do
      foot <- sizesOf (NoteKeys PageFoot Nothing Nothing)
      end <- sizesOf (NoteKeys ChapterEnd Nothing Nothing)
      -- without the keys: the note in the size of the grid, the title in that of headings of level 2
      szNote foot @?= [10]
      szNote end @?= [10]
      szTitle foot @?= []
      assertBool (show end) (szTitle end /= [] && szTitle end /= [8] && szTitle end /= [9])
      forM_ allKeys $ \k -> do
        s <- sizesOf k
        let base = if nkPlacement k == ChapterEnd then end else foot
        assertEqual
          (show k)
          base
            { -- the marks are checked below
              szMark = szMark s,
              szNote = maybe (szNote base) (const [8]) (nkBody k),
              szTitle = if nkPlacement k == ChapterEnd then maybe (szTitle base) (const [9]) (nkHeading k) else []
            }
          s
        -- the other channels and the mark in the text (5pt) do not take the keys; the mark of the note is in its body
        (szBody s, szMark s, szSidenote s) @?= ([10], sort (nub (5 : szNote s)), [7]),
    testCase "ADR 0366 I1: inv1_note_body_styles_case_1: body-style alone leaves the title of the list in the default" $ do
      def' <- sizesOf (NoteKeys ChapterEnd Nothing Nothing)
      s <- sizesOf (NoteKeys ChapterEnd (Just "small") Nothing)
      szNote s @?= [8]
      szTitle s @?= szTitle def'
      -- the footnotes take it too
      foot <- sizesOf (NoteKeys PageFoot (Just "small") Nothing)
      szNote foot @?= [8],
    testCase "ADR 0366 I1: inv1_note_body_styles_case_2: heading-style alone leaves the bodies of notes in the default" $ do
      s <- sizesOf (NoteKeys ChapterEnd Nothing (Just "mid"))
      (szNote s, szTitle s) @?= ([10], [9])
      foot <- sizesOf (NoteKeys PageFoot Nothing (Just "mid"))
      szNote foot @?= [10],
    testCase "ADR 0366: the mark in the text keeps its size; the mark at the start of the note is in the note body" $ do
      s <- sizesOf (NoteKeys PageFoot (Just "small") Nothing)
      szMark s @?= [5, 8]
  ]
