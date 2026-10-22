{- | lint rules (golem-lint ADR 0001). Rules cannot be configured,
extended or suppressed; only near-certain mistakes are reported.
-}
module Golem.Lint
  ( LintInput (..),
    FileLint (..),
    lint,
    latinJoinedByNewline,
    isLatinScript,
  )
where

import Data.Char (isAlphaNum, ord)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (listToMaybe)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as T
import Golem.Eval.File (Usage (..))
import Golem.Parser.CST
import Golem.Parser.SourceSettings
import Golem.Syntax

data FileLint = FileLint
  { flFile :: !FileId,
    flPath :: !FilePath,
    flCst :: !Node,
    -- | how the file was read (docs/adr ADR 0013)
    flSource :: !SourceSettings,
    flUsage :: !Usage
  }

data LintInput = LintInput
  { liFiles :: ![FileLint],
    liLabels :: !(Map Text SrcSpan), -- defined labels
    liReferenced :: !(Set Text),
    -- | the paragraph styles with line-breaks = "keep" (docs/adr ADR 0005)
    liKeepStyles :: !(Set Text)
  }

lint :: LintInput -> [Diagnostic]
lint input =
  sortDiagnostics $
    concatMap (\f -> latinJoinedByNewline (flSource f) (liKeepStyles input) (flFile f) (flCst f)) (liFiles input)
      <> unusedVariables input
      <> unusedImports input
      <> unreferencedLabels input

-- | Letters and digits of the Latin, Greek and Cyrillic scripts.
isLatinScript :: Char -> Bool
isLatinScript c =
  isAlphaNum c
    && ( ord c < 0x80
           || (ord c >= 0x00C0 && ord c <= 0x024F)
           || (ord c >= 0x1E00 && ord c <= 0x1EFF)
           || (ord c >= 0x0370 && ord c <= 0x04FF)
       )

