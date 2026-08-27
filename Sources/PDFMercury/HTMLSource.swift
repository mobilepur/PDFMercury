import Foundation

public enum HTMLSource: Sendable {
  case string(String, baseURL: URL? = nil)
  case file(URL)
}
