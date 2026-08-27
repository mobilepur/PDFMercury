# Release notes

## 0.1.0 - Initial release

PDFMercury 0.1.0 provides the first public HTML-to-PDF rendering API for iOS, macOS, and Mac Catalyst.

### Included

- Public `RenderEngine`, `HTMLSource`, `CSSSource`, and `PDFMercuryError` APIs.
- HTML and multiple CSS inputs from strings or local files.
- Local HTML and CSS assets, including SVG images and fonts.
- Vector-based A4 portrait and landscape output.
- Automatic multi-page content flow and CSS `@page` margins.
- Text-line-aware pagination.
- Multi-page tables with intact rows and repeated `<thead>` content.
- A versioned visual PDF report workflow for manual rendering review.

### Known limitations

- Page size is currently limited to A4.
- `@page` support covers orientation and margins, not the complete paged-media specification.
- Rows taller than one available page must be split.
- Parallel independently paginated tables, `rowspan` pagination, and over-wide tables are not supported explicitly.
- Local CSS `@import`, HTML `srcset`, and complex URL query or fragment variants are not embedded yet.
- Rendering uses WebKit on the main actor and should receive trusted HTML and CSS.
