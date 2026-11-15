import SwiftUI

/// A count of pawns: the pawn glyph and the number, in the pawns' yellow.
struct PawnAmount: View {
  var count: Int
  var size: CGFloat = 17
  var color: Color = Theme.pawn

  var body: some View {
    HStack(spacing: size * 0.18) {
      Icon(name: "pawn", size: size * 0.95)
      Text("\(count)").font(.system(size: size, weight: .bold).monospacedDigit())
        .contentTransition(.numericText(value: Double(count)))
    }
    .foregroundStyle(color)
    .accessibilityElement()
    .accessibilityLabel("\(count) pawn\(count == 1 ? "" : "s")")
  }
}

extension Image {
  /// The pawn as a template image, for the tab bar, which takes only images.
  @MainActor static let pawn: Image = {
    let renderer = ImageRenderer(content: Icon(name: "pawn", size: 24).foregroundStyle(.black))
    renderer.scale = 3
    guard let image = renderer.uiImage else { return Image(systemName: "circle.fill") }
    return Image(uiImage: image.withRenderingMode(.alwaysTemplate))
  }()
}
