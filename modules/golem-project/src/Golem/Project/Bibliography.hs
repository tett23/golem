-- | Reading and checking bibliography declarations (root ADR 0470).
module Golem.Project.Bibliography
  ( bibliographyOf,
    bibliographyChecks,
    bibliographySchema,
  )
where

import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Assemble.BibliographyFormats (parseBibliographyPiece)
import Golem.Assemble.BibliographyNames (parseInitialFormat)
import Golem.Assemble.BibliographyStyle
import Golem.Project.BibliographyRequirements (bibliographyAllRequiredChecks)
import Golem.Project.Manifest (maxNaturalInt)
import Golem.Project.TomlSchema
import Toml.Schema
import Toml.Semantics (valueAnn)

-- | The dimension reader is supplied by Style, keeping its type out of this module.
bibliographyOf :: (Value' l -> Matcher l d) -> Value' l -> Matcher l (Bibliography d)
bibliographyOf dimension = parseTableFromValue $ Bibliography . fromMaybe "golem" <$> optKey "style" <*> (fromMaybe Map.empty <$> optKeyOf "styles" (namedOf (declarationOf dimension True)))

namedOf :: (Value' l -> Matcher l a) -> Value' l -> Matcher l (Map Text a)
namedOf reader value@(Table' _ (MkTable entries)) =
  flip parseTableFromValue value $ Map.fromList <$> traverse (\key -> (key,) <$> reqKeyOf key reader) (Map.keys entries)
namedOf _ value = failAt (valueAnn value) "名前をキーに持つ表を書きます"

declarationOf :: (Value' l -> Matcher l d) -> Bool -> Value' l -> Matcher l (BibliographyStyle d)
declarationOf dimension languages = parseTableFromValue $ do
  mode <- enumKey "citation-mode" ["numeric", "author-year", "note"]
  citation <- optKey "citation"
  citationYear <- optKey "citation-year"
  delimiter <- optKey "citation-delimiter"
  citationPrefix <- optKey "citation-prefix"
  citationSuffix <- optKey "citation-suffix"
  citationSort <- enumKey "citation-sort" ["written", "year"]
  subsequent <- optKey "subsequent"
  channel <- enumKey "note-channel" ["footnote", "endnote"]
  sortKeys <- optKeyOf "sort" $ \value -> do
    keys <- fromValue value
    if all (`elem` ["citation", "author", "year", "title", "language"]) keys then pure keys else failAt (valueAnn value) "sort に使えないキーがあります"
  languageOrder <- optKey "language-order"
  label <- optKey "label"
  indent <- optKeyOf "hanging-indent" dimension
  suffix <- optKey "year-suffix"
  pageRange <- enumKey "page-range" ["full", "minimal"]
  rangeDelimiter <- optKey "range-delimiter"
  months <- optKeyOf "months" $ \value -> do
    values <- fromValue value
    if length values == 12 then pure values else failAt (valueAnn value) "months は12個の文字列の配列です"
  locatorLabels <- fromMaybe Map.empty <$> optKeyOf "locator-labels" (namedOf pairOf)
  types <- fromMaybe Map.empty <$> optKeyOf "types" (namedOf typeOf)
  names <- fromMaybe Map.empty <$> optKeyOf "names" namesOf
  overrides <- if languages then fromMaybe Map.empty <$> optKeyOf "languages" (namedOf (declarationOf dimension False)) else pure Map.empty
  pure (BibliographyStyle mode citation citationYear delimiter citationPrefix citationSuffix citationSort subsequent channel sortKeys languageOrder label indent suffix pageRange rangeDelimiter months locatorLabels types names overrides)

pairOf :: Value' l -> Matcher l (Text, Text)
pairOf value =
  fromValue value >>= \case
    [one, many] -> pure (one, many)
    _ -> failAt (valueAnn value) "単数と複数の二つの文字列の配列です"

typeOf :: Value' l -> Matcher l BibliographyType
typeOf = parseTableFromValue $ BibliographyType <$> optKey "pieces" <*> (fromMaybe Map.empty <$> optKey "char-styles")

namesOf :: Value' l -> Matcher l (Map Text BibliographyNames)
namesOf = parseTableFromValue $ do
  author <- optKeyOf "author" (nameOf False False)
  editor <- optKeyOf "editor" (nameOf False True)
  short <- optKeyOf "short" (nameOf True False)
  pure (Map.fromList [(key, value) | (key, Just value) <- [("author", author), ("editor", editor), ("short", short)]])

nameOf :: Bool -> Bool -> Value' l -> Matcher l BibliographyNames
nameOf short editor = parseTableFromValue $ do
  order <- unlessShort (enumKey "order" ["family-given", "given-family", "first-family-given"])
  partDelimiter <- unlessShort (optKey "part-delimiter")
  initials <- unlessShort (optKey "initials")
  initialFormat <- unlessShort (optKey "initial-format")
  initialDelimiter <- unlessShort (optKey "initial-delimiter")
  delimiter <- optKey "delimiter"
  lastDelimiter <- optKey "last-delimiter"
  maximumNames <- optKeyOf "max" countOf
  useFirst <- optKeyOf "use-first" countOf
  useLast <- optKeyOf "use-last" countOf
  pairDelimiter <- optKey "pair-delimiter"
  etAl <- optKey "et-al"
  label <- if editor then optKeyOf "label" pairOf else pure Nothing
  pure (BibliographyNames order partDelimiter initials initialFormat initialDelimiter delimiter lastDelimiter maximumNames useFirst useLast pairDelimiter etAl label)
  where
    unlessShort action = if short then pure Nothing else action

-- | A name count reports the style's G03006, not the general G02103.
countOf :: Value' l -> Matcher l Int
countOf value = case value of
  Integer' _ number | number >= 0 && number <= toInteger maxNaturalInt -> pure (fromInteger number)
  _ -> failAt (valueAnn value) "名前の数は0以上の整数です"

enumKey :: Text -> [Text] -> ParseTable l (Maybe Text)
enumKey key allowed = optKeyOf key $ \value -> do
  text <- fromValue value
  if text `elem` allowed then pure text else failAt (valueAnn value) (T.unpack (key <> " に使えない値です: " <> text))

-- | Format and reference checks keep paths for diagnostics at each written value.
bibliographyChecks :: Bibliography d -> [(Text, Text, [Scope], Text)]
bibliographyChecks bibliography = selected <> concatMap declaration (Map.toList (bibStyles bibliography)) <> bibliographyAllRequiredChecks bibliography
  where
    selected = [("G03303", "", [ScopeKey "bibliography", ScopeKey "style"], "参考文献のスタイル " <> bibSelected bibliography <> " がありません") | bibSelected bibliography `notElem` builtinBibliographyNames, Map.notMember (bibSelected bibliography) (bibStyles bibliography)]
    declaration (name, style) =
      let base = [ScopeKey "bibliography", ScopeKey "styles", ScopeKey name]
       in [("G03305", name, base, name <> " は決まったスタイルの名前なので、宣言できません") | name `elem` builtinBibliographyNames] <> formats name base style
    formats name base style =
      concat [pieces key values | (key, Just values) <- [("citation", bsCitation style), ("citation-year", bsCitationYear style), ("subsequent", bsSubsequent style)]]
        <> [bad [ScopeKey "label"] reason | Just text <- [bsLabel style], Left reason <- [parseBibliographyPiece bibliographyFields text]]
        <> concat [concat [piecesAt [ScopeKey "types", ScopeKey kind, ScopeKey "pieces"] values | Just values <- [btPieces entry]] | (kind, entry) <- Map.toList (bsTypes style)]
        <> [bad [ScopeKey "names", ScopeKey role, ScopeKey "initial-format"] reason | (role, names) <- Map.toList (bsNames style), Just text <- [bnInitialFormat names], Left reason <- [parseInitialFormat text]]
        <> concat [formats name (base <> [ScopeKey "languages", ScopeKey language]) override | (language, override) <- Map.toList (bsLanguages style)]
      where
        pieces key = piecesAt [ScopeKey key]
        piecesAt path values = [bad (path <> [ScopeIndex index]) reason | (index, text) <- zip [0 ..] values, Left reason <- [parseBibliographyPiece bibliographyFields text]]
        bad path reason =
          let key = T.intercalate "." [case scope of ScopeKey text -> text; ScopeIndex index -> "[" <> T.pack (show index) <> "]" | scope <- drop 3 (base <> path)]
           in ("G03304", name, base <> path, "参考文献のスタイル " <> name <> " の " <> key <> " を書式として読めません: " <> reason)

bibliographySchema :: Node
bibliographySchema = NTable [("style", str), ("styles", NNamed Nothing (declarationNode True))]
  where
    declarationNode languages =
      NTable $
        [ ("citation-mode", enumeration ["numeric", "author-year", "note"]),
          ("citation", strings),
          ("citation-year", strings),
          ("citation-delimiter", str),
          ("citation-prefix", str),
          ("citation-suffix", str),
          ("citation-sort", enumeration ["written", "year"]),
          ("subsequent", strings),
          ("note-channel", enumeration ["footnote", "endnote"]),
          ("sort", NArray (enumeration ["citation", "author", "year", "title", "language"])),
          ("language-order", strings),
          ("label", str),
          ("hanging-indent", NValue LDimension),
          ("year-suffix", boolean),
          ("page-range", enumeration ["full", "minimal"]),
          ("range-delimiter", str),
          ("months", strings),
          ("locator-labels", NTable [(label, strings) | label <- bibliographyLocatorNames]),
          ("types", NNamed Nothing (NTable [("pieces", strings), ("char-styles", NNamed Nothing (NValue (LRef CharStyles)))])),
          ("names", NTable [("author", namesNode False False), ("editor", namesNode False True), ("short", namesNode True False)])
        ]
          <> [("languages", NNamed Nothing (declarationNode False)) | languages]
    namesNode short editor =
      NTable $
        (if short then [] else [("order", enumeration ["family-given", "given-family", "first-family-given"]), ("part-delimiter", str), ("initials", boolean), ("initial-format", str), ("initial-delimiter", str)])
          <> [("delimiter", str), ("last-delimiter", str), ("max", NValue LInteger), ("use-first", NValue LInteger), ("use-last", NValue LInteger), ("pair-delimiter", str), ("et-al", str)]
          <> [("label", strings) | editor]
    str = NValue LString
    strings = NArray str
    boolean = NValue LBoolean
    enumeration = NValue . LEnum
