import Book
import ChessCore
import Model
import SwiftUI

/// The Playbook tab: one side at a time, each opening a row with its tier and
/// its line count, with Tidy and the Extensions review as pills on top.
struct PlaybookView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  var tidyFocus: TidyFind? = nil
  /// The focus is taken: Tidy holds it from here.
  var onConsumedTidyFocus: () -> Void = {}
  var onExplore: ([String], ChessCore.Color) -> Void = { _, _ in }
  /// Grow an opening, from Growth's own pick for it.
  var onGrow: (GrowOffer) -> Void = { _ in }
  /// Play a line out to a middlegame, as this side.
  var onMiddlegame: (ChessCore.Color, [String]) -> Void = { _, _ in }
  var onImport: () -> Void = {}
  var onBuild: () -> Void = {}
  /// Go to Home, after an opening page selected its opening.
  var onHome: () -> Void = {}
  /// Start a run, after openings were added from +.
  var onPlay: () -> Void = {}

  @Environment(AppStore.self) private var store
  @State private var scan = TidyScan()
  @State private var page: Page?
  @State private var focus: TidyFind?
  @State private var adding = false
  @State private var side = ChessCore.Color.w
  /// The app bar's width, to point a tip at its + or more button.
  @State private var barWidth: CGFloat = 393

  enum Page: Equatable {
    case tidy, extensions
    case opening(repId: String, name: String)
    case browse(repId: String, nodeId: String?, title: String)
    /// The board editor on a line of one side's tree, back to the browser after.
    case board(repId: String, sans: [String], title: String)
  }

  var body: some View {
    let state = store.state
    Group {
      switch page {
      case .tidy: TidyView(scan: scan, focus: focus, onFocusShown: { focus = nil }) { page = nil }
      case .extensions: ExtensionsView { page = nil }
      case .opening(let repId, let name):
        OpeningPage(
          tree: tree, index: index, repId: repId, name: name, onBack: { page = nil },
          onOpenLine: { tipId, title in page = .browse(repId: repId, nodeId: tipId, title: title) },
          onGrow: onGrow, onMiddlegame: onMiddlegame,
          onSelected: {
            page = nil
            onHome()
          })
      case .browse(let repId, let nodeId, let title):
        if state.repertoires[repId] != nil {
          RepertoireBrowser(
            repId: repId, startNodeId: nodeId, title: title, onBack: { page = nil }, onExplore: onExplore,
            onEdit: { sans in page = .board(repId: repId, sans: sans, title: title) })
        } else {
          Color.clear.onAppear { page = nil }
        }
      case .board(let repId, let sans, let title):
        if let rep = state.repertoires[repId] {
          BoardBuildView(start: sans, side: rep.color, onBack: { _ in
            // Back to the browser where the line's saved moves end.
            let fresh = store.state.repertoires[repId] ?? rep
            let held = Array(sans.prefix(savedPlies(fresh, sans)))
            page = .browse(repId: repId, nodeId: held.isEmpty ? nil : nodeAtLine(fresh, held)?.id, title: title)
          })
        } else {
          Color.clear.onAppear { page = nil }
        }
      case nil: list
      }
    }
    .task(id: scanInput) { await scan.run(scanInput, tree, index) }
    .onAppear {
      if store.state.repertoireList.first(where: { $0.color == side }) == nil, let other = store.state.repertoireList.first {
        side = other.color
      }
      guard let tidyFocus else { return }
      focus = tidyFocus
      page = .tidy
      onConsumedTidyFocus()
    }
  }

  private var scanInput: TidyScan.Input {
    let state = store.state
    return TidyScan.Input(
      repertoires: state.repertoires, order: state.repertoireOrder, selection: state.settings.selection,
      growth: state.settings.growth)
  }

  private var list: some View {
    let reps = store.state.repertoireList
    let rep = reps.first { $0.color == side }
    let rows = rep.map { playbookRows($0, index) } ?? []
    let extensions = extensionOpenings(reps, index)
    let extCount = rep.map { Self.extensionCounts($0, rows, extensions) } ?? [:]
    let tip = playbookTip(store.state.settings.tips, hasRows: !rows.isEmpty)
    let putAway = { dismissTip(store, tip) }
    return VStack(spacing: 0) {
      AppBar(title: "Playbook", large: true) {
        Menu {
          Button { onImport() } label: { Label("Import my games", systemImage: "square.and.arrow.down") }
          Button { onBuild() } label: { Label("Play on the board", systemImage: "checkerboard.rectangle") }
          if !reps.isEmpty {
            ShareLink(item: exportFile(reps)) { Label("Export", systemImage: "square.and.arrow.up") }
          }
        } label: {
          Icon(name: "more", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .accessibilityLabel("More")
        IconButton(icon: "plus") { adding = true }
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
      .tip(tip, when: tip == .playbookAdd || tip == .playbookMore, arrowAt: barArrowAt(tip), inset: 16, onDismiss: putAway)
      ScrollView {
        VStack(spacing: 0) {
          SegmentedControl(value: $side, options: [(.w, "White"), (.b, "Black")])
          PlaybookPills(count: scan.count, extensions: extensions, onTidy: { page = .tidy }, onExtensions: { page = .extensions })
            .padding(.top, 12)
          if let rep, !rows.isEmpty {
            HStack {
              Spacer()
              Text("LINES").font(.system(size: 11.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.text3)
                .frame(width: 40, alignment: .trailing)
              Spacer().frame(width: 18)
            }
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 6)
            ListCard {
              ForEach(rows, id: \.id) { row in
                PlaybookRowView(tree: tree, row: row, extensions: extCount[row.id] ?? 0) {
                  page = .opening(repId: rep.id, name: row.name)
                }
              }
            }
            // Over the card, pointing down at its first row: the card clips what hangs inside it.
            .tip(tip, when: tip == .playbookRow, arrow: .down, arrowAt: 0.3, inset: 8, onDismiss: putAway)
            ListCard {
              Button { page = .browse(repId: rep.id, nodeId: nil, title: repertoireName(rep.color)) } label: {
                HStack(spacing: 12) {
                  Icon(name: "tree", size: 20).foregroundStyle(Theme.text2)
                  Text("Whole tree").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                  Spacer()
                  Text("\(rep.nodes.count)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
                  Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
                }
                .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
            .padding(.top, 12)
          } else {
            EmptyNote(title: side == .w ? "No openings as White" : "No openings as Black", hint: "Tap + to add one")
              .padding(.top, 24)
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 28)
      }
    }
    // While a tip shows, a tap anywhere goes to the next one.
    .overlay {
      if tip != nil {
        SwiftUI.Color.black.opacity(0.001).contentShape(Rectangle())
          .onTapGesture(perform: putAway)
          .accessibilityHidden(true)
      }
    }
    .fullScreenCover(isPresented: $adding) {
      OnboardingView(tree: tree, index: index, onClose: { adding = false }) { next in
        adding = false
        if next == .autopilot { onPlay() } else { onHome() }
      }
    }
  }

  /// Where along the app bar a tip points: its + button, or the more menu left of it.
  private func barArrowAt(_ tip: FirstGameTip?) -> CGFloat {
    // The bar's 20pt sides, 38pt buttons 8pt apart; the tip spans the bar less 16pt each side.
    let plus = barWidth - 20 - 19
    let x = tip == .playbookMore ? plus - 46 : plus
    return (x - 16) / max(barWidth - 32, 1)
  }

  /// Extensions per row, counted once however many of its parts and variations they sit in.
  static func extensionCounts(_ rep: Repertoire, _ rows: [PlaybookRow], _ extensions: [ExtensionOpening]) -> [String: Int] {
    let roots = Set(extensions.filter { $0.rep.id == rep.id }.flatMap(\.roots))
    var out: [String: Int] = [:]
    for row in rows {
      let held = roots.filter { root in row.parts.contains { holdsNode(rep, $0, root) } }.count
      if held > 0 { out[row.id] = held }
    }
    return out
  }

  /// Your repertoire with the log of how it got that way, as a JSON file to share.
  private func exportFile(_ reps: [Repertoire]) -> URL {
    let date = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
    let url = FileManager.default.temporaryDirectory.appending(path: "repertoire-\(date).json")
    struct Export: Encodable {
      var format = "chess-trainer-repertoire"
      var version = 1
      var exportedAt: String
      var repertoires: [Repertoire]
      var events: [AppEvent]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(Export(exportedAt: date, repertoires: reps, events: store.state.events)) {
      try? data.write(to: url)
    }
    return url
  }
}

struct RepRef: Identifiable { var id: String }

/// The book's opening a Playbook row stands for, where its rating is kept:
/// the shallowest node of that name, else the node at the row's first move order.
@MainActor func openingNode(_ tree: OpeningTree, _ row: PlaybookRow) -> OpeningNode? {
  row.parts.first.flatMap { familyNode(tree, row.name, path: $0.path) }
}

/// One opening on the tab: its tier dot, name and tier bar, its extensions, and its line count.
struct PlaybookRowView: View {
  let tree: OpeningTree
  let row: PlaybookRow
  let extensions: Int
  let onOpen: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let node = openingNode(tree, row)
    let stats = node.map { nodeStats(store.state.score, $0.id) } ?? NodeStats()
    let rank = rankOf(stats.rating, stats.rated)
    Button(action: onOpen) {
      HStack(spacing: 10) {
        Circle().fill(SwiftUI.Color(hexString: (rank.held ?? UNRATED).color)).frame(width: 10, height: 10)
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 6) {
            Text(row.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          }
          TierBar(rating: stats.rating, rated: stats.rated)
        }
        if extensions > 0 { ExtPill(text: "+\(extensions)") }
        Text("\(row.lines)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
          .frame(width: 40, alignment: .trailing)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 60).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Tidy and the Extensions review, as two pills with their counts.
struct PlaybookPills: View {
  let count: Int?
  let extensions: [ExtensionOpening]
  let onTidy: () -> Void
  let onExtensions: () -> Void

  var body: some View {
    let open = extensions.reduce(0) { $0 + $1.open }
    let mistakes = extensions.reduce(0) { $0 + $1.mistakes }
    HStack(spacing: 8) {
      Button(action: onTidy) {
        StatsPill(dot: count.map { $0 > 0 ? Theme.accent : Theme.good }, bold: count.flatMap { $0 > 0 ? "\($0)" : nil }, text: "Tidy")
      }
      .buttonStyle(.plain)
      if !extensions.isEmpty {
        Button(action: onExtensions) {
          StatsPill(dot: mistakes > 0 ? Theme.warn : open > 0 ? Theme.accent : Theme.good, bold: open > 0 ? "\(open)" : nil, text: "Extensions")
        }
        .buttonStyle(.plain)
      }
      Spacer(minLength: 0)
    }
  }
}
