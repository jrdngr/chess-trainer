import Book
import ChessCore
import Model
import Shared
import SwiftUI

/// Home's Recommendations: what the Playbook needs next, grouped by why.
/// "No answer yet" rows are common replies with no answer; "Too short" rows
/// are lines that stop before their named opening does. Up to three show,
/// one of each kind when there is one; More opens up to ten. A tap fills
/// that gap in Growth.
struct RecommendationsCard: View {
  let tree: OpeningTree
  let onPick: (Gap) -> Void
  @Environment(AppStore.self) private var store
  @State private var memo = Memo<[Gap]>()
  @State private var showingAll = false

  var body: some View {
    let all = ranked
    if !all.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline) {
          Text("Recommendations").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
          Spacer()
          if all.count > 3 {
            Button("More") { showingAll = true }
              .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent).buttonStyle(.plain)
          }
        }
        .padding(.bottom, 6)
        GapGroups(gaps: topGaps(all), onPick: onPick)
      }
      .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
      .sheet(isPresented: $showingAll) {
        RecommendationsSheet(gaps: moreGaps(all)) { gap in
          showingAll = false
          onPick(gap)
        } onClose: { showingAll = false }
        .presentationBackground(Theme.background)
      }
    }
  }

  /// Every gap in the Playbook, kept until a line is added or removed.
  private var ranked: [Gap] {
    let state = store.state
    let key = state.repertoireList.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ",")
      + "|\(lastAddedAt(state.repertoireList))|\(state.settings.favoriteOpenings.joined(separator: ","))"
    return memo.get(key) { playbookGaps(state, tree) }
  }
}

/// More recommendations, grouped the same way as on Home.
struct RecommendationsSheet: View {
  let gaps: [Gap]
  let onPick: (Gap) -> Void
  let onClose: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: "Recommendations", onClose: onClose) { EmptyView() }
      ScrollView {
        GapGroups(gaps: gaps, onPick: onPick)
          .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 6)
          .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
          .padding(.horizontal, 16).padding(.bottom, 24)
      }
    }
  }
}

/// Gaps under their kind's heading, breadth first.
struct GapGroups: View {
  let gaps: [Gap]
  let onPick: (Gap) -> Void

  var body: some View {
    let kinds = [GapKind.noAnswer, .tooShort].filter { kind in gaps.contains { $0.kind == kind } }
    VStack(alignment: .leading, spacing: 0) {
      ForEach(Array(kinds.enumerated()), id: \.element) { i, kind in
        if i > 0 { Rectangle().fill(Theme.surface2).frame(height: 1).padding(.top, 8).padding(.bottom, 12) }
        HStack(spacing: 7) {
          Icon(name: kind == .noAnswer ? "tree" : "down", size: 15)
          Text(kind == .noAnswer ? "No answer yet" : "Too short").font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(kind == .noAnswer ? Theme.ext : Theme.book).padding(.bottom, 2)
        ForEach(gaps.filter { $0.kind == kind }, id: \.id) { gap in
          GapRow(gap: gap) { onPick(gap) }
        }
      }
    }
  }
}

/// One recommendation: the side, the opening's name, and the moves.
struct GapRow: View {
  let gap: Gap
  let action: () -> Void

  var body: some View {
    let label = gapLabel(gap.name)
    Button(action: action) {
      HStack(spacing: 10) {
        SideSquare(color: gap.color, size: 15)
        VStack(alignment: .leading, spacing: 1) {
          if let family = label.family {
            Text(family).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.text3).lineLimit(1)
          }
          // The first and last variation names when they fit, else only the last.
          ViewThatFits(in: .horizontal) {
            ForEach(label.lines, id: \.self) { text in
              Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1).fixedSize()
            }
            Text(label.lines.last ?? "").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
              .truncationMode(.tail)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        moves
      }
      .frame(minHeight: label.family == nil ? 44 : 48).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// Your move and the reply with no answer, or your last move and how many are missing.
  private var moves: some View {
    let mine = gap.path.last.map { moveLabel($0, ply: gap.path.count - 1) }
    return HStack(spacing: 0) {
      if let mine {
        Text(mine).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(Theme.text2)
          .padding(.horizontal, 8).padding(.vertical, 5).background(Theme.surface3)
      }
      if gap.kind == .noAnswer {
        Text(mine == nil ? moveLabel(gap.hole.san, ply: gap.path.count) : gap.hole.san)
          .font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundStyle(SwiftUI.Color(hex: 0xd6d7ff))
          .padding(.horizontal, 8).padding(.vertical, 5).background(Theme.ext.opacity(0.28))
      } else {
        Text("+\(gap.missing)").font(.system(size: 13, weight: .heavy).monospacedDigit()).foregroundStyle(SwiftUI.Color(hex: 0xbfe3ff))
          .padding(.horizontal, 8).padding(.vertical, 5).background(Theme.book.opacity(0.28))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 8)).fixedSize()
  }
}

/// A move with its number: "3.c3", "4...Be7".
func moveLabel(_ san: String, ply: Int) -> String {
  "\(ply / 2 + 1)\(ply % 2 == 0 ? "." : "...")\(san)"
}

/// A book name as a row shows it: the family small on top, and under it the
/// first and last variation names, or only the last when both don't fit.
/// A name with no variation is one line.
func gapLabel(_ name: String) -> (family: String?, lines: [String]) {
  guard let colon = name.range(of: ": ") else { return (nil, [name]) }
  let family = String(name[..<colon.lowerBound])
  let parts = name[colon.upperBound...].components(separatedBy: ", ").map { part in
    part.replacingOccurrences(of: #" (Variation|Variations|Defence|Defense|Opening|Game)$"#, with: "", options: .regularExpression)
  }
  guard let last = parts.last else { return (nil, [family]) }
  if parts.count == 1 { return (family, [last]) }
  return (family, ["\(parts[0]), \(last)", last])
}
