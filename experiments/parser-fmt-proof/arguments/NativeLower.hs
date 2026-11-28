{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Text as T
import qualified Golem.Parser.AST as A
import qualified Golem.Parser.CST as C
import qualified Golem.Parser.Lower as L
import Golem.Syntax (FileId (..))
import System.Environment (getArgs)

argument :: A.Located A.Argument -> J.Value
argument (A.Located _ (A.Keyword (A.Located _ name) (A.Word value))) =
  J.object ["name" J..= name, "kind" J..= ("Word" :: T.Text), "value" J..= value]
argument (A.Located _ (A.Keyword (A.Located _ name) (A.StringLit value))) =
  J.object ["name" J..= name, "kind" J..= ("StringLit" :: T.Text), "value" J..= value]
argument _ = error "unexpected CST argument shape"

make :: [T.Text] -> C.Element
make [_, "Ignored", text] = C.token C.KText text
make [name, kind, value] =
  C.ElemNode
    ( C.node
        C.NKeywordArgument
        ( [C.token C.KProofComment "%%= proof %%" | kind == "ProofComment"]
            <> [ C.token C.KComment "%% before %%",
                 C.token C.KWord name,
                 C.token C.KWhitespace "  ",
                 C.token C.KEquals "=",
                 C.token C.KComment "%% middle %%",
                 C.token (if kind == "Word" then C.KWord else C.KString) value,
                 C.token C.KNewline "\n"
               ]
        )
    )
make _ = error "expected name, kind and source spelling"

main :: IO ()
main = do
  [file] <- getArgs
  bytes <- B.readFile file
  rows <- either fail pure (J.eitherDecode bytes)
  let cst =
        C.node
          C.NFile
          [ C.ElemNode
              ( C.node
                  C.NBlockCommand
                  (C.token C.KIdent "inspect" : map make rows)
              )
          ]
      A.File _ blocks = L.lower (FileId 0) cst
  case blocks of
    [A.Located _ (A.BlockCommand (A.Located _ "inspect") args [])] -> B.putStrLn (J.encode (map argument args))
    _ -> error (show blocks)
