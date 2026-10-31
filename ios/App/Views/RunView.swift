import ChessCore
import Model
import SwiftUI

/// A run in play: the board, what floats over it, and the prompt under it.
struct RunView: View {
  @Bindable var model: RunModel
  let onExit: () -> Void

  var body: some View {
    ZStack {
      board
      if model.intro == .announce {
        Theme.background.ignoresSafeArea()
        IntroPlate(
          name: openingName(model.tree, model.introOpening), sans: nodeById(model.tree, model.introOpening).sans,
          color: model.run.color, span: model.span)
        .padding()
      }
    }
    .contentShape(Rectangle())
    .onTapGesture { if model.intro == .announce { model.toBoard() } }
  }

  private var board: some View {
    VStack(spacing: 0) {
      header
      BoardView(
        fen: model.shownFen, orientation: model.run.color,
        interactive: model.live && !model.held && model.myTurn && !model.thinking && model.pending == nil,
        lastMove: model.held ? lastMoveOf(Array(model.introPath.prefix(model.introPly))) : lastMove, highlights: highlights, arrows: arrows, glow: model.glow, pop: model.pop,
        onMove: model.play
      )
      .overlay(alignment: .top) { flash }
      .onTapGesture { model.intro == .replay ? model.skipIntro() : model.clearMiss() }
      if model.intro == .replay {
        Text(sansToMoveText(Array(model.introPath.prefix(model.introPly)))).font(.footnote).foregroundStyle(Theme.text2).padding(.top, 8)
      } else if model.run.opened > 0 {
        Text("From \(sansToMoveText(Array(model.run.played.prefix(model.run.opened))))")
          .font(.footnote).foregroundStyle(Theme.text2).padding(.top, 8)
      }
      Spacer()
      prompt.padding()
    }
  }

  private var header: some View {
    HStack {
      Button(action: onExit) { Image(systemName: "xmark") }.foregroundStyle(Theme.text2)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 8) {
          SideSquare(color: model.run.color, size: 12)
          Text(openingName(model.tree, model.openingId)).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
        }
        PrepSegmentsView(span: model.span, height: 4).frame(maxWidth: 150)
      }
      Spacer()
      let n = Int(JSRound(model.ratingGained))
      Text(n < 0 ? "\u{2212}\(-n)" : "+\(n)")
        .font(.subheadline.monospacedDigit().bold())
        .foregroundStyle(n > 0 ? Theme.good : n < 0 ? Theme.bad : Theme.text2)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Theme.surface2))
    }
    .padding(.horizontal).padding(.vertical, 10)
  }

  @ViewBuilder private var prompt: some View {
    if let blunder = model.blunder {
      VStack(spacing: 12) {
        Label(endingTitle(model.session.ending!, model.run.played.count), systemImage: "xmark")
          .foregroundStyle(Theme.bad).font(.headline)
        Button("Continue") { model.continueToEnd() }.buttonStyle(.borderedProminent).tint(Theme.accent)
        let _ = blunder
      }
    } else {
      VStack(spacing: 6) {
        HStack(spacing: 8) {
          if model.thinking || model.pending != nil {
            ProgressView().controlSize(.small)
          } else {
            Circle().fill(model.run.color == .w ? SwiftUI.Color.white : SwiftUI.Color.black).frame(width: 12, height: 12)
              .overlay(Circle().stroke(Theme.text3))
          }
          Text(model.pending != nil ? "Judging" : model.myTurn && !model.thinking ? "Your move" : "Reply")
            .font(.headline).foregroundStyle(Theme.text)
        }
        if let label = model.label {
          let status = prepStatusText(label)
          Text(status.text).font(.subheadline.bold()).foregroundStyle(status.color)
        }
        if model.momentHere {
          Text("There's something here").font(.subheadline.bold()).foregroundStyle(Theme.accent)
        }
        if model.prefs.missions, let mission = model.session.state.extras.mission {
          Text(missionText(mission)).font(.subheadline).foregroundStyle(Theme.text2)
        }
        let multiplier = comboMultiplier(model.session.state.extras.combo)
        if model.prefs.combo && multiplier > 1 {
          Text("Combo \u{00d7}\(multiplier)").font(.subheadline.bold()).foregroundStyle(Theme.good)
        }
        Button("End round") { model.endRound() }
          .font(.footnote).foregroundStyle(Theme.text2).padding(.top, 8)
        let misses = model.session.state.misses.count
        if misses > 0 {
          Text("\(misses) miss\(misses == 1 ? "" : "es") so far").font(.footnote).foregroundStyle(Theme.text2)
        }
      }
    }
  }

  @ViewBuilder private var flash: some View {
    if model.intro == .replay {
      HStack(spacing: 6) {
        Text("Autoplay").font(.caption.bold()).padding(.horizontal, 6).padding(.vertical, 2)
          .background(Capsule().fill(Theme.accent.opacity(0.25))).foregroundStyle(Theme.accent)
        Text(openingName(model.tree, model.introOpening)).font(.subheadline.bold()).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 12).padding(.vertical, 6)
      .background(Capsule().fill(Theme.background.opacity(0.9))).padding(.top, 10)
    } else if let miss = model.miss {
      pill("Off your prep \u{00b7} \(miss.expected) was yours", Theme.accent)
    } else if let note = model.note {
      pill(note.text, note.tone == "good" ? Theme.good : note.tone == "bad" ? Theme.bad : Theme.accent)
    }
  }

  private func pill(_ text: String, _ color: SwiftUI.Color) -> some View {
    Text(text).font(.subheadline.bold()).foregroundStyle(color)
      .padding(.horizontal, 12).padding(.vertical, 6)
      .background(Capsule().fill(Theme.background.opacity(0.9)))
      .padding(.top, 10)
  }

  private var lastMove: (from: String, to: String)? {
    if model.blunder != nil { return nil }
    if let pending = model.pending { return (pending.from, pending.to) }
    return lastMoveOf(model.run.played)
  }

  private var highlights: [String: SwiftUI.Color] {
    guard let b = model.blunder else { return [:] }
    return [b.move.from: Theme.bad, b.move.to: Theme.bad]
  }

  private var arrows: [BoardArrow] {
    if let b = model.blunder {
      return b.threat.map { [BoardArrow(from: $0.from, to: $0.to, color: Theme.bad)] } ?? []
    }
    if let miss = model.miss { return [BoardArrow(from: miss.from, to: miss.to, color: Theme.good)] }
    if let best = model.missedBest { return [BoardArrow(from: best.from, to: best.to, color: Theme.good)] }
    return []
  }
}

/// `Math.round`.
func JSRound(_ x: Double) -> Double {
  let down = x.rounded(.down)
  return x - down >= 0.5 ? down + 1 : down
}
