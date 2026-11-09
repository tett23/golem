{- | The compositions of the units that did not change, reused between the
rounds of the fixpoint of page references (docs/adr ADR 0251): the PDF and
its diagnostics are those of composing every unit again (I1); a unit that
refers to a page (I2) or that changed (I3) is composed again; the first
round composes every unit (I4); a round sees only the round before it (I5).
-}
module ReuseSpec (reuseTests) where

import Data.ByteString qualified as BS
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Driver
import Golem.Driver.Version (golemVersion)
import Golem.Layout.Paginate (ColumnSet (..), PageOut (..))
import Golem.LayoutSpec (pageGeometry)
import Golem.Project (Manifest (..), Project (..), ProjectFailure (..))
import Golem.Project.Files (diskFiles)
import Golem.Syntax
import Golem.Typeset (PdfInput (..), PdfLayout (..), fixpoint, layoutPdfWith, renderPdfAllReusing)
import Support
import System.IO.Temp (withSystemTempDirectory)
import System.IO.Unsafe (unsafePerformIO)
import Test.Tasty
import Test.Tasty.HUnit

-- | The PDF input of a one-chapter project with the extra files, as the driver passes it, and its page geometry.
withInput :: BS.ByteString -> Text -> [(FilePath, BS.ByteString)] -> (PdfInput -> IO a) -> IO a
withInput style source files k = withSystemTempDirectory "golem-reuse" $ \tmp -> do
  writeProject tmp miniManifest style source files
  ev <- evaluateProject Dev tmp
  case ev of
    Left f -> assertFailure (show (pfDiagnostics f))
    Right e -> case evBook e of
      _ | errs@(_ : _) <- filter isError (evDiagnostics e) -> assertFailure (show errs)
      Just book -> do
        let (vars, _) = runningVars e
        k (PdfInput (diskFiles tmp) (evProject e) (evStyle e) book False [] Map.empty Nothing (localStylesOf e) (chapterMasters (evProject e)) (evStyleFile e) vars (projectVarTexts (manifestVars (projectManifest (evProject e)))) (evStyleText e))
      Nothing -> assertFailure "no book"

-- | The PDF and its notices, or the errors, composed with the compositions of the round before reused or not.
renderedWith :: Bool -> PdfInput -> IO (Either [(DiagnosticCode, SrcSpan, Text)] (BS.ByteString, [(DiagnosticCode, SrcSpan, Text)]))
renderedWith reuse inp = do
  r <- renderPdfAllReusing reuse golemVersion fakeProvider inp
  let ds = map (\d -> (diagCode d, diagSpan d, diagMessage d))
  pure (either (Left . ds) (\(bytes, notices, _, _, _) -> Right (bytes, ds notices)) r)

-- | I1: the PDF and the diagnostics with the reuse are those without it.
sameWithReuse :: BS.ByteString -> Text -> [(FilePath, BS.ByteString)] -> Assertion
sameWithReuse style source files = withInput style source files $ \inp -> do
  on <- renderedWith True inp
  off <- renderedWith False inp
  assertBool ("no PDF: " <> show (either id snd off)) (either (const False) (not . BS.null . fst) off)
  assertBool "the PDF or the diagnostics differ with the reuse" (on == off)

{- | The fake fonts counting the texts they measure and shape, by text:
the words, the characters and the runs the composition asks for.
-}
measuringFonts :: IORef (Map.Map Text Int) -> LoadedFonts
measuringFonts ref =
  fakeFonts
    { lfAdvance = \s c -> counted ref (T.singleton c) (lfAdvance fakeFonts s c),
      lfWordAdvance = \s t -> counted ref t (lfWordAdvance fakeFonts s t),
      lfShape = \s t -> counted ref t (lfShape fakeFonts s t)
    }

