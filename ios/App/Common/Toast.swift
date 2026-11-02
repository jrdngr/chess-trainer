import Observation
import SwiftUI

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
        .transition(.asymmetric(insertion: .offset(y: 12).combined(with: .opacity), removal: .identity))
        .padding(.bottom, 76)
      }
    }
    .animation(reduceMotion ? nil : Motion.arrive(0.22), value: toasts.current?.id)
    .allowsHitTesting(toasts.current?.action != nil)
  }
}