{- | G05001: a newline inside a paragraph between two Latin characters
joins the words without a space. The newlines of a paragraph in a
paragraph style that keeps its lines (the body of @style, or the target
of an attribute group with @style) break lines, and those of a paragraph
or a list item in the line style separate paragraphs; only the prose
slots inside them are checked (docs/adr ADR 0003, 0005, 0013).
-}
latinJoinedByNewline :: SourceSettings -> Set Text -> FileId -> Node -> [Diagnostic]
latinJoinedByNewline source keep fid = go 0
  where
    lineStyle = ssParagraphSeparator source == LineSeparated
    go start n
      | isKeepStyle n = verseBody start (nodeChildren n)
      | nodeKind n == NAttributed && or [isKeepStyle m | ElemNode m <- nodeChildren n] = keepTarget start (nodeChildren n)
      -- in the line style a newline of a paragraph separates paragraphs (docs/adr ADR 0013)
      | lineStyle && nodeKind n `elem` [NParagraph, NListItem] = proseSlots start (nodeChildren n)
      | nodeKind n `elem` [NParagraph, NProseSlot, NListItem, NDefTerm] = scan start (nodeChildren n)
      | otherwise = descend start (nodeChildren n)
    -- @style with the name of a style that keeps its lines
    isKeepStyle n =
      nodeKind n == NBlockCommand
        && listToMaybe [tokText t | ElemToken t <- nodeChildren n, tokKind t == KIdent] == Just "style"
        && maybe False (`Set.member` keep) (listToMaybe [tokText t | ElemNode a <- nodeChildren n, nodeKind a == NArgument, ElemToken t <- nodeChildren a, tokKind t == KWord])
    -- the paragraph of an attribute group: only its prose slots
    keepTarget _ [] = []
    keepTarget s (e : es) =
      ( case e of
          ElemNode m
            | nodeKind m == NParagraph -> proseSlots s (nodeChildren m)
            | otherwise -> go s m
          _ -> []
      )
        <> keepTarget (s + elementWidth e) es
    -- paragraphs of the body: only their prose slots
    verseBody _ [] = []
    verseBody s (e : es) =
      ( case e of
          ElemNode m
            | nodeKind m == NCommandBody -> verseBody s (nodeChildren m)
            | nodeKind m == NParagraph -> proseSlots s (nodeChildren m)
            | otherwise -> go s m
          _ -> []
      )
        <> verseBody (s + elementWidth e) es
    proseSlots _ [] = []
    proseSlots s (e : es) =
      ( case e of
          ElemNode m
            | nodeKind m == NProseSlot -> go s m
            | otherwise -> proseSlots s (nodeChildren m)
          _ -> []
      )
        <> proseSlots (s + elementWidth e) es
    descend _ [] = []
    descend s (e : es) = (case e of ElemNode m -> go s m; _ -> []) <> descend (s + elementWidth e) es
    -- tokens of this node in order with their offsets, nested nodes searched separately
    scan start cs =
      let toks = flat start cs
          hits =
            [ diagnostic "G05001" Error (mkSpan fid off (off + 1)) "改行の前後が欧文なので、単語が空白なしにつながります。一行で書いてください"
            | (i, (off, Token KNewline _)) <- zip [0 :: Int ..] toks,
              Just before <- [lastChar (map snd (take i toks))],
              isLatinScript before,
              Just after <- [firstChar (map snd (drop (i + 1) toks))],
              isLatinScript after
            ]
       in hits <> nested start cs
    nested _ [] = []
    nested s (e : es) = (case e of ElemNode m | nodeKind m == NProseSlot -> go s m; _ -> []) <> nested (s + elementWidth e) es
    flat _ [] = []
    flat s (e : es) = case e of
      ElemToken t -> (s, t) : flat (s + elementWidth e) es
      ElemNode m
        | nodeKind m `elem` [NInlineCommand, NExpr] -> (s, Token KOperator "") : flat (s + elementWidth e) es
        | otherwise -> flat s (nodeChildren m) <> flat (s + elementWidth e) es
    lastChar ts = case [t | t <- reverse ts, tokKind t /= KWhitespace] of
      (Token KText t : _) | not (T.null t) -> Just (T.last t)
      _ -> Nothing
    firstChar ts = case [t | t <- ts, tokKind t /= KWhitespace] of
      (Token KText t : _) | not (T.null t) -> Just (T.head t)
      _ -> Nothing

-- | G05002: a variable used neither in its file nor by any importer.
unusedVariables :: LintInput -> [Diagnostic]
unusedVariables input =
  [ diagnostic "G05002" Error sp ("使われていない変数です: " <> v)
  | f <- liFiles input,
    (v, sp) <- usageDefined (flUsage f),
    not (v `Set.member` usageReferenced (flUsage f)),
    not (usedByImporters (flPath f) v)
  ]
  where
    usedByImporters path v =
      or
        [ v `Set.member` Map.findWithDefault Set.empty ns (usageNamespaceRefs (flUsage g))
        | g <- liFiles input,
          (ns, target, _) <- usageImports (flUsage g),
          target == path
        ]

-- | G05003: an import whose namespace is never referenced.
unusedImports :: LintInput -> [Diagnostic]
unusedImports input =
  [ diagnostic "G05003" Error sp ("使われていない import です: " <> ns)
  | f <- liFiles input,
    (ns, _, sp) <- usageImports (flUsage f),
    not (Map.member ns (usageNamespaceRefs (flUsage f)))
  ]

{- | G05004: a label nobody refers to. A warning in dev, an error in prod
(adjusted in golem-syntax).
-}
unreferencedLabels :: LintInput -> [Diagnostic]
unreferencedLabels input =
  [ diagnostic "G05004" Warning sp ("参照されていないラベルです: " <> l)
  | (l, sp) <- Map.toList (liLabels input),
    not (l `Set.member` liReferenced input)
  ]
