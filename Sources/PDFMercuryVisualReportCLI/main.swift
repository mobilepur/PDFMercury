import Darwin
import Foundation
import PDFMercuryVisualReporter

@main
enum PDFMercuryVisualReportCommand {
  static func main() {
    do {
      let invocation = try Invocation(arguments: Array(CommandLine.arguments.dropFirst()))
      try PDFVisualReportGenerator().generate(
        from: invocation.inputURLs,
        to: invocation.outputURL
      )
      print("Created \(invocation.outputURL.path)")
    } catch {
      writeError("error: \(error.localizedDescription)\n")
      writeError(Invocation.usage)
      Darwin.exit(EXIT_FAILURE)
    }
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data(message.utf8))
  }
}

private struct Invocation {
  static let usage = """
    Usage: pdfmercury-visual-report [options] <pdf-or-directory> [...]

      --package-version <version>   Version used in automatic report names (default: dev)
      --output-directory <path>     Archive directory for automatic report names
      --output <report.pdf>         Exact output path; overrides automatic naming

    """

  let inputURLs: [URL]
  let outputURL: URL

  init(arguments: [String]) throws {
    var inputs: [String] = []
    var output: String?
    var outputDirectory = ".build/pdfmercury-visual-report"
    var packageVersion = "dev"
    var index = 0

    while index < arguments.count {
      switch arguments[index] {
      case "--output":
        index += 1
        guard index < arguments.count else { throw InvocationError.missingOutputPath }
        output = arguments[index]
      case "--output-directory":
        index += 1
        guard index < arguments.count else { throw InvocationError.missingOutputDirectory }
        outputDirectory = arguments[index]
      case "--package-version":
        index += 1
        guard index < arguments.count else { throw InvocationError.missingPackageVersion }
        packageVersion = arguments[index]
      default:
        inputs.append(arguments[index])
      }
      index += 1
    }

    guard !inputs.isEmpty else { throw InvocationError.missingInput }

    let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let resolvedOutputURL: URL
    if let output {
      resolvedOutputURL =
        URL(
          fileURLWithPath: output,
          relativeTo: currentDirectory
        ).standardizedFileURL
    } else {
      let directory = URL(
        fileURLWithPath: outputDirectory,
        relativeTo: currentDirectory
      ).standardizedFileURL
      resolvedOutputURL = try PDFVisualReportArchive().nextReportURL(
        in: directory,
        packageVersion: packageVersion
      )
    }
    outputURL = resolvedOutputURL
    inputURLs = try Self.expand(inputs, relativeTo: currentDirectory)
      .filter { $0.standardizedFileURL != resolvedOutputURL }
      .sorted(by: Self.isOrderedBefore)

    guard !inputURLs.isEmpty else { throw InvocationError.noPDFs }
  }

  private static func expand(_ paths: [String], relativeTo baseURL: URL) throws -> [URL] {
    let fileManager = FileManager.default
    var result: [URL] = []

    for path in paths {
      let url = URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw InvocationError.inputDoesNotExist(url)
      }

      if isDirectory.boolValue {
        let contents = try fileManager.contentsOfDirectory(
          at: url,
          includingPropertiesForKeys: nil,
          options: [.skipsHiddenFiles]
        )
        result.append(contentsOf: contents.filter { $0.pathExtension.lowercased() == "pdf" })
      } else if url.pathExtension.lowercased() == "pdf" {
        result.append(url)
      }
    }

    return result
  }

  private static func isOrderedBefore(_ left: URL, _ right: URL) -> Bool {
    let leftName = left.deletingPathExtension().lastPathComponent
    let rightName = right.deletingPathExtension().lastPathComponent

    if leftName.hasPrefix(rightName) {
      return false
    }
    if rightName.hasPrefix(leftName) {
      return true
    }

    return leftName.localizedStandardCompare(rightName) == .orderedAscending
  }
}

private enum InvocationError: LocalizedError {
  case inputDoesNotExist(URL)
  case missingInput
  case missingOutputPath
  case missingOutputDirectory
  case missingPackageVersion
  case noPDFs

  var errorDescription: String? {
    switch self {
    case .inputDoesNotExist(let url):
      "Input does not exist: \(url.path)"
    case .missingInput:
      "At least one PDF file or directory is required."
    case .missingOutputPath:
      "--output requires a path."
    case .missingOutputDirectory:
      "--output-directory requires a path."
    case .missingPackageVersion:
      "--package-version requires a value."
    case .noPDFs:
      "No PDF files were found in the supplied inputs."
    }
  }
}
