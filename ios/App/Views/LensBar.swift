import Model
import SwiftUI

/// The lens bar under a board: hold a lens to see it over the position;
/// let go and the board is clean again.
struct LensBar: View {
  @Binding var held: LensKind?
  /// Eval only where the screen has the engine's word on the game.
  var lenses = LENSES.filter { $0.kind != .eval }
  var enabled = true
  /// The structure's plan, held like a lens, where the screen offers it.
  var plan: Binding<Bool>? = nil
  var planEnabled = false

  var body: some View {
    HStack(spacing: 6) {
      ForEach(lenses, id: \.kind) { lens in
        let on = held == lens.kind
        button(lens.label, on: on, ink: Theme.text2, fill: Theme.accent, onInk: Theme.accentInk, enabled: enabled) {
          if held != lens.kind { held = lens.kind }
        } release: { held = nil }
      }
      if let plan {
        button("Plan", on: plan.wrappedValue, ink: PlanColors.plan, fill: PlanColors.plan, onInk: PlanColors.ink, enabled: enabled && planEnabled) {
          if !plan.wrappedValue { plan.wrappedValue = true }
        } release: { plan.wrappedValue = false }
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
    _ label: String, on: Bool, ink: SwiftUI.Color, fill: SwiftUI.Color, onInk: SwiftUI.Color, enabled: Bool,
    press: @escaping () -> Void, release: @escaping () -> Void
  ) -> some View {
    Text(label)
      .font(.system(size: 12.5, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
      .foregroundStyle(on ? onInk : ink)
      .frame(maxWidth: .infinity).padding(.vertical, 8)
      .background(RoundedRectangle(cornerRadius: 10).fill(on ? fill : Theme.surface2))
      .opacity(enabled ? 1 : 0.5)
      // High priority, so a tap gesture further up the screen never holds the press back.
      .highPriorityGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { _ in if enabled { press() } }
          .onEnded { _ in release() })
      .accessibilityAddTraits(.isButton)
  }
}

/// The key to a held lens: one row per kind of mark it draws.
struct LensLegend: View {
  var kind: LensKind

  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
      ForEach(Self.rows[kind] ?? [], id: \.label) { row in
        HStack(spacing: 8) {
          row.swatch.frame(width: 18, height: 18)
          Text(row.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2)
        }
      }
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
    .padding(.top, 12)
  }

  struct Row {
    var swatch: AnyView
    var label: String
  }

  private static func tint(_ color: TintColor) -> AnyView {
    AnyView(RoundedRectangle(cornerRadius: 4).fill(LensColors.tint(color).opacity(0.6)))
  }
  private static func dot(_ color: SwiftUI.Color, _ size: CGFloat) -> AnyView { AnyView(Circle().fill(color).frame(width: size, height: size)) }
  private static func ring(_ color: SwiftUI.Color) -> AnyView { AnyView(Circle().strokeBorder(color, lineWidth: 2.5)) }
  private static func star(_ color: SwiftUI.Color) -> AnyView { AnyView(Text("\u{2605}").font(.system(size: 15)).foregroundStyle(color)) }
  private static func shield(_ color: SwiftUI.Color) -> AnyView { AnyView(ShieldShape().fill(color)) }
  private static func arrow(_ color: SwiftUI.Color, faint: Bool = false) -> AnyView {
    AnyView(Canvas { context, size in
      let k = size.width / 20
      var shaft = Path()
      shaft.move(to: CGPoint(x: 2 * k, y: 10 * k))
      shaft.addLine(to: CGPoint(x: 13 * k, y: 10 * k))
      context.stroke(shaft, with: .color(color), style: StrokeStyle(lineWidth: (faint ? 2 : 3) * k, lineCap: .round))
      var head = Path()
      head.move(to: CGPoint(x: 12 * k, y: 5 * k))
      head.addLine(to: CGPoint(x: 19 * k, y: 10 * k))
      head.addLine(to: CGPoint(x: 12 * k, y: 15 * k))
      head.closeSubpath()
      context.fill(head, with: .color(color))
    })
  }
  private static let zone = AnyView(
    RoundedRectangle(cornerRadius: 3).fill(SwiftUI.Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255).opacity(0.3))
      .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.9), lineWidth: 1.5).padding(1.5))
      .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.black.opacity(0.6), lineWidth: 1.5)))
  private static let empty = AnyView(
    Circle().strokeBorder(LensColors.red.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 14, height: 14))
  private static let line = AnyView(Canvas { context, size in
    var path = Path()
    path.move(to: CGPoint(x: 2, y: size.height / 2))
    path.addLine(to: CGPoint(x: size.width - 2, y: size.height / 2))
    context.stroke(path, with: .color(LensColors.red.opacity(0.8)), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
  })

  private static let rows: [LensKind: [Row]] = [
    .pawns: [
      Row(swatch: dot(LensColors.red, 10), label: "Weak pawn"),
      Row(swatch: dot(LensColors.green, 10), label: "Passed pawn"),
      Row(swatch: dot(LensColors.amber.opacity(0.9), 10), label: "Hole"),
      Row(swatch: arrow(LensColors.blue), label: "Your best break"),
      Row(swatch: arrow(LensColors.red), label: "Their best break"),
    ],
    .pieces: [
      Row(swatch: ring(LensColors.green), label: "Active"),
      Row(swatch: ring(LensColors.amber), label: "Passive"),
      Row(swatch: ring(LensColors.red), label: "Doing nothing"),
      Row(swatch: AnyView(WorstBadge(size: 16)), label: "Worst piece"),
      Row(swatch: tint(.blue), label: "Your square"),
      Row(swatch: tint(.red), label: "Their square"),
      Row(swatch: tint(.purple), label: "Contested"),
      Row(swatch: star(LensColors.lightBlue), label: "Your outpost"),
      Row(swatch: star(LensColors.lightRed), label: "Their outpost"),
      Row(swatch: arrow(LensColors.lightBlue.opacity(0.55), faint: true), label: "Knight route"),
    ],
    .kings: [
      Row(swatch: zone, label: "King zone"),
      Row(swatch: dot(LensColors.lightRed, 8), label: "Attacker"),
      Row(swatch: dot(LensColors.lightBlue, 8), label: "Defender"),
      Row(swatch: empty, label: "Missing shield pawn"),
      Row(swatch: line, label: "Open line to the king"),
      Row(swatch: shield(LensColors.green), label: "Safe"),
      Row(swatch: shield(LensColors.amber), label: "Exposed"),
      Row(swatch: shield(LensColors.red), label: "Under attack"),
    ],
  ]
}
