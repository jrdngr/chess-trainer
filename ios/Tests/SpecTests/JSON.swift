import Foundation

/// A JSON value, for reading golden cases and comparing answers to them.
enum JSON: Equatable, CustomStringConvertible {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  init(any: Any?) {
    switch any {
    case nil, is NSNull: self = .null
    case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
    case let n as NSNumber: self = .number(n.doubleValue)
    case let s as String: self = .string(s)
    case let a as [Any]: self = .array(a.map { JSON(any: $0) })
    case let o as [String: Any]: self = .object(o.mapValues { JSON(any: $0) })
    default: fatalError("not JSON: \(String(describing: any))")
    }
  }

  static func parse(_ data: Data) throws -> JSON {
    JSON(any: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
  }

  var description: String {
    switch self {
    case .null: return "null"
    case .bool(let b): return String(b)
    case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
    case .string(let s): return "\"\(s)\""
    case .array(let a): return "[" + a.map(\.description).joined(separator: ",") + "]"
    case .object(let o):
      return "{" + o.keys.sorted().map { "\"\($0)\":\(o[$0]!)" }.joined(separator: ",") + "}"
    }
  }

  // Reading arguments.
  var string: String { if case .string(let s) = self { return s }; fatalError("not a string: \(self)") }
  var stringOrNil: String? { if case .null = self { return nil }; return string }
  var number: Double { if case .number(let n) = self { return n }; fatalError("not a number: \(self)") }
  var numberOrNil: Double? { if case .null = self { return nil }; return number }
  var int: Int { Int(number) }
  var bool: Bool { if case .bool(let b) = self { return b }; fatalError("not a bool: \(self)") }
  var array: [JSON] { if case .array(let a) = self { return a }; fatalError("not an array: \(self)") }
  var object: [String: JSON] { if case .object(let o) = self { return o }; fatalError("not an object: \(self)") }
  subscript(key: String) -> JSON { object[key] ?? .null }
  subscript(index: Int) -> JSON { array[index] }
  var strings: [String] { array.map(\.string) }
  var numbers: [Double] { array.map(\.number) }
}

/// Whether an answer matches the golden one.
///
/// JSON.stringify leaves out a key whose value is undefined, so a missing key
/// and a null are the same answer. Numbers match to a few ulps: both sides do
/// the same double arithmetic, through different maths libraries.
func matches(_ a: JSON, _ b: JSON) -> Bool {
  switch (a, b) {
  case (.number(let x), .number(let y)):
    return x == y || abs(x - y) <= 1e-9 * max(1, abs(x), abs(y))
  case (.array(let x), .array(let y)):
    return x.count == y.count && zip(x, y).allSatisfy(matches)
  case (.object(let x), .object(let y)):
    let keys = Set(x.keys).union(y.keys)
    return keys.allSatisfy { matches(x[$0] ?? .null, y[$0] ?? .null) }
  default:
    return a == b
  }
}

/// Building answers.
protocol JSONable { var json: JSON { get } }
extension String: JSONable { var json: JSON { .string(self) } }
extension Bool: JSONable { var json: JSON { .bool(self) } }
extension Double: JSONable {
  var json: JSON {
    if isNaN { return .string("NaN") }
    if isInfinite { return .string(self > 0 ? "Infinity" : "-Infinity") }
    return .number(self == 0 ? 0 : self)
  }
}
extension Int: JSONable { var json: JSON { .number(Double(self)) } }
extension Optional: JSONable where Wrapped: JSONable { var json: JSON { self?.json ?? .null } }
extension Array: JSONable where Element: JSONable { var json: JSON { .array(map(\.json)) } }
extension JSON: JSONable { var json: JSON { self } }

func obj(_ pairs: KeyValuePairs<String, JSONable?>) -> JSON {
  var out: [String: JSON] = [:]
  for (k, v) in pairs { if let v { out[k] = v.json } }
  return .object(out)
}

extension Dictionary: JSONable where Key == String, Value: JSONable {
  var json: JSON { .object(mapValues(\.json)) }
}

/// Any Codable model value as JSON, through its Codable shape.
func encoded<T: Encodable>(_ value: T) -> JSON {
  let data = try! JSONEncoder().encode(value)
  return try! JSON.parse(data)
}

extension JSON {
  /// A JSON argument decoded into a Codable model value.
  func decoded<T: Decodable>(_ type: T.Type = T.self) -> T {
    let data = try! JSONSerialization.data(withJSONObject: anyValue, options: [.fragmentsAllowed])
    return try! JSONDecoder().decode(T.self, from: data)
  }

  var anyValue: Any {
    switch self {
    case .null: return NSNull()
    case .bool(let b): return b
    case .number(let n): return n
    case .string(let s): return s
    case .array(let a): return a.map(\.anyValue)
    case .object(let o): return o.mapValues(\.anyValue)
    }
  }
}
