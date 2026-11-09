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
  /// A tip hung under this view (or over it, for an arrow pointing down), drawn
  /// over what follows without moving it. It hangs from a line of no height at
  /// the view's edge, so it clears the view whatever its own height.
  func tip(_ tip: TutorialTip?, when shown: Bool, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, onDismiss: @escaping () -> Void) -> some View {
    self.tip(text: shown ? tip?.text : nil, arrow: arrow, arrowAt: arrowAt, inset: inset, onDismiss: onDismiss)
  }

  /// A tip with its own text, hung the same way; none while `text` is nil.
  /// On a view narrower than `minWidth` the tip keeps that width, running
  /// right from the view's leading edge; `arrowAt` is then along the tip.
  /// Use one per view: a second's `zIndex` loses to the first's.
  func tip(
    text: String?, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, minWidth: CGFloat = 0,
    onDismiss: @escaping () -> Void = {}
  ) -> some View {
    overlay(alignment: arrow == .up ? .bottom : .top) {
      if let text {
        Color.clear.frame(height: 0).overlay(alignment: arrow == .up ? .topLeading : .bottomLeading) {
          TipBubble(
            text: text, arrow: arrow, arrowAt: arrowAt, onDismiss: onDismiss)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: minWidth)
            .padding(arrow == .up ? .top : .bottom, 12).padding(.horizontal, inset)
        }
      }
    }
    .zIndex(text != nil ? 2 : 0)
  }
}

/// A tip off the board put away for good, so the next one shows.
@MainActor func dismissTip(_ store: AppStore, _ tip: TutorialTip?) {
  guard let tip else { return }
  withAnimation(.easeOut(duration: 0.15)) {
    store.update { $0.settings.putAway(tip) }
  }
}
