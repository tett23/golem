{- | Inseparable characters at the line edges (golem-layout ADR 0016):
an ellipsis keeps the full stop after it, and a double dash of U+2015
HORIZONTAL BAR is not split, as a double dash of U+2014 EM DASH is not.
-}
module InseparableSpec (inseparableTests) where

import Control.Monad (forM_)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (compose, fs)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Test.Tasty
import Test.Tasty.HUnit

-- | Every combination of strict kinsoku, vertical writing and hanging punctuation.
envs :: [(String, ComposeEnv)]
envs =
  [ (show (strict, vertical, hanging), (defaultComposeEnv fs) {ceKinsokuStrict = strict, ceVertical = vertical, ceHanging = hanging})
  | strict <- [True, False],
    vertical <- [True, False],
    hanging <- [True, False]
  ]

-- | The text of each line of the paragraph 'あ' × n <> run <> 'い' × 40, set 38 em wide.
linesOf :: ComposeEnv -> Text -> Int -> [Text]
linesOf env run n =
  [ T.concat [bcText c | Box _ c <- lineItems l]
  | l <- brLines (breakParagraph defaultParams (const (38 * fs)) (compose env (T.replicate n "あ" <> run <> T.replicate 40 "い")))
  ]

-- | Does the line end with exactly one of the character (not two or more)?
endsWithOne :: Char -> Text -> Bool
endsWithOne ch t = T.length (T.takeWhileEnd (== ch) t) == 1

-- | The legal breaks among the items, by index.
legal :: [Item] -> [Int]
legal items =
  [ i
  | (i, it) <- zip [0 ..] items,
    case it of
      Penalty _ p _ -> p < infPenalty
      Glue {} -> i > 0 && isBox (items !! (i - 1))
      Box {} -> False
  ]
  where
    isBox = \case Box {} -> True; _ -> False

-- | Is there a legal break between the k-th box and the next (counting from 0)?
breakAfterBox :: [Item] -> Int -> Bool
breakAfterBox items k =
  case drop k [i | (i, Box {}) <- zip [0 :: Int ..] items] of
    (a : b : _) -> any (`elem` legal items) [a + 1 .. b - 1]
    _ -> False

-- | The glue (width, stretch, shrink) between the characters, without the paragraph end.
glues :: Text -> [(Sp, Sp, Sp)]
glues t = [(w, s, h) | Glue w s h <- compose (defaultComposeEnv fs) t, s < filStretch]

inseparableTests :: TestTree
inseparableTests =
  testGroup
    "inseparable characters (golem-layout ADR 0016)"
    [ testCase "U+2015 HORIZONTAL BAR is inseparable, as U+2014 and the ellipsis are" $ do
        charClass '―' @?= Inseparable
        charClass '—' @?= Inseparable
        charClass '…' @?= Inseparable,
      testGroup
        "an ellipsis keeps what follows it off the line start"
        [ testCase (T.unpack run) $
            forM_ envs $ \(name, env) -> forM_ [30 .. 41] $ \n -> do
              let ls = linesOf env run n
                  ctx = name <> " n=" <> show n <> " " <> show ls
              assertBool ctx (not (any (\l -> T.take 1 l `elem` ["。", "」", "、", "？"]) ls))
              assertBool ctx (not (any (endsWithOne '…') ls))
        | run <- ["……。", "……」", "……、", "……？"]
        ],
      testCase "a double dash of U+2015 is not split" $
        forM_ envs $ \(name, env) -> forM_ [30 .. 41] $ \n -> do
          let ls = linesOf env "――。" n
              ctx = name <> " n=" <> show n <> " " <> show ls
          assertBool ctx (not (any (endsWithOne '―') ls))
          assertBool ctx (all (\l -> not ("―" `T.isPrefixOf` l) || "――" `T.isPrefixOf` l) ls)
          assertBool ctx (not (any ("。" `T.isPrefixOf`) ls)),
      testCase "no break between the two bars of a double dash, but one before it" $ do
        let items = compose (defaultComposeEnv fs) "漢――漢"
        [bcText c | Box _ c <- items] @?= ["漢", "―", "―", "漢"]
        breakAfterBox items 0 @?= True
        breakAfterBox items 1 @?= False
        let em = compose (defaultComposeEnv fs) "漢——漢"
        breakAfterBox em 1 @?= False,
      testCase "the default aki set spaces U+2015 as an ideograph" $ do
        glues "漢―" @?= glues "漢漢"
        glues "―漢" @?= glues "漢漢"
    ]
