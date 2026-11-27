module BibliographyStyleSpec (tests) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Golem.Assemble.BibliographyStyle qualified as Bib
import Golem.Project.Style
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit

tests :: TestTree
tests =
  testGroup "bibliography style declarations" $
    [ testCase "root ADR 0470 I1: no bibliography settings retains the defaults" $ readable "",
      testCase "root ADR 0470 I2: a named custom declaration is read" $
        readable "[bibliography]\nstyle = 'mine'\n[bibliography.styles.mine]\ncitation-mode = 'author-year'\ncitation = ['({author}, {year})']\ncitation-year = ['({year})']\ncitation-delimiter = '; '\ncitation-sort = 'year'\nsubsequent = ['{author} ({first-note})']\nnote-channel = 'endnote'\nsort = ['language', 'author', 'year', 'title', 'citation']\nlanguage-order = ['ja', 'en', '*']\nlabel = '[{number}]'\nhanging-indent = '1zw'\nyear-suffix = true\npage-range = 'minimal'\nrange-delimiter = '–'\nmonths = ['Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.', 'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.']\n[bibliography.styles.mine.types.default]\npieces = ['{author}', '. {title}', '. {year}']\nchar-styles = { title = 'emphasis' }\n[bibliography.styles.mine.locator-labels]\npage = ['p.', 'pp.']\n[bibliography.styles.mine.names.author]\norder = 'first-family-given'\npart-delimiter = ', '\ninitials = true\ninitial-format = '{i}.'\ninitial-delimiter = ' '\ndelimiter = ', '\nlast-delimiter = ' & '\nmax = 6\nuse-first = 3\net-al = ' et al.'\n[bibliography.styles.mine.names.editor]\nlabel = ['ed.', 'eds.']\n[bibliography.styles.mine.names.short]\ndelimiter = ', '\nlast-delimiter = ' and '\nmax = 3\nuse-first = 1\net-al = ' et al.'\n[bibliography.styles.mine.languages.ja]\ncitation-delimiter = '、'\n[bibliography.styles.mine.languages.ja.types.book]\npieces = ['{author}', '『{title}』', '、{year:kanji}年']\n",
      testCase "root ADR 0470 I2: declarations retain their typed values" $ do
        value <- declaration "[bibliography]\nstyle = 'mine'\n[bibliography.styles.mine]\ncitation-mode = 'note'\nnote-channel = 'endnote'\ncitation = ['{author}']\nsort = ['author', 'year']\nhanging-indent = '1zw'\nyear-suffix = false\ncitation-delimiter = ', '\ncitation-sort = 'written'\npage-range = 'full'\nrange-delimiter = '–'\n[bibliography.styles.mine.names.author]\norder = 'given-family'\npart-delimiter = ' '\ndelimiter = ', '\nlast-delimiter = ' and '\nmax = 0\nuse-first = 0\ninitials = false\net-al = ''\n[bibliography.styles.mine.types.book]\npieces = ['{title}']\nchar-styles = { title = 'emphasis' }\n"
        Bib.bsCitationMode value @?= Just "note"
        Bib.bsNoteChannel value @?= Just "endnote"
        Bib.bsCitation value @?= Just ["{author}"]
        Bib.bsSort value @?= Just ["author", "year"]
        Bib.bsHangingIndent value @?= Just (Zw 1)
        Bib.bsYearSuffix value @?= Just False
        fmap Bib.bnMax (Map.lookup "author" (Bib.bsNames value)) @?= Just (Just 0)
        fmap Bib.bnInitials (Map.lookup "author" (Bib.bsNames value)) @?= Just (Just False)
        Map.lookup "book" (Bib.bsTypes value) @?= Just (Bib.BibliographyType (Just ["{title}"]) (Map.singleton "title" "emphasis")),
      testCase "root ADR 0470 I2: language overrides preserve absence and explicit empty values" $ do
        value <- declaration "[bibliography.styles.mine]\ncitation-delimiter = '; '\ncitation-mode = 'numeric'\ncitation = []\ncitation-sort = 'written'\nsort = []\nhanging-indent = '0pt'\nyear-suffix = false\npage-range = 'full'\nrange-delimiter = '–'\n[bibliography.styles.mine.languages.ja]\ncitation-delimiter = ''\nsort = []\n"
        Bib.bsCitationDelimiter value @?= Just "; "
        case Map.lookup "ja" (Bib.bsLanguages value) of
          Just override -> do
            Bib.bsCitationDelimiter override @?= Just ""
            Bib.bsSort override @?= Just []
            Bib.bsCitationMode override @?= Nothing
          Nothing -> assertFailure "missing language override",
      testCase "root ADR 0470 I7: a missing selected style reports G03303" $
        codes "[bibliography]\nstyle = 'missing'\n" @?= ["G03303"],
      testCase "root ADR 0470 I7: each malformed format value reports G03304" $
        codes "[bibliography.styles.mine]\ncitation = ['{typo}', '{typo}']\nsubsequent = ['{year:unknown}']\ncitation-mode = 'numeric'\ncitation-delimiter = ', '\ncitation-sort = 'written'\nsort = []\nhanging-indent = '0pt'\nyear-suffix = false\npage-range = 'full'\nrange-delimiter = '–'\n[bibliography.styles.mine.types.default]\npieces = ['{title']\n" @?= replicate 4 "G03304",
      testCase "root ADR 0470 I7: a malformed initial format reports G03304" $
        codes "[bibliography.styles.mine]\ncitation-mode = 'numeric'\ncitation = []\ncitation-delimiter = ', '\ncitation-sort = 'written'\nsort = []\nhanging-indent = '0pt'\nyear-suffix = false\npage-range = 'full'\nrange-delimiter = '–'\n[bibliography.styles.mine.names.author]\ninitial-format = '{unknown}'\n" @?= ["G03304"],
      testCase "root ADR 0470 I7: built-in style declarations cannot be overwritten" $
        codes "[bibliography.styles.ieee]\ncitation = ['{number}']\ncitation-mode = 'numeric'\ncitation-delimiter = ', '\ncitation-sort = 'written'\nsort = []\nhanging-indent = '0pt'\nyear-suffix = false\npage-range = 'full'\nrange-delimiter = '–'\n" @?= ["G03305"]
    ]
      <> [ testCase ("root ADR 0470 I2: built-in name " <> show name) $
             readable ("[bibliography]\nstyle = '" <> name <> "'\n")
         | name <- ["golem", "ieee", "vancouver", "sist02", "unified-linguistics", "chicago-notes-bibliography", "chicago-author-date", "apa"]
         ]
      <> [ testCase ("root ADR 0470 I7: invalid declaration value " <> show value) $
             codes ("[bibliography.styles.mine]\n" <> value <> "\n") @?= ["G03006"]
         | value <- ["citation-mode = 'unknown'", "citation = 'wrong'", "citation-sort = 'author'", "note-channel = 'sidenote'", "sort = ['unknown']", "hanging-indent = '-1pt'", "months = ['Jan.']", "unknown = true"]
         ]
      <> [ testCase ("root ADR 0470 I7: invalid name option " <> show value) $
             codes ("[bibliography.styles.mine.names.author]\n" <> value <> "\n") @?= ["G03006"]
         | value <- ["order = 'unknown'", "max = -1", "max = 2147483648", "max = 1.5", "initials = 'yes'", "label = ['ed.', 'eds.']"]
         ]

readable :: Text -> Assertion
readable input = case parseStyle (FileId 0) input of
  Right _ -> pure ()
  Left ds -> assertFailure (show ds)

codes :: Text -> [Text]
codes input = case parseStyle (FileId 0) input of
  Right _ -> []
  Left ds -> [code | d <- ds, let DiagnosticCode code = diagCode d]

declaration :: Text -> IO (Bib.BibliographyStyle Dim)
declaration input = case parseStyle (FileId 0) input of
  Right style -> maybe (assertFailure "missing declaration" >> fail "missing declaration") pure (Map.lookup "mine" (Bib.bibStyles (stBibliography style)))
  Left diagnostics -> assertFailure (show diagnostics) >> fail "declaration did not read"
