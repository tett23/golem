module PhysicalPaginateSpec (physicalPaginateTests) where

import Control.Monad (forM_, when)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Golem.Doc.IR (BreakKind (..))
import Golem.Layout.Code (codeGeometry)
import Golem.Layout.Paginate
import Golem.Layout.Paginate.Physical
import Golem.Layout.RuleArea (RuleGrid (..), RuleSide (..))
import Golem.Length (Sp)
import Golem.Project.Style (KeepParts (..))
import Golem.Syntax (FileId (..), SrcSpan, mkSpan)
import Test.Tasty hiding (after)
import Test.Tasty.HUnit

line :: Int -> LineBox
line i = LineBox i [] [] [] 0

noteLine :: Int -> LineBox
noteLine i = LineBox i [NoteBody (NoteId span0 0) 1] [] [] 0

longNoteLine :: Int -> LineBox
longNoteLine i = LineBox i [NoteBody (NoteId span0 0) 3] [] [] 0

settings :: PhysicalSettings
settings = PhysicalSettings 16 10 42 42 0 (ColumnSet 1 0 0 0) Map.empty Map.empty Map.empty Map.empty Map.empty Nothing Set.empty

span0 :: SrcSpan
span0 = mkSpan (FileId 0) 0 0

columnsOf :: [PageOutAt Sp] -> [(Int, Int, [Int])]
columnsOf pages = [(poNumber p, poColumn p, ids) | p <- pages, let ids = [n | (_, SLine n) <- poSlots p], not (null ids)]

slots :: Either PhysicalFailure [PageOutAt Sp] -> Either PhysicalFailure [[(Sp, Slotted)]]
slots = fmap (map poSlots)

