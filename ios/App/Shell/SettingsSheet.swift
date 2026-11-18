import Engine
import Game
import Model
import SwiftUI

/// Settings: the board, Play's extras, iCloud backup and Export, and in Xcode and TestFlight builds
/// the developer tools.
struct SettingsSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var exporting = false
  @State private var restoring = false
  /// Xcode and TestFlight builds: the Developer row shows.
  @State private var devTools = false
  @State private var developing = false

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
          .accessibilityLabel("Close")
        }
        section("Board", first: true)
        ListCard {
          SegmentedControl(
            value: Binding(get: { settings.boardTheme }, set: { t in store.update { $0.settings.boardTheme = t } }),
            options: BoardTheme.allCases.map { ($0, $0.rawValue.prefix(1).uppercased() + $0.rawValue.dropFirst()) }
          )
          .padding(.horizontal, 16).padding(.vertical, 10)
          ToggleRow(label: "Coordinates", on: settings.showCoordinates) { store.update { $0.settings.showCoordinates.toggle() } }
          ToggleRow(label: "Haptics", on: settings.hapticFeedback) { store.update { $0.settings.hapticFeedback.toggle() } }
          ToggleRow(label: "Replay", on: settings.autoplay) { store.update { $0.settings.autoplay.toggle() } }
        }
        section("Play")
        ListCard {
          ToggleRow(label: "Move scores", on: settings.play.moveScores) { store.update { $0.settings.play.moveScores.toggle() } }
          FillSizeRow(value: settings.movesPerFill) { n in store.update { $0.settings.movesPerFill = n } }
          HStack(spacing: 12) {
            Text("Opening names").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            SegmentedControl(
              value: Binding(get: { settings.openingNames }, set: { n in store.update { $0.settings.openingNames = n } }),
              options: [(OpeningNames.family, "Family"), (.book, "Book name")]
            )
            .frame(maxWidth: 200)
          }
          .padding(.horizontal, 16).padding(.vertical, 10)
        }
        section("iCloud")
        ListCard {
          HStack {
            Text("Last backup").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Text(lastBackup).font(.system(size: 14)).foregroundStyle(store.iCloudOff || store.backupHeld ? Theme.warn : Theme.text3)
          }
          .padding(.horizontal, 16).frame(minHeight: 54)
          Button { restoring = true } label: {
            HStack {
              Text("Restore from iCloud").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Spacer()
              Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        ListCard {
          Button { exporting = true } label: {
            HStack {
              Text("Export").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Spacer()
              Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 24)
        if devTools {
          ListCard {
            Button { developing = true } label: {
              HStack {
                Text("Developer").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
              }
              .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          .padding(.top, 24)
        }
      }
      .padding(20)
    }
    .task {
      devTools = await DevAccess.allowed()
      if devTools && HomeView.debugDeveloper { developing = true }
    }
    .sheet(isPresented: $developing) { DeveloperView().presentationBackground(Theme.background) }
    .sheet(isPresented: $exporting) { ExportView().presentationBackground(Theme.background) }
    .sheet(isPresented: $restoring) { RestoreView().presentationBackground(Theme.background) }
  }

  private func section(_ title: String, first: Bool = false) -> some View {
    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      .padding(.horizontal, 4).padding(.top, first ? 16 : 24).padding(.bottom, 8)
  }

  private var lastBackup: String {
    if store.backupHeld { return "Paused" }
    if store.iCloudOff { return "iCloud off" }
    let at = store.device.manifest.savedAt
    guard at > 0 else { return "None yet" }
    return Date(timeIntervalSince1970: at / 1000).formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
/// New moves per round: how many of your moves a run or a recommendation adds at
/// once, and so how many runs go by between new moves.
struct FillSizeRow: View {
  var value: Int
  var onChange: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("New moves per round").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        Spacer()
        Text("\(value)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text2)
      }
      Slider(
        value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
        in: Double(MOVES_PER_FILL_RANGE.lowerBound)...Double(MOVES_PER_FILL_RANGE.upperBound), step: 1
      )
      .tint(Theme.accent)
    }
    .padding(.horizontal, 16).padding(.vertical, 12)
  }
}

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
