{- | The built-in modules of .emet (docs/adr/0160): @List@ and @String@,
used without import and always with their names (@List.map@). Their
functions are written in .emet on top of primitives ('Golem.Emet.Prim'):
a signature without equations is a primitive. The functions written in
.emet count their steps and frames as any other. Each module has a path
that no file of a project can have.

The higher-order functions take the requirements of the functions they
are given as their own (docs/adr/0161): @List.map :: (a -> e b) -> List a
-> e (List b)@. The module @File@ has @File.read@, whose type depends on
its argument, a string literal: the checker gives it the type
@<file "path"> String@, and the evaluator calls the handler of the
driver for it.
-}
module Golem.Emet.Builtins
  ( builtinSources,
    divInfo,
    hiddenConstructors,
  )
where

import Data.Text (Text)
import Data.Text qualified as T
import Golem.Emet.Check (FunInfo (..))
import Golem.Emet.Core (GKey, Global (..))
import Golem.Emet.Types

-- | The built-in modules in the order they are checked: their names, paths and sources.
builtinSources :: [(Text, FilePath, Text)]
builtinSources =
  [ ("List", "<builtin>/List.emet", listSource),
    ("String", "<builtin>/String.emet", stringSource),
    ("File", "<builtin>/File.emet", "pub read :: String -> String\n"),
    ("Inline", "<builtin>/Inline.emet", inlineSource),
    ("Block", "<builtin>/Block.emet", blockSource)
  ]

{- | The constructors of the built-in modules that no module may use: the
one of @Inline.Deferred@, whose value is the index of a deferred
expression of the IR (docs/adr/0162).
-}
hiddenConstructors :: [(Text, Text)]
hiddenConstructors = [("Inline", "Opaque")]

{- | The inlines of the semantic IR (docs/adr/0162), as the ABI with the
plugins serialises them (the section シリアライズ形式 of the specification). The
spans, the numbers of the notes and the expressions of Deferred are not
fields: a node that comes in keeps them, and a node a function makes
takes the place of its call. The functions are the short ways of making
the nodes used most.
-}
inlineSource :: Text
inlineSource =
  T.unlines
    [ "pub data Inline =",
      "  Text String",
      "  | Ruby (List RubySegment)",
      "  | Kenten (Maybe String) (List Inline)",
      "  | Color String (List Inline)",
      "  | CharStyle String (List Inline)",
      "  | Tcy String",
      "  | Number Int (Maybe NumberStyle)",
      "  | Ref RefKind String",
      "  | Deferred Deferred",
      "  | Note (List Inline)",
      "  | Sidenote (List Inline)",
      "  | IndexMark (List String) (List String)",
      "  | Cite String",
      "  | ProofComment String",
      "  | LineBreak",
      "  | Aki AkiAmount",
      "  | ChannelItem String (Maybe String) (Maybe String) (List Inline)",
      "  | Link String (List Inline)",
      "  | Lang String (List Inline)",
      "",
      "pub data RubySegment = RubySegment (List Inline) (Maybe String)",
      "",
      "pub data NumberStyle = Kanji | KanjiDigits | TateChuYoko",
      "",
      "pub data RefKind = RefNumber | RefTitle | RefPage",
      "",
      "pub data AkiAmount = Zw Rat | Sp Nat",
      "",
      "pub data Deferred = Opaque Nat",
      "",
      "pub text :: String -> List Inline",
      "text s = [Text s]",
      "",
      "pub ruby :: String -> String -> List Inline",
      "ruby base reading = [Ruby [RubySegment [Text base] (Just reading)]]",
      "",
      "pub style :: String -> List Inline -> List Inline",
      "style name xs = [CharStyle name xs]",
      "",
      "pub color :: String -> List Inline -> List Inline",
      "color name xs = [Color name xs]",
      "",
      "pub kenten :: List Inline -> List Inline",
      "kenten xs = [Kenten Nothing xs]",
      "",
      "pub tcy :: String -> List Inline",
      "tcy s = [Tcy s]",
      "",
      "pub note :: List Inline -> List Inline",
      "note xs = [Note xs]",
      "",
      "pub plain :: List Inline -> String",
      "plain xs = String.join \"\" (List.map plainOf xs)",
      "",
      "plainOf :: Inline -> String",
      "plainOf (Text s) = s",
      "plainOf (Ruby segs) = String.join \"\" (List.map segmentText segs)",
      "plainOf (Kenten _ xs) = plain xs",
      "plainOf (Color _ xs) = plain xs",
      "plainOf (CharStyle _ xs) = plain xs",
      "plainOf (Link _ xs) = plain xs",
      "plainOf (Lang _ xs) = plain xs",
      "plainOf (Tcy s) = s",
      "plainOf (Number n _) = String.fromInt n",
      "plainOf _ = \"\"",
      "",
      "segmentText :: RubySegment -> String",
      "segmentText (RubySegment base _) = plain base"
    ]

