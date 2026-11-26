{- | The tables of the variables of an @import, found through the import
graph, and the @import of a variable file that the evaluation of a file
outside a project does not resolve (root ADR 0455).
-}
module ImportGraphSpec (importGraphTests) where

import Data.List (nub, sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Golem.Doc.IR (Document)
import Golem.Driver
import Golem.Eval.File (EvalResult (..))
import Golem.Syntax
import Support (codesOf, withChapters)
import System.Directory (createDirectoryIfMissing, createFileLink)
import System.FilePath ((</>))
import Test.Tasty
import Test.Tasty.HUnit

importGraphTests :: TestTree
importGraphTests =
  testGroup
    "variable imports through the import graph (root ADR 0455)"
    [ testCase "root ADR 0455 I1: ./common/v.gm { price } is common/v.gm { price }" $
        sameAs (listed "./common/v.gm") (listed "  common/v.gm"),
      testCase "root ADR 0455 I1: common/../common/v.gm * as v is common/v.gm * as v" $
        sameAs (spaced "common/../common/v.gm") (spaced "          common/v.gm"),
      testCase "root ADR 0455 I1: a link to common/v.gm is common/v.gm" $
        sameAs (listed "    link.gm") (listed "common/v.gm"),
      testCase "root ADR 0455 I4: common/v.gm { price } shows the price, with no diagnostic of the import" $ do
        (codes, docs) <- project (listed "common/v.gm")
        assertBool (show codes) (not (any (`elem` codes) ["G02002", "G02276"]))
        assertBool "the value" (any (T.isInfixOf "PRICEVALUE" . T.pack . show) docs),
      testCase "root ADR 0455 I4: a name common/v.gm does not set is G02276" $ do
        (codes, _) <- project "@import common/v.gm { cost }\n\n一。\n"
        assertBool (show codes) ("G02276" `elem` codes),
      testCase "root ADR 0461 I3: outside a project, v.gm { price } and [= price], [= price + 1] are G02281 twice" $
        loose "@import v.gm { price }\n\n[= price]\n\n[= price + 1]\n" @?= ["G02281", "G02281"],
      testCase "root ADR 0461 I3: outside a project, v.gm * as v and [= v.price] is G02281" $
        loose "@import v.gm * as v\n\n[= v.price]\n" @?= ["G02281"],
      testCase "root ADR 0461 I3: outside a project, f.emet { total } and [= total(1)] is one G02281" $
        loose "@import f.emet { total }\n\n[= total(1)]\n" @?= ["G02281"],
      testCase "root ADR 0455 I2: outside a project, v.gm { meta } is G02275 only" $
        loose "@import v.gm { meta }\n" @?= ["G02275"],
      testCase "root ADR 0455 I2: outside a project, the clashes of v.gm { price } are not reported" $
        loose "@import v.gm { price }\n@import w.gm { price }\n\n@set price = 1\n" @?= [],
      testCase "root ADR 0455 I5: outside a project, a @set of a listed variable defines nothing, as of a .emet" $ do
        let src p = "@import " <> p <> " { price }\n\n@set y = price(1)\n\n[= y]\n"
        loose (src "v.gm") @?= ["G02281", "G02002"]
        set (loose (src "v.gm")) @?= set (loose (src "f.emet"))
        -- root ADR 0461 I3, I6: G02281 at the @set, and G02002 at y as before
        loose "@import v.gm { price }\n\n@set y = price\n\n[= y]\n" @?= ["G02281", "G02002"],
      testCase "root ADR 0455 I5: outside a project, a call of a listed name reports as of a .emet" $ do
        let src p = "@import " <> p <> " { total }\n\n[= total(1)]\n"
        set (loose (src "v.gm")) @?= set (loose (src "f.emet"))
    ]
  where
    listed p = "@import " <> p <> " { price }\n\n[= price]\n"
    spaced p = "@import " <> p <> " * as v\n\n[= v.price]\n"
    set = sort . nub

{- | Two chapters, each evaluated in a project with common/v.gm and a link
to it, give the same codes and the same documents. The lines of the
@import of the two are of the same length, so that the spans are too.
-}
sameAs :: T.Text -> T.Text -> Assertion
sameAs a b = do
  (ca, da) <- project a
  (cb, db) <- project b
  assertBool (show ca) ("G02276" `notElem` ca)
  sort ca @?= sort cb
  da @?= db

-- | The codes of the evaluation of a project of one chapter, and the documents of its files.
project :: T.Text -> IO ([T.Text], [Document])
project chapter = withChapters "" [("a.gm", chapter)] [] $ \tmp -> do
  createDirectoryIfMissing True (tmp </> "common")
  TIO.writeFile (tmp </> "common" </> "v.gm") "@set price = \"PRICEVALUE\"\n"
  createFileLink ("common" </> "v.gm") (tmp </> "link.gm")
  r <- evaluateProject Dev tmp
  case r of
    Left _ -> assertFailure "the project does not load" >> pure ([], [])
    Right ev -> pure (codesOf (evDiagnostics ev), map erDocument (Map.elems (evResults ev)))

-- | The codes of the evaluation of a file outside a project.
loose :: T.Text -> [T.Text]
loose = codesOf . erDiagnostics . evaluateLoose "a.gm"
