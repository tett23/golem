{- | Every small paragraph of the line breaking (docs/adr/0209, its
section 1): a run of the parts of 'parts' after 'あ' set some times and
before 'い' set none or a line's worth of times, in lines of 2 to 5 em,
in every composition environment, tier n holding the runs of n parts.

The advances do not come from a font: 'advance' gives the characters
three widths of Latin text, a quarter em to the space and an em to the
Japanese characters, through 'ceAdvance' and 'ceWordAdvance', so that
the items come from the same 'composeInlines' as in a book, the
patterns of 'patternsFor' among them.

The environments are taken in a normal form: an environment whose
setting the characters of the run cannot tell apart from another's is
not made ('normalSettings'). The items do not depend on the width of
the line nor on the glyph expansion, so that the run is composed once
for each 'Group' and broken for every width and expansion of it.
-}
module LineBreakEnum
  ( jaParts,
    latinParts,
    parts,
    hasLatin,
    Setting (..),
    allSettings,
    normalSettings,
    Input (..),
    Group (..),
    groupInputs,
    placings,
    groupsOf,
    normalGroups,
    rawGroups,
    groupT,
    advance,
    composeEnv,
    inlinesOf,
    itemsOf,
    paramsOf,
    lineWidth,
    breakInput,
    lineText,
    renderInput,
    renderCase,
    codeParts,
    codeMark,
    codeSettings,
    normalCodeSettings,
    codeGroupsOf,
    codeGroupT,
    codePadding,
    codeEnv,
    codeEnvWith,
    codeInlinesOf,
    codeItemsOf,
    codeItemsWith,
    breakCodeInput,
  )
where

import Data.Char (isSpace)
import Data.List (intercalate)
import Data.Maybe (isNothing)
import Data.Text (Text)
import Data.Text qualified as T
import Fixtures (fs, sp)
import Golem.Doc.IR qualified as IR
import Golem.Layout.CharClass (isDualCharacter)
import Golem.Layout.Hyphenation.Languages (patternsFor)
import Golem.Layout.Japanese
import Golem.Layout.KnuthPlass
import Golem.Layout.Look (Look (..))
import Golem.TestSupport.Enum

{- | One character of each JLReq class (docs/adr/0209): an ideograph,
hiragana, an opening and a closing bracket, a hyphen, a dividing
punctuation mark, a middle dot, a full stop, a comma, an inseparable
character of both scripts, an iteration mark, a prolonged sound mark, a
small kana, the ideographic space, and U+2014, a double dash when two of
them follow one another and part of a Latin word beside a Latin letter.
-}
jaParts :: [Text]
jaParts = map T.singleton "漢あ「」〜！・。、…ゝーぁ　—"

{- | The Latin parts: words of no, one and two places where the patterns
break them and a word with an explicit hyphen, then a space, a full stop,
the quotation marks of both scripts and a soft hyphen (U+00AD, docs/adr
ADR 0272), which next to the others is at the head, inside and at the end
of a word, and between Japanese characters.
-}
latinParts :: [Text]
latinParts = ["a", "table", "hyphenation", "lime-tree", " ", ".", "“", "”", "\xAD"]

-- | The 24 parts of the runs.
parts :: [Text]
parts = jaParts <> latinParts

{- | Whether a run has a Latin part or a character of both scripts: the
protrusion, the expansion and the language can only matter then. The soft
hyphen is not one: it makes no box (docs/adr ADR 0272), and the normal
form checks that it changes nothing they could.
-}
hasLatin :: [Text] -> Bool
hasLatin = any (\p -> (p `elem` latinParts && p /= "\xAD") || T.any isDualCharacter p)

{- | The composition environment but the glyph expansion: strict kinsoku,
hanging punctuation, protrusion, and the language span around the run.
-}
data Setting = Setting
  { sStrict :: !Bool,
    sHanging :: !Bool,
    sProtrusion :: !Bool,
    sLang :: !(Maybe Text)
  }
  deriving stock (Eq, Ord, Show)

-- | Every setting, the default (strict, no hanging, no protrusion, no span) first.
allSettings :: [Setting]
allSettings = [Setting s h p l | s <- [True, False], h <- [False, True], p <- [False, True], l <- [Nothing, Just "en", Just "ja"]]

