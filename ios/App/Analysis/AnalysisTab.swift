import Book
import ChessCore
import Engine
import Model
import SwiftUI

/// Analysis: board, engine, and the reference book in one place. The
/// engine's lines above, the book's moves and games below, and the named
/// lines the book knows from this position.
struct AnalysisTab: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// Opened over a mode's end screen: Back returns to it.
  let onBack: (() -> Void)?
  @Environment(AppStore.self) var store
  @State private var sans: [String]
  @State private var cursor: Int
  @State private var orientation: ChessCore.Color
  @State private var engine = AnalysisEngine()
  @State private var lens: LensKind?
  @State private var breaks: (fen: String, found: PawnBreaks.Breaks)?
  @State private var showReference = true
  @State var sheet: AnalysisSheet?
  @State var pgnText = ""
  @State var toast: String?

  /// The tab, from the start position.
  init(tree: OpeningTree, index: ReferenceIndex) {
    self.init(tree: tree, index: index, line: [], orientation: .w)
  }

  /// From the end of `line`, seen from `orientation`'s side; with `onBack`, a Back button and no tab bar.
  init(tree: OpeningTree, index: ReferenceIndex, line: [String], orientation: ChessCore.Color, onBack: (() -> Void)? = nil) {
    self.tree = tree
    self.index = index
    self.onBack = onBack
    let start = Self.debugLine ?? line
    _sans = State(initialValue: start)
    _cursor = State(initialValue: start.count)
    _orientation = State(initialValue: orientation)
    _sheet = State(initialValue: Self.debugSheet(start))
  }

  var visible: [String] { Array(sans.prefix(cursor)) }
  private var fens: [String] { walkSan(visible).fens }
  var fen: String { fens.last! }
  private var settings: Settings { store.state.settings }
  /// The engine's last word, once it is about the position shown.
  private var current: EngineSnapshot? { engine.snapshot.flatMap { $0.fen == fen ? $0 : nil } }
  private var lines: [SanLine] { current == nil ? [] : engine.sanLines }
  private var best: EngineLine? { lines.first?.line }

  var body: some View {
    VStack(spacing: 0) {
      AnalysisAppBar(opening: openingNameForPath(index, visible), onBack: onBack) {
        orientation = orientation.other
      } onPgn: {
        sheet = .pgn
      }
      ScrollViewReader { proxy in
        ScrollView {
          content.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
        }
        .task { await debugScroll(proxy) }
      }
    }
    .background(Theme.background)
    .overlay(alignment: .bottom) { toastView }
    .task(id: settings.engineEnabled ? fen : nil) { await engine.run(settings.engineEnabled ? fen : nil) }
    .task(id: lens == .pawns ? fen : nil) {
      guard lens == .pawns else { return }
      let at = fen
      let found = await PawnBreaks.find(HintEngine.shared, at)
      if !Task.isCancelled { breaks = (at, found) }
    }
    .sheet(item: $sheet) { sheetView($0) }
  }

  @ViewBuilder private var content: some View {
    VStack(spacing: 0) {
      if settings.engineEnabled {
        EvalRow(best: best, depth: current?.depth ?? 0).padding(.bottom, 10)
      }
      if let caption = marks?.caption {
        Text(caption).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text).frame(minHeight: 22).padding(.bottom, 6)
      } else {
        CapturedRow(fen: fen, orientation: orientation).padding(.bottom, 6)
      }
      BoardView(
        fen: fen, orientation: orientation, interactive: true, lastMove: lastMoveOf(visible),
        arrows: marks == nil ? bestArrow : [], marks: marks, bothSides: true, onMove: { play($0.san) })
      LensBar(held: $lens)
      if let lens {
        LensLegend(kind: lens, endgame: isEndgame(fen))
      } else {
        below
      }
    }
  }

  @ViewBuilder private var below: some View {
    PlanCard(fens: fens, me: orientation)
    Spacer().frame(height: 8)
    strip
    let status = positionStatus(fen)
    if status.gameOver {
      Text(status.checkmate ? "Checkmate" : status.stalemate ? "Stalemate" : "Draw")
        .font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity).padding(16).background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface)).padding(.top, 8)
    }
    EngineSection(
      label: "Basic evaluator", enabled: settings.engineEnabled, started: engine.started,
      thinking: current?.thinking ?? true, fen: fen, lines: lines,
      onToggle: { store.update { $0.settings.engineEnabled.toggle() } }, onPlay: play)
    AnalysisSectionHead(title: "Reference") {
      Button { showReference.toggle() } label: { AnalysisChip(text: showReference ? "Hide" : "Show") }.buttonStyle(.plain)
    }
    .id(AnalysisAnchor.reference)
    if showReference {
      ExplorerPanel(index: index, fen: fen, path: visible, onPlay: play) { sheet = .game($0) }
    }
    if !visible.isEmpty {
      HStack(spacing: 8) {
        WideButton(title: "PGN", kind: .soft) { exportPgn() }
        WideButton(title: "Add to Playbook", icon: "plus", kind: .primary) {
          sheet = .save(SaveRequest(sans: visible, title: "Save line"))
        }
      }
      .padding(.top, 16)
    }
    NamedLines(lines: bookLinesFrom(visible)) { sheet = .bookLine($0) }.id(AnalysisAnchor.named)
  }

  /// The line's moves, with a prompt before the first.
  private var strip: some View {
    let items = sans.enumerated().map { i, san in
      StripItem(san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, tone: i >= cursor ? .ghost : nil, current: i == cursor - 1, seek: i + 1)
    }
    return MoveStrip(items: items, cursor: cursor, max: sans.count) { cursor = max(0, min(sans.count, $0)) }
      .overlay(alignment: .leading) {
        if sans.isEmpty {
          Text("Play a move").font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.leading, 92).allowsHitTesting(false)
        }
      }
  }

  /// What the held lens draws: `useLens`.
  private var marks: LensMarks? {
    guard let lens else { return nil }
    var marks = heldLens(lens, fen, orientation, fens.count > 1 ? fens[fens.count - 2] : nil)
    if lens == .pawns, let breaks, breaks.fen == fen {
      let sides: [ChessCore.Color] = [.w, .b]
      marks.arrows = sides.compactMap { (side: ChessCore.Color) -> LensArrow? in
        guard let move = breaks.found[side] else { return nil }
        return LensArrow(from: move.from, to: move.to, tone: side == orientation ? "mine" : "theirs")
      }
    }
    return marks
  }

  private var bestArrow: [BoardArrow] {
    guard settings.engineEnabled, let uci = best?.pv.first, let move = applyUci(fen, uci) else { return [] }
    return [BoardArrow(from: move.from, to: move.to, color: Theme.accent)]
  }

  /// Play a move from the shown position, cutting off whatever came after it.
  func play(_ san: String) {
    guard let move = applySan(fen, san) else { return }
    sans = visible + [move.san]
    cursor = sans.count
  }

  /// Replace the board's line.
  func load(_ moves: [String], at: Int? = nil) {
    sans = moves
    cursor = at ?? moves.count
  }

  private func exportPgn() {
    pgnText = Pgn.export(visible)
    sheet = .pgn
  }

  func show(_ text: String) {
    withAnimation { toast = text }
    Task {
      try? await Task.sleep(for: .seconds(2))
      if toast == text { withAnimation { toast = nil } }
    }
  }

  @ViewBuilder private var toastView: some View {
    if let toast {
      Text(toast).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.background)
        .padding(.horizontal, 18).padding(.vertical, 10).background(Capsule().fill(Theme.text))
        .padding(.bottom, 20).transition(.opacity)
    }
  }
}
