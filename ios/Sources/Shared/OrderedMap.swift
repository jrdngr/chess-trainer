/// A dictionary that remembers insertion order, like a JS `Map`.
///
/// The prototype reads several maps in insertion order and its answers depend
/// on it (ties broken by whichever came first), so the port keeps the order.
public struct OrderedMap<Key: Hashable, Value> {
  public private(set) var keys: [Key] = []
  private var storage: [Key: Value] = [:]

  public init() {}

  public subscript(key: Key) -> Value? {
    get { storage[key] }
    set {
      if let newValue {
        if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
      } else if storage.removeValue(forKey: key) != nil {
        keys.removeAll { $0 == key }
      }
    }
  }

  public var count: Int { keys.count }
  public var isEmpty: Bool { keys.isEmpty }
  public func has(_ key: Key) -> Bool { storage[key] != nil }
  public var values: [Value] { keys.map { storage[$0]! } }
  public var entries: [(key: Key, value: Value)] { keys.map { ($0, storage[$0]!) } }
}
