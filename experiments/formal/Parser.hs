module Main where
import Control.Monad (unless)
import Data.Text qualified as T
import Data.Text.IO qualified as T
import Data.Text.Encoding qualified as TE
import Data.ByteString qualified as BS
import Peg.Grammar qualified as P
import Peg.Grammar.Parser (parseGrammar)
import Golem.Parser (parse)
import Golem.Fmt
import Golem.Syntax

main :: IO ()
main = do
  grammar <- T.readFile "modules/golem-parser/grammar/Golem.hpeg"
  g <- either (fail . show) pure (parseGrammar grammar)
  let literals = [t | rule <- P.grammarRules g, P.ruleName rule == "HashMark",
                      alt <- P.ruleAlts rule, [item] <- [P.altItems alt], P.ELit t _ <- [P.itemExpr item]]
      texts = ["a","漢","😀"]
      valid = "" : [hash <> " " <> t <> "\n" | hash <- literals, t <- texts] ++ [a <> "\n\n" <> b | a <- texts, b <- texts]
      broken = [(p <> "####### a\n", BS.length (TE.encodeUtf8 p) + 6) | p <- "" : [t <> "\n\n" | t <- texts]]
      good t = case format t of
        Formatted u -> null (snd (parse (FileId 0) t)) && astFingerprint t == astFingerprint u && case format u of Formatted v -> u == v; _ -> False
        _ -> False
      bad (t, at) = any (\d -> diagCode d == DiagnosticCode "G01012" && spanStart (diagSpan d) == at) (snd (parse (FileId 0) t))
  unless (map T.length literals == [6,5..1] && all good valid && all bad broken) $
    fail (show (filter (not . good) valid, [(t,n,snd (parse (FileId 0) t)) | (t,n) <- broken, not (bad (t,n))]))
  putStrLn ("G1/G2 valid=" ++ show (length valid) ++ " G3 invalid=" ++ show (length broken))
