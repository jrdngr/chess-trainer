import Model
import SwiftUI

/// One of the tutorial's tips: white, with an arrow at what it explains.
/// A tap puts it away.
struct TipBubble: View {
  enum Arrow { case up, down }
  let text: String
  var arrow: Arrow = .up
  /// Where along the bubble's width the arrow sits, 0...1.
  var arrowAt: CGFloat = 0.5
  let onDismiss: () -> Void

  var body: some View {
    Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
      .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 14).padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 14).fill(.white))
    .overlay(alignment: arrow == .up ? .topLeading : .bottomLeading) {
      GeometryReader { geo in
        TipArrow(up: arrow == .up).fill(.white).frame(width: 16, height: 8)
          .offset(x: geo.size.width * arrowAt - 8, y: arrow == .up ? -8 : geo.size.height)
      }
    }
    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)
    .contentShape(Rectangle())
    .onTapGesture(perform: onDismiss)
    .accessibilityAddTraits(.isButton)
    .transition(.opacity)
  }
}

private struct TipArrow: Shape {
  let up: Bool
  func path(in rect: CGRect) -> Path {
    var path = Path()
    if up {
      path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    } else {
      path.move(to: CGPoint(x: rect.minX, y: rect.minY))
      path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    }
    path.closeSubpath()
    return path
  }
}

extension View {
  /// A tutorial tip under this view (over it, for an arrow pointing down), while `shown`. `tip(text:)`.
  func tip(
    _ tip: TutorialTip?, when shown: Bool, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, drop: CGFloat = 0,
    rest: Double = 0, onDismiss: @escaping () -> Void
  ) -> some View {
    self.tip(text: shown ? tip?.text : nil, arrow: arrow, arrowAt: arrowAt, inset: inset, drop: drop, rest: rest, onDismiss: onDismiss)
  }

  /// A tip with its own text; none while `text` is nil. It hangs under this
  /// view (over it, for an arrow pointing down) on top of what follows, so it
  /// never moves anything. A `minWidth` wider than a narrow view runs the tip
  /// right from the view's leading edge with `arrowAt` along the tip. `drop`
  /// sets it further out. `rest` is the view's `zIndex` with no tip up.
  /// Use one per view: a second tip's `zIndex` loses to the first's.
  func tip(
    text: String?, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, minWidth: CGFloat = 0, drop: CGFloat = 0,
    rest: Double = 0, onDismiss: @escaping () -> Void = {}
  ) -> some View {
    modifier(TipLayer(text: text, arrow: arrow, arrowAt: arrowAt, inset: inset, minWidth: minWidth, drop: drop, rest: rest, onDismiss: onDismiss))
  }
}

/// Hangs a tip off its view, and keeps the view on top until the tip has faded out.
struct TipLayer: ViewModifier {
  let text: String?
  let arrow: TipBubble.Arrow
  let arrowAt: CGFloat
  let inset: CGFloat
  let minWidth: CGFloat
  let drop: CGFloat
  let rest: Double
  let onDismiss: () -> Void
  /// A tip is up, or still fading out.
  @State private var raised = false

  /// How long a tip takes to fade.
  private static let fade = 0.2

  func body(content: Content) -> some View {
    content
      .overlay(alignment: arrow == .up ? .bottom : .top) {
        if let text {
          Color.clear.frame(height: 0).overlay(alignment: arrow == .up ? .topLeading : .bottomLeading) {
            TipBubble(text: text, arrow: arrow, arrowAt: arrowAt, onDismiss: onDismiss)
              .fixedSize(horizontal: false, vertical: true)
              .frame(minWidth: minWidth)
              .padding(arrow == .up ? .top : .bottom, 12 + drop).padding(.horizontal, inset)
          }
          .transition(.opacity)
        }
      }
      .animation(.easeOut(duration: Self.fade), value: text)
      .zIndex(raised || text != nil ? 2 : rest)
      .task(id: text != nil) {
        if text != nil {
          raised = true
        } else if raised {
          try? await Task.sleep(for: .seconds(Self.fade + 0.05))
          if !Task.isCancelled { raised = false }
        }
      }
  }
}

/// A tip off the board put away for good, so the next one shows.
@MainActor func dismissTip(_ store: AppStore, _ tip: TutorialTip?) {
  guard let tip else { return }
  withAnimation(.easeOut(duration: 0.15)) {
    store.update { $0.settings.putAway(tip) }
  }
}
