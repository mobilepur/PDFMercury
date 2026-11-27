# Release Notes

**Unreleased**
- Render CSS at its physical size, as a browser prints it: one CSS pixel is 0.75 pt, `@page` margins in `mm`, `cm`, `in` and `pt` keep their length. Earlier versions laid out one CSS pixel as one PDF point, so documents came out a third too large and the page held a third less content.
- Every document changes size. Stylesheets tuned for the old scale keep their look if their `px` lengths are written as `pt`.

**0.2.0** - 2026-09-22
- Add optional running page footers with page-number and page-count placeholders, measured space reservation, and overflow validation.
- Keep fitting blocks together at page boundaries and preserve text and repeated table headers when oversized content spans pages.
- Move document preparation, pagination and PDF composition to a background queue; reuse an exclusive WebKit session across renders.
- Propagate cancellation through queued work and navigation, discarding interrupted sessions before the next render.
- Existing render calls can omit the new `pageFooter` argument. Explicit references to the old two-argument method must use the new full method signature or a forwarding closure.
- WebKit stays on the main actor; initial WebKit startup can still pause the UI.

**0.1.0** - 2026-08-27
- Initial release
