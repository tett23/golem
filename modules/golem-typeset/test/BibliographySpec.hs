module BibliographySpec (bibliographyTests) where

import Data.Map.Strict qualified as Map
import Golem.Bibliography (EntryPart (..))
import Golem.Doc.IR (InlineF (..))
import Golem.Syntax.Span (FileId (..), mkSpan)
import Golem.Typeset (bibliographyLines)
import Test.Tasty
import Test.Tasty.HUnit

bibliographyTests :: TestTree
bibliographyTests =
  testCase "root ADR 0470 I2: PDF bibliography retains field styles and URL links" $
    let sp = mkSpan (FileId 0) 0 0
     in bibliographyLines (Map.singleton "k" [EntryStyled "italic" [EntryText "Title"], EntryText ". ", EntryStyled "strong" [EntryUrl "https://example.org"]]) [("k", 1)]
          @?= [[Text sp "[1] ", CharStyle sp "italic" [Text sp "Title"], Text sp ". ", CharStyle sp "strong" [Link sp "https://example.org" [CharStyle sp "url" [Text sp "https://example.org"]]]]]
