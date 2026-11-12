import ChessCore
import Book
import Engine
import Model
import Shared
import SwiftUI

/// A line saved from the board.
struct BoardLine: Equatable {
  var color: ChessCore.Color
  var sans: [String]
}

/// The board editor: build lines by playing the moves in, for both sides.
/// Nothing moves on its own; Move opponent plays the book's most played reply,
/// or the engine's best past the book. Book moves are filled in the strip and
/// moves past the book outlined; only the book part of a line is saved. The
/// engine judges every move, and a dubious move or a blunder shows what it
/// gave away and an arrow to the better move. Nothing is saved until Save line.
/// Shared by onboarding, the Playbook tab and the Playbook browser.
struct BoardBuildView: View {
  /// The line it opens on, cursor at its end.
  var start: [String] = []
  /// The side, when the caller knows it; otherwise the White/Black switch picks it.
  var side: ChessCore.Color? = nil
  /// Leave, with the lines saved so far.
  let onBack: ([BoardLine]) -> Void
  /// After a line is saved, with the lines saved so far; nil stays on the board.
  var onSaved: (([BoardLine]) -> Void)? = nil
  /// Hand the saved lines on without putting them in the Playbook.
  var hold = false

  @Environment(AppStore.self) private var store
  @State private var started = false
  @State private var color = ChessCore.Color.w
  @State private var flipped = false
  @State private var moves: [String] = []
  @State private var cursor = 0
  @State private var style = Style.popular
  @State private var saved: [BoardLine] = []
  @State private var saving: [String]?
  @State private var justSaved = false
  @State private var discarding = false
  @State private var thinking = false
  /// Bumped whenever the line changes, so an engine reply on its way to an older line is dropped.
  @State private var replyFor = 0
  private var checks: EngineChecks { EngineChecks.shared }

  var body: some View {
    if let index = store.index, let tree = store.tree {
      content(index, tree)
    }
  }