{- | The settings of a run in the normal form (docs/adr/0209, its section
1): loose kinsoku only with a prolonged sound mark or a small kana,
hanging punctuation only with a full stop or a comma, protrusion and a
language span only with a Latin part or a character of both scripts.
-}
normalSettings :: [Text] -> [Setting]
normalSettings run = filter normal allSettings
  where
    normal s =
      (sStrict s || any (`elem` ["ー", "ぁ"]) run)
        && (not (sHanging s) || any (`elem` ["。", "、"]) run)
        && (hasLatin run || (not (sProtrusion s) && isNothing (sLang s)))

-- | One paragraph: its setting, its expansion, the width of its lines in em, and its characters.
data Input = Input
  { inSetting :: !Setting,
    inExpansion :: !Bool,
    inWidth :: !Int,
    inPre :: !Int,
    inRun :: ![Text],
    inPost :: !Int
  }
  deriving stock (Eq, Ord, Show)

{- | A run composed once in a setting, with 'あ' set 'gPre' times before it
and 'い' set 'gPost' times after it, and the widths and expansions it is
broken with.
-}
data Group = Group
  { gSetting :: !Setting,
    gPre :: !Int,
    gRun :: ![Text],
    gPost :: !Int,
    gCases :: ![(Int, Bool)]
  }
  deriving stock (Eq, Show)

-- | The inputs of a group, in the order of its cases.
groupInputs :: Group -> [Input]
groupInputs g = [Input (gSetting g) e w (gPre g) (gRun g) (gPost g) | (w, e) <- gCases g]

{- | The characters before and after the run, with the widths up to the
one given (from 2 em) they are broken in: before it, from none to one
fewer than the width, so that the run starts at every place of the
line; after it, none or the width, so that the run is on the last line
and on the one before it.
-}
placings :: Int -> [(Int, Int, [Int])]
placings maxWidth =
  [(pre, 0, [w | w <- widths, pre < w]) | pre <- [0 .. maxWidth - 1]]
    <> [(pre, w, [w]) | w <- widths, pre <- [0 .. w - 1]]
  where
    widths = [2 .. maxWidth]

-- | The groups of a run in the settings given, in lines up to the width given: the expansion only where the run has a Latin part or a character of both scripts.
groupsOf :: Int -> [Setting] -> [Text] -> [Group]
groupsOf maxWidth settings run =
  [ Group s pre run post [(w, e) | w <- ws, e <- expansions]
  | s <- settings,
    (pre, post, ws) <- placings maxWidth
  ]
  where
    expansions = if hasLatin run then [False, True] else [False]

-- | The groups of a run in the normal form, in lines up to the width given.
normalGroups :: Int -> [Text] -> [Group]
normalGroups maxWidth run = groupsOf maxWidth (normalSettings run) run

{- | The groups of a run in the settings the normal form leaves out, each
with and without the expansion, and with the setting of the normal form
whose values they must give: strict where the run has no prolonged sound
mark and no small kana, no hanging where it has no full stop and no
comma, no protrusion and no span where it has no Latin part and no
character of both scripts. Without a Latin part and a character of both
scripts, the expansion is the one the normal form leaves out.
-}
rawGroups :: Int -> [Text] -> [(Group, Setting)]
rawGroups maxWidth run =
  [ (g {gCases = [(w, e) | w <- widthsOf g, e <- [False, True], left (gSetting g) e]}, normalOf (gSetting g))
  | g <- groupsOf maxWidth allSettings run,
    any (left (gSetting g)) [False, True]
  ]
  where
    widthsOf g = foldr ((\x acc -> x : filter (/= x) acc) . fst) [] (gCases g)
    normal = normalSettings run
    -- whether the normal form leaves out a setting with an expansion
    left s e = s `notElem` normal || (e && not (hasLatin run))
    normalOf s =
      Setting
        { sStrict = sStrict s || not (any (`elem` ["ー", "ぁ"]) run),
          sHanging = sHanging s && any (`elem` ["。", "、"]) run,
          sProtrusion = sProtrusion s && hasLatin run,
          sLang = if hasLatin run then sLang s else Nothing
        }

{- | Every group, tier n holding those of the runs of n parts, in the
order of the runs.
-}
groupT :: ([Text] -> [Group]) -> Tiers Group
groupT groups = let Tiers xss = listsOf (Tiers [parts]) in Tiers (map (concatMap groups) xss)

