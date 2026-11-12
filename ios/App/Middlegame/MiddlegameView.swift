import Book
import ChessCore
import Engine
import Foundation
import Game
import Model
import SwiftUI

/// Middlegame mode, opened from Home or from a line on the opening sheet: one of
/// your lines played out to a middlegame, then a run from there. While the
/// handoff is built, the mode is announced over the screen. A run plays on
/// `RunModel` and `RunView`, and ends on `EndView`, as Run's do.
struct MiddlegameView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  /// The exact line to play out; nil to draw one from your setup each run.
  var exact: MiddlegameLine?
  let onExit: () -> Void
  /// Leave for the Analysis tab on this line, seen from this side.
  let onAnalyze: (_ sans: [String], _ side: ChessCore.Color) -> Void
  /// From Home, start a run at once, without the setup screen.
  var straight = false

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var session: MiddlegameSession?
  /// Whether the first run has been tried: until then a straight start shows nothing.
  @State private var opened = false
  @State private var settings = false

  var body: some View {
    Group {
      if let session { content(session) } else { Theme.background.ignoresSafeArea() }
    }
    .sheet(isPresented: $settings) {
      MiddlegameSetupView(tree: tree, onStart: { prefs in
        settings = false
        session?.start(prefs, line: exact)
      }, onExit: { settings = false }, startLabel: "Restart")
      .presentationBackground(Theme.background)
    }
    .task {
      let session = self.session ?? made()
      if let exact, session.model == nil, session.building == nil {
        session.start(store.state.settings.middlegame, line: exact)
      } else if straight && !opened && session.model == nil && session.building == nil {
        session.start(store.state.settings.middlegame)
      }
      opened = true
    }
  }

  private func made() -> MiddlegameSession {
    let made = MiddlegameSession(store: store, tree: tree, index: index, exact: exact)
    made.onFail = { message, close in
      toasts.show(message)
      if close { onExit() }
    }
    session = made
    return made
  }

  @ViewBuilder private func content(_ session: MiddlegameSession) -> some View {
    if let building = session.building {
      // The announcement fades out on its own; a long build waits under it, and can be left.
      ZStack {
        VStack(spacing: 18) {
          ProgressView().tint(Theme.text2)
          Button("Cancel", action: exit).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background)
        PlayIntroCover(trail: building, mode: "Middlegame").allowsHitTesting(false)
      }
    } else if let model = session.model {
      if model.phase == .over, let finish = model.finish {
        EndView(
          model: model, finish: finish, onNext: { session.start(store.state.settings.middlegame) },
          onAnalyze: { onAnalyze(model.run.played, model.run.color) }, onExit: exit,
          onChangeOptions: exact == nil ? { session.setup() } : nil,
          onSameLine: session.last == nil ? nil : { if let last = session.last { session.start(store.state.settings.middlegame, line: last) } })
      } else {
        RunView(model: model, onExit: exit, onAnalyze: { onAnalyze(model.run.played, model.run.color) })
          .environment(\.openModeSettings) { settings = true }
      }
    } else if exact != nil || (straight && !opened) {
      Theme.background.ignoresSafeArea()
    } else {
      MiddlegameSetupView(tree: tree, onStart: { session.start($0) }, onExit: onExit)
    }
  }

  private func exit() {
    session?.exit()
    onExit()
  }
}
