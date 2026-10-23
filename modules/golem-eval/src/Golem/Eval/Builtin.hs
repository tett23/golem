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
