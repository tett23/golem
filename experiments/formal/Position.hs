module Main where
import Control.Monad (replicateM, unless)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as M
import Golem.Syntax
import Golem.Lsp.Features qualified as F
import Golem.Typeset.Pages
main :: IO ()
main = do
  let family = "👨\x200d👩\x200d👧\x200d👦"
      families = [family, "a" ++ family ++ "漢", "😀\n" ++ family ++ "\n" ++ family]
      corpus = concat [replicateM n "a漢😀\n" | n <- [0..3]]
      cases = [(s,k) | s <- corpus ++ families, k <- [0..length s]]
      check (s,k) =
        let text = T.pack s
            prefix = T.pack (take k s)
            current = last (T.splitOn "\n" prefix)
            byte = BS.length (TE.encodeUtf8 prefix)
            l = T.count "\n" prefix
            c = BS.length (TE.encodeUtf16LE current) `div` 2
            pos = LineCol l c
            index = mkLineIndex text
            fid = FileId 0
            json = pagesJson (M.singleton fid ("in.gm",text)) [Just (fid,byte)]
            field n = T.pack (show n)
        in F.toLineCol F.Utf16 index byte == pos && F.fromLineCol F.Utf16 index pos == Just byte &&
           F.fromLineCol F.Utf8 index (F.toLineCol F.Utf8 index byte) == Just byte &&
           (not (any ((> 0xffff) . fromEnum) (take 1 (drop k s))) || F.fromLineCol F.Utf16 index (LineCol l (c+1)) == Nothing) &&
           json == "[{\"page\":1,\"file\":\"in.gm\",\"line\":" <> field l <> ",\"character\":" <> field c <> "}]\n"
  unless (all check cases) $ fail (show (filter (not . check) cases))
  let familyOffsets = [(F.toLineCol F.Utf16 (mkLineIndex (T.pack family)) byte) | byte <- [0,4,7,11,14,18,21,25]]
  unless (familyOffsets == map (LineCol 0) [0,2,3,5,6,8,9,11]) $ fail "family UTF-16 boundary"
  putStrLn ("U1/U2/U3 strings=" ++ show (length (corpus ++ families)) ++ " boundaries=" ++ show (length cases))
  putStrLn ("family UTF8=" ++ show (map (BS.length . TE.encodeUtf8 . T.pack . (\k -> take k family)) [0..length family]) ++ " UTF16=" ++ show (map ((`div` 2) . BS.length . TE.encodeUtf16LE . T.pack . (\k -> take k family)) [0..length family]) ++ " families=" ++ show (length families))
