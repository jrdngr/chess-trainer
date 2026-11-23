import Observation
import SwiftUI
import UIKit

/// A short message along the bottom, with an action such as Undo.
@MainActor @Observable
final class Toasts {
  struct Toast: Identifiable {
    let id = UUID()
    var message: String
    var action: (label: String, run: () -> Void)?
  }

  private(set) var current: Toast?

  /// Shows a message: 2 seconds, or 5 with an action.
  func show(_ message: String, action: (label: String, run: () -> Void)? = nil) {
    let toast = Toast(message: message, action: action)
    current = toast
    Task {
      try? await Task.sleep(for: .seconds(action == nil ? 2 : 5))
      if current?.id == toast.id { current = nil }
    }
  }

  func run() {
    current?.action?.run()
    current = nil
  }
}

/// Where toasts appear, over everything.
struct ToastHost: View {
  @Environment(Toasts.self) private var toasts
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack {
      Spacer()
      if let toast = toasts.current {
        HStack(spacing: 14) {
          Text(toast.message).font(.system(size: 14, weight: .semibold)).foregroundStyle(SwiftUI.Color(hex: 0x0b0b0e))
          if let action = toast.action {
            Button { toasts.run() } label: {
              Text(action.label)
                .font(.system(size: 13.5, weight: .bold)).foregroundStyle(SwiftUI.Color(hex: 0xf5f5f7))
                .padding(.horizontal, 14).padding(.vertical, 7).background(Capsule().fill(SwiftUI.Color(hex: 0x0b0b0e)))
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.leading, 18).padding(.trailing, toast.action == nil ? 18 : 6).padding(.vertical, toast.action == nil ? 11 : 6)
        .background(Capsule().fill(SwiftUI.Color(hex: 0xf5f5f7)))
        .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        // Where the toast is, so its window takes taps there and nowhere else.
        .background(GeometryReader { g in Color.clear.preference(key: ToastFrameKey.self, value: g.frame(in: .global)) })
        .transition(.asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .identity))
        .padding(.bottom, 76)
      }
    }
    .animation(reduceMotion ? nil : Motion.arrive(0.22), value: toasts.current?.id)
    .allowsHitTesting(toasts.current?.action != nil)
  }
}

/// The toast's frame on screen; empty with no toast.
private struct ToastFrameKey: PreferenceKey {
  static let defaultValue = CGRect.zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

extension View {
  /// Toasts in a window of their own, above every other and so above any sheet.
  func toastWindow(_ toasts: Toasts) -> some View { modifier(ToastWindow(toasts: toasts)) }
}

private struct ToastWindow: ViewModifier {
  let toasts: Toasts
  @State private var window: ToastUIWindow?

  func body(content: Content) -> some View {
    content.background(SceneFinder { scene in
      guard window == nil else { return }
      let made = ToastUIWindow(windowScene: scene)
      let host = UIHostingController(rootView: WindowToasts(toasts: toasts, window: made))
      host.view.backgroundColor = .clear
      made.rootViewController = host
      made.windowLevel = .alert + 1
      made.backgroundColor = .clear
      made.isHidden = false
      window = made
    })
    // A new session builds the screens again, with a window of their own.
    .onDisappear {
      window?.isHidden = true
      window = nil
    }
  }
}

/// The toast host in its window, telling the window where the toast is.
private struct WindowToasts: View {
  let toasts: Toasts
  let window: ToastUIWindow

  var body: some View {
    ToastHost().environment(toasts)
      .preferredColorScheme(.dark)
      .onPreferenceChange(ToastFrameKey.self) { rect in
        MainActor.assumeIsolated { window.toastFrame = toasts.current == nil ? .zero : rect }
      }
  }
}

/// A window that takes only the taps on its toast; every other tap goes through to the app below.
private final class ToastUIWindow: UIWindow {
  var toastFrame = CGRect.zero

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard toastFrame.contains(point) else { return nil }
    return super.hitTest(point, with: event)
  }
}

/// Finds the window scene this view is shown in.
private struct SceneFinder: UIViewRepresentable {
  let found: (UIWindowScene) -> Void

  func makeUIView(context: Context) -> FinderView { FinderView(found: found) }
  func updateUIView(_ view: FinderView, context: Context) {}

  final class FinderView: UIView {
    let found: (UIWindowScene) -> Void
    init(found: @escaping (UIWindowScene) -> Void) {
      self.found = found
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      guard let scene = window?.windowScene else { return }
      Task { @MainActor in self.found(scene) }
    }
  }
}
