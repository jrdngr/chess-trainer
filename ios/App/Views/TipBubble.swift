import Game
import Model
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A tip: white, with an arrow at what it explains. A tap on it only puts it
/// away; the first touch anywhere else puts it away and still goes to what it landed on.
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
  /// A tip under this view (over it, for an arrow pointing down), while `shown`. `tip(text:)`.
  func tip(
    _ tip: GameTip?, when shown: Bool, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, drop: CGFloat = 0,
    rest: Double = 0, onDismiss: @escaping () -> Void
  ) -> some View {
    self.tip(text: shown ? tip?.text : nil, arrow: arrow, arrowAt: arrowAt, inset: inset, drop: drop, rest: rest, onDismiss: onDismiss)
  }

  /// A tip with its own text; none while `text` is nil. It hangs under this
  /// view (over it, for an arrow pointing down) on top of what follows, so it
  /// never moves anything. A `minWidth` wider than a narrow view runs the tip
  /// right from the view's leading edge with `arrowAt` along the tip. `drop`
  /// sets it further out. `rest` is the view's `zIndex` with no tip up.
  /// `trailing` runs a wide tip left from the view's trailing edge instead.
  /// Use one per view: a second tip's `zIndex` loses to the first's.
  func tip(
    text: String?, arrow: TipBubble.Arrow = .up, arrowAt: CGFloat = 0.5, inset: CGFloat = 0, minWidth: CGFloat = 0, drop: CGFloat = 0,
    trailing: Bool = false, rest: Double = 0, onDismiss: @escaping () -> Void = {}
  ) -> some View {
    modifier(
      TipLayer(
        text: text, arrow: arrow, arrowAt: arrowAt, inset: inset, minWidth: minWidth, drop: drop, trailing: trailing, rest: rest,
        onDismiss: onDismiss))
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
  let trailing: Bool
  let rest: Double
  let onDismiss: () -> Void
  /// A tip is up, or still fading out.
  @State private var raised = false

  /// How long a tip takes to fade.
  private static let fade = 0.2

  func body(content: Content) -> some View {
    content
      .overlay(alignment: arrow == .up ? .bottom : .top) {
        // Only the tip fades: an animation on the view itself would also animate whatever
        // changed with it, such as the board showing as the round's deal hands over.
        ZStack {
          if let text {
            Color.clear.frame(height: 0).overlay(alignment: arrow == .up ? (trailing ? .topTrailing : .topLeading) : (trailing ? .bottomTrailing : .bottomLeading)) {
              TipBubble(text: text, arrow: arrow, arrowAt: arrowAt, onDismiss: onDismiss)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: minWidth)
                .padding(arrow == .up ? .top : .bottom, 12 + drop).padding(.horizontal, inset)
            }
            .transition(.opacity)
          }
        }
        .animation(.easeOut(duration: Self.fade), value: text)
      }
      .background { if text != nil { AnyTouch(action: onDismiss) } }
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

/// A tip off the board put away: it never shows again.
@MainActor func dismissTip(_ store: AppStore, _ tip: GameTip?) {
  guard let tip else { return }
  withAnimation(.easeOut(duration: 0.15)) { store.see(tip) }
}

/// Calls `action` on the first touch anywhere in the window, and lets the
/// touch go on to whatever it landed on.
private struct AnyTouch: UIViewRepresentable {
  let action: () -> Void
  func makeUIView(context: Context) -> TouchWatcher { TouchWatcher() }
  func updateUIView(_ view: TouchWatcher, context: Context) { view.watch.action = action }
  static func dismantleUIView(_ view: TouchWatcher, coordinator: ()) { view.stop() }
}

/// An empty view that watches its window's touches while it is in one.
final class TouchWatcher: UIView {
  let watch = FirstTouch()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    stop()
    window?.addGestureRecognizer(watch)
  }

  func stop() { watch.view?.removeGestureRecognizer(watch) }
}

/// Sees a touch begin, then fails at once, so it never holds up, cancels or
/// delays any other gesture or control.
final class FirstTouch: UIGestureRecognizer {
  var action: () -> Void = {}

  init() {
    super.init(target: nil, action: nil)
    cancelsTouchesInView = false
    delaysTouchesBegan = false
    delaysTouchesEnded = false
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    let action = action
    // After this touch is handed out, so the tip leaving never disturbs it.
    DispatchQueue.main.async { action() }
    state = .failed
  }

  override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
