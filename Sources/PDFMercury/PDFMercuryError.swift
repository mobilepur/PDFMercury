import Foundation

public enum PDFMercuryError: Error, Equatable, LocalizedError, Sendable {
  case unreadableHTMLFile(URL)
  case unreadableCSSFile(URL)
  case webContentFailedToLoad(String)
  case invalidRenderedPDF
  case couldNotCreatePDF
  case invalidPageFooter(String)

  public var errorDescription: String? {
    switch self {
    case .unreadableHTMLFile(let url):
      "Could not read HTML file: \(url.path)"
    case .unreadableCSSFile(let url):
      "Could not read CSS file: \(url.path)"
    case .webContentFailedToLoad(let message):
      "Web content failed to load: \(message)"
    case .invalidRenderedPDF:
      "WebKit returned an invalid PDF page."
    case .couldNotCreatePDF:
      "Could not create the multi-page PDF."
    case .invalidPageFooter(let message):
      "Invalid page footer: \(message)"
    }
  }
}
