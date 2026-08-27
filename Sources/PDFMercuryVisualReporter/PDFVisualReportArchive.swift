import Foundation

public struct PDFVisualReportArchive: Sendable {
  public init() {}

  public func nextReportURL(in directory: URL, packageVersion: String) throws -> URL {
    guard Self.isValid(packageVersion: packageVersion) else {
      throw PDFVisualReportArchiveError.invalidPackageVersion(packageVersion)
    }

    let prefix = "report-\(packageVersion)-"
    let filenames: [String]
    if FileManager.default.fileExists(atPath: directory.path) {
      filenames = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    } else {
      filenames = []
    }

    let highestNumber =
      filenames.compactMap { filename -> Int? in
        guard filename.hasPrefix(prefix), filename.hasSuffix(".pdf") else { return nil }
        let numberStart = filename.index(filename.startIndex, offsetBy: prefix.count)
        let numberEnd = filename.index(filename.endIndex, offsetBy: -4)
        return Int(filename[numberStart..<numberEnd])
      }.max() ?? 0
    let nextFilename = String(
      format: "report-%@-%04d.pdf",
      packageVersion,
      highestNumber + 1
    )
    return directory.appendingPathComponent(nextFilename)
  }

  private static func isValid(packageVersion: String) -> Bool {
    !packageVersion.isEmpty
      && packageVersion.allSatisfy { character in
        character.isLetter || character.isNumber || character == "." || character == "-"
      }
  }
}

public enum PDFVisualReportArchiveError: Error, Equatable {
  case invalidPackageVersion(String)
}

extension PDFVisualReportArchiveError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .invalidPackageVersion(let version):
      "Invalid package version '\(version)'. Use letters, numbers, dots, or hyphens."
    }
  }
}
