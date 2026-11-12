import Book
import ChessCore
import Model
import SwiftUI
import UIKit

/// The Playbook tab: one side at a time, its openings under their first move,
/// replies to one opening of yours under its name, each row with its tier and
/// its line count. Tidy and the Extensions review are in the more menu when they have something.
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
  @Environment(Toasts.self) private var toasts
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
    let untidy = scan.count ?? 0
    let openExtensions = extensions.reduce(0) { $0 + $1.open }
    return VStack(spacing: 0) {
      AppBar(title: "Playbook", large: true) {
        Menu {
          if untidy > 0 {
            Button { page = .tidy } label: { Label("Tidy (\(untidy))", systemImage: "wand.and.stars") }
          }
          if !extensions.isEmpty {
            Button { page = .extensions } label: {
              Label(openExtensions > 0 ? "Extensions (\(openExtensions))" : "Extensions", systemImage: "arrow.triangle.branch")
            }
          }
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
          if let rep, !rows.isEmpty {
            let groups = playbookGroups(rows, tree)
            ForEach(Array(groups.enumerated()), id: \.offset) { at, group in
              HStack {
                Text(group.move).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
                Spacer()
                if at == 0 {
                  Text("LINES").font(.system(size: 11.5, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.text3)
                    .frame(width: 40, alignment: .trailing)
                  Spacer().frame(width: 18)
                }
              }
              .padding(.horizontal, 16).padding(.top, at == 0 ? 18 : 14).padding(.bottom, 6)
              ListCard {
                ForEach(Array(group.entries.enumerated()), id: \.offset) { _, entry in
                  switch entry {
                  case .row(let row):
                    rowView(rep, row, extCount)
                  case .family(let name, let node, let members):
                    FamilyRowView(name: name, nodeId: node, lines: entry.lines)
                    ForEach(members, id: \.id) { row in rowView(rep, row, extCount, name: nameUnder(name, row.name), indent: 18) }
                  }
                }
              }
              // Over the first card, pointing down at its first row.
              .tip(tip, when: at == 0 && tip == .playbookRow, arrow: .down, arrowAt: 0.3, inset: 8, onDismiss: putAway)
            }
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
    // While a tip shows, a tap anywhere goes to the next one, and nothing else takes a touch.
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

  /// One opening's row, swiping left to delete it after a confirmation.
  private func rowView(_ rep: Repertoire, _ row: PlaybookRow, _ extCount: [String: Int], name: String? = nil, indent: CGFloat = 0) -> some View {
    let removes = row.parts.reduce(0) { $0 + $1.removes }
    return SwipeToRemove(title: "Delete \(row.name)?", action: "Delete \(removes) \(removes == 1 ? "move" : "moves")") {
      store.update { state in
        for part in row.parts {
          state.removeOpening(rep.id, part.rootId, tips: part.nested != nil ? tipsOf(rep, part) : nil)
        }
      }
      toasts.show("\(row.name) deleted")
    } content: {
      PlaybookRowView(tree: tree, row: row, extensions: extCount[row.id] ?? 0, name: name, indent: indent) {
        page = .opening(repId: rep.id, name: row.name)
      }
    }
  }

  /// Where along the app bar a tip points: its + button, or the more menu left of it.
  private func barArrowAt(_ tip: TutorialTip?) -> CGFloat {
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

/// One opening on the tab: its name over its tier bar, the tier's name, its extensions, and its line count.
struct PlaybookRowView: View {
  let tree: OpeningTree
  let row: PlaybookRow
  let extensions: Int
  /// The name shown, shorter under a family's row.
  var name: String? = nil
  var indent: CGFloat = 0
  let onOpen: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let node = openingNode(tree, row)
    let stats = node.map { nodeStats(store.state.score, $0.id) } ?? NodeStats()
    let rank = rankOf(stats.rating, stats.rated)
    Button(action: onOpen) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 0) {
          Text(name ?? row.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          TierBar(rating: stats.rating, rated: stats.rated, label: false)
        }
        Text(stats.rated == 0 ? NEW_LABEL : rank.heldLabel).font(.system(size: 13)).foregroundStyle(Theme.text2)
          .lineLimit(1).frame(width: 64, alignment: .trailing)
        if extensions > 0 { ExtPill(text: "+\(extensions)") }
        Text("\(row.lines)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
          .frame(width: 40, alignment: .trailing)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(.leading, indent).padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 60).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// The opening of yours that the rows under it answer: its name, its own tier, and their lines together.
struct FamilyRowView: View {
  let name: String
  /// The book position it is named for, where its rating is kept.
  let nodeId: String
  let lines: Int
  @Environment(AppStore.self) private var store

  var body: some View {
    let stats = nodeStats(store.state.score, nodeId)
    let rank = rankOf(stats.rating, stats.rated)
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 0) {
        Text(name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
        TierBar(rating: stats.rating, rated: stats.rated, label: false)
      }
      Text(stats.rated == 0 ? NEW_LABEL : rank.heldLabel).font(.system(size: 13)).foregroundStyle(Theme.text2)
        .lineLimit(1).frame(width: 64, alignment: .trailing)
      Text("\(lines)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
        .frame(width: 40, alignment: .trailing)
      Spacer().frame(width: 18)
    }
    .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 60)
    .background(Theme.surface)
  }
}

/// A row that swipes left to show Delete, which asks before it deletes.
struct SwipeToRemove<Content: View>: View {
  let title: String
  /// The confirming button's label.
  let action: String
  let onRemove: () -> Void
  @ViewBuilder var content: Content
  @State private var offset: CGFloat = 0
  @State private var start: CGFloat = 0
  @State private var asking = false
  private let width: CGFloat = 92

  var body: some View {
    ZStack(alignment: .trailing) {
      if offset < 0 {
        Button { asking = true } label: {
          Text("Delete").font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: width).frame(maxHeight: .infinity).background(Theme.bad)
        }
        .buttonStyle(.plain)
      }
      content
        .background(Theme.surface)
        // While open, a tap on the row closes it instead of opening the opening.
        .overlay {
          if offset < 0 {
            SwiftUI.Color.black.opacity(0.001).contentShape(Rectangle())
              .onTapGesture { close() }
          }
        }
        .offset(x: offset)
        .gesture(HorizontalPan { dx in
          offset = min(0, max(-width * 1.3, start + dx))
        } onEnd: { dx, velocity in
          let end = start + dx
          withAnimation(.snappy) { offset = end < -width / 2 || velocity < -300 ? -width : 0 }
          start = offset
        })
    }
    .clipped()
    .confirmationDialog(title, isPresented: $asking, titleVisibility: .visible) {
      Button(action, role: .destructive) {
        close()
        onRemove()
      }
      Button("Cancel", role: .cancel) { close() }
    }
    .accessibilityAction(named: "Delete") { asking = true }
  }

  private func close() {
    withAnimation(.snappy) { offset = 0 }
    start = 0
  }
}

/// A pan that starts only when the finger moves more sideways than up or down,
/// so the list still scrolls and the row's button loses the touch once it starts.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
  let onChange: (CGFloat) -> Void
  /// The pan's sideways travel and speed when the finger lifts.
  let onEnd: (CGFloat, CGFloat) -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
    let pan = UIPanGestureRecognizer()
    pan.delegate = context.coordinator
    return pan
  }

  func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
    let dx = pan.translation(in: pan.view).x
    switch pan.state {
    case .changed: onChange(dx)
    case .ended, .cancelled, .failed: onEnd(dx, pan.velocity(in: pan.view).x)
    default: break
    }
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
      guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
      let v = pan.velocity(in: pan.view)
      return abs(v.x) > abs(v.y)
    }
  }
}
