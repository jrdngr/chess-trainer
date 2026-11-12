import Game
import Model
import SwiftUI
import UIKit

/// Export: this profile whole, its games as PGN, or its Playbook, each sent
/// through the share sheet as a file.
struct ExportView: View {
  @Environment(AppStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var shared: SharedFile?

  var body: some View {
    let games = store.state.games
    let now = Env.now()
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack {
          Text("Export").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          Spacer()
          Button { dismiss() } label: {
            Icon(name: "close", size: 18).foregroundStyle(Theme.text).frame(width: 36, height: 36).background(Circle().fill(Theme.surface))
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Close")
        }
        ListCard {
          row("Everything") { share(everything(), "profile", "json") }
        }
        .padding(.top, 16)
        section("Games")
        ListCard {
          ForEach(GameScope.allCases, id: \.self) { scope in
            let picked = gamesIn(games, scope, now: now)
            row(scopeLabel(scope), count: picked.count) {
              if let tree = store.tree { share(Data(gamesPgn(picked, tree).utf8), "games-\(scope.rawValue)", "pgn") }
            }
            .disabled(picked.isEmpty)
          }
        }
        section("Playbook")
        ListCard {
          row("Playbook only") { share(playbook(), "playbook", "json") }
        }
      }
      .padding(20)
    }
    .sheet(item: $shared) { file in ShareSheet(url: file.url).ignoresSafeArea().presentationDetents([.medium, .large]) }
  }

  private func scopeLabel(_ scope: GameScope) -> String {
    switch scope {
    case .last: "Last game"
    case .day: "Last day"
    case .week: "Last week"
    case .all: "All games"
    }
  }

  private func row(_ label: String, count: Int? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack {
        Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(count == 0 ? Theme.text3 : Theme.text)
        Spacer()
        if let count { Text("\(count)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text3).monospacedDigit() }
        Icon(name: "export", size: 16).foregroundStyle(count == 0 ? Theme.text3 : Theme.text2)
      }
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func section(_ title: String) -> some View {
    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
  }

  private var stamp: String { ISO8601DateFormatter().string(from: Date()) }

  private func everything() -> Data? {
    try? exportJson(ProfileExport(exportedAt: stamp, profile: store.profiles.activeProfile.name, state: store.state))
  }

  private func playbook() -> Data? {
    try? exportJson(PlaybookExport(exportedAt: stamp, playbooks: store.state.playbookList))
  }

  /// Write the file to the temporary folder and open the share sheet on it.
  private func share(_ data: Data?, _ name: String, _ ext: String) {
    guard let data else { return }
    let day = String(stamp.prefix(10))
    let url = FileManager.default.temporaryDirectory.appending(path: "chess-playbook-\(name)-\(day).\(ext)")
    do {
      try data.write(to: url)
      shared = SharedFile(url: url)
    } catch {}
  }
}

struct SharedFile: Identifiable {
  let url: URL
  var id: URL { url }
}

/// The system share sheet on one file.
struct ShareSheet: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
