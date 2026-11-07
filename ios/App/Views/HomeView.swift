import ChessCore
import Model
import SwiftUI

/// Home: Play's next run on its button with the selection under it, Middlegame and
/// Endgames, Recommendations and Milestones. A mode tile starts the mode on
/// your saved settings; press and hold Middlegame for Start or Settings (its
/// setup screen first).
struct HomeView: View {
  let tree: OpeningTree
  let onOpen: (Mode) -> Void
  /// Open a mode on its setup screen.
  let onSetup: (Mode) -> Void
  /// Fill a recommendation in Growth.
  let onGap: (Gap) -> Void
  /// Go to the Playbook tab, when there is nothing to play yet.
  let onPlaybook: () -> Void
  @Environment(AppStore.self) private var store
  @State private var settings = false

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        HStack {
          Spacer()
          Button { settings = true } label: {
            Icon(name: "gear", size: 20).foregroundStyle(Theme.text2).padding(.horizontal, 11).frame(minWidth: 44, minHeight: 44)
              .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
              .contentShape(RoundedRectangle(cornerRadius: 14))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Settings")
        }
        .padding(.top, 2).padding(.bottom, 12)
        VStack(spacing: 0) {
          autopilot
          PlayFooter()
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.bottom, 10)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
          tile("Middlegame", "middlegame", .middlegame, held: true)
          tile("Endgames", "flag", .endgame)
        }
        VStack(spacing: 10) {
          RecommendationsCard(tree: tree, onPick: onGap)
          MilestonesCard()
        }
        .padding(.top, 10)
      }
      .padding(.horizontal, 16).padding(.bottom, 24)
    }
    .sheet(isPresented: $settings) { SettingsSheet().presentationBackground(Theme.background) }
    .fullScreenCover(isPresented: Binding(
      get: { homeCardPending(store.state.settings.tips) },
      set: { shown in if !shown { store.update { $0.settings.tips = [] } } }
    )) {
      PlayHowPage { store.update { $0.settings.tips = [] } }
    }
    .onAppear {
      guard store.takeSettingsHeld() else { return }
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) { settings = true }
    }
  }

  /// What Play would start with, said on its button, or that there is nothing to play yet.
  @ViewBuilder private var autopilot: some View {
    let selection = store.peekRoundSelection()
    if let round = nextRound(store.state, tree, selection, AutoHistory()) {
      let rep = store.state.repertoireList.first { $0.color == round.pick.color }
      // Freeform always starts from move one, so its button shows no segments.
      let span = store.state.settings.start == .freeform ? nil : roundSpan(rep, round.pick, round.at)
      Button { onOpen(.autopilot) } label: {
        AutopilotPlate(
          name: store.catalog.map { selectionTrail(tree, $0, round.pick.opening.id).last ?? "" } ?? "",
          sans: round.pick.opening.sans, color: round.pick.color, span: span, attached: true)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    } else {
      Button { onPlaybook() } label: {
        HStack(spacing: 13) {
          Icon(name: "bolt", size: 22).foregroundStyle(Theme.accentInk).frame(width: 42, height: 42)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accent))
          VStack(alignment: .leading, spacing: 1) {
            Text("PLAY").font(.system(size: 10.5, weight: .heavy)).tracking(0.9).foregroundStyle(Theme.accent)
            Text("Build").font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
            Text("Nothing to play yet \u{00b7} add an opening").font(.system(size: 12.5)).foregroundStyle(Theme.text2).lineLimit(1)
          }
          Spacer()
          Icon(name: "chevron", size: 20).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .background(LinearGradient(
          colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
      }
      .buttonStyle(.plain)
    }
  }

  /// A mode's tile. `held`: press and hold offers Start and Settings.
  @ViewBuilder private func tile(_ name: String, _ icon: String, _ mode: Mode, held: Bool = false) -> some View {
    let button = Button { onOpen(mode) } label: {
      HStack(spacing: 10) {
        Icon(name: icon, size: 20).foregroundStyle(Theme.accent)
        Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 12).frame(minHeight: 56)
      .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
      .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
    }
    .buttonStyle(.plain)
    if held {
      button.contextMenu {
        Button { onOpen(mode) } label: { Label("Start", systemImage: "play.fill") }
        Button { onSetup(mode) } label: { Label("Settings", systemImage: "slider.horizontal.3") }
      }
    } else {
      button
    }
  }
}

/// Play's next run on Home's button: the opening's position faded in
/// behind its name, how far into your prep it starts along the bottom edge.
struct AutopilotPlate: View {
  let name: String
  let sans: [String]
  let color: ChessCore.Color
  let span: PrepSpan?
  /// On Home, the top of one block with the selection under it: no side square
  /// (the side shows right below), square bottom corners.
  var attached = false

  var body: some View {
    HStack(alignment: .center, spacing: 9) {
      if !attached { SideSquare(color: color) }
      Text(name).font(.system(size: 21, weight: .heavy)).foregroundStyle(Theme.text).shadow(color: .black.opacity(0.6), radius: 5, y: 2)
        .multilineTextAlignment(.leading)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20).padding(.top, 42).padding(.bottom, 16)
    .frame(maxWidth: .infinity, minHeight: 96)
    .background(alignment: .topTrailing) {
      MiniBoard(sans: sans, orientation: color, size: 176, lastMove: true)
        .opacity(0.85).rotationEffect(.degrees(-8))
        .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5)))
        // Gone before the plate's bottom edge, so no piece peeks past the prep bar.
        .mask(LinearGradient(colors: [.black, .clear], startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: UnitPoint(x: 0.5, y: 0.72)))
        .offset(x: 14, y: -40)
        .allowsHitTesting(false)
    }
    .background(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
    .overlay(alignment: .topLeading) {
      HStack(spacing: 4) {
        Icon(name: "bolt", size: 11, filled: true)
        Text("PLAY").font(.system(size: 11, weight: .heavy)).tracking(0.66)
      }
      .foregroundStyle(SwiftUI.Color(hex: 0xc4c5ff)).padding(.leading, 6).padding(.trailing, 8).padding(.vertical, 3)
      .background(Capsule().fill(SwiftUI.Color(red: 139 / 255, green: 140 / 255, blue: 248 / 255).opacity(0.2)))
      .padding(.top, 10).padding(.leading, 14)
    }
    .overlay(alignment: .bottom) {
      PrepSegmentsView(span: span, height: 4).padding(.top, 0).background(attached ? Theme.surface : Theme.background).padding(.horizontal, 18)
    }
    .clipShape(UnevenRoundedRectangle(
      topLeadingRadius: 20, bottomLeadingRadius: attached ? 0 : 20, bottomTrailingRadius: attached ? 0 : 20, topTrailingRadius: 20))
  }
}

