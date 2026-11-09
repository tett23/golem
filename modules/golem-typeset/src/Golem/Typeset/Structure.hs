{- | The structure tree of the PDF (docs/adr ADR 0183): the elements of the
standard types that the blocks and inlines of the IR make, in the order of
the IR, whose leaves are the places of composition that 'Golem.Typeset.Flow'
gives the boxes it composes.
-}
module Golem.Typeset.Structure
  ( structureTree,
    linksOfLeaves,
  )
where

import Data.Char (isSpace)
import Data.List (mapAccumL)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text qualified as T
import Data.Text.Encoding qualified as TE
import Golem.Assemble
import Golem.Doc.IR
import Golem.Layout.Japanese (ComposeEnv (..), InlineNode (..), InlineRole (..), inlineStructure)
import Golem.Layout.Look (Look (..))
import Golem.Layout.Paginate (NoteId (..))
import Golem.LayoutSpec (PageGeometry (..))
import Golem.Pdf qualified as P
import Golem.Project.Style (CaptionPosition (..), Style (..))
import Golem.Syntax
import Golem.Typeset.Flow
import Golem.Typeset.Fonts

-- what a unit gives the tree before its frames are made elements
data Node
  = NKid P.StructKid
  | -- | the marker of a list item, for its LI
    NMarker P.StructElem
  | -- | the content of a term of a definition list, for the Lbl of its LI
    NTerm [P.StructKid]

