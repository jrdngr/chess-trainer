import ChessCore
import Model
import SwiftUI

/// Home: the selection, Play's next run on its button, Middlegame and
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
        SelectionBar {
          Button { settings = true } label: {
            Icon(name: "gear", size: 20).foregroundStyle(Theme.text2).padding(.horizontal, 11).frame(minWidth: 44, minHeight: 44)
              .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
              .contentShape(RoundedRectangle(cornerRadius: 14))
          }
          .buttonStyle(.plain)
        }
        .padding(.top, 2).padding(.bottom, 12)
        ScoreStrip().padding(.bottom, 12)
        autopilot.padding(.bottom, 10)
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
      // My Playbook always starts from move one, so its button shows no segments.
      let span = selection.opening == ANY_OPENING ? nil : roundSpan(rep, round.pick, round.at)
      Button { onOpen(.autopilot) } label: {
        AutopilotPlate(
          name: store.catalog.map { selectionTrail(tree, $0, round.pick.opening.id).last ?? "" } ?? "",
          sans: round.pick.opening.sans, color: round.pick.color, span: span)
          .contentShape(RoundedRectangle(cornerRadius: 20))
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
        .background(RoundedRectangle(cornerRadius: 20).fill(LinearGradient(
          colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
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

  var body: some View {
    HStack(alignment: .center, spacing: 9) {
      SideSquare(color: color)
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
      PrepSegmentsView(span: span, height: 4).padding(.top, 0).background(Theme.background).padding(.horizontal, 18)
    }
    .clipShape(RoundedRectangle(cornerRadius: 20))
  }
}
