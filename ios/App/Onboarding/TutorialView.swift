import ChessCore
import Model
import SwiftUI

/// The first screen a new profile sees: what the app is, the tutorial, or Skip.
struct WelcomeView: View {
  let onTutorial: () -> Void
  let onSkip: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        card(["e4", "c5"], .b).rotationEffect(.degrees(-11)).offset(x: -78, y: 14).opacity(0.75)
        card(["d4", "d5", "c4", "e6"], .b).rotationEffect(.degrees(11)).offset(x: 78, y: 14).opacity(0.75)
        card(["e4", "e5", "Nf3", "Nc6", "Bc4"], .w)
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 1.5))
      }
      .frame(maxWidth: .infinity).frame(height: 190).padding(.top, 40)
      Text("Flash cards you play").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        .padding(.top, 24)
      VStack(alignment: .leading, spacing: 16) {
        point("\u{265F}\u{FE0E}", "Your openings are the cards.")
        point("\u{265A}", "Each one is a real game until you blunder.")
        point("\u{265E}", "Autoplays to the position you need to drill most.")
      }
      .padding(.top, 22)
      Spacer(minLength: 0)
      BigButton(label: "Play the tutorial", action: onTutorial)
      SkipButton(label: "Skip", action: onSkip).frame(maxWidth: .infinity).padding(.top, 6).padding(.bottom, 8)
    }
    .padding(.horizontal, 20)
    .background(Theme.background.ignoresSafeArea())
  }

  private func card(_ sans: [String], _ color: ChessCore.Color) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      MiniBoard(sans: sans, orientation: color, size: 116, lastMove: true).clipShape(RoundedRectangle(cornerRadius: 6))
      Capsule().fill(Theme.surface3).frame(width: 80, height: 6)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    .shadow(color: .black.opacity(0.55), radius: 15, y: 14)
  }

  /// The pawn has an emoji form, so its glyph carries the text-style selector to take the accent like the others.
  private func point(_ glyph: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(glyph).font(.system(size: 21)).foregroundStyle(Theme.accent)
        .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
      Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
    }
  }
}

/// The playable tutorial, on rails: each move is shown by an arrow and only
/// that move is accepted. Three moves of lent prep with their ticks and
/// times, a book move, then out of book the Pawns lens shows a push to play,
/// and End round finishes. Nothing it plays is kept.
struct TutorialView: View {
  let onDone: () -> Void

  @Environment(AppStore.self) private var store
  @State private var step = 0
  @State private var played: [String] = []
  @State private var pop: Pop?
  @State private var lens: LensKind?
  @State private var replying = false
  @State private var turnStarted = Date()

  private var fen: String { walkSan(played).fens.last ?? START_FEN }
  private var finished: Bool { step >= TUTORIAL_STEPS.count }
  private var current: TutorialStep? { finished ? nil : TUTORIAL_STEPS[step] }
  private var outOfBook: Bool { current?.phase == .out || (finished && TUTORIAL_STEPS.last?.phase == .out) }

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        VStack(spacing: 6) {
          Text("Italian Game").font(.headline).foregroundStyle(Theme.text)
          PrepSegmentsView(span: span, height: 4).frame(maxWidth: 150)
        }
        HStack {
          Spacer()
          SkipButton(label: "Skip", action: onDone)
        }
      }
      .padding(.horizontal).padding(.vertical, 10)
      BoardView(
        fen: fen, orientation: .w, interactive: !replying && current != nil, lastMove: lastMoveOf(played),
        arrows: arrows, pop: pop, marks: marks, allowed: current.map { [$0.san] }, onMove: play
      )
      .overlay(alignment: .top) {
        if outOfBook {
          Text("Out of book").font(.system(size: 19, weight: .heavy)).foregroundStyle(Theme.accent)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Capsule().fill(Theme.surface)).shadow(color: .black.opacity(0.5), radius: 15, y: 10)
            .padding(.top, 10).allowsHitTesting(false)
        }
      }
      .padding(.horizontal).padding(.top, 6)
      if outOfBook {
        LensBar(held: $lens).padding(.horizontal)
      }
      VStack(spacing: 10) {
        if finished {
          BigButton(label: "End round", action: onDone)
        } else if let current {
          Text(instruction(current)).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
          Text(current.phase == .out
            ? "Lenses show you what's important and give you hints for what to do next."
            : "Chess Playbook tracks how well you know your saved openings.")
            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .padding(.horizontal, 20).padding(.top, 18)
      Spacer(minLength: 0)
    }
    .background(Theme.background.ignoresSafeArea())
  }

  private func instruction(_ step: TutorialStep) -> String {
    step.phase == .out ? "Hold Pawns, then play \(step.san)." : "Play \(step.san)."
  }

  /// The prep's segments, then the book's, lit as far as the game has got.
  private var span: PrepSpan {
    let mine = played.enumerated().filter { $0.offset % 2 == 0 }.count
    let prep = TUTORIAL_PREP
    let book = TUTORIAL_STEPS.filter { $0.phase == .book }.count
    return PrepSpan(played: min(mine, prep) * 2, total: prep * 2, book: max(0, min(mine - prep, book)) * 2)
  }

  /// The move to play, as an arrow; out of book only once Pawns is held.
  private var arrows: [BoardArrow] {
    guard let current, !replying, let move = applySan(fen, current.san) else { return [] }
    if current.phase == .out && lens != .pawns { return [] }
    return [BoardArrow(from: move.from, to: move.to, color: Theme.accent)]
  }

  private var marks: LensMarks? {
    guard let lens, outOfBook else { return nil }
    return heldLens(lens, fen, .w, played.count >= 2 ? walkSan(Array(played.dropLast())).fens.last : nil)
  }

  private func play(_ move: LegalMove) {
    guard let current, move.san == current.san, !replying else { return }
    let seconds = Date().timeIntervalSince(turnStarted)
    played.append(move.san)
    Haptics.buzz(10, on: store.state.settings.hapticFeedback)
    if current.phase != .out {
      pop = tutorialPop(square: move.to, seconds: seconds, book: current.phase == .book)
    }
    lens = nil
    step += 1
    guard let reply = current.reply else { return }
    replying = true
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(0.9))
      pop = nil
      played.append(reply)
      replying = false
      turnStarted = Date()
    }
  }
}