physicalPaginateTests :: TestTree
physicalPaginateTests =
  testGroup "physical pagination" $
    [ testCase "root ADR 0401 I2: discarded source callbacks preserve only accepted ids notes labels and marks" $ do
        let cfg = settings {physicalCapacity = 64, physicalMaxCapacity = 64, physicalColumns = ColumnSet 2 0 0 0}
        cursor <- either (assertFailure . show) pure (stepPhysicalCursor cfg (startPhysicalCursor cfg) [FParagraph defaultKeep (map line [0 .. 6])])
        (acceptedPage, chosen) <-
          either
            (assertFailure . show)
            pure
            ( retainPhysicalPart
                cfg
                KeepPage
                span0
                "item"
                cursor
                ( \at -> do
                    let (page, _, _) = physicalCursorPosition at
                        ident = page * 10
                        first = (noteLine ident) {lbLabels = [if page == 1 then "discarded" else "accepted"], lbMarks = [span0]}
                    placed <- stepPhysicalCursor cfg at [FParagraph defaultKeep (first : map line [ident + 1, ident + 2])]
                    pure (page, [ident .. ident + 2], placed)
                )
            )
        acceptedPage @?= 2
        let pages = finishPhysicalCursor cfg chosen
        concatMap poLabels pages @?= ["accepted"]
        concatMap poMarks pages @?= [span0]
        concatMap poFootnotes pages @?= [(NoteId span0 0, 0, 1)]
        [n | p <- pages, (_, SLine n) <- poSlots p, n >= 10] @?= [20, 21, 22],
      testCase "root ADR 0401 I2: a retained callback re-composes source at the accepted cursor" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
        cursor <- either (assertFailure . show) pure (stepPhysicalCursor cfg (startPhysicalCursor cfg) [FParagraph defaultKeep (map line [0 .. 2])])
        (sourcePage, chosen) <-
          either
            (assertFailure . show)
            pure
            ( retainPhysicalPart
                cfg
                KeepPage
                span0
                "item"
                cursor
                ( \at -> do
                    let (page, _, _) = physicalCursorPosition at
                    placed <- stepPhysicalCursor cfg at [FParagraph defaultKeep (map line [10 .. 12])]
                    pure (page, [10 .. 12], placed)
                )
            )
        sourcePage @?= 2
        [poNumber p | p <- finishPhysicalCursor cfg chosen, (_, SLine n) <- poSlots p, n >= 10] @?= [2, 2, 2],
      testCase "root ADR 0401 I2: free page keeps a list item across columns in one page" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
            part = FBookPart KeepPage span0 "list item" [10, 11, 12] [FParagraph defaultKeep (map line [10 .. 12])]
        pages <- either (assertFailure . show) pure (paginatePhysical cfg [FParagraph defaultKeep (map line [0 .. 2]), part])
        [(poNumber p, poColumn p) | p <- pages, (_, SLine n) <- poSlots p, n >= 10] @?= [(2, 0), (2, 0), (2, 1)],
      testCase "root ADR 0401 I2: free page lets a table header and first row cross columns within a page" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
            part = FBookPart KeepPage span0 "table" [10, 11, 20, 21] [FTable 10 0 [line 10, line 11] [[line 20, line 21]] [] False]
        pages <- either (assertFailure . show) pure (paginatePhysical cfg [part])
        columnsOf pages @?= [(1, 0, [10, 11]), (1, 1, [20, 21])],
      testCase "root ADR 0401 I2: free spread repeats a table header on the next physical page only" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
            part = FBookPart KeepSpread span0 "table" [10, 20] [FTable 10 0 [line 10] [[line 20], [line 30], [line 40], [line 50]] [] False]
        pages <- either (assertFailure . show) pure (paginatePhysical cfg [FBreak BreakPage, part])
        columnsOf pages @?= [(2, 0, [10, 20]), (2, 1, [30, 40]), (3, 0, [10, 50])],
      testCase "root ADR 0401 I2: free page keeps a lower caption in its last row's page across columns" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
            part = FBookPart KeepPage span0 "table" [10, 11] [FTable 10 0 [] [[line 10, line 11], [line 20]] [line 30, line 31] True]
        pages <- either (assertFailure . show) pure (paginatePhysical cfg [part])
        columnsOf pages @?= [(1, 0, [10, 11]), (2, 0, [20]), (2, 1, [30, 31])],
      testCase "root ADR 0401 I2: free page lets a definition term and its first description cross columns" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
            part = FBookPart KeepPage span0 "definition" [10, 11, 20] [FDefTerm [line 10, line 11], FParagraph (Keep 1 1 False) [line 20, line 21]]
        pages <- either (assertFailure . show) pure (paginatePhysical cfg [FParagraph defaultKeep [line 0], part])
        columnsOf pages @?= [(1, 0, [0, 10]), (1, 1, [11, 20]), (2, 0, [21])],
      testCase "root ADR 0401 I1: free column keeps a table header with its first row in one column" $ do
        let cfg = settings {physicalColumns = ColumnSet 2 0 0 0}
            part = FBookPart KeepColumn span0 "table" [10, 20] [FTable 10 0 [line 10] [[line 20], [line 30], [line 40]] [] False]
        pages <- either (assertFailure . show) pure (paginatePhysical cfg [part])
        columnsOf pages @?= [(1, 0, [10, 20]), (1, 1, [10, 30]), (2, 0, [10, 40])],
      testCase "root ADR 0401 I3: free oversized item produces one notice without losing rows" $ do
        let part = FBookPart KeepPage span0 "list item" [10 .. 14] [FParagraph defaultKeep (map line [10 .. 14])]
        pages <- either (assertFailure . show) pure (paginatePhysical settings [FParagraph defaultKeep [line 0], part])
        [n | p <- pages, (_, SLine n) <- poSlots p, n >= 10] @?= [10 .. 14]
        [u | p <- pages, u@SplitBookPart {} <- poUnmet p] @?= [SplitBookPart span0 "list item" KeepPage],
      testCase "root ADR 0397 I9 I10: cursor trials discard failed labels, marks and notes when a paragraph moves" $ do
        let cfg = settings {physicalSeparator = 10}
            row = (noteLine 0) {lbLabels = ["body"], lbMarks = [span0]}
        (wrapped, region) <- either (assertFailure . show) pure (beginPhysicalWrap cfg (startPhysicalCursor cfg) 9 30 ["figure"] [])
        trial <- either (assertFailure . show) pure (trialParagraphPart cfg (Just region) defaultKeep True wrapped [row])
        case trial of
          PhysicalPlaced {} -> assertFailure "the figure leaves no room for this note"
          PhysicalMoved next keep -> do
            physicalCursorPosition next @?= (2, 0, 0)
            let original = finishPhysicalCursor cfg (endPhysicalWrap (Just region) wrapped)
            map poSlots original @?= [[(0, SWrapped 9)]]
            map poLabels original @?= [["figure"]]
            map poFootnotes original @?= [[]]
            retried <- either (assertFailure . show) pure (trialParagraphPart cfg (Just region) keep True next [row])
            case retried of
              PhysicalMoved {} -> assertFailure "the note must fit in the empty next column"
              PhysicalPlaced count placed _ -> do
                count @?= 1
                let pages = finishPhysicalCursor cfg placed
                map poSlots pages @?= [[(0, SWrapped 9)], [(0, SLine 0)]]
                map poLabels pages @?= [["figure"], ["body"]]
                map poMarks pages @?= [[], [span0]]
                map poFootnotes pages @?= [[], [(NoteId span0 0, 0, 1)]],
      testCase "root ADR 0397 I8 I10: the committed figure anchor includes the preceding holding group" $ do
        let cfg = settings {physicalCapacity = 64, physicalMaxCapacity = 64}
            prefix = [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1]
        (cursor, region) <- either (assertFailure . show) pure (beginPhysicalWrapAfter cfg (startPhysicalCursor cfg) prefix 9 48 [] [])
        physicalCursorPosition cursor @?= (2, 0, 16)
        region @?= PhysicalWrap 2 0 64
        map poSlots (finishPhysicalCursor cfg (endPhysicalWrap (Just region) cursor)) @?= [[(0, SLine 99)], [(0, SLine 0), (16, SWrapped 9)]],
      testCase "root ADR 0397 I9 I13: a cursor rejects impossible continued notes before any trial" $
        let cfg = settings {physicalSeparator = 30}
            side = RuleSide 0 0 1 True Nothing
            flow = FRuled 5 (Just side) Nothing False (RuleGrid 16 10) 0 (RuledLines defaultKeep [noteLine 0])
         in case stepPhysicalCursor cfg (startPhysicalCursor cfg) [flow] of
              Left failure -> failure @?= PhysicalFootnoteTooTall (NoteId span0 0)
              Right _ -> assertFailure "a note cannot make progress in any column",
      testCase "root ADR 0397 I8 I10: an empty paragraph trial consumes no rows or column" $ do
        let original = startPhysicalCursor settings
        trial <- either (assertFailure . show) pure (trialParagraphPart settings Nothing defaultKeep True original [])
        case trial of
          PhysicalMoved {} -> assertFailure "an empty paragraph cannot move"
          PhysicalPlaced count cursor keep -> do
            count @?= 0
            keep @?= defaultKeep
            physicalCursorPosition cursor @?= physicalCursorPosition original,
      testCase "root ADR 0397 I8 I10: an oversized keep-all trial relaxes once in an empty column" $ do
        trial <- either (assertFailure . show) pure (trialParagraphPart settings Nothing (Keep 1 1 True) True (startPhysicalCursor settings) [line 0, line 1, line 2])
        case trial of
          PhysicalMoved {} -> assertFailure "the empty column is the relaxation boundary"
          PhysicalPlaced count cursor keep -> do
            count @?= 2
            kAll keep @?= False
            concatMap poUnmet (finishPhysicalCursor settings cursor) @?= [SplitKept 0],
      testCase "root ADR 0397 I8: joined ordinary paragraphs retain the later paragraph's first and last keeps" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FParagraph (Keep 2 2 False) [line 1, line 2, line 3, line 4]]])
          @?= Right [[(1, SLine 0)], [(1, SLine 1), (17, SLine 2)], [(1, SLine 3), (17, SLine 4)]],
      testCase "root ADR 0397 I8: a mixed verse and paragraph box retains the later paragraph's keeps" $
        slots (paginatePhysical settings {physicalCapacity = 58, physicalMaxCapacity = 58, physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[line 0, line 1]], FParagraph (Keep 2 2 False) [line 2, line 3, line 4, line 5]]])
          @?= Right [[(1, SLine 0), (17, SLine 1)], [(1, SLine 2), (17, SLine 3)], [(1, SLine 4), (17, SLine 5)]],
      testCase "root ADR 0397 I8 I13: an oversized later keep-all paragraph relaxes once" $
        fmap (concatMap poUnmet) (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FParagraph (Keep 2 2 True) [line 1, line 2, line 3, line 4]]])
          @?= Right [SplitKept 1],
      testCase "root ADR 0397 I8 I13: an oversized later keep-all stanza relaxes once" $
        fmap (concatMap poUnmet) (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FStanza (Keep 1 1 True) [[line 1], [line 2], [line 3]]]])
          @?= Right [SplitKept 1],
      testCase "root ADR 0397 I8: an internal keep-with-next retains two following display rows" $
        slots (paginatePhysical settings {physicalCapacity = 58, physicalMaxCapacity = 58, physicalBoxPadding = Map.singleton 5 4} [FParagraph (Keep 1 1 False) [line 99], FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 2, FParagraph (Keep 1 1 False) [line 1, line 2, line 3]]])
          @?= Right [[(0, SLine 99)], [(1, SLine 0), (17, SLine 1), (33, SLine 2)], [(1, SLine 3)]],
      testCase "root ADR 0397 I8 I11: internal keep controls look past a dimensional boundary space" $
        slots (paginatePhysical settings {physicalCapacity = 66, physicalMaxCapacity = 66, physicalBoxPadding = Map.singleton 5 4} [FParagraph (Keep 1 1 False) [line 99], FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FSpace 15, FKeepNext span0 2, FParagraph (Keep 1 1 False) [line 1, line 2, line 3]]])
          @?= Right [[(0, SLine 99)], [(1, SLine 0), (32, SLine 1), (48, SLine 2)], [(1, SLine 3)]],
      testCase "root ADR 0397 I8 I11: repeated internal keep controls retain their largest prefix" $
        slots (paginatePhysical settings {physicalCapacity = 66, physicalMaxCapacity = 66, physicalBoxPadding = Map.singleton 5 4} [FParagraph (Keep 1 1 False) [line 99], FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FKeepNext (mkSpan (FileId 0) 1 1) 3, FParagraph (Keep 1 1 False) [line 1, line 2, line 3, line 4]]])
          @?= Right [[(0, SLine 99)], [(1, SLine 0), (17, SLine 1), (33, SLine 2), (49, SLine 3)], [(1, SLine 4)]],
      testCase "root ADR 0397 I8: internal keeps retain each supported count from one to five" $
        forM_ [1 .. 5] $ \requested -> do
          let extent = fromIntegral (16 * (requested + 1) + 2)
              body = [FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 requested, FParagraph (Keep 1 1 False) [line n | n <- [1 .. requested + 1]]]
          slots (paginatePhysical settings {physicalCapacity = extent, physicalMaxCapacity = extent, physicalBoxPadding = Map.singleton 5 4} [FParagraph (Keep 1 1 False) [line 99], FBoxed 5 0 0 body])
            @?= Right [[(0, SLine 99)], [(1 + fromIntegral (16 * n), SLine n) | n <- [0 .. requested]], [(1, SLine (requested + 1))]],
      testCase "root ADR 0397 I8: an impossible internal link preserves the following keep-all paragraph" $ do
        let result = paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FParagraph (Keep 1 1 True) [line 1, line 2]]]
        slots result @?= Right [[(1, SLine 0)], [(1, SLine 1), (17, SLine 2)]]
        fmap (concatMap poUnmet) result @?= Right [UnmetKeepNext span0],
      testCase "root ADR 0397 I8 I13: an empty verse cannot hide an oversized following boxed row" $
        paginatePhysical settings {physicalCapacity = 17, physicalMaxCapacity = 17, physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[], [line 0]], FParagraph (Keep 1 1 False) [line 1]]]
          @?= Left (PhysicalBoxTooTall 5),
      testCase "root ADR 0397 I11: a split wrapped verse and the following paragraph share one trailing fragment" $ do
        let result = paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[line 0, line 1, line 2]], FParagraph (Keep 1 1 False) [line 3]]]
        slots result @?= Right [[(1, SLine 0), (17, SLine 1)], [(1, SLine 2), (17, SLine 3)]]
        fmap (map (length . poBoxes)) result @?= Right [1, 1],
      testCase "root ADR 0397 I9: an existing note separator is not reserved again before a box" $
        slots (paginatePhysical settings {physicalCapacity = 72, physicalMaxCapacity = 72, physicalSeparator = 8} [FParagraph (Keep 1 1 False) [noteLine 0], FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [LineBox 1 [NoteBody (NoteId span0 1) 1] [] [] 0]]])
          @?= Right [[(0, SLine 0), (16, SLine 1)]],
      testCase "root ADR 0397 I8: ordinary keeps look ahead to the following paragraph's first valid part" $
        slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FParagraph (Keep 3 1 False) [line 1, line 2, line 3, line 4]])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2), (48, SLine 3)], [(0, SLine 4)]],
      testCase "root ADR 0397 I8: repeated keep controls retain their largest requested prefix" $
        slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FKeepNext span0 3, FParagraph (Keep 1 1 False) [line 1, line 2, line 3, line 4]])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2), (48, SLine 3)], [(0, SLine 4)]],
      testCase "root ADR 0397 I8: a boundary before a keep control contributes to the retained extent" $
        slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FSpace 20, FKeepNext span0 1, FParagraph (Keep 1 1 False) [line 1]])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (36, SLine 1)]],
      testCase "root ADR 0397 I8: an ordinary stanza keeps its last original verse with following rows" $
        slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FStanza (Keep 1 1 False) [[line 0]], FKeepNext span0 3, FParagraph (Keep 1 1 False) [line 1, line 2, line 3, line 4]])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2), (48, SLine 3)], [(0, SLine 4)]],
      testCase "root ADR 0397 I8: keep-with-next does not split a preceding keep-all paragraph" $
        slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 True) [line 0, line 1, line 2], FKeepNext span0 1, FParagraph (Keep 1 1 False) [line 3]])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2), (48, SLine 3)]],
      testCase "root ADR 0397 I8: an impossible requested prefix warns even when one following row fits" $
        fmap (concatMap poUnmet) (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 True) [line 0, line 1], FKeepNext span0 3, FParagraph (Keep 1 1 False) [line 2, line 3, line 4]])
          @?= Right [UnmetKeepNext span0],
      testCase "root ADR 0397 I8: a feasible ordinary keep chain moves together" $ do
        let result = paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FParagraph (Keep 1 1 False) [line 1], FKeepNext (mkSpan (FileId 0) 1 1) 1, FParagraph defaultKeep [line 2, line 3]]
        slots result @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2), (48, SLine 3)]]
        fmap (concatMap poUnmet) result @?= Right [],
      testCase "root ADR 0397 I9: ordinary headings retain their footnote bodies" $
        fmap (map poFootnotes) (paginatePhysical settings {physicalSeparator = 10} [FHeading 1 False 16 [noteLine 0]])
          @?= Right [[(NoteId span0 0, 0, 1)]],
      testCase "root ADR 0397 I9: ruled headings retain their footnote bodies" $
        let side = RuleSide 0 0 1 True Nothing
            heading = FRuled 5 (Just side) Nothing False (RuleGrid 16 10) 0 (RuledHeading False 16 [noteLine 0])
         in fmap (map poFootnotes) (paginatePhysical settings {physicalSeparator = 10} [heading])
              @?= Right [[(NoteId span0 0, 0, 1)]],
      testCase "root ADR 0397 I8: a heading moves with the following paragraph" $
        slots (paginatePhysical settings {physicalCapacity = 48, physicalMaxCapacity = 48} [FParagraph defaultKeep [line 99], FHeading 2 False 16 [line 0], FParagraph defaultKeep [line 1, line 2]])
          @?= Right [[(0, SLine 99)], [(0, SHeading 0 1), (16, SLine 1), (32, SLine 2)]],
      testCase "root ADR 0397 I8: a definition term moves with its explanation" $
        slots (paginatePhysical settings {physicalCapacity = 48, physicalMaxCapacity = 48} [FParagraph defaultKeep [line 99], FDefTerm [line 0], FParagraph defaultKeep [line 1, line 2]])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2)]],
      testCase "root ADR 0397 I8: an otherwise empty column of headings permits a forced paragraph split" $
        slots (paginatePhysical settings {physicalCapacity = 48, physicalMaxCapacity = 48} [FHeading 2 False 16 [line 0], FParagraph defaultKeep [line 1, line 2, line 3]])
          @?= Right [[(0, SHeading 0 1), (16, SLine 1), (32, SLine 2)], [(0, SLine 3)]],
      testCase "root ADR 0397 I2, I5: exactly fitting line boxes remain in one column" $
        slots (paginatePhysical settings {physicalPitches = Map.fromList [(0, 21), (1, 21)]} [FParagraph (Keep 1 1 False) [line 0, line 1]])
          @?= Right [[(0, SLine 0), (21, SLine 1)]],
      testCase "root ADR 0397 I2, I5: one sp overflow moves the next line" $
        slots (paginatePhysical settings {physicalPitches = Map.fromList [(0, 21), (1, 22)]} [FParagraph (Keep 1 1 False) [line 0, line 1]])
          @?= Right [[(0, SLine 0)], [(0, SLine 1)]],
      testCase "root ADR 0397 I3: paragraph spacing is a physical distance" $
        slots (paginatePhysical settings [FParagraph defaultKeep [line 0], FSpace 3, FParagraph defaultKeep [line 1]])
          @?= Right [[(0, SLine 0), (19, SLine 1)]],
      testCase "root ADR 0397 I5: boundary spacing is dropped when the next paragraph moves" $
        slots (paginatePhysical settings [FParagraph defaultKeep [line 0], FSpace 20, FParagraph defaultKeep [line 1]])
          @?= Right [[(0, SLine 0)], [(0, SLine 1)]],
      testCase "root ADR 0397 I13: a line larger than an empty column fails" $
        paginatePhysical settings {physicalPitches = Map.singleton 0 43} [FParagraph defaultKeep [line 0]] @?= Left (PhysicalLineTooTall 0),
      testCase "root ADR 0397 I8: empty input has no occupied positions" $
        slots (paginatePhysical settings []) @?= Right [[]],
      testCase "root ADR 0397 I10: wrapped figure keeps its side lines at the same origin" $
        slots (paginatePhysical settings [FWrapped 10 32 [] [] [line 0, line 1]])
          @?= Right [[(0, SWrapped 10), (0, SLine 0), (16, SLine 1)]],
      testCase "root ADR 0397 I8: a table repeats its header on the next column" $
        slots (paginatePhysical settings [FTable 10 0 [line 0] [[line 1], [line 2]] [] False])
          @?= Right [[(0, SLine 0), (16, SLine 1)], [(0, SLine 0), (16, SLine 2)]],
      testCase "root ADR 0397 I8: a code block splits by rows" $
        let geometry = codeGeometry 10 16 10 0
         in slots (paginatePhysical settings [FCode geometry 0 1 False [line 0, line 1, line 2]])
              @?= Right [[(0, SCode 0 2 2)], [(0, SCode 2 1 1)]],
      testCase "root ADR 0397 I8: no-break keeps the preceding paragraph with the next" $
        slots (paginatePhysical settings [FParagraph defaultKeep [line 0], FParagraph defaultKeep [line 1], FNoBreak span0, FParagraph defaultKeep [line 2]])
          @?= Right [[(0, SLine 0)], [(0, SLine 1), (16, SLine 2)]],
      testCase "root ADR 0397 I11: a before rule uses its physical extra length" $
        let before = RuleSide 10 0 2 True Nothing
            ruled = FRuled 5 (Just before) Nothing False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 0])
         in slots (paginatePhysical settings [ruled]) @?= Right [[(9, SLine 0)]],
      testCase "root ADR 0397 I11, I13: a boxed line checks the physical padding" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 18} [FBoxed 5 0 0 [FParagraph defaultKeep [line 0]]])
          @?= Left (PhysicalBoxTooTall 5),
      testCase "root ADR 0397 I8, I9: a line and its first footnote fit exactly" $
        fmap (map poFootnotes) (paginatePhysical settings {physicalSeparator = 10} [FParagraph defaultKeep [noteLine 0]])
          @?= Right [[(NoteId span0 0, 0, 1)]],
      testCase "root ADR 0397 I9, I13: a first footnote one sp too tall fails" $
        paginatePhysical settings {physicalCapacity = 41, physicalSeparator = 10} [FParagraph defaultKeep [noteLine 0]]
          @?= Left (PhysicalFootnoteTooTall (NoteId span0 0)),
      testCase "root ADR 0397 I5, I12: successive explicit blank lines add their lengths" $
        slots (paginatePhysical settings {physicalCapacity = 70} [FParagraph defaultKeep [line 0], FBlank span0 1, FBlank span0 1, FParagraph defaultKeep [line 1]])
          @?= Right [[(0, SLine 0), (48, SLine 1)]],
      testCase "root ADR 0397 I8, I11: each box fragment includes its own padding" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0, line 1, line 2]]])
          @?= Right [[(1, SLine 0), (17, SLine 1)], [(1, SLine 2)]],
      testCase "root ADR 0397 I5: boundary spacing at the column top is dropped" $
        slots (paginatePhysical settings [FSpace 3, FParagraph defaultKeep [line 0]])
          @?= Right [[(0, SLine 0)]],
      testCase "root ADR 0397 I8, I11: a box of multiple paragraphs pads each fragment" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph defaultKeep [line 0], FSpace 3, FParagraph defaultKeep [line 1], FParagraph defaultKeep [line 2]]])
          @?= Right [[(1, SLine 0), (20, SLine 1)], [(1, SLine 2)]],
      testCase "root ADR 0397 I12: need-lines has the same result on either side of a boundary space" $
        let before = [FParagraph defaultKeep [line 0], FNeedLines span0 1, FSpace 20, FParagraph defaultKeep [line 1]]
            after = [FParagraph defaultKeep [line 0], FSpace 20, FNeedLines span0 1, FParagraph defaultKeep [line 1]]
         in slots (paginatePhysical settings before) @?= slots (paginatePhysical settings after),
      testCase "root ADR 0397 I8: page-lines cannot shrink past already placed text" $
        fmap (map poLines) (paginatePhysical settings [FParagraph defaultKeep [line 0], FAdjustLines span0 (-2)])
          @?= Right [26],
      testCase "root ADR 0397 I11: adjacent rules share one physical area" $
        let side = RuleSide 4 2 2 True Nothing
            first = FRuled 5 Nothing (Just side) False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 0])
            second = FRuled 6 (Just side) Nothing True (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 1])
         in slots (paginatePhysical settings {physicalCapacity = 70} [first, second])
              @?= Right [[(0, SLine 0), (24, SLine 1)]],
      testCase "root ADR 0397 I9: a continued footnote keeps its line counts across pages" $
        fmap (map poFootnotes) (paginatePhysical settings {physicalSeparator = 10} [FParagraph defaultKeep [longNoteLine 0]])
          @?= Right [[(NoteId span0 0, 0, 1)], [(NoteId span0 0, 1, 2)]],
      testCase "root ADR 0397 I8, I9, I13: a boxed line with no room for its first note fails as a note" $
        paginatePhysical settings {physicalSeparator = 10, physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph defaultKeep [noteLine 0]]]
          @?= Left (PhysicalFootnoteTooTall (NoteId span0 0)),
      testCase "root ADR 0397 I12: need-lines above the column length is recorded unmet" $
        fmap (concatMap poUnmet) (paginatePhysical settings [FParagraph defaultKeep [line 0], FNeedLines span0 3])
          @?= Right [UnmetNeedLines span0 3],
      testCase "root ADR 0397 I8, I12: a waiting figure leaves room for following text" $
        slots (paginatePhysical settings [FParagraph defaultKeep [line 0], FFigure 10 30 [] [], FParagraph defaultKeep [line 1]])
          @?= Right [[(0, SLine 0), (16, SLine 1)], [(0, SFigure 10)]],
      testCase "root ADR 0397 I11: a ruled heading retains the rule that fits" $
        let before = RuleSide 10 0 2 True Nothing
            ruled = FRuled 5 (Just before) Nothing False (RuleGrid 16 10) 0 (RuledHeading False 16 [line 0])
         in fmap (map poRules) (paginatePhysical settings [ruled])
              @?= Right [[PlacedRule 5 True 0]],
      testCase "root ADR 0397 I8: a recto heading starts on an odd page with a blank verso" $
        fmap (map (\page -> (poNumber page, poBlank page, poSlots page))) (paginatePhysical settings [FParagraph defaultKeep [line 0], FHeading 1 True 16 [line 1]])
          @?= Right [(1, False, [(0, SLine 0)]), (2, True, []), (3, False, [(0, SHeading 1 1)])],
      testCase "root ADR 0397 I11: an oversized pair of heading rules drops the after rule first" $ do
        let side = RuleSide 10 0 2 True Nothing
            heading = FRuled 5 (Just side) (Just side) False (RuleGrid 16 10) 0 (RuledHeading False 16 [line 0])
            result = paginatePhysical settings {physicalCapacity = 30, physicalMaxCapacity = 30} [heading]
        slots result @?= Right [[(9, SHeading 0 1)]]
        fmap (map poRules) result @?= Right [[PlacedRule 5 True 0]],
      testCase "root ADR 0397 I9 I11: heading rule omission retains its first note in the same column" $ do
        let side = RuleSide 10 0 2 True Nothing
            heading = FRuled 5 (Just side) (Just side) False (RuleGrid 16 10) 0 (RuledHeading False 16 [noteLine 0])
            result = paginatePhysical settings {physicalCapacity = 58, physicalMaxCapacity = 58, physicalSeparator = 10} [heading]
        slots result @?= Right [[(9, SHeading 0 1)]]
        fmap (map poRules) result @?= Right [[PlacedRule 5 True 0]]
        fmap (map poFootnotes) result @?= Right [[(NoteId span0 0, 0, 1)]],
      testCase "root ADR 0397 I8 I11: keep-with-next reserves only the first legal part of a following box" $ do
        let boxed = FBoxed 5 0 0 [FParagraph defaultKeep [line 1, line 2, line 3, line 4]]
            flows = [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, boxed]
        slots (paginatePhysical settings {physicalCapacity = 58, physicalMaxCapacity = 58, physicalBoxPadding = Map.singleton 5 4} flows)
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (17, SLine 1), (33, SLine 2)], [(1, SLine 3), (17, SLine 4)]]
        slots (paginatePhysical settings {physicalCapacity = 66, physicalMaxCapacity = 66, physicalBoxPadding = Map.singleton 5 4} flows)
          @?= Right [[(0, SLine 99), (16, SLine 0), (33, SLine 1), (49, SLine 2)], [(1, SLine 3), (17, SLine 4)]],
      testCase "root ADR 0397 I8 I11: keep-with-next measures the following rule from the actual preceding face" $ do
        let side = RuleSide 10 0 2 True Nothing
            ruled = FRuled 5 (Just side) Nothing False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 1, line 2])
            flows = [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, ruled]
        slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} flows)
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (22, SLine 1), (38, SLine 2)]]
        slots (paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70} flows)
          @?= Right [[(0, SLine 99), (16, SLine 0), (38, SLine 1), (54, SLine 2)]],
      testCase "root ADR 0397 I8 I11: a ruled paragraph retains the requested following prefix" $
        let side = RuleSide 10 0 2 True Nothing
            ruled = FRuled 5 (Just side) Nothing False (RuleGrid 16 10) 0 (RuledLines (Keep 1 1 False) [line 0])
         in slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], ruled, FKeepNext span0 2, FParagraph defaultKeep [line 1, line 2]])
              @?= Right [[(0, SLine 99)], [(9, SLine 0), (25, SLine 1), (41, SLine 2)]],
      testCase "root ADR 0397 I8 I9: keep-with-next reserves the first table part and its note" $
        slots (paginatePhysical settings {physicalCapacity = 74, physicalMaxCapacity = 74, physicalSeparator = 10} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FTable 10 0 [noteLine 1] [[line 2]] [] False])
          @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SLine 1), (32, SLine 2)]],
      testCase "root ADR 0397 I8: keep-with-next reserves code caption and minimum initial rows" $
        let geometry = codeGeometry 10 16 10 0
         in slots (paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64} [FParagraph (Keep 1 1 False) [line 99], FParagraph (Keep 1 1 False) [line 0], FKeepNext span0 1, FCode geometry 16 2 False [line 1, line 2]])
              @?= Right [[(0, SLine 99)], [(0, SLine 0), (16, SCode 1 2 2)]],
      testCase "root ADR 0397 I8 I9: table header notes reserve the first body row" $ do
        let result = paginatePhysical settings {physicalCapacity = 64, physicalMaxCapacity = 64, physicalSeparator = 10} [FTable 10 0 [longNoteLine 0] [[line 1]] [] False]
        fmap (map poSlots) result @?= Right [[(0, SLine 0), (16, SLine 1)], []]
        case result of
          Left failure -> assertFailure (show failure)
          Right pages -> do
            sum [count | page <- pages, (_, _, count) <- poFootnotes page] @?= 3
            forM_ pages $ \page -> do
              let noteCount = sum [count | (_, _, count) <- poFootnotes page]
                  reserved = fromIntegral noteCount * 16 + if noteCount > 0 then 10 else 0
              forM_ (poSlots page) $ \(at, _) -> assertBool "table row overlaps notes" (at + 16 <= poLines page - reserved),
      testCase "root ADR 0397 I9 I13: a table minimum with its first note fits exactly" $
        fmap (map poSlots) (paginatePhysical settings {physicalCapacity = 58, physicalMaxCapacity = 58, physicalSeparator = 10} [FTable 10 0 [noteLine 0] [[line 1]] [] False])
          @?= Right [[(0, SLine 0), (16, SLine 1)]],
      testCase "root ADR 0397 I9 I13: a table minimum with its first note one sp too tall fails as a note" $
        paginatePhysical settings {physicalCapacity = 57, physicalMaxCapacity = 57, physicalSeparator = 10} [FTable 10 0 [noteLine 0] [[line 1]] [] False]
          @?= Left (PhysicalFootnoteTooTall (NoteId span0 0)),
      testCase "root ADR 0397 I8 I9 I13: bounded tables preserve body rows and notes within every fragment" $ do
        let cases = [(capacity, headerCount, firstCount, lastCount, captionCount, below, noteAt, columns) | capacity <- [14, 18, 22], headerCount <- [0, 1], firstCount <- [1, 2], lastCount <- [1, 2], captionCount <- [0, 1], below <- [False, True], noteAt <- [0 .. 3 :: Int], columns <- [1, 2]]
        length cases @?= 768
        forM_ cases $ \sample@(capacity, headerCount, firstCount, lastCount, captionCount, below, noteAt, columns) -> do
          let rows base count location = [LineBox (base + i) [NoteBody (NoteId span0 base) 3 | i == 0 && location == noteAt] [] [] 0 | i <- [0 .. count - 1]]
              header = rows 0 headerCount 1
              first = rows 10 firstCount 2
              last' = rows 20 lastCount 3
              caption = [line (30 + i) | i <- [0 .. captionCount - 1]]
              cfg = settings {physicalPagePitch = 4, physicalFontSize = 2, physicalCapacity = capacity, physicalMaxCapacity = capacity, physicalSeparator = 1, physicalColumns = ColumnSet columns 0 0 0}
              expectedNotes = Map.fromList [(nbId note, nbLines note) | row <- header <> first <> last', note <- lbNotes row]
              firstMinimum = 4 * fromIntegral (headerCount + firstCount + if below then 0 else captionCount)
              lastMinimum = 4 * fromIntegral (headerCount + lastCount + if below then captionCount else 0)
              firstNote = noteAt == 2 || (headerCount > 0 && noteAt == 1)
              mustFail = firstMinimum > capacity || lastMinimum > capacity || (firstNote && firstMinimum + 5 > capacity) || (noteAt == 3 && lastMinimum + 5 > capacity)
              refused = assertBool (show sample <> ": refused a fitting table minimum") mustFail
          case paginatePhysical cfg [FTable 10 0 header [first, last'] caption below] of
            Left PhysicalTableTooTall {} -> refused
            Left PhysicalTableCaptionTooTall {} -> refused
            Left PhysicalFootnoteTooTall {} -> refused
            Left failure -> assertFailure (show sample <> ": " <> show failure)
            Right pages -> do
              assertBool (show sample <> ": accepted an oversized table minimum") (not mustFail)
              sort [ident | page <- pages, (_, SLine ident) <- poSlots page, ident >= 10] @?= map lbId (first <> last' <> caption)
              Map.fromListWith (+) [(ident, count) | page <- pages, (ident, _, count) <- poFootnotes page] @?= expectedNotes
              forM_ pages $ \page -> do
                let noteCount = sum [count | (_, _, count) <- poFootnotes page]
                    reserved = fromIntegral noteCount * 4 + if noteCount > 0 then 1 else 0
                forM_ (poSlots page) $ \(at, _) -> assertBool (show sample <> ": table overlaps note region") (at >= 0 && at + 4 <= poLines page - reserved),
      testCase "root ADR 0397 I8 I9: equal physical and grid units agree on bounded ordinary flows" $ do
        let variants = [0 .. 15 :: Int]
            inputs = [] : [[a] | a <- variants] <> [[a, b] | a <- variants, b <- variants] <> [[a, b, c] | a <- variants, b <- variants, c <- variants]
            cases = [(capacity, columns, kinds) | capacity <- [3 .. 6], columns <- [1, 2], kinds <- inputs]
            makeFlow index kind =
              let ident = 100 * index
                  noted = LineBox ident [NoteBody (NoteId span0 ident) 1] [] [] 0
               in case kind of
                    0 -> FParagraph defaultKeep [line ident]
                    1 -> FParagraph defaultKeep [line ident, line (ident + 1)]
                    2 -> FParagraph defaultKeep [line ident, line (ident + 1), line (ident + 2)]
                    3 -> FHeading 2 False 1 [line ident]
                    4 -> FDefTerm [line ident]
                    5 -> FSpace 1
                    6 -> FFigure ident 2 [] []
                    7 -> FParagraph defaultKeep [noted]
                    8 -> FHeading 2 False 1 [noted]
                    9 -> FStanza defaultKeep [[line ident], [line (ident + 1)], [line (ident + 2)]]
                    10 -> FNoBreak span0
                    11 -> FKeepNext span0 2
                    12 -> FBlank span0 1
                    13 -> FNeedLines span0 2
                    14 -> FNoBreakLines span0 3
                    _ -> FContinued defaultKeep [line ident, line (ident + 1), line (ident + 2)]
            trace pages = [(poNumber page, poColumn page, poBlank page, poSlots page, poFootnotes page) | page <- pages]
        length cases @?= 34952
        forM_ cases $ \sample@(capacity, columns, kinds) -> do
          let flows = zipWith makeFlow [0 ..] kinds
              set = ColumnSet columns 0 0 0
              cfg = settings {physicalPagePitch = 1, physicalFontSize = 1, physicalCapacity = fromIntegral capacity, physicalMaxCapacity = fromIntegral capacity, physicalSeparator = 1, physicalColumns = fmap fromIntegral set}
              expected = trace (map (fmap fromIntegral) (paginateIn 1 set capacity flows))
              actual = fmap trace (paginatePhysical cfg (map (fmap fromIntegral) flows))
          assertEqual (show sample) (Right expected) actual,
      testCase "root ADR 0397 I8 I9 I11: bounded variable-pitch flows retain every row and note within physical bounds" $ do
        let keeps = [Keep 1 1 False, Keep 2 2 False, Keep 1 1 True]
            cases = [(capacity, columns, n, m, p, q, noted, padding, a, b, gap, boxed) | capacity <- [14, 18], columns <- [1, 2], n <- [0 .. 2], m <- [0 .. 2], p <- [3, 5], q <- [3, 5], noted <- [False, True], padding <- [0, 2], a <- keeps, b <- keeps, gap <- [0, 1], boxed <- [False, True]]
        length cases @?= 20736
        forM_ cases $ \sample@(capacity, columns, n, m, p, q, noted, padding, a, b, gap, boxed) -> do
          let rows base count = [LineBox (base + i) [NoteBody (NoteId span0 base) 2 | noted && i == 0] [] [] 0 | i <- [0 .. count - 1]]
              firstRows = rows 0 n
              secondRows = rows 10 m
              allRows = firstRows <> secondRows
              pitches = Map.fromList ([(lbId row, p) | row <- firstRows] <> [(lbId row, q) | row <- secondRows])
              cfg = settings {physicalPagePitch = 4, physicalFontSize = 2, physicalCapacity = capacity, physicalMaxCapacity = capacity, physicalSeparator = 1, physicalColumns = ColumnSet columns 0 0 0, physicalPitches = pitches, physicalBoxPadding = Map.singleton 5 padding}
              body = [FParagraph a firstRows, FSpace gap, FParagraph b secondRows]
              flows = if boxed then [FBoxed 5 0 0 body] else body
              context = show sample
          case paginatePhysical cfg flows of
            Left failure -> assertFailure (context <> ": " <> show failure)
            Right pages -> do
              sort [ident | page <- pages, (_, SLine ident) <- poSlots page] @?= map lbId allRows
              let actualNotes = Map.fromListWith (+) [(ident, count) | page <- pages, (ident, _, count) <- poFootnotes page]
                  expectedNotes = Map.fromList [(nbId note, nbLines note) | row <- allRows, note <- lbNotes row]
              actualNotes @?= expectedNotes
              forM_ pages $ \page -> do
                let noteCount = sum [count | (_, _, count) <- poFootnotes page]
                    reserved = fromIntegral noteCount * physicalPagePitch cfg + if noteCount > 0 then physicalSeparator cfg else 0
                forM_ (poSlots page) $ \(at, slotted) -> case slotted of
                  SLine ident -> assertBool (context <> ": row outside text region") (at >= 0 && at + Map.findWithDefault 4 ident pitches <= poLines page - reserved)
                  _ -> pure ()
                forM_ (poBoxes page) $ \segment -> assertBool (context <> ": box outside text region") (bsFirst segment >= 0 && bsLast segment <= poLines page - reserved),
      testCase "root ADR 0397 I8: small flows lose no lines and exceed no physical region" $
        let samples =
              [ (settings, [], []),
                (settings, [FParagraph defaultKeep [line 0]], [0]),
                (settings {physicalCapacity = 70, physicalPitches = Map.fromList [(0, 21), (1, 17)]}, [FParagraph defaultKeep [line 0], FSpace 3, FParagraph defaultKeep [line 1]], [0, 1]),
                (settings {physicalSeparator = 10}, [FParagraph defaultKeep [noteLine 0]], [0]),
                (settings {physicalBoxPadding = Map.singleton 5 4}, [FBoxed 5 0 0 [FParagraph (Keep 1 1 False) [line 0, line 1, line 2]]], [0, 1, 2])
              ]
         in forM_ samples $ \(cfg, flows, expectedIds) -> case paginatePhysical cfg flows of
              Left failure -> assertFailure (show failure)
              Right pages -> do
                let placedIds = [ident | page <- pages, (_, SLine ident) <- poSlots page]
                sort placedIds @?= expectedIds
                forM_ pages $ \page -> do
                  let noteCount = sum [count | (_, _, count) <- poFootnotes page]
                      reserved = fromIntegral noteCount * physicalPagePitch cfg + if noteCount > 0 then physicalSeparator cfg else 0
                  forM_ (poSlots page) $ \(at, slotted) -> case slotted of
                    SLine ident -> assertBool "line exceeds the text region" (at >= 0 && at + Map.findWithDefault (physicalPagePitch cfg) ident (physicalPitches cfg) <= poLines page - reserved)
                    _ -> pure ()
                  forM_ (poBoxes page) $ \segment -> assertBool "box exceeds the column" (bsFirst segment >= 0 && bsLast segment <= poLines page),
      testCase "root ADR 0397 I8: an impossible keep-with-next chain records the relaxed keep" $
        fmap (concatMap poUnmet) (paginatePhysical settings [FParagraph defaultKeep [line 0], FKeepNext span0 1, FParagraph defaultKeep [line 1], FKeepNext span0 1, FParagraph defaultKeep [line 2]])
          @?= Right [UnmetKeepNext span0],
      testCase "root ADR 0397 I8, I13: a table header and first row must fit physically" $
        paginatePhysical settings [FTable 10 0 [line 0, line 1] [[line 2]] [] False]
          @?= Left (PhysicalTableTooTall 10),
      testCase "root ADR 0397 I8, I13: a table caption with its first row must fit" $
        paginatePhysical settings [FTable 10 0 [line 0] [[line 1]] [line 2] False]
          @?= Left (PhysicalTableCaptionTooTall 10),
      testCase "root ADR 0397 I8, I13: a code block minimum part must fit" $
        let geometry = codeGeometry 10 16 10 16
         in paginatePhysical settings [FCode geometry 0 1 False [line 0]]
              @?= Left (PhysicalCodeTooTall 0),
      testCase "root ADR 0397 I8: a section column start in an empty column stays there" $
        fmap (map poNumber) (paginatePhysical settings [FSection (OfParagraph span0) BreakColumn, FParagraph defaultKeep [line 0]])
          @?= Right [1],
      testCase "root ADR 0397 I8: a section page start in an empty page stays there" $
        fmap (map poNumber) (paginatePhysical settings [FSection (OfParagraph span0) BreakPage, FParagraph defaultKeep [line 0]])
          @?= Right [1],
      testCase "root ADR 0397 I8: a section start is recorded on its first page" $
        fmap (map poSections) (paginatePhysical settings [FSection (OfSection 7) BreakPage, FParagraph defaultKeep [line 0]])
          @?= Right [[7]],
      testCase "root ADR 0397 I5: a blank line dropped at the column top is reported" $
        fmap (concatMap poUnmet) (paginatePhysical settings [FBlank span0 1, FParagraph defaultKeep [line 0]])
          @?= Right [DroppedBlank span0],
      testCase "root ADR 0397 I8: index columns keep their physical start on a one-column page" $
        let set = ColumnSet 2 0 0 0
         in fmap (map (\page -> (poNumber page, csFirstLine (poColumnSet page), poSlots page))) (paginatePhysical settings [FParagraph defaultKeep [line 0], FSwitchColumns set, FParagraph defaultKeep [line 1]])
              @?= Right [(1, 0, [(0, SLine 0)]), (1, 16, [(16, SLine 1)])],
      testCase "root ADR 0397 I10: wrapped paragraphs keep their physical boundary space" $
        slots (paginatePhysical settings {physicalPagePitch = 10, physicalFontSize = 10, physicalCapacity = 50, physicalMaxCapacity = 50, physicalWrappedBefore = Map.singleton 1 12} [FWrapped 10 30 [] [] [line 0, line 1]])
          @?= Right [[(0, SWrapped 10), (0, SLine 0), (22, SLine 1)]],
      testCase "root ADR 0397 I8, I9: deferred figure precedes continued notes in the new column" $
        let marker = LineBox 0 [NoteBody (NoteId span0 0) 4] [] [] 0
            result = paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70, physicalSeparator = 10} [FParagraph defaultKeep [marker], FFigure 10 30 [] []]
         in fmap (map (\page -> (poSlots page, poFootnotes page))) result
              @?= Right
                [ ([(0, SLine 0)], [(NoteId span0 0, 0, 2)]),
                  ([(0, SFigure 10)], [(NoteId span0 0, 2, 1)]),
                  ([], [(NoteId span0 0, 3, 1)])
                ],
      testCase "root ADR 0397 I8, I11: boxed stanza repeats padding in each column" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[line 0], [line 1], [line 2]]]])
          @?= Right [[(1, SLine 0), (17, SLine 1)], [(1, SLine 2)]],
      testCase "root ADR 0397 I8, I11: a wrapped verse line stays whole inside a box" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[line 0, line 1], [line 2]]]])
          @?= Right [[(1, SLine 0), (17, SLine 1)], [(1, SLine 2)]],
      testCase "root ADR 0397 I5: dropped top space leaves room for both lines" $
        slots (paginatePhysical settings [FSpace 20, FParagraph defaultKeep [line 0, line 1]])
          @?= Right [[(0, SLine 0), (16, SLine 1)]],
      testCase "root ADR 0397 I8: forced short paragraph records both keep failures" $
        fmap (concatMap poUnmet) (paginatePhysical settings [FParagraph (Keep 3 2 False) [line 0, line 1, line 2]])
          @?= Right [ShortPart FirstPart 0 3 2, ShortPart LastPart 0 2 1],
      testCase "root ADR 0397 I8: forced short stanza records both keep failures" $
        fmap (concatMap poUnmet) (paginatePhysical settings [FStanza (Keep 3 2 False) [[line 0], [line 1], [line 2]]])
          @?= Right [ShortPart FirstPart 0 3 2, ShortPart LastPart 0 2 1],
      testCase "root ADR 0397 I8: forced short boxed paragraph records keep failures" $
        fmap (concatMap poUnmet) (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph (Keep 3 2 False) [line 0, line 1, line 2]]])
          @?= Right [ShortPart FirstPart 0 3 2, ShortPart LastPart 0 2 1],
      testCase "root ADR 0397 I10: a wrapped side line moves when its note does not fit beside the figure" $
        slots (paginatePhysical settings {physicalSeparator = 10} [FWrapped 10 32 [] [] [noteLine 0]])
          @?= Right [[(0, SWrapped 10)], [(0, SLine 0)]],
      testCase "root ADR 0397 I8: code starts after a physical boundary space" $
        let geometry = codeGeometry 10 16 10 0
         in slots (paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70} [FParagraph defaultKeep [line 0], FSpace 3, FCode geometry 0 1 False [line 1]])
              @?= Right [[(0, SLine 0), (19, SCode 1 1 1)]],
      testCase "root ADR 0397 I13: every table row must fit with its repeated header" $
        paginatePhysical settings [FTable 10 0 [line 0] [[line 1], [line 2, line 3, line 4]] [] False]
          @?= Left (PhysicalTableTooTall 10),
      testCase "root ADR 0397 I8: forced short boxed stanza records keep failures" $
        fmap (concatMap poUnmet) (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FStanza (Keep 3 2 False) [[line 0], [line 1], [line 2]]]])
          @?= Right [ShortPart FirstPart 0 3 2, ShortPart LastPart 0 2 1],
      testCase "root ADR 0397 I13: a table minimum skips an empty shortened column" $
        fmap (map (\page -> (poNumber page, poSlots page))) (paginatePhysical settings [FAdjustLines span0 (-1), FTable 10 0 [line 0] [[line 1]] [] False])
          @?= Right [(2, [(0, SLine 0), (16, SLine 1)])],
      testCase "root ADR 0397 I13: a code minimum skips an empty shortened column" $
        let geometry = codeGeometry 10 16 10 0
         in fmap (map (\page -> (poNumber page, poSlots page))) (paginatePhysical settings [FAdjustLines span0 (-1), FCode geometry 0 2 False [line 0, line 1]])
              @?= Right [(2, [(0, SCode 0 2 2)])],
      testCase "root ADR 0397 I9: keep-with-next counts the next line and its note" $
        slots (paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70, physicalSeparator = 10} [FParagraph defaultKeep [line 0], FParagraph defaultKeep [line 1], FKeepNext span0 1, FParagraph defaultKeep [noteLine 2]])
          @?= Right [[(0, SLine 0)], [(0, SLine 1), (16, SLine 2)]],
      testCase "root ADR 0397 I10: wrapped figure fits when only side lines overflow" $
        slots (paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70} [FParagraph defaultKeep [line 0], FWrapped 10 32 [] [] [line 1, line 2, line 3, line 4]])
          @?= Right [[(0, SLine 0), (16, SWrapped 10), (16, SLine 1), (32, SLine 2), (48, SLine 3)], [(0, SLine 4)]],
      testCase "root ADR 0397 I8, I9, I11: a ruled paragraph reserves its ending rule before notes" $
        let side = RuleSide 10 0 2 True Nothing
            ruled = FRuled 5 Nothing (Just side) False (RuleGrid 16 10) 0 (RuledLines defaultKeep [noteLine 0])
         in fmap (map poFootnotes) (paginatePhysical settings {physicalSeparator = 10} [ruled])
              @?= Right [[], [(NoteId span0 0, 0, 1)]],
      testCase "root ADR 0397 I11: a joined box with prose and single-row verses has padding in each part" $
        slots (paginatePhysical settings {physicalBoxPadding = Map.singleton 5 4} [FBoxed 5 0 0 [FParagraph defaultKeep [line 0], FSpace 3, FStanza (Keep 1 1 False) [[line 1], [line 2]]]])
          @?= Right [[(1, SLine 0), (20, SLine 1)], [(1, SLine 2)]],
      testCase "root ADR 0397 I11: an unspaced before rule centers odd sp at the type-area edge" $
        let side = RuleSide 0 0 1 False Nothing
            ruled = FRuled 5 (Just side) Nothing False (RuleGrid 17 10) 0 (RuledLines defaultKeep [line 0])
         in fmap (concatMap poRules) (paginatePhysical settings {physicalPitches = Map.singleton 0 17} [ruled])
              @?= Right [PlacedRule 5 True 1],
      testCase "root ADR 0397 I11: an unspaced after rule centers odd sp at the type-area edge" $
        let side = RuleSide 0 0 1 False Nothing
            ruled = FRuled 5 Nothing (Just side) False (RuleGrid 17 10) 0 (RuledLines defaultKeep [line 0])
         in fmap (concatMap poRules) (paginatePhysical settings {physicalPitches = Map.singleton 0 17} [ruled])
              @?= Right [PlacedRule 5 False 14],
      testCase "root ADR 0397 I8: a heading may exceed only a shortened column" $
        fmap
          (map (\page -> (poNumber page, poSlots page, poUnmet page)))
          ( paginatePhysical
              settings {physicalPagePitch = 20, physicalCapacity = 90, physicalMaxCapacity = 90}
              [FAdjustLines span0 (-1), FHeading 1 False 80 [line 0]]
          )
          @?= Right [(1, [(0, SHeading 0 1)], [TallHeadingExtent 0 80 70])],
      testCase "root ADR 0397 I11: an unspaced heading rule centers odd sp" $
        let side = RuleSide 0 0 1 False Nothing
            ruled = FRuled 5 (Just side) Nothing False (RuleGrid 17 10) 0 (RuledHeading False 17 [line 0])
         in fmap (concatMap poRules) (paginatePhysical settings {physicalPitches = Map.singleton 0 17} [ruled])
              @?= Right [PlacedRule 5 True 1],
      testCase "root ADR 0397 I11: an interior before rule reserves its outer gap" $
        let side = RuleSide 0 10 1 True Nothing
            ruled = FRuled 5 (Just side) Nothing False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 1])
         in fmap (map (\page -> (poSlots page, poRules page))) (paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70} [FParagraph defaultKeep [line 0], ruled])
              @?= Right [([(0, SLine 0), (21, SLine 1)], [PlacedRule 5 True 23])],
      testCase "root ADR 0397 I11: an interior after rule reserves its outer gap" $
        let side = RuleSide 0 10 1 True Nothing
            ruled = FRuled 5 Nothing (Just side) False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 0])
         in fmap (map (\page -> (poSlots page, poRules page))) (paginatePhysical settings {physicalCapacity = 70, physicalMaxCapacity = 70} [ruled, FParagraph defaultKeep [line 1]])
              @?= Right [([(0, SLine 0), (21, SLine 1)], [PlacedRule 5 False 13])],
      testCase "root ADR 0397 I11: two unspaced rules share the central remainder" $
        let side = RuleSide 0 0 1 False Nothing
            first = FRuled 5 Nothing (Just side) False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 0])
            second = FRuled 6 (Just side) Nothing True (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 1])
         in fmap (concatMap poRules) (paginatePhysical settings [first, second])
              @?= Right [PlacedRule 5 False 14, PlacedRule 6 True 17],
      testCase "root ADR 0397 I11: joined rules separate when the second block moves" $
        let side = RuleSide 0 10 1 True Nothing
            first = FRuled 5 Nothing (Just side) False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 0])
            second = FRuled 6 (Just side) Nothing True (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 1])
         in fmap (map (\page -> (poSlots page, poRules page))) (paginatePhysical settings {physicalPitches = Map.singleton 1 30} [first, second])
              @?= Right [([(0, SLine 0)], [PlacedRule 5 False 13]), ([(0, SLine 1)], [PlacedRule 6 True 9])],
      testCase "root ADR 0397 I12: a waiting figure does not erase a boundary space before need-lines" $
        let cfg = settings {physicalCapacity = 70, physicalMaxCapacity = 70}
            before = [FParagraph defaultKeep [line 0], FFigure 10 70 [] [], FSpace 16, FFigure 11 16 [] [], FNeedLines span0 2, FParagraph defaultKeep [line 1]]
            after = [FParagraph defaultKeep [line 0], FFigure 10 70 [] [], FFigure 11 16 [] [], FSpace 16, FNeedLines span0 2, FParagraph defaultKeep [line 1]]
         in (slots (paginatePhysical cfg before), slots (paginatePhysical cfg after))
              @?= (Right [[(0, SLine 0), (32, SLine 1)], [(0, SFigure 10)], [(0, SFigure 11)]], Right [[(0, SLine 0), (32, SLine 1)], [(0, SFigure 10)], [(0, SFigure 11)]]),
      testCase "root ADR 0397 I12: need-lines is judged again after a deferred figure moves" $
        slots
          ( paginatePhysical
              settings {physicalCapacity = 70, physicalMaxCapacity = 70, physicalPitches = Map.singleton 1 10}
              [FParagraph defaultKeep [line 0], FFigure 10 55 [] [], FNeedLines span0 4, FParagraph defaultKeep [line 1]]
          )
          @?= Right [[(0, SLine 0)], [(0, SFigure 10)], [(0, SLine 1)]],
      testCase "root ADR 0397 I11: a mixed box keeps a wrapped verse whole with padding" $
        slots
          ( paginatePhysical
              settings {physicalBoxPadding = Map.singleton 5 4}
              [FBoxed 5 0 0 [FParagraph defaultKeep [line 0], FSpace 3, FStanza defaultKeep [[line 1, line 2], [line 3]]]]
          )
          @?= Right [[(1, SLine 0)], [(1, SLine 1), (17, SLine 2)], [(1, SLine 3)]],
      testCase "root ADR 0397 I8: a ruled heading may exceed a shortened column" $
        let ruled = FRuled 5 Nothing Nothing False (RuleGrid 20 10) 0 (RuledHeading False 80 [line 0])
         in fmap
              (map (\page -> (poNumber page, poSlots page, poUnmet page)))
              ( paginatePhysical
                  settings {physicalPagePitch = 20, physicalCapacity = 90, physicalMaxCapacity = 90}
                  [FAdjustLines span0 (-1), ruled]
              )
              @?= Right [(1, [(0, SHeading 0 1)], [TallHeadingExtent 0 80 70])],
      testCase "root ADR 0397 I8, I11: keep-next inside a joined box moves both paragraphs" $
        slots
          ( paginatePhysical
              settings {physicalBoxPadding = Map.singleton 5 4}
              [FParagraph defaultKeep [line 0], FBoxed 5 0 0 [FParagraph defaultKeep [line 1], FKeepNext span0 1, FParagraph defaultKeep [line 2]]]
          )
          @?= Right [[(0, SLine 0)], [(1, SLine 1), (17, SLine 2)]],
      testCase "root ADR 0397 I8, I11: impossible keep-next inside a box records its relaxation" $
        fmap
          (map (\page -> (poSlots page, poUnmet page)))
          ( paginatePhysical
              settings {physicalBoxPadding = Map.singleton 5 14, physicalPitches = Map.fromList [(0, 30), (1, 30)]}
              [FBoxed 5 0 0 [FParagraph defaultKeep [line 0], FKeepNext span0 1, FParagraph defaultKeep [line 1]]]
          )
          @?= Right [([(4, SLine 0)], [UnmetKeepNext span0]), ([(4, SLine 1)], [])],
      testCase "root ADR 0397 I9, I10: a wrapped side line may carry part of its note" $
        fmap
          (map (\page -> (poSlots page, poFootnotes page)))
          ( paginatePhysical
              settings {physicalCapacity = 70, physicalMaxCapacity = 70, physicalSeparator = 10}
              [FWrapped 10 32 [] [] [longNoteLine 0]]
          )
          @?= Right
            [ ([(0, SWrapped 10), (0, SLine 0)], [(NoteId span0 0, 0, 1)]),
              ([], [(NoteId span0 0, 1, 2)])
            ],
      testCase "root ADR 0397 I11: heading rules use their actual drawn face bounds" $
        let side = RuleSide 0 0 1 True Nothing
            ruled = FRuled 5 (Just side) (Just side) False (RuleGrid 16 10) 0 (RuledHeading False 32 [line 0])
         in fmap
              (concatMap poRules)
              (paginatePhysical settings {physicalFaces = Map.singleton 0 20, physicalHeadingBounds = Map.singleton 0 (3, 23)} [ruled])
              @?= Right [PlacedRule 5 True 2, PlacedRule 5 False 23],
      testCase "root ADR 0397 I8: no-break without a preceding block is unmet" $
        fmap (concatMap poUnmet) (paginatePhysical settings [FNoBreak span0, FParagraph defaultKeep [line 0]])
          @?= Right [UnmetNoBreak span0],
      testCase "root ADR 0397 I11: a moved ruled block recalculates its rule at the new edge" $
        let side = RuleSide 0 10 1 True Nothing
            ruled = FRuled 5 (Just side) Nothing False (RuleGrid 16 10) 0 (RuledLines defaultKeep [line 1])
         in fmap
              (map (\page -> (poSlots page, poRules page)))
              (paginatePhysical settings {physicalPitches = Map.singleton 1 30} [FParagraph defaultKeep [line 0], ruled])
              @?= Right [([(0, SLine 0)], []), ([(0, SLine 1)], [PlacedRule 5 True 9])],
      testCase "root ADR 0397 I8, I11: stanza and keep-next share each box fragment" $
        fmap
          (map (\page -> (poSlots page, poBoxes page, poUnmet page)))
          ( paginatePhysical
              settings {physicalCapacity = 60, physicalMaxCapacity = 60, physicalBoxPadding = Map.singleton 5 4}
              [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[line 0, line 1], [line 2]], FKeepNext span0 1, FParagraph defaultKeep [line 3]]]
          )
          @?= Right
            [ ([(1, SLine 0), (17, SLine 1)], [BoxSegment 5 0 34], []),
              ([(1, SLine 2), (17, SLine 3)], [BoxSegment 5 0 34], [])
            ],
      testCase "root ADR 0397 I8, I11: a later keep-all paragraph remains whole in a mixed box" $
        slots
          ( paginatePhysical
              settings {physicalCapacity = 60, physicalMaxCapacity = 60, physicalBoxPadding = Map.singleton 5 4}
              [FBoxed 5 0 0 [FStanza (Keep 1 1 False) [[line 0]], FKeepNext span0 1, FParagraph (Keep 1 1 True) [line 1, line 2, line 3]]]
          )
          @?= Right [[(1, SLine 0)], [(1, SLine 1), (17, SLine 2), (33, SLine 3)]]
    ]
      <> turnedFigureTests
      <> continuedNoteOrderTests
      <> continuedTableNoteTests
      <> indexColumnNotesTests
      <> indexOnAdjustedPageTests

