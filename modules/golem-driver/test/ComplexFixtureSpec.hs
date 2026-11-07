{- | The two books that combine the features of Golem
(test/fixtures/complex-vertical and test/fixtures/complex-horizontal,
docs/adr/0175). Their outputs are fixed by the goldens of
'OutputGoldenSpec'; this module reads their sources (the @.gm@, the
@.emet@, @style.toml@ and @manifest.toml@) and checks that each feature the
ADR lists is written there at least once, so that a later edit that drops
a feature from a book fails a test instead of leaving the interaction
unchecked. It also checks that each manifest silences the notices G07030
and G07046 and no other code (docs/adr/0198).

The checks read the notation, not the output: a heading line is a line
that starts with @#@, a table row one that starts with @|@, and the tables
of @style.toml@ are found by their headers.
-}
module ComplexFixtureSpec (complexFixtureTests) where

import Data.List (isPrefixOf, sort)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import System.Directory (doesDirectoryExist, listDirectory)
import System.FilePath (takeExtension, (</>))
import Test.Tasty
import Test.Tasty.HUnit

complexFixtureTests :: TestTree
complexFixtureTests =
  testGroup
    "the books that combine the features (docs/adr/0175)"
    [ book "complex-vertical" (common <> vertical),
      book "complex-horizontal" (common <> horizontal)
    ]

-- | The sources of a book: the manuscripts, the functions, the style and the manifest.
data Sources = Sources
  { srcGm :: [Text],
    srcEmet :: Text,
    srcStyle :: [(Text, [Text])],
    srcManifest :: Text
  }

type Feature = (String, Sources -> Bool)

book :: FilePath -> [Feature] -> TestTree
book name features =
  testGroup
    name
    ( [ testCase feature $ do
          s <- readSources ("test/fixtures" </> name)
          assertBool ("the book does not use: " <> feature) (check s)
      | (feature, check) <- features
      ]
        <> [silencedNotices name]
    )

{- | The table @[diagnostics]@ of the manifest has exactly one key,
@silence-notices = ["G07030", "G07046"]@ (docs/adr/0198): the two notices
the features of the books always give, and no other code. Blank lines and
comment lines are left out. A third code, @silence-info@ or a manifest
without @[diagnostics]@ fails here.
-}
silencedNotices :: FilePath -> TestTree
silencedNotices name = testCase "the manifest silences G07030 and G07046 and nothing else (docs/adr/0198)" $ do
  manifest <- TIO.readFile ("test/fixtures" </> name </> "manifest.toml")
  assertEqual
    "[diagnostics] of manifest.toml"
    [["silence-notices = [\"G07030\", \"G07046\"]"]]
    [ [l | l <- map T.strip body, not (T.null l), not ("#" `T.isPrefixOf` l)]
    | (h, body) <- tables manifest,
      h == "[diagnostics]"
    ]

readSources :: FilePath -> IO Sources
readSources dir = do
  files <- sort <$> walk dir
  gms <- mapM TIO.readFile [f | f <- files, takeExtension f == ".gm"]
  emets <- mapM TIO.readFile [f | f <- files, takeExtension f == ".emet"]
  style <- TIO.readFile (dir </> "style.toml")
  manifest <- TIO.readFile (dir </> "manifest.toml")
  pure Sources {srcGm = gms, srcEmet = T.unlines emets, srcStyle = tables style, srcManifest = manifest}
  where
    walk d = do
      entries <- listDirectory d
      concat
        <$> mapM
          ( \e -> do
              isDir <- doesDirectoryExist (d </> e)
              if isDir then (if e == "build" || e == "fonts" then pure [] else walk (d </> e)) else pure [d </> e]
          )
          entries

{- | The tables of a TOML file: each header line (@[...]@ or @[[...]]@)
with the lines up to the next header.
-}
tables :: Text -> [(Text, [Text])]
tables = go "" [] . T.lines
  where
    go h acc [] = [(h, reverse acc)]
    go h acc (l : ls)
      | "[" `T.isPrefixOf` T.strip l = (h, reverse acc) : go (T.strip l) [] ls
      | otherwise = go h (l : acc) ls