{- | The advance of a character in em (docs/adr/0209): Latin text a
quarter em for i, l, t, f, the full stop, the comma, the hyphen and the
apostrophe, three quarters for m and w, a half for the rest, the
characters of both scripts in a Latin word among them, as one
character of a word alone ('ceWordCharAdvance', docs/adr/0222); the
space a quarter em; the Japanese characters an em.
-}
advance :: Bool -> Char -> Rational
advance latin c
  | isSpace c && c /= '\x3000' = 1 / 4
  | not latin = 1
  | c `elem` ("iltf.,-'" :: String) = 1 / 4
  | c `elem` ("mw" :: String) = 3 / 4
  | otherwise = 1 / 2

-- | The composition environment of a setting, vertical or not.
composeEnv :: Bool -> Setting -> ComposeEnv
composeEnv vertical s =
  (defaultComposeEnv fs)
    { ceKinsokuStrict = sStrict s,
      ceVertical = vertical,
      ceHanging = sHanging s,
      ceProtrusion = sProtrusion s,
      cePatterns = patternsFor,
      ceAdvance = \lk c -> advance (latinIn lk c) c,
      ceWordAdvance = \_ t -> sum (map (advance True) (T.unpack t)),
      ceWordCharAdvance = \_ _ -> advance True
    }
  where
    latinIn :: Look -> Char -> Bool
    latinIn lk c = lookClass lk c == Western

-- | The inlines of a paragraph: 'あ' before the run, the run in its language span, 'い' after it.
inlinesOf :: Setting -> Int -> [Text] -> Int -> [IR.Inline]
inlinesOf s pre run post =
  [IR.Text sp (T.replicate pre "あ") | pre > 0]
    <> [maybe text (\l -> IR.Lang sp l [text]) (sLang s) | not (null run)]
    <> [IR.Text sp (T.replicate post "い") | post > 0]
  where
    text = IR.Text sp (T.concat run)

-- | The items of a group, vertical or not.
itemsOf :: Bool -> Setting -> Int -> [Text] -> Int -> [Item]
itemsOf vertical s pre run post = fst (composeInlines (composeEnv vertical s) (inlinesOf s pre run post))

{- | The parameters of the breaking: those of 'defaultParams', the
expansion of docs/adr/0209 (a limit of 20 and a step of 5 permille), and
the protrusion where hanging punctuation or protrusion is on, as
golem-typeset sets it. The expansion is given only where a box takes it,
and the protrusion only where an item protrudes: without them,
'breakParagraph' does the same with either, so that the parameters of
two inputs are the same where their breaking is.
-}
paramsOf :: Setting -> Bool -> [Item] -> Params
paramsOf s e its =
  defaultParams
    { pExpansion = if e && or [bcExpandable c | Box _ c <- its] then Just (20, 5) else Nothing,
      pProtrusion = (sProtrusion s || sHanging s) && protrudes
    }
  where
    protrudes = or [bcProtrudeStart c /= 0 || bcProtrudeEnd c /= 0 | Box _ c <- its] || or [q /= 0 | Penalty _ _ h <- its, q <- case h of PatternHyphen x -> [x]; SoftHyphen x -> [x]; _ -> []]

-- | The width of the lines of an input.
lineWidth :: Input -> Sp
lineWidth i = fromIntegral (inWidth i) * fs

-- | The items, the parameters and the breaks of an input.
breakInput :: Input -> ([Item], Params, Breaks)
breakInput i =
  let its = itemsOf False (inSetting i) (inPre i) (inRun i) (inPost i)
      ps = paramsOf (inSetting i) (inExpansion i) its
   in (its, ps, breakParagraph ps (const (lineWidth i)) its)

-- | The characters of the boxes of a line.
lineText :: Line -> Text
lineText l = T.concat [bcText c | Box _ c <- lineItems l]

-- | The input as the Haskell expression that makes it.
renderInput :: Input -> String
renderInput = show

{- | A test case for InseparableSpec or LineBreakingSpec that fixes the
lines the input breaks into now.
-}
renderCase :: String -> Input -> String
renderCase name input =
  let (_, _, br) = breakInput input
   in intercalate
        "\n"
        [ "testCase " <> show name <> " $ do",
          "  let (_, _, br) = breakInput (" <> renderInput input <> ")",
          "  map lineText (brLines br)",
          "    @?= " <> show (map lineText (brLines br))
        ]

-- * the runs of code (golem-layout ADR 0034, its section 5)

