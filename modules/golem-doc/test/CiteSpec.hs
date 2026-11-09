{- | The values of a citation and the mark of the default style
(docs/adr/0266): I1 to I4 and I8 by every set of numbers from 1 to 6 in
every order, I7 by the CBOR round trip and the checks; C4 of docs/adr/0277
by the same sets with and without the locators.
-}
module CiteSpec (tests) where

import Codec.CBOR.Term (Term (..), encodeTerm)
import Codec.CBOR.Write (toStrictByteString)
import Control.Monad (forM_)
import Data.ByteString qualified as BS
import Data.List (intercalate, permutations, sort, subsequences)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Doc.Cbor
import Golem.Doc.Citation
import Golem.Doc.IR
import Golem.Doc.Validate
import Golem.Syntax.Span
import Golem.TestSupport.ExternalTool (needsTool)
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Tasty
import Test.Tasty.HUnit

sp :: SrcSpan
sp = SrcSpan (FileId 0) 0 1

docOf :: [Inline] -> Document
docOf is = Document (FileId 0) [Block sp Nothing Nothing (Paragraph Nothing is)]

size :: FileId -> Maybe Int
size (FileId 0) = Just 10
size _ = Nothing

-- | The key of a number: k1 for 1.
keyOf :: Int -> Text
keyOf n = "k" <> T.pack (show n)

-- | The items of the numbers, in the order given.
itemsOf :: [Int] -> [(CiteItem (), Maybe Int)]
itemsOf ns = [(citeItem (keyOf n), Just n) | n <- ns]

page :: LocatorValue -> Maybe Locator
page = Just . Locator LocatorPage

-- | Every nonempty set of numbers from 1 to 6 in every order.
orders :: [[Int]]
orders = concatMap permutations (filter (not . null) (subsequences [1 .. 6]))

-- | The numbers a mark shows, a range as the numbers it covers.
covered :: [CitePiece] -> [Int]
covered = go
  where
    go = \case
      CiteNumber _ a : CiteText "\x2013" : CiteNumber _ b : rest -> [a .. b] <> go rest
      CiteNumber _ n : rest -> n : go rest
      _ : rest -> go rest
      [] -> []

-- | The parts of a mark between its separators: a number, or a range.
parts :: [CitePiece] -> [[Int]]
parts = go
  where
    go = \case
      CiteNumber _ a : CiteText "\x2013" : CiteNumber _ b : rest -> [a, b] : go rest
      CiteNumber _ n : rest -> [n] : go rest
      _ : rest -> go rest
      [] -> []

{- | The text of a mark as the default style wrote it before docs/adr/0277,
from the items alone: the oracle of C4.
-}
textBefore :: [(CiteItem r, Maybe Int)] -> Text
textBefore items
  | any (isJust . citLocator . fst) items = "[" <> T.intercalate "; " [label i n <> maybe "" ((", " <>) . locator) (citLocator i) | (i, n) <- items] <> "]"
  | otherwise = "[" <> T.pack (intercalate ", " (map run (runsOf (sort [n | (_, Just n) <- items])) <> [T.unpack (citKey i) | (i, Nothing) <- items])) <> "]"
  where
    label i = maybe (citKey i) (T.pack . show)
    locator (Locator l v) = case (l, v) of
      (LocatorPage, LocRange a b) | a /= b -> "pp. " <> T.pack (show a) <> "\x2013" <> T.pack (show b)
      (LocatorPage, LocRange a _) -> "p. " <> T.pack (show a)
      (LocatorPage, LocNumber a) -> "p. " <> T.pack (show a)
      (LocatorPage, LocText t) -> "p. " <> t
      _ -> error "a locator not of a page"
    runsOf = foldr step []
    step n = \case
      (r@(m : _) : rest) | m == n + 1 -> (n : r) : rest
      rs -> [n] : rs
    run = \case
      r@(a : _ : _ : _) -> show a <> "\x2013" <> show (last r)
      r -> intercalate ", " (map show r)

-- | The locators of C4: a page, a page of 0, a range, a range of equal ends, a page of text and one with a space.
locators :: [LocatorValue]
locators = [LocNumber 5, LocNumber 0, LocRange 5 7, LocRange 5 5, LocText "xii", LocText "5 f."]