-- | Whether a table whose header starts with the prefix has the key (or a subtable of that name).
styleKey :: Text -> Text -> Sources -> Bool
styleKey prefix key s =
  or
    [ any (\l -> (key <> " ") `T.isPrefixOf` T.strip l || (key <> "=") `T.isPrefixOf` T.strip l) body || ("." <> key <> "]") `T.isSuffixOf` h
    | (h, body) <- srcStyle s,
      ("[" <> prefix) `T.isPrefixOf` h
    ]

-- | The value of a key in the table of the header, as written.
styleValue :: Text -> Text -> Sources -> Maybe Text
styleValue header key s =
  case [T.strip (T.drop 1 v) | (h, body) <- srcStyle s, h == header, l <- body, let (k, v) = T.breakOn "=" l, T.strip k == key, not (T.null v)] of
    (v : _) -> Just v
    [] -> Nothing

-- | Every line of every manuscript.
gmLines :: Sources -> [Text]
gmLines = concatMap T.lines . srcGm

hasGm :: Text -> Sources -> Bool
hasGm needle = any (needle `T.isInfixOf`) . srcGm

-- | Lines that start with the prefix and contain the needle.
lineWith :: Text -> Text -> Sources -> Bool
lineWith prefix needle s = or [needle `T.isInfixOf` l | l <- gmLines s, prefix `T.isPrefixOf` l]

-- | The bodies of the bracketed commands of the name: what follows @[name@ up to the matching @]@.
commands :: Text -> Sources -> [Text]
commands name s = concatMap (go . T.unpack) (srcGm s)
  where
    open = T.unpack ("[" <> name)
    go [] = []
    go str@(_ : rest)
      | open `isPrefixOf` str,
        (c : _) <- drop (length open) str,
        c == ' ' || c == ':' =
          T.pack (body 0 (drop (length open) str)) : go rest
      | otherwise = go rest
    body :: Int -> String -> String
    body _ [] = []
    body d ('\\' : c : r) = '\\' : c : body d r
    body d ('[' : r) = '[' : body (d + 1) r
    body d (']' : r)
      | d == 0 = []
      | otherwise = ']' : body (d - 1) r
    body d (c : r) = c : body d r

-- | Whether a line of a manuscript starts with the prefix.
lineStarts :: Text -> Sources -> Bool
lineStarts prefix = any (prefix `T.isPrefixOf`) . gmLines

-- | Whether the body of a command of the name contains the needle.
commandWith :: Text -> Text -> Sources -> Bool
commandWith name needle = any (needle `T.isInfixOf`) . commands name

-- | The figures with a file of one of the extensions.
figureOf :: [String] -> Sources -> Bool
figureOf exts s = or [any (\e -> T.pack e `T.isInfixOf` l) exts | l <- gmLines s, "@figure " `T.isPrefixOf` T.stripStart l]

