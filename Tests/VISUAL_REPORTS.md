# Visual PDF reports

`PDFMercuryVisualReporter` builds an A4 landscape contact sheet from rendered PDF files. Each report page contains up to eight source pages in a 4-by-2 grid of square cells. Every PDF page is scaled to fit its cell without changing its effective portrait or landscape orientation. Every preview is labeled with its source filename and page number.

Render the PDFs for the scenarios under review into a directory, then run the complete test and report workflow:

```sh
Scripts/run-visual-tests.sh \
  --package-version 0.1.0 \
  .build/pdfmercury-visual-input
```

The script runs the Swift test suite before it creates the visual report. Reports are archived under `output/pdf/reports` with incrementing names such as `report-0.1.0-0001.pdf`. Existing reports are never selected as the next output. When no input is supplied, the script reads PDFs from `.build/pdfmercury-visual-input`.

The underlying command accepts any combination of PDF files and directories. Directory inputs are non-recursive. Source files and pages are ordered by their human-readable filenames. An explicit `--output` path remains available when automatic versioning is not wanted.

Open the report on macOS with:

```sh
open output/pdf/reports/report-0.1.0-0001.pdf
```

The contact sheet is intended for quick visual review. Keep the original rendered PDFs available when a page needs to be inspected at full size.
