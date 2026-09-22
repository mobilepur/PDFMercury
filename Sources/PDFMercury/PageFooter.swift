import Foundation

/// A normal-flow HTML element repeated at the bottom of every page's content area.
public struct PageFooter: Sendable {
  /// The unique ID of a visible direct child of `<body>`.
  public let elementID: String
  /// Space in PDF points between the body and the footer. Must be finite and nonnegative.
  public let gap: Double

  public init(elementID: String, gap: Double = 12) {
    self.elementID = elementID
    self.gap = gap
  }
}
