module ScriptSpec (tests) where

import Control.Monad (forM_)
import Golem.Unicode.Script (isHanOrKana)
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup
    "bibliography scripts"
    [ testCase "root ADR 0470 I7: Han and both kana scripts are recognized" $
        forM_ ("山田やまだヤマダ々〇" :: String) $
          \c -> assertBool (show c) (isHanOrKana c),
      testCase "root ADR 0470 I7: halfwidth kana is recognized" $
        forM_ ("ﾔﾏﾀ" :: String) $
          \c -> assertBool (show c) (isHanOrKana c),
      testCase "root ADR 0470 I7: supplementary Han and archaic kana are recognized" $
        forM_ ['\x20000', '\x33479', '\x1B000', '\x1B001', '\x1AFF0'] $
          \c -> assertBool (show c) (isHanOrKana c),
      testCase "root ADR 0470 I7: Latin, Hangul, Greek and emoji are not Han or kana" $
        forM_ ("SmithＫａｄａｒ김Παπα🙂" :: String) $
          \c -> assertBool (show c) (not (isHanOrKana c)),
      testCase "root ADR 0470 I7: Common and Inherited kana marks retain their own scripts" $
        forM_ ['\x30FC', '\xFF9E', '\x3099'] $
          \c -> assertBool (show c) (not (isHanOrKana c)),
      testCase "root ADR 0470 I7: unassigned boundary and surrogate code points are not Han or kana" $
        forM_ ['\x3347A', '\xD800', '\xDFFF', '\x10FFFF'] $
          \c -> assertBool (show c) (not (isHanOrKana c))
    ]
