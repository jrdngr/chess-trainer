import Book
import ChessCore
import Model
import SwiftUI

/// Where onboarding hands over to.
enum OnboardingNext: Equatable { case home, autopilot }

/// Adding openings, from the Playbook tab's +: four ways in. A starter set,
/// picked by style; the openings you already play, picked one at a time;
/// lines played in on the board; or the openings found in your Lichess or
/// Chess.com games, which go in as soon as they are added and start a run.
/// Otherwise nothing goes in until the ready screen is left, so "Add more
/// openings" can still list and drop them. Lines saved on the board are held
/// the same way, Back included. Close leaves without adding what is held.
struct OnboardingView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
  let onClose: () -> Void
  let onDone: (OnboardingNext) -> Void

  @Environment(AppStore.self) private var store
  @State private var step: OnboardingStep = Self.debugStep ?? .path
  /// Everything picked so far, held until the ready screen is left. Backing out keeps it.
  @State private var pending: [PendingOpening] = []
  /// What the ready screen last listed: picking counts what is new since.
  @State private var listed: [String] = []

  var body: some View {
    Group {
      switch step {
      case .path: PathsView(onClose: onClose, onStep: { step = $0 })
      case .sets: SetListView(tree: tree, onBack: { step = .path }, onOpen: { step = .set($0) })
      case .set(let id):
        let set = STARTER_SETS.first { $0.id == id } ?? STARTER_SETS[0]
        SetDetailView(tree: tree, set: set, onBack: { step = .sets }, onUse: { ready(pendingFromSet(tree, set)) })
      case .pick:
        PickOpeningsView(
          tree: tree, index: index, picked: $pending, listed: listed,
          onBack: { if !listed.isEmpty && !pending.isEmpty { ready([]) } else { step = .path } },
          onAdd: { ready([]) })
      case .board:
        BoardBuildView(onBack: { saved in
          hold(boardHeld(saved))
          step = .path
        }, onSaved: { saved in ready(boardHeld(saved)) }, hold: true)
      case .ready:
        ReadyView(tree: tree, rows: pending, onMore: { step = .pick }, onDone: confirm)
      case .importGames:
        ImportView(onBack: { step = .path }, onAdded: { confirm(.autopilot) })
      case .browse:
        BrowsePicker(onClose: { step = .path })
      }
    }
    .background(Theme.background.ignoresSafeArea())
    .onAppear(perform: debugHold)
  }

  private func ready(_ rows: [PendingOpening]) {
    hold(rows)
    listed = pending.map(\.key)
    step = .ready
  }

  private func hold(_ rows: [PendingOpening]) {
    pending = pending.filter { row in !rows.contains { $0.key == row.key } } + rows
  }

  /// The board's rows for every line held from the board, the ones held before and the ones just saved.
  private func boardHeld(_ saved: [BoardLine]) -> [PendingOpening] {
    var lines = boardLines(pending)
    for line in saved.map(\.onboarding) where !lines.contains(where: { $0.color == line.color && $0.sans == line.sans }) {
      lines.append(line)
    }
    return boardRows(store.state, tree, index, lines)
  }

  private func confirm(_ next: OnboardingNext) {
    store.update { $0.onboarded(tree, seedsOf(pending), boardLines(pending)) }
    onDone(next)
  }

  /// Debug builds open on a step with `ONB_STEP=sets|set:classical|pick|board|ready|browse`, for screenshots.
  /// `ready` and `pick` start with the Classical set held.
  private static var debugStep: OnboardingStep? {
    #if DEBUG
      guard let raw = ProcessInfo.processInfo.environment["ONB_STEP"] else { return nil }
      if raw.hasPrefix("set:") { return .set(String(raw.dropFirst(4))) }
      return ["sets": .sets, "pick": .pick, "board": .board, "ready": .ready, "browse": .browse][raw]
    #else
      return nil
    #endif
  }

  /// Debug builds start `ONB_STEP=ready` and `pick` with the Classical set held.
  private func debugHold() {
    #if DEBUG
      guard let raw = ProcessInfo.processInfo.environment["ONB_STEP"], raw == "ready" || raw == "pick", pending.isEmpty else { return }
      pending = pendingFromSet(tree, STARTER_SETS[0])
      listed = pending.map(\.key)
    #endif
  }
}

enum OnboardingStep: Equatable {
  case path, sets, set(String), pick, board, importGames, ready
  /// Debug only: the opening browser on its own.
  case browse
}

/// Choosing your openings: four ways to add to the Playbook.
struct PathsView: View {
  let onClose: () -> Void
  let onStep: (OnboardingStep) -> Void

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: "Choose your openings", large: true) {
        RoundIconButton(icon: "close", action: onClose)
      }
      ScrollView {
        VStack(spacing: 12) {
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            path("Suggest a set", "star") { onStep(.sets) }
            path("Pick openings", "tree") { onStep(.pick) }
            path("Play on the board", "play") { onStep(.board) }
            path("Import my games", "download") { onStep(.importGames) }
          }
        }
        .padding(.horizontal, 16).padding(.top, 16)
      }
    }
  }

  private func path(_ name: String, _ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 14) {
        Icon(name: icon, size: 22).foregroundStyle(Theme.accent)
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.16)))
        Text(name).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
          .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .padding(16).frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
      .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
