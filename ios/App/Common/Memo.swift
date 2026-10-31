/// One value kept until its key changes, for a list too slow to build on every redraw.
/// Held in `@State`; it is not observed, so filling it from `body` is safe.
final class Memo<Value> {
  private var key: String?
  private var value: Value?

  func get(_ key: String, _ make: () -> Value) -> Value {
    if key != self.key || value == nil {
      value = make()
      self.key = key
    }
    return value!
  }
}
