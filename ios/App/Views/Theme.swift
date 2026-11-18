import SwiftUI

/// The app's palette.
enum Theme {
  static let background = Color(hex: 0x0d0d10)
  static let surface = Color(hex: 0x17171c)
  static let surface2 = Color(hex: 0x212127)
  static let surface3 = Color(hex: 0x2c2c34)
  static let text = Color(hex: 0xf5f5f7)
  static let text2 = Color(hex: 0xa3a3ad)
  static let text3 = Color(hex: 0x66666f)
  static let accent = Color(hex: 0x8a8cff)
  /// Dark lines on the book's blue card back, and on a current book move.
  static let accentInk = Color(hex: 0x0e0e2a)
  /// Filled buttons: near-white with near-black words. The accent is for highlights only.
  static let button = Color(hex: 0xececf2)
  static let buttonInk = Color(hex: 0x111116)
  /// Home's Play button pressed.
  static let buttonPressed = Color(hex: 0xd4d4dc)
  static let good = Color(hex: 0x4ade80)
  static let bad = Color(hex: 0xfb7185)
  static let warn = Color(hex: 0xfbbf24)
  /// A chance you missed: its arrow and its callout.
  static let missed = Color(hex: 0xf472b6)
  /// Pawns, their prices and the balance.
  static let pawn = Color(hex: 0xfbbf24)
  /// A streak day kept by a freeze or a repair.
  static let ice = Color(hex: 0x7dd3fc)
  /// The book's blue and the extension's purple.
  static let book = Color(hex: 0x4fb3ff)
  static let ext = Color(hex: 0x8a8cff)
  /// Text on an extension's outline, and on a book move's tint.
  static let extText = Color(hex: 0xc4c5ff)
}

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
  }
}

extension Color {
  /// A color from "#rrggbb".
  init(hexString: String) {
    self.init(hex: UInt32(hexString.dropFirst(), radix: 16) ?? 0)
  }
}
