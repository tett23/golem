{-# LANGUAGE OverloadedStrings #-}

import qualified Data.Aeson as J
import qualified Data.ByteString.Lazy.Char8 as B
import qualified Data.Text as T
import qualified Data.Text.IO as TIO
import qualified Golem.Parser as P
import qualified Golem.Syntax as S
import System.Environment (getArgs)

severity :: S.Severity -> T.Text
severity S.Error = "error"
severity S.Warning = "warning"
severity S.Notice = "notice"
severity S.Info = "info"

diagnostic :: S.Diagnostic -> J.Value
diagnostic d =
  let S.DiagnosticCode code = S.diagCode d
      sp = S.diagSpan d
      edits fix = map (\(e, t) -> J.object ["start" J..= S.spanStart e, "end" J..= S.spanEnd e, "text" J..= t]) (S.fixEdits fix)
   in J.object ["code" J..= code, "severity" J..= severity (S.diagSeverity d), "start" J..= S.spanStart sp, "end" J..= S.spanEnd sp, "fixes" J..= map edits (S.diagFixes d)]

main :: IO ()
main = do
  [file] <- getArgs
  source <- TIO.readFile file
  let (_, ds) = P.parse (S.FileId 0) source
  B.putStrLn (J.encode (map diagnostic ds))
