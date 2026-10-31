import SwiftUI

/// The prototype's palette: `src/styles.css`.
enum Theme {
  static let background = Color(hex: 0x0d0d10)
  static let surface = Color(hex: 0x17171c)
  static let surface2 = Color(hex: 0x212127)
  static let text = Color(hex: 0xf5f5f7)
  static let text2 = Color(hex: 0xa3a3ad)
  static let text3 = Color(hex: 0x66666f)
  static let accent = Color(hex: 0x8a8cff)
  static let good = Color(hex: 0x4ade80)
  static let bad = Color(hex: 0xfb7185)
  static let warn = Color(hex: 0xfbbf24)
  /// The book's blue and the extension's purple.
  static let book = Color(hex: 0x4fb3ff)
  static let ext = Color(hex: 0x8a8cff)
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
  }
}
