{- | The built-in inline commands as a sum type (docs/adr ADR 0027): whether
a plugin may override a command is the type its constructor is in, and the
names of the commands a plugin provides apart from them.
-}
module Golem.Eval.Builtin
  ( BuiltinInline (..),
    OverridableBuiltin (..),
    FixedBuiltin (..),
    allBuiltins,
    builtinName,
    parseBuiltin,
    takesNoSlot,
    PluginCommandName,
    pluginCommandName,
    unPluginCommandName,
    builtinBlockCommands,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)

-- | A built-in inline command. The order is the order of builtinInlineCommands.
data BuiltinInline
  = Overridable !OverridableBuiltin
  | Fixed !FixedBuiltin
  deriving stock (Eq, Ord, Show)

-- | The commands a plugin may override.
data OverridableBuiltin
  = BStrong
  | BBold
  | BItalic
  | BCode
  | BRuby
  | BKenten
  | BColor
  | BStyle
  | BTcy
  | BNumberText
  deriving stock (Eq, Ord, Show, Enum, Bounded)

-- | The commands a plugin may not override.
data FixedBuiltin
  = BRefNumber
  | BRefTitle
  | BRefPage
  | BNote
  | BSidenote
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

-- | The overridable commands, then the others.
allBuiltins :: [BuiltinInline]
allBuiltins = map Overridable [minBound .. maxBound] <> map Fixed [minBound .. maxBound]

builtinName :: BuiltinInline -> Text
builtinName = \case
  Overridable o -> case o of
    BStrong -> "strong"
    BBold -> "bold"
    BItalic -> "italic"
    BCode -> "code"
    BRuby -> "ruby"
    BKenten -> "kenten"
    BColor -> "color"
    BStyle -> "style"
    BTcy -> "tcy"
    BNumberText -> "number-text"
  Fixed f -> case f of
    BRefNumber -> "ref-number"
    BRefTitle -> "ref-title"
    BRefPage -> "ref-page"
    BNote -> "note"
    BSidenote -> "sidenote"
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
  Overridable o -> case o of
    BStrong -> False
    BBold -> False
    BItalic -> False
    BCode -> False
    BRuby -> False
    BKenten -> False
    BColor -> False
    BStyle -> False
    BTcy -> False
    BNumberText -> True
  Fixed f -> case f of
    BRefNumber -> True
    BRefTitle -> True
    BRefPage -> True
    BNote -> False
    BSidenote -> False
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

{- | The names of the built-in block commands, the file settings and the
attributes among them: a plugin may not provide a block command of one of
these names (docs/adr/0122).
-}
builtinBlockCommands :: [Text]
builtinBlockCommands =
  [ "import",
    "set",
    "toc",
    "index",
    "bibliography",
    "channel",
    "printings",
    "page-break",
    "column-break",
    "no-page-break",
    "need-lines",
    "page-lines",
    "blank-line",
    "figure",
    "table",
    "listing",
    "style",
    "manifest",
    "style-def",
    "label",
    "toc-title",
    "number",
    "nonumber",
    "notoc",
    "caption",
    -- docs/adr ADR 0187
    "lang",
    -- docs/adr/0262
    "column-widths",
    -- docs/adr ADR 0272
    "hyphenation-exceptions",
    -- docs/adr/0263
    "note"
  ]
