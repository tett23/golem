{- | The built-in inline commands as a sum type (docs/adr ADR 0027), and
the built-in block commands a plugin or a name listed by @import may
override (root ADR 0453, root ADR 0471): every inline command, and every
block command but those that decide the mechanisms of Golem and @frame.
-}
module Golem.Eval.Builtin
  ( BuiltinInline (..),
    allBuiltins,
    builtinName,
    parseBuiltin,
    takesNoSlot,
    PluginCommandName,
    pluginCommandName,
    unPluginCommandName,
    builtinBlockCommands,
    OverridableBlock (..),
    overridableBlockName,
    parseOverridableBlock,
    overridableBlockCommands,
    fixedBlockCommands,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)

{- | A built-in inline command. A plugin (overrides) or a name listed by
@import may override each of them (root ADR 0471).
-}
data BuiltinInline
  = BStrong
  | BBold
  | BItalic
  | BCode
  | BRuby
  | BKenten
  | BColor
  | BStyle
  | BWarichu
  | BUpright
  | BTcy
  | BNumberText
  | BRefNumber
  | BRefTitle
  | BRefPage
  | BNote
  | BSidenote
  | -- | an endnote, at the end of the chapter in every output (root ADR 0412)
    BEndnote
  | BIndex
  | BCite
  | BAki
  | -- | a link to an external URL (docs/adr ADR 0182)
    BLink
  | -- | a language span (docs/adr ADR 0187)
    BLang
  | -- | a soft hyphen, U+00AD (docs/adr ADR 0272)
    BShy
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The built-in inline commands, in the order of builtinInlineCommands.
allBuiltins :: [BuiltinInline]
allBuiltins = [minBound .. maxBound]

builtinName :: BuiltinInline -> Text
builtinName = \case
  BStrong -> "strong"
  BBold -> "bold"
  BItalic -> "italic"
  BCode -> "code"
  BRuby -> "ruby"
  BKenten -> "kenten"
  BColor -> "color"
  BStyle -> "style"
  BWarichu -> "warichu"
  BUpright -> "upright"
  BTcy -> "tcy"
  BNumberText -> "number-text"
  BRefNumber -> "ref-number"
  BRefTitle -> "ref-title"
  BRefPage -> "ref-page"
  BNote -> "note"
  BSidenote -> "sidenote"
  BEndnote -> "endnote"
  BIndex -> "index"
  BCite -> "cite"
  BAki -> "aki"
  BLink -> "link"
  BLang -> "lang"
  BShy -> "shy"

-- | The command of a name, the inverse of 'builtinName'.
parseBuiltin :: Text -> Maybe BuiltinInline
parseBuiltin n = Map.lookup n byName

byName :: Map Text BuiltinInline
byName = Map.fromList [(builtinName b, b) | b <- allBuiltins]

-- | Commands that take no prose slot (golem-eval ADR 0003).
takesNoSlot :: BuiltinInline -> Bool
takesNoSlot = \case
  BStrong -> False
  BBold -> False
  BItalic -> False
  BCode -> False
  BRuby -> False
  BKenten -> False
  BColor -> False
  BStyle -> False
  BWarichu -> False
  BUpright -> False
  BTcy -> False
  BNumberText -> True
  BRefNumber -> True
  BRefTitle -> True
  BRefPage -> True
  BNote -> False
  BSidenote -> False
  BEndnote -> False
  BIndex -> False
  BCite -> True
  -- [aki] reports a slot as G02055 itself (docs/adr ADR 0019)
  BAki -> False
  -- the prose slot of [link] may be left out (docs/adr ADR 0182)
  BLink -> False
  -- [lang] reports a slot that is not one as G02038 itself (docs/adr ADR 0187)
  BLang -> False
  -- docs/adr ADR 0272
  BShy -> True

-- | The name of a plugin command that is not a built-in one.
newtype PluginCommandName = PluginCommandName Text
  deriving stock (Eq, Ord, Show)

-- | Nothing for the name of a built-in command.
pluginCommandName :: Text -> Maybe PluginCommandName
pluginCommandName n
  | Map.member n byName = Nothing
  | otherwise = Just (PluginCommandName n)

unPluginCommandName :: PluginCommandName -> Text
unPluginCommandName (PluginCommandName n) = n

{- | The built-in block commands a plugin (block-overrides) or a name
listed by @import may override (root ADR 0471): all but those of
'fixedBlockCommands'.
-}
data OverridableBlock
  = BlockToc
  | BlockIndex
  | BlockBibliography
  | BlockPrintings
  | BlockSeparator
  | BlockPageBreak
  | BlockColumnBreak
  | BlockNoPageBreak
  | BlockNeedLines
  | BlockPageLines
  | BlockBlankLine
  | BlockFigure
  | BlockTable
  | BlockListing
  | BlockStyle
  | -- | docs/adr ADR 0187
    BlockLang
  | -- | docs/adr/0263
    BlockNote
  | -- | root ADR 0412
    BlockEndnote
  deriving stock (Eq, Ord, Show, Enum, Bounded)

overridableBlockName :: OverridableBlock -> Text
overridableBlockName = \case
  BlockToc -> "toc"
  BlockIndex -> "index"
  BlockBibliography -> "bibliography"
  BlockPrintings -> "printings"
  BlockSeparator -> "separator"
  BlockPageBreak -> "page-break"
  BlockColumnBreak -> "column-break"
  BlockNoPageBreak -> "no-page-break"
  BlockNeedLines -> "need-lines"
  BlockPageLines -> "page-lines"
  BlockBlankLine -> "blank-line"
  BlockFigure -> "figure"
  BlockTable -> "table"
  BlockListing -> "listing"
  BlockStyle -> "style"
  BlockLang -> "lang"
  BlockNote -> "note"
  BlockEndnote -> "endnote"

-- | The overridable block command of a name, the inverse of 'overridableBlockName'.
parseOverridableBlock :: Text -> Maybe OverridableBlock
parseOverridableBlock n = lookup n [(overridableBlockName b, b) | b <- [minBound .. maxBound]]

-- | The names of the overridable block commands (root ADR 0471).
overridableBlockCommands :: [Text]
overridableBlockCommands = map overridableBlockName [minBound .. maxBound]

{- | The names of the built-in block commands, the file settings and the
attributes among them (docs/adr/0122): the overridable ones, then the
fixed ones (root ADR 0471). A plugin provides a block command of one of
these names only to override an overridable one by block-overrides.
-}
builtinBlockCommands :: [Text]
builtinBlockCommands = overridableBlockCommands <> fixedBlockCommands

{- | The names of the built-in block commands that neither a plugin nor a
listed name may override (root ADR 0471), the names G02270 counts: those
that decide the mechanisms of Golem, which the evaluation reads before
every other command (the imports, the variables, the channels, the file
settings, the definitions of styles and the attributes of a group), and
@frame, without which nothing is set.
-}
fixedBlockCommands :: [Text]
fixedBlockCommands =
  [ "import",
    "set",
    "channel",
    "manifest",
    "style-def",
    -- docs/adr ADR 0272
    "hyphenation-exceptions",
    "label",
    "toc-title",
    "number",
    "nonumber",
    "notoc",
    "caption",
    -- docs/adr/0262
    "column-widths",
    -- root ADR 0438
    "frame"
  ]
