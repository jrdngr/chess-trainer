import ChessCore
import Model
import SwiftUI

/// The browser's top row: back or close, the side, undo and search. `.bp-top`.
struct BrowseTopBar: View {
  @Binding var side: ChessCore.Color
  var canUndo: Bool
  var onBack: (() -> Void)?
  var onClose: () -> Void
  var onUndo: () -> Void
  var onSearch: () -> Void

  var body: some View {
    HStack(spacing: 2) {
      if let onBack {
        RoundIconButton(icon: "back", plain: true, size: 44, action: onBack)
      } else {
        RoundIconButton(icon: "close", plain: true, size: 44, action: onClose)
      }
      SideSwitch(side: $side, square: { ColorSquare(choice: $0 == .w ? .w : .b, size: 12) }).padding(.leading, 4)
      Spacer(minLength: 0)
      RoundIconButton(icon: "undo", plain: true, disabled: !canUndo, size: 44, action: onUndo)
      RoundIconButton(icon: "search", plain: true, size: 44, action: onSearch)
      if onBack != nil { RoundIconButton(icon: "close", plain: true, size: 44, action: onClose) }
    }
    .padding(.horizontal, -8)
  }
}

/// White or Black, each with its square: `.segmented.build-side`.
struct SideSwitch<Square: View>: View {
  @Binding var side: ChessCore.Color
  @ViewBuilder var square: (ChessCore.Color) -> Square
  var height: CGFloat = 34

  var body: some View {
    HStack(spacing: 2) {
      ForEach([ChessCore.Color.w, .b], id: \.self) { c in
        Button { side = c } label: {
          HStack(spacing: 6) {
            square(c)
            Text(c == .w ? "White" : "Black").font(.system(size: 13.5, weight: .semibold))
          }
          .foregroundStyle(c == side ? Theme.text : Theme.text2)
          .padding(.horizontal, 12).frame(minHeight: height)
          .background(RoundedRectangle(cornerRadius: 9).fill(c == side ? Theme.surface3 : .clear))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(3)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
  }
}

/// What is on the board, by name and moves, with its tier, its star and Choose. `.bp-bar`.
struct BrowseNameBar: View {
  let ctx: BrowseContext
  let moves: [String]
  let onStar: (String) -> Void
  let onChoose: () -> Void

  var body: some View {
    let node = moves.isEmpty ? nil : nodeAt(ctx.tree, moves)
    let exact = node.flatMap { $0.depth > 0 && !$0.custom ? $0 : nil }
    let stats = exact.flatMap { ctx.state.score.nodes[$0.id] }
    let held = stats.flatMap { $0.rated > 0 ? rankOf($0.rating, $0.rated).held : nil }
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(lineName(ctx.tree, ctx.catalog, moves)).font(.system(size: 15.5, weight: .bold)).foregroundStyle(Theme.text)
        Text(moves.isEmpty ? "Every line" : moveText(moves)).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
          .lineLimit(1).truncationMode(.head)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let held, let stats {
        Text("\(held.name) \(Int(JSRound(stats.rating)))").font(.system(size: 13, weight: .semibold))
          .foregroundStyle(SwiftUI.Color(hexString: held.color)).lineLimit(1)
      }
      if let exact {
        let starred = ctx.state.settings.favoriteOpenings.contains(exact.id)
        Button { onStar(exact.id) } label: {
          Icon(name: "star", size: 20, filled: starred).foregroundStyle(Theme.text2).frame(width: 40, height: 44)
        }
        .buttonStyle(.plain)
      }
      Button(action: onChoose) {
        Text("Choose").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accentInk)
          .padding(.horizontal, 16).frame(minHeight: 44)
          .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent))
      }
      .buttonStyle(.plain)
    }
    .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8).frame(minHeight: 60)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
  }
}

/// The book's moves from here, each named for where it goes. The browser's list with no chip on.
struct NextMovesList: View {
  let moves: [NextMove]
  let onPlay: (String) -> Void

  var body: some View {
    VStack(spacing: 0) {
      BrowseHead(text: "Next")
      if moves.isEmpty { BrowseEmpty(text: "The book has nothing after this", inset: true) }
      ForEach(Array(moves.enumerated()), id: \.element.san) { i, move in
        if i > 0 { BrowseDivider() }
        Button { onPlay(move.san) } label: {
          HStack(spacing: 12) {
            Text(move.label).font(.system(size: 14, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text)
              .frame(width: 64, alignment: .leading)
            Text(move.name).font(.system(size: 14.5)).foregroundStyle(Theme.text2).lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
            if move.mine { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
            Text("\(Int(JSRound(move.share)))%").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text3)
              .frame(width: 36, alignment: .trailing)
          }
          .padding(.horizontal, 14).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .background(Theme.surface)
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }
}
