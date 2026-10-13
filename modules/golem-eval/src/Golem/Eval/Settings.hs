{- | The file settings (docs/adr ADR 0014): the @manifest and @style-def
lines at the top of a file, which override keys of [source] and define
styles for that file alone.
-}
module Golem.Eval.Settings
  ( settingCommands,
    isSettingCommand,
    fileHeader,
    fileSettings,
    fileStyles,
  )
where

import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Parser.AST qualified as A
import Golem.Project.Style
import Golem.Syntax

-- | The commands of the file settings.
settingCommands :: [Text]
settingCommands = ["manifest", "style-def"]

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

-- | The keyword arguments of a setting: (key, span, value), or the G0252 messages.
keywordArgs :: [A.Located A.Argument] -> ([(Text, SrcSpan, LocalValue)], [(SrcSpan, Text)])
keywordArgs args =
  let kws = [(k, sp, v) | A.Located sp (A.Keyword (A.Located _ k) v) <- args]
      keys = [k | (k, _, _) <- kws]
      dup = nub [k | (i, k) <- zip [0 :: Int ..] keys, k `elem` take i keys]
      values = [(k, sp, lv) | (k, sp, v) <- kws, k `notElem` dup, Just lv <- [localValue v]]
      bad =
        [(sp, "値は語か文字列で書きます") | (_, sp, v) <- kws, Nothing <- [localValue v]]
          <> [(sp, "同じキーを二度書いています: " <> k) | k <- dup, (k', sp, _) <- take 1 [x | x@(k'', _, _) <- kws, k'' == k], k' == k]
   in (values, bad)
  where
    localValue = \case
      A.Word w -> Just (LocalWord w)
      A.StringLit s -> Just (LocalString s)
      _ -> Nothing

{- | Each @manifest applied in order with a table of the keys of [source]
(docs/adr ADR 0013) to the settings of the context, and the diagnostics.
A wrong argument is left out; the others take effect.
-}
fileSettings :: [(Text, Text -> Either Text (s -> s))] -> s -> [A.Located A.Block] -> (s, [Diagnostic])
fileSettings table s0 header = foldl step (s0, []) [(sp, args, body) | A.Located sp (A.BlockCommand (A.Located _ "manifest") args body) <- header]
  where
    shape = "@manifest には key=value だけを書きます"
    step (s, ds) (sp, args, body)
      | not (null body) || null args = (s, ds <> [err "G0252" sp shape])
      | otherwise =
          let others = [asp | A.Located asp a <- args, not (isKeyword a)]
              (kvs, bad) = keywordArgs args
              apply (s', ds') (k, ksp, v) = case lookup k table of
                Nothing -> (s', ds' <> [err "G0250" ksp (notOverridable k)])
                Just f -> case f (valueText v) of
                  Left m -> (s', ds' <> [err "G0251" ksp m])
                  Right g -> (g s', ds')
              (s'', applied) = foldl apply (s, []) kvs
           in (s'', ds <> [err "G0252" asp shape | asp <- others] <> [err "G0252" bsp m | (bsp, m) <- bad] <> applied)
    isKeyword = \case
      A.Keyword {} -> True
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

-- | One @style-def read: its span, kind, name and keys.
data Def = Def SrcSpan StyleKind Text (Either CharStyleDef ParaStyleDef)

{- | The styles of the @style-def lines, checked against style.toml, and the
diagnostics. A wrong definition is dropped as a whole.
-}
fileStyles :: Style -> [A.Located A.Block] -> (LocalStyles, [Diagnostic])
fileStyles style header =
  let (defs, ds1) = foldl readDef ([], []) [(sp, args, body) | A.Located sp (A.BlockCommand (A.Located _ "style-def") args body) <- header]
      local0 = LocalStyles (Map.fromList [(n, d) | Def _ _ n (Left d) <- defs]) (Map.fromList [(n, d) | Def _ _ n (Right d) <- defs])
      spanOf kind n = listToMaybe [sp | Def sp k n' _ <- defs, k == kind, n' == n]
      (local, ds2) = checked local0 []
      -- the checks again until no definition is dropped
      checked ls acc =
        let cs = checkLocalStyles style ls
            ds = [err code (positionOf ls name) m | (code, name, m) <- cs]
            wrong = [localsOf ls name | (code, name, _) <- cs, code `elem` ["G0306", "G0308", "G0313"]]
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
      -- where a diagnostic about a name is reported: the @style-def of the name it stands for
      positionOf ls name =
        let (ps, cs) = localsOf ls name
            candidates =
              [sp | m <- ps, Just sp <- [spanOf ParagraphKind m]]
                <> [sp | m <- cs, Just sp <- [spanOf CharacterKind m]]
                <> [sp | Def sp _ _ _ <- defs]
         in fromMaybe (mkSpan (FileId 0) 0 0) (listToMaybe candidates)
   in (local, ds1 <> ds2)
  where
    shape = "@style-def には種類（character、paragraph、regex）と名前を書きます"
    readDef (defs, ds) (sp, args, body) =
      let positionals = [v | A.Located _ (A.Positional v) <- args]
          splats = [() | A.Located _ a <- args, isSplat a]
          (kvs, bad) = keywordArgs args
          shapeErrs = [err "G0252" bsp m | (bsp, m) <- bad]
       in case positionals of
            [A.Word kindW, A.Word name]
              | null body,
                null splats,
                Just kind <- kindOf kindW ->
                  case kind of
                    Nothing
                      | null shapeErrs -> (defs, ds <> [err "G0254" sp "正規表現スタイルはまだ実装していません"])
                      | otherwise -> (defs, ds <> shapeErrs)
                    Just k
                      | not (null shapeErrs) -> (defs, ds <> shapeErrs)
                      | any (\(Def _ k' n _) -> k' == k && n == name) defs -> (defs, ds <> [err "G0253" sp ("同じ名前のスタイルを二度定義しています: " <> name)])
                      | otherwise -> case localStyleDef k [(key, v) | (key, _, v) <- kvs] of
                          -- an aki amount in a dimension is G0320 (docs/adr ADR 0019)
                          Left ms -> (defs, ds <> [err (if "アキの量の指定が正しくありません" `T.isPrefixOf` m then "G0320" else "G0306") sp ("@style-def の値が不正です: " <> m) | m <- ms])
                          Right d -> (defs <> [Def sp k name d], ds)
            _ -> (defs, ds <> [err "G0252" sp shape] <> shapeErrs)
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
