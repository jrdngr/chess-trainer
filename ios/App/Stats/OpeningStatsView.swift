import Model
import Shared
import SwiftUI

/// One opening's page: its rating and ladder, its charts, its modes and its
/// played variations.
struct OpeningStatsView: View {
  let tree: OpeningTree
  let node: OpeningNode
  @Binding var days: Int
  let onOpen: (String) -> Void
  let onBack: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let score = store.state.score
    let stats = nodeStats(score, node.id)
    let trail = ancestorsOf(tree, node.id).dropLast().filter { $0.name != node.name }
    VStack(spacing: 0) {
      PageBar(title: node.name, subtitle: trail.isEmpty ? bookMoveText(node.sans) : trail.map(\.name).joined(separator: " \u{203a} "), onBack: onBack) { EmptyView() }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          hero(stats)
          selectButton.padding(.top, 12)
          StatsSection(title: "Window")
          SegmentedControl(value: $days, options: STATS_WINDOWS)
          let climb = ratingOverTime(stats, days)
          if !climb.isEmpty {
            StatsSection(title: "Rating over time")
            StatsCard { LineChart(points: climb, color: Theme.accent) }
          }
          AccuracySection(stats: stats, days: days)
          StatsSection(title: "By mode", aside: "rounds")
          ListCard { ForEach(ACTIVITY_MODES, id: \.self) { modeRow($0, stats.byMode[$0]) } }
          children(score)
          if stats.lastAt != nil {
            StatsNote(
              text: Text("\(colorSquare) Rounds and accuracy here count every game played through this position, in any mode. Only Play moves the rating."),
              center: true
            )
            .padding(.top, 12)
          }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 44)
      }
      .defaultScrollAnchor(StatsDebug.scrollToBottom ? .bottom : .top)
    }
  }

  private func hero(_ stats: NodeStats) -> some View {
    let rank = rankOf(stats.rating, stats.rated)
    let rounds = roundsOf(stats)
    let acc = accuracy(answered: stats.answered, correct: stats.correct)
    let label = rank.heldLabel + (node.eco.map { " \u{00b7} \($0)" } ?? "") + " \u{00b7} " + bookMoveText(node.sans)
    return StatsHero(big: stats.rated == 0 ? "\u{2014}" : ratingText(stats.rating), label: label) {
      FlowRow(spacing: 8) {
        StatsPill(bold: "\(rounds)", text: rounds == 1 ? "round" : "rounds")
        if let acc { StatsPill(bold: percentText(acc), text: "accuracy") }
        if stats.bestRun > 0 { StatsPill(bold: "\(stats.bestRun)", text: "best run") }
        if let last = stats.lastAt { StatsPill(text: "last \(shortDate(last))") }
      }
      .padding(.top, 16)
      StatsLadder(rating: stats.rating, rated: stats.rated).padding(.top, 16)
      if stats.extRated > 0 {
        VStack(alignment: .leading, spacing: 4) {
          Text("Extensions").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ext)
          StatsLadder(rating: stats.extRating, rated: stats.extRated)
        }
        .padding(.top, 14)
      }
    }
  }

  private var selectButton: some View {
    let selected = store.state.settings.selection.opening == node.id
    return Button { store.update { $0.settings.selection.opening = node.id } } label: {
      Text(selected ? "Selected" : "Select this opening").font(.system(size: 16, weight: .semibold)).tracking(-0.16)
        .foregroundStyle(selected ? Theme.text : Color(hex: 0x0b0b0e))
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.surface : Theme.text))
        .opacity(selected ? 0.35 : 1)
    }
    .buttonStyle(.plain).disabled(selected)
  }

  private func modeRow(_ mode: ActivityMode, _ tally: ModeTally?) -> some View {
    let (rounds, answered, correct) = (tally?.rounds ?? 0, tally?.answered ?? 0, tally?.correct ?? 0)
    let share = answered > 0 ? " \u{00b7} \(percentText(Double(correct) / Double(answered)))" : ""
    return HStack(spacing: 12) {
      Text(modeName(mode)).font(.system(size: 13)).foregroundStyle(Theme.text2).frame(maxWidth: .infinity, alignment: .leading)
      Text((rounds == 1 ? "1 round" : "\(rounds) rounds") + share).font(.system(size: 12.5)).foregroundStyle(Theme.text3)
    }
    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
  }

  @ViewBuilder private func children(_ score: ScoreState) -> some View {
    let kids = orderedChildren(node).filter { nodeStats(score, $0.id).answered > 0 }
      .jsSorted { a, b in Double(roundsOf(nodeStats(score, b.id)) - roundsOf(nodeStats(score, a.id))) }
    if !kids.isEmpty {
      StatsSection(title: node.depth == 1 ? "Openings" : "Variations", aside: "by rounds")
      ListCard {
        ForEach(kids, id: \.id) { kid in
          let stats = nodeStats(score, kid.id)
          StatsRow(
            dot: rankOf(stats.rating).held.map { Color(hexString: $0.color) }, title: kid.name,
            meta: (kid.eco.map { "\($0) \u{00b7} " } ?? "") + bookMoveText(kid.sans),
            value: "\(roundsOf(stats))", dotTrailing: true
          ) { onOpen(kid.id) }
        }
      }
    }
  }

  /// The side you play, drawn inline with the note.
  private var colorSquare: Image {
    let renderer = ImageRenderer(content: ColorSquare(choice: store.state.settings.selection.color, size: 10))
    renderer.scale = 3
    return Image(uiImage: renderer.uiImage ?? UIImage())
  }
}
