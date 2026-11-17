module Main (main) where
import Golem.Parser (parseAst)
import Golem.Parser.AST qualified as A
import Golem.Syntax (FileId(..),diagCode,DiagnosticCode(..))
import System.Exit (exitFailure)

main :: IO ()
main = do
  let kind = \case
        A.SetVar {} -> "set"
        A.Paragraph {} -> "paragraph"
        A.CodeBlock {} -> "code"
        A.BlockCommand {} -> "command"
        _ -> "other"
      cases = [ ("set x = 3\n",["set"]),("@set x = 3\n",["set"])
              , ("set x == 3\n",["paragraph"]),("set x is fine\n",["paragraph"])
              , ("本文 set x = 3\n",["paragraph"]),("set bad-name = 3\n",["paragraph"])
              , ("\x60\x60\x60\nset x = 3\n\x60\x60\x60\n",["code"])
              , ("@import f as m\n",["command"])
              , ("set x = 3\n\n[= x]\n",["set","paragraph"])
              ]
      run (src,want) =
        let (ast,_,ds) = parseAst (FileId 1) src
            got = map (kind . A.locValue) (A.fileBlocks ast)
         in (src,got,null ds && got==want)
      results=map run cases
      ok=length [() | (_,_,True)<-results]
  let rangeCases = [ ("@listing missing.txt lines=-1\n",["G02110"])
                   , ("@listing missing.txt lines=\"2...-1\"\n",["G02110"])
                   , ("``` highlight=-2\na\n```\n",["G02110"])
                   , ("@listing missing.txt lines=[= 0 - 1]\n",[])
                   , ("@listing missing.txt lines=1...3\n",[])
                   , ("@other lines=-1\n",[])
                   ]
      probe (src,want) = let (_,_,ds)=parseAst (FileId 1) src
                          in (src,[x | d<-ds, let DiagnosticCode x=diagCode d]==want)
      stage=map probe rangeCases
  mapM_ print stage
  print (length (filter snd stage),length stage)
  mapM_ print results
  print (ok,length cases)
  if ok==length cases && all snd stage then pure () else exitFailure
