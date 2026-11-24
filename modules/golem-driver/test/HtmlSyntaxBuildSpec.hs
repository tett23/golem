{- | The HTML target in the HTML syntax and EPUB in the XHTML syntax, over
built projects (root ADR 0432).
-}
module HtmlSyntaxBuildSpec (htmlSyntaxBuildTests) where

import Codec.Archive.Zip (findEntryByPath, fromEntry, toArchive)
import Control.Monad (forM, forM_)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.List (isPrefixOf, isSuffixOf, sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Driver
import Golem.Syntax
import Support
import System.Directory (createDirectoryIfMissing)
import System.FilePath (joinPath, splitDirectories, takeDirectory, (</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Tasty
import Test.Tasty.HUnit

-- | Two chapters: the first with a table of contents, a note, a language and a reference to the second.
sources :: [(FilePath, Text)]
sources =
  [ ("chapters/01.gm", "@toc depth=1\n\n# 一\n\n本文[note: 注。]と[lang en: word]、[ref-title two]。\n"),
    ("chapters/02.gm", "@label two\n# 二\n\n本文。\n")
  ]

-- | Builds the project to HTML and EPUB and gives the files of build/html, by their paths under it, and the EPUB.
buildSite :: IO ([(FilePath, BS.ByteString)], BL.ByteString)
buildSite = withSystemTempDirectory "golem-html-syntax" $ \tmp -> do
  let manifest = T.replace "chapters = [\"a.gm\"]" "chapters = [\"chapters/01.gm\", \"chapters/02.gm\"]" (TE.decodeUtf8 miniManifest)
  BS.writeFile (tmp </> "manifest.toml") (TE.encodeUtf8 manifest <> "[targets.html]\n[targets.epub]\n")
  BS.writeFile (tmp </> "style.toml") horizontalStyle
  createDirectoryIfMissing True (tmp </> "chapters")
  writeTexts tmp sources
  r <- build (defaultOptions tmp) {optTargets = Just [TargetHtml, TargetEpub]}
  assertEqual "no errors" [] (map diagCode (filter isError (brDiagnostics r)))
  let dir = tmp </> "build" </> "html"
  files <- forM (sort [p | p <- brWritten r, (dir <> "/") `isPrefixOf` p]) $ \p -> (drop (length dir + 1) p,) <$> BS.readFile p
  epub <- BL.fromStrict <$> BS.readFile (tmp </> "build" </> "epub" </> "book.epub")
  pure (files, epub)

pages :: [(FilePath, BS.ByteString)] -> [(FilePath, Text)]
pages files = [(p, TE.decodeUtf8 b) | (p, b) <- files, ".html" `isSuffixOf` p]

-- | A relative path from a directory, its .. taken out.
resolve :: FilePath -> FilePath -> FilePath
resolve dir rel = joinPath (reverse (foldl step [] (splitDirectories (dir </> rel))))
  where
    step (_ : up) ".." = up
    step acc "." = acc
    step acc part = part : acc

-- | The values of the href attributes of a page.
hrefs :: Text -> [Text]
hrefs page = [T.takeWhile (/= '"') piece | piece <- drop 1 (T.splitOn " href=\"" page)]

htmlSyntaxBuildTests :: TestTree
htmlSyntaxBuildTests =
  testGroup
    "the HTML target in the HTML syntax (root ADR 0432)"
    [ testCase "root ADR 0432 I1: the pages of build/html are .html in the HTML syntax, index.html among them" $ do
        (files, _) <- buildSite
        map fst (pages files) @?= ["chapters/01.html", "chapters/02.html", "index.html"]
        [p | (p, _) <- files, ".xhtml" `isSuffixOf` p] @?= []
        forM_ (pages files) $ \(p, page) -> do
          assertBool (p <> ": doctype") ("<!DOCTYPE html>\n<html lang=\"ja\">\n" `T.isPrefixOf` page)
          forM_ ["<?xml", "xmlns", "xml:lang", "epub:type", "/>"] $ \bad -> assertBool (p <> ": " <> T.unpack bad) (not (bad `T.isInfixOf` page))
        let first = fromMaybe "" (lookup "chapters/01.html" (pages files))
        forM_ ["role=\"doc-toc\"", "role=\"doc-noteref\"", "role=\"doc-footnote\"", "<span lang=\"en\">word</span>", "<meta charset=\"UTF-8\">"] $ \x ->
          assertBool (T.unpack x) (x `T.isInfixOf` first),
      testCase "root ADR 0432 I4: the links of HTML go to .html files that exist, those of EPUB to .xhtml" $ do
        (files, epub) <- buildSite
        let first = fromMaybe "" (lookup "chapters/01.html" (pages files))
        assertBool "HTML" ("href=\"../chapters/02.html#two\"" `T.isInfixOf` first)
        forM_ (pages files) $ \(p, page) ->
          forM_ [h | h <- hrefs page, ".html#" `T.isInfixOf` h] $ \h -> do
            let target = resolve (takeDirectory p) (T.unpack (T.takeWhile (/= '#') h))
            assertBool (p <> " -> " <> T.unpack h) (target `elem` map fst files)
        let entry path = maybe "" (TE.decodeUtf8 . BL.toStrict . fromEntry) (findEntryByPath path (toArchive epub))
        assertBool "EPUB" ("href=\"../chapters/02.xhtml#two\"" `T.isInfixOf` entry "OEBPS/chapters/01.xhtml")
        assertBool "EPUB in the XHTML syntax" ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" `T.isPrefixOf` entry "OEBPS/chapters/01.xhtml"),
      testCase "root ADR 0432 I5: the same project gives the same bytes of build/html twice" $ do
        (a, _) <- buildSite
        (b, _) <- buildSite
        a @?= b
    ]
