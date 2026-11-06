{- | The outline of a .emet (docs/adr/0170): the top-level declarations of
a file as a tree. A function (its signature and its equations) holds the
bindings of its where; a data type its constructors, and a constructor
of a record its fields. A file that does not parse has the declarations
of the part before the error ('parsedPrefix').
-}
module Golem.Emet.Outline
  ( SymbolKind (..),
    Symbol (..),
    emetOutline,
  )
where

import Data.ByteString qualified as BS
import Data.List (nub)
import Data.Maybe (fromMaybe, listToMaybe)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Emet.Parse (parseModule, parsedPrefix)
import Golem.Emet.Syntax
import Golem.Syntax (FileId (..))

-- | The kinds of the symbols, those of LSP the table of docs/adr/0170 names.
data SymbolKind
  = SymFunction
  | SymVariable
  | SymEnum
  | SymStruct
  | SymEnumMember
  | SymField
  | SymTypeParameter
  | SymModule
  deriving stock (Eq, Show)

{- | A symbol: its name, kind, detail, its range and the range of its name
in UTF-8 bytes, and the symbols under it.
-}
data Symbol = Symbol
  { symName :: !Text,
    symKind :: !SymbolKind,
    symDetail :: !(Maybe Text),
    symStart :: !Int,
    symEnd :: !Int,
    symNameStart :: !Int,
    symNameEnd :: !Int,
    symChildren :: ![Symbol]
  }
  deriving stock (Eq, Show)

-- | The declarations of a text, in the order of the text.
emetOutline :: Text -> [Symbol]
emetOutline text = maybe [] (declarations text) (parsedPrefix (parseModule (FileId 0)) text)

declarations :: Text -> Module -> [Symbol]
declarations text (Module decls) = concatMap decl decls
  where
    bytes = TE.encodeUtf8 text
    source (Loc s e) = TE.decodeUtf8Lenient (BS.take (e - s) (BS.drop s bytes))
    -- the text of a type on one line
    flat = T.unwords . T.words
    sigs = [s | DSig s <- decls]
    eqsOf n = [q | DEq q <- decls, eqName q == n]
    sigOf n = listToMaybe [s | s <- sigs, sigName s == n]
    nameRange l n = (locStart l, locStart l + BS.length (TE.encodeUtf8 n))
    decl = \case
      DImport l p _ -> [Symbol p SymModule Nothing (locStart l) (locEnd l) (locStart l) (locEnd l) []]
      DSig s -> [function s (eqsOf (sigName s))]
      -- equations without a signature: once, at their first
      DEq q
        | Nothing <- sigOf (eqName q),
          (first : _) <- eqsOf (eqName q),
          locStart (eqLoc first) == locStart (eqLoc q) ->
            [equationsOnly (eqsOf (eqName q))]
      DEq _ -> []
      DData l _ n _ cs ->
        let (ns, ne) = declaredName l n
            kind = case cs of
              [_] -> SymStruct
              _ -> SymEnum
         in [Symbol n kind Nothing (locStart l) (locEnd l) ns ne (map constructor cs)]
      DType l _ n _ t ->
        let (ns, ne) = declaredName l n
         in [Symbol n SymTypeParameter (Just (flat (source (typeLoc t)))) (locStart l) (locEnd l) ns ne []]
    function s eqs =
      let (ns, ne) = nameRange (sigNameLoc s) (sigName s)
          end = maximum (locEnd (sigLoc s) : map (locEnd . eqLoc) eqs)
       in Symbol (sigName s) SymFunction (Just (detailOf s)) (locStart (sigLoc s)) end ns ne (whereSymbols eqs)
    equationsOnly eqs = case eqs of
      q : _ ->
        let (ns, ne) = nameRange (eqNameLoc q) (eqName q)
         in Symbol (eqName q) SymFunction Nothing (locStart (eqLoc q)) (maximum (map (locEnd . eqLoc) eqs)) ns ne (whereSymbols eqs)
      [] -> Symbol "" SymFunction Nothing 0 0 0 0 []
    -- the type as written, after the kind and the name .gm uses
    detailOf s =
      let ty = flat (source (maybe (typeLoc (sigType s)) (\r -> rowLoc r <-> typeLoc (sigType s)) (sigRow s)))
       in case sigKind s of
            Just (k, _) -> "pub " <> kindWord k <> maybe "" (\(n, _) -> " \"" <> n <> "\"") (sigExport s) <> " :: " <> ty
            Nothing -> ty
    whereSymbols eqs =
      let bindings = [b | q <- eqs, Where _ bs <- eqWheres q <> guardWheres (eqRhs q), b <- bs]
          localSigs = [s | BSig s <- bindings]
          localEqs = [q | BEq q <- bindings]
          names = nub ([sigName s | s <- localSigs] <> [eqName q | q <- localEqs])
       in [binding n [s | s <- localSigs, sigName s == n] [q | q <- localEqs, eqName q == n] | n <- names]
    binding n ss qs =
      let isFunction = not (all (null . eqPats) qs) || any (isArrow . sigType) ss
          firstLoc = listToMaybe (map sigLoc ss <> map eqLoc qs)
          nameLoc = fromMaybe (Loc 0 0) (listToMaybe (map sigNameLoc ss <> map eqNameLoc qs))
          (ns, ne) = nameRange nameLoc n
          start = maybe ns locStart firstLoc
          end = maximum (ne : map (locEnd . sigLoc) ss <> map (locEnd . eqLoc) qs)
       in Symbol n (if isFunction then SymFunction else SymVariable) (detailOf <$> listToMaybe ss) start end ns ne []
    isArrow = \case
      TFun {} -> True
      _ -> False
    guardWheres = \case
      Guarded gs -> concatMap snd gs
      Plain _ -> []
    constructor = \case
      ConPos l n _ ->
        let (ns, ne) = nameRange l n
         in Symbol n SymEnumMember Nothing (locStart l) (locEnd l) ns ne []
      ConRec l n fs ->
        let (ns, ne) = nameRange l n
         in Symbol n SymEnumMember Nothing (locStart l) (locEnd l) ns ne (fields (locStart l) fs)
    -- the fields, each found in the text before the :: of its type
    fields from = \case
      [] -> []
      (f, t) : rest ->
        let fs = fieldStart from (locStart (typeLoc t)) f
            fe = fs + BS.length (TE.encodeUtf8 f)
         in Symbol f SymField (Just (flat (source (typeLoc t)))) fs (locEnd (typeLoc t)) fs fe [] : fields (locEnd (typeLoc t)) rest
    fieldStart from to f = fromMaybe from (lastWordAt from to f)
    -- the name of a data type or an alias: the first word of its name after the keyword
    declaredName l n = maybe (locStart l, locStart l) (\s -> (s, s + BS.length (TE.encodeUtf8 n))) (firstWordAt (locStart l) (locEnd l) n)
    -- the offsets of a word in [from, to) of the text, as a whole word
    wordsAt from to w =
      let piece = BS.take (to - from) (BS.drop from bytes)
          wb = TE.encodeUtf8 w
          isWordByte b = b == 95 || (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
          go i
            | i + BS.length wb > BS.length piece = []
            | BS.take (BS.length wb) (BS.drop i piece) == wb
                && (i == 0 || not (isWordByte (BS.index piece (i - 1))))
                && (i + BS.length wb == BS.length piece || not (isWordByte (BS.index piece (i + BS.length wb)))) =
                (from + i) : go (i + 1)
            | otherwise = go (i + 1)
       in go 0
    firstWordAt from to w = listToMaybe (wordsAt from to w)
    lastWordAt from to w = listToMaybe (reverse (wordsAt from to w))
