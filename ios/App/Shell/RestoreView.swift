import Model
import SwiftUI

/// Restore from iCloud: other devices' backups, a profile at a time, or a whole device
/// when a fresh install first opens.
struct RestoreView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  /// The first-launch offer: backups already found, and Start fresh to skip them.
  var offered: [DeviceBackup]?

  @State private var backups: [DeviceBackup]?
  @State private var looked = false
  @State private var working = false
  @State private var failed = false
  @State private var asking: Ask?

  enum Ask: Identifiable {
    case one(BackedUpProfile, DeviceBackup)
    case all(DeviceBackup)
    var id: String {
      switch self {
      case .one(let profile, let device): "\(device.folder)/\(profile.id)"
      case .all(let device): device.folder
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Restore from iCloud").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          Spacer()
          if offered == nil {
            Button { dismiss() } label: {
              Icon(name: "close", size: 18).foregroundStyle(Theme.text).frame(width: 36, height: 36).background(Circle().fill(Theme.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
          }
        }
        if let backups {
          if backups.isEmpty {
            note(store.iCloudOff ? "iCloud is off on this device." : "No backups from other devices.")
          }
          ForEach(backups) { device in deviceCard(device) }
        } else if looked {
          note("iCloud is off on this device.")
        } else {
          ProgressView().tint(Theme.text2).frame(maxWidth: .infinity).padding(.top, 40)
        }
        if offered != nil {
          BigButton(label: "Start fresh", accent: false, soft: true) { dismiss() }.padding(.top, 28)
        }
      }
      .padding(20)
    }
    .disabled(working)
    .overlay { if working { ProgressView().tint(Theme.text) } }
    .task {
      if let offered {
        backups = offered
      } else {
        backups = await store.deviceBackups()
      }
      looked = true
    }
    .alert(askTitle, isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), presenting: asking) { ask in
      Button("Restore", role: .destructive) { run(ask) }
      Button("Cancel", role: .cancel) { asking = nil }
    } message: { ask in
      Text(askMessage(ask))
    }
    .alert("Couldn't restore", isPresented: $failed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("The backup couldn't be read. Try again once iCloud has finished downloading it.")
    }
  }

  private func deviceCard(_ device: DeviceBackup) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(device.manifest.device) · \(when(device.manifest.savedAt))").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
        .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
      ListCard {
        if offered != nil {
          row("Restore all", detail: nil) { asking = .all(device) }
        }
        ForEach(device.manifest.profiles) { profile in
          row(profile.name, detail: when(profile.savedAt)) { asking = .one(profile, device) }
        }
      }
    }
  }

  private func row(_ label: String, detail: String?, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        Spacer()
        if let detail { Text(detail).font(.system(size: 13)).foregroundStyle(Theme.text3) }
        Icon(name: "download", size: 16).foregroundStyle(Theme.text2)
      }
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func note(_ text: String) -> some View {
    Text(text).font(.system(size: 15)).foregroundStyle(Theme.text2).padding(.top, 24).padding(.horizontal, 4)
  }

  private func when(_ ms: Double) -> String {
    Date(timeIntervalSince1970: ms / 1000).formatted(.dateTime.month(.abbreviated).day().hour().minute())
  }

  private var askTitle: String {
    switch asking {
    case .one(let profile, _): "Restore \(profile.name)?"
    case .all: "Restore all profiles?"
    case nil: ""
    }
  }

  private func askMessage(_ ask: Ask) -> String {
    switch ask {
    case .one(let profile, _):
      store.profiles.profiles.contains { $0.id == profile.id }
        ? "This replaces \(profile.name) on this device with the backup."
        : "It's added as a new profile."
    case .all:
      "This replaces every profile on this device."
    }
  }

  private func run(_ ask: Ask) {
    asking = nil
    working = true
    Task {
      let done: Bool
      switch ask {
      case .one(let profile, let device): done = await store.restore(profile, from: device)
      case .all(let device): done = await store.restoreAll(device)
      }
      working = false
      if done {
        dismiss()
      } else {
        failed = true
      }
    }
  }
}
