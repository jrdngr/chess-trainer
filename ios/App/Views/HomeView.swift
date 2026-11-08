import ChessCore
import Model
import SwiftUI

/// Home: Play's next run on its button with the selection under it, Middlegame and
/// Endgames, Recommendations and Milestones. A mode tile starts the mode on
/// your saved settings; press and hold Middlegame for Start or Settings (its
/// setup screen first). After the first game, tips on the controls under Play,
/// on Play itself, then on the Playbook tab below, one per tap.
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
            .tip(tip, when: tip == .play, inset: 8) { nextHomeTip(store) }
          PlayFooter()
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
        // Over the tiles below, so a tip hanging past the card stays on top.
        .zIndex(1)
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
    // While a tip shows, a tap anywhere goes to the next one.
    .overlay {
      if tip != nil {
        SwiftUI.Color.black.opacity(0.001).contentShape(Rectangle())
          .onTapGesture { nextHomeTip(store) }
          .accessibilityHidden(true)
      }
    }
    // The Playbook tab is the system tab bar's second of four, just under Home.
    .overlay(alignment: .bottom) {
      if tip == .playbookTab {
        TipBubble(text: FirstGameTip.playbookTab.text, arrow: .down, arrowAt: 0.38) { nextHomeTip(store) }
          .padding(.horizontal, 16).padding(.bottom, 12)
      }
    }
    // Leaving Home by the tab its last tip points at puts that tip away.
    .onDisappear { if tip == .playbookTab { nextHomeTip(store) } }
    .sheet(isPresented: $settings) { SettingsSheet().presentationBackground(Theme.background) }
    .onAppear {
      guard store.takeSettingsHeld() else { return }
      var still = Transaction()
      still.disablesAnimations = true
      withTransaction(still) { settings = true }
    }
  }

  private var tip: FirstGameTip? { homeTip(store.state.settings.tips) }

  /// What Play would start with, said on its button, or that there is nothing to play yet.
  @ViewBuilder private var autopilot: some View {
    let selection = store.peekRoundSelection()
    if let round = nextRound(store.state, tree, selection, store.autoHistory) {
      let rep = store.state.repertoireList.first { $0.color == round.pick.color }
      // Freeform always starts from move one, so its button shows no segments.
      let span = store.state.settings.start == .freeform ? nil : roundSpan(rep, round.pick, round.at)
      Button { onOpen(.autopilot) } label: {
        AutopilotPlate(
          name: store.catalog.map { selectionTrail(tree, $0, round.pick.opening.id).last ?? "" } ?? "",
          color: round.pick.color, span: span, attached: true)
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
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20))
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

/// Play's next run on Home's button: the opening, the move the game starts
/// from, and how far into your prep that is along the bottom.
struct AutopilotPlate: View {
  let name: String
  let color: ChessCore.Color
  let span: PrepSpan?
  /// On Home, the top of one block with the selection under it: no side square
  /// (the side shows right below), square bottom corners.
  var attached = false

  /// Your move the game starts at: the first one not played for you.
  private var from: Int { (span?.played ?? 0) + 1 }

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center, spacing: 12) {
        if !attached { SideSquare(color: color) }
        VStack(alignment: .leading, spacing: 3) {
          Text(name).font(.system(size: 21, weight: .heavy)).foregroundStyle(Theme.text)
            .multilineTextAlignment(.leading)
          Text("From move \(from)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2)
        }
        Spacer(minLength: 0)
        Image(systemName: "play.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.accentInk)
          .frame(width: 48, height: 48)
          .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
          .accessibilityHidden(true)
      }
      .padding(.leading, 18).padding(.trailing, 12).padding(.vertical, 12)
      .background(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing))
      .clipShape(UnevenRoundedRectangle(
        topLeadingRadius: 20, bottomLeadingRadius: attached ? 0 : 20, bottomTrailingRadius: attached ? 0 : 20, topTrailingRadius: 20))
      PrepSegmentsView(span: span, height: 4).padding(.horizontal, 18).padding(.top, attached ? 0 : 8)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Play \(name), from move \(from)")
  }
}

/// Home's tip put away, for the next one.
@MainActor private func nextHomeTip(_ store: AppStore) {
  dismissTip(store, homeTip(store.state.settings.tips))
}

/// Under Play's button on Home: the side, how runs start, and the opening.
private struct PlayFooter: View {
  @Environment(AppStore.self) private var store
  @State private var picking: SelectionPicking?

  var body: some View {
    let settings = store.state.settings
    let tip = homeTip(settings.tips)
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
      .tip(tip, when: tip == .opening) { nextHomeTip(store) }
    }
    .padding(8)
    .buttonStyle(.plain)
    .selectionSheets($picking)
  }
}
