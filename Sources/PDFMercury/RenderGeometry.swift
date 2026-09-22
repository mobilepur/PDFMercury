import CoreGraphics
import Foundation

struct VerticalRange: Sendable {
  let minY: CGFloat
  let maxY: CGFloat

  var height: CGFloat { maxY - minY }
}

struct TableContinuation: Sendable {
  let rowRange: VerticalRange
  let headerRange: VerticalRange
}

struct PageSlice: Sendable {
  let bodyRect: CGRect
  let repeatedHeaderRect: CGRect?
}

struct RenderedPage: Sendable {
  let body: Data
  let repeatedHeader: Data?
  let repeatedHeaderHeight: CGFloat
  let footer: Data?
  let footerHeight: CGFloat
}

