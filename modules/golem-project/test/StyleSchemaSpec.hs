{- | The schema of style.toml (docs/adr ADR 0169): every key of the schema
is one the decoder reads, the unknown keys keep their messages, codes and
positions, an error of a value does not hide an unknown key, and the keys
of @style-def come from the schema.
-}
module StyleSchemaSpec (tests) where

import Data.ByteString qualified as BS
import Data.List (isPrefixOf)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Project.Style
import Golem.Project.TomlSchema
import Golem.Syntax
import Test.Tasty
import Test.Tasty.HUnit
import Toml.Schema (FromValue (..), MatchMessage (..), Matcher, Result (..), Value, Value' (..), runMatcher, table)

-- | A step of a path of the schema: a key, a name of a named table, an element of an array.
data Step = SKey Text | SName | SIndex
  deriving stock (Show)

-- | Every key of a schema, with the path to it and its node.
keyPaths :: Node -> [([Step], Node)]
keyPaths = go []
  where
    go pre = \case
      NTable kvs -> concat [(pre <> [SKey k], n) : go (pre <> [SKey k]) n | (k, n) <- kvs]
      NNamed _ n -> go (pre <> [SName]) n
      NArray n -> go (pre <> [SIndex]) n
      NEither ns -> concatMap (go pre) ns
      _ -> []

-- | A TOML document with the value at the path, and the keys each table along it requires.
docWith :: [Step] -> Value -> Value
docWith steps leaf = go [] steps
  where
    go here = \case
      [] -> leaf
      SKey k : rest -> Table (table ((k, go (here <> [k]) rest) : [kv | kv@(k', _) <- required here k, k' /= k]))
      SName : rest ->
        let n = if here == ["headings"] then "1" else "x"
         in Table (table [(n, go (here <> [n]) rest)])
      SIndex : rest -> List [go (here <> ["[]"]) rest]

-- | The keys a table at a path needs besides the key written there.
required :: [Text] -> Text -> [(Text, Value)]
required here k = case here of
  ["page"] -> [("size", Text "B6")]
  ["page", "size"] -> [("width", Text "100mm"), ("height", Text "100mm")]
  ["page", "grid"] ->
    [ ("font-size", Text "10pt"),
      ("characters", Integer 40),
      ("lines", Integer 30),
      ("line-pitch", Text "16pt"),
      ("position", Table (table [("top", Text "10mm"), ("gutter", Text "10mm")]))
    ]
  ["page", "grid", "position"] -> [("top", Text "10mm"), ("gutter", Text "10mm")]
  ["aki-sets", _, "rules", _] -> [("before", Text "opening"), ("after", Text "closing"), ("optimum", Text "四分")]
  ["paragraph-styles", _, "regex-styles", _] -> [("pattern", Text "x"), ("style", Text "bold")]
  ["composition", "expansion"] -> [("limit", Integer 1), ("step", Integer 1)]
  ["sidenotes"] -> [("width", Text "10mm"), ("gap", Text "1mm")]
  ["masters", _, "running-head"] ->
    ("position", Text "top-outside") : case k of
      "even" -> [("odd", Text "title")]
      "odd" -> [("even", Text "title")]
      "content" -> []
      _ -> [("content", Text "title")]
  ["masters", _, "folio"] -> [("position", Text "bottom-center")]
  ["color", "swatches", _] -> [("cmyk", cmyk)]
  ["notes", "rule"] -> ("length", Text "10mm") : dashed
  _ | take 1 (reverse here) `elem` [["rule-before"], ["rule-after"]] -> dashed
  _ -> []
  where
    -- a dash or a gap is for the styles of dashes and dots (golem-driver ADR 0028)
    dashed = [("style", Text "dashed") | k `elem` ["dash", "gap"]]

cmyk :: Value
cmyk = List [Integer 0, Integer 0, Integer 0, Integer 0]

-- | A value the decoder reads for the node at the path.
sample :: [Text] -> Node -> Value
sample here node = case (reverse here, node) of
  (k : _, _) | k `elem` ["content", "even", "odd"], "running-head" `elem` here -> Text "title"
  ("cmyk" : _, _) -> cmyk
  (k : "[]" : "rules" : _, _) | k `elem` ["optimum", "minimum", "maximum"] -> Text "四分"
  ("mark-format" : _, _) -> Text "{n}"
  ("numbers" : "lists" : _, _) -> List [Text "{n}"]
  _ -> case node of
    NValue l -> leafSample l
    NTable _ -> Table (table (required here ""))
    NNamed _ _ -> Table (table [])
    NArray (NValue l) -> List [leafSample l]
    NArray _ -> List []
    NEither (n : _) -> sample here n
    _ -> Text "x"
  where
    leafSample = \case
      LString -> Text "x"
      LDimension -> Text "1pt"
      LInteger -> Integer 1
      LBoolean -> Bool False
      LFalse -> Bool False
      LEnum (v : _) -> Text v
      LEnum [] -> Text "x"
      LRef _ -> Text "x"

-- | The path of keys of the steps, with the names of 'docWith'.
keysOf :: [Step] -> [Text]
keysOf = go []
  where
    go here = \case
      [] -> here
      SKey k : rest -> go (here <> [k]) rest
      SName : rest -> go (here <> [if here == ["headings"] then "1" else "x"]) rest
      SIndex : rest -> go (here <> ["[]"]) rest

-- | The values of the enumerations of a node.
enumValues :: Node -> [Value]
enumValues = \case
  NValue (LEnum vs) -> map Text vs
  NEither ns -> concatMap enumValues ns
  NArray n -> [List [v] | v <- enumValues n]
  _ -> []

decodeStyle :: Value -> Result (MatchMessage ()) Style
decodeStyle v = runMatcher (fromValue v :: Matcher () Style)

unexpected :: MatchMessage () -> Bool
unexpected = isPrefixOf "unexpected key: " . matchMessage

-- | The code, message, line and column (from 1) of each diagnostic.
located :: Text -> [Diagnostic] -> [(Text, Text, Int, Int)]
located src ds =
  [ (c, diagMessage d, lcLine lc + 1, lcColumn lc + 1)
  | d <- ds,
    let DiagnosticCode c = diagCode d
        lc = offsetToLineCol (mkLineIndex src) (spanStart (diagSpan d))
  ]

errorsOf :: Text -> [(Text, Text, Int, Int)]
errorsOf src = either (located src) (const []) (parseStyle (FileId 0) src)

tests :: TestTree
tests =
  testGroup
    "the schema of style.toml (docs/adr ADR 0169)"
    [ testCase "every key of the schema is read by the decoder" $ do
        let paths = keyPaths styleSchema
        assertBool "the schema has keys" (length paths > 100)
        mapM_
          ( \(steps, node) -> do
              let here = keysOf steps
              case node of
                NRejected -> case decodeStyle (docWith steps (Text "x")) of
                  Failure es -> assertBool (show (here, es)) (not (any unexpected es))
                  Success ws _ -> assertFailure ("a rejected key is accepted: " <> show (here, ws))
                _ -> case decodeStyle (docWith steps (sample here node)) of
                  Success ws _ -> assertBool (show (here, ws)) (not (any unexpected ws))
                  Failure es -> assertFailure ("the sample does not read: " <> show (here, es))
          )
          paths,
      testCase "every value of an enumeration is read at its key" $
        mapM_
          ( \(steps, node) ->
              mapM_
                ( \v -> case decodeStyle (docWith steps v) of
                    Success [] _ -> pure ()
                    r -> assertFailure (show (keysOf steps, v, r))
                )
                (enumValues node)
          )
          (keyPaths styleSchema),
      testCase "an unknown key of [page]: G03006 at the key" $
        errorsOf "[page]\nsize = \"B6\"\nunknown = 1\n" @?= [("G03006", "知らないキーです: page.unknown", 3, 1)],
      testCase "an unknown key of a paragraph style: G03006 at the key" $
        errorsOf "[paragraph-styles.body]\ncolour = \"x\"\n" @?= [("G03006", "知らないキーです: paragraph-styles.body.colour", 2, 1)],
      testCase "an unknown key of [page.size]: G03017 at the key" $
        errorsOf "[page.size]\nwidth = \"100mm\"\nheight = \"100mm\"\ndepth = \"1mm\"\n" @?= [("G03017", "知らないキーです: page.size.depth", 4, 1)],
      testCase "an unknown key of a regex style: G03006 with the index in the path" $
        errorsOf "[paragraph-styles.body]\nregex-styles = [{ pattern = \"x\", style = \"bold\", colour = 1 }]\n"
          @?= [("G03006", "知らないキーです: paragraph-styles.body.regex-styles[0].colour", 2, 50)],
      testCase "an error of a value and an unknown key are both reported, in the order of their positions" $
        errorsOf "[page]\nsize = \"B6\"\nbleed = \"1zw\"\nunknown = 1\n"
          @?= [ ("G03006", "塗り足しには zw を使えません (page.bleed)", 3, 9),
                ("G03006", "知らないキーです: page.unknown", 4, 1)
              ],
      testCase "an unknown key before an error of a value comes first" $
        errorsOf "[page]\nunknown = 1\nsize = \"B6\"\nbleed = \"1zw\"\n"
          @?= [ ("G03006", "知らないキーです: page.unknown", 2, 1),
                ("G03006", "塗り足しには zw を使えません (page.bleed)", 4, 9)
              ],
      testCase "a value outside an enumeration keeps its message" $
        errorsOf "[paragraph-styles.body]\nline-breaks = \"x\"\n"
          @?= [("G03006", "line-breaks に使えない値です: x（join, keep のどれか） (paragraph-styles.body.line-breaks)", 2, 15)],
      testCase "a kerning outside its values keeps its message and code" $
        errorsOf "[character-styles.em]\nkerning = \"x\"\n"
          @?= [("G03021", "kerning の値が正しくありません: x (character-styles.em.kerning)", 2, 11)],
      testCase "the keys of @style-def are those of the schema, in its order" $ do
        charStyleKeys @?= ["based-on", "font", "size", "color", "synthetic-bold", "synthetic-italic", "kerning", "tracking", "proportional-metrics", "baseline-shift", "background", "padding"]
        paraStyleKeys @?= ["based-on", "font", "size", "line-breaks", "space-between", "space-before", "space-after", "align", "indent", "first-line-indent", "end-indent", "aki-set", "kerning", "tracking", "proportional-metrics", "baseline-shift", "background", "padding", "border", "border-width"]
        regexStyleKeys @?= ["pattern", "style"],
      testCase "the values of line-breaks are those the decoder reads" $
        lineBreaksValues @?= ["join", "keep"],
      testCase "the byte offsets of the positions are in UTF-8" $
        let src = "# 日本語\n[page]\nsize = \"B6\"\nunknown = 1\n"
         in case parseStyle (FileId 0) src of
              Left [d] -> spanStart (diagSpan d) @?= BS.length (TE.encodeUtf8 (fst (T.breakOn "unknown" src)))
              r -> assertFailure (show r)
    ]