turnedSettings :: PhysicalSettings
turnedSettings = settings {physicalPagePitch = 10, physicalCapacity = 50, physicalMaxCapacity = 50}

pageTrace :: Either PhysicalFailure [PageOutAt Sp] -> Either PhysicalFailure [(Int, Int, [(Sp, Slotted)])]
pageTrace = fmap (map (\page -> (poNumber page, poColumn page, poSlots page)))

lines10 :: Int -> Int -> [LineBox]
lines10 from count = map line [from .. from + count - 1]

-- The turned figures of the specification (golem-driver ADR 0034 and 0039) in the free placement of root ADR 0397.
turnedFigureTests :: [TestTree]
turnedFigureTests =
  [ testCase "golem-driver ADR 0034, root ADR 0397: a turned figure after waiting figures takes a page after them in manuscript order" $
      pageTrace (paginatePhysical turnedSettings [FParagraph defaultKeep (lines10 0 4), FFigure 100 30 [] [], FFigure 101 30 [] [], FPageFigure 200 [] []])
        @?= Right
          [ (1, 0, [(0, SLine 0), (10, SLine 1), (20, SLine 2), (30, SLine 3)]),
            (2, 0, [(0, SFigure 100)]),
            (3, 0, [(0, SFigure 101)]),
            (4, 0, [(0, SPageFigure 200)])
          ],
    testCase "golem-driver ADR 0034, root ADR 0397: the text after a waiting turned figure fills the current page first" $
      pageTrace (paginatePhysical turnedSettings [FParagraph defaultKeep (lines10 0 4), FPageFigure 200 ["f"] [], FParagraph defaultKeep [line 10]])
        @?= Right
          [ (1, 0, [(0, SLine 0), (10, SLine 1), (20, SLine 2), (30, SLine 3), (40, SLine 10)]),
            (2, 0, [(0, SPageFigure 200)])
          ],
    testCase "golem-driver ADR 0034, root ADR 0397: a turned figure met on an empty page takes that page" $
      pageTrace (paginatePhysical turnedSettings [FPageFigure 200 [] [], FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SPageFigure 200)]), (2, 0, [(0, SLine 10)])],
    testCase "golem-driver ADR 0034, root ADR 0397: a figure after a waiting turned figure waits even when it fits" $
      pageTrace (paginatePhysical turnedSettings [FParagraph defaultKeep (lines10 0 2), FPageFigure 200 [] [], FFigure 60 10 [] [], FParagraph defaultKeep [line 10]])
        @?= Right
          [ (1, 0, [(0, SLine 0), (10, SLine 1), (20, SLine 10)]),
            (2, 0, [(0, SPageFigure 200)]),
            (3, 0, [(0, SFigure 60)])
          ],
    testCase "golem-driver ADR 0034, root ADR 0397: a waiting turned figure is placed before a page break" $
      pageTrace (paginatePhysical turnedSettings [FParagraph defaultKeep (lines10 0 2), FPageFigure 200 [] [], FBreak BreakPage, FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SLine 0), (10, SLine 1)]), (2, 0, [(0, SPageFigure 200)]), (3, 0, [(0, SLine 10)])],
    testCase "golem-driver ADR 0039, root ADR 0397: two or three page breaks after a waiting turned figure add no blank page" $
      forM_ [2, 3] $ \k ->
        pageTrace (paginatePhysical turnedSettings ([FParagraph defaultKeep (lines10 0 2), FPageFigure 200 [] []] <> replicate k (FBreak BreakPage) <> [FParagraph defaultKeep [line 10]]))
          @?= Right [(1, 0, [(0, SLine 0), (10, SLine 1)]), (2, 0, [(0, SPageFigure 200)]), (3, 0, [(0, SLine 10)])],
    testCase "golem-driver ADR 0039, root ADR 0397: a page break right after a turned figure met on an empty page adds no blank page" $
      pageTrace (paginatePhysical turnedSettings [FPageFigure 200 [] [], FBreak BreakPage, FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SPageFigure 200)]), (2, 0, [(0, SLine 10)])],
    testCase "golem-driver ADR 0039, root ADR 0397: a column break while a turned figure waits is a page break" $
      pageTrace (paginatePhysical turnedSettings {physicalColumns = ColumnSet 2 0 0 0} [FParagraph defaultKeep (lines10 0 2), FPageFigure 200 [] [], FBreak BreakColumn, FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SLine 0), (10, SLine 1)]), (2, 0, [(0, SPageFigure 200)]), (3, 0, [(0, SLine 10)])],
    testCase "golem-driver ADR 0039, root ADR 0397: a column break with only an unturned figure waiting goes to the next column" $
      pageTrace (paginatePhysical turnedSettings {physicalColumns = ColumnSet 2 0 0 0} [FParagraph defaultKeep (lines10 0 4), FFigure 60 30 [] [], FBreak BreakColumn, FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SLine 0), (10, SLine 1), (20, SLine 2), (30, SLine 3)]), (1, 1, [(0, SFigure 60), (30, SLine 10)])],
    testCase "golem-driver ADR 0034, root ADR 0397: a turned figure met in an empty second column waits for the next page" $
      pageTrace (paginatePhysical turnedSettings {physicalColumns = ColumnSet 2 0 0 0} [FParagraph defaultKeep (lines10 0 2), FBreak BreakColumn, FPageFigure 200 [] [], FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SLine 0), (10, SLine 1)]), (1, 1, [(0, SLine 10)]), (2, 0, [(0, SPageFigure 200)])],
    testCase "golem-driver ADR 0034, root ADR 0397: a waiting turned figure is placed before a column switch" $
      pageTrace (paginatePhysical turnedSettings [FParagraph defaultKeep (lines10 0 2), FPageFigure 200 [] [], FSwitchColumns (ColumnSet 2 0 0 0), FParagraph defaultKeep [line 10]])
        @?= Right [(1, 0, [(0, SLine 0), (10, SLine 1)]), (2, 0, [(0, SPageFigure 200)]), (3, 0, [(0, SLine 10)])],
    testCase "golem-driver ADR 0034, root ADR 0397: a waiting turned figure is placed before a recto heading" $
      fmap
        (map (\page -> (poNumber page, poBlank page, poSlots page)))
        (paginatePhysical turnedSettings [FParagraph defaultKeep (lines10 0 2), FPageFigure 200 [] [], FParagraph defaultKeep [line 10], FHeading 1 True 10 [line 20]])
        @?= Right
          [ (1, False, [(0, SLine 0), (10, SLine 1), (20, SLine 10)]),
            (2, False, [(0, SPageFigure 200)]),
            (3, False, [(0, SHeading 20 1)])
          ],
    testCase "golem-driver ADR 0034, root ADR 0397: a footnote continued from the page before skips the page of a turned figure" $
      fmap
        (map (\page -> (poNumber page, poSlots page, poFootnotes page)))
        (paginatePhysical turnedSettings [FParagraph defaultKeep [LineBox 0 [NoteBody (NoteId span0 0) 6] [] [] 0], FPageFigure 200 [] [], FParagraph defaultKeep [line 10, line 11]])
        @?= Right
          [ (1, [(0, SLine 0)], [(NoteId span0 0, 0, 4)]),
            (2, [(0, SPageFigure 200)], []),
            (3, [(0, SLine 10), (10, SLine 11)], [(NoteId span0 0, 4, 2)])
          ]
  ]

