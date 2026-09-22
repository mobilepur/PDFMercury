import CoreGraphics

enum PDFPagination {
  private static let pageBoundaryTolerance: CGFloat = 0.5

  static func pageSlices(
    contentHeight: CGFloat,
    pageSize: CGSize,
    pageBreakAvoidanceRanges: [VerticalRange],
    tableContinuations: [TableContinuation]
  ) -> [PageSlice] {
    var slices: [PageSlice] = []
    var startY: CGFloat = 0

    while contentHeight - startY > Self.pageBoundaryTolerance {
      let startingContinuation = tableContinuations.first {
        $0.rowRange.minY <= startY + Self.pageBoundaryTolerance
          && $0.rowRange.maxY > startY + Self.pageBoundaryTolerance
      }
      let repeatedHeaderRange = startingContinuation.flatMap { continuation in
        let headerHeight = continuation.headerRange.height
        // Even an overheight first row can continue across several pages.
        // Omit an oversized header so the body can always make progress.
        return pageSize.height - headerHeight > Self.pageBoundaryTolerance
          ? continuation.headerRange : nil
      }
      let bodyHeight = pageSize.height - (repeatedHeaderRange?.height ?? 0)
      let maximumEndY = min(startY + bodyHeight, contentHeight)
      var endY = maximumEndY
      if maximumEndY < contentHeight {
        // Oversized containers must not hide the text lines inside them. Only
        // move a break for content that fits and starts after this page's start;
        // otherwise split it while retaining any smaller avoidable ranges.
        let avoidableRanges = pageBreakAvoidanceRanges.filter {
          $0.height <= bodyHeight
            && $0.minY - startY > Self.pageBoundaryTolerance
        }
        while let safeEndY = avoidableRanges
          .filter({ $0.minY < endY && $0.maxY > endY })
          .map(\.minY)
          .min()
        {
          endY = safeEndY
        }
      }

      let repeatedHeaderRect = repeatedHeaderRange.map {
        CGRect(
          x: 0,
          y: $0.minY,
          width: pageSize.width,
          height: $0.height
        )
      }
      slices.append(
        PageSlice(
          bodyRect: CGRect(
            x: 0,
            y: startY,
            width: pageSize.width,
            height: endY - startY
          ),
          repeatedHeaderRect: repeatedHeaderRect
        )
      )
      startY = endY
    }

    if slices.isEmpty {
      slices.append(
        PageSlice(
          bodyRect: CGRect(
            x: 0,
            y: 0,
            width: pageSize.width,
            height: pageSize.height
          ),
          repeatedHeaderRect: nil
        )
      )
    }
    return slices
  }

}
