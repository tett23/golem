module Main (main) where

import Data.Either (isLeft, isRight)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Regex
import Suites (boostCases, pcreCases)
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main =
  defaultMain $
    testGroup
      "golem-regex"
      [ dialectTests,
        leftmostTests,
        assertionTests,
        errorTests,
        performanceTests,
        suiteTests
      ]

-- | The matches of a pattern that compiles.
m :: Text -> Text -> [(Int, Int)]
m p s = either (\e -> error ("compile " <> show p <> ": " <> show e)) (`matches` s) (compile p)

-- | Whether a pattern matches somewhere.
hits :: Text -> Text -> Bool
hits p s = not (null (m p s))

-- | The offset of a compile error.
errorAt :: Text -> Maybe Int
errorAt p = either (Just . reOffset) (const Nothing) (compile p)

-- | One row of the dialect table: a pattern, subjects it matches, subjects it does not.
row :: String -> Text -> [Text] -> [Text] -> TestTree
row name p yes no =
  testCase name $ do
    mapM_ (\s -> assertBool (show p <> " matches " <> show s) (hits p s)) yes
    mapM_ (\s -> assertBool (show p <> " does not match " <> show s) (not (hits p s))) no

dialectTests :: TestTree
dialectTests =
  testGroup
    "the dialect table"
    [ testCase "[0-9]+ finds the runs of digits" $ m "[0-9]+" "a12b345" @?= [(1, 3), (4, 7)],
      row "a character" "a" ["a", "bab"] ["b", "A"],
      row "a character outside ASCII" "漢" ["漢字"] ["字"],
      row "an escaped character that is not alphanumeric" "\\.\\\\\\[\\~\\$" [".\\[~$"] ["a\\[~$"],
      row "\\t and \\n" "a\\tb\\nc" ["a\tb\nc"] ["a b c", "a\tb c"],
      row "\\xHH" "\\x41\\x7e" ["A~"] ["a~"],
      row "\\x{H...}" "\\x{3042}\\x{1F600}" ["あ\x1F600"] ["あ"],
      testCase ". does not match \\n" $ m "a.c" "abc a\nc" @?= [(0, 3)],
      testCase "\\n matches a line break" $ m "\\n" "a\nb" @?= [(1, 2)],
      row "a class" "[abc]" ["b"] ["d"],
      row "a negated class" "[^abc]" ["d", "\n"] ["abc"],
      row "a range in a class" "[a-c]+" ["b"] ["d"],
      row "a range written with \\x{...}" "^[\\x{3041}-\\x{3096}]+$" ["ひらがな"] ["カタカナ", "かな漢字"],
      row "a class escape in a class" "^[\\d\\s]+$" ["1 ２\x3000"] ["1a"],
      row "] first in a class is a character" "[]a]" ["]"] ["b"],
      row "- at the end of a class is a character" "[a-]" ["-"] ["b"],
      row "[:alpha:]" "^[[:alpha:]]+$" ["abc漢字かなÉ"] ["a1", "a_"],
      row "[:digit:]" "^[[:digit:]]+$" ["12３４"] ["1a", "Ⅳ"],
      row "[:alnum:]" "^[[:alnum:]]+$" ["a1漢３"] ["a-1"],
      row "[:upper:]" "^[[:upper:]]+$" ["ABCÉ"] ["Ab"],
      row "[:lower:]" "^[[:lower:]]+$" ["abcé"] ["aB"],
      row "[:space:]" "^[[:space:]]+$" [" \t\x3000\xA0"] ["a "],
      testCase "[:punct:] matches 、" $ m "[[:punct:]]" "あ、い" @?= [(1, 2)],
      row "[:punct:] is the category P" "[[:punct:]]" ["、", "。", "「", "!"] ["+", "$", "a"],
      row "a POSIX class beside a range" "[[:alpha:]0-9]" ["a", "0"] ["-"],
      testCase "\\d matches full-width digits" $ m "\\d+" "１２" @?= [(0, 2)],
      row "\\d" "\\d" ["0", "９", "٣"] ["a", "Ⅳ", "一"],
      row "\\D" "^\\D+$" ["abc一"] ["a1"],
      testCase "\\w matches kanji and kana" $ m "\\w+" "漢字かな" @?= [(0, 4)],
      row "\\w" "^\\w+$" ["a_1漢かなカナ\x3099"] ["a-b", "a b", "、"],
      row "\\W" "^\\W+$" ["- 、"] ["a"],
      testCase "\\s matches U+3000" $ m "\\s" "a\x3000\&b" @?= [(1, 2)],
      row "\\s" "\\s" [" ", "\t", "\n", "\x85", "\xA0", "\x2028", "\x3000"] ["a", "\x200B"],
      row "\\S" "^\\S+$" ["abc"] ["a b"],
      row "\\l" "^\\l+$" ["abcé"] ["aB", "漢"],
      row "\\u" "^\\u+$" ["ABCÉ"] ["Ab", "漢"],
      testCase "\\p{P} and \\p{Punctuation} give the same matches" $
        m "\\p{P}" "a、b。c「d」" @?= m "\\p{Punctuation}" "a、b。c「d」",
      row "\\p{L}" "^\\p{L}+$" ["abc漢"] ["1"],
      row "\\p{Letter}" "^\\p{Letter}+$" ["abc漢"] ["1"],
      row "\\p{Lu}" "^\\p{Lu}+$" ["AB"] ["a"],
      row "\\p{Nd}" "^\\p{Nd}+$" ["1２"] ["Ⅳ"],
      row "\\p{N}" "^\\p{N}+$" ["1２Ⅳ"] ["a"],
      row "\\p{Number}" "^\\p{Number}+$" ["1２Ⅳ"] ["a"],
      row "\\p{M} and \\p{Mark}" "^\\p{M}\\p{Mark}$" ["\x3099\x0301"] ["aa"],
      row "\\p{S} and \\p{Symbol}" "^\\p{S}\\p{Symbol}$" ["+$"] ["+a"],
      row "\\p{Z} and \\p{Separator}" "^\\p{Z}\\p{Separator}$" [" \x3000"] ["\t "],
      row "\\p{C} and \\p{Other}" "^\\p{C}\\p{Other}$" ["\t\x200B"] ["  "],
      row "\\P{L}" "^\\P{L}+$" ["1、"] ["a"],
      row "\\p{...} in a class" "^[\\p{Lu}\\d]+$" ["A1"] ["a"],
      testCase "* is greedy" $ m "a*" "aaa" @?= [(0, 3)],
      testCase "+ is greedy" $ m "ba+" "baaa" @?= [(0, 4)],
      testCase "? is greedy" $ m "ab?" "ab" @?= [(0, 2)],
      testCase "{n}" $ m "a{2}" "aaaaa" @?= [(0, 2), (2, 4)],
      testCase "{n,}" $ m "a{2,}" "a aa aaaa" @?= [(2, 4), (5, 9)],
      testCase "{n,m}" $ m "a{2,3}" "aaaaaaa" @?= [(0, 3), (3, 6)],
      testCase "*? is lazy" $ m "a*?b" "aab" @?= [(0, 3)],
      testCase "+? is lazy" $ m "a+?" "aaa" @?= [(0, 1), (1, 2), (2, 3)],
      testCase "?? is lazy" $ m "ab??" "ab" @?= [(0, 1)],
      testCase "{n,}? is lazy" $ m "a{2,}?" "aaaaa" @?= [(0, 2), (2, 4)],
      testCase "{n,m}? is lazy" $ m "a{1,3}?" "aa" @?= [(0, 1), (1, 2)],
      testCase "| and (...)" $ m "(ab|cd)+" "abcdx" @?= [(0, 4)],
      testCase "(?:...)" $ m "(?:ab)+" "ababa" @?= [(0, 4)],
      testCase "an empty alternative" $ m "a(b|)c" "ac abc" @?= [(0, 2), (3, 6)],
      testCase "a { that does not begin a quantifier is a character" $ m "a{x}" "a{x}" @?= [(0, 4)],
      testCase "} is a character" $ m "a}" "a}" @?= [(0, 2)],
      testCase "(?i)abc matches ABC" $ m "(?i)abc" "ABC" @?= [(0, 3)],
      row "(?i) folds classes and ranges" "(?i)^[a-c]+$" ["aBC"] ["d"],
      row "(?i) with a negated class" "(?i)[^a]" ["b"] ["a", "A"],
      row "(?i) folds a character outside ASCII" "(?i)é" ["É"] ["e"]
    ]