/// Under Play's button on Home: the side, how runs start, and the opening.
private struct PlayFooter: View {
  @Environment(AppStore.self) private var store
  @State private var picking: SelectionPicking?

  var body: some View {
    let settings = store.state.settings
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        Button { picking = .color } label: {
          HStack(spacing: 6) {
            ColorSquare(choice: settings.selection.color, size: 20)
            Icon(name: "down", size: 14).foregroundStyle(Theme.text3)
          }
          .padding(.leading, 12).padding(.trailing, 10).frame(minHeight: 44)
          .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
          .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Side")
        SegmentedControl(
          value: Binding(get: { settings.start }, set: { start in store.update { $0.settings.start = start } }),
          options: [(RunStart.freeform, "Freeform"), (RunStart.drill, "Drill")], track: Theme.background)
      }
      Button { picking = .quick } label: {
        HStack(spacing: 8) {
          SelectionTrail(opening: settings.selection.opening).frame(maxWidth: .infinity, alignment: .leading)
          Icon(name: "down", size: 16).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
      }
    }
    .padding(8)
    .buttonStyle(.plain)
    .selectionSheets($picking)
  }
}

/// After the first game, in the welcome's style: how a game goes from here, until Got it.
private struct PlayHowPage: View {
  let onDone: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        card(["e4", "c5"], .b).rotationEffect(.degrees(-11)).offset(x: -78, y: 14).opacity(0.75)
        card(["d4", "d5", "c4", "e6"], .b).rotationEffect(.degrees(11)).offset(x: 78, y: 14).opacity(0.75)
        card(["e4", "e5", "Nf3", "Nc6", "Bc4"], .w)
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 1.5))
      }
      .frame(maxWidth: .infinity).frame(height: 190).padding(.top, 40)
      Text(FirstGameTip.end.text).font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        .padding(.top, 24)
      VStack(alignment: .leading, spacing: 16) {
        WelcomePoint(glyph: "\u{265E}", text: "Each game plays a line from your Playbook.")
        WelcomePoint(glyph: "\u{265F}\u{FE0E}", text: "Once you know a line, the game pauses to let you add new moves.")
        WelcomePoint(glyph: "\u{265A}", text: "See how far you get before you blunder!")
      }
      .padding(.top, 22)
      Spacer(minLength: 0)
      BigButton(label: "Got it", action: onDone).padding(.bottom, 8)
    }
    .padding(.horizontal, 20)
    .background(Theme.background.ignoresSafeArea())
  }

  private func card(_ sans: [String], _ color: ChessCore.Color) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      MiniBoard(sans: sans, orientation: color, size: 116, lastMove: true).clipShape(RoundedRectangle(cornerRadius: 6))
      Capsule().fill(Theme.surface3).frame(width: 80, height: 6)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    .shadow(color: .black.opacity(0.55), radius: 15, y: 14)
  }
}
