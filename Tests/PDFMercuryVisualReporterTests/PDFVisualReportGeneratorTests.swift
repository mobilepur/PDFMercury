import CoreGraphics
import Foundation
import Testing

@testable import PDFMercuryVisualReporter

@Suite("PDF visual report generator")
struct PDFVisualReportGeneratorTests {
  @Test("creates the first versioned report name")
  func createsFirstVersionedReportName() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = try PDFVisualReportArchive().nextReportURL(
      in: directory,
      packageVersion: "0.1.0"
    )

    #expect(url.lastPathComponent == "report-0.1.0-0001.pdf")
  }

  @Test("increments the highest report number for the package version")
  func incrementsHighestReportNumber() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    for filename in [
      "report-0.1.0-0001.pdf",
      "report-0.1.0-0003.pdf",
      "report-0.2.0-0042.pdf",
      "notes.pdf",
    ] {
      try Data().write(to: directory.appendingPathComponent(filename))
    }

    let url = try PDFVisualReportArchive().nextReportURL(
      in: directory,
      packageVersion: "0.1.0"
    )

    #expect(url.lastPathComponent == "report-0.1.0-0004.pdf")
  }

  @Test("rejects package versions that could escape the archive directory")
  func rejectsUnsafePackageVersion() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    #expect(throws: PDFVisualReportArchiveError.invalidPackageVersion("../0.1.0")) {
      try PDFVisualReportArchive().nextReportURL(
        in: directory,
        packageVersion: "../0.1.0"
      )
    }
  }

  @Test("requires at least one PDF page")
  func requiresAtLeastOnePDFPage() throws {
    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("Report.pdf")

    #expect(throws: PDFVisualReportError.noPages) {
      try PDFVisualReportGenerator().generate(from: [], to: outputURL)
    }
  }

  @Test("rejects unreadable PDF input")
  func rejectsUnreadablePDFInput() throws {
    let temporaryDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

    let invalidPDFURL = temporaryDirectory.appendingPathComponent("invalid.pdf")
    try Data("not a PDF".utf8).write(to: invalidPDFURL)
    let outputURL = temporaryDirectory.appendingPathComponent("Report.pdf")

    #expect(throws: PDFVisualReportError.invalidPDF(invalidPDFURL)) {
      try PDFVisualReportGenerator().generate(from: [invalidPDFURL], to: outputURL)
    }
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
