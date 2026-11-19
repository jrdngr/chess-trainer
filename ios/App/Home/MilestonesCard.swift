import Game
import Model
import SwiftUI

/// The next four milestones to earn, ringed by how close they are; all of
/// them in a sheet.
struct MilestonesCard: View {
  @Environment(AppStore.self) private var store
  @State private var open = false

  var body: some View {
    let list = milestones(store.state.score, store.state.runRecord)
    let today = store.state.streakNow()
    // The streak always leads; the three closest of the rest follow it.
    let rest = list.filter { $0.kind != .streak }
    let next = nextUp(rest, 3)
    Button { open = true } label: {
      HomeCard(title: "Milestones") {
        HStack(spacing: 6) {
          StreakBadge(today: today, waiting: store.streakWaiting > 0).frame(maxWidth: .infinity)
          ForEach(next.isEmpty ? Array(rest.suffix(3)) : next, id: \.id) { MilestoneBadge(milestone: $0).frame(maxWidth: .infinity) }
        }
      }
    }
    .buttonStyle(.plain)
    // Over the card, its arrow at the streak ring in the first of four columns.
    .tip(text: store.state.homeTip == .dailyRewards ? GameTip.dailyRewards.text : nil, arrow: .down, arrowAt: 0.125) {
      dismissTip(store, .dailyRewards)
    }
    .sheet(isPresented: $open) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("Milestones").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          if today.repairable { StreakRepair() }
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

/// The streak's week: a ring in seven parts, one a day, with the flame and the day in the middle,
/// and under it today's pawns, outlined until today's game pays them.
struct StreakBadge: View {
  var today: StreakToday
  /// Today's pawns are paid but have yet to pop out of the ring.
  var waiting = false

  var body: some View {
    let lit = today.paid && !waiting
    VStack(spacing: 4) {
      ZStack {
        ForEach(0..<7, id: \.self) { i in
          let part = 1.0 / 7
          let gap = 1.6 / (2 * .pi * ringRadius)
          Circle().trim(from: Double(i) * part + gap, to: Double(i + 1) * part - gap)
            .stroke(color(i), style: StrokeStyle(lineWidth: 3.5))
            .rotationEffect(.degrees(-90))
            .frame(width: ringRadius * 2, height: ringRadius * 2)
        }
        VStack(spacing: 0) {
          Icon(name: "flame", size: 12, filled: lit).foregroundStyle(lit ? Theme.warn : Theme.text2)
          Text("\(today.day)").font(.system(size: 13, weight: .heavy).monospacedDigit()).foregroundStyle(Theme.text)
        }
      }
      .frame(width: 52, height: 52)
      .animation(.easeOut(duration: 0.45), value: lit)
      HStack(spacing: 1) {
        PawnMark(filled: lit).frame(width: 12, height: 12)
        Text("\(today.pawns)").font(.system(size: 11, weight: .bold).monospacedDigit())
      }
      .frame(height: 13)
      .foregroundStyle(Theme.pawn)
      .pawnSpot("streak")
    }
    .accessibilityElement()
    .accessibilityLabel("Streak day \(today.day), \(today.pawns) pawn\(today.pawns == 1 ? "" : "s") a day\(lit ? ", today's paid" : "")")
  }

  /// Days before today in the week are lit, frozen ones icy; yesterday, missed but repairable, is
  /// a faint ice; today's part is dim until its game pays.
  private func color(_ i: Int) -> SwiftUI.Color {
    let at = today.weekday - 1
    if today.repairable && i == at - 1 { return Theme.ice.opacity(0.3) }
    if i < at { return today.frozen.contains(i + 1) ? Theme.ice : Theme.pawn }
    if i == at { return today.paid && !waiting ? Theme.pawn : SwiftUI.Color(hex: 0x6b5a2a) }
    return Theme.surface3
  }
}

/// A small pawn, filled or as an outline.
private struct PawnMark: View {
  var filled: Bool

  var body: some View {
    let parts = Icon.specs["pawn"]?.parts ?? []
    Canvas { context, canvas in
      let k = canvas.width / 24
      context.scaleBy(x: k, y: k)
      for part in parts {
        if filled {
          context.fill(part.shape.path, with: .foreground)
        } else {
          context.stroke(part.shape.path, with: .foreground, style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }
      }
    }
  }
}

/// One milestone: lit when earned, dimmed with a ring of progress when not. `Badge`.
struct MilestoneBadge: View {
  var milestone: Milestone

  var body: some View {
    let won = earned(milestone)
    let tint = milestone.kind == .streak ? Theme.warn : Theme.accent
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
    case .run: Text("\(Int(milestone.target))").font(.system(size: 13, weight: .heavy).monospacedDigit())
    case .rounds:
      Text(milestone.target >= 1000 ? "\(Int(milestone.target) / 1000)k" : "\(Int(milestone.target))")
        .font(.system(size: 13, weight: .heavy).monospacedDigit())
    }
  }
}

/// The quiet offer to repair yesterday, missed: in the Milestones sheet, never a popup.
private struct StreakRepair: View {
  @Environment(AppStore.self) private var store
  @State private var confirming = false

  var body: some View {
    let afford = store.state.pawns >= REPAIR_PRICE
    HStack(spacing: 12) {
      Icon(name: "flame", size: 18).foregroundStyle(Theme.ice)
      VStack(alignment: .leading, spacing: 2) {
        Text("Repair your streak").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        Text("Yesterday was missed. Repair it any time today.").font(.system(size: 13)).foregroundStyle(Theme.text2)
      }
      Spacer(minLength: 0)
      Button { confirming = true } label: { PawnAmount(count: REPAIR_PRICE) }
        .buttonStyle(PlayButtonStyle(kind: afford ? .accent : .plain, height: 40, inset: 14))
        .disabled(!afford)
        .confirmationDialog("Repair your streak?", isPresented: $confirming, titleVisibility: .visible) {
          Button("Repair for \(REPAIR_PRICE.formatted()) pawns") { store.update { $0.repairStreak() } }
          Button("Cancel", role: .cancel) {}
        }
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}