{- | The blocks of the semantic IR (docs/adr/0162), as the ABI serialises
them. The spans and the labels are not fields, as for 'inlineSource'.
-}
blockSource :: Text
blockSource =
  T.unlines
    [ "pub data Block =",
      "  Paragraph (Maybe String) Inlines",
      "  | Heading Nat HeadingAttrs Inlines",
      "  | BulletList (List ListItem)",
      "  | OrderedList (List ListItem)",
      "  | DefList (List DefGroup)",
      "  | Table (List Alignment) (List Inlines) (List (List Inlines))",
      "  | CodeBlock Code",
      "  | FigureBlock Figure",
      "  | ChannelOutput Channel",
      "  | ForcedBreak BreakKind",
      "  | PageControl PageControl",
      "  | BlankLines Nat",
      "",
      "pub data HeadingAttrs = HeadingAttrs { tocTitle :: Maybe Inlines, number :: Maybe Nat, nonumber :: Bool, notoc :: Bool }",
      "",
      "pub data ListItem = ListItem (Maybe Nat) (List Block)",
      "",
      "pub data DefGroup = DefGroup (List Inlines) (List (List Block))",
      "",
      "pub data Alignment = AlignDefault | AlignLeft | AlignCenter | AlignRight",
      "",
      "pub data Code = Code { lang :: Maybe String, numbers :: Maybe Bool, file :: Maybe String, caption :: Maybe Inlines, diff :: Bool, lines :: List CodeLine, nonumber :: Bool }",
      "",
      "pub data CodeLine = CodeLine { text :: String, number :: Maybe Nat, mark :: Maybe DiffMark, highlight :: Bool, callouts :: List Nat }",
      "",
      "pub data DiffMark = Added | Removed | Unchanged",
      "",
      "pub data Figure = Figure { source :: String, web :: Maybe String, alt :: String, wrap :: Maybe Wrap, width :: Maybe String, caption :: List Block, page :: Maybe Nat, rotate :: Bool, nonumber :: Bool }",
      "",
      "pub data Wrap = WrapStart | WrapEnd",
      "",
      "pub data Channel = TocOutput Nat | IndexOutput | BibliographyOutput | CustomOutput String (Maybe String)",
      "",
      "pub data BreakKind = BreakPage | BreakRecto | BreakVerso | BreakColumn",
      "",
      "pub data PageControl = NoBreak | NeedLines Nat | AdjustLines Int",
      "",
      "pub paragraph :: Inlines -> Blocks",
      "paragraph xs = [Paragraph Nothing xs]",
      "",
      "pub styled :: String -> Inlines -> Blocks",
      "styled name xs = [Paragraph (Just name) xs]",
      "",
      "pub bullets :: List Blocks -> Blocks",
      "bullets items = [BulletList (List.map item items)]",
      "",
      "pub numbered :: List Blocks -> Blocks",
      "numbered items = [OrderedList (List.map item items)]",
      "",
      "item :: Blocks -> ListItem",
      "item bs = ListItem Nothing bs",
      "",
      "pub table :: List Inlines -> List (List Inlines) -> Blocks",
      "table header rows = [Table (List.map align header) header rows]",
      "  where {",
      "    align _ = AlignDefault",
      "  }",
      "",
      "pub definitions :: List (Inlines, Blocks) -> Blocks",
      "definitions pairs = [DefList (List.map group pairs)]",
      "",
      "group :: (Inlines, Blocks) -> DefGroup",
      "group (term, body) = DefGroup [term] [body]"
    ]

