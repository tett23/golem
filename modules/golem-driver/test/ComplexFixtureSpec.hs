{- | The two books that combine the features of Golem
(test/fixtures/complex-vertical and test/fixtures/complex-horizontal,
docs/adr/0175). Their outputs are fixed by the goldens of
'OutputGoldenSpec'; this module reads their sources (the @.gm@, the
@.emet@, @style.toml@ and @manifest.toml@) and checks that each feature the
ADR lists is written there at least once, so that a later edit that drops
a feature from a book fails a test instead of leaving the interaction
unchecked.

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
    [ testCase feature $ do
        s <- readSources ("test/fixtures" </> name)
        assertBool ("the book does not use: " <> feature) (check s)
    | (feature, check) <- features
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
    [ any ((key <> " ") `T.isPrefixOf`) (map T.strip body) || any ((key <> "=") `T.isPrefixOf`) (map T.strip body) || ("." <> key <> "]") `T.isSuffixOf` h
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
    ("mono ruby", \s -> any ("/" `T.isInfixOf`) (commands "ruby" s)),
    ("group ruby", \s -> any (not . ("/" `T.isInfixOf`)) (commands "ruby" s)),
    ("kenten", \s -> commands "kenten" s /= []),
    ("ruby and kenten in headings", \s -> lineWith "#" "[ruby" s && lineWith "#" "[kenten" s),
    ("footnotes with [notes.rule]", \s -> commands "note" s /= [] && any ((== "[notes.rule]") . fst) (srcStyle s)),
    ("a citation in a footnote", \s -> any ("[cite " `T.isInfixOf`) (commands "note" s)),
    ("an SVG figure", figureOf [".svg"]),
    ("a PNG or JPEG figure", figureOf [".png", ".jpg", ".jpeg"]),
    ("ref-number and ref-title", \s -> commands "ref-number" s /= [] && commands "ref-title" s /= []),
    ("a table from a file", hasGm "@table src="),
    ("a table written in the manuscript", \s -> any ("|---" `T.isInfixOf`) (gmLines s) || any ("|:---" `T.isInfixOf`) (gmLines s)),
    ("@listing", \s -> any ("@listing " `T.isPrefixOf`) (gmLines s)),
    ("a code block", \s -> any ("```" `T.isPrefixOf`) (gmLines s)),
    ("a numbered list", \s -> any ("+ " `T.isPrefixOf`) (gmLines s)),
    ("a definition list", \s -> any ("= " `T.isPrefixOf`) (gmLines s)),
    ("index marks of two levels", \s -> any (\c -> "/" `T.isInfixOf` snd (T.breakOn ":" c)) (commands "index" s)),
    ("index marks in a heading, a footnote and a table cell", \s -> lineWith "#" "[index" s && any ("[index " `T.isInfixOf`) (commands "note" s) && lineWith "|" "[index" s),
    ("the index", \s -> "@index" `elem` map T.strip (gmLines s)),
    ("the bibliography of CSL-JSON", \s -> hasGm "@bibliography" s && "bibliography" `T.isInfixOf` srcManifest s),
    ("an inline and a block function of .emet", \s -> "pub inline" `T.isInfixOf` srcEmet s && "pub block" `T.isInfixOf` srcEmet s && hasGm "@import " s),
    ("a function that reads a TSV with File.read and makes a table", \s -> "File.read" `T.isInfixOf` srcEmet s && "Block.table" `T.isInfixOf` srcEmet s && ".tsv" `T.isInfixOf` srcManifest s),
    ("a filter of [[filters]] that changes headings", \s -> "[[filters]]" `T.isInfixOf` srcManifest s && "pub filter" `T.isInfixOf` srcEmet s && "Block.Heading" `T.isInfixOf` srcEmet s)
  ]

-- | The features of the vertical book only.
vertical :: [Feature]
vertical =
  [ ("vertical writing on B6, one column", \s -> styleValue "[page]" "writing-mode" s == Just "\"vertical\"" && styleValue "[page]" "size" s == Just "\"B6\"" && maybe True (== "1") (styleValue "[page.grid]" "columns" s)),
    ("[tcy: ...]", \s -> commands "tcy" s /= []),
    ("[number-text ... style=tcy]", \s -> any ("style=tcy" `T.isInfixOf`) (commands "number-text" s)),
    ("a wrapped figure", \s -> lineWith "@figure" "wrap=" s),
    ("double dashes", hasGm "――"),
    ("an index of two columns", \s -> styleValue "[index]" "columns" s == Just "2")
  ]

-- | The features of the horizontal book only.
horizontal :: [Feature]
horizontal =
  [ ("horizontal writing on A5, two columns", \s -> styleValue "[page]" "writing-mode" s == Just "\"horizontal\"" && styleValue "[page]" "size" s == Just "\"A5\"" && styleValue "[page.grid]" "columns" s == Just "2"),
    ("no wrapped figure", \s -> not (lineWith "@figure" "wrap=" s)),
    ("an index of three columns", \s -> styleValue "[index]" "columns" s == Just "3"),
    ("Latin words long enough to be hyphenated", \s -> any (\w -> T.length w >= 14 && T.all (`elem` ['a' .. 'z']) w) (concatMap T.words (gmLines s)))
  ]
