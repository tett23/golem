{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Golem.Parser as P
import qualified Golem.Parser.AST as A
import Golem.Syntax (FileId (..))
import System.Environment (getArgs)

argument :: A.Located A.Argument -> J.Value
argument (A.Located _ (A.Keyword (A.Located _ name) (A.StringLit value))) =
  J.object ["name" J..= name, "kind" J..= ("StringLit" :: T.Text), "value" J..= value]
argument (A.Located _ (A.Keyword (A.Located _ name) (A.Word value))) =
  J.object ["name" J..= name, "kind" J..= ("Word" :: T.Text), "value" J..= value]
argument _ = error "expected one Word or StringLit keyword argument"

main :: IO ()
main = do
  [file] <- getArgs
  source <- TIO.readFile file
  let (A.File _ blocks, _, diagnostics) = P.parseAst (FileId 0) source
  if null diagnostics then pure () else error (show diagnostics)
  case blocks of
    [A.Located _ (A.BlockCommand (A.Located _ "inspect") args [])] -> B.putStrLn (J.encode (map argument args))
    _ -> error (show blocks)
