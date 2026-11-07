import Model
import SwiftUI

/// Settings: the board, Autopilot's extras, the engine, profiles, iCloud backup and Export.
struct SettingsSheet: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var exporting = false
  @State private var restoring = false
  /// The name prompt open: a new profile, or the profile being renamed.
  @State private var naming: Naming?
  @State private var typed = ""
  /// The profile waiting on a delete (or, as the last one, a reset) to be confirmed.
  @State private var removing: Profile?

  enum Naming: Equatable { case new, rename(Profile) }

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
        section("Board", first: true)
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
        section("Play")
        ListCard {
          ToggleRow(label: "Move scores", hint: "What each move the engine judges cost you, in centipawns, over its square",
                    on: settings.autopilot.moveScores) { store.update { $0.settings.autopilot.moveScores.toggle() } }
          FillSizeRow(value: settings.movesPerFill) { n in store.update { $0.settings.movesPerFill = n } }
        }
        section("Engine")
        ListCard {
          ToggleRow(label: "Engine", hint: "Analysis's lines",
                    on: settings.engineEnabled) { store.update { $0.settings.engineEnabled.toggle() } }
        }
        section("Profiles")
        ListCard {
          ForEach(store.profiles.profiles) { profile in profileRow(profile) }
          Button {
            typed = ""
            naming = .new
          } label: {
            HStack(spacing: 10) {
              Icon(name: "plus", size: 16).foregroundStyle(Theme.text2)
              Text("New profile").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Spacer()
            }
            .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
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
      }
      .padding(20)
    }
    .sheet(isPresented: $exporting) { ExportView().presentationBackground(Theme.background) }
    .sheet(isPresented: $restoring) { RestoreView().presentationBackground(Theme.background) }
    .alert(naming == .new ? "New profile" : "Rename profile", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
      TextField("Name", text: $typed)
      Button(naming == .new ? "Create" : "Rename") { finishNaming() }
      Button("Cancel", role: .cancel) { naming = nil }
    }
    .alert(removeTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
      Button(lastProfile ? "Reset" : "Delete", role: .destructive) { finishRemoving() }
      Button("Cancel", role: .cancel) { removing = nil }
    } message: {
      Text("This can't be undone.")
    }
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

  private var lastProfile: Bool { store.profiles.profiles.count == 1 }

  private var removeTitle: String {
    guard let removing else { return "" }
    return "\(lastProfile ? "Reset" : "Delete") \(removing.name)?"
  }

  /// A profile: tap to switch to it, long-press to rename or delete it.
  private func profileRow(_ profile: Profile) -> some View {
    let active = profile.id == store.profiles.active
    return Button {
      guard !active else { return }
      dismiss()
      store.switchProfile(profile.id)
    } label: {
      HStack {
        Text(profile.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        Spacer()
        if active { Icon(name: "check", size: 16).foregroundStyle(Theme.good) }
      }
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      Button("Rename") {
        typed = profile.name
        naming = .rename(profile)
      }
      Button(lastProfile ? "Reset" : "Delete", role: .destructive) { removing = profile }
    }
  }

  private func finishNaming() {
    switch naming {
    case .new:
      dismiss()
      store.createProfile(typed)
    case .rename(let profile):
      store.renameProfile(profile.id, typed)
    case nil:
      break
    }
    naming = nil
  }

  private func finishRemoving() {
    guard let profile = removing else { return }
    removing = nil
    if lastProfile {
      dismiss()
      store.resetProfile()
    } else {
      store.deleteProfile(profile.id)
    }
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
/// Moves per fill: how many of your moves a run or a recommendation adds at
/// once, and so how many runs go by between new moves.
struct FillSizeRow: View {
  var value: Int
  var onChange: (Int) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("Moves per fill").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
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
