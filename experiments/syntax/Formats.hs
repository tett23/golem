module Main (main) where
import Control.Monad (forM)
import Golem.Project.Style (parseStyle)
import Golem.Syntax
import System.Exit (exitFailure)
main :: IO ()
main = do
  let cases =
        [ ("318 I1","[lists]\nnumbers = [\"{n:lower-alpha}\"]",[])
        , ("318 I1","[character-styles.note-mark]\nsize=\"0.5zw\"",[])
        , ("318 I2","[lists]\nnumbers = [\"{{{n}}}\"]",["G03250"])
        , ("318 I2","[lists]\nnumbers = [\"{a}\"]",["G03251"])
        , ("318 I2","[lists]\nnumbers = [\"{{{a}}}\"]",["G03250","G03251"])
        , ("318 I2","[masters.book]\nrunning-head={position=\"top-outside\",content=[\"{{x}}\"]}",["G03252"])
        , ("318 I2","[notes]\nmark-size=\"0.5zw\"",["G03253"])
        ]
  matches <- forM cases $ \(label,src,expected) -> do
    let ds=either id (const []) (parseStyle (FileId 0) src)
        actual=map diagCode ds
        ok=actual==map DiagnosticCode expected && all ((==Error) . diagSeverity) ds
    print (label,src, map (\d->(diagCode d,spanStart (diagSpan d))) ds,ok)
    pure ok
  print (length (filter id matches),length cases)
  if and matches then pure () else exitFailure
