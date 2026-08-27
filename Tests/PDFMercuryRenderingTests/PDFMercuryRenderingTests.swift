import CoreGraphics
import Foundation
import PDFMercury
import Testing

@Suite("HTML and CSS PDF rendering")
struct PDFMercuryRenderingTests {
  @Test("renders inline HTML with inline CSS")
  func rendersInlineHTMLAndCSS() async throws {
    let html = HTMLSource.string(
      try fixtureString("inline-card.html")
    )
    let stylesheets: [CSSSource] = [
      .string(try fixtureString("inline-card.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(pdf, as: "01-inline-html-css.pdf")
  }

  @Test("renders HTML and CSS files with relative assets")
  func rendersFilesWithRelativeAssets() async throws {
    let html = HTMLSource.file(try fixtureURL("company-profile.html"))
    let stylesheets: [CSSSource] = [
      .file(try fixtureURL("company-profile.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(pdf, as: "02-file-html-css-assets.pdf")
  }

  @Test("resolves a local image relative to the HTML base URL")
  func resolvesLocalAssetFromBaseURL() async throws {
    let fixtures = try fixturesDirectory()
    let html = HTMLSource.string(
      try fixtureString("company-profile.html"),
      baseURL: fixtures
    )
    let stylesheets: [CSSSource] = [
      .string(try fixtureString("company-profile.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(pdf, as: "03-html-base-url-local-asset.pdf")
  }

  @Test("paginates HTML into multiple PDF pages")
  func paginatesHTML() async throws {
    let html = HTMLSource.string(
      try fixtureString("pagination.html")
    )
    let stylesheets: [CSSSource] = [
      .string(try fixtureString("pagination.css"))
    ]

    let pdf = try await RenderEngine().render(
      html: html,
      stylesheets: stylesheets
    )

    try verifyAndArchive(pdf, as: "04-pagination.pdf", expectedPageCount: 3)
  }

  private func verifyAndArchive(
    _ pdf: Data,
    as filename: String,
    expectedPageCount: Int? = nil
  ) throws {
    let outputDirectory = repositoryRoot()
      .appendingPathComponent(".build/pdfmercury-visual-input", isDirectory: true)
    try FileManager.default.createDirectory(
      at: outputDirectory,
      withIntermediateDirectories: true
    )

    let outputURL = outputDirectory.appendingPathComponent(filename)
    try pdf.write(to: outputURL, options: .atomic)

    let document = try #require(CGPDFDocument(outputURL as CFURL))
    #expect(document.numberOfPages > 0)
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
}
