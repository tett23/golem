{- | The line adjustment and the stretch limit of paragraph styles through
the build (docs/adr/0274): the default pulls in, a paragraph style of
"balanced" sets its lines as before, a paragraph style of a stretch limit
caps the stretch of its lines, the same when @style-def defines the
paragraph style as when style.toml does, and neither key changes HTML and
EPUB (R9).
-}
module LineAdjustmentSpec (lineAdjustmentTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Layout.KnuthPlass (Line (..), placeLine)
import Golem.Project.Style (Sp)
import Golem.Syntax
import Golem.Typeset (PdfLayout (..), SetLine (..))
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

{- | Eleven characters and two commas, 13 em at their natural widths in
lines of 12: 12 em with the half em after each comma taken.
-}
squeezable :: Text
squeezable = "あいうえお、かきくけこ、さ\n"

-- | The lines of the first page of a one-chapter book.
firstPage :: BS.ByteString -> Text -> IO [Text]
firstPage style source = do
  r <- pagesMini "" style source [] Map.empty
  case r of
    Right (p : _) -> pure p
    Right [] -> assertFailure "no page"
    Left ds -> assertFailure (show ds)

{- | Latin words and a comma in lines of 12 em, so that lines before the
last stretch their glue.
-}
loose :: Text
loose = "あいうえお、かきくけこ abc def さしすせそたちつてと、なにぬねの abcdefg hij\n"

{- | The lines of a one-chapter book: their text, the stretch limit they
carry and where their items are placed.
-}
placedLines :: BS.ByteString -> Text -> IO [(Text, Maybe Rational, [Sp])]
placedLines style source = do
  (_, pl) <- layoutOk style source []
  pure [(t, lineStretchLimit (slLine sl), map snd (placeLine (slLine sl))) | (t, sl) <- zip (lineTexts pl) (Map.elems (plLines pl))]

lineAdjustmentTests :: TestTree
lineAdjustmentTests =
  testGroup
    "the line adjustment of paragraph styles through the build (docs/adr/0274)"
    [ testCase "R3: by default a paragraph that fits a line by the shrink of its glue is one line" $
        firstPage horizontalStyle squeezable >>= (@?= ["あいうえお、かきくけこ、さ"]),
      testCase "R1: body balanced sets it as before the ADR, in two lines" $
        firstPage (horizontalStyle <> "\n[paragraph-styles.body]\nline-adjustment = \"balanced\"\n") squeezable >>= (@?= ["あいうえお、かきくけこ、", "さ"]),
      testCase "R1: a paragraph of a style based on body with balanced, by @style" $
        firstPage (horizontalStyle <> "\n[paragraph-styles.even]\nline-adjustment = \"balanced\"\n") ("@style even\n" <> squeezable) >>= (@?= ["あいうえお、かきくけこ、", "さ"]),
      testCase "R1: a paragraph style of @style-def with balanced sets its lines as one of style.toml does" $ do
        firstPage horizontalStyle ("@style-def paragraph even line-adjustment=\"balanced\"\n\n@style even\n" <> squeezable) >>= (@?= ["あいうえお、かきくけこ、", "さ"])
        firstPage horizontalStyle ("@style-def paragraph body line-adjustment=balanced\n\n" <> squeezable) >>= (@?= ["あいうえお、かきくけこ、", "さ"]),
      testCase "R3: a paragraph style of @style-def with pull-in-first pulls in where body of style.toml is balanced" $ do
        let balancedBody = horizontalStyle <> "\n[paragraph-styles.body]\nline-adjustment = \"balanced\"\n"
        firstPage balancedBody ("@style-def paragraph tight line-adjustment=pull-in-first\n\n@style tight\n" <> squeezable) >>= (@?= ["あいうえお、かきくけこ、さ"])
        -- one of @style-def without the key takes balanced from body
        firstPage balancedBody ("@style-def paragraph plain\n\n@style plain\n" <> squeezable) >>= (@?= ["あいうえお、かきくけこ、", "さ"]),
      testCase "R5, R7: a stretch limit of @style-def caps the stretch of the lines as one of style.toml does, and keeps the breaks" $ do
        plain <- placedLines horizontalStyle ("@style-def paragraph even\n\n@style even\n" <> loose)
        toml <- placedLines (horizontalStyle <> "\n[paragraph-styles.even]\nstretch-limit = 0\n") ("@style even\n" <> loose)
        local <- placedLines horizontalStyle ("@style-def paragraph even stretch-limit=0\n\n@style even\n" <> loose)
        let texts = map (\(t, _, _) -> t)
            limits = map (\(_, m, _) -> m)
        assertBool "more than one line" (length plain > 1)
        limits plain @?= map (const Nothing) plain
        limits toml @?= map (const (Just 0)) toml
        assertBool "the limit moves items of a line" (toml /= plain)
        -- R7: the limit does not change the breaks
        texts toml @?= texts plain
        local @?= toml,
      testCase "R9: HTML and EPUB are the same bytes with the keys written and without them" $ do
        let out style = withSystemTempDirectory "golem-adjust" $ \tmp -> do
              BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
              BS.writeFile (tmp </> "style.toml") style
              BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 ("# 一\n\n" <> squeezable))
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              buildFiles (tmp </> "build")
        plain <- out horizontalStyle
        written <- out (horizontalStyle <> "\n[paragraph-styles.body]\nline-adjustment = \"balanced\"\nstretch-limit = 1000\n\n[paragraph-styles.caption]\nstretch-limit = 0\n")
        assertBool "files" (not (Map.null plain))
        written @?= plain,
      testCase "R9: HTML and EPUB are the same bytes with the keys written in @style-def and without them" $ do
        -- no heading, whose identifier is the offset of its source
        let out def = withSystemTempDirectory "golem-adjust" $ \tmp -> do
              BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
              BS.writeFile (tmp </> "style.toml") horizontalStyle
              BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 (def <> "\n\n@style even\n" <> squeezable))
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              buildFiles (tmp </> "build")
        plain <- out "@style-def paragraph even"
        written <- out "@style-def paragraph even line-adjustment=balanced stretch-limit=1000"
        assertBool "files" (not (Map.null plain))
        written @?= plain
    ]
