import Model
import SwiftUI

/// Settings: the board, Autopilot's extras, the engine, sync and data.
struct SettingsSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  /// The reset waiting to be confirmed, if either: one at a time.
  @State private var armed: Reset?
  @State private var intro = false

  enum Reset { case progress, all }

  var body: some View {
    let settings = store.state.settings
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Settings").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          Spacer()
          Button { dismiss() } label: {
            Icon(name: "close", size: 18).foregroundStyle(Theme.text).frame(width: 36, height: 36).background(Circle().fill(Theme.surface))
          }
          .buttonStyle(.plain)
        }
        ListCard {
          Button { intro = true } label: {
            HStack {
              Text("How it works").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Spacer()
              Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 16)
        section("Board")
        ListCard {
          SegmentedControl(
            value: Binding(get: { settings.boardTheme }, set: { t in store.update { $0.settings.boardTheme = t } }),
            options: BoardTheme.allCases.map { ($0, $0.rawValue.prefix(1).uppercased() + $0.rawValue.dropFirst()) }
          )
          .padding(.horizontal, 16).padding(.vertical, 10)
          ToggleRow(label: "Coordinates", on: settings.showCoordinates) { store.update { $0.settings.showCoordinates.toggle() } }
          ToggleRow(label: "Haptics", on: settings.hapticFeedback) { store.update { $0.settings.hapticFeedback.toggle() } }
          ToggleRow(label: "Autoplay", on: settings.autoplay) { store.update { $0.settings.autoplay.toggle() } }
        }
        section("Autopilot")
        ListCard {
          ToggleRow(label: "Move scores", hint: "What each move the engine judges cost you, in centipawns, over its square",
                    on: settings.autopilot.moveScores) { store.update { $0.settings.autopilot.moveScores.toggle() } }
          ToggleRow(label: "Board glow", hint: "The board's edge tints green when you are better and red when you are worse",
                    on: settings.autopilot.boardGlow) { store.update { $0.settings.autopilot.boardGlow.toggle() } }
        }
        section("Engine")
        ListCard {
          ToggleRow(label: "Run Stockfish", hint: "Used by Analysis and by Drill's explanations, with a built-in evaluator as fallback",
                    on: settings.engineEnabled) { store.update { $0.settings.engineEnabled.toggle() } }
        }
        Text("How each mode plays is set on that mode's own screen.").font(.system(size: 12.5)).foregroundStyle(Theme.text3)
          .padding(.horizontal, 4).padding(.top, 8)
        section("Sync")
        ListCard {
          ToggleRow(label: "Sync across devices", hint: settings.cloudSync ? describeStatus(.unavailable) : "Saved on this device",
                    on: settings.cloudSync) { store.update { $0.settings.cloudSync.toggle() } }
        }
        section("Data")
        ListCard {
          resetRow(.progress, "Reset progress", color: Theme.text) { $0.resetProgress() }
          resetRow(.all, "Reset everything", color: Theme.bad) { $0.resetAll() }
        }
      }
      .padding(20)
    }
    .onDisappear { armed = nil }
    .fullScreenCover(isPresented: $intro) { IntroPagesView { intro = false } }
  }

  private func section(_ title: String, first: Bool = false) -> some View {
    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      .padding(.horizontal, 4).padding(.top, first ? 16 : 24).padding(.bottom, 8)
  }

  private func resetRow(_ which: Reset, _ title: String, color: SwiftUI.Color, _ reset: @escaping (inout AppState) -> Void) -> some View {
    Button {
      if armed != which {
        armed = which
        return
      }
      store.update(reset)
      armed = nil
      if which == .all { dismiss() }
    } label: {
      Text(armed == which ? "Tap again to confirm" : title).font(.system(size: 15, weight: .semibold)).foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(.horizontal, 16).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A rounded list of rows with lines between them.
struct ListCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { rows in
        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
          if i > 0 { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
          row
        }
      }
    }
    .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    .clipShape(RoundedRectangle(cornerRadius: 18))
  }
}

/// A setting that is on or off.
struct ToggleRow: View {
  var label: String
  var hint: String?
  var on: Bool
  var onToggle: () -> Void

  var body: some View {
    Button(action: onToggle) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
          if let hint { Text(hint).font(.system(size: 12.5)).foregroundStyle(Theme.text3).multilineTextAlignment(.leading) }
        }
        Spacer()
        Capsule().fill(on ? Theme.good : Theme.surface3).frame(width: 50, height: 30)
          .overlay(alignment: on ? .trailing : .leading) { Circle().fill(.white).padding(3) }
          .animation(.easeOut(duration: 0.15), value: on)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
