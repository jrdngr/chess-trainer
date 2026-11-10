import ChessCore
import Model
import SwiftUI

/// The lens bar under a board: tap a lens to see it over the position, tap it
/// again to clear the board. A tap elsewhere on the screen clears it too (`clearsLens`).
/// Plan toggles the same way.
struct LensBar: View {
  @Binding var held: LensKind?
  /// Eval only where the screen has the engine's word on the game.
  var lenses = LENSES.filter { $0.kind != .eval }
  var enabled = true
  /// The structure's plan, held like a lens, where the screen offers it.
  var plan: Binding<Bool>? = nil
  var planEnabled = false
  /// The plan changed since the player last opened Plan.
  var planPulse = false
  /// A lens to draw the eye to until it is held: the tutorial's.
  var spotlight: LensKind? = nil
  /// A touch on Plan has toggled it and not yet lifted.
  @State private var planTouched = false
  /// The lens a touch has toggled and not yet lifted from.
  @State private var touched: LensKind?

  var body: some View {
    HStack(spacing: 6) {
      ForEach(lenses, id: \.kind) { lens in
        let on = held == lens.kind
        button(
          lens.label, on: on, ink: spotlight == lens.kind ? Theme.accent : Theme.text2, fill: Theme.accent, onInk: Theme.accentInk,
          enabled: enabled, pulse: spotlight == lens.kind, pulseColor: Theme.accent, outlined: spotlight == lens.kind
        ) {
          guard touched != lens.kind else { return }
          touched = lens.kind
          held = on ? nil : lens.kind
        } release: { touched = nil }
      }
      if let plan {
        button(
          "Plan", on: plan.wrappedValue, ink: PlanColors.plan, fill: PlanColors.plan, onInk: PlanColors.ink, enabled: enabled && planEnabled,
          pulse: planPulse && enabled && planEnabled
        ) {
          // Plan toggles, so its card stays open to scroll and tap.
          guard !planTouched else { return }
          planTouched = true
          plan.wrappedValue.toggle()
        } release: { planTouched = false }
      }
    }
    .padding(.top, 8)
    .onChange(of: enabled) {
      guard !enabled else { return }
      held = nil
      if let plan { plan.wrappedValue = false }
    }
    .onChange(of: planEnabled) { if !planEnabled, let plan { plan.wrappedValue = false } }
  }

  private func button(
    _ label: String, on: Bool, ink: SwiftUI.Color, fill: SwiftUI.Color, onInk: SwiftUI.Color, enabled: Bool, pulse: Bool,
    pulseColor: SwiftUI.Color = PlanColors.plan, outlined: Bool = false, press: @escaping () -> Void, release: @escaping () -> Void
  ) -> some View {
    Text(label)
      .font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
      .foregroundStyle(on ? onInk : ink)
      .frame(maxWidth: .infinity).padding(.vertical, 8)
      .background {
        RoundedRectangle(cornerRadius: 10).fill(on ? fill : Theme.surface2)
        if pulse && !on { PlanPulse(color: pulseColor) }
        if outlined && !on { RoundedRectangle(cornerRadius: 10).strokeBorder(pulseColor, lineWidth: 1.5) }
      }
      .opacity(enabled ? 1 : 0.5)
      // High priority, so a tap gesture further up the screen never holds the press back.
      .highPriorityGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in if enabled { press() } }
          .onEnded { _ in release() })
      .accessibilityAddTraits(.isButton)
  }
}

extension View {
  /// A tap here puts the lens away; whatever was tapped still gets the tap.
  func clearsLens(_ lens: Binding<LensKind?>) -> some View {
    simultaneousGesture(TapGesture().onEnded { if lens.wrappedValue != nil { lens.wrappedValue = nil } })
  }
}

