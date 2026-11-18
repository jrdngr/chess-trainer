import Book
import ChessCore
import Game
import Model
import SwiftUI

/// An opening of yours on the tree, at its position: the board and the moves to
/// it, its form, Grow as the curve allows it, Analyze and Select. Its menu deletes it.
struct OpeningPage: View {
  let tree: OpeningTree
  let node: MapNode
  let onBack: () -> Void
  /// Grow this hole under the opening.
  let onGrow: (Gap) -> Void
  /// Analysis on the opening's position.
  let onAnalyze: ([String], ChessCore.Color) -> Void
  /// Back to the tree, open at the opening the curve grows next.
  let onShowNext: () -> Void
  /// The opening is now Play's selection.
  let onSelected: () -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var memo = Memo<NodePage>()
  @State private var cursor: Int?
  @State private var deleting = false

  var body: some View {
    if let rep = store.state.playbookList.first(where: { $0.color == node.color }), nodeAtLine(rep, node.line) != nil {
      content(page)
    } else {
      Color.clear.onAppear(perform: onBack)
    }
  }

  /// The page's numbers, kept until the Playbook, the games or the form change.
  private var page: NodePage {
    let state = store.state
    let key = state.playbookList.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ",")
      + "|\(lastAddedAt(state.playbookList))|\(state.games.count)|\(state.form.stamp)"
    return memo.get(key) { nodePage(state, tree, side: node.color, id: node.id, line: node.line) }
  }

  private func content(_ page: NodePage) -> some View {
    let removes = store.state.movesUnder(node.color, node.line)
    return VStack(spacing: 0) {
      AppBar(title: node.name, onBack: onBack) {
        Menu {
          Button(role: .destructive) { deleting = true } label: { Label("Delete", systemImage: "trash") }
        } label: {
          Icon(name: "more", size: 20).foregroundStyle(Theme.text).frame(width: 38, height: 38).background(Circle().fill(Theme.surface))
        }
        .accessibilityLabel("More")
      }
      ScrollView {
        VStack(spacing: 12) {
          board
          VStack(spacing: 12) {
            accuracy(page)
            growCard(page.grow)
            HStack(spacing: 8) {
              SheetButton("Analyze", icon: "analysis", style: .plain) { onAnalyze(node.line, node.color) }
              SheetButton("Select", icon: "check", style: .accent) { select() }
                .unlockedBy(.openingPicker, hidden: true)
            }
          }
          .padding(.horizontal, 16)
        }
        .padding(.bottom, 28)
      }
    }
    .confirmationDialog("Delete \(node.name)?", isPresented: $deleting, titleVisibility: .visible) {
      Button("Delete \(removes) \(removes == 1 ? "move" : "moves")", role: .destructive) { delete(removes) }
    }
  }

  /// The board at the opening's position, the full width of the screen, and under it
  /// the moves to the position to step back through.
  private var board: some View {
    let at = cursor ?? node.line.count
    return VStack(spacing: 10) {
      GeometryReader { geo in
        MiniBoard(sans: Array(node.line.prefix(at)), orientation: node.color, size: geo.size.width, lastMove: true)
      }
      .aspectRatio(1, contentMode: .fit)
      MoveStrip(
        items: node.line.enumerated().map { i, san in
          StripItem(san: san, label: i % 2 == 0 ? "\(i / 2 + 1)." : nil, current: i + 1 == at, seek: i + 1)
        },
        cursor: at, max: node.line.count, onSeek: { cursor = $0 })
      .padding(.horizontal, 16)
    }
  }

  /// The opening's form: its ring, and its last answers in a row.
  private func accuracy(_ page: NodePage) -> some View {
    HStack(spacing: 14) {
      FormRing(form: page.form, size: 52, lineWidth: 4.5, value: true)
      VStack(alignment: .leading, spacing: 7) {
        Text("LAST \(FORM_ANSWERS) ANSWERS").font(.system(size: 11.5, weight: .bold)).tracking(0.6).foregroundStyle(Theme.text2)
        AnswerMarks(answers: page.answers)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16).padding(.vertical, 14)
    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
  }

  @ViewBuilder private func growCard(_ grow: NodeGrow) -> some View {
    switch grow {
    case .none: EmptyView()
    case .ready(let gap):
      Button { onGrow(gap) } label: {
        HStack(spacing: 12) {
          Icon(name: "sprout", size: 22)
          Text("Grow").font(.system(size: 17, weight: .heavy)).frame(maxWidth: .infinity, alignment: .leading)
          Text(gap.name).font(.system(size: 14, weight: .bold)).lineLimit(1)
        }
        .foregroundStyle(Theme.accentInk).padding(.horizontal, 18).frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.accent))
      }
      .buttonStyle(.plain)
    case .level(let level, let games, let gamesNeeded, let green, let openings):
      waiting(trailing: "Level \(level)") {
        VStack(spacing: 12) {
          need("Games", games, of: gamesNeeded)
          need("Green openings", green, of: openings)
        }
      }
    case .after(let next, let count):
      waiting(trailing: "After \(count) \(count == 1 ? "line" : "lines")") {
        Button(action: onShowNext) {
          HStack(spacing: 8) {
            Text(next.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
            Icon(name: "chevron", size: 16).foregroundStyle(Theme.text2)
          }
          .padding(.horizontal, 14).frame(minHeight: 48)
          .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
        }
        .buttonStyle(.plain)
      }
    }
  }

  /// Grow while it waits: what it waits for under a dimmed title.
  private func waiting<Body: View>(trailing: String, @ViewBuilder _ body: () -> Body) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 10) {
        Icon(name: "sprout", size: 20).foregroundStyle(Theme.text2)
        Text("Grow").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
        Text(trailing).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      }
      body()
    }
    .padding(16).background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
  }

  private func need(_ title: String, _ have: Int, of total: Int) -> some View {
    VStack(spacing: 6) {
      HStack {
        Text(title).foregroundStyle(Theme.text2)
        Spacer()
        Text("\(min(have, total)) / \(total)").fontWeight(.bold).monospacedDigit().foregroundStyle(Theme.text)
      }
      .font(.system(size: 14))
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Theme.surface3)
          Capsule().fill(Theme.accent).frame(width: geo.size.width * CGFloat(min(1, Double(have) / Double(max(total, 1)))))
        }
      }
      .frame(height: 6)
    }
  }

  /// Make this opening and its side Play's selection, as the opening picker does.
  private func select() {
    store.update {
      $0.settings.selection.opening = node.id
      $0.settings.selection.color = node.color == .w ? .w : .b
    }
    onSelected()
  }

  private func delete(_ removes: Int) {
    var undo: PlaybookUndo?
    store.update { undo = $0.removeNodeAt(node.color, node.line) }
    guard let undo else { return }
    toasts.show("Deleted \(removes) move\(removes == 1 ? "" : "s")", action: ("Undo", { store.update { $0.undo(undo) } }))
    onBack()
  }
}

/// An opening's last answers, oldest first, in one row: fast, slow, or missed;
/// empty slots for answers still to come.
struct AnswerMarks: View {
  let answers: [Double]

  var body: some View {
    let shown = Array(answers.suffix(FORM_ANSWERS))
    HStack(spacing: 4) {
      ForEach(0..<FORM_ANSWERS, id: \.self) { i in
        mark(i < shown.count ? shown[i] : nil).frame(maxWidth: .infinity).frame(height: 16)
      }
    }
    .accessibilityElement()
    .accessibilityLabel("\(shown.filter { $0 > 0 }.count) of the last \(shown.count) answers right")
  }

  @ViewBuilder private func mark(_ score: Double?) -> some View {
    if let score {
      if score >= 1 {
        RoundedRectangle(cornerRadius: 4).fill(Theme.good)
      } else if score > 0 {
        RoundedRectangle(cornerRadius: 4).fill(Theme.warn)
      } else {
        RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.bad, lineWidth: 1.5)
      }
    } else {
      RoundedRectangle(cornerRadius: 4).fill(Theme.surface3)
    }
  }
}
