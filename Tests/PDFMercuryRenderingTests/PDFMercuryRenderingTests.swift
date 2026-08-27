import CoreGraphics
import Foundation
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

  @Test("expected: applies page padding on every page")
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
      as: "05-expected-padding-on-every-page.pdf",
      minimumPageCount: 2
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
