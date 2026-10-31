import Foundation

/// The few places the prototype's numbers and orderings come from JavaScript
/// itself. Each matches the JS built-in exactly, so ported code can call it
/// where the TypeScript calls the original.
public enum JS {
  /// `Math.round`: the nearest integer, halves toward +infinity.
  public static func round(_ x: Double) -> Double {
    guard x.isFinite else { return x }
    let down = x.rounded(.down)
    return x - down >= 0.5 ? down + 1 : down
  }

  /// `Number.prototype.toFixed`: rounds the double's exact decimal value,
  /// an exact tie going up (printf would go to even).
  public static func toFixed(_ x: Double, _ digits: Int) -> String {
    guard x.isFinite, abs(x) < 1e21 else { return string(x) }
    // Every double has a finite decimal expansion; 1100 places holds any of them.
    let exact = String(format: "%.1100f", abs(x))
    let point = exact.firstIndex(of: ".")!
    var whole = Array(exact[..<point]).map { Int(String($0))! }
    let fraction = Array(exact[exact.index(after: point)...]).map { Int(String($0))! }
    var kept = Array(fraction.prefix(digits))
    let rest = fraction.dropFirst(digits)
    if let first = rest.first, first >= 5 {
      // Round up: carry through the kept digits and into the whole part.
      var carry = 1
      for i in kept.indices.reversed() where carry > 0 {
        kept[i] += carry
        carry = kept[i] / 10
        kept[i] %= 10
      }
      for i in whole.indices.reversed() where carry > 0 {
        whole[i] += carry
        carry = whole[i] / 10
        whole[i] %= 10
      }
      if carry > 0 { whole.insert(carry, at: 0) }
    }
    var out = whole.map(String.init).joined()
    if digits > 0 { out += "." + kept.map(String.init).joined() }
    return (x < 0 ? "-" : "") + out
  }

  /// `String(n)` for a number: integers without a decimal point.
  public static func string(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if x == x.rounded(), abs(x) < 1e21 { return String(Int64(x)) }
    return "\(x)"
  }

  /// `a.localeCompare(b)` in the prototype's default locale.
  public static func localeCompare(_ a: String, _ b: String) -> Int {
    switch a.compare(b, options: [], range: nil, locale: locale) {
    case .orderedAscending: return -1
    case .orderedDescending: return 1
    case .orderedSame: return 0
    }
  }

  private static let locale = Locale(identifier: "en_US")
}

extension Array {
  /// `Array.prototype.sort` with a comparator: stable, unlike Swift's `sort`.
  public func jsSorted(_ compare: (Element, Element) -> Double) -> [Element] {
    enumerated()
      .sorted { a, b in
        let c = compare(a.element, b.element)
        return c != 0 ? c < 0 : a.offset < b.offset
      }
      .map(\.element)
  }

  public mutating func jsSort(_ compare: (Element, Element) -> Double) {
    self = jsSorted(compare)
  }
}

/// `a - b` for comparators: the sign of a comparison as a number.
@inlinable public func cmp<T: Comparable>(_ a: T, _ b: T) -> Double {
  a < b ? -1 : a > b ? 1 : 0
}
