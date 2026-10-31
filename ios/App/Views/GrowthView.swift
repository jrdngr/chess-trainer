import Foundation
import ChessCore
import Engine
import Model
import SwiftUI

/// One sitting of Growth: the reply you have no answer to, the answers on
/// offer with who recommends them, and the reveal once the batch is done.
/// `Run` in `GrowthScreen.tsx`. Autopilot's batch ends in Next round;
/// Growth from Home in New run, with the rest of the reveal.
struct GrowthView: View {
  /// Where the reveal leads.
  struct Exits {
    /// Autopilot's next round, in place of New run.
    var nextRound: (() -> Void)?
    /// What the next-round button says: Autopilot's "Next round", or Survival's "Practice these lines".
    var nextLabel = "Next round"
    var again: (() -> Void)?
    var analyze: (() -> Void)?
    /// The card that points back to practising.
    var practice: ((Selection) -> Void)?
    var playFrom: ((String) -> Void)?
    /// Back to the lobby.
    var back: (() -> Void)?
    var close: () -> Void
  }

  @Bindable var model: GrowthModel
  let exits: Exits
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts

  /// Autopilot's batch, as it opens from the end of a run.
  init(model: GrowthModel, onNext: @escaping () -> Void) {
    self.init(model: model, exits: Exits(nextRound: onNext, close: onNext))
  }

  /// Survival's batch: the same, its way out named for where it goes.
  init(model: GrowthModel, nextLabel: String, onNext: @escaping () -> Void) {
    self.init(model: model, exits: Exits(nextRound: onNext, nextLabel: nextLabel, close: onNext))
  }

  init(model: GrowthModel, exits: Exits) {
    self.model = model
    self.exits = exits
  }

  var body: some View {
    ZStack {
      screen
      if model.intro == .announce {
        PlayIntroCover(trail: model.introTrail, mode: "Growth").onTapGesture { model.toBoard() }.transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: model.intro == .announce)
    .onAppear { model.onToast = { [toasts] in toasts.show($0) } }
    .onDisappear { model.leave() }
    .task(id: "\(model.run.fen)|\(model.phase)|\(model.listed.map(\.san))") {
      model.askEvals()
      model.askSoundness()
    }
  }

  private var screen: some View {
    VStack(spacing: 0) {
      PlayAppBar(title: "Growth", subtitle: subtitle, onClose: exits.close) {
        Text("\(model.live?.nodes.count ?? 0)").font(.system(size: 13).monospacedDigit()).foregroundStyle(Theme.text2)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      ScrollView {
        VStack(spacing: 0) {
          PlayEvalBar(line: model.evals.position.map { EngineLine(multipv: 1, depth: 0, cp: $0, mate: nil, pv: []) })
            .padding(.bottom, 10)
          CapturedRow(fen: model.introFen ?? model.fen, orientation: model.run.color).padding(.bottom, 6)
          board
          if model.phase == .done { nextRow.padding(.top, 12) }
          below.padding(.vertical, 8)
          GrowthPhaseView(model: model, exits: exits)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
      .defaultScrollAnchor(Self.debugAnchor)
    }
  }

  /// Debug builds hold the page to its bottom with `GROWTH_SCROLL=1`, for screenshots.
  private static var debugAnchor: UnitPoint? {
    #if DEBUG
      ProcessInfo.processInfo.environment["GROWTH_SCROLL"] != nil ? .bottom : nil
    #else
      nil
    #endif
  }

  private var subtitle: String {
    let side: ColorChoice = model.run.color == .w ? .w : .b
    return store.catalog.map { selectionText(model.tree, $0, side, model.launch.regionId ?? model.launch.opening.id) } ?? ""
  }

  private var board: some View {
    let hole = model.phase == .hole && !model.held
    return BoardView(
      fen: model.introFen ?? model.fen, orientation: model.run.color,
      interactive: !model.held && ((model.phase == .walking && isUsersTurn(model.run)) || model.phase == .hole),
      lastMove: model.held ? model.introLastMove : model.session.answer == nil ? lastMoveOf(model.run.path) : nil,
      highlights: answerHighlights, arrows: hole ? arrows : [], allowed: model.phase == .hole ? model.listed.map(\.san) : nil,
      onMove: model.play
    )
    .opacity(model.phase == .lost ? 0.55 : 1)
    .overlay(alignment: .top) {
      if let name = model.introPill { GrowthIntroPill(name: name, autoplay: model.intro == .replay) }
    }
    .overlay {
      if model.flash { BoardFlash(text: "End of the book").onTapGesture { model.clearFlash() } }
      if model.intro == .replay { Color.clear.contentShape(Rectangle()).onTapGesture { model.skipIntro() } }
    }
    .overlay(alignment: .top) {
      if let toast = model.toast {
        Text(toast).font(.subheadline.bold()).foregroundStyle(Theme.good)
          .padding(.horizontal, 12).padding(.vertical, 6)
          .background(Capsule().fill(Theme.background.opacity(0.9))).padding(.top, 10)
      }
    }
  }

  /// The green highlight on the move just added, in place of the last-move tint.
  private var answerHighlights: [String: SwiftUI.Color] {
    guard let answer = model.session.answer else { return [:] }
    return [answer.from: Theme.good, answer.to: Theme.good]
  }

  /// The role arrows, glowing where a move matches or breaks your patterns,
  /// and a familiar move nobody recommends in gray: least important first.
  private var arrows: [BoardArrow] {
    let roles = model.roles
    let toned = model.toned
    let glow = { (san: String) in toned.first { $0.san == san && $0.tone != nil }.map { nudgeColor($0.tone) } }
    let familiar = toned.filter { move in (move.tone == .toward || move.tone == .towardFar) && !roles.contains { $0.san == move.san } }
      .map { BoardArrow(from: $0.from, to: $0.to, color: Theme.text2, glow: nudgeColor($0.tone)) }
    return familiar + roles.reversed().map { BoardArrow(from: $0.from, to: $0.to, color: roleColor($0.role) ?? Theme.accent, glow: glow($0.san)) }
  }

  @ViewBuilder private var nextRow: some View {
    HStack(spacing: 8) {
      if let analyze = exits.analyze {
        Button(action: analyze) {
          Label { Text("Analyze") } icon: { Icon(name: "search", size: 18) }.frame(maxWidth: .infinity)
        }
        .buttonStyle(PlayButtonStyle(height: 52))
      }
      if let go = exits.nextRound ?? exits.again {
        Button(action: go) {
          HStack(spacing: 8) {
            Text(exits.nextRound != nil ? exits.nextLabel : "New run")
            Icon(name: "next", size: 18)
          }
          .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlayButtonStyle(kind: .primary, height: 52))
      }
    }
  }

  @ViewBuilder private var below: some View {
    if model.intro == .replay {
      Text(sansToMoveText(Array(model.introPath.prefix(model.introPly)))).font(.system(size: 13)).foregroundStyle(Theme.text3)
        .frame(maxWidth: .infinity, minHeight: 38)
    } else if !model.run.path.isEmpty {
      MoveStrip(items: growthStrip(model.run.path, model.session.added, model.run.color), cursor: model.run.path.count, max: model.run.path.count, arrows: false, onSeek: { _ in })
    }
  }
}