leftmostTests :: TestTree
leftmostTests =
  testGroup
    "leftmost-first and empty matches"
    [ testCase "a|ab takes the first alternative" $ m "a|ab" "ab" @?= [(0, 1)],
      testCase "ab|a takes the first alternative" $ m "ab|a" "ab" @?= [(0, 2)],
      testCase "a*?b" $ m "a*?b" "aab" @?= [(0, 3)],
      testCase "<.+?>" $ m "<.+?>" "<a><b>" @?= [(0, 3), (3, 6)],
      testCase "an empty match is not reported" $ m "a*" "baa" @?= [(1, 3)],
      testCase "a pattern that only matches empty" $ m "x?" "abc" @?= [],
      testCase "the next search starts at the end of a match" $ m "aa" "aaaaa" @?= [(0, 2), (2, 4)],
      testCase "positions count characters, not bytes" $ m "c" "漢字c" @?= [(2, 3)],
      testCase "an empty subject" $ m "a" "" @?= []
    ]

assertionTests :: TestTree
assertionTests =
  testGroup
    "assertions"
    [ testCase "lookbehind and lookahead" $ m "(?<=第)[0-9]+(?=章)" "第12章と第3節" @?= [(1, 3)],
      testCase "negative lookbehind and lookahead" $ m "(?<!\\d)\\d{2}(?!\\d)" "1 22 333" @?= [(2, 4)],
      testCase "a lookbehind at the start of the subject" $ m "(?<=a)b" "bab" @?= [(2, 3)],
      testCase "a lookbehind with alternatives of the same length" $ m "(?<=ab|cd)e" "abe cde xye" @?= [(2, 3), (6, 7)],
      testCase "a lookbehind with a fixed repeat" $ m "(?<=a{2})b" "ab aab" @?= [(5, 6)],
      testCase "a lookbehind with a nested lookahead" $ m "(?<=(?=a)..)c" "abc bbc" @?= [(2, 3)],
      testCase "a lookahead reaching past the match" $ m "a(?=.*z)" "abaz a" @?= [(0, 1), (2, 3)],
      testCase "\\K" $ m "第\\K[0-9]+" "第12章" @?= [(1, 3)],
      testCase "the last \\K wins" $ m "a\\Kb\\Kc" "abc" @?= [(2, 3)],
      testCase "\\K leaving an empty range" $ m "a\\K" "aa" @?= [],
      testCase "^ is the start of the paragraph" $ m "^a" "aa" @?= [(0, 1)],
      testCase "$ is the end of the paragraph" $ m "a$" "aa" @?= [(1, 2)],
      testCase "^ is not the start of a line" $ m "^b" "a\nb" @?= [],
      testCase "$ is not the end of a line" $ m "a$" "a\nb" @?= [],
      testCase "\\b" $ m "\\bab\\b" "ab cab ab、" @?= [(0, 2), (7, 9)],
      testCase "\\b between kanji and a space" $ m "\\b漢" "漢 漢字" @?= [(0, 1), (2, 3)],
      testCase "\\B" $ m "\\Bb" "ab b" @?= [(1, 2)],
      testCase "a quantified lookahead" $ m "(?=a)*a" "a" @?= [(0, 1)]
    ]

