import ChessCore
import Model
import SwiftUI

/// Import my games: your recent Lichess or Chess.com games, read once and
/// never kept, turned into openings to add to your Playbook.
struct ImportView: View {
  let onBack: () -> Void
  /// After openings are added. Without it, adding goes back.
  var onAdded: (() -> Void)? = nil
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var site = GameSite.lichess
  @State private var username: String?
  @State private var step: Step?
  @State private var error: (message: String, blocked: Bool)?
  /// The list, with what the engine said of each of your moves in it.
  @State private var found: [SeedRow]?
  @State private var picked: Set<String> = []

  private enum Step { case fetching, checking }

  private var name: String {
    username ?? (site == .lichess ? store.state.settings.lichessUsername : store.state.settings.chesscomUsername)
  }
  private var nameBinding: Binding<String> { Binding(get: { name }, set: { username = $0 }) }
  private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    if let found {
      results(found)
    } else {
      source
    }
  }

  private var source: some View {
    VStack(spacing: 0) {
      AppBar(title: "Import my games", onBack: onBack)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SegmentedControl(value: $site, options: [(.lichess, "Lichess"), (.chesscom, "Chess.com")])
          FieldInput(placeholder: "Your \(site.name) username", text: nameBinding).padding(.top, 12)
          if let error {
            BadBanner(
              title: error.blocked ? "Can't reach \(site.name) from here" : "Couldn't import",
              sub: error.blocked ? "Check your connection and try again." : error.message
            ).padding(.top, 12)
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
      .scrollDismissesKeyboard(.interactively)
      BigButton(label: stepLabel, disabled: trimmed.isEmpty || step != nil) { Task { await find() } }
        .padding(.horizontal, 16).padding(.bottom, 12)
    }
  }

  private var stepLabel: String {
    switch step {
    case .fetching: return "Reading your games…"
    case .checking: return "Checking your moves…"
    case nil: return "Find my openings"
    }
  }

  private func results(_ rows: [SeedRow]) -> some View {
    let chosen = rows.filter { picked.contains($0.id) }
    return VStack(spacing: 0) {
      AppBar(title: "Your openings", onBack: { found = nil })
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if rows.isEmpty {
            EmptyNote(title: "No openings to add", hint: "Your Playbook already has the openings you play most").padding(.top, 8)
          } else {
            ListCard {
              ForEach(rows) { row in seedRow(row) }
            }
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
      if !rows.isEmpty {
        BigButton(label: chosen.isEmpty ? "Add openings" : "Add \(plural(chosen.count, "opening"))", disabled: chosen.isEmpty) {
          store.update { _ = $0.addSeedRows(chosen) }
          toasts.show("\(plural(chosen.count, "opening")) added")
          (onAdded ?? onBack)()
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
      }
    }
  }

  private func seedRow(_ row: SeedRow) -> some View {
    let on = picked.contains(row.id)
    return Button {
      if on { picked.remove(row.id) } else { picked.insert(row.id) }
    } label: {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 7)
          .fill(on ? Theme.accent : SwiftUI.Color.clear)
          .overlay { RoundedRectangle(cornerRadius: 7).stroke(on ? SwiftUI.Color.clear : Theme.surface3, lineWidth: 2) }
          .overlay { if on { Icon(name: "check", size: 15).foregroundStyle(Theme.accentInk) } }
          .frame(width: 24, height: 24)
        SideDot(side: row.color)
        Text(row.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(row.slot.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
      }
      .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 52).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Fetch the games, list their openings, ask the engine about your moves in them, and list them again without the mistakes.
  private func find() async {
    guard let index = store.index else { return }
    let name = trimmed
    // The site asked, even if the picker moves while the fetch runs.
    let site = self.site
    step = .fetching
    error = nil
    let result = await fetchGames(site, name, max: 120)
    guard case .ok(let games) = result else {
      if case .failed(let reason, let message) = result { error = (message, reason == .blocked) }
      step = nil
      return
    }
    store.update {
      if site == .lichess { $0.settings.lichessUsername = name } else { $0.settings.chesscomUsername = name }
    }
    step = .checking
    let reps = store.state.playbookList
    var lost: [String: Double] = [:]
    for move in seedMoves(seedRows(games, index, reps)) {
      if let cost = await EngineChecks.quickLoss(move.fen, move.san) { lost["\(positionKey(move.fen)) \(move.san)"] = cost }
    }
    let rows = seedRows(games, index, reps, lost: lost)
    picked = Set(rows.filter(\.checked).map(\.id))
    found = rows
    step = nil
  }
}