{- | The structure tree: the units in their frames (lists, items, the
table of contents, the index and so on), each unit an element of its
kind, the Notes after their marks. @figureAttrs@ gives the attributes of
the Figure of each figure by its unit (its BBox, from the drawing).
-}
structureTree :: FlowEnv -> [(Int, Unit)] -> (Int -> [P.Attribute]) -> (P.StructElem, Map P.AnnotId T.Text)
structureTree fe units figureAttrs =
  let body = [(uFrames u, n) | (i, u) <- units, not (isEndNote u), n <- unitNodes i u]
      kids = concatMap nodeKids (build body)
      root = (P.structElem P.SDocument kids) {P.seAttrs = [P.Attribute "Layout" [("WritingMode", P.OName "TbRl")] | pgVertical geom]}
      tree = numberNotes root
   in (withoutTexts tree, Map.fromList (linkTexts tree))
  where
    inp = feInput fe
    geom = feGeom fe
    book = piBook inp
    lang = bookLanguage inp
    atEnd = feNotesAtEnd fe
    isEndNote u = any (\case Frame _ (FEndNote _ _) _ -> True; Frame _ (FEndNoteMore _) _ -> True; _ -> False) (uFrames u)
    -- the units of the notes at the end of chapters by their spans, in order: each note its first paragraph and the others (docs/adr/0263)
    endNotes = Map.map groupNotes (Map.fromListWith (flip (<>)) [(sp, [(isFirst, (i, u))]) | (i, u) <- units, (sp, isFirst) <- endNoteOf u])
    endNoteOf u = [(sp, True) | Frame _ (FEndNote sp _) _ <- uFrames u] <> [(sp, False) | Frame _ (FEndNoteMore sp) _ <- uFrames u]
    groupNotes = \case
      [] -> []
      (_, x) : rest -> let (more, others) = span (not . fst) rest in (x : map snd more) : groupNotes others
    content env site inls = [toKid (site, n) | n <- inlineStructure env inls]
    toKid (site, n) = case n of
      NodeLeaf k -> P.KidLeaf (P.LeafId (site <> [k]))
      -- a language span: a Span of its language (docs/adr ADR 0187)
      NodeElem (RoleLang l) ns -> P.KidElem ((P.structElem P.SSpan [toKid (site, m) | m <- ns]) {P.seLang = Just l})
      -- a range with a line of its own: a Span with its TextDecorationType (docs/adr/0270)
      NodeElem RoleUnderline ns -> P.KidElem (decorated "Underline" [toKid (site, m) | m <- ns])
      NodeElem RoleStrikethrough ns -> P.KidElem (decorated "LineThrough" [toKid (site, m) | m <- ns])
      NodeElem role ns -> P.KidElem (P.structElem (roleType role) [toKid (site, m) | m <- ns])
      NodeNote sp k num nbody -> P.KidElem (noteElem sp k num nbody)
      NodeSidenote sp num snBody -> P.KidElem (sidenoteElem sp num (concat snBody))
      -- a link: its text, then the annotations of its lines (docs/adr ADR 0183)
      NodeLink u xs ns -> P.KidElem (linkElem site u xs [toKid (site, m) | m <- ns] ns)
    linkElem site u xs kids ns =
      let first = case ns of
            NodeLeaf k : _ -> k
            _ -> 0
          -- without its soft hyphens, which the PDF does not write (docs/adr ADR 0272)
          shown = T.filter (/= '\xAD') (T.concat (map inlineText xs))
          contents = if shown == u then u else shown <> "（" <> u <> "）"
       in -- the text rides in an attribute of no owner of the PDF until 'withoutTexts' takes it out
          (P.structElem P.SLink (kids <> [P.KidAnnot (P.AnnotId (site <> [first]))])) {P.seAttrs = [P.Attribute "Golem" [("Contents", P.OStr (TE.encodeUtf8 contents))]]}
    roleType = \case
      RoleLabel -> P.SLbl
      RoleRuby -> P.SRuby
      RoleRubyBase -> P.SRB
      RoleRubyText -> P.SRT
      RoleReference -> P.SReference
      RoleCode -> P.SCode
      RoleLang _ -> P.SSpan
      RoleUnderline -> P.SSpan
      RoleStrikethrough -> P.SSpan
    decorated kind kids = (P.structElem P.SSpan kids) {P.seAttrs = [P.Attribute "Layout" [("TextDecorationType", P.OName kind)]]}
    -- a Note: the mark (Lbl), then the body (P)
    noteFrom kids = case kids of
      P.KidElem lbl@P.StructElem {P.seType = P.SLbl} : rest -> P.structElem P.SNote (P.KidElem lbl : [P.KidElem (P.structElem P.SP rest) | not (null rest)])
      _ -> P.structElem P.SNote [P.KidElem (P.structElem P.SP kids)]
    -- the mark (Lbl), the first paragraph (P) and a P for each other paragraph (docs/adr/0263)
    withMore el more = el {P.seKids = P.seKids el <> [P.KidElem (P.structElem P.SP kids) | kids <- more]}
    noteElem sp k num nbody
      | atEnd = case drop k (Map.findWithDefault [] sp endNotes) of
          ((j, u) : more) : _ -> withMore (noteFrom (content (unitEnv fe u) (unitSite j) (uInlines u))) [content (unitEnv fe mu) (unitSite mj) (uInlines mu) | (mj, mu) <- more]
          _ -> P.structElem P.SNote []
      | otherwise =
          let key = NoteId sp k
              st = piStyle inp
              vertical = pgVertical geom
              env = noteEnv fe (styleOfSpan sp)
           in case nbody of
                first : more -> withMore (noteFrom (content env {ceLabelInlines = noteMarkCount st vertical (noteIdSpan key) num} (noteSite key) (withNoteMark st vertical (noteIdSpan key) num first))) [content env {ceLabelInlines = 0} (noteParagraphSite key j) para | (j, para) <- zip [1 ..] more]
                [] -> P.structElem P.SNote []
    sidenoteElem sp num snBody =
      let st = styleOfSpan sp
          prefix = sidenotePrefix fe sp num
       in noteFrom (content ((sidenoteEnv fe st) {ceLabelInlines = length prefix}) (sidenoteSite sp num) (prefix <> snBody))
    styleOfSpan sp = docStyle inp (spanFile sp)
    -- the nodes of one unit
    unitNodes i u =
      let env = unitEnv fe u
          text = content env (unitSite i) (uInlines u)
          marker = [NMarker (P.structElem P.SLbl (content env (markerSite i) m)) | Just m <- [uMarker u]]
          -- the element of a block with a language has its /Lang (docs/adr ADR 0187)
          own = \case
            NKid (P.KidElem e) -> NKid (P.KidElem e {P.seLang = uLang u})
            x -> x
       in marker <> map own (unitKids i u text)
    unitKids i u text = case uKind u of
      UPara _ -> [NKid (P.KidElem (P.structElem P.SP text))]
      UIndexEntry _ -> [NKid (P.KidElem (P.structElem P.SP text))]
      UHeading l _ _ -> [NKid (P.KidElem (P.structElem (headingType l) text))]
      UTerm _ -> [NTerm text]
      UTocEntry _ _ -> [NKid (P.KidElem (P.structElem P.STOCI text))]
      UTable tbl -> [NKid (P.KidElem (tableElem i u tbl))]
      UCode _ code -> [NKid (P.KidElem (codeElem i u code))]
      UFigure fig -> [NKid (P.KidElem (figureElem i u fig))]
      _ -> []
    headingType = \case
      1 -> P.SH1
      2 -> P.SH2
      3 -> P.SH3
      4 -> P.SH4
      5 -> P.SH5
      _ -> P.SH6
    {- a table: the header row of TH, the other rows of TD (golem-driver ADR
    0008, 0031), and its caption the first child, or the last below the
    table, in the order it is set (docs/adr/0262) -}
    tableElem i u tbl =
      let env = tableEnv fe (uStyle u) (lkLang (uLook u)) tbl
          h = tableHeader tbl
          rows = tableRows tbl
          caption = case tableCaption tbl of
            Just is -> [P.KidElem (P.structElem P.SCaption (content (captionEnv fe u) (captionSite i) (numberedTitle lang (uSpan u) (Map.lookup (uSpan u) (bookTables book)) is)))]
            Nothing -> []
          below = stTableCaption (piStyle inp) == CaptionBelow
          blankRow = all (T.all isSpace . T.concat . map inlineText) h
          cellElem r c t is = P.structElem t (content env (cellSite i r c) is)
          cell r c t is = P.KidElem (cellElem r c t is)
          header = [P.KidElem (P.structElem P.STR [P.KidElem (cellElem 0 c P.STH is) {P.seAttrs = [P.Attribute "Table" [("Scope", P.OName "Column")]]} | (c, is) <- zip [0 ..] h]) | not blankRow]
          body = [P.KidElem (P.structElem P.STR [cell r c P.STD is | (c, is) <- zip [0 ..] row]) | (r, row) <- zip [1 ..] rows]
       in P.structElem P.STable (if below then header <> body <> caption else caption <> header <> body)
    -- a code block: its caption, its file name and each line a P of Code (golem-driver ADR 0017, 0023)
    codeElem i u code =
      let caption = case codeCaption code of
            Just is -> [P.KidElem (P.structElem P.SCaption (content (captionEnv fe u) (captionSite i) (numberedTitle lang (uSpan u) (Map.lookup (uSpan u) (bookListings book)) is)))]
            Nothing -> []
          file = [P.KidElem (P.structElem P.SP [P.KidElem (P.structElem P.SCode [P.KidLeaf (P.LeafId (codeFileSite i <> [0]))])]) | isJust (codeFile code)]
          linesOf = [P.KidElem (P.structElem P.SP [P.KidElem (P.structElem P.SCode [P.KidLeaf (P.LeafId (codeRowSite i j <> [0]))])]) | j <- [0 .. max 1 (length (codeLines code)) - 1]]
       in P.structElem P.SDiv (caption <> file <> linesOf)
    -- a figure: the Figure with its alternate text, then its caption (golem-driver ADR 0005, 0010)
    figureElem i u fig =
      let captionInlines = numberedTitle lang (uSpan u) (Map.lookup (uSpan u) (bookFigures book)) (concat [is | Block _ _ _ (Paragraph _ is) <- figCaption fig])
          figure = (P.structElem P.SFigure [P.KidLeaf (P.LeafId (figureSite i <> [0]))]) {P.seAlt = Just (figAlt fig), P.seAttrs = figureAttrs i}
       in P.structElem P.SDiv (P.KidElem figure : [P.KidElem (P.structElem P.SCaption (content (captionEnv fe u) (captionSite i) captionInlines)) | not (null captionInlines)])
    -- the units in their frames, the frames made elements
    build = \case
      [] -> []
      ([], n) : rest -> n : build rest
      (f : fs, n) : rest ->
        let (same, others) = span (\(p, _) -> take 1 p == [f]) rest
         in frameNodes f (build ((fs, n) : [(drop 1 p, m) | (p, m) <- same])) <> build others
    -- the element of a frame of a block with a language has its /Lang (docs/adr ADR 0187)
    frameNodes (Frame _ k flang) inner = map (withLang flang) $ case k of
      FList numbered -> [elemNode (listElem (if numbered then "Decimal" else "Disc") (concatMap nodeKids inner))]
      FItem ->
        let lbls = [P.KidElem e | NMarker e <- inner]
            rest = concatMap nodeKids [n | n <- inner, not (isMarker n)]
         in [elemNode (P.structElem P.SLI (lbls <> [P.KidElem (P.structElem P.SLBody rest)]))]
      FDefList -> [elemNode (listElem "None" (concatMap nodeKids inner))]
      FDefItem ->
        let terms = concat [ks | NTerm ks <- inner]
            rest = concatMap nodeKids [n | n <- inner, not (isTerm n)]
         in [elemNode (P.structElem P.SLI ([P.KidElem (P.structElem P.SLbl terms) | not (null terms)] <> [P.KidElem (P.structElem P.SLBody rest)]))]
      FDefBody -> inner
      FToc -> [elemNode (P.structElem P.STOC (concatMap nodeKids inner))]
      FIndex -> [elemNode (P.structElem P.SIndex (concatMap nodeKids inner))]
      FChannel -> [elemNode (P.structElem P.SDiv (concatMap nodeKids inner))]
      -- each entry: its number the Lbl, the rest a BibEntry in the LBody
      FBibliography ->
        [ elemNode
            ( listElem
                "None"
                [ P.KidElem $ case P.seKids e of
                    P.KidElem lbl@P.StructElem {P.seType = P.SLbl} : rest -> P.structElem P.SLI [P.KidElem lbl, P.KidElem (P.structElem P.SLBody [P.KidElem (P.structElem P.SBibEntry rest)])]
                    ks -> P.structElem P.SLI [P.KidElem (P.structElem P.SLBody [P.KidElem (P.structElem P.SBibEntry ks)])]
                | P.KidElem e <- concatMap nodeKids inner
                ]
            )
        ]
      -- the lines of a paragraph of a style that keeps its lines: one P
      FPara -> [elemNode (P.structElem P.SP (concat [if P.seType e == P.SP then P.seKids e else [P.KidElem e] | P.KidElem e <- concatMap nodeKids inner]))]
      FEndNote _ _ -> []
      FEndNoteMore _ -> []
    elemNode = NKid . P.KidElem
    withLang = \case
      Nothing -> id
      Just l -> \case
        NKid (P.KidElem e) -> NKid (P.KidElem e {P.seLang = Just l})
        x -> x
    listElem numbering = (\e -> e {P.seAttrs = [P.Attribute "List" [("ListNumbering", P.OName numbering)]]}) . P.structElem P.SL
    isMarker = \case
      NMarker _ -> True
      _ -> False
    isTerm = \case
      NTerm _ -> True
      _ -> False
    nodeKids = \case
      NKid k -> [k]
      NMarker e -> [P.KidElem e]
      NTerm ks -> [P.KidElem (P.structElem P.SLbl ks)]

