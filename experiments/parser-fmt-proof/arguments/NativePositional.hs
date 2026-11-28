{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Golem.Parser as P
import qualified Golem.Parser.AST as A
import qualified Golem.Parser.CST as C
import Golem.Syntax (FileId (..))
import System.Environment (getArgs)

raw :: C.Element -> J.Value
raw (C.ElemToken (C.Token C.KWord text)) = J.object ["name" J..= ("Word" :: T.Text), "text" J..= text]
raw (C.ElemToken (C.Token C.KString text)) = J.object ["name" J..= ("StringLit" :: T.Text), "text" J..= text]
raw _ = error "unexpected positional token or nested node"

captures :: C.Node -> [[J.Value]]
captures node
  | C.nodeKind node == C.NArgument = [map raw (C.nodeChildren node)]
  | otherwise = concat [captures child | C.ElemNode child <- C.nodeChildren node]

argument :: A.Located A.Argument -> J.Value
argument (A.Located _ (A.Positional value)) =
  let (kind, text) = case value of
        A.Word chars -> ("Word", chars)
        A.StringLit chars -> ("StringLit", chars)
        _ -> error "unexpected positional value"
   in J.object ["argument" J..= ("Positional" :: T.Text), "kind" J..= (kind :: T.Text), "value" J..= text]
argument _ = error "expected a positional argument"

main :: IO ()
main = do
  [file] <- getArgs
  source <- TIO.readFile file
  let (A.File _ blocks, tree, diagnostics) = P.parseAst (FileId 0) source
  if null diagnostics then pure () else error (show diagnostics)
  case blocks of
    [A.Located _ (A.Paragraph [A.Located _ (A.Command (A.Located _ "inspect") args [])])] ->
      B.putStrLn (J.encode (J.object ["cst" J..= captures tree, "ast" J..= map argument args]))
    _ -> error (show blocks)
