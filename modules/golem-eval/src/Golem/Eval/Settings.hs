{- | The file settings (docs/adr ADR 0014): the @manifest, @style-def and
@hyphenation-exceptions lines at the top of a file, which override keys
of [source], define styles and list hyphenation exceptions (docs/adr ADR
0272) for that file alone.
-}
module Golem.Eval.Settings
  ( settingCommands,
    isSettingCommand,
    fileHeader,
    fileSettings,
    fileStyles,
    fileHyphenationExceptions,
  )
where

import Data.List (nub, sortOn)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Parser.AST qualified as A
import Golem.Project.Style
import Golem.Syntax
import Golem.Syntax.LanguageTag (isLanguageTag)

-- | The commands of the file settings.
settingCommands :: [Text]
settingCommands = ["manifest", "style-def", "hyphenation-exceptions"]

isSettingCommand :: A.Located A.Block -> Bool
isSettingCommand = \case
  A.Located _ (A.BlockCommand (A.Located _ n) _ _) -> n `elem` settingCommands
  _ -> False

{- | The @manifest and @style-def lines at the top of a file, and the blocks
after them. Settings at the start of an attribute group are taken out of
it: the rest of the group stays, or its target alone when nothing is
left.
-}
fileHeader :: [A.Located A.Block] -> ([A.Located A.Block], [A.Located A.Block])
fileHeader = go []
  where
    go acc = \case
      (b : bs)
        | isSettingCommand b -> go (acc <> [b]) bs
      (A.Located sp (A.Attributed cmds t) : bs)
        | (pre@(_ : _), post) <- span isSettingCommand cmds ->
            let rest = case (post, t) of
                  ([], Just tb) -> [tb]
                  ([], Nothing) -> []
                  (c : _, _) -> [A.Located (mkSpan (spanFile sp) (spanStart (A.locSpan c)) (spanEnd sp)) (A.Attributed post t)]
             in (acc <> pre, rest <> bs)
      bs -> (acc, bs)

err :: Text -> SrcSpan -> Text -> Diagnostic
err code = diagnostic code Error

{- | G02114: @manifest and @style-def are read before the evaluation, so
an argument *[式] or **[式] is not spread (docs/adr ADR 0112).
-}
spreadBeforeEvaluation :: Text -> SrcSpan -> Diagnostic
spreadBeforeEvaluation name sp = diagnostic "G02114" Error sp (name <> " は評価の前に読むので、*[式] と **[式] を書けません")

{- | The keyword arguments of a setting: (key, span, value) of each key
written once, and the diagnostics of the others in the order written
(docs/adr ADR 0132): G02116 for a value that is no word nor string,
G02077 for each argument of a key after its first. A key written twice
is left out as a whole.
-}
keywordArgs :: [A.Located A.Argument] -> ([(Text, SrcSpan, LocalValue)], [Diagnostic])
keywordArgs args =
  let kws = [(k, sp, v) | A.Located sp (A.Keyword (A.Located _ k) v) <- args]
      keys = [k | (k, _, _) <- kws]
      repeated i k = k `elem` take i keys
      dup = nub [k | (i, k) <- zip [0 :: Int ..] keys, repeated i k]
      values = [(k, sp, lv) | (k, sp, v) <- kws, k `notElem` dup, Just lv <- [localValue v]]
      diags =
        concat
          [ [notWordDiagnostic sp | isNothing (localValue v)] <> [err "G02077" sp ("同じキーを二度書いています: " <> k) | repeated i k]
          | (i, (k, sp, v)) <- zip [0 :: Int ..] kws
          ]
   in (values, diags)

-- | A value or a positional argument written as a word or a string.
localValue :: A.ArgValue -> Maybe LocalValue
localValue = \case
  A.Word w -> Just (LocalWord w)
  A.StringLit s -> Just (LocalString s)
  _ -> Nothing

-- | G02116: a value or a positional argument that is no word nor string (docs/adr ADR 0132).
notWordDiagnostic :: SrcSpan -> Diagnostic
notWordDiagnostic sp = err "G02116" sp "値は語か文字列で書きます"

