import ChessCore
import Game
import Model
import StoreKit
import SwiftUI
import UIKit

/// Whether this build shows the developer tools: Xcode and TestFlight builds do, App Store builds don't.
enum DevAccess {
  static func allowed() async -> Bool {
    #if DEBUG
      return true
    #else
      guard let result = try? await AppTransaction.shared else { return false }
      return result.unsafePayloadValue.environment != .production
    #endif
  }
}

/// The developer tools: profiles, the clock, and every part of the save a test needs set by hand.
/// Changes here log nothing and earn nothing.
struct DeveloperView: View {
  @Environment(Game.AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @Environment(\.dismiss) private var dismiss
  @State private var naming: Naming?
  @State private var typed = ""
  @State private var removing: Profile?
  /// The clock when the screen opened, so screens start over on the new day when it closes.
  @State private var daysAtOpen: Int?

  enum Naming: Equatable { case new, rename(Profile) }

  var body: some View {
    let state = store.state
    VStack(spacing: 0) {
      // The title and Close stay put while the rest scrolls.
      HStack {
        Text("Developer").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
        Spacer()
        Button { dismiss() } label: {
          Icon(name: "close", size: 18).foregroundStyle(Theme.text).frame(width: 36, height: 36).background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
      }
      .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          profiles
          section("Clock")
          ListCard {
            CountRow(label: "Days ahead", value: store.dev.daysAhead) { n in
              store.travel(days: n)
              Env.travel.set(n)
            }
          }
          section("Pawns")
          ListCard {
            HStack {
              Text("Balance").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Spacer()
              PawnAmount(count: state.pawns, size: 15)
            }
            .padding(.horizontal, 16).frame(minHeight: 54)
            HStack(spacing: 8) {
              ForEach([100, 1_000, 10_000], id: \.self) { n in
                chip("+\(n.formatted())") { store.devUpdate { $0.devAddPawns(n) } }
              }
              chip("Zero") { store.devUpdate { $0.pawns = 0 } }
            }
            .padding(12)
          }
          section("Pawn Shop")
          ListCard {
            HStack(spacing: 8) {
              chip("Own all") { store.devUpdate { $0.devSetAllOwned(true) } }
              chip("Own none") { store.devUpdate { $0.devSetAllOwned(false) } }
            }
            .padding(12)
            ForEach(SHOP.filter { $0.feature != nil }) { item in
              ToggleRow(label: item.name, on: state.unlocked.contains(item.id)) {
                store.devUpdate { $0.devSetOwned(item.id, !state.unlocked.contains(item.id)) }
              }
            }
          }
          section("App Store")
          ListCard {
            ToggleRow(
              label: "Ignore owned unlock", hint: "The unlock the App Store says you own isn't credited on this device.",
              on: store.dev.ignoreStoreUnlock
            ) { store.setDev { $0.ignoreStoreUnlock.toggle() } }
            actionRow("Forget credited purchases (\(state.credited.count))") { store.devUpdate { $0.credited = [] } }
          }
          openings
          tips
          streak
          growth
          section("Onboarding")
          ListCard {
            actionRow("Replay Welcome") {
              dismiss()
              store.devUpdate { $0.devReplayWelcome() }
            }
          }
          section("Save")
          ListCard {
            if let data = store.exportSave(), let json = String(data: data, encoding: .utf8) {
              ShareLink(item: json) {
                HStack {
                  Text("Export save").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                  Spacer()
                  Icon(name: "export", size: 16).foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
            actionRow("Paste save") {
              guard let text = UIPasteboard.general.string, store.importSave(Data(text.utf8)) else {
                toasts.show("That isn't a save this version reads")
                return
              }
              toasts.show("Save pasted in")
            }
            HStack {
              Text("Build").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Spacer()
              Text(buildText).font(.system(size: 14).monospacedDigit()).foregroundStyle(Theme.text3)
            }
            .padding(.horizontal, 16).frame(minHeight: 54)
          }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
      }
    }
    .onAppear { daysAtOpen = daysAtOpen ?? store.dev.daysAhead }
    .onDisappear {
      if daysAtOpen != store.dev.daysAhead { store.restartScreens() }
    }
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

  /* ── sections ── */

  @ViewBuilder private var profiles: some View {
    section("Profiles", first: true)
    ListCard {
      ForEach(store.profiles.profiles) { profile in profileRow(profile) }
    }
    // Making a profile is its own card, apart from the profiles themselves.
    ListCard {
      iconRow("plus", "New profile") {
        typed = ""
        naming = .new
      }
      iconRow("cards", "Duplicate \(store.profiles.activeProfile.name)") { store.duplicateProfile() }
    }
    .padding(.top, 10)
  }

  @ViewBuilder private var openings: some View {
    let state = store.state
    section("Openings")
    ListCard {
      ForEach(OPENING_LIST, id: \.id) { opening in
        let owned = state.ownsFamily(opening.id)
        ToggleRow(label: opening.name, hint: opening.color == .w ? "White" : "Black", on: owned) {
          store.devSetOpening(opening.id, owned: !owned)
        }
      }
    }
  }

  @ViewBuilder private var tips: some View {
    let settings = store.state.settings
    section("Tips")
    ListCard {
      HStack(spacing: 8) {
        chip("All unseen") { store.devUpdate { $0.devSetAllTips(seen: false) } }
        chip("All seen") { store.devUpdate { $0.devSetAllTips(seen: true) } }
      }
      .padding(12)
      ForEach(GameTip.allCases, id: \.self) { tip in
        ToggleRow(label: tip.rawValue, hint: tip.text, on: settings.seen(tip)) {
          store.devUpdate { $0.devSetTip(tip, seen: !settings.seen(tip)) }
        }
      }
    }
  }

  @ViewBuilder private var streak: some View {
    let streak = store.state.pawnStreak
    let last = lastPlayed(streak)
    section("Streak")
    ListCard {
      CountRow(label: "Days", value: streak.days, range: 0...365) { n in
        store.devUpdate { $0.devSetStreak(days: n, lastPlayed: last ?? 0) }
      }
      // A streak of 0 days has no last day.
      if streak.days > 0 {
        HStack(spacing: 12) {
          Text("Last day").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
          Spacer()
          SegmentedControl(
            value: Binding(
              get: { last ?? 4 },
              set: { back in store.devUpdate { $0.devSetStreak(days: streak.days, lastPlayed: back) } }
            ),
            options: [(0, "Today"), (1, "1 ago"), (2, "2 ago"), (3, "3 ago"), (4, "Older")]
          )
          .frame(maxWidth: 280)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
      }
    }
  }

  @ViewBuilder private var growth: some View {
    if let tree = store.tree {
      let state = store.state
      let gate = curveGate(state, tree)
      let open = openLevels(curveHoles(curveSides(state), tree.index, tree: tree), gate).sorted().map(String.init).joined(separator: ", ")
      section("Growth levels")
      ListCard {
        Text("Play games \(gate.games) · green \(gate.green) of \(gate.openings) · levels open \(open)")
          .font(.system(size: 14)).foregroundStyle(Theme.text2)
          .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: 8) {
          chip("+10 Play games") { store.devUpdate { $0.devAddPlayGames(10) } }
          chip("All green") {
            let owned = ownedOpenings(curveSides(state), tree)
            store.devUpdate { s in for o in owned { s.devSetForm(o.node.id, o.color, .green) } }
          }
        }
        .padding(12)
        ForEach(ownedOpenings(curveSides(state), tree), id: \.id) { owned in
          VStack(alignment: .leading, spacing: 8) {
            Text(owned.color == .w ? owned.node.name : "\(owned.node.name) (Black)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            SegmentedControl(
              value: Binding(
                get: { formLevel(state.form, owned.node.id, owned.color) },
                set: { level in store.devUpdate { $0.devSetForm(owned.node.id, owned.color, level) } }),
              options: [(DevForm.green, "Green"), (.middle, "Middle"), (.red, "Red"), (.none, "None")]
            )
          }
          .padding(.horizontal, 16).padding(.vertical, 10)
        }
      }
    }
  }

  /* ── pieces ── */

  private func section(_ title: String, first: Bool = false) -> some View {
    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      .padding(.horizontal, 4).padding(.top, first ? 16 : 24).padding(.bottom, 8)
  }

  private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
        .lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface3))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
    .buttonStyle(.plain)
  }

  /// A row that makes something, led by its icon and in the accent color.
  private func iconRow(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Icon(name: icon, size: 16)
        Text(label).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        Spacer()
      }
      .foregroundStyle(Theme.accent)
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func actionRow(_ label: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        Spacer()
      }
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var buildText: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build)) · save v\(SAVE_VERSION)"
  }

  /// How many days before today the streak's last day is; nil with no streak or further back.
  private func lastPlayed(_ streak: PawnStreak) -> Int? {
    guard let day = streak.day else { return nil }
    let now = Env.now()
    if day == dayKey(now) { return 0 }
    return daysBefore(now, 3).firstIndex(of: day).map { $0 + 1 }
  }

  private func formLevel(_ form: FormRecord, _ id: String, _ color: ChessCore.Color) -> DevForm {
    let scores = form.scores(id, color)
    guard !scores.isEmpty else { return .none }
    return DevForm.allCases.first { $0.answers == scores } ?? (isGreen(form, id, color) ? .green : .middle)
  }

  /* ── profiles ── */

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

/// A count with − and + on either side.
private struct CountRow: View {
  var label: String
  var value: Int
  var range: ClosedRange<Int> = 0...999
  var onChange: (Int) -> Void

  var body: some View {
    HStack(spacing: 10) {
      Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
      Spacer()
      step("\u{2212}", value - 1)
      Text("\(value)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text2)
        .frame(minWidth: 34)
      step("+", value + 1)
    }
    .padding(.horizontal, 16).frame(minHeight: 54)
  }

  private func step(_ label: String, _ to: Int) -> some View {
    Button { onChange(to) } label: {
      Text(label).font(.system(size: 18, weight: .semibold)).foregroundStyle(range.contains(to) ? Theme.text : Theme.text3)
        .frame(width: 40, height: 36)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface3))
    }
    .buttonStyle(.plain)
    .disabled(!range.contains(to))
  }
}
