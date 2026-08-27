import Foundation

public enum CSSSource: Sendable {
  case string(String)
  case file(URL)
}
