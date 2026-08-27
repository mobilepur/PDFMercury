# Development log

## Unreleased - Release preparation and repeated table headers

Table headers are repeated when a normal-flow table continues on a later PDF page while preserving intact rows. The package documentation, release notes, installation example, and CI verification are prepared for version 0.1.0.

## `2e51fd4` - Keep table rows intact across PDF pages

The paginator now treats table rows as protected vertical ranges and moves page boundaries before rows that fit. A visual fixture verifies that a long table continues across pages without cutting its rows.

## `74e9da3` - Resolve local HTML and CSS assets

Local HTML `src` references and CSS `url(...)` references are embedded relative to their source directories. Runtime fixtures verify local logos and stylesheet-relative SVG assets while preserving vector output.

## `b014fd7` - Keep text lines intact across PDF pages

The renderer measures text line rectangles and moves page boundaries away from intersecting lines. This prevents duplicated or visibly clipped text at page transitions.

## `3679a03` - Add page margins to HTML rendering

CSS `@page` declarations now control A4 orientation and page margins. Natural-flow fixtures cover documents with and without page padding across multiple pages.

## `b03b769` - Add HTML rendering and visual PDF tests

The first public rendering API loads HTML and CSS into WebKit and creates portrait, landscape, and multi-page PDFs. The visual suite was reshaped around reusable fixture files and deterministic report inputs.

## `db204f7` - Add visual PDF test infrastructure

A reporter CLI and archive create versioned A4 contact sheets from source PDFs. Tests and a runner script establish the manual visual-review workflow and deterministic report numbering.

## `e4e8d13` - Initialize Swift package

The Swift package foundation, public library product, platform requirements, CI skeleton, README, MIT license, and ignore rules were added. This established the repository structure used by all later rendering work.

## `555c5d3` - Initial commit

The repository history was created. No project files were introduced in this baseline commit.
