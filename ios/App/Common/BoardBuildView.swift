import ChessCore
import Book
import Model
import Shared
import SwiftUI

/// A line saved from the board, with what the engine said of each move when it is held back.
struct BoardLine: Equatable {
  var color: ChessCore.Color
  var sans: [String]
  var lost: [Double?]?
}

/// Play on the board: build a Playbook by playing the moves in. You play
/// your side and the book answers for the other, unless Book replies is
/// off. The arrows are the book's most played moves, one lit by the style
/// you pick. Shared by onboarding and the Playbook tab. `BoardScreen.tsx`.
struct BoardBuildView: View {
  let onBack: () -> Void
  let onDone: ([BoardLine]) -> Void
  var doneLabel = "Done"
  /// Hand the saved lines to `onDone` without putting them in the Playbook.
  var hold = false

  @Environment(AppStore.self) private var store
  @State private var color = ChessCore.Color.w
  @State private var flipped = false
  @State private var replies = true
  @State private var moves: [String] = []
  @State private var cursor = 0
  @State private var style = Style.popular
  @State private var saved: [BoardLine] = []
  @State private var saving: [String]?
  /// Bumped whenever the line changes by hand, so a book reply on its way to an older line is dropped.
  @State private var replyFor = 0

  /// How long the book waits before it answers your move.
  static let replyDelay = Duration.milliseconds(350)

  var body: some View {
    if let index = store.index, let tree = store.tree {
      content(index, tree)
    }
  }

  @ViewBuilder private func content(_ index: ReferenceIndex, _ tree: OpeningTree) -> some View {
    let visible = Array(moves.prefix(cursor))
    let fen = walkSan(visible).fens.last!
    let mine = turnAfter(visible) == color
    let choices = bookChoices(index, fen)
    let picks: [Style: String] = mine
      ? Dictionary(uniqueKeysWithValues: STYLES.compactMap { s in stylePick(index, tree, visible, choices, s.id).map { (s.id, $0) } }) : [:]
    let highlight = mine ? (picks[style] ?? picks[.popular]) : choices.first?.san
    let arrows = arrowChoices(choices, highlight).compactMap { choice -> BoardArrow? in
      guard let move = applySan(fen, choice.san) else { return nil }
      return BoardArrow(from: move.from, to: move.to, color: choice.san == highlight ? Theme.accent : Theme.accent.opacity(0.5))
    }
    .jsSorted { reach($1) - reach($0) }
    let styles = mine ? shownStyles(picks, style) : []
    let opening = openingNameForPath(index, visible)
    let (family, variation) = splitName(opening?.name)
    let toSave = !visible.isEmpty && turnAfter(visible) == color ? Array(visible.dropLast()) : visible
    let savable = !toSave.isEmpty && toSave.indices.contains { ($0 % 2 == 0) == (color == .w) }

    VStack(spacing: 0) {
      AppBar(title: family ?? "On the board", subtitle: variation, onBack: onBack) {
        IconButton(icon: "flip") { flipped.toggle() }
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          HStack(spacing: 10) {
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
            Spacer()
            Button { replies.toggle() } label: {
              HStack(spacing: 8) {
                Text("Book replies").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(replies ? "On" : "Off").font(.system(size: 12, weight: .heavy))
                  .foregroundStyle(replies ? Theme.accentInk : Theme.text2).padding(.horizontal, 8).padding(.vertical, 2)
                  .background(Capsule().fill(replies ? Theme.accent : Theme.surface3))
              }
              .padding(.leading, 12).padding(.trailing, 6).padding(.vertical, 6)
              .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
              .overlay {
                if moves.isEmpty && saved.isEmpty {
                  RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.accent, lineWidth: 2).shadow(color: Theme.accent.opacity(0.7), radius: 9)
                }
              }
            }
            .buttonStyle(.plain)
          }
          .padding(.bottom, 10)
          BoardView(fen: fen, orientation: flipped ? color.other : color, interactive: true, bothSides: true,
                    lastMove: lastMoveOf(visible), arrows: arrows) { move in play(move, visible, index) }
          MoveStrip(
            items: moves.enumerated().map { i, san in
              StripItem(san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, tone: i >= cursor ? .ghost : nil, current: i == cursor - 1, seek: i + 1)
            },
            cursor: cursor, max: moves.count, onSeek: seek, hint: "Play a move"
          )
          .padding(.top, 10)
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
      HStack(spacing: 10) {
        SheetButton("Save line", style: .accent) { saving = toSave }.disabled(!savable)
        SheetButton(doneLabel, style: .plain) { onDone(saved) }.frame(width: 110)
      }
      .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
      .background(Theme.background.opacity(0.92))
      .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }
    }
    .task(id: "\(color.rawValue) \(replies)") {
      // Playing Black from the start, the book makes White's first move for you.
      guard replies, !mine, cursor == 0, let reply = choices.first else { return }
      let token = replyFor
      try? await Task.sleep(for: Self.replyDelay)
      if replyFor == token && !Task.isCancelled { setLine(visible + [reply.san]) }
    }
    .sheet(item: Binding(get: { saving.map { LineRef(sans: $0) } }, set: { saving = $0?.sans })) { ref in
      SaveSheet(sans: ref.sans, color: color, source: .board,
                onSaved: { _, _, line in saved.append(BoardLine(color: color, sans: line)) },
                onKeep: hold ? { line, _, lost in saved.append(BoardLine(color: color, sans: line, lost: lost)) } : nil,
                onClose: { saving = nil })
        .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
  }

  private func setLine(_ next: [String]) {
    replyFor += 1
    moves = next
    cursor = next.count
  }

  private func play(_ move: LegalMove, _ visible: [String], _ index: ReferenceIndex) {
    let next = visible + [move.san]
    setLine(next)
    guard replies, turnAfter(next) != color else { return }
    let token = replyFor
    Task {
      try? await Task.sleep(for: Self.replyDelay)
      guard replyFor == token, let reply = bookChoices(index, walkSan(next).fens.last!).first else { return }
      setLine(next + [reply.san])
    }
  }

  private func seek(_ n: Int) {
    replyFor += 1
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