-- | Laid out freely, the footnotes keep the order written while one continues (root ADR 0444).
continuedNoteOrderTests :: [TestTree]
continuedNoteOrderTests =
  [ testCase "root ADR 0444 I1: freely, page-lines +2 puts the rest of note 500 on page 1, and line 10 with note 510 on page 2" $ do
      ps <- either (assertFailure . show) pure (continued 2 5 (Just 1) 0)
      [i | (_, i, _, _) <- noteParts ps] @?= [note500, note510]
      [(n, from, len) | (n, i, from, len) <- noteParts ps, i == note500] @?= [(1, 0, 5)]
      pageOfLine 10 ps @?= [2],
    testCase "root ADR 0444 I1, I2: freely, page-lines +1 puts one more line of note 500 on page 1, and the rest before note 510 on page 2" $ do
      ps <- either (assertFailure . show) pure (continued 1 5 (Just 1) 0)
      [(n, i) | (n, i, _, _) <- noteParts ps] @?= [(1, note500), (2, note500), (2, note510)]
      pageOfLine 10 ps @?= [2],
    testCase "root ADR 0444 I1, I2, I4: freely, whatever the page-lines and the notes, the notes keep the order written and every line is placed once in order" $
      forM_ [(k, len, second, more) | k <- [0 .. 5], len <- [1 .. 8], second <- [Nothing, Just 1, Just 2], more <- [0 .. 2]] $ \(k, len, second, more) ->
        case continued k len second more of
          Left failure -> assertFailure (show (k, len, second, more, failure))
          Right ps -> do
            let order = [i | (_, i, _, _) <- noteParts ps]
                what = show (k, len, second, more, noteParts ps, map poSlots ps)
            assertBool ("I1 " <> what) (note500 `notElem` dropWhile (/= note510) order)
            [i | p <- ps, (_, SLine i) <- poSlots p] @?= [0, 10] <> take more [20 ..]
  ]
  where
    note500 = NoteId (mkSpan (FileId 0) 500 501) 0
    note510 = NoteId (mkSpan (FileId 0) 510 511) 0
    -- a column of 50 sp that may grow to 90, a pitch of 10 and a separator of 10, as the grid tests of root ADR 0444
    cfg = settings {physicalPagePitch = 10, physicalFontSize = 10, physicalCapacity = 50, physicalMaxCapacity = 90, physicalSeparator = 10}
    continued :: Int -> Int -> Maybe Int -> Int -> Either PhysicalFailure [PageOutAt Sp]
    continued k len second more =
      paginatePhysical cfg $
        [FParagraph defaultKeep [LineBox 0 [NoteBody note500 len] [] [] 0]]
          <> [FAdjustLines span0 k | k /= 0]
          <> [FParagraph defaultKeep [LineBox 10 [NoteBody note510 n | Just n <- [second]] [] [] 0]]
          <> [FParagraph defaultKeep (map line [20 .. 20 + more - 1]) | more > 0]
    noteParts ps = [(poNumber p, i, from, n) | p <- ps, (i, from, n) <- poFootnotes p]
    pageOfLine j ps = [poNumber p | p <- ps, (_, SLine i) <- poSlots p, i == j]

