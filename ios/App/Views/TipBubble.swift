import Model
import SwiftUI

/// One of the first game's tips: white, with an arrow at what it explains.
/// A tap puts it away. A tip in a run of tips shows dots for where it is in the run.
struct TipBubble: View {
  enum Arrow { case up, down }
  let text: String
  var arrow: Arrow = .up
  /// Where along the bubble's width the arrow sits, 0...1.
  var arrowAt: CGFloat = 0.5
  /// Which tip of how many in a run, from 0.
  var step: (at: Int, of: Int)?
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
      if let step {
        HStack(spacing: 4) {
          ForEach(0..<step.of, id: \.self) { i in
            Circle().fill(i == step.at ? SwiftUI.Color.black : SwiftUI.Color(hex: 0xd4d4da)).frame(width: 6, height: 6)
          }
        }
        .accessibilityHidden(true)
      }
    }
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
  func tip(_ tip: FirstGameTip?, when shown: Bool, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, onDismiss: @escaping () -> Void) -> some View {
    overlay(alignment: arrow == .up ? .bottom : .top) {
      if shown, let tip {
        Color.clear.frame(height: 0).overlay(alignment: arrow == .up ? .top : .bottom) {
          TipBubble(
            text: tip.text, arrow: arrow, arrowAt: arrowAt,
            step: tip.playStep.map { ($0, FirstGameTip.playTips.count) }, onDismiss: onDismiss)
            .fixedSize(horizontal: false, vertical: true)
            .padding(arrow == .up ? .top : .bottom, 12).padding(.horizontal, inset)
        }
      }
    }
    .zIndex(shown && tip != nil ? 2 : 0)
  }
}

/// A tip after the first game put away for good, so the next one shows.
@MainActor func dismissTip(_ store: AppStore, _ tip: FirstGameTip?) {
  guard let tip else { return }
  withAnimation(.easeOut(duration: 0.15)) {
    store.update { $0.settings.tips.removeAll { $0 == tip } }
  }
}
