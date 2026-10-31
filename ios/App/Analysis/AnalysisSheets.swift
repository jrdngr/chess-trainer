import Book
import ChessCore
import SwiftUI

/// The sheets Analysis opens over itself.
enum AnalysisSheet: Identifiable {
  case pgn
  case bookLine(BookLine)
  case game(ReferenceGame)
  case save(SaveRequest)

  var id: String {
    switch self {
    case .pgn: return "pgn"
    case .bookLine(let line): return "line:\(line.id)"
    case .game(let game): return "game:\(game.id)"
    case .save(let request): return "save:\(request.id)"
    }
  }
}

/// Where the debug hooks can scroll to.
enum AnalysisAnchor: Hashable { case reference, named }

extension AnalysisTab {
  @ViewBuilder func sheetView(_ which: AnalysisSheet) -> some View {
    let close = { sheet = nil }
    switch which {
    case .pgn:
      PgnSheet(text: $pgnText, visible: visible, haptics: store.state.settings.hapticFeedback, onLoad: { moves in
        load(moves)
        close()
      }, onToast: show, onClose: close)
    case .bookLine(let line):
      BookLineSheet(line: line, onPlay: { moves in
        load(moves)
        close()
      }, onAdd: { line in
        sheet = .save(SaveRequest(sans: line.moves, note: line.summary, title: line.name, color: line.forColor))
      }, onClose: close)
    case .game(let game):
      GameSheet(game: game, onReplay: {
        load(game.moves, at: min(game.moves.count, visible.count + 2))
        close()
      }, onClose: close)
    case .save(let request):
      SaveSheet(sans: request.sans, preferColor: request.color, trim: true, title: request.title, source: .analysis, note: request.note, onClose: close)
    }
  }

  /* ── debug hooks, for screenshots ── */

  /// `ANALYSIS_LINE="e4 c5 Nf3"` opens on that line.
  static var debugLine: [String]? {
    #if DEBUG
      ProcessInfo.processInfo.environment["ANALYSIS_LINE"].map { $0.split(separator: " ").map(String.init) }
    #else
      nil
    #endif
  }

  /// `ANALYSIS_SHEET=pgn|line|save|game` opens on a sheet.
  static func debugSheet(_ line: [String]) -> AnalysisSheet? {
    #if DEBUG
      switch ProcessInfo.processInfo.environment["ANALYSIS_SHEET"] {
      case "pgn": return .pgn
      case "line": return bookLinesFrom(line).first.map { .bookLine($0) }
      case "save": return .save(SaveRequest(sans: line, title: "Save line"))
      case "game": return topGames(walkSan(line).fens.last!).first.map { .game($0) }
      default: return nil
      }
    #else
      return nil
    #endif
  }

  /// `ANALYSIS_SCROLL=reference|named|bottom` scrolls there once open.
  func debugScroll(_ proxy: ScrollViewProxy) async {
    #if DEBUG
      guard let to = ProcessInfo.processInfo.environment["ANALYSIS_SCROLL"] else { return }
      try? await Task.sleep(for: .milliseconds(600))
      switch to {
      case "reference": proxy.scrollTo(AnalysisAnchor.reference, anchor: .top)
      case "named": proxy.scrollTo(AnalysisAnchor.named, anchor: .top)
      default: proxy.scrollTo(AnalysisAnchor.named, anchor: .bottom)
      }
    #endif
  }
}

/// The bar over Analysis: Back when opened over a mode, the opening's name
/// (or "Analysis"), Flip and PGN.
struct AnalysisAppBar: View {
  let opening: OpeningName?
  let onBack: (() -> Void)?
  let onFlip: () -> Void
  let onPgn: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if let onBack { AnalysisIconButton(icon: "back", label: "Back", action: onBack) }
      VStack(alignment: .leading, spacing: 1) {
        if let opening {
          Text(opening.name).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text).lineSpacing(2)
          Text(opening.eco).font(.system(size: 13)).foregroundStyle(Theme.text2)
        } else {
          Text("Analysis").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      AnalysisIconButton(icon: "flip", label: "Flip board", action: onFlip)
      AnalysisIconButton(icon: "note", label: "PGN", action: onPgn)
    }
    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10).frame(minHeight: 56)
  }
}

/// What to save, as the Save sheet is asked: the whole line, a note, a side to suggest.
struct SaveRequest: Identifiable {
  var sans: [String]
  var note: String?
  var title: String
  var color: ChessCore.Color?
  var id: String { "\(title)|\(sans.joined(separator: " "))" }
}
