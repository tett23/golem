module PositionEnumSpec (positionEnumTests) where

import Control.Monad (replicateM, when)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Lsp.Features qualified as Lsp
import Golem.Syntax (FileId (..), LineCol (..), mkLineIndex)
import Golem.Typeset (pagesJson)
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (assertEqual, testCase, (@?=))

family :: String
family = "👨\x200d👩\x200d👧\x200d👦"

manuscripts :: [String]
manuscripts =
  concat [replicateM n "a漢😀\n" | n <- [0 .. 3]]
    ++ [family, "a" ++ family ++ "漢", "😀\n" ++ family ++ "\n" ++ family]

boundaries :: [(String, Int)]
boundaries = [(source, count) | source <- manuscripts, count <- [0 .. length source]]

expected :: String -> Int -> (Int, LineCol)
expected source count =
  let prefix = T.pack (take count source)
      lastLine = last (T.splitOn "\n" prefix)
      byte = BS.length (TE.encodeUtf8 prefix)
      line = T.count "\n" prefix
      column = BS.length (TE.encodeUtf16LE lastLine) `div` 2
   in (byte, LineCol line column)

positionEnumTests :: TestTree
positionEnumTests =
  testGroup
    "Golem ADR 0311"
    [ testCase "U1: all valid UTF-8 and UTF-16 boundaries round trip" $ do
        Lsp.chooseEncoding (Just [Lsp.encodingKind Lsp.Utf16, Lsp.encodingKind Lsp.Utf8]) @?= Lsp.Utf8
        mapM_
          ( \(source, count) -> do
              let index = mkLineIndex (T.pack source)
                  (byte, utf16) = expected source count
                  context = "source: " ++ show source ++ ", boundary: " ++ show count
              assertEqual context utf16 (Lsp.toLineCol Lsp.Utf16 index byte)
              assertEqual context (Just byte) (Lsp.fromLineCol Lsp.Utf16 index utf16)
              assertEqual context (Just byte) (Lsp.fromLineCol Lsp.Utf8 index (Lsp.toLineCol Lsp.Utf8 index byte))
              when (source == "a😀" && count == 2) $
                Lsp.toLineCol Lsp.Utf8 index byte @?= LineCol 0 5
          )
          boundaries,
      testCase "U2: pagesJson uses independent UTF-16 line and column" $
        mapM_
          ( \(source, count) -> do
              let (byte, LineCol line column) = expected source count
                  fid = FileId 0
                  actual = pagesJson (Map.singleton fid ("in.gm", T.pack source)) [Just (fid, byte)]
                  value = T.pack . show
                  want =
                    "[{\"page\":1,\"file\":\"in.gm\",\"line\":"
                      <> value line
                      <> ",\"character\":"
                      <> value column
                      <> "}]\n"
              assertEqual ("source: " ++ show source ++ ", boundary: " ++ show count) want actual
          )
          boundaries,
      testCase "U3: positions inside supplementary characters have no byte offset" $ do
        mapM_
          ( \(source, count) -> do
              let index = mkLineIndex (T.pack source)
                  (_, LineCol line column) = expected source count
              case drop count source of
                character : _
                  | fromEnum character > 0xffff ->
                      Lsp.fromLineCol Lsp.Utf16 index (LineCol line (column + 1)) @?= Nothing
                _ -> pure ()
          )
          boundaries
        let index = mkLineIndex (T.pack family)
        map (Lsp.toLineCol Lsp.Utf16 index) [0, 4, 7, 11, 14, 18, 21, 25]
          @?= map (LineCol 0) [0, 2, 3, 5, 6, 8, 9, 11]
        map (Lsp.fromLineCol Lsp.Utf16 index . LineCol 0) [1, 4, 7, 10]
          @?= replicate 4 Nothing
    ]