-- | G02097 at the first block of a body (docs/adr ADR 0132).
bodyDiagnostics :: Text -> [A.Located A.Block] -> [Diagnostic]
bodyDiagnostics name body = [err "G02097" bsp (name <> " は本体を持てません") | A.Located bsp _ <- take 1 body]

-- | The diagnostics of the arguments in the order they are written.
inOrder :: [Diagnostic] -> [Diagnostic]
inOrder = sortOn (spanStart . diagSpan)

{- | Each @manifest applied in order with a table of the keys of [source]
(docs/adr ADR 0013) to the settings of the context, and the diagnostics.
A @manifest with a body (G02097) or without arguments (G02115) is left
out. Otherwise a wrong argument is left out (G02052, G02077, G02114,
G02116; docs/adr ADR 0132) and the others take effect. A body does not
hide the errors of the arguments: each cause has its code (docs/adr ADR
0132; the audit of 2026-11-04, F-44), but the keys of a @manifest left
out are not checked against the table (G02050, G02051).
-}
fileSettings :: [(Text, Text -> Either Text (s -> s))] -> s -> [A.Located A.Block] -> (s, [Diagnostic])
fileSettings table s0 header = foldl step (s0, []) [(sp, args, body) | A.Located sp (A.BlockCommand (A.Located _ "manifest") args body) <- header]
  where
    shape = "@manifest には key=value だけを書きます"
    step (s, ds) (sp, args, body)
      | null args = (s, ds <> [err "G02115" sp "@manifest には key=value を一つ以上書きます"] <> bodyDiagnostics "@manifest" body)
      | not (null body) = (s, ds <> argDiags <> bodyDiagnostics "@manifest" body)
      | otherwise =
          let apply (s', ds') (k, ksp, v) = case lookup k table of
                Nothing -> (s', ds' <> [err "G02050" ksp (notOverridable k)])
                Just f -> case f (valueText v) of
                  Left m -> (s', ds' <> [err "G02051" ksp m])
                  Right g -> (g s', ds')
              (s'', applied) = foldl apply (s, []) kvs
           in (s'', ds <> argDiags <> applied)
      where
        others = [asp | A.Located asp a <- args, not (isKeyword a), not (isSplat a)]
        spreads = [asp | A.Located asp a <- args, isSplat a]
        (kvs, kwDiags) = keywordArgs args
        argDiags = inOrder ([spreadBeforeEvaluation "@manifest" asp | asp <- spreads] <> [err "G02052" asp shape | asp <- others] <> kwDiags)
    isKeyword = \case
      A.Keyword {} -> True
      _ -> False
    isSplat = \case
      A.SplatPositional _ -> True
      A.SplatKeyword _ -> True
      _ -> False
    valueText = \case
      LocalWord w -> w
      LocalString t -> t
    notOverridable k =
      "ファイルの中で上書きできない設定です: "
        <> k
        <> case map fst table of
          [] -> ""
          keys -> "。上書きできるのは " <> T.intercalate "、" keys <> " です"

-- | One @style-def read: its span, kind, name and keys, or a regex style for a paragraph style (docs/adr ADR 0015).
data Def
  = Def SrcSpan StyleKind Text (Either CharStyleDef ParaStyleDef)
  | RegexDef SrcSpan Text RegexStyleDef