tests :: TestTree
tests =
  testGroup
    "citations (docs/adr/0266)"
    [ testCase "C4 (docs/adr/0277): the text of every mark is the one before the ADR, without a locator and with one on any item" $
        forM_ orders $ \ns -> do
          citationText (citationPieces (itemsOf ns)) @?= textBefore (itemsOf ns)
          forM_ locators $ \v ->
            forM_ [0 .. length ns - 1] $ \k -> do
              let items = [(if j == k then i {citLocator = page v} else i, n) | (j, (i, n)) <- zip [0 ..] (itemsOf ns)]
              citationText (citationPieces items) @?= textBefore items,
      testCase "C4 (docs/adr/0277): an item with a locator has one CiteLocator, its label p. or pp. and its value the rest" $
        forM_ locators $ \v -> do
          let ps = citationPieces [(citeItem "b", Just 2), (CiteItem "a" (page v) [] [], Just 1)]
          case [(l, x) | CiteLocator l x <- ps] of
            [(l, x)] -> do
              assertBool (show l) (l `elem` ["p.", "pp."])
              (l == "pp.") @?= (case v of LocRange a b -> a /= b; _ -> False)
              ps @?= [CiteText "[", CiteNumber "b" 2, CiteText "; ", CiteNumber "a" 1, CiteText ", ", CiteLocator l x, CiteText "]"]
            other -> assertFailure (show other),
       testCase "I1: the numbers of a mark without a locator, the ranges by what they cover, are the numbers cited, each once" $
        forM_ orders $
          \ns -> covered (citationPieces (itemsOf ns)) @?= sort ns,
      testCase "I2: the mark without a locator does not change with the order of the keys" $
        forM_ (filter (not . null) (subsequences [1 .. 6])) $ \ns ->
          forM_ (permutations ns) $ \o -> citationPieces (itemsOf o) @?= citationPieces (itemsOf ns),
      testCase "I3: the parts ascend; a range covers three or more; parts not ranges next to each other are apart or only two in a row" $
        forM_ orders $ \ns -> do
          let ps = parts (citationPieces (itemsOf ns))
              ends = map (\q -> (minimum q, maximum q)) ps
              next a b = snd a + 1 == fst b
              single (a, b) = a == b
          assertBool (show ns) (and (zipWith (<) (concat ps) (drop 1 (concat ps))))
          assertBool (show ns) (and [b - a >= 2 | [a, b] <- ps])
          -- next to a range nothing is consecutive; two singles in a row may be, never three
          assertBool (show ns) (and [single a && single b | (a, b) <- zip ends (drop 1 ends), next a b])
          assertBool (show ns) (not (or (zipWith3 (\a b c -> next a b && next b c) ends (drop 1 ends) (drop 2 ends)))),
      testCase "the marks of the ADR" $ do
        citationText (citationPieces (itemsOf [1, 2])) @?= "[1, 2]"
        citationText (citationPieces (itemsOf [3, 1, 2])) @?= "[1\x2013\&3]"
        citationText (citationPieces (itemsOf [7, 5, 1, 4, 3])) @?= "[1, 3\x2013\&5, 7]"
        citationText (citationPieces (itemsOf [1, 2, 4, 5])) @?= "[1, 2, 4, 5]"
        citationText (citationPieces [(CiteItem "a" (page (LocNumber 5)) [] [], Just 1)]) @?= "[1, p. 5]"
        citationText (citationPieces [(CiteItem "a" (page (LocText "xii")) [] [], Just 1)]) @?= "[1, p. xii]"
        citationText (citationPieces [(CiteItem "a" (page (LocRange 5 7)) [] [], Just 1)]) @?= "[1, pp. 5\x2013\&7]"
        citationText (citationPieces [(CiteItem "a" (page (LocRange 5 5)) [] [], Just 1)]) @?= "[1, p. 5]"
        citationText (citationPieces [(CiteItem "a" (page (LocNumber 0)) [] [], Just 1)]) @?= "[1, p. 0]",
      testCase "I4: a mark with a locator puts its numbers in the order written" $ do
        let items = [(CiteItem "c" (page (LocNumber 9)) [] [], Just 3), (citeItem "a", Just 1), (citeItem "b", Just 2)]
        citationText (citationPieces items) @?= "[3, p. 9; 1; 2]"
        [n | CiteNumber _ n <- citationPieces items] @?= [3, 1, 2],
      testCase "I8: the mark of one key without a locator is [n]" $
        forM_ [1 .. 12] $
          \n -> citationText (citationPieces (itemsOf [n])) @?= "[" <> T.pack (show n) <> "]",
      testCase "each number stands with the key it stands for; a range its two ends" $ do
        citationPieces (itemsOf [2, 1, 3]) @?= [CiteText "[", CiteNumber "k1" 1, CiteText "\x2013", CiteNumber "k3" 3, CiteText "]"]
        citationPieces (itemsOf [2, 1]) @?= [CiteText "[", CiteNumber "k1" 1, CiteText ", ", CiteNumber "k2" 2, CiteText "]"],
      testCase "an item without a number stands as its key, after the numbers" $
        citationText (citationPieces [(citeItem "z", Nothing), (citeItem "a", Just 2)]) @?= "[2, z]",
      testCase "I7: citations of every locator, a prefix and a suffix survive the CBOR round trip" $
        forM_ [minBound .. maxBound] $ \label ->
          forM_ [LocNumber 0, LocNumber 5, LocRange 5 7, LocText "xii"] $ \v -> do
            let d = docOf [Cite sp [CiteItem "a" (Just (Locator label v)) [Text sp "前"] [Text sp "後"], citeItem "b"]]
            decodeDocument (encodeDocument d) @?= Right d,
      testCase "a citation is tag 25; 15 is retired" $ do
        let spT = TList [TInt 0, TInt 0, TInt 1]
            inl t = decodeInlines (toStrictByteString (encodeTerm (TList [t])))
            item k l = TList [TString k, l, TList [], TList []]
        inl (TList [TInt 25, spT, TList [item "a" TNull]]) @?= Right [Cite sp [citeItem "a"]]
        inl (TList [TInt 25, spT, TList [item "a" (TList [TString "page", TList [TInt 1, TInt 5, TInt 7]])]])
          @?= Right [Cite sp [CiteItem "a" (page (LocRange 5 7)) [] []]]
        inl (TList [TInt 15, spT, TString "a"]) @?= Left "スキーマに合いません: インラインの種類"
        inl (TList [TInt 25, spT, TList [item "a" (TList [TString "pages", TList [TInt 0, TInt 5]])]]) @?= Left "スキーマに合いません: 位置の種類"
        inl (TList [TInt 25, spT, TList [item "a" (TList [TString "page", TList [TInt 0, TInt (-1)]])]]) @?= Left "スキーマに合いません: 自然数",
      testCase "I7: Validate rejects no item, a key twice, a kind other than page, a prefix or a suffix, and a bad value" $ do
        let errs is = validateDocument size [] (docOf is)
            loc v = CiteItem "a" (page v) [] []
        errs [Cite sp [citeItem "a", citeItem "b"]] @?= []
        errs [Cite sp []] @?= ["引用は一つ以上の文献を持ちます"]
        errs [Cite sp [citeItem "a", citeItem "a", citeItem "a"]] @?= ["引用に同じキーが二度あります: a"]
        errs [Cite sp [CiteItem "a" (Just (Locator LocatorChapter (LocNumber 2))) [] []]] @?= ["まだ組めない引用の値です: 位置の種類 chapter"]
        errs [Cite sp [CiteItem "a" Nothing [Text sp "前"] []]] @?= ["まだ組めない引用の値です: 前置きと後置き"]
        errs [Cite sp [CiteItem "a" Nothing [] [Text sp "後"]]] @?= ["まだ組めない引用の値です: 前置きと後置き"]
        errs [Cite sp [loc (LocNumber 0)], Cite sp [loc (LocRange 5 5)], Cite sp [loc (LocText "xii")]] @?= []
        errs [Cite sp [loc (LocNumber (-1))]] @?= ["引用の位置の数が負です"]
        errs [Cite sp [loc (LocRange 7 5)]] @?= ["引用の位置の範囲が負か逆向きです"]
        errs [Cite sp [loc (LocRange (-1) 5)]] @?= ["引用の位置の範囲が負か逆向きです"]
        errs [Cite sp [loc (LocText "")]] @?= ["引用の位置の文字列が空です"],
      needsTool "cddl" cddlValidator $ \cddl ->
        testCase "the cddl CLI takes a citation of tag 25 and rejects one of no item" $ do
          exe <- cddl
          let validate bs = withSystemTempDirectory "golem-doc" $ \dir -> do
                let path = dir </> "doc.cbor"
                BS.writeFile path bs
                (code, _, _) <- readProcessWithExitCode exe ["--ci", "validate", "--cddl", "schema/golem-doc.cddl", "--cbor", path] ""
                pure code
          validate (encodeDocument (docOf [Cite sp [CiteItem "a" (page (LocRange 5 7)) [Text sp "前"] [], citeItem "b"]])) >>= (@?= ExitSuccess)
          code <- validate (encodeDocument (docOf [Cite sp []]))
          assertBool "empty" (code /= ExitSuccess)
    ]

cddlValidator :: IO (Maybe FilePath)
cddlValidator = do
  env <- lookupEnv "GOLEM_CDDL"
  case env of
    Just p -> pure (Just p)
    Nothing -> findExecutable "cddl"