-- | @div@: the floor division of integers, as in the expression context.
divInfo :: (FunInfo, (GKey, Global))
divInfo =
  let key = ("<builtin>", "div")
   in (FunInfo key (Scheme [] pureRow (TF tInt pureRow (TF tInt pureRow tInt))) True, (key, GPrim "div" 2))

listSource :: Text
listSource =
  T.unlines
    [ "pub length :: List a -> Nat",
      "pub reverse :: List a -> List a",
      "pub take :: Nat -> List a -> List a",
      "pub drop :: Nat -> List a -> List a",
      "pub range :: Int -> Int -> List Int",
      "pub concat :: List (List a) -> List a",
      "pub at :: Nat -> List a -> Maybe a",
      "",
      "pub isEmpty :: List a -> Bool",
      "isEmpty [] = True",
      "isEmpty _ = False",
      "",
      "pub map :: (a -> e b) -> List a -> e (List b)",
      "map f xs = mapGo f xs []",
      "",
      "mapGo :: (a -> e b) -> List a -> List b -> e (List b)",
      "mapGo _ [] acc = reverse acc",
      "mapGo f (y : ys) acc = mapGo f ys (f y : acc)",
      "",
      "pub select :: (a -> e Bool) -> List a -> e (List a)",
      "select p xs = selectGo p xs []",
      "",
      "selectGo :: (a -> e Bool) -> List a -> List a -> e (List a)",
      "selectGo _ [] acc = reverse acc",
      "selectGo p (y : ys) acc = selectGo p ys (p y ? (y : acc) : acc)",
      "",
      "pub foldl :: (b -> a -> e b) -> b -> List a -> e b",
      "foldl _ z [] = z",
      "foldl f z (y : ys) = foldl f (f z y) ys",
      "",
      "pub foldr :: (a -> b -> e b) -> b -> List a -> e b",
      "foldr f z xs = foldrGo f z (reverse xs)",
      "",
      "foldrGo :: (a -> b -> e b) -> b -> List a -> e b",
      "foldrGo _ z [] = z",
      "foldrGo f z (y : ys) = foldrGo f (f y z) ys",
      "",
      "pub any :: (a -> e Bool) -> List a -> e Bool",
      "any _ [] = False",
      "any p (y : ys) = p y || any p ys",
      "",
      "pub all :: (a -> e Bool) -> List a -> e Bool",
      "all _ [] = True",
      "all p (y : ys) = p y && all p ys",
      "",
      "pub concatMap :: (a -> e (List b)) -> List a -> e (List b)",
      "concatMap f xs = concat (map f xs)",
      "",
      "pub zip :: List a -> List b -> List (a, b)",
      "zip xs ys = zipGo xs ys []",
      "",
      "zipGo :: List a -> List b -> List (a, b) -> List (a, b)",
      "zipGo (x : xs) (y : ys) acc = zipGo xs ys ((x, y) : acc)",
      "zipGo _ _ acc = reverse acc"
    ]

stringSource :: Text
stringSource =
  T.unlines
    [ "pub length :: String -> Nat",
      "pub chars :: String -> List Char",
      "pub fromChars :: List Char -> String",
      "pub fromChar :: Char -> String",
      "pub join :: String -> List String -> String",
      "pub split :: String -> String -> List String",
      "pub lines :: String -> List String",
      "pub trim :: String -> String",
      "pub startsWith :: String -> String -> Bool",
      "pub endsWith :: String -> String -> Bool",
      "pub contains :: String -> String -> Bool",
      "pub replace :: String -> String -> String -> String",
      "pub take :: Nat -> String -> String",
      "pub drop :: Nat -> String -> String",
      "pub fromNat :: Nat -> String",
      "pub fromInt :: Int -> String",
      "pub fromRat :: Rat -> String",
      "pub toNat :: String -> Maybe Nat",
      "pub toInt :: String -> Maybe Int",
      "",
      "pub all :: (Char -> e Bool) -> String -> e Bool",
      "all p s = List.all p (chars s)",
      "",
      "pub any :: (Char -> e Bool) -> String -> e Bool",
      "any p s = List.any p (chars s)",
      "",
      "pub map :: (Char -> e Char) -> String -> e String",
      "map f s = fromChars (List.map f (chars s))"
    ]
