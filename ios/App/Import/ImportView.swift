import Model
import SwiftUI

/// Import games: from Lichess or Chess.com, a pasted PGN, or a sample
/// archive; then what they say against your Playbook.
struct ImportView: View {
  let onBack: () -> Void
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var reviewing: Bool?
  @State private var site = GameSite.lichess
  @State private var username: String?
  @State private var loading = false
  @State var error: (message: String, blocked: Bool)?
  @State var pgnOpen = false
  @State private var pgnText = ""

  var games: [ImportedGame] { importedOnly(store.state.importedGames) }
  private var name: String {
    username ?? (store.state.settings.lichessUsername.isEmpty ? store.state.settings.chesscomUsername : store.state.settings.lichessUsername)
  }
  private var nameBinding: Binding<String> { Binding(get: { name }, set: { username = $0 }) }
  var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    Group {
      if reviewing ?? !games.isEmpty, !games.isEmpty {
        GameReviewView(games: games, onBack: { reviewing = false }, onExit: onBack)
      } else {
        source
      }
    }
    .task { debugOpen() }
  }

  private var source: some View {
    VStack(spacing: 0) {
      AppBar(title: "Import games", onBack: onBack)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SegmentedControl(value: $site, options: [(.lichess, "Lichess"), (.chesscom, "Chess.com")])
          FieldInput(placeholder: "Username", text: nameBinding).padding(.top, 8)
          SheetButton(loading ? "Importing…" : "Import recent games", style: .primary) { Task { await run() } }
            .unavailable(trimmed.isEmpty || loading).padding(.top, 8)
          if let error {
            BadBanner(
              title: error.blocked ? "Can't reach \(site.name) from here" : "Couldn't import",
              sub: error.blocked ? "Paste a PGN or try the sample instead." : error.message
            ).padding(.top, 12)
          }
          SectionHead(title: "Or")
          ListCard {
            ChevronRow(title: "Paste PGN") { pgnOpen = true }
            ChevronRow(title: "Try sample games", meta: "60 generated games", action: loadSample)
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .sheet(isPresented: $pgnOpen) { pgnSheet }
  }

  private var pgnSheet: some View {
    SheetFrame(title: "Paste PGN", detents: [.medium, .large], onClose: { pgnOpen = false }) {
      FieldInput(placeholder: "Your username in the PGN", text: nameBinding, raised: true)
      FieldArea(placeholder: "[Event \"Rated blitz game\"]…", text: $pgnText).padding(.top, 8)
      SheetButton("Import", style: .primary, action: loadPgn)
        .unavailable(pgnText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).padding(.top, 8)
    }
    .overlay { ToastHost() }
  }

  private func run() async {
    let name = trimmed
    guard !name.isEmpty else { return }
    // The site asked, even if the picker moves while the fetch runs.
    let site = self.site
    loading = true
    error = nil
    let result = await fetchGames(site, name, max: 120)
    loading = false
    switch result {
    case .failed(let reason, let message):
      error = (message, reason == .blocked)
    case .ok(let fetched):
      store.update {
        $0.setImportedGames(fetched)
        if site == .lichess { $0.settings.lichessUsername = name } else { $0.settings.chesscomUsername = name }
      }
      reviewing = true
      toasts.show("\(fetched.count) games imported")
    }
  }

  func loadSample() {
    guard let index = store.index else { return }
    let sample = generateSampleArchive(index, username: trimmed.isEmpty ? "you" : trimmed, count: 60, source: site.source)
    store.update { $0.setImportedGames(sample) }
    reviewing = true
  }

  private func loadPgn() {
    let tagged = pastedGames(pgnText, name)
    guard !tagged.isEmpty else {
      toasts.show("No games found")
      return
    }
    store.update { $0.setImportedGames(tagged) }
    pgnOpen = false
    reviewing = true
    toasts.show("\(tagged.count) games imported")
  }
}
