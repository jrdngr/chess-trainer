import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Growth's lobby: where the work is, the settings it is found with, and
/// where a side with nothing in it starts. `Lobby.tsx`.
struct GrowthLobbyView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onStart: (GrowthRow) -> Void
  let onExit: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var memo = Memo<GrowthLobby>()

  var body: some View {
    let lobby = current
    let prefs = store.state.settings.growth
    VStack(spacing: 0) {
      PlayAppBar(title: "Growth", subtitle: lobby.subtitle, onClose: onExit) { EmptyView() }
      ScrollView {
        VStack(spacing: 0) {
          SelectionBar()
          starts(lobby)
          work(lobby, prefs)
          GrowthSettings(prefs: prefs) { change in store.update { change(&$0.settings.growth) } }
          if lobby.hasMoves { have(lobby) }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
    }
    .task(id: lobby.asking) { if !lobby.asking.isEmpty { GrowthEngine.shared.ask(lobby.asking) } }
  }

  /// The lobby, worked out again only when what it reads changes.
  private var current: GrowthLobby {
    let state = store.state
    let reps = state.repertoireList.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ",")
    let key = "\(reps)|\(state.settings.selection)|\(state.settings.growth)|\(state.settings.favoriteOpenings)|\(GrowthEngine.shared.version)"
    return memo.get(key) { GrowthLobby(state, tree, index) }
  }

  @ViewBuilder private func starts(_ lobby: GrowthLobby) -> some View {
    if let pick = lobby.pick {
      bigButton("Start") { start(lobby, pick, "Start button") }
    } else if let first = lobby.unstarted.first {
      bigButton("Start \(first.node.name)") { startOpening(first) }
    }
    let rest = Array(lobby.unstarted.dropFirst(lobby.pick == nil ? 1 : 0))
    if !rest.isEmpty {
      PlaySection(title: "Not in your Playbook yet")
      ListCard {
        ForEach(rest, id: \.node.id) { region in
          LobbyRow(side: region.side, title: "Start \(region.node.name)", meta: sansToMoveText(region.node.sans)) { startOpening(region) }
        }
      }
    }
    if lobby.whiteEmpty && !lobby.unstarted.contains(where: { $0.side == .w }) {
      PlaySection(title: "Your first move as White", aside: "from the book")
      ListCard {
        ForEach(lobby.firstMoves, id: \.san) { move in
          LobbyRow(side: .w, title: "1.\(move.san)", meta: "\(JS.string(move.share))% of strong players' games") { keepFirstMove(move.san) }
        }
      }
    }
  }

  @ViewBuilder private func work(_ lobby: GrowthLobby, _ prefs: GrowthPrefs) -> some View {
    if lobby.rows.isEmpty && GrowthEngine.shared.pending(lobby.asking) > 0 {
      ProgressView().tint(Theme.text2).frame(maxWidth: .infinity).padding(.vertical, 40)
    } else if lobby.rows.isEmpty {
      if lobby.hasMoves && lobby.unstarted.isEmpty {
        EmptyNote(title: "Nothing to extend", hint: lobby.emptyHint(prefs, store.state.settings.selection))
      }
    } else {
      PlaySection(title: "Openings to extend")
      ListCard {
        ForEach(lobby.rows, id: \.id) { row in
          LobbyRow(side: row.color, title: row.name, meta: repliesLabel(row), starred: row.starred) { start(lobby, row, "picked from the list") }
        }
      }
    }
  }

  private func have(_ lobby: GrowthLobby) -> some View {
    VStack(spacing: 0) {
      PlaySection(title: "What you have")
      ListCard {
        ForEach(lobby.reps, id: \.id) { rep in
          HStack(spacing: 12) {
            SideDot(side: rep.color)
            Text(rep.color == .w ? "As White" : "As Black").font(.system(size: 13)).foregroundStyle(Theme.text2)
            Spacer()
            Text("\(rep.nodes.count)").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
          }
          .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
        }
      }
    }
  }

  private func bigButton(_ title: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).frame(maxWidth: .infinity) }
      .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17))
      .padding(.top, 12)
  }

  /// A row on a stand-in starts on the real tree, made on the spot.
  private func start(_ lobby: GrowthLobby, _ row: GrowthRow, _ how: String) {
    store.update {
      $0.logEvent(AppEvent(
        kind: "growth-start", via: .growth, rows: lobby.rows.map { "\($0.name) (\($0.holes.count) replies)" }, picked: row.name, start: how))
    }
    guard row.repertoireId.hasPrefix(GrowthLobby.standIn) else { return onStart(row) }
    var real = row
    store.update { real.repertoireId = $0.ensureRepertoire(row.color) }
    onStart(real)
  }

  private func startOpening(_ region: SideRegion) {
    store.update { state in
      let id = state.ensureRepertoire(region.side)
      state.addLine(id, region.node.sans, .fixed(.picker), via: .growth)
    }
    toasts.show("\(region.node.name) kept \u{00b7} now answer the replies")
  }

  private func keepFirstMove(_ san: String) {
    store.update { state in
      let id = state.ensureRepertoire(.w)
      state.addLine(id, [san], .fixed(.growth), via: .growth)
    }
    toasts.show("1.\(san) kept \u{00b7} now answer Black's replies")
  }
}

/// A lobby row: the side, a title, what it holds, and a chevron. `.list-row`.
struct LobbyRow: View {
  var side: ChessCore.Color
  var title: String
  var meta: String
  var starred = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        SideDot(side: side)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 5) {
            if starred { Icon(name: "star", size: 12, filled: true).foregroundStyle(Theme.accent) }
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
          }
          .lineLimit(1)
          Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
        }
        Spacer(minLength: 0)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