  @ViewBuilder private func content(_ index: ReferenceIndex, _ tree: OpeningTree) -> some View {
    let visible = Array(moves.prefix(cursor))
    let fens = walkSan(moves).fens
    let fen = fens[min(cursor, fens.count - 1)]
    let mine = turnAfter(visible) == color
    let judged = moves.indices.map { i in i + 1 < fens.count ? checks.check(fens[i], moves[i]) ?? nil : nil }
    let lost = judged.map { $0?.lost }
    let book = bookLength(index, moves)
    let last = cursor > 0 ? judged[cursor - 1] : nil
    let lastBad = last.flatMap { moveQuality($0.lost) } != nil
    let choices = bookChoices(index, fen)
    let picks: [Style: String] = mine
      ? Dictionary(uniqueKeysWithValues: STYLES.compactMap { s in stylePick(index, tree, visible, choices, s.id).map { (s.id, $0) } }) : [:]
    let highlight = mine ? (picks[style] ?? picks[.popular]) : choices.first?.san
    let arrows = lastBad ? betterArrow(fens[cursor - 1], last?.best) : bookArrows(fen, choices, highlight)
    let styles = mine && !lastBad ? shownStyles(picks, style) : []
    let opening = openingNameForPath(index, visible)
    let (family, variation) = splitName(opening?.name)
    let toSave = !visible.isEmpty && turnAfter(visible) == color ? Array(visible.dropLast()) : visible
    let savable = !toSave.isEmpty && toSave.indices.contains { movedBy($0, color) }
    let unsaved = savable ? toSave.count - held(toSave) : 0

    VStack(spacing: 0) {
      AppBar(title: family ?? "On the board", subtitle: variation, onBack: { if unsaved > 0 { discarding = true } else { onBack(saved) } }) {
        IconButton(icon: "flip") { flipped.toggle() }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          if side == nil {
            sideSwitch.padding(.bottom, 10)
          }
          BoardView(fen: fen, orientation: flipped ? color.other : color, interactive: true,
                    lastMove: lastMoveOf(visible), arrows: arrows, bothSides: true) { move in setLine(visible + [move.san]) }
            .padding(3)
          MoveStrip(
            items: moves.enumerated().map { i, san in
              StripItem(san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, tone: tone(i, book, lost), current: i == cursor - 1,
                        badge: i < cursor ? badge(lost[i]) : nil, seek: i + 1)
            },
            cursor: cursor, max: moves.count, onSeek: seek, hint: "Play a move"
          )
          .padding(.top, 16)
          SheetButton(thinking ? "Thinking\u{2026}" : "Move opponent", icon: "next", style: .plain) {
            moveOpponent(visible, fen, choices.first?.san)
          }
          .disabled(mine || thinking)
          .padding(.top, 12)
          if styles.count > 1 {
            SectionHead(title: "Style")
            WrapLayout(spacing: 6) {
              ForEach(STYLES.filter { styles.contains($0.id) }, id: \.id) { s in
                Button { style = s.id } label: {
                  Text(s.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(s.id == style ? Theme.accentInk : Theme.text)
                    .padding(.horizontal, 14).padding(.vertical, 8).background(Capsule().fill(s.id == style ? Theme.accent : Theme.surface))
                }
                .buttonStyle(.plain)
              }
            }
          }
          SectionHead(title: "Goals")
          ListCard {
            ForEach(goals(fen, color), id: \.label) { goal in
              HStack {
                Text(goal.label).font(.system(size: 13)).foregroundStyle(Theme.text2)
                Spacer()
                Text(goal.value).font(.system(size: 15, weight: .semibold, design: goal.moves ? .monospaced : .default)).foregroundStyle(Theme.text)
              }
              .padding(.horizontal, 16).frame(minHeight: 44)
            }
          }
          if !saved.isEmpty {
            SectionHead(title: "Saved", aside: "\(saved.count) \(saved.count == 1 ? "line" : "lines")")
            ListCard {
              ForEach(Array(saved.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 12) {
                  SideSquare(color: line.color).padding(.top, 5)
                  Text(sansToMoveText(line.sans)).font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.text2).lineSpacing(4)
                  Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
              }
            }
          }
        }
        .padding(.horizontal, 16).padding(.bottom, 24)
      }
      SheetButton("Save line", style: .accent) { saving = toSave }.disabled(!savable)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
        .background(Theme.background.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }
    .onAppear {
      guard !started else { return }
      started = true
      color = side ?? .w
      moves = start
      cursor = start.count
    }
    .task(id: moves) {
      let fens = walkSan(moves).fens
      for i in moves.indices where i + 1 < fens.count { checks.askCheck(fens[i], moves[i]) }
    }
    .confirmationDialog(unsaved == 1 ? "Discard 1 move?" : "Discard \(unsaved) moves?", isPresented: $discarding, titleVisibility: .visible) {
      Button("Discard", role: .destructive) { onBack(saved) }
      Button("Keep playing", role: .cancel) {}
    }
    .sheet(item: Binding(get: { saving.map { LineRef(sans: $0) } }, set: { saving = $0?.sans }), onDismiss: {
      if justSaved, let onSaved {
        justSaved = false
        onSaved(saved)
      }
    }) { ref in
      SaveSheet(sans: ref.sans, color: color, source: .board,
                onSaved: { _, _, line in keep(BoardLine(color: color, sans: line)) },
                onKeep: hold ? { line, _ in keep(BoardLine(color: color, sans: line)) } : nil,
                onClose: { saving = nil })
        .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
  }

  private var sideSwitch: some View {
    HStack(spacing: 2) {
      ForEach([ChessCore.Color.w, .b], id: \.self) { c in
        Button { color = c } label: {
          HStack(spacing: 6) {
            SideSquare(color: c, size: 12)
            Text(c == .w ? "White" : "Black").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(c == color ? Theme.text : Theme.text2)
          }
          .padding(.horizontal, 12).frame(minHeight: 36)
          .background(RoundedRectangle(cornerRadius: 9).fill(c == color ? Theme.surface3 : .clear))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(3).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
  }

  /// A move in the strip: judged dubious or a blunder, else in the book or past it; past the cursor, faint.
  private func tone(_ ply: Int, _ book: Int, _ lost: [Double?]) -> MoveTone {
    if ply >= cursor { return .ghost }
    switch lost[ply].flatMap(moveQuality) {
    case .blunder: return .blunder
    case .dubious: return .dubious
    case nil: return ply < book ? .book : .offBook
    }
  }

  /// "−1.3": what a dubious move or a blunder gave away, in pawns.
  private func badge(_ lost: Double?) -> String? {
    guard let lost, moveQuality(lost) != nil else { return nil }
    return "\u{2212}" + String(format: "%.1f", lost / 100)
  }

  /// The book's moves as arrows, the highlighted one strongest.
  private func bookArrows(_ fen: String, _ choices: [BookChoice], _ highlight: String?) -> [BoardArrow] {
    arrowChoices(choices, highlight).compactMap { choice -> BoardArrow? in
      guard let move = applySan(fen, choice.san) else { return nil }
      return BoardArrow(from: move.from, to: move.to, color: choice.san == highlight ? Theme.accent : Theme.accent.opacity(0.5))
    }
    .jsSorted { reach($1) - reach($0) }
  }

  /// The engine's move where the last one went wrong.
  private func betterArrow(_ fenBefore: String, _ best: String?) -> [BoardArrow] {
    guard let best, let move = applyUci(fenBefore, best) else { return [] }
    return [BoardArrow(from: move.from, to: move.to, color: Theme.good)]
  }

  /// How many moves at the start of a line are already saved: in the Playbook, or in this sitting's held lines.
  private func held(_ line: [String]) -> Int {
    if hold {
      return saved.filter { $0.color == color }.map { zip($0.sans, line).prefix { $0.0 == $0.1 }.count }.max() ?? 0
    }
    return savedPlies(store.state.playbookList.first { $0.color == color }, line)
  }

  private func keep(_ line: BoardLine) {
    saved.append(line)
    justSaved = true
  }

  private func setLine(_ next: [String]) {
    replyFor += 1
    thinking = false
    moves = next
    cursor = next.count
  }

  /// The opponent's move: the book's most played, else the engine's best.
  private func moveOpponent(_ visible: [String], _ fen: String, _ book: String?) {
    if let book {
      setLine(visible + [book])
      return
    }
    replyFor += 1
    let token = replyFor
    thinking = true
    Task {
      let snap = await HintEngine.shared.analyse(fen, EngineLimits(depth: 12, movetime: 800, multiPv: 1))
      guard replyFor == token else { return }
      thinking = false
      guard let uci = snap.lines.first?.pv.first, let move = applyUci(fen, uci) else { return }
      setLine(visible + [move.san])
    }
  }

  private func seek(_ n: Int) {
    replyFor += 1
    thinking = false
    cursor = max(0, min(moves.count, n))
  }

  /// How far an arrow goes, in squares.
  private func reach(_ arrow: BoardArrow) -> Double {
    let f = Array(arrow.from.utf8), t = Array(arrow.to.utf8)
    return hypot(Double(Int(t[0]) - Int(f[0])), Double(Int(t[1]) - Int(f[1])))
  }

  /// "Italian Game: Giuoco Pianissimo" as its family and the rest.
  private func splitName(_ name: String?) -> (String?, String?) {
    guard let name else { return (nil, nil) }
    guard let at = name.range(of: ": ") else { return (name, nil) }
    return (String(name[..<at.lowerBound]), String(name[at.upperBound...]))
  }
}