{- | The 18 parts of the runs of code: Japanese characters of the classes
the breaks of code tell apart, an ideograph, hiragana, an opening and a
closing bracket, a full stop, a comma, a prolonged sound mark, a small
kana and an ellipsis (a character of both scripts); Latin text of one
and two letters, a slash, a low line, a quotation mark and a space
(golem-layout ADR 0034, its section 5); a hyphen-minus sign, a full stop
and a digit, the last for the places between two digits (golem-layout
ADR 0045, its section 3).
-}
codeParts :: [Text]
codeParts = map T.singleton "漢あ「」。、ーぁ…" <> ["a", "ab", "/", "_", "\"", " ", "-", ".", "1"]

-- | The wrap mark of the code of the runs: the default of the character style code.
codeMark :: Text
codeMark = "⏎"

{- | The settings of the runs of code: the strictness of the kinsoku and
the language span around the run; no hanging, protrusion nor expansion,
which the boxes of code do not take.
-}
codeSettings :: [Setting]
codeSettings = [Setting s False False l | s <- [True, False], l <- [Nothing, Just "en", Just "ja"]]

{- | The settings of a run of code in the normal form (docs/adr/0209):
loose kinsoku only with a prolonged sound mark or a small kana, a
language span only with a character of both scripts.
-}
normalCodeSettings :: [Text] -> [Setting]
normalCodeSettings run = filter normal codeSettings
  where
    normal s =
      (sStrict s || any (`elem` ["ー", "ぁ"]) run)
        && (any (T.any isDualCharacter) run || isNothing (sLang s))

-- | The groups of a run of code in the normal form, in lines up to the width given, without the expansion.
codeGroupsOf :: Int -> [Text] -> [Group]
codeGroupsOf maxWidth run =
  [ Group s pre run post [(w, False) | w <- ws]
  | s <- normalCodeSettings run,
    (pre, post, ws) <- placings maxWidth
  ]

-- | Every group of the runs of code, tier n holding those of the runs of n parts.
codeGroupT :: Int -> Tiers Group
codeGroupT maxWidth = let Tiers xss = listsOf (Tiers [codeParts]) in Tiers (map (concatMap (codeGroupsOf maxWidth)) xss)

{- | The padding of the runs of code that have it: the default of the
character style code, 0.25zw (golem-layout ADR 0048, its section
「テスト設計」).
-}
codePadding :: Sp
codePadding = Sp (unSp fs `div` 4)

{- | The composition environment of the runs of code: that of 'composeEnv',
the character style code with the wrap mark 'codeMark' and no padding,
and the advance of a text of code each of its characters by its class, as
'advance' gives it.
-}
codeEnv :: Bool -> Setting -> ComposeEnv
codeEnv = codeEnvWith 0

-- | 'codeEnv' with the padding of the character style code given (golem-layout ADR 0048).
codeEnvWith :: Sp -> Bool -> Setting -> ComposeEnv
codeEnvWith pad vertical s =
  (composeEnv vertical s)
    { ceWordAdvance = \lk t -> sum [advance (lookClass lk c == Western) c | c <- T.unpack t],
      ceRestyle = \lk -> \case
        IR.CharStyle _ "code" _ -> lk {lkCode = True, lkWrapMark = codeMark, lkPadding = pad}
        _ -> lk
    }

-- | The inlines of a paragraph of code: 'あ' before the run, the run of code in its language span, 'い' after it.
codeInlinesOf :: Setting -> Int -> [Text] -> Int -> [IR.Inline]
codeInlinesOf s pre run post =
  [IR.Text sp (T.replicate pre "あ") | pre > 0]
    <> [maybe code (\l -> IR.Lang sp l [code]) (sLang s) | not (null run)]
    <> [IR.Text sp (T.replicate post "い") | post > 0]
  where
    code = IR.CharStyle sp "code" [IR.Text sp (T.concat run)]

-- | The items of a group of code, vertical or not, without padding.
codeItemsOf :: Bool -> Setting -> Int -> [Text] -> Int -> [Item]
codeItemsOf = codeItemsWith 0

-- | 'codeItemsOf' with the padding of the character style code given (golem-layout ADR 0048).
codeItemsWith :: Sp -> Bool -> Setting -> Int -> [Text] -> Int -> [Item]
codeItemsWith pad vertical s pre run post = fst (composeInlines (codeEnvWith pad vertical s) (codeInlinesOf s pre run post))

-- | The items, the parameters and the breaks of an input of code.
breakCodeInput :: Input -> ([Item], Params, Breaks)
breakCodeInput i =
  let its = codeItemsOf False (inSetting i) (inPre i) (inRun i) (inPost i)
      ps = paramsOf (inSetting i) False its
   in (its, ps, breakParagraph ps (const (lineWidth i)) its)
