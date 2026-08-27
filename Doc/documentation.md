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

Content flows onto additional PDF pages automatically. PDFMercury avoids splitting text lines and ordinary table rows where they fit on a page. For a normal-flow table with a `<thead>`, the header is repeated when the table continues on another page.

An individual row taller than the available page height must be split. Parallel tables with independent vertical row grids, `rowspan` pagination, tables wider than the page, named `@page` rules, running headers and footers, and CSS page counters are not part of version 0.1.0.

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
