import Game
import Model
import SwiftUI

/// Restore from iCloud: a profile at a time from any device's backup, its latest save or an
/// older day's, or a whole device when a fresh install first opens.
struct RestoreView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(Toasts.self) private var toasts
  /// The first-launch offer: backups already found, and Start fresh to skip them.
  var offered: [DeviceBackup]?

  @State private var backups: [DeviceBackup]?
  @State private var looked = false
  @State private var working = false
  @State private var failed = false
  /// A profile waiting on which copy to restore.
  @State private var picking: (profile: BackedUpProfile, device: DeviceBackup)?
  /// A whole device waiting on Restore all to be confirmed.
  @State private var restoringAll: DeviceBackup?

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
          if backups.isEmpty { note("No backups yet.") }
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
    .confirmationDialog(
      picking.map { "Restore \($0.profile.name)?" } ?? "",
      isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
      titleVisibility: .visible, presenting: picking
    ) { pick in
      Button("Latest, \(when(pick.profile.savedAt))") { restoreOne(pick.profile, pick.device, day: nil) }
      ForEach(pick.profile.olderDays, id: \.self) { day in
        Button(dayLabel(day)) { restoreOne(pick.profile, pick.device, day: day) }
      }
      Button("Cancel", role: .cancel) { picking = nil }
    } message: { pick in
      Text(
        store.profiles.profiles.contains { $0.id == pick.profile.id }
          ? "This replaces \(pick.profile.name) on this device."
          : "It's added as a new profile.")
    }
    .alert("Restore all profiles?", isPresented: Binding(get: { restoringAll != nil }, set: { if !$0 { restoringAll = nil } }), presenting: restoringAll) { device in
      Button("Restore", role: .destructive) { run { await store.restoreAll(device) } }
      Button("Cancel", role: .cancel) { restoringAll = nil }
    } message: { _ in
      Text("This replaces every profile on this device.")
    }
    .alert("Couldn't restore", isPresented: $failed) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("No copy in the backup could be read. Try again once iCloud has finished downloading it.")
    }
  }

  private func deviceCard(_ device: DeviceBackup) -> some View {
    let own = device.folder == store.device.folder
    return VStack(alignment: .leading, spacing: 0) {
      Text("\(own ? "This \(device.manifest.device)" : device.manifest.device) · \(when(device.manifest.savedAt))")
        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
        .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
      ListCard {
        if offered != nil {
          row("Restore all", detail: nil) { restoringAll = device }
        }
        ForEach(device.manifest.profiles) { profile in
          row(profile.name, detail: when(profile.savedAt)) { picking = (profile, device) }
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

  /// "Nov 4" for a snapshot's `yyyy-MM-dd`.
  private func dayLabel(_ day: String) -> String {
    let parse = DateFormatter()
    parse.locale = Locale(identifier: "en_US_POSIX")
    parse.dateFormat = "yyyy-MM-dd"
    guard let date = parse.date(from: day) else { return day }
    return "End of \(date.formatted(.dateTime.month(.abbreviated).day()))"
  }

  private func restoreOne(_ profile: BackedUpProfile, _ device: DeviceBackup, day: String?) {
    picking = nil
    run { await store.restore(profile, from: device, day: day) }
  }

  private func run(_ restore: @escaping @MainActor () async -> RestoreOutcome) {
    restoringAll = nil
    working = true
    Task {
      let outcome = await restore()
      working = false
      switch outcome {
      case .failed: failed = true
      case .restored(let older):
        // A restore opens the profile and starts every screen over, so the note goes in a toast.
        if let older { toasts.show("Newer copy unreadable. \(dayLabel(older)) restored") }
        dismiss()
      }
    }
  }
}
