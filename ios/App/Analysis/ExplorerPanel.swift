import Book
import ChessCore
import Shared
import SwiftUI

/// The book's moves from a position, its famous games, and where it all
/// comes from.
struct ExplorerPanel: View {
  let index: ReferenceIndex
  let fen: String
  /// SAN path to this position, used to name the opening.
  let path: [String]
  /// Moves already in the user's playbook from this position.
  var inPlaybook: [String] = []
  let onPlay: (String) -> Void
  var onPickGame: ((ReferenceGame) -> Void)?

  var body: some View {
    let entry = lookup(index, fen)
    let named = openingNameForPath(index, path)
    if let entry, !entry.moves.isEmpty {
      list(entry, named)
    } else {
      VStack(alignment: .leading, spacing: 6) {
        if let named {
          HStack {
            Text(named.name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            AnalysisChip(text: named.eco)
          }
        }
        Text("No reference games").font(.system(size: 13)).foregroundStyle(Theme.text3)
      }
      .frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    }
  }

  private func list(_ entry: ExplorerEntry, _ named: OpeningName?) -> some View {
    let total = totalGamesAt(entry)
    let name = named?.name ?? entry.opening
    let eco = named?.eco ?? entry.eco
    let games = topGames(fen)
    return VStack(spacing: 0) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 1) {
          if let name { Text(name).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1) }
          Text("\(formatGameCount(total)) games").font(.system(size: 12.5)).foregroundStyle(Theme.text3)
        }
        Spacer(minLength: 0)
        if let eco { AnalysisChip(text: eco) }
      }
      .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
      ForEach(Array(entry.moves.enumerated()), id: \.element.san) { i, move in
        if i > 0 { divider }
        ExplorerRow(move: move, total: total, inPlaybook: inPlaybook.contains(move.san)) { onPlay(move.san) }
      }
      if !games.isEmpty {
        divider
        HStack {
          Text("Games").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
          Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        ForEach(Array(games.enumerated()), id: \.offset) { i, game in
          if i > 0 { divider }
          gameRow(game)
        }
      }
      Text(bookSource(index)).font(.system(size: 13)).foregroundStyle(Theme.text3)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 10)
    }
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
    .clipShape(RoundedRectangle(cornerRadius: 16))
  }

  private var divider: some View { Rectangle().fill(.white.opacity(0.07)).frame(height: 1) }

  private func gameRow(_ game: ReferenceGame) -> some View {
    Button { onPickGame?(game) } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(game.white) \u{2013} \(game.black)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          Text([game.event, String(game.year)].compactMap { $0 }.joined(separator: " \u{00b7} "))
            .font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
        }
        Spacer(minLength: 0)
        AnalysisChip(text: game.result)
        Icon(name: "chevron", size: 16).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// One book move: its share of games, and how they went. `ExplorerRow`.
private struct ExplorerRow: View {
  let move: ExplorerMove
  let total: Double
  let inPlaybook: Bool
  let onPlay: () -> Void

  var body: some View {
    let pct = movePercent(move, total)
    let results = (move.white + move.draw + move.black) == 0 ? 1 : move.white + move.draw + move.black
    Button(action: onPlay) {
      HStack(spacing: 12) {
        HStack(spacing: 4) {
          Text(move.san).font(.system(size: 16, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
          if inPlaybook { Icon(name: "star", size: 12, filled: true).foregroundStyle(Theme.accent) }
        }
        .frame(minWidth: 54, alignment: .leading)
        ResultBar(white: move.white / results * 100, draw: move.draw / results * 100, black: move.black / results * 100)
        VStack(alignment: .trailing, spacing: 2) {
          Text(pct >= 1 ? "\(Int(JS.round(pct)))%" : "<1%").font(.system(size: 14, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.text)
          Text(formatGameCount(move.games)).font(.system(size: 11, weight: .medium).monospacedDigit()).foregroundStyle(Theme.text3)
        }
        .frame(minWidth: 44, alignment: .trailing)
      }
      .padding(.horizontal, 16).padding(.vertical, 11).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// White's wins, draws and Black's wins across one bar: `.exp-bar`.
private struct ResultBar: View {
  let white: Double
  let draw: Double
  let black: Double

  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 0) {
        part(white, geo.size.width, SwiftUI.Color(hex: 0xececef), SwiftUI.Color(hex: 0x111111))
        part(draw, geo.size.width, SwiftUI.Color(hex: 0x6f6f7a), .white)
        part(black, geo.size.width, SwiftUI.Color(hex: 0x2f2f37), SwiftUI.Color(hex: 0xd4d4dc))
      }
    }
    .frame(minWidth: 70).frame(height: 18)
    .background(Theme.surface2)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }

  private func part(_ pct: Double, _ width: CGFloat, _ bg: SwiftUI.Color, _ fg: SwiftUI.Color) -> some View {
    Text(pct > 17 ? "\(Int(JS.round(pct)))" : "").font(.system(size: 10, weight: .bold).monospacedDigit()).foregroundStyle(fg)
      .frame(width: width * pct / 100, height: 18).background(bg)
  }
}

/// Where the book comes from: `BOOK_SOURCE`, "Lichess Elite 2025-11 · 280,246 games".
func bookSource(_ index: ReferenceIndex) -> String {
  let games = index.totalGames.formatted(.number.locale(Locale(identifier: "en_US")))
  return [BookFile.source, "\(games) games"].compactMap { $0 }.joined(separator: " \u{00b7} ")
}

/// The book file's own name for its source, read from its head.
private enum BookFile {
  static let source: String? = {
    guard let url = Bundle.main.url(forResource: "book", withExtension: "json"),
      let handle = try? FileHandle(forReadingFrom: url), let head = (try? handle.read(upToCount: 400)).flatMap({ data in
        try? handle.close()
        return data
      }),
      let text = String(data: head, encoding: .utf8),
      let match = text.firstMatch(of: /"source":"([^"]*)"/)
    else { return nil }
    return String(match.1)
  }()
}
