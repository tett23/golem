{- | Where a URL may break (golem-layout ADR 0018): after the characters of
url.sty's \UrlBreaks and \UrlBigBreaks, after the last slash of a run,
never inside "https:" and "//", never at a hyphen or after a percent sign.
-}
module UrlBreakSpec (urlBreakTests) where

import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, look0, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Test.Tasty
import Test.Tasty.HUnit

compose :: Look -> Text -> [Item]
compose lk t = fst (composeInlines (defaultComposeEnv fs) {ceLook = lk} [IR.Text sp t])

url, code :: Look
url = look0 {lkUrl = True}
code = look0 {lkCode = True}

{- | The text before each legal break inside the text (the paragraph end
left out), and its penalty.
-}
breaksOf :: [Item] -> [(Text, Int)]
breaksOf items = go "" (take (length items - 3) items)
  where
    go acc = \case
      Box _ c : rest -> go (acc <> bcText c) rest
      Penalty _ p _ : rest | p < infPenalty -> (acc, p) : go acc rest
      Glue {} : rest -> go acc rest
      _ : rest -> go acc rest
      [] -> []

urlBreakTests :: TestTree
urlBreakTests =
  testGroup
    "line breaks inside a URL (golem-layout ADR 0018)"
    [ testCase "after the slashes and the dots of a URL, 0 after a slash and 100 after a dot" $
        breaksOf (compose url "https://learn.microsoft.com/ja-jp/windows/wsl/filesystems")
          @?= [ ("https://", 0),
                ("https://learn.", 100),
                ("https://learn.microsoft.", 100),
                ("https://learn.microsoft.com/", 0),
                ("https://learn.microsoft.com/ja-jp/", 0),
                ("https://learn.microsoft.com/ja-jp/windows/", 0),
                ("https://learn.microsoft.com/ja-jp/windows/wsl/", 0)
              ],
      testCase "not between https: and //, between two slashes, or around a hyphen" $ do
        let bs = map fst (breaksOf (compose url "https://learn.microsoft.com/ja-jp/windows"))
        assertBool (show bs) (all (`notElem` bs) ["https:", "https:/", "https://learn.microsoft.com/ja-", "https://learn.microsoft.com/ja"]),
      testCase "after ?, =, & and # with 100; not inside a percent encoding" $ do
        breaksOf (compose url "a?b=c&d#e") @?= [("a?", 100), ("a?b=", 100), ("a?b=c&", 100), ("a?b=c&d#", 100)]
        breaksOf (compose url "%E3%81") @?= [],
      testCase "the other characters of url.sty's breaks" $
        map fst (breaksOf (compose url "a.b@c!d_e|f;g>h]i)j,k'l+m:n"))
          @?= map T.pack ["a.", "a.b@", "a.b@c!", "a.b@c!d_", "a.b@c!d_e|", "a.b@c!d_e|f;", "a.b@c!d_e|f;g>", "a.b@c!d_e|f;g>h]", "a.b@c!d_e|f;g>h]i)", "a.b@c!d_e|f;g>h]i)j,", "a.b@c!d_e|f;g>h]i)j,k'", "a.b@c!d_e|f;g>h]i)j,k'l+", "a.b@c!d_e|f;g>h]i)j,k'l+m:"],
      testCase "code keeps its breaks: after a slash only" $
        breaksOf (compose code "a.b/c") @?= [("a.b/", 0)],
      testCase "a line broken inside a URL ends with no hyphen" $ do
        let its = compose url "https://learn.microsoft.com/ja-jp/windows/wsl/filesystems"
            ls = brLines (breakParagraph defaultParams (const (10 * fs)) its)
        assertBool (show (length ls)) (length ls > 1)
        mapM_ (\l -> [w | Penalty w _ _ <- lineItems l, w > 0] @?= []) ls
    ]