{- | root ADR 0444 I1 and I4, laid out freely, for the rows of a table,
which place their marks even when no line of their notes fits and add
those notes after the continued note.
-}
continuedTableNoteTests :: [TestTree]
continuedTableNoteTests =
  [ testCase "root ADR 0444 I1, I4: freely, a table row after a continued note, whatever the page-lines and the notes, puts its note after the continued one, and every line is placed once in order" $
      forM_ [(k, len, second, third) | k <- [0 .. 4], len <- [1 .. 8], second <- [Nothing, Just 1, Just 2], third <- [Nothing, Just 1]] $ \(k, len, second, third) ->
        case paginatePhysical cfg (flows k len second third) of
          Left failure -> assertFailure (show (k, len, second, third, failure))
          Right ps -> do
            let order = [i | p <- ps, (i, _, _) <- poFootnotes p]
                what = show (k, len, second, third, [(poNumber p, poSlots p, poFootnotes p) | p <- ps])
                later = dropWhile (/= note510) order
            assertBool ("I1 " <> what) (note500 `notElem` later && note500 `notElem` dropWhile (/= note520) order)
            assertBool ("I1 " <> what) (note510 `notElem` dropWhile (/= note520) order)
            assertEqual ("I4 " <> what) [0, 10, 11] [i | p <- ps, (_, SLine i) <- poSlots p]
  ]
  where
    note500 = NoteId (mkSpan (FileId 0) 500 501) 0
    note510 = NoteId (mkSpan (FileId 0) 510 511) 0
    note520 = NoteId (mkSpan (FileId 0) 520 521) 0
    cfg = settings {physicalPagePitch = 10, physicalFontSize = 10, physicalCapacity = 50, physicalMaxCapacity = 90, physicalSeparator = 10}
    notesOf ident = maybe [] (\n -> [NoteBody ident n])
    flows k len second third =
      [FParagraph defaultKeep [LineBox 0 [NoteBody note500 len] [] [] 0]]
        <> [FAdjustLines span0 k | k /= 0]
        <> [FTable 1 0 [] [[LineBox 10 (notesOf note510 second) [] [] 0], [LineBox 11 (notesOf note520 third) [] [] 0]] [] False]

