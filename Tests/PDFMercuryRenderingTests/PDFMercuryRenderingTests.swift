import CoreGraphics
import Foundation
import PDFKit
import PDFMercury
import Testing

@Suite("Visual HTML and CSS rendering")
@MainActor
struct PDFMercuryRenderingTests {
  @Test("expected: renders one solid portrait page")
  func rendersSolidPortraitPage() async throws {
    let html = HTMLSource.string(try fixtureString("solid-portrait.html"))
    let stylesheets: [CSSSource] = [
      .string(try fixtureString("solid-portrait.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(pdf, as: "01-expected-portrait.pdf")
  }

  @Test("expected: renders one solid landscape page")
  func rendersSolidLandscapePage() async throws {
    let html = HTMLSource.file(try fixtureURL("solid-landscape.html"))
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("solid-landscape.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(pdf, as: "02-expected-landscape.pdf")
  }

  @Test("expected: renders exactly three explicit pages")
  func rendersMultiPageLoremIpsumDocument() async throws {
    let html = HTMLSource.file(try fixtureURL("lorem-ipsum-multipage.html"))
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("lorem-ipsum-multipage.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(
      pdf,
      as: "03-expected-3-explicit-pages.pdf",
      expectedPageCount: 3
    )
  }

  @Test("expected: renders natural flow without page padding")
  func rendersNaturallyFlowingTextAcrossPages() async throws {
    let html = HTMLSource.file(try fixtureURL("flowing-lorem-ipsum.html"))
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("flowing-lorem-ipsum.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(
      pdf,
      as: "04-expected-no-page-padding.pdf",
      minimumPageCount: 2
    )
  }

  @Test("expected: applies page padding and keeps text lines intact")
  func rendersNaturallyFlowingTextWithPagePadding() async throws {
    let html = HTMLSource.file(try fixtureURL("flowing-lorem-ipsum.html"))
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("flowing-lorem-ipsum.css")),
      .file(try fixtureURL("flowing-lorem-ipsum-page-padding.css")),
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(
      pdf,
      as: "05-expected-padding-and-intact-lines.pdf",
      minimumPageCount: 2
    )
  }

  @Test("expected: resolves local HTML and CSS file assets")
  func rendersLocalRuntimeAssets() async throws {
    let html = HTMLSource.string(
      try fixtureString("runtime-local-assets.html"),
      baseURL: try fixturesDirectory()
    )
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("runtime-assets/document.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(
      pdf,
      as: "06-expected-local-runtime-assets.pdf",
      expectedPageCount: 1
    )
  }

  @Test("expected: repeats table headers and keeps rows intact across pages")
  func rendersTableAcrossPagesWithRepeatedHeadersAndIntactRows() async throws {
    let html = HTMLSource.file(try fixtureURL("flowing-table.html"))
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("flowing-table.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(
      pdf,
      as: "07-expected-repeated-table-headers-and-intact-rows.pdf",
      minimumPageCount: 2
    )
    try expectTextsOnSamePage(
      in: pdf,
      first: "ROW 04 START",
      second: "ROW 04 END"
    )
    try expectText(
      "POSITION",
      onEveryPageContaining: "ROW",
      in: pdf
    )
  }

  private func verifyAndArchive(
    _ pdf: Data,
    as filename: String,
    expectedPageCount: Int? = nil,
    minimumPageCount: Int = 1
  ) throws {
    let outputDirectory = visualOutputDirectory()
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )

    let outputURL = outputDirectory.appendingPathComponent(filename)
    try pdf.write(to: outputURL, options: .atomic)

    let document = try #require(CGPDFDocument(outputURL as CFURL))
    #expect(document.numberOfPages >= minimumPageCount)
    if let expectedPageCount {
      #expect(document.numberOfPages == expectedPageCount)
    }
  }

  private func fixturesDirectory() throws -> URL {
    try #require(Bundle.module.resourceURL)
      .appendingPathComponent("Fixtures", isDirectory: true)
  }

  private func fixtureURL(_ filename: String) throws -> URL {
    let url = try fixturesDirectory().appendingPathComponent(filename)
    return try #require(
      FileManager.default.fileExists(atPath: url.path) ? url : nil,
      "Missing fixture: \(filename)"
    )
  }

  private func fixtureString(_ filename: String) throws -> String {
    try String(contentsOf: fixtureURL(filename), encoding: .utf8)
  }

  private func expectTextsOnSamePage(
    in pdf: Data,
    first: String,
    second: String
  ) throws {
    let document = try #require(PDFDocument(data: pdf))
    let pageTexts = (0..<document.pageCount).map {
      document.page(at: $0)?.string ?? ""
    }
    let firstPage = try #require(pageTexts.firstIndex { $0.contains(first) })
    let secondPage = try #require(pageTexts.firstIndex { $0.contains(second) })
    #expect(firstPage == secondPage)
  }

  private func expectText(
    _ expectedText: String,
    onEveryPageContaining pageMarker: String,
    in pdf: Data
  ) throws {
    let document = try #require(PDFDocument(data: pdf))
    let relevantPageTexts = (0..<document.pageCount)
      .compactMap { document.page(at: $0)?.string }
      .filter { $0.contains(pageMarker) }
    let normalizedExpectedText = expectedText.filter { !$0.isWhitespace }

    #expect(!relevantPageTexts.isEmpty)
    for pageText in relevantPageTexts {
      let normalizedPageText = pageText.filter { !$0.isWhitespace }
      #expect(normalizedPageText.contains(normalizedExpectedText))
    }
  }

  private func repositoryRoot() -> URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func visualOutputDirectory() -> URL {
    #if os(iOS)
      return FileManager.default.temporaryDirectory
        .appendingPathComponent("pdfmercury-visual-input", isDirectory: true)
    #else
      if let configuredPath = ProcessInfo.processInfo.environment[
        "PDFMERCURY_VISUAL_INPUT_DIRECTORY"
      ] {
        return URL(fileURLWithPath: configuredPath, isDirectory: true)
      }

      return repositoryRoot()
        .appendingPathComponent(".build/pdfmercury-visual-input", isDirectory: true)
    #endif
  }
}
