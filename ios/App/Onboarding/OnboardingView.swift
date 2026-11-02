import Book
import ChessCore
import Model
import SwiftUI

/// Where onboarding hands over to.
enum OnboardingNext: Equatable { case home, autopilot }

/// The first screens a new profile sees: building the first Playbook.
///
/// Three ways in: a starter set, picked by style; the openings you already
/// play, picked one at a time; or lines played in on the board. Nothing goes
/// in until the ready screen is left, so "Add more openings" can still list
/// and drop them. Skipping is a real answer: nothing goes in, and it is never
/// asked again.
struct OnboardingView: View {
  let tree: OpeningTree
  let index: ReferenceIndex
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
      case .path: PathsView(onStep: { step = $0 }, onSkip: skip)
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
        BoardBuildView(onBack: { step = .path }, onDone: { saved in
          if saved.isEmpty { step = .path } else { ready(boardRows(store.state, tree, index, saved.map(\.onboarding))) }
        }, doneLabel: "Done", hold: true)
      case .ready:
        ReadyView(tree: tree, rows: pending, onMore: { step = .pick }, onDone: confirm)
      case .browse:
        BrowsePicker(onClose: { step = .path })
      }
    }
    .background(Theme.background.ignoresSafeArea())
    .onAppear(perform: debugHold)
  }

  private func ready(_ rows: [PendingOpening]) {
    pending = pending.filter { row in !rows.contains { $0.key == row.key } } + rows
    listed = pending.map(\.key)
    step = .ready
  }

  private func confirm(_ next: OnboardingNext) {
    store.update { $0.onboarded(tree, seedsOf(pending), boardLines(pending)) }
    onDone(next)
  }

  private func skip() {
    store.update { $0.onboarded(tree, []) }
    onDone(.home)
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
  case path, sets, set(String), pick, board, ready
  /// Debug only: the opening browser on its own.
  case browse
}

/// The welcome: three ways to build a Playbook, and Skip.
struct PathsView: View {
  let onStep: (OnboardingStep) -> Void
  let onSkip: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: "Build your Playbook", large: true)
      ScrollView {
        VStack(spacing: 12) {
          path("Suggest a set", "star", main: true) { onStep(.sets) }
          path("Pick openings", "tree") { onStep(.pick) }
          path("Play on the board", "play") { onStep(.board) }
          SkipButton(label: "Skip for now", action: onSkip).padding(.top, 8)
        }
        .padding(.horizontal, 16).padding(.top, 16)
      }
    }
  }

  private func path(_ name: String, _ icon: String, main: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Icon(name: icon, size: 22).foregroundStyle(main ? Theme.accent : Theme.text)
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 12).fill(main ? Theme.accent.opacity(0.16) : Theme.surface2))
        Text(name).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(18)
      .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
      .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(main ? Theme.accent : .white.opacity(0.07), lineWidth: 1.5))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