-- | The features both books use (docs/adr/0175, 「二冊が使う機能」).
common :: [Feature]
common =
  [ ("three levels of headings", \s -> all (\p -> any (p `T.isPrefixOf`) (gmLines s)) ["# ", "## ", "### "]),
    ("heading numbers on the three levels", \s -> all (\n -> isJust (styleValue ("[headings." <> n <> "]") "number" s)) ["1", "2", "3"]),
    ("rule-before and rule-after of a heading", \s -> styleKey "headings." "rule-before" s && styleKey "headings." "rule-after" s),
    ("rule-before and rule-after of a paragraph style", \s -> styleKey "paragraph-styles." "rule-before" s && styleKey "paragraph-styles." "rule-after" s),
    ("a running head with the number of a heading, and a folio", \s -> any (\(h, b) -> "[masters." `T.isPrefixOf` h && any (\l -> "number" `T.isInfixOf` l && "heading." `T.isInfixOf` l) b) (srcStyle s) && styleKey "masters." "folio" s),
    ("the table of contents", hasGm "@toc"),
    ("mono ruby", commandWith "ruby" "/"),
    ("group ruby", not . all ("/" `T.isInfixOf`) . commands "ruby"),
    ("kenten", \s -> commands "kenten" s /= []),
    ("ruby and kenten in headings", \s -> lineWith "#" "[ruby" s && lineWith "#" "[kenten" s),
    ("footnotes with [notes.rule]", \s -> commands "note" s /= [] && any ((== "[notes.rule]") . fst) (srcStyle s)),
    ("a citation in a footnote", commandWith "note" "[cite "),
    ("an SVG figure", figureOf [".svg"]),
    ("a PNG or JPEG figure", figureOf [".png", ".jpg", ".jpeg"]),
    ("a figure with a width that does not wrap (docs/adr/0190)", \s -> or ["width=" `T.isInfixOf` l && not ("wrap=" `T.isInfixOf` l) | l <- gmLines s, "@figure " `T.isPrefixOf` T.stripStart l]),
    ("ref-number and ref-title", \s -> commands "ref-number" s /= [] && commands "ref-title" s /= []),
    ("a table from a file", hasGm "@table data/"),
    ("a table written in the manuscript", \s -> any ("|---" `T.isInfixOf`) (gmLines s) || any ("|:---" `T.isInfixOf`) (gmLines s)),
    ("@listing", lineStarts "@listing "),
    ("a code block", lineStarts "```"),
    ("a numbered list", lineStarts "+ "),
    ("a definition list", lineStarts "= "),
    ("index marks of two levels", any (\c -> "/" `T.isInfixOf` snd (T.breakOn ":" c)) . commands "index"),
    ("index marks in a heading, a footnote and a table cell", \s -> lineWith "#" "[index" s && any ("[index " `T.isInfixOf`) (commands "note" s) && lineWith "|" "[index" s),
    ("the index", \s -> "@index" `elem` map T.strip (gmLines s)),
    ("the bibliography of CSL-JSON", \s -> hasGm "@bibliography" s && "bibliography" `T.isInfixOf` srcManifest s),
    ("an inline and a block function of .emet", \s -> "pub inline" `T.isInfixOf` srcEmet s && "pub block" `T.isInfixOf` srcEmet s && hasGm "@import " s),
    ("a function that reads a TSV with File.read and makes a table", \s -> "File.read" `T.isInfixOf` srcEmet s && "Block.table" `T.isInfixOf` srcEmet s && ".tsv" `T.isInfixOf` srcManifest s),
    ( "a centred title, a signature at the end of the line and a quote spaced and indented on both sides (docs/adr/0189)",
      \s ->
        styleValue "[paragraph-styles.title]" "align" s == Just "\"center\""
          && styleValue "[paragraph-styles.signature]" "align" s == Just "\"right\""
          && all (\k -> isJust (styleValue "[paragraph-styles.quote]" k s)) ["indent", "end-indent", "space-before", "space-after"]
          && all (\n -> lineStarts ("@style " <> n) s) ["title", "signature", "quote"]
    ),
    ("a filter of [[filters]] that changes headings", \s -> "[[filters]]" `T.isInfixOf` srcManifest s && "pub filter" `T.isInfixOf` srcEmet s && "Block.Heading" `T.isInfixOf` srcEmet s)
  ]

-- | The features of the vertical book only.
vertical :: [Feature]
vertical =
  [ ("vertical writing on B6, one column", \s -> styleValue "[page]" "writing-mode" s == Just "\"vertical\"" && styleValue "[page]" "size" s == Just "\"B6\"" && maybe True (== "1") (styleValue "[page.grid]" "columns" s)),
    ("[tcy: ...]", \s -> commands "tcy" s /= []),
    ("[number-text ... style=tcy]", commandWith "number-text" "style=tcy"),
    ("a wrapped figure", lineWith "@figure" "wrap="),
    ("double dashes", hasGm "――"),
    ("an index of two columns", \s -> styleValue "[index]" "columns" s == Just "2")
  ]

-- | The features of the horizontal book only.
horizontal :: [Feature]
horizontal =
  [ ("horizontal writing on A5, two columns", \s -> styleValue "[page]" "writing-mode" s == Just "\"horizontal\"" && styleValue "[page]" "size" s == Just "\"A5\"" && styleValue "[page.grid]" "columns" s == Just "2"),
    ("no wrapped figure", not . lineWith "@figure" "wrap="),
    ("an index of three columns", \s -> styleValue "[index]" "columns" s == Just "3"),
    ("Latin words long enough to be hyphenated", any (any (\w -> T.length w >= 14 && T.all (`elem` ['a' .. 'z']) w) . T.words) . gmLines)
  ]
