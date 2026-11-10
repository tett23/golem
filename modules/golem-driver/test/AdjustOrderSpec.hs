{- | The order of the places of line adjustment through the build
(docs/adr/0278): the lines of a paragraph carry the order of its
paragraph style, the default of body or one written, and neither key
changes HTML and EPUB (A11).
-}
module AdjustOrderSpec (adjustOrderTests) where

import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as TE
import Golem.Assemble (Book)
import Golem.Driver
import Golem.Layout.KnuthPlass (AdjustOrder (..), GlueKind (..), Line (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), SetLine (..), layoutPdf)
import Support
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | A paragraph of a word space, a comma and Latin words, of more than a line.
paragraph :: Text
paragraph = "あいうえお、かきくけこ abc def さしすせそたちつてと、なにぬねの\n"

{- | The orders of the lines of the pages of a one-chapter book, with the
styles of @style-def of the chapter.
-}
ordersOf :: BS.ByteString -> Text -> IO [AdjustOrder]
ordersOf style source = withChapters style [("a.gm", source)] [] $ \tmp -> do
  (e, book) <- evaluatedOk tmp
  geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False (evStyle e))
  r <- layoutPdf (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) Map.empty (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e)) geom fakeFonts
  pl <- either (assertFailure . show) pure r
  pure [lineAdjustOrder (slLine sl) | sl <- Map.elems (plLines pl)]

-- | The evaluation of a project with no errors, and its book.
evaluatedOk :: FilePath -> IO (Evaluated, Book)
evaluatedOk tmp = do
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case (evBook e, filter isError (evDiagnostics e)) of
      (Just book, []) -> pure (e, book)
      (_, errs) -> assertFailure (show [(diagCode d, diagMessage d) | d <- errs])

-- | The default of body: the order of JIS X 4051.
defaultOrder :: AdjustOrder
defaultOrder =
  AdjustStaged
    [[WordSpaceGlue], [MiddleDotGlue], [BracketsGlue, CommaGlue], [JapaneseWesternGlue]]
    [[WordSpaceGlue], [JapaneseWesternGlue], [BetweenCharactersGlue]]

adjustOrderTests :: TestTree
adjustOrderTests =
  testGroup
    "the order of the places of line adjustment through the build (docs/adr/0278)"
    [ testCase "the lines of body take the default order" $ do
        os <- ordersOf horizontalStyle paragraph
        assertBool "lines" (not (null os))
        os @?= map (const defaultOrder) os,
      testCase "a paragraph of a style with shrink-order and stretch-order takes them; one of @style-def, the names separated by commas, a stage each" $ do
        os <- ordersOf (horizontalStyle <> "\n[paragraph-styles.even]\nshrink-order = []\nstretch-order = [[\"word-space\", \"japanese-western\"]]\n") ("@style even\n" <> paragraph)
        os @?= map (const (AdjustStaged [] [[WordSpaceGlue, JapaneseWesternGlue]])) os
        local <- ordersOf horizontalStyle ("@style-def paragraph tight shrink-order=comma,word-space\n\n@style tight\n" <> paragraph)
        local @?= map (const (AdjustStaged [[CommaGlue], [WordSpaceGlue]] (aoStretch defaultOrder))) local,
      testCase "a paragraph style of @style-def with stretch-order takes them as one of style.toml" $ do
        let toml = horizontalStyle <> "\n[paragraph-styles.even]\nstretch-order = [[\"word-space\"], [\"japanese-western\"]]\n"
        fromToml <- ordersOf toml ("@style even\n" <> paragraph)
        local <- ordersOf horizontalStyle ("@style-def paragraph even stretch-order=word-space,japanese-western\n\n@style even\n" <> paragraph)
        assertBool "lines" (not (null fromToml))
        fromToml @?= map (const (AdjustStaged (aoShrink defaultOrder) [[WordSpaceGlue], [JapaneseWesternGlue]])) fromToml
        local @?= fromToml,
      testCase "A11: HTML and EPUB are the same bytes with the keys written and without them" $ do
        let out style = withSystemTempDirectory "golem-order" $ \tmp -> do
              BS.writeFile (tmp </> "manifest.toml") (miniManifest <> "\n[targets.html]\n\n[targets.epub]\n")
              BS.writeFile (tmp </> "style.toml") style
              BS.writeFile (tmp </> "a.gm") (TE.encodeUtf8 ("# 一\n\n" <> paragraph))
              r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
              assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
              buildFiles (tmp </> "build")
        plain <- out horizontalStyle
        written <- out (horizontalStyle <> "\n[paragraph-styles.body]\nshrink-order = [\"comma\"]\nstretch-order = []\n\n[paragraph-styles.caption]\nshrink-order = []\n")
        assertBool "files" (not (Map.null plain))
        written @?= plain
    ]
