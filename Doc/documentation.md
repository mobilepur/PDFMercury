# PDFMercury documentation

PDFMercury renders HTML and CSS with `WKWebView` and returns the resulting PDF as `Data`. Rendering runs on the main actor.

## Public API

```swift
let pdf = try await RenderEngine().render(
  html: htmlSource,
  stylesheets: cssSources
)
```

### HTML sources

- `HTMLSource.string(_:baseURL:)` renders an in-memory HTML string. Set `baseURL` to a local directory when the HTML references files such as `<img src="logo.svg">`.
- `HTMLSource.file(_:)` reads an HTML file and uses its containing directory as the base URL.

### CSS sources

- `CSSSource.string(_:)` injects an in-memory stylesheet.
- `CSSSource.file(_:)` reads and injects a stylesheet. Relative `url(...)` assets resolve against the stylesheet's directory.

Multiple stylesheets are applied in the order supplied. Local HTML `src` assets and CSS `url(...)` assets are embedded as data URLs before WebKit renders the document.

## Page layout

PDFMercury currently creates A4 pages. Use a CSS `@page` rule in a `CSSSource` passed through the `stylesheets` argument to select portrait or landscape orientation and page margins:

```css
@page {
  size: A4 landscape;
  margin: 18mm 14mm;
}
```

Supported margin units are `px`, `pt`, `in`, `cm`, and `mm`. The `margin` shorthand and the four individual `margin-*` properties are supported.

An `@page` rule inside an HTML `<style>` element is rendered by WebKit but is not used by PDFMercury to calculate the PDF page rectangle in version 0.1.0.

## Pagination

Content flows onto additional PDF pages automatically. PDFMercury avoids splitting text lines and ordinary table rows where they fit on a page. Normal-flow blocks with computed `break-inside: avoid`, `break-inside: avoid-page`, or legacy `page-break-inside: avoid` are also kept together when they fit in the available page area. This is useful for invoice totals and final payment details; use flowing content rather than fixed heights or absolute positioning for these blocks.

For a normal-flow table with a `<thead>`, the header is repeated when the table continues on another page, including continuations within an oversized row. Its height is reserved from that page's content area. A header as tall as the page content area is not repeated.

A block or row taller than the available page height must be split. Its text lines and smaller keep-together blocks are still protected where they fit, so an oversized container does not force a cut through an otherwise avoidable text line. If even an individual line is taller than the available area, splitting is unavoidable. Parallel tables with independent vertical row grids, `rowspan` pagination, tables wider than the page, named `@page` rules, running headers, and CSS page counters are not supported.

### Optional running footer (local development)

Pass a `PageFooter` to repeat an explicitly identified HTML element on every page:

```swift
let pdf = try await RenderEngine().render(
  html: .string("""
    <html><body>
      <main>Document content</main>
      <footer id="page-footer">
        Company · Bank details
        Page <span data-pdf-page-number></span> of <span data-pdf-page-count></span>
      </footer>
    </body></html>
    """),
  stylesheets: [.string("@page { size: A4; margin: 48pt; }")],
  pageFooter: PageFooter(elementID: "page-footer", gap: 12)
)
```

The element must have a unique, nonempty ID and be a visible, normal-flow direct child of `<body>`. The renderer removes it from the body flow and renders it at the bottom of the content area, **inside** the configured page margins. Its measured height and the gap (PDF points, default 12) are reserved before splitting body content or repeating table headers. Short final pages use the same bottom alignment. Counter text is measured with the actual page count; varying heights reserve the largest measured footer to prevent overlap.

Footer rendering preserves the document's stylesheets, HTML/body attributes, horizontal body insets and inherited typography. It uses a separate document containing only the footer, so use selectors that do not depend on body siblings, viewport height, or JavaScript. Vertical body layout dimensions, padding, margins and borders are reset there, and the footer's outer margin is zeroed; use `gap` for separation and footer padding for internal spacing. Keep the footer in normal flow without fixed/absolute positioning, fixed heights that clip content, or overflow. Counter placeholders are replaced with decimal text. The consumer owns wording such as “Page” or “Seite”.

Missing, duplicate, hidden, overflowing or oversized footers, invalid gaps, and layouts whose height does not stabilize throw `PDFMercuryError.invalidPageFooter`. Omitting `pageFooter` preserves the existing behavior: an ordinary HTML footer remains in document flow and appears once. This additive API is currently local development work and has not been released.

## Assets and output

HTML, text, CSS shapes, fonts, and SVG assets remain vector content when WebKit emits them as vectors. Raster source images remain raster images in the PDF.

The local asset resolver supports common image and font formats. CSS `@import`, HTML `srcset`, and complex URL query or fragment variants are not yet resolved as local embedded assets.

Only render trusted HTML and CSS. PDFMercury does not sanitize markup or provide a security boundary for scripts and remote resources loaded by WebKit.

## Visual tests

Run the complete rendering suite and create a visual contact sheet with:

```sh
Scripts/run-visual-tests.sh --package-version 0.1.0
```

The generated report opens automatically on macOS. See [Visual PDF reports](../Tests/VISUAL_REPORTS.md) for details.
