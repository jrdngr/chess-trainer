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
  /// Buttons are keys (`KeyKind`): a face, a lighter top edge, a darker lip, and a darker face pressed.
  static let key = Color(hex: 0x4a4cd2)
  static let keyEdge = Color(hex: 0x7375ee)
  static let keyLip = Color(hex: 0x2c2d8e)
  static let keyDown = Color(hex: 0x3a3cae)
  static let keyDownLip = Color(hex: 0x27287c)
  static let keyPressedInk = Color(hex: 0xe4e4f6)
  /// Home's Play key, a step brighter than the others.
  static let play = Color(hex: 0x5658e6)
  static let playEdge = Color(hex: 0x9395fb)
  static let playLip = Color(hex: 0x3031a0)
  static let playDown = Color(hex: 0x4345c4)
  /// The gray key.
  static let key2 = Color(hex: 0x292930)
  static let key2Edge = Color(hex: 0x3d3d47)
  static let key2Lip = Color(hex: 0x18181d)
  static let key2Down = Color(hex: 0x1a1a1f)
  /// Something chosen that is not a button: the current move, a lens or chip turned on.
  static let selected = Color(hex: 0x2b2c58)
  static let selectedInk = Color(hex: 0xe9e9ff)
  static let good = Color(hex: 0x4ade80)
  static let bad = Color(hex: 0xfb7185)
  static let warn = Color(hex: 0xfbbf24)
  /// A chance you missed: its arrow and its callout.
  static let missed = Color(hex: 0xf472b6)
  /// Pawns, their prices and the balance.
  static let pawn = Color(hex: 0xfbbf24)
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