{- | The styles of the @style-def lines, checked against style.toml, and the
diagnostics. A wrong definition is dropped as a whole. The regex styles
are checked after the character and the paragraph styles, each at its
line; a wrong one is dropped and the others take effect (docs/adr ADR
0015).
-}
fileStyles :: Style -> [A.Located A.Block] -> (LocalStyles, [Diagnostic])
fileStyles style header =
  let (defs, ds1) = foldl readDef ([], []) [(sp, args, body) | A.Located sp (A.BlockCommand (A.Located _ "style-def") args body) <- header]
      local0 = LocalStyles (Map.fromList [(n, d) | Def _ _ n (Left d) <- defs]) (Map.fromList [(n, d) | Def _ _ n (Right d) <- defs]) Map.empty Map.empty
      spanOf kind n = listToMaybe [sp | Def sp k n' _ <- defs, k == kind, n' == n]
      (local, ds2) = checked local0 []
      -- the checks again until no definition is dropped
      checked ls acc =
        let cs = checkLocalStyles style ls
            ds = [err code (positionFor code ls name) m | (code, name, m) <- cs]
            wrong = [localsOf ls name | (code, name, _) <- cs, code `elem` ["G03006", "G03008", "G03013", "G03118"]]
            ls' =
              ls
                { lsCharStyles = foldr Map.delete (lsCharStyles ls) (concatMap snd wrong),
                  lsParaStyles = foldr Map.delete (lsParaStyles ls) (concatMap fst wrong)
                }
            acc' = nub (acc <> ds)
         in if ls' == ls then (ls, acc') else checked ls' acc'
      {- the paragraph and the character styles of the file a name stands
      for: the name itself, or the first name of its based-on chain the
      file defines -}
      localsOf ls name =
        let combined = withLocalStyles style ls
            paraChain = chainBy (\m -> Map.lookup m (stParaStyles combined) >>= paraParentOf m) name
            charChain = chainBy (\m -> Map.lookup m (stCharStyles combined) >>= csBasedOn) name
         in (take 1 (filter (`Map.member` lsParaStyles ls) paraChain), take 1 (filter (`Map.member` lsCharStyles ls) charChain))
      paraParentOf m d = if m == "body" then Nothing else Just (fromMaybe "body" (psBasedOn d))
      chainBy parent = go []
        where
          go seen m
            | m `elem` seen = []
            | otherwise = m : maybe [] (go (m : seen)) (parent m)
      -- G03118 is at the argument of align of the definition (docs/adr/0189)
      positionFor code ls name = case code of
        "G03118" | ksp : _ <- [ksp | (Def _ ParagraphKind n _, kvs) <- defKeys, n == name, (k, ksp, _) <- kvs, k == "align"] -> ksp
        _ -> positionOf ls name
      -- where a diagnostic about a name is reported: the @style-def of the name it stands for
      positionOf ls name =
        let (ps, cs) = localsOf ls name
            candidates =
              [sp | m <- ps, Just sp <- [spanOf ParagraphKind m]]
                <> [sp | m <- cs, Just sp <- [spanOf CharacterKind m]]
                <> [sp | Def sp _ _ _ <- defs]
         in fromMaybe (mkSpan (FileId 0) 0 0) (listToMaybe candidates)
      -- the regex styles, in the order written, each with its line
      regexes = [(sp, n, d) | RegexDef sp n d <- defs]
      withRegexes = local {lsRegexStyles = Map.fromListWith (flip (<>)) [(n, [d]) | (_, n, d) <- regexes]}
      regexSpan n i = case drop i [sp | (sp, n', _) <- regexes, n' == n] of
        sp : _ -> sp
        [] -> mkSpan (FileId 0) 0 0
      regexErrs = checkLocalRegexStyles style withRegexes
      wrongRegexes = [(n, i) | (n, i, _, _) <- regexErrs]
      ds3 = [err code (regexSpan n i) m | (n, i, code, m) <- regexErrs]
      final =
        withRegexes
          { lsRegexStyles =
              Map.filter (not . null) (Map.mapWithKey (\n rs -> [r | (i, r) <- zip [0 ..] rs, (n, i) `notElem` wrongRegexes]) (lsRegexStyles withRegexes))
          }
      -- G02062: one notice for each definition that took effect over a style of style.toml or a built-in one
      overrides =
        [ notice "G02062" sp ("ファイルの中の定義が" <> kindName k <> "の " <> n <> " を上書きしています")
        | Def sp k n _ <- defs,
          let (inFile, inStyle) = case k of
                CharacterKind -> (Map.member n (lsCharStyles final), Map.member n (stCharStyles style))
                ParagraphKind -> (Map.member n (lsParaStyles final), Map.member n (stParaStyles style)),
          inFile && inStyle
        ]
      kindName = \case
        CharacterKind -> "文字スタイル"
        ParagraphKind -> "段落スタイル"
      -- G03100: a zero indent of caption or sidenote has no effect (golem-driver ADR 0043)
      zeroIndents =
        [ notice "G03100" ksp (captionZeroIndentMessage n k (written v))
        | (Def _ ParagraphKind n (Right d), kvs) <- defKeys,
          Map.member n (lsParaStyles final),
          k <- captionZeroIndentKeys n d,
          (k', ksp, v) <- kvs,
          k' == k
        ]
      -- each definition with the keys written on its line
      defKeys = [(def, fst (keywordArgs args)) | def@(Def sp _ _ _) <- defs, A.Located sp' (A.BlockCommand (A.Located _ "style-def") args _) <- header, sp' == sp]
      written = \case
        LocalWord w -> w
        LocalString t -> "\"" <> t <> "\""
   in (final, ds1 <> ds2 <> ds3 <> overrides <> zeroIndents)
  where
    shape = "@style-def には種類（character、paragraph、regex）と名前を書きます"
    -- the features of a definition are at its line, for G08103 (docs/adr/0268)
    sited sp = \case
      Left c -> Left c {csFeatures = [f {ftSite = SiteSource sp} | f <- csFeatures c]}
      Right p -> Right p {psFeatures = [f {ftSite = SiteSource sp} | f <- psFeatures p]}
    readDef (defs, ds) (sp, args, body) =
      let positionals = [(asp, v) | A.Located asp (A.Positional v) <- args]
          spreads = [spreadBeforeEvaluation "@style-def" asp | A.Located asp a <- args, isSplat a]
          (kvs, kwDiags) = keywordArgs args
          -- G02052: the number of the positional arguments, at each one past the two or at the line
          countDiags = case positionals of
            [_, _] -> []
            _ : _ : extra -> [err "G02052" asp shape | (asp, _) <- extra]
            _ -> [err "G02052" sp shape]
          -- G02116 for a kind or a name that is no word nor string, G02117 for an unknown kind
          kindDiags = case positionals of
            (asp, v) : _ -> case textOf v of
              Nothing -> [notWordDiagnostic asp]
              Just w | isNothing (kindOf w) -> [err "G02117" asp ("未知のスタイルの種類です: " <> w <> "。character、paragraph、regex のどれかを書きます")]
              Just _ -> []
            [] -> []
          nameDiags = [notWordDiagnostic asp | _ : (asp, v) : _ <- [positionals], isNothing (textOf v)]
          errs = inOrder (spreads <> countDiags <> kindDiags <> nameDiags <> kwDiags) <> bodyDiagnostics "@style-def" body
       in case positionals of
            [(_, kv), (_, nv)]
              | null errs,
                Just kindW <- textOf kv,
                Just name <- textOf nv,
                Just kind <- kindOf kindW ->
                  case kind of
                    -- a word is read as a string: the pattern and the style are strings (docs/adr ADR 0015)
                    Nothing -> case localRegexStyleDef [(key, asString v) | (key, _, v) <- kvs] of
                      Left ms -> (defs, ds <> [err "G03006" sp ("@style-def の値が不正です: " <> m) | m <- ms])
                      Right d -> (defs <> [RegexDef sp name d], ds)
                    Just k
                      | not (null [() | Def _ k' n _ <- defs, k' == k, n == name]) -> (defs, ds <> [err "G02053" sp ("同じ名前のスタイルを二度定義しています: " <> name)])
                      | otherwise -> case localStyleDef k [(key, v) | (key, _, v) <- kvs] of
                          -- an aki amount in a dimension is G03020 (docs/adr ADR 0019); kerning, tracking and baseline shift G03021 (docs/adr/0020)
                          Left ms -> (defs, ds <> [err (if "アキの量の指定が正しくありません" `T.isPrefixOf` m then "G03020" else code) sp ("@style-def の値が不正です: " <> m) | (code, m) <- ms])
                          Right d -> (defs <> [Def sp k name (sited sp d)], ds)
            _ -> (defs, ds <> errs)
    -- the kind and the name, as a word or a string literal (docs/adr ADR 0132)
    textOf v = case localValue v of
      Just (LocalWord w) -> Just w
      Just (LocalString t) -> Just t
      Nothing -> Nothing
    asString = \case
      LocalWord w -> LocalString w
      v -> v
    isSplat = \case
      A.SplatPositional _ -> True
      A.SplatKeyword _ -> True
      _ -> False
    -- Just Nothing is regex
    kindOf = \case
      "character" -> Just (Just CharacterKind)
      "paragraph" -> Just (Just ParagraphKind)
      "regex" -> Just Nothing
      _ -> Nothing

{- | The hyphenation exceptions of the @hyphenation-exceptions lines (docs/adr
ADR 0272), by language tag, and the diagnostics in the order of the
lines, those of a line in the order written. A line is a language tag and
one or more words, each a word or a string literal. A line with a body
(G02097), with fewer than two positional arguments (G02052), with a tag
that is not one (G02116, G03126) or of the tag of a line before it but
for case (G03130) is left out; a keyword argument (G02153), a spread
(G02114) and a wrong word (G02116, G03127, G03128, G03129) are left out
alone.
-}
fileHyphenationExceptions :: [A.Located A.Block] -> (Map.Map Text [Text], [Diagnostic])
fileHyphenationExceptions header = foldl step (Map.empty, []) [(sp, args, body) | A.Located sp (A.BlockCommand (A.Located _ "hyphenation-exceptions") args body) <- header]
  where
    name = "@hyphenation-exceptions"
    step (m, ds) (sp, args, body) =
      let positionals = [(asp, v) | A.Located asp (A.Positional v) <- args]
          spreads = [spreadBeforeEvaluation name asp | A.Located asp a <- args, isSplat a]
          keywords = [err "G02153" asp "@hyphenation-exceptions にはキーワード引数を書けません。言語のタグと語だけを書きます" | A.Located asp (A.Keyword {}) <- args]
          notWords = [notWordDiagnostic asp | (asp, v) <- positionals, isNothing (textOf v)]
          countDiags = [err "G02052" sp "@hyphenation-exceptions には言語のタグと一つ以上の語を書きます" | length positionals < 2]
          argDiags = inOrder (spreads <> keywords <> notWords <> countDiags)
          bodyDiags = bodyDiagnostics name body
       in case positionals of
            (tsp, tv) : wordArgs@(_ : _)
              | null body,
                Just tag <- textOf tv ->
                  if not (isLanguageTag tag)
                    then (m, ds <> argDiags <> [err "G03126" tsp ("分綴の例外の一覧のキーが言語のタグの形ではありません: " <> tag)])
                    else
                      if T.toLower tag `elem` map T.toLower (Map.keys m)
                        then (m, ds <> argDiags <> [err "G03130" tsp ("大文字と小文字だけが違う言語のタグの一覧が二つあります: " <> tag)])
                        else
                          let ws = [(asp, w) | (asp, v) <- wordArgs, Just w <- [textOf v]]
                              wrong = exceptionWordErrors (map snd ws)
                              wordDiags = [err code (fst (ws !! i)) msg | (i, code, msg) <- wrong]
                              kept = [w | (i, (_, w)) <- zip [0 ..] ws, i `notElem` [j | (j, _, _) <- wrong]]
                           in (Map.insert tag kept m, ds <> inOrder (argDiags <> wordDiags))
            _ -> (m, ds <> argDiags <> bodyDiags)
    textOf v = case localValue v of
      Just (LocalWord w) -> Just w
      Just (LocalString t) -> Just t
      Nothing -> Nothing
    isSplat = \case
      A.SplatPositional _ -> True
      A.SplatKeyword _ -> True
      _ -> False
