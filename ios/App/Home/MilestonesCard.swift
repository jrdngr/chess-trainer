import Model
import SwiftUI

/// The next four milestones to earn, ringed by how close they are; all of
/// them in a sheet.
struct MilestonesCard: View {
  @Environment(AppStore.self) private var store
  @State private var open = false

  var body: some View {
    let list = store.tree.map { milestones(store.state.score, store.state.survival, $0) } ?? []
    let days = streak(store.state.score.global)
    let done = list.filter(earned).count
    // The streak always leads; the three closest of the rest follow it.
    let rest = list.filter { $0.kind != .streak }
    let next = nextUp(rest, 3)
    Button { open = true } label: {
      HomeCard(title: "Milestones", aside: "\(done) of \(list.count)") {
        HStack(spacing: 6) {
          StreakBadge(days: days).frame(maxWidth: .infinity)
          ForEach(next.isEmpty ? Array(rest.suffix(3)) : next, id: \.id) { MilestoneBadge(milestone: $0).frame(maxWidth: .infinity) }
        }
      }
    }
    .buttonStyle(.plain)
    .sheet(isPresented: $open) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Milestones").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], spacing: 14) {
            ForEach(list, id: \.id) { MilestoneBadge(milestone: $0) }
          }
        }
        .padding(20)
      }
      .presentationDetents([.medium, .large]).presentationBackground(Theme.background)
    }
  }
}

private let ringRadius: CGFloat = 21

/// A ring of progress around a glyph.
private struct Ring<Glyph: View>: View {
  var share: Double
  var tint: SwiftUI.Color
  var solid = false
  @ViewBuilder var glyph: Glyph

  var body: some View {
    ZStack {
      Circle().fill(solid ? Theme.surface3 : .clear).frame(width: ringRadius * 2, height: ringRadius * 2)
      Circle().stroke(Theme.surface3, lineWidth: 4).frame(width: ringRadius * 2, height: ringRadius * 2)
      if share > 0 {
        Circle().trim(from: 0, to: share).stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
          .rotationEffect(.degrees(-90)).frame(width: ringRadius * 2, height: ringRadius * 2)
      }
      glyph
    }
    .frame(width: 52, height: 52)
  }
}

/// Your current streak: the days in the middle, ringed toward the next streak milestone.
struct StreakBadge: View {
  var days: Int
  static let steps = [3, 7, 30]

  var body: some View {
    let goal = Self.steps.first { $0 > days }
    let share = goal.map { Double(days) / Double($0) } ?? 1
    let lit = days > 0
    VStack(spacing: 4) {
      Ring(share: share, tint: Theme.warn) {
        VStack(spacing: 0) {
          Icon(name: "flame", size: 13, filled: lit)
          Text("\(days)").font(.system(size: 13, weight: .heavy).monospacedDigit())
        }
        .foregroundStyle(lit ? Theme.warn : Theme.text3)
      }
      Text(days == 1 ? "1 day" : "\(days) days").font(.system(size: 11)).foregroundStyle(lit ? Theme.text2 : Theme.text3).lineLimit(1)
    }
  }
}

/// One milestone: lit when earned, dimmed with a ring of progress when not. `Badge`.
struct MilestoneBadge: View {
  var milestone: Milestone

  var body: some View {
    let won = earned(milestone)
    let tint = milestone.color.map { SwiftUI.Color(hexString: $0) } ?? (milestone.kind == .streak ? Theme.warn : Theme.accent)
    VStack(spacing: 4) {
      Ring(share: won ? 0 : progress(milestone), tint: tint, solid: won) {
        glyph(won).foregroundStyle(won ? tint : Theme.text3)
      }
      Text(milestone.label).font(.system(size: 11)).foregroundStyle(won ? Theme.text2 : Theme.text3).lineLimit(1)
    }
  }

  @ViewBuilder private func glyph(_ won: Bool) -> some View {
    switch milestone.kind {
    case .streak: Icon(name: "flame", size: 20, filled: won)
    case .tier: Icon(name: "star", size: 20, filled: won)
    case .breadth: Icon(name: "tree", size: 20)
    case .survival: Text("\(Int(milestone.target))").font(.system(size: 13, weight: .heavy).monospacedDigit())
    case .rounds:
      Text(milestone.target >= 1000 ? "\(Int(milestone.target) / 1000)k" : "\(Int(milestone.target))")
        .font(.system(size: 13, weight: .heavy).monospacedDigit())
    }
  }
}
