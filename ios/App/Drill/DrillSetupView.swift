import ChessCore
import Model
import SwiftUI

/// What a drill session will consist of, decided before it starts: `Setup.tsx`.
struct DrillSetupView: View {
  @Environment(AppStore.self) private var store
  let tree: OpeningTree
  let onStart: (DrillPrefs) -> Void
  let onExit: () -> Void

  var body: some View {
    let state = store.state
    let prefs = state.settings.drill
    let selection = state.settings.selection
    let regions = regionsBySide(tree, selection, state.settings.favoriteOpenings)
    let inScope = repertoiresIn(state.repertoireList, selection.color)
    let items = acrossRegions(regions, inScope, { rep, node in itemsInRegion(tree, node, allItems([rep])) }, \.cardId)
    let lineList = acrossRegions(regions, inScope, { rep, node in drillableLines(rep, tree, node) }, { "\($0.repertoireId):\($0.tipId)" })
    let due = dueLines(lineList, state.lineCards).count
    let lineMode = prefs.form == .lines
    let empty = lineMode ? lineList.isEmpty : items.isEmpty
    let place = isAnyFavorite(selection) ? "your favorites" : regions.first.map { $0.node.depth == 0 ? "your Playbook" : $0.node.name } ?? "your Playbook"
    let count = lineMode ? (lineList.count == 1 ? "1 line" : "\(lineList.count) lines") : (items.count == 1 ? "1 position" : "\(items.count) positions")

    VStack(spacing: 0) {
      PlayAppBar(title: "Drill", onClose: onExit) { Color.clear.frame(height: 1) }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          SelectionBar().padding(.bottom, 12)
          Button { onStart(prefs) } label: { Text(empty ? "Nothing prepared here" : "Start").frame(maxWidth: .infinity) }
            .buttonStyle(PlayButtonStyle(kind: .primary, height: 56, radius: 16, font: 17)).disabled(empty)
          Text("\(count) in \(place)\(lineMode && due > 0 ? " \u{00b7} \(due) due" : "")")
            .font(.system(size: 12)).foregroundStyle(Theme.text3).frame(maxWidth: .infinity).padding(.top, 6)
          PlaySection(title: "Drill")
          SegmentedControl(value: bind(\.form), options: [(DrillForm.lines, "Lines"), (.positions, "Positions")])
          PlaySection(title: "Draw from")
          SegmentedControl(value: bind(\.draw), options: [(DrillDraw.due, "Scheduled"), (.new, "New only"), (.cram, "Everything")])
          PlaySection(title: "Clock")
          SegmentedControl(value: bind(\.clock), options: CLOCK_MODES.map { ($0, clockLabel($0)) })
          PlaySection(title: "How it asks")
          options(prefs, lineMode)
          DrillSchedule(cards: items.compactMap { state.cards[$0.cardId] }, positions: items.count)
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
      }
    }
  }

  @ViewBuilder private func options(_ prefs: DrillPrefs, _ lineMode: Bool) -> some View {
    ListCard {
      if !lineMode {
        StepperRow(label: "New per session", value: prefs.newPerSession, range: 0...40, step: 2) { n in set { $0.newPerSession = n } }
        ToggleRow(label: "Follow the line", hint: "Keep going after a correct move instead of stopping at one answer", on: prefs.followLine) {
          set { $0.followLine.toggle() }
        }
      }
      ToggleRow(
        label: "Weakest first",
        hint: lineMode
          ? "Draw the lines you grade lowest rather than the ones strong players choose most"
          : "Ask what you keep getting wrong before what is merely due",
        on: prefs.weakFirst) { set { $0.weakFirst.toggle() } }
      if lineMode {
        ToggleRow(label: "Batch similar lines", hint: "Drill a few lines that share most of their moves, then move on to another group",
                  on: prefs.batchSimilar) { set { $0.batchSimilar.toggle() } }
      }
      ToggleRow(label: "Explain mistakes", hint: "Offer the engine's refutation after a wrong move", on: prefs.explain) {
        set { $0.explain.toggle() }
      }
    }
  }

  private func bind<V>(_ key: WritableKeyPath<DrillPrefs, V>) -> Binding<V> {
    Binding(get: { store.state.settings.drill[keyPath: key] }, set: { value in set { $0[keyPath: key] = value } })
  }

  /// `setModePrefs('drill', patch)`.
  private func set(_ change: (inout DrillPrefs) -> Void) {
    store.update { change(&$0.settings.drill) }
  }
}

/// A number with − and + either side: `Stepper` in `ui.tsx`.
struct StepperRow: View {
  var label: String
  var value: Int
  var range: ClosedRange<Int>
  var step: Int
  var onChange: (Int) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Text(label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
      Spacer()
      HStack(spacing: 2) {
        button("\u{2212}") { onChange(max(range.lowerBound, value - step)) }
        Text("\(value)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text).frame(minWidth: 30)
        button("+") { onChange(min(range.upperBound, value + step)) }
      }
      .padding(2).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
    }
    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54)
  }

  private func button(_ text: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(text).font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.text).frame(width: 34, height: 30).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}
