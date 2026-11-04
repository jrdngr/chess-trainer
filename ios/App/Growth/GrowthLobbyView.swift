import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Growth's lobby: where the work is, the settings it is found with, and
/// where a side with nothing in it starts.
struct GrowthLobbyView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onStart: (GrowthRow, GrowthLobby.Launch) -> Void
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
    if let opening = lobby.opening {
      bigButton("Start \(opening.node.name)") { startOpening(opening) }
    } else if let pick = lobby.pick {
      bigButton("Start") { start(lobby, pick, "Start button") }
    }
    let rest = lobby.opening == nil ? lobby.unstarted : Array(lobby.unstarted.dropFirst())
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
        ForEach(lobby.saved, id: \.id) { rep in
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
    begin(row, lobby.launch(row), rows: lobby.rows.map { "\($0.name) (\($0.holes.count) replies)" }, how)
  }

  private func begin(_ row: GrowthRow, _ launch: GrowthLobby.Launch, rows: [String], _ how: String) {
    store.update {
      $0.logEvent(AppEvent(kind: "growth-start", via: .growth, rows: rows, picked: row.name, start: how))
    }
    guard row.repertoireId.hasPrefix(GrowthLobby.standIn) else { return onStart(row, launch) }
    var real = row
    store.update { real.repertoireId = $0.ensureRepertoire(row.color) }
    onStart(real, launch)
  }

  /// A favorite not in the Playbook yet: a sitting that keeps its own moves.
  private func startOpening(_ region: SideRegion) {
    let line = openingLine(index, region.node, region.side)
    guard let found = GrowthLobby.lineStart(store.state, tree, index, region.side, line, region: region.node, source: .picker) else {
      return toasts.show("Nothing to answer after \(region.node.name)")
    }
    begin(found.row, found.launch, rows: [found.row.name], "Start \(region.node.name)")
  }

  /// A first move as White: a sitting that keeps it and answers Black's replies.
  private func keepFirstMove(_ san: String) {
    guard let found = GrowthLobby.lineStart(store.state, tree, index, .w, [san], region: nil, source: .growth) else {
      return toasts.show("Nothing to answer after 1.\(san)")
    }
    begin(found.row, found.launch, rows: [found.row.name], "first move 1.\(san)")
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