{- | The Link of each leaf of the tree inside one, by the annotations of
the Link (docs/adr ADR 0183): an annotation is of the Link that holds the
first box of its line.
-}
linksOfLeaves :: P.StructElem -> Map P.LeafId P.AnnotId
linksOfLeaves = Map.fromList . go Nothing
  where
    go link e =
      let here = case [a | P.KidAnnot a <- P.seKids e] of
            (a : _) -> Just a
            [] -> link
       in concat [case k of P.KidLeaf l -> [(l, a) | Just a <- [here]]; P.KidElem c -> go here c; P.KidAnnot _ -> [] | k <- P.seKids e]

-- | The text of each link, for the Contents of its annotations: as plain text writes it (docs/adr ADR 0182).
linkTexts :: P.StructElem -> [(P.AnnotId, T.Text)]
linkTexts e =
  [(a, t) | P.seType e == P.SLink, P.KidAnnot a <- P.seKids e, P.Attribute "Golem" [("Contents", P.OStr b)] <- P.seAttrs e, let t = TE.decodeUtf8 b]
    <> concat [linkTexts c | P.KidElem c <- P.seKids e]

-- | The tree without the texts of its links, which 'linkTexts' has taken.
withoutTexts :: P.StructElem -> P.StructElem
withoutTexts e =
  e
    { P.seAttrs = [a | a <- P.seAttrs e, P.atOwner a /= "Golem"],
      P.seKids = [case k of P.KidElem c -> P.KidElem (withoutTexts c); _ -> k | k <- P.seKids e]
    }

-- | The IDs of the Notes, note-1 on in the order of the tree.
numberNotes :: P.StructElem -> P.StructElem
numberNotes = snd . go 1
  where
    go :: Int -> P.StructElem -> (Int, P.StructElem)
    go n e =
      let (n1, e1) = if P.seType e == P.SNote then (n + 1, e {P.seId = Just ("note-" <> T.pack (show n))}) else (n, e)
          (n2, kids) = mapAccumL kid n1 (P.seKids e1)
       in (n2, e1 {P.seKids = kids})
    kid n = \case
      P.KidElem c -> P.KidElem <$> go n c
      k -> (n, k)
