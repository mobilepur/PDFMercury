import CoreGraphics
import Foundation

struct RenderDocument: Sendable {
  let html: String
  let baseURL: URL?
  let pageLayout: PageLayout

  init(html source: HTMLSource, stylesheets: [CSSSource]) throws {
    let resolvedHTML = try Self.resolve(source)
    let resolvedStylesheets = try stylesheets.map(Self.resolve)
    let resolvedPageLayout = Self.pageLayout(
      for: resolvedStylesheets.map(\.contents).joined(separator: "\n")
    )
    let viewport = """
      <meta name="viewport" content="width=\(resolvedPageLayout.contentRect.width), initial-scale=1.0">
      """

    html = Self.inject(
      ([viewport] + resolvedStylesheets.map(\.htmlElement)).joined(separator: "\n"),
      into: resolvedHTML.contents
    )
    baseURL = resolvedHTML.baseURL
    pageLayout = resolvedPageLayout
  }

  private static func resolve(_ source: HTMLSource) throws -> ResolvedHTML {
    switch source {
    case .string(let contents, let baseURL):
      return ResolvedHTML(
        contents: LocalAssetResolver.resolveHTMLAssets(
          in: contents,
          relativeTo: baseURL
        ),
        baseURL: baseURL
      )
    case .file(let url):
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        throw PDFMercuryError.unreadableHTMLFile(url)
      }
      let baseURL = url.deletingLastPathComponent()
      return ResolvedHTML(
        contents: LocalAssetResolver.resolveHTMLAssets(
          in: contents,
          relativeTo: baseURL
        ),
        baseURL: baseURL
      )
    }
  }

  private static func resolve(_ source: CSSSource) throws -> ResolvedStylesheet {
    switch source {
    case .string(let contents):
      return ResolvedStylesheet(
        contents: contents,
        htmlElement: "<style>\n\(contents)\n</style>"
      )
    case .file(let url):
      guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
        throw PDFMercuryError.unreadableCSSFile(url)
      }
      let resolvedContents = LocalAssetResolver.resolveCSSAssets(
        in: contents,
        relativeTo: url.deletingLastPathComponent()
      )
      return ResolvedStylesheet(
        contents: resolvedContents,
        htmlElement: "<style>\n\(resolvedContents)\n</style>"
      )
    }
  }

  private static func inject(_ stylesheets: String, into html: String) -> String {
    guard !stylesheets.isEmpty else { return html }
    guard let closingHead = html.range(of: "</head>", options: .caseInsensitive) else {
      return "<head>\n\(stylesheets)\n</head>\n\(html)"
    }

    var result = html
    result.insert(contentsOf: "\n\(stylesheets)\n", at: closingHead.lowerBound)
    return result
  }

  private static func pageLayout(for css: String) -> PageLayout {
    let a4Portrait = CGSize(width: 595.28, height: 841.89)
    var orientation = PageOrientation.portrait
    var margins = PageMargins.zero

    for pageRule in pageDeclarations(in: css) {
      for declaration in declarations(in: pageRule) {
        switch declaration.name {
        case "size":
          orientation = declaration.value.contains("landscape") ? .landscape : .portrait
        case "margin":
          if let resolvedMargins = PageMargins(cssValue: declaration.value) {
            margins = resolvedMargins
          }
        case "margin-top":
          margins.top = cssLength(declaration.value) ?? margins.top
        case "margin-right":
          margins.right = cssLength(declaration.value) ?? margins.right
        case "margin-bottom":
          margins.bottom = cssLength(declaration.value) ?? margins.bottom
        case "margin-left":
          margins.left = cssLength(declaration.value) ?? margins.left
        default:
          break
        }
      }
    }

    let size =
      orientation == .landscape
      ? CGSize(width: a4Portrait.height, height: a4Portrait.width)
      : a4Portrait
    return PageLayout(pageSize: size, margins: margins)
  }

  private static func pageDeclarations(in css: String) -> [String] {
    let lowercaseCSS = css.lowercased()
    var rules: [String] = []
    var searchStart = lowercaseCSS.startIndex

    while let pageRule = lowercaseCSS.range(
      of: "@page",
      range: searchStart..<lowercaseCSS.endIndex
    ),
      let openingBrace = lowercaseCSS[pageRule.upperBound...].firstIndex(of: "{"),
      let closingBrace = lowercaseCSS[openingBrace...].firstIndex(of: "}")
    {
      rules.append(String(lowercaseCSS[openingBrace...closingBrace]))
      searchStart = lowercaseCSS.index(after: closingBrace)
    }

    return rules
  }

  private static func declarations(in pageRule: String) -> [(name: String, value: String)] {
    pageRule
      .dropFirst()
      .dropLast()
      .split(separator: ";")
      .compactMap { declaration in
        guard let separator = declaration.firstIndex(of: ":") else { return nil }
        let name = declaration[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = declaration[declaration.index(after: separator)...]
          .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, value)
      }
  }

  fileprivate static func cssLength(_ value: String) -> CGFloat? {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if value == "0" { return 0 }

    let units: [(suffix: String, factor: Double)] = [
      ("px", 1),
      ("pt", 96 / 72),
      ("in", 96),
      ("cm", 96 / 2.54),
      ("mm", 96 / 25.4),
    ]
    guard let unit = units.first(where: { value.hasSuffix($0.suffix) }) else {
      return nil
    }
    guard let number = Double(value.dropLast(unit.suffix.count)), number >= 0 else {
      return nil
    }
    return CGFloat(number * unit.factor)
  }
}

