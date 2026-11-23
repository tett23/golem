module KeepPartsSpec (tests) where

import Control.Monad (forM_)
import Data.Text qualified as T
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "root ADR 0401 book-part retention settings"
    [ testCase "root ADR 0401 I1: omitted keep-parts equals column" $
        parseStyle (FileId 0) "" @?= parseStyle (FileId 0) "[composition]\nkeep-parts = \"column\"\n",
      testCase "root ADR 0401 I2: all three retention units are accepted" $
        forM_ ["column", "page", "spread"] $ \unit ->
          case parseStyle (FileId 0) ("[composition]\nkeep-parts = \"" <> unit <> "\"\n") of
            Left ds -> assertFailure (show ds)
            Right _ -> pure (),
      testCase "root ADR 0401 I2: invalid units and types report G03006" $
        forM_ ["\"sheet\"", "true", "1", "[]"] $ \value ->
          case parseStyle (FileId 0) ("[composition]\nkeep-parts = " <> value <> "\n") of
            Left ds -> map diagCode ds @?= [DiagnosticCode "G03006"]
            Right _ -> assertFailure ("accepted " <> T.unpack value)
    ]
