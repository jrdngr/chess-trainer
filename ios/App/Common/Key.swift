import SwiftUI

/// The app's buttons are keys: a face over a darker lip. A press sinks the face into the lip,
/// inside the key's own footprint, so nothing around it moves.
enum KeyKind {
  /// Indigo with white words: Select and sheet buttons.
  case primary
  /// Gray with light words: Analyze and the other quiet buttons.
  case secondary
  /// Home's Play: a brighter indigo, a deeper lip and a checker trim at each end.
  case play

  var face: Color {
    switch self {
    case .primary: Theme.key
    case .secondary: Theme.key2
    case .play: Theme.play
    }
  }

  var pressedFace: Color {
    switch self {
    case .primary: Theme.keyDown
    case .secondary: Theme.key2Down
    case .play: Theme.playDown
    }
  }

  var edge: Color {
    switch self {
    case .primary: Theme.keyEdge
    case .secondary: Theme.key2Edge
    case .play: Theme.playEdge
    }
  }

  var lipColor: Color {
    switch self {
    case .primary: Theme.keyLip
    case .secondary: Theme.key2Lip
    case .play: Theme.playLip
    }
  }

  var pressedLip: Color { self == .secondary ? Theme.key2Lip : Theme.keyDownLip }

  /// How far the lip shows below the face.
  var lip: CGFloat { self == .play ? 5 : 3 }

  var ink: Color { self == .secondary ? Theme.text : .white }
  var pressedInk: Color { self == .secondary ? Theme.text2 : Theme.keyPressedInk }
}

extension View {
  /// Draws `self` as a key's face. The key is the face's height plus its lip.
  func key(_ kind: KeyKind, radius: CGFloat, pressed: Bool = false) -> some View {
    modifier(KeyCap(kind: kind, radius: radius, pressed: pressed))
  }
}

private struct KeyCap: ViewModifier {
  let kind: KeyKind
  let radius: CGFloat
  let pressed: Bool

  func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: radius)
    content
      .foregroundStyle(pressed ? kind.pressedInk : kind.ink)
      .background {
        ZStack {
          shape.fill(pressed ? kind.pressedFace : kind.face)
          if kind == .play { CheckerTrim().opacity(pressed ? 0.5 : 1) }
          // The light along the top edge; pressed, a shadow takes its place.
          shape.strokeBorder(
            LinearGradient(
              colors: [pressed ? .black.opacity(0.3) : kind.edge, .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12)),
            lineWidth: pressed ? 2 : 1)
        }
        .clipShape(shape)
      }
      .offset(y: pressed ? kind.lip - 1 : 0)
      .padding(.bottom, kind.lip)
      .background { shape.fill(pressed ? kind.pressedLip : kind.lipColor).padding(.top, kind.lip) }
      .contentShape(shape)
      .animation(.easeOut(duration: 0.07), value: pressed)
  }
}

/// Three rows of white squares at each end of Play's face, fading toward the word.
private struct CheckerTrim: View {
  var body: some View {
    Canvas { context, size in
      let side = size.height / 3
      let strength: [Double] = [0.12, 0.08, 0.045, 0.02]
      for (column, alpha) in strength.enumerated() {
        for row in 0..<3 where (row + column) % 2 == 0 {
          let y = CGFloat(row) * side
          for x in [CGFloat(column) * side, size.width - CGFloat(column + 1) * side] {
            context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(.white.opacity(alpha)))
          }
        }
      }
    }
    .allowsHitTesting(false)
  }
}

/// A button drawn as a key: `height` is the whole key, lip included.
struct KeyButtonStyle: ButtonStyle {
  var kind = KeyKind.primary
  var height: CGFloat = 50
  var radius: CGFloat = 14
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(maxWidth: .infinity, minHeight: height - kind.lip)
      .key(kind, radius: radius, pressed: configuration.isPressed)
      .opacity(enabled ? 1 : 0.35)
  }
}