{- | Laid out freely, every index column on the page of the switch divides
the lines left after the footnotes of the page (root ADR 0025).
-}
indexColumnNotesTests :: [TestTree]
indexColumnNotesTests =
  [ testCase "root ADR 0025: freely, two lines and a note of two, both index columns end before the note" $
      fmap (entriesOn 1) (switchPage 2 2) @?= Right (tens 2 6 <> tens 2 6),
    testCase "root ADR 0025: freely, without a note, both index columns take the rest of the type area" $
      fmap (entriesOn 1) (switchPage 2 0) @?= Right (tens 2 9 <> tens 2 5),
    testCase "root ADR 0025: freely, whatever the lines and the note, no index line on the page of the switch reaches its footnotes" $
      forM_ [(n, m) | n <- [1 .. 8], m <- [0 .. 3]] $ \(n, m) -> case switchPage n m of
        Left failure -> assertFailure (show failure)
        Right pages -> forM_ [p | p <- pages, poNumber p == 1, csColumns (poColumnSet p) == 1] $ \body -> do
          let notes = sum [c | (_, _, c) <- poFootnotes body]
              noteStart = poLines body - (if notes == 0 then 0 else 10 + fromIntegral notes * 10)
          assertBool (show (n, m, noteStart, entriesOn 1 pages)) (all (\at -> at + 10 <= noteStart) (entriesOn 1 pages))
  ]
  where
    cfg = settings {physicalPagePitch = 10, physicalFontSize = 10, physicalCapacity = 100, physicalMaxCapacity = 200, physicalSeparator = 10}
    switchPage :: Int -> Int -> Either PhysicalFailure [PageOutAt Sp]
    switchPage n m =
      let first = if m > 0 then LineBox 0 [NoteBody (NoteId span0 0) m] [] [] 0 else line 0
       in paginatePhysical cfg ([FParagraph defaultKeep (first : map line [1 .. n - 1]), FSwitchColumns (ColumnSet 2 0 0 0)] <> [FParagraph defaultKeep [line (100 + i)] | i <- [0 .. 11]] <> [FRestoreColumns])
    -- the starts of the entries on a page, column by column
    entriesOn page pages = [at | p <- pages, poNumber p == page, (at, SLine i) <- poSlots p, i >= 100]
    -- the lines a to b of pitch 10
    tens :: Int -> Int -> [Sp]
    tens a b = [fromIntegral (10 * i) | i <- [a .. b]]