{-# NOINLINE counted #-}
counted :: IORef (Map.Map Text Int) -> Text -> a -> a
counted ref t x = unsafePerformIO (atomicModifyIORef' ref (\m -> (Map.insertWith (+) t 1 m, ()))) `seq` x

-- | How many times the texts that hold a word were measured or shaped.
timesOf :: Map.Map Text Int -> Text -> Int
timesOf m w = sum [n | (t, n) <- Map.toList m, w `T.isInfixOf` t]

-- | The counts of the measuring and shaping of a layout, with the reuse or without it.
countsWith :: Bool -> PdfInput -> IO (Map.Map Text Int)
countsWith reuse inp = do
  ref <- newIORef Map.empty
  geom <- either (assertFailure . show) pure (pageGeometry (FileId 0) False (piStyle inp))
  r <- layoutPdfWith reuse inp geom (measuringFonts ref)
  case r of
    Left ds -> assertFailure (show ds)
    Right pl -> length (plPages pl) `seq` readIORef ref

-- | Pages with the labels given, page n holding the nth list.
pagesWith :: [[Text]] -> [PageOut]
pagesWith ls = [PageOut n 0 False [] [] l [] [] (ColumnSet 1 0 0 0) [] 10 [] | (n, l) <- zip [1 ..] ls]

-- | 100 paragraphs of the word zq, enough for several pages of horizontalStyle; the words of two letters are not hyphenated.
bodyParagraphs :: Text
bodyParagraphs = T.concat ["zq " <> T.pack (show n) <> "\n\n" | n <- [1 .. 100 :: Int]]

reuseTests :: [TestTree]
reuseTests =
  [ testCase "I2 I3 I4: the second round composes only the index and the paragraph that refers to a page" $
      withInput horizontalStyle (bodyParagraphs <> "mk[index reading=いんでっくす: ix]\n\nrx [ref-page last]\n\n@label last\nlw\n\n@index\n") [] $ \inp -> do
        on <- countsWith True inp
        off <- countsWith False inp
        -- the paragraphs of the body, and the one of the index mark: once with the reuse, once a round without it
        assertBool "zq is measured" (timesOf on "zq" > 0)
        timesOf off "zq" @?= 2 * timesOf on "zq"
        timesOf off "mk" @?= 2 * timesOf on "mk"
        timesOf off "lw" @?= 2 * timesOf on "lw"
        -- I2: the paragraph of [ref-page] in every round
        assertBool "rx is measured" (timesOf on "rx" > 0)
        timesOf on "rx" @?= timesOf off "rx"
        -- I3: the line of the index, whose page changed from the 1 of the first round
        assertBool "ix is measured" (timesOf on "ix" > 0)
        timesOf on "ix" @?= timesOf off "ix",
    testCase "I3: the paragraphs beside a wrapped figure that did not change are reused; beside one that refers to a page, composed again" $ do
      img <- tinyImage
      withInput horizontal24 (wrapped "end" "4zw" <> T.replicate 20 "bw " <> "\n\n" <> bodyParagraphs <> "@label last\nlast[index reading=a: ix]\n\n@index\n") img $ \inp -> do
        on <- countsWith True inp
        off <- countsWith False inp
        assertBool "bw is measured" (timesOf on "bw" > 0)
        timesOf off "bw" @?= 2 * timesOf on "bw"
      withInput horizontal24 (wrapped "end" "4zw" <> T.replicate 20 "bw " <> "[ref-page last]\n\n" <> bodyParagraphs <> "@label last\nlast\n") img $ \inp -> do
        on <- countsWith True inp
        off <- countsWith False inp
        assertBool "bw is measured" (timesOf on "bw" > 0)
        timesOf on "bw" @?= timesOf off "bw",
    testCase "I4: a book without references is laid out in one round, the same with and without the reuse" $
      withInput horizontalStyle bodyParagraphs [] $ \inp -> do
        on <- countsWith True inp
        off <- countsWith False inp
        timesOf on "zq" @?= timesOf off "zq",
    testCase "I5: each round is given the value of the round just before it" $ do
      seen <- newIORef []
      calls <- newIORef (0 :: Int)
      let flipping prev _ = do
            modifyIORef' seen (prev :)
            modifyIORef' calls (+ 1)
            n <- readIORef calls
            pure (Right (n, pagesWith (if odd n then [["a"], []] else [[], ["a"]])))
      _ <- fixpoint (const (mkSpan (FileId 0) 0 0)) (const "") flipping
      readIORef seen >>= (@?= [Nothing, Just 1, Just 2, Just 3, Just 4]) . reverse,
    testGroup
      "I1: the PDF and the diagnostics are those of composing every unit again"
      [ testCase name (files >>= sameWithReuse style source)
      | (name, style, source, files) <-
          [ ("no label and no index mark: one round", horizontalStyle, bodyParagraphs, pure []),
            ("a label only", horizontalStyle, "@label a\nfirst\n\n" <> bodyParagraphs, pure []),
            ("an index mark only", horizontalStyle, bodyParagraphs <> "mark[index reading=いんでっくす: ix]\n\n@index\n", pure []),
            ("a label and an index mark", horizontalStyle, "@label a\nfirst[index reading=a: aterm]\n\n" <> bodyParagraphs <> "[index reading=b: bterm]last\n\n@index\n", pure []),
            ("ref-page in a paragraph of the body", horizontalStyle, "see [ref-page last]\n\n" <> bodyParagraphs <> "@label last\nlast\n", pure []),
            ("ref-page in a footnote", horizontalStyle, "note[note: see [ref-page last]]\n\n" <> bodyParagraphs <> "@label last\nlast\n", pure []),
            ("ref-page in a table cell", horizontalStyle, "| a | b |\n| --- | --- |\n| [ref-page last] | x |\n\n" <> bodyParagraphs <> "@label last\nlast\n", pure []),
            ("ref-page in the caption of a figure", horizontal24, "@figure images/tiny.jpg alt=\"t\"\n  see [ref-page last]\n\n" <> bodyParagraphs <> "@label last\nlast\n", tinyImage),
            ("a wrapped figure, the paragraphs beside it unchanged", horizontal24, wrapped "end" "4zw" <> longPara 10 <> longPara 60 <> bodyParagraphs <> "@label last\nlast[index reading=a: aterm]\n\n@index\n", tinyImage),
            ("a wrapped figure, a paragraph beside it refers to a page", horizontal24, wrapped "end" "4zw" <> "see [ref-page last]" <> longPara 10 <> longPara 60 <> "@label last\nlast\n", tinyImage)
          ]
      ]
  ]
