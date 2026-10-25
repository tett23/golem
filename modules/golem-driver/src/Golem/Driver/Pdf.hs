{- | The PDF pipeline (golem-driver ADR 0002): page geometry, fonts,
composition and line breaking per paragraph (optionally in parallel),
pagination with page references resolved to a fixed point (S2), font
subsetting and the PDF/X-4 writer.

Fonts come from a 'FontProvider'. The real provider is golem-font
(HarfBuzz and FreeType, golem-font ADR 0001 and 0002), which is not
implemented yet; 'noFontProvider' reports that.
-}
module Golem.Driver.Pdf
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
    listBullets,
    textBullets,
    usedRoles,
    bookHasCode,
    codeStyles,
    codeFontNotice,
    kentenRubyNotices,
    syntheticStroke,
    headingDefaults,
    syntheticStrokeJa,
    syntheticStrokeLatin,
    styleFileId,
    PdfInput (..),
    SetLine (..),
    CodeInfo (..),
    PlacedFigure (..),
    PlacedSidenote (..),
    PdfLayout (..),
    TableGeometry (..),
    styleLayoutDiagnostics,
    listNumberDiagnostics,
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
    runningMetadata,
    hiddenFolios,
    figureRect,
    fitFigure,
    renderPdf,
    renderPdfView,
    flowLines,
    pdfFileName,
    instanceIdInputs,
    producer,
  )
where

import Golem.Driver.Pdf.Draw
import Golem.Driver.Pdf.Flow
import Golem.Driver.Pdf.Fonts
import Golem.Driver.TextLayer (ClusterPart (..))
