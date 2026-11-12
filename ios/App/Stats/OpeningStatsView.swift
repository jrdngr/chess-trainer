import Game
import Model
import Shared
import SwiftUI

/// One opening's page: its rating and tier, its charts, its modes and its
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
          SegmentedControl(value: $days, options: STATS_WINDOWS).padding(.top, 24)
          let climb = ratingOverTime(stats, days)
          if !climb.isEmpty {
            StatsSection(title: "Rating over time", first: true)
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

  /// The rating and its tier, one bar toward the next tier, then the opening's numbers in a row.
  private func hero(_ stats: NodeStats) -> some View {
    let rank = rankOf(stats.rating, stats.rated)
    let rounds = roundsOf(stats)
    let acc = accuracy(answered: stats.answered, correct: stats.correct)
    return StatsHero(big: stats.rated == 0 ? "\u{2014}" : ratingText(stats.rating), label: rank.heldLabel) {
      TierBar(rating: stats.rating, rated: stats.rated, label: false).padding(.top, 10)
      HStack {
        Text(ratingText(rank.floor))
        Spacer()
        if let next = rank.nextLabel { Text("\(next) at \(ratingText(rank.ceiling))") }
      }
      .font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
      HStack(alignment: .top, spacing: 0) {
        figure("\(rounds)", rounds == 1 ? "round" : "rounds")
        if let acc { figure(percentText(acc), "accuracy") }
        if let last = stats.lastAt { figure(shortDate(last), "last played") }
      }
      .padding(.top, 18)
    }
  }

  private func figure(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
      Text(label).font(.system(size: 12)).foregroundStyle(Theme.text3)
    }
    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
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
