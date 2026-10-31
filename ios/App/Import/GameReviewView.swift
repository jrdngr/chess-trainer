import ChessCore
import Model
import Shared
import SwiftUI

/// Your imported games against a Playbook: coverage, then the gaps and
/// deviations. `GameReview` in `ImportScreen.tsx`.
struct GameReviewView: View {
  let games: [ImportedGame]
  let onBack: () -> Void
  let onExit: () -> Void
  @Environment(AppStore.self) private var store
  @State private var repId = ""
  @State private var kind: FindingKind?
  @State private var finding: Finding?
  @State private var report: Report?

  /// What the games say against one Playbook, worked out once per Playbook.
  struct Report {
    var id: String
    var findings: [Finding]
    var coverage: RepertoireCoverage
  }

  private var reps: [Repertoire] { store.state.repertoireList }
  private var rep: Repertoire? { store.state.repertoires[repId] ?? reps.first }
  private var reportKey: String { "\(rep?.id ?? "")|\(games.count)|\(games.first?.id ?? "")" }

  var body: some View {
    VStack(spacing: 0) {
      AppBar(title: "Your games", subtitle: "\(games.count) imported", onBack: onExit) {
        IconButton(icon: "download", action: onBack)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) { content }
          .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
    }
    .task(id: reportKey) { build() }
    .sheet(item: Binding(get: { finding.map(FindingRef.init) }, set: { finding = $0?.finding })) { ref in
      FindingSheet(finding: ref.finding, orientation: rep?.color ?? .w) { finding = nil }
    }
  }

  @ViewBuilder private var content: some View {
    if !reps.isEmpty {
      SegmentedControl(value: Binding(get: { rep?.id ?? "" }, set: { repId = $0 }),
                       options: reps.map { ($0.id, displayName($0.name)) })
    }
    let findings = report?.findings ?? []
    let gaps = findings.filter { $0.kind == .gap }.count
    let deviations = findings.filter { $0.kind == .deviation }.count
    // Open on whichever tab actually has something to look at.
    let active = kind ?? (gaps == 0 && deviations > 0 ? .deviation : .gap)
    let shown = findings.filter { $0.kind == active }
    if let coverage = report?.coverage {
      StatGrid(stats: [
        ("\(coverage.inPrep)", "In book"),
        ("\(coverage.outOfPrep)", "Off book"),
        (JS.toFixed(coverage.averageExitPly / 2, 1), "Exit move"),
      ]).padding(.top, 8)
    }
    SegmentedControl(value: Binding(get: { active }, set: { kind = $0 }),
                     options: [(.gap, "Gaps · \(gaps)"), (.deviation, "Deviations · \(deviations)")])
      .padding(.top, 16)
    if shown.isEmpty {
      EmptyNote(title: active == .gap ? "No gaps" : "No deviations", hint: "Import more games to find more").padding(.top, 8)
    }
    LazyVStack(spacing: 10) {
      ForEach(Array(shown.prefix(25)), id: \.key) { f in
        FindingCard(finding: f) { finding = f }
      }
    }
    .padding(.top, 8)
  }

  private func build() {
    guard let rep else {
      report = nil
      return
    }
    let tree = buildPlayerTree(games, rep.color)
    report = Report(id: rep.id, findings: analyseAgainstRepertoire(tree, rep, minGames: 2), coverage: measureCoverage(games, rep))
    if let n = ImportDebug.finding, let findings = report?.findings, n < findings.count { finding = findings[n] }
  }
}

private struct FindingRef: Identifiable {
  let finding: Finding
  var id: String { "\(finding.kind.rawValue)-\(finding.key)" }
}

/// One finding, on the board: `Sheet` in `GameReview`.
struct FindingSheet: View {
  let finding: Finding
  let orientation: ChessCore.Color
  let onClose: () -> Void

  var body: some View {
    SheetFrame(title: finding.kind == .gap ? "Gap" : "Deviation", detents: [.fraction(0.84), .large], onClose: onClose) {
      MoveText(text: finding.lineText).padding(.bottom, 10)
      BoardView(fen: finding.fen, orientation: orientation, interactive: false, lastMove: nil, coordinates: false, onMove: { _ in })
        .aspectRatio(1, contentMode: .fit)
      VStack(spacing: 0) {
        KVRow(key: "Games", value: "\(finding.games)")
        line
        KVRow(key: "Played", value: finding.played.map { "\($0.san) ×\($0.count)" }.joined(separator: ", ").ifEmpty("—"))
        if !finding.expected.isEmpty {
          line
          KVRow(key: "Playbook", value: finding.expected.joined(separator: ", "), tint: Theme.good)
        }
        line
        KVRow(key: "Score", value: scoreText(finding.results))
      }
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface2))
      .padding(.top, 8)
    }
  }
}

extension FindingSheet {
  private var line: some View { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
}

private extension String {
  func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
