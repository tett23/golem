{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Golem.Parser as P
import qualified Golem.Parser.CST as C
import Golem.Syntax (FileId (..))
import System.Environment (getArgs)

raw :: C.Element -> J.Value
raw (C.ElemToken (C.Token kind text)) =
  let name = case kind of
        C.KWord -> "Word"
        C.KEquals -> "Eq"
        C.KString -> "StringLit"
        _ -> error ("unexpected keyword token " <> show kind)
   in J.object ["name" J..= (name :: T.Text), "text" J..= text]
raw _ = error "unexpected nested node in the canonical keyword"

keywords :: C.Node -> [[J.Value]]
keywords node
  | C.nodeKind node == C.NKeywordArgument = [map raw (C.nodeChildren node)]
  | otherwise = concat [keywords child | C.ElemNode child <- C.nodeChildren node]

main :: IO ()
main = do
  [file] <- getArgs
  source <- TIO.readFile file
  let (tree, diagnostics) = P.parse (FileId 0) source
  if null diagnostics then pure () else error (show diagnostics)
  B.putStrLn (J.encode (keywords tree))
