import Foundation
import ChessCore
import Engine
import Model
import SwiftUI

/// One sitting of Growth: the reply you have no answer to, the answers on
/// offer with who recommends them, and the reveal once the batch is done.
/// Save Line writes the sitting and goes Home; X goes Home without it.
struct GrowthView: View {
  /// Where the reveal leads.
  struct Exits {
    var analyze: (() -> Void)?
    var playFrom: ((String) -> Void)?
    /// Home.
    var close: () -> Void
  }

  @Bindable var model: GrowthModel
  let exits: Exits
  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var discarding = false

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
      PlayAppBar(title: "Growth", subtitle: subtitle, onClose: close) { EmptyView() }
      if let rim {
        StatusLine(white: model.run.color == .w, text: rim, busy: status?.busy ?? false, tone: Theme.accent).padding(.bottom, 4)
      } else if let status {
        StatusLine(white: model.run.color == .w, text: status.text, busy: status.busy).padding(.bottom, 4)
      }
      ScrollView {
        VStack(spacing: 0) {
          PlayEvalBar(line: model.evals.position.map { EngineLine(multipv: 1, depth: 0, cp: $0, mate: nil, pv: []) })
            .padding(.bottom, 10)
          CapturedRow(fen: model.introFen ?? model.fen, orientation: model.run.color).padding(.bottom, 6)
          board
          if model.phase == .done { nextRow.padding(.top, 12) }
          below.padding(.vertical, 8)
            .opacity(model.flash ? 0 : 1)
            .overlay(alignment: .top) {
              if model.flash { CalloutStrip(text: "End of the book", good: true).padding(.top, 8).transition(.opacity) }
            }
            .animation(.easeOut(duration: 0.25), value: model.flash)
            // The callout runs past the row it stands in: over what follows, not under it.
            .zIndex(1)
          GrowthPhaseView(model: model, exits: exits)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 20)
      }
      .defaultScrollAnchor(Self.debugAnchor)
    }
    .confirmationDialog(discardTitle, isPresented: $discarding, titleVisibility: .visible) {
      Button("Discard", role: .destructive, action: exits.close)
      Button("Keep playing", role: .cancel) {}
    }
  }

  /// X: Home without saving, asked first when there are moves to lose.
  private func close() {
    if model.unsaved > 0 { discarding = true } else { exits.close() }
  }

  private var discardTitle: String { model.unsaved == 1 ? "Discard 1 move?" : "Discard \(model.unsaved) moves?" }

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
      highlights: answerHighlights, arrows: hole ? holeArrows(model) : [], allowed: model.phase == .hole ? model.listed.map(\.san) : nil,
      onMove: model.play
    )
    .opacity(model.phase == .lost ? 0.55 : 1)
    .overlay { if rim != nil { BoardRim(color: Theme.accent) } }
    .overlay {
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

  /// The board's rim and what the status line calls it, as in Play: the way in playing out, then adding moves at the hole.
  private var rim: String? {
    if model.intro == .replay { return "Replay" }
    if model.phase == .hole && !model.held { return "Adding new moves" }
    return nil
  }

  /// Whose move, as in Play: none once the sitting is over.
  private var status: (text: String, busy: Bool)? {
    guard !model.held else { return nil }
    switch model.phase {
    case .walking:
      let mine = isUsersTurn(model.run)
      return (mine && !model.thinking ? "Your move" : "Reply", model.thinking)
    case .answered: return ("Reply", true)
    case .hole: return model.waitingForEngine ? ("Reply", true) : ("Your move", false)
    default: return nil
    }
  }

  /// The green highlight on the move just added, in place of the last-move tint.
  private var answerHighlights: [String: SwiftUI.Color] {
    guard let answer = model.session.answer else { return [:] }
    return [answer.from: Theme.good, answer.to: Theme.good]
  }

  @ViewBuilder private var nextRow: some View {
    HStack(spacing: 8) {
      if let analyze = exits.analyze {
        Button(action: analyze) {
          Label { Text("Analyze") } icon: { Icon(name: "search", size: 18) }.frame(maxWidth: .infinity)
        }
        .buttonStyle(PlayButtonStyle(height: 52))
      }
      Button {
        model.save()
        exits.close()
      } label: {
        Text("Save Line").frame(maxWidth: .infinity)
      }
      .buttonStyle(PlayButtonStyle(kind: .primary, height: 52))
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
