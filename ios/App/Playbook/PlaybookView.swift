import Book
import ChessCore
import Model
import SwiftUI

/// The Playbook tab: your openings, listed by family per side, with Tidy and
/// the Extensions review on top.
struct PlaybookView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  var tidyFocus: TidyFind? = nil
  /// The focus is taken: Tidy holds it from here.
  var onConsumedTidyFocus: () -> Void = {}
  var onExplore: ([String], ChessCore.Color) -> Void = { _, _ in }
  var onDrill: (String, String, String) -> Void = { _, _, _ in }
  /// Play a line out to a middlegame, as this side.
  var onMiddlegame: (ChessCore.Color, [String]) -> Void = { _, _ in }
  var onImport: () -> Void = {}
  var onBuild: () -> Void = {}

  @Environment(AppStore.self) private var store
  @State private var scan = TidyScan()
  @State private var page: Page?
  @State private var focus: TidyFind?
  @State private var adding = false
  @State private var openingMenu: DerivedOpening?
  @State private var sideMenu: String?

  enum Page: Equatable {
    case tidy, extensions
    case browse(repId: String, nodeId: String?, title: String)
  }

  var body: some View {
    let state = store.state
    Group {
      switch page {
      case .tidy: TidyView(scan: scan, focus: focus, onFocusShown: { focus = nil }) { page = nil }
      case .extensions: ExtensionsView { page = nil }
      case .browse(let repId, let nodeId, let title):
        if state.repertoires[repId] != nil {
          RepertoireBrowser(repId: repId, startNodeId: nodeId, title: title, onBack: { page = nil }, onExplore: onExplore, onDrill: onDrill)
        } else {
          Color.clear.onAppear { page = nil }
        }
      case nil: list
      }
    }
    .task(id: scanInput) { await scan.run(scanInput, tree, index) }
    .onAppear {
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
      favorites: state.settings.favoriteOpenings, growth: state.settings.growth)
  }

  private var sides: [(rep: Repertoire, openings: [DerivedOpening])] {
    [ChessCore.Color.w, .b].compactMap { color in
      store.state.repertoireList.first { $0.color == color }.map { ($0, familiesIn($0, index)) }
    }
  }

  private var list: some View {
    let reps = store.state.repertoireList
    let sides = self.sides
    let extensions = extensionOpenings(reps, index)
    let extCount = Self.extensionCounts(sides, extensions)
    return VStack(spacing: 0) {
      AppBar(title: "Playbook", large: true) {
        if !reps.isEmpty {
          ShareLink(item: exportFile(reps)) {
            Icon(name: "export", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
          }
        }
        IconButton(icon: "download", action: onImport)
        IconButton(icon: "plus") { adding = true }
      }
      ScrollView {
        VStack(spacing: 0) {
          if sides.isEmpty {
            EmptyNote(title: "No openings yet", hint: "Build a line in Growth, or save the opening from a game in Play. Practice never writes into your Playbook.")
          } else {
            TidyRow(count: scan.count, extensions: extensions, onOpen: { page = .tidy }, onExtensions: { page = .extensions })
              .padding(.top, 4)
          }
          ForEach(sides, id: \.rep.id) { side in
            SectionHead(title: side.rep.color == .w ? "As White" : "As Black",
                        aside: "\(side.openings.count) \(side.openings.count == 1 ? "opening" : "openings")")
            ListCard {
              ForEach(side.openings, id: \.id) { opening in
                OpeningRow(opening: opening, extensions: extCount[opening.id] ?? 0,
                           onOpen: { page = .browse(repId: side.rep.id, nodeId: opening.rootId, title: opening.name) },
                           onMenu: { openingMenu = opening })
              }
              HStack(spacing: 0) {
                Button { page = .browse(repId: side.rep.id, nodeId: nil, title: repertoireName(side.rep.color)) } label: {
                  HStack {
                    VStack(alignment: .leading, spacing: 2) {
                      Text("Whole tree, from move one").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2)
                      Text("\(side.rep.nodes.count) moves").font(.system(size: 12.5)).foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                IconButton(icon: "more", size: 18, plain: true) { sideMenu = side.rep.id }
              }
              .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 54)
            }
          }
          VStack(spacing: 8) {
            SheetButton("Play on the board", icon: "play", style: .soft, action: onBuild)
            SheetButton("Import games", icon: "download", style: .soft, action: onImport)
          }
          .padding(.top, 24)
        }
        .padding(.horizontal, 16).padding(.bottom, 28)
      }
    }
    .sheet(isPresented: $adding) {
      NewOpeningSheet { repId, color in page = .browse(repId: repId, nodeId: nil, title: repertoireName(color)) }
        .presentationDetents([.height(300)]).presentationBackground(Theme.background)
    }
    .sheet(item: Binding(get: { openingMenu.map(OpeningRef.init) }, set: { openingMenu = $0?.opening })) { ref in
      OpeningMenu(picked: ref.opening, index: index) { repId, nodeId, title in
        openingMenu = nil
        onDrill(repId, nodeId, title)
      } onOpenLine: { repId, tipId, title in
        openingMenu = nil
        page = .browse(repId: repId, nodeId: tipId, title: title)
      } onMiddlegame: { repId, sans in
        openingMenu = nil
        if let rep = store.state.repertoires[repId] { onMiddlegame(rep.color, sans) }
      } onClose: { openingMenu = nil }
      .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
    .sheet(item: Binding(get: { sideMenu.map(RepRef.init) }, set: { sideMenu = $0?.id })) { ref in
      SideMenu(repId: ref.id) { sideMenu = nil }.presentationDetents([.medium]).presentationBackground(Theme.background)
    }
  }

  /// Extensions per family row, counted once however many of its variations they sit in.
  static func extensionCounts(_ sides: [(rep: Repertoire, openings: [DerivedOpening])], _ extensions: [ExtensionOpening]) -> [String: Int] {
    var out: [String: Int] = [:]
    for side in sides {
      let roots = Set(extensions.filter { $0.rep.id == side.rep.id }.flatMap(\.roots))
      for opening in side.openings {
        let held = roots.filter { holdsNode(side.rep, opening, $0) }.count
        if held > 0 { out[opening.id] = held }
      }
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

struct OpeningRef: Identifiable { var opening: DerivedOpening; var id: String { opening.id } }
struct RepRef: Identifiable { var id: String }

/// One opening in the list: its name, ECO, lines and depth, and its extensions.
struct OpeningRow: View {
  let opening: DerivedOpening
  let extensions: Int
  let onOpen: () -> Void
  let onMenu: () -> Void

  var body: some View {
    let meta = [
      opening.eco, "\(opening.lines) \(opening.lines == 1 ? "line" : "lines")", "\((opening.depth + 1) / 2) \((opening.depth + 1) / 2 == 1 ? "move" : "moves") deep",
      opening.variations.isEmpty ? nil : "\(opening.variations.count) \(opening.variations.count == 1 ? "variation" : "variations")",
    ].compactMap { $0 }.joined(separator: " \u{00b7} ")
    HStack(spacing: 0) {
      Button(action: onOpen) {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 2) {
            Text(opening.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
            Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
          }
          Spacer(minLength: 0)
          if extensions > 0 { ExtPill(text: "+\(extensions)") }
          Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      IconButton(icon: "more", size: 18, plain: true, action: onMenu)
    }
    .padding(.leading, 16).padding(.trailing, 8).frame(minHeight: 64)
  }
}

/// Tidy at the top of the list, with how much it has found, and the Extensions review.
struct TidyRow: View {
  let count: Int?
  let extensions: [ExtensionOpening]
  let onOpen: () -> Void
  let onExtensions: () -> Void

  var body: some View {
    let open = extensions.reduce(0) { $0 + $1.open }
    let mistakes = extensions.reduce(0) { $0 + $1.mistakes }
    ListCard {
      row("merge", "Tidy", action: onOpen) {
        if let count { count == 0 ? Chip(text: "clear", tone: .good) : Chip(text: "\(count)", tone: .accent) }
      }
      if !extensions.isEmpty {
        row("sprout", "Extensions", action: onExtensions) {
          if mistakes > 0 { ExtPill(text: "\(mistakes)", mistake: true) }
          if open > 0 { ExtPill(text: "\(open)") } else { Chip(text: "reviewed", tone: .good) }
        }
      }
    }
  }

  private func row<Trailing: View>(_ icon: String, _ title: String, action: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Icon(name: icon, size: 20).foregroundStyle(Theme.accent)
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        Spacer()
        trailing()
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(.horizontal, 16).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