enum PageOrientation: Sendable {
  case portrait
  case landscape
}

struct PageLayout: Sendable {
  let pageRect: CGRect
  let contentRect: CGRect

  init(pageSize: CGSize, margins: PageMargins) {
    pageRect = CGRect(origin: .zero, size: pageSize)
    contentRect = CGRect(
      x: margins.left,
      y: margins.bottom,
      width: max(1, pageSize.width - margins.left - margins.right),
      height: max(1, pageSize.height - margins.top - margins.bottom)
    )
  }
}

struct PageMargins: Sendable {
  var top: CGFloat
  var right: CGFloat
  var bottom: CGFloat
  var left: CGFloat

  static let zero = PageMargins(top: 0, right: 0, bottom: 0, left: 0)

  init?(cssValue: String) {
    let values =
      cssValue
      .split(whereSeparator: \.isWhitespace)
      .compactMap { RenderDocument.cssLength(String($0)) }
    guard values.count == cssValue.split(whereSeparator: \.isWhitespace).count else {
      return nil
    }

    switch values.count {
    case 1:
      self.init(top: values[0], right: values[0], bottom: values[0], left: values[0])
    case 2:
      self.init(top: values[0], right: values[1], bottom: values[0], left: values[1])
    case 3:
      self.init(top: values[0], right: values[1], bottom: values[2], left: values[1])
    case 4:
      self.init(top: values[0], right: values[1], bottom: values[2], left: values[3])
    default:
      return nil
    }
  }

  private init(top: CGFloat, right: CGFloat, bottom: CGFloat, left: CGFloat) {
    self.top = top
    self.right = right
    self.bottom = bottom
    self.left = left
  }
}

struct ResolvedHTML: Sendable {
  let contents: String
  let baseURL: URL?
}

struct ResolvedStylesheet: Sendable {
  let contents: String
  let htmlElement: String
}

private enum LocalAssetResolver {
  private static let htmlSourcePattern = #"(?i)(\bsrc\s*=\s*[\"'])([^\"']+)([\"'])"#
  private static let cssURLPattern = #"(?i)(url\(\s*[\"']?)([^\"')]+)([\"']?\s*\))"#

  static func resolveHTMLAssets(in html: String, relativeTo baseURL: URL?) -> String {
    replacingLocalURLs(
      in: html,
      matching: htmlSourcePattern,
      relativeTo: baseURL
    )
  }

  static func resolveCSSAssets(in css: String, relativeTo baseURL: URL) -> String {
    replacingLocalURLs(
      in: css,
      matching: cssURLPattern,
      relativeTo: baseURL
    )
  }

  private static func replacingLocalURLs(
    in contents: String,
    matching pattern: String,
    relativeTo baseURL: URL?
  ) -> String {
    guard let baseURL, baseURL.isFileURL else { return contents }
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return contents
    }

    let original = contents as NSString
    let matches = expression.matches(
      in: contents,
      range: NSRange(location: 0, length: original.length)
    )
    var result = contents

    for match in matches.reversed() {
      let valueRange = match.range(at: 2)
      let value = original.substring(with: valueRange)
      guard let dataURL = dataURL(for: value, relativeTo: baseURL) else {
        continue
      }
      guard let range = Range(valueRange, in: result) else { continue }
      result.replaceSubrange(range, with: dataURL)
    }

    return result
  }

  private static func dataURL(for value: String, relativeTo baseURL: URL) -> String? {
    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty, !trimmedValue.hasPrefix("#") else { return nil }

    let assetURL: URL
    if let absoluteURL = URL(string: trimmedValue), absoluteURL.scheme != nil {
      guard absoluteURL.isFileURL else { return nil }
      assetURL = absoluteURL
    } else {
      assetURL = URL(fileURLWithPath: trimmedValue, relativeTo: baseURL).standardizedFileURL
    }

    guard let data = try? Data(contentsOf: assetURL) else { return nil }
    return "data:\(mimeType(for: assetURL));base64,\(data.base64EncodedString())"
  }

  private static func mimeType(for url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "svg":
      return "image/svg+xml"
    case "png":
      return "image/png"
    case "jpg", "jpeg":
      return "image/jpeg"
    case "gif":
      return "image/gif"
    case "webp":
      return "image/webp"
    case "woff":
      return "font/woff"
    case "woff2":
      return "font/woff2"
    case "ttf":
      return "font/ttf"
    case "otf":
      return "font/otf"
    default:
      return "application/octet-stream"
    }
  }
}