errorTests :: TestTree
errorTests =
  testGroup
    "errors"
    ( [ testCase (T.unpack p) (errorAt p @?= Just at)
      | (p, at) <-
          [ ("\\1", 0),
            ("\\9", 0),
            ("\\k<n>", 0),
            ("(?<n>a)", 0),
            ("(?P<n>a)", 0),
            ("(?>a)", 0),
            ("a*+", 2),
            ("a++", 2),
            ("a?+", 2),
            ("(?(1)a)", 0),
            ("(?#c)", 0),
            ("(?s)a", 0),
            ("(?m)a", 0),
            ("(?x)a", 0),
            ("(?-i)a", 0),
            ("(?i:a)", 0),
            ("a(?i)bc", 1),
            ("(?i)(?i)a", 4),
            ("\\Q", 0),
            ("\\E", 0),
            ("\\X", 0),
            ("\\h", 0),
            ("\\v", 0),
            ("\\R", 0),
            ("\\A", 0),
            ("\\z", 0),
            ("\\Z", 0),
            ("\\G", 0),
            ("\\y", 0),
            ("a\\0", 1),
            ("\\p{Han}", 0),
            ("\\p{Hiragana}", 0),
            ("\\p{Nope}", 0),
            ("\\p{lu}", 0),
            ("\\pL", 0),
            ("\\p{L", 0),
            ("(?<=a+)b", 0),
            ("(?<=a|bc)d", 0),
            ("(?<!a*)b", 0),
            ("x(?<=a{1,2})b", 1),
            ("(?=\\Ka)", 3),
            ("~m", 0),
            ("a~", 1),
            ("[~]", 1),
            ("[z-a]", 1),
            ("[\\d-z]", 1),
            ("[[:word:]]", 1),
            ("[[:^alpha:]]", 1),
            ("[\\b]", 1),
            ("a{3,2}", 1),
            ("a{70000}", 1),
            ("(a", 0),
            ("a)", 1),
            ("[a", 0),
            ("\\x4", 0),
            ("\\x{110000}", 0),
            ("\\x{D800}", 0),
            ("\\x{}", 0),
            ("a\\", 1),
            ("", 0),
            ("(?i)", 0),
            ("*a", 0),
            ("a|*", 2),
            ("(*a)", 1),
            ("a**", 2),
            ("a{2}{3}", 4),
            ("(a{1000}){1000}", 9),
            (T.replicate 10001 "a", 0)
          ]
      ]
        <> [ testCase "\\~ compiles" $ assertBool "Right" (isRight (compile "\\~")),
             testCase "(?<=ab|cd)e compiles" $ assertBool "Right" (isRight (compile "(?<=ab|cd)e")),
             testCase "a program of 10000 instructions compiles" $ assertBool "Right" (isRight (compile (T.replicate 9999 "a"))),
             testCase "an error has a message" $ assertBool "message" (either (not . T.null . reMessage) (const False) (compile "\\1")),
             testCase "the message of a back reference" $ either (Just . reMessage) (const Nothing) (compile "\\1") @?= Just "後方参照は使えません",
             testCase "the message of a script" $
               either (T.isInfixOf "\\x{4E00}-\\x{9FFF}" . reMessage) (const False) (compile "\\p{Han}") @? "names the range",
             testCase "the message of ~" $
               either (T.isInfixOf "\\~" . reMessage) (const False) (compile "~m") @? "names \\~",
             testCase "a variable lookbehind is an error" $ assertBool "Left" (isLeft (compile "(?<=a?)b"))
           ]
    )

performanceTests :: TestTree
performanceTests =
  testGroup
    "steps"
    [ bounded "(a*)*b",
      bounded "(a|aa)*c",
      bounded "(?=(a+))*b",
      bounded "(a+)+$x",
      testCase "Eq and Show compare the source" $ do
        compile "a+" @?= compile "a+"
        assertBool "different" (compile "a+" /= compile "a*")
    ]
  where
    subject = T.replicate 10000 "a"
    bounded p = testCase (T.unpack p <> " over 10000 a") $ case compile p of
      Left e -> assertFailure (show e)
      Right r -> do
        let (ms, steps) = matchesCounting r subject
        ms @?= matches r subject
        assertBool ("steps " <> show steps) (steps <= programSize r * 10001 * 4)

suiteTests :: TestTree
suiteTests =
  testGroup
    "examples from PCRE2 and Boost.Regex"
    [ testGroup "PCRE2 testinput1" [testCase ("testinput1:" <> show pl <> " subject " <> show sl) (m p s @?= e) | (pl, sl, p, s, e) <- pcreCases],
      testGroup "Boost.Regex" [testCase (f <> ":" <> show l) (m p s @?= e) | (f, l, p, s, e) <- boostCases]
    ]