/// The key to the lens that is on: one row per kind of mark it draws.
struct LensLegend: View {
  var kind: LensKind
  /// The endgame lenses draw their own marks.
  var endgame = false
  /// Each king's grade, which the Kings key leads with.
  var safety: KingSafety? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
        ForEach(kingRows + ((endgame ? Self.endgameRows : Self.rows)[kind] ?? []), id: \.label) { row in
          HStack(spacing: 8) {
            row.swatch.frame(width: 18, height: 18)
            Text(row.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
          }
        }
      }
      if kind == .pieces { ControlScale() }
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .padding(.top, 12)
  }

  private var kingRows: [Row] {
    guard kind == .kings, let safety else { return [] }
    return [
      Row(swatch: Self.zone(LensColors.grade(safety.mine)), label: "You: \(KING_GRADE_TEXT[safety.mine]!)"),
      Row(swatch: Self.zone(LensColors.grade(safety.theirs)), label: "Them: \(KING_GRADE_TEXT[safety.theirs]!)"),
    ]
  }

  struct Row {
    var swatch: AnyView
    var label: String
  }

  /// Who holds the squares, as one scale from yours to theirs.
  private struct ControlScale: View {
    var body: some View {
      VStack(spacing: 4) {
        Capsule()
          .fill(LinearGradient(
            colors: [TintColor.blue, .purpleBlue, .purple, .purpleRed, .red].map { LensColors.tint($0).opacity(0.75) },
            startPoint: .leading, endPoint: .trailing))
          .frame(height: 8)
        HStack {
          Text("Your squares")
          Spacer()
          Text("Contested")
          Spacer()
          Text("Theirs")
        }
        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
      }
    }
  }

  private static func piece(_ type: PieceType, _ color: SwiftUI.Color) -> AnyView {
    AnyView(PieceView(piece: BoardPiece(square: "a1", type: type, color: .w), size: 20, tint: color))
  }
  private static func dot(_ color: SwiftUI.Color, _ size: CGFloat) -> AnyView { AnyView(Circle().fill(color).frame(width: size, height: size)) }
  private static func tint(_ color: TintColor) -> AnyView {
    AnyView(RoundedRectangle(cornerRadius: 4).fill(LensColors.tint(color).opacity(0.6)))
  }
  private static func arrow(_ color: SwiftUI.Color) -> AnyView {
    AnyView(Canvas { context, size in
      let k = size.width / 20
      var shaft = Path()
      shaft.move(to: CGPoint(x: 2 * k, y: 10 * k))
      shaft.addLine(to: CGPoint(x: 13 * k, y: 10 * k))
      context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: 3 * k, lineCap: .round))
      var head = Path()
      head.move(to: CGPoint(x: 12 * k, y: 5 * k))
      head.addLine(to: CGPoint(x: 19 * k, y: 10 * k))
      head.addLine(to: CGPoint(x: 12 * k, y: 15 * k))
      head.closeSubpath()
      context.fill(head, with: .color(color))
    })
  }
  private static func zone(_ color: SwiftUI.Color) -> AnyView {
    AnyView(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.14)).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(color, lineWidth: 2)))
  }
  private static let empty = AnyView(
    Circle().strokeBorder(LensColors.red.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 14, height: 14))
  private static let line = AnyView(Canvas { context, size in
    var path = Path()
    path.move(to: CGPoint(x: 2, y: size.height / 2))
    path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
    context.stroke(path, with: .color(LensColors.red.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
  })

  private static func guide(_ color: SwiftUI.Color) -> AnyView {
    AnyView(Canvas { context, size in
      var path = Path()
      path.move(to: CGPoint(x: 2, y: size.height / 2))
      path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
      context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.5, dash: [4, 3]))
    })
  }
  private static func letter(_ text: String) -> AnyView {
    AnyView(Text(text).font(.system(size: 10, weight: .heavy)).foregroundStyle(.black.opacity(0.85))
      .frame(width: 16, height: 16).background(Circle().fill(LensColors.green)))
  }
  private static let box = AnyView(
    Rectangle().fill(LensColors.green.opacity(0.12))
      .overlay(Rectangle().strokeBorder(LensColors.green, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))))

  private static let activity: [Row] = [
    Row(swatch: piece(.n, LensColors.green), label: "Active"),
    Row(swatch: piece(.n, LensColors.amber), label: "Passive"),
    Row(swatch: piece(.n, LensColors.red), label: "Idle"),
    Row(swatch: AnyView(WorstBadge(size: 16)), label: "Worst piece"),
  ]

  private static let endgameRows: [LensKind: [Row]] = [
    .pawns: [
      Row(swatch: piece(.p, LensColors.green), label: "Passed pawn"),
      Row(swatch: piece(.p, LensColors.red), label: "Weak pawn"),
      Row(swatch: box, label: "Pawn\u{2019}s square"),
      Row(swatch: letter("O"), label: "Outside passer"),
      Row(swatch: letter("P"), label: "Protected passer"),
      Row(swatch: letter("C"), label: "Connected passers"),
      Row(swatch: arrow(LensColors.blue), label: "Your best break"),
      Row(swatch: arrow(LensColors.red), label: "Their best break"),
    ],
    .pieces: activity + [Row(swatch: dot(LensColors.amber.opacity(0.9), 10), label: "Pawn on its bishop\u{2019}s color")],
    .kings: [
      Row(swatch: tint(.blue), label: "Your key square"),
      Row(swatch: tint(.red), label: "Their key square"),
      Row(swatch: guide(SwiftUI.Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)), label: "Opposition"),
      Row(swatch: guide(LensColors.amber), label: "Cut-off line"),
      Row(swatch: line, label: "Open line to the king"),
      Row(swatch: empty, label: "Missing shield pawn"),
    ],
  ]

  private static let rows: [LensKind: [Row]] = [
    .pawns: [
      Row(swatch: piece(.p, LensColors.red), label: "Weak pawn"),
      Row(swatch: piece(.p, LensColors.green), label: "Passed pawn"),
      Row(swatch: dot(LensColors.amber.opacity(0.9), 10), label: "Hole"),
      Row(swatch: arrow(LensColors.blue), label: "Your best break"),
      Row(swatch: arrow(LensColors.red), label: "Their best break"),
    ],
    .pieces: activity,
    .kings: [
      Row(swatch: line, label: "Open line to the king"),
      Row(swatch: empty, label: "Missing shield pawn"),
    ],
  ]
}

/// The Plan button's fill breathing toward its held cyan and back, every four seconds.
private struct PlanPulse: View {
  static let period = 4.0
  static let depth = 0.22
  var color = PlanColors.plan

  var body: some View {
    TimelineView(.animation) { context in
      let t = context.date.timeIntervalSinceReferenceDate
      let k = (1 - cos(2 * .pi * t / Self.period)) / 2
      RoundedRectangle(cornerRadius: 10).fill(color.opacity(Self.depth * k))
    }
    .allowsHitTesting(false)
  }
}