-- | The index columns on the page of the switch, laid out freely, end before the footnotes of the column before it (root ADR 0441).
indexOnAdjustedPageTests :: [TestTree]
indexOnAdjustedPageTests =
  [ testCase "root ADR 0441 I1, I2: freely, page-lines -3, two lines and a note of two, the index takes lines 2 and 3 only" $
      fmap (indexAt 1) (switchPage (-3) 2 2) @?= Right [20, 30, 20, 30],
    testCase "root ADR 0441 I2: freely, page-lines -3, two lines and no note, the index takes lines 2 to 6" $
      fmap (indexAt 1) (switchPage (-3) 2 0) @?= Right (tens 2 6 <> tens 2 6),
    testCase "root ADR 0441 I3: freely, page-lines -3, four lines and a note of two leave no line, the index starts on the next page" $
      fmap (indexAt 1) (switchPage (-3) 4 2) @?= Right [],
    testCase "root ADR 0441 I1, I2: freely, page-lines +3, two lines and a note of two, the index takes lines 2 to 9" $
      fmap (indexAt 1) (switchPage 3 2 2) @?= Right (tens 2 9 <> tens 2 5),
    testCase "root ADR 0441 I1, I4: freely, no page-lines, two lines and a note of two, the index takes lines 2 to 6" $
      fmap (indexAt 1) (switchPage 0 2 2) @?= Right (tens 2 6 <> tens 2 6),
    testCase "root ADR 0441 I1, I2, I3: freely, whatever the page-lines, the lines and the note, the index on the page of the switch ends before the note and the type area" $
      forM_ [(k, n, m) | k <- [-4 .. 4], n <- [1 .. 7], m <- [0 .. 3]] $ \(k, n, m) -> case switchPage k n m of
        Left failure -> assertFailure (show failure)
        Right pages -> case [p | p <- pages, poNumber p == 1, csColumns (poColumnSet p) == 1] of
          body : _ -> do
            let notes = sum [c | (_, _, c) <- poFootnotes body]
                noteLength = if notes == 0 then 0 else 10 + fromIntegral notes * 10
                end = min 100 (poLines body - noteLength)
                used = maximum (0 : [at + 10 | (at, SLine _) <- poSlots body])
                rows = indexAt 1 pages
                label = show (k, n, m, end, rows)
            assertBool ("I1, I2 " <> label) (all (\at -> at + 10 <= end) rows)
            when (used >= end) $ assertBool ("I3 " <> label) (null rows)
          [] -> assertFailure "no column of the body on page 1"
  ]
  where
    cfg = settings {physicalPagePitch = 10, physicalFontSize = 10, physicalCapacity = 100, physicalMaxCapacity = 200, physicalSeparator = 10}
    index2 = ColumnSet 2 0 0 0
    switchPage :: Int -> Int -> Int -> Either PhysicalFailure [PageOutAt Sp]
    switchPage k n m =
      let first = if m > 0 then LineBox 0 [NoteBody (NoteId span0 0) m] [] [] 0 else line 0
          adjust = [FAdjustLines span0 k | k /= 0]
       in paginatePhysical cfg (adjust <> [FParagraph defaultKeep (first : map line [1 .. n - 1]), FSwitchColumns index2] <> [FParagraph defaultKeep [line (100 + i)] | i <- [0 .. 11]] <> [FRestoreColumns])
    -- the lines a to b of pitch 10
    tens :: Int -> Int -> [Sp]
    tens a b = [fromIntegral (10 * i) | i <- [a .. b]]
    -- the starts of the entries on a page, column by column
    indexAt page pages = [at | p <- pages, poNumber p == page, (at, SLine i) <- poSlots p, i >= 100]
