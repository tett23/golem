{- | The PDF pipeline (golem-driver ADR 0002): page geometry, fonts,
composition and line breaking per paragraph (optionally in parallel),
pagination with page references resolved to a fixed point (S2), font
subsetting and the PDF/X-4 writer.

Fonts come from a 'FontProvider'. The real provider is golem-font
(HarfBuzz and FreeType, golem-font ADR 0001 and 0002), which is not
implemented yet; 'noFontProvider' reports that.
-}
module Golem.Typeset
  ( FontProvider (..),
    LoadedFonts (..),
    Shaped (..),
    ClusterPart (..),
    GlyphFrame (..),
    offsetOrigin,
    Shaping (..),
    shapingOf,
    noFontProvider,
    bodyRole,
    bodyFontDiagnostics,
    usedRoles,
    bookHasCode,
    codeStyles,
    codeFontNotice,
    kentenRubyNotices,
    syntheticStroke,
    headingDefaults,
    syntheticStrokeJa,
    syntheticStrokeLatin,
    PdfInput (..),
    SetLine (..),
    CodeInfo (..),
    PlacedFigure (..),
    PlacedSidenote (..),
    PdfLayout (..),
    TableGeometry (..),
    styleLayoutDiagnostics,
    noteNumberDiagnostics,
    layoutPdf,
    layoutPages,
    indexLines,
    bibliographyLines,
    pdfXPeople,
    Assumed (..),
    fixpoint,
    labelSpans,
    TocGeometry (..),
    TocPage (..),
    tocPage,
    numberedTitle,
    runningHeadLines,
    runningHeads,
    hiddenFolios,
    figureRect,
    fitFigure,
    renderPdf,
    renderPdfView,
    renderPdfStructure,
    flowLines,
    pdfFileName,
    instanceIdInputs,
    producer,
  )
where

import Golem.Typeset.Draw
import Golem.Typeset.Flow
import Golem.Typeset.Fonts
import Golem.Typeset.TextLayer (ClusterPart (..))
