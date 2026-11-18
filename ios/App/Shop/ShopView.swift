import Game
import Model
import SwiftUI

/// The Pawn Shop tab: the unlock tree, medallions joined by elbow lines, a line in green
/// once the item above it is yours. Tapping an item opens its sheet; buying pours pawns
/// from the balance into its medallion while a ring fills and its price counts down.
struct ShopView: View {
  /// The item to open, from a locked control elsewhere; cleared once open.
  @Binding var focus: String?
  /// A feature bought: Home shows it off.
  let onUnlocked: (ShopFeature) -> Void
  @Environment(AppStore.self) private var store
  @State private var selected: String?
  @State private var purchase: Purchase?
  @State private var frames: [String: CGRect] = [:]
  @State private var flights: [Flight] = []

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Pawn Shop").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        Spacer()
        PawnAmount(count: purchase?.balance ?? store.state.pawns)
          .padding(.horizontal, 14).frame(height: 42)
          .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames["balance"] = $0 }
      }
      .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
      ScrollView {
        VStack(spacing: 16) {
          UnlockEverythingRow()
          ShopTree(selected: selected, purchase: purchase, frames: $frames) { selected = $0 }
          StreakFreezeRow()
          PawnPacksRow()
        }
        .padding(.horizontal, 16).padding(.bottom, selected == nil ? 24 : 330)
      }
    }
    .background(Theme.background.ignoresSafeArea())
    .overlay { FlightLayer(flights: flights) }
    .coordinateSpace(name: Self.space)
    .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0, purchase == nil { selected = nil } })) {
      if let id = selected, let item = shopItem(id) {
        BuySheet(item: item, purchase: purchase, onSelect: { selected = $0 }, onBuy: { buy(item) }) { selected = nil }
          .presentationDetents([.height(300)])
          .presentationBackground(SwiftUI.Color(hex: 0x131317))
          .presentationBackgroundInteraction(.enabled)
          .interactiveDismissDisabled(purchase != nil)
      }
    }
    .onChange(of: focus, initial: true) {
      guard let focus else { return }
      // An empty focus opens the shop on no item.
      if shopItem(focus) != nil { selected = focus }
      self.focus = nil
    }
  }

  static let space = "shop"

  /// The purchase played out: pawns fly, the ring fills, the counts run down; then it is yours.
  private func buy(_ item: ShopItem) {
    guard purchase == nil, store.state.status(item) == .buyable else { return }
    let start = store.state.pawns
    purchase = Purchase(id: item.id, start: start, price: item.price, progress: 0)
    if let from = frames["balance"], let to = frames[item.id] {
      flights = (0..<10).map { Flight(id: $0, from: CGPoint(x: from.midX, y: from.midY), to: CGPoint(x: to.midX, y: to.midY)) }
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(210))
      withAnimation(.linear(duration: 0.575)) { purchase?.progress = 1 }
      try? await Task.sleep(for: .milliseconds(575))
      flights = []
      store.buy(item.id)
      purchase?.done = true
      try? await Task.sleep(for: .milliseconds(1700))
      selected = nil
      purchase = nil
      if let feature = item.feature { onUnlocked(feature) }
    }
  }
}

/// A purchase under way.
struct Purchase: Equatable {
  var id: String
  var start: Int
  var price: Int
  /// 0 to 1: how much of the price has gone in.
  var progress: Double
  var done = false
  var balance: Int { start - Int((Double(price) * progress).rounded()) }
  var left: Int { price - Int((Double(price) * progress).rounded()) }
}

/// The tree: features in rows, then the styles' row under its heading.
private struct ShopTree: View {
  let selected: String?
  let purchase: Purchase?
  @Binding var frames: [String: CGRect]
  let onTap: (String) -> Void
  @Environment(AppStore.self) private var store

  /// Where each item sits on a 358 by 700 grid. Endgame families and the styles sit in rows under their headings.
  static let spots: [String: CGPoint] = [
    "sidePicker": CGPoint(x: 56, y: 0), "lensPawns": CGPoint(x: 236, y: 0), "endgames": CGPoint(x: 318, y: 0),
    "openingPicker": CGPoint(x: 56, y: 112), "lensPieces": CGPoint(x: 236, y: 112), "lensPlan": CGPoint(x: 318, y: 112),
    "freeform": CGPoint(x: 56, y: 224), "guides": CGPoint(x: 146, y: 224), "lensKings": CGPoint(x: 236, y: 224),
    "middlegame": CGPoint(x: 318, y: 224),
    "personalities": CGPoint(x: 146, y: 336), "lensEval": CGPoint(x: 236, y: 336),
    "endgamesPawn": CGPoint(x: 56, y: 478), "endgamesRook": CGPoint(x: 146, y: 478),
    "boards": CGPoint(x: 36, y: 598), "pieces": CGPoint(x: 107, y: 598), "decks": CGPoint(x: 179, y: 598),
    "styles": CGPoint(x: 251, y: 598), "icons": CGPoint(x: 322, y: 598),
  ]

  var body: some View {
    GeometryReader { geo in
      let k = geo.size.width / 358
      let lit = related(selected)
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          for item in SHOP {
            // An endgame family sits in its own row under its heading: no line to Endgames.
            for need in item.needs where item.feature?.endgameFamily == nil {
              guard let a = Self.spots[need], let b = Self.spots[item.id] else { continue }
              var path = Path()
              path.move(to: CGPoint(x: a.x * k, y: a.y + 90))
              path.addLine(to: CGPoint(x: a.x * k, y: a.y + 99))
              path.addLine(to: CGPoint(x: b.x * k, y: a.y + 99))
              path.addLine(to: CGPoint(x: b.x * k, y: b.y - 5))
              let owned = store.state.unlocked.contains(need)
              var layer = context
              layer.opacity = lit == nil || (lit!.contains(need) && lit!.contains(item.id)) ? 1 : 0.28
              layer.stroke(path, with: .color(owned ? Theme.good : Theme.surface3),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
          }
        }
        Text("Endgames").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
          .offset(x: 8, y: 448).opacity(lit == nil || lit!.contains("endgames") ? 1 : 0.28)
        Text("Styles").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
          .offset(x: 8, y: 568).opacity(lit == nil ? 1 : 0.28)
        ForEach(SHOP) { item in
          if let spot = Self.spots[item.id] {
            ShopNode(item: item, status: store.state.status(item), selected: selected == item.id,
              purchase: purchase?.id == item.id ? purchase : nil, balance: store.state.pawns)
              .frame(width: 100)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShopView.space)) } action: { frames[item.id] = medallion($0) }
              .opacity(lit == nil || lit!.contains(item.id) ? 1 : 0.28)
              .offset(x: spot.x * k - 50, y: spot.y)
              .onTapGesture { onTap(item.id) }
          }
        }
      }
      .animation(.easeOut(duration: 0.35), value: selected)
    }
    .frame(height: 700)
  }

  /// The medallion inside a node's frame: its top 48 points, centered.
  private func medallion(_ node: CGRect) -> CGRect {
    CGRect(x: node.midX - 24, y: node.minY, width: 48, height: 48)
  }

  /// The item, what it needs and what needs it: the rest dims while its sheet is up.
  private func related(_ id: String?) -> Set<String>? {
    guard let id, let item = shopItem(id) else { return nil }
    return Set([id] + item.needs + SHOP.filter { $0.needs.contains(id) }.map(\.id))
  }
}

/// One item: its medallion, its name, and its price or a check.
private struct ShopNode: View {
  let item: ShopItem
  let status: ShopStatus
  let selected: Bool
  let purchase: Purchase?
  let balance: Int

  var body: some View {
    VStack(spacing: 0) {
      medallion.padding(.bottom, 6)
      Text(item.name.replacingOccurrences(of: " styles", with: "")).font(.system(size: 12, weight: .semibold))
        .foregroundStyle(dim ? Theme.text3 : Theme.text).lineLimit(2).minimumScaleFactor(0.85)
        .multilineTextAlignment(.center).frame(maxWidth: 100).fixedSize(horizontal: false, vertical: true)
      price.frame(height: 16)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  private var dim: Bool { status == .locked || status == .soon }

  @ViewBuilder private var medallion: some View {
    let owned = status == .owned || purchase?.done == true
    ZStack {
      switch status {
      case .soon:
        Circle().strokeBorder(Theme.surface3, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
      case .locked:
        Circle().fill(Theme.surface)
      case .buyable where purchase == nil:
        Circle().fill(Theme.accent)
      default:
        Circle().fill(Theme.surface2)
      }
      if let purchase, !purchase.done {
        ring(purchase.progress, Theme.pawn)
      } else if case .short = status {
        ring(Double(balance) / Double(item.price), Theme.accent)
      }
      Icon(name: status == .locked ? "lock" : shopIcon(item), size: 22).foregroundStyle(glyph(owned))
    }
    .frame(width: 48, height: 48)
    .overlay {
      if selected { Circle().strokeBorder(Theme.text, lineWidth: 2).padding(-5) }
    }
    .keyframeAnimator(initialValue: 1.0, trigger: purchase?.done == true) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
      CubicKeyframe(1.18, duration: 0.14)
      CubicKeyframe(1, duration: 0.18)
    }
  }

  private func ring(_ share: Double, _ color: SwiftUI.Color) -> some View {
    ZStack {
      Circle().stroke(Theme.surface3, lineWidth: 3)
      Circle().trim(from: 0, to: max(0, min(1, share))).stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(1.5)
  }

  private func glyph(_ owned: Bool) -> SwiftUI.Color {
    if owned { return Theme.good }
    if purchase != nil { return Theme.pawn }
    switch status {
    case .buyable: return Theme.accentInk
    case .locked, .soon: return Theme.text3
    default: return Theme.text2
    }
  }

  @ViewBuilder private var price: some View {
    if status == .owned || purchase?.done == true {
      Icon(name: "check", size: 14).foregroundStyle(Theme.good)
    } else {
      PawnAmount(count: purchase?.left ?? item.price, size: 12, color: dim ? Theme.text3 : status == .buyable || purchase != nil ? Theme.pawn : Theme.text2)
    }
  }
}

/// The short sheet over the tree: the item as it will look, what it does, and Buy, how
/// short you are, or the item it needs first.
private struct BuySheet: View {
  let item: ShopItem
  let purchase: Purchase?
  let onSelect: (String) -> Void
  let onBuy: () -> Void
  let onClose: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    let status = store.state.status(item)
    VStack(spacing: 0) {
      ZStack {
        Text(item.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
        HStack {
          Button(action: onClose) {
            Icon(name: "close", size: 19).foregroundStyle(Theme.text).frame(width: 37, height: 37)
              .background(Circle().fill(Theme.surface2))
          }
          .buttonStyle(.plain).accessibilityLabel("Close")
          .disabled(purchase != nil)
          Spacer()
        }
      }
      .frame(height: 56).padding(.horizontal, 4).padding(.bottom, 8)
      ShopPreview(item: item)
        .padding(14).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
        .opacity(status == .locked ? 0.4 : 1)
      Text(item.about).font(.system(size: 14)).foregroundStyle(Theme.text2)
        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity).padding(.top, 12).padding(.horizontal, 8)
      action(status).padding(.top, 14)
    }
    .padding(.horizontal, 16).padding(.top, 10)
  }

  @ViewBuilder private func action(_ status: ShopStatus) -> some View {
    let shape = RoundedRectangle(cornerRadius: 18)
    if purchase?.done == true || status == .owned {
      Label { Text("Owned") } icon: { Icon(name: "check", size: 19) }
        .font(.system(size: 17, weight: .semibold)).foregroundStyle(SwiftUI.Color(hex: 0x06240f))
        .frame(maxWidth: .infinity, minHeight: 54).background(shape.fill(Theme.good))
    } else {
      switch status {
      case .buyable:
        Button(action: onBuy) {
          HStack(spacing: 7) {
            Text("Buy")
            PawnAmount(count: purchase?.left ?? item.price, size: 17, color: SwiftUI.Color(hex: 0x0b0b0e))
          }
          .font(.system(size: 17, weight: .semibold)).foregroundStyle(SwiftUI.Color(hex: 0x0b0b0e))
          .frame(maxWidth: .infinity, minHeight: 54).background(shape.fill(Theme.text))
        }
        .buttonStyle(PressScale()).disabled(purchase != nil)
      case .short(let by):
        Text("\(by) short").font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text3)
          .frame(maxWidth: .infinity, minHeight: 54).background(shape.fill(Theme.surface2))
      case .locked:
        if let need = item.needs.compactMap(shopItem).first(where: { !store.state.unlocked.contains($0.id) }) {
          Button { onSelect(need.id) } label: {
            HStack(spacing: 8) {
              Icon(name: "lock", size: 17).foregroundStyle(Theme.text3)
              Text(need.name).foregroundStyle(Theme.text)
              Spacer()
              PawnAmount(count: need.price, size: 17)
              Icon(name: "chevron", size: 17).foregroundStyle(Theme.text3)
            }
            .font(.system(size: 17, weight: .semibold))
            .padding(.leading, 16).padding(.trailing, 14).frame(minHeight: 54).background(shape.fill(Theme.surface2))
          }
          .buttonStyle(.plain)
        }
      case .soon:
        Text("Coming later").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text3)
          .frame(maxWidth: .infinity, minHeight: 54).background(shape.fill(Theme.surface2))
      case .owned:
        EmptyView()
      }
    }
  }
}

/// A button that gives a little under the finger.
private struct PressScale: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(.easeOut(duration: 0.13), value: configuration.isPressed)
  }
}

/// What an item looks like where it lives: the real control.
private struct ShopPreview: View {
  let item: ShopItem

  var body: some View {
    let field = RoundedRectangle(cornerRadius: 12)
    switch item.id {
    case "sidePicker":
      HStack(spacing: 8) {
        ColorSquare(choice: .b, size: 21).frame(width: 42, height: 42).background(field.fill(Theme.surface2))
        ColorSquare(choice: .w, size: 21).frame(width: 42, height: 42).background(field.fill(Theme.surface2))
      }
    case "openingPicker":
      HStack(spacing: 8) {
        ColorSquare(choice: .w, size: 21).frame(width: 42, height: 42).background(field.fill(Theme.surface2))
        HStack {
          Text("Any Opening").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
          Spacer()
          Icon(name: "down", size: 17).foregroundStyle(Theme.text3)
        }
        .padding(.horizontal, 14).frame(height: 42).background(field.fill(Theme.surface2))
      }
    case "freeform":
      HStack(spacing: 8) {
        ColorSquare(choice: .either, size: 21).frame(width: 42, height: 42).background(field.fill(Theme.surface2))
        HStack(spacing: 0) {
          Text("Freeform").frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.surface3)).foregroundStyle(Theme.text)
          Text("Drill").frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(Theme.text2)
        }
        .font(.system(size: 15, weight: .medium)).padding(3).frame(height: 42).background(field.fill(Theme.surface2))
      }
    default:
      HStack(spacing: 10) {
        Icon(name: item.id == "middlegame" ? "middlegame" : item.id == "endgames" ? "flag" : shopIcon(item), size: 20)
          .foregroundStyle(Theme.accent)
        Text(item.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 14).frame(width: 200, height: 46, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
    }
  }
}

/// A pawn on its way from the balance to a medallion.
struct Flight: Identifiable, Equatable {
  var id: Int
  var from: CGPoint
  var to: CGPoint
}

/// The pawns in the air during a purchase: one after another, each arcing over to the medallion.
private struct FlightLayer: View {
  let flights: [Flight]

  var body: some View {
    ZStack {
      ForEach(flights) { flight in
        FlyingPawn(flight: flight)
      }
    }
    .allowsHitTesting(false)
  }
}

private struct FlyingPawn: View {
  let flight: Flight
  @State private var start = Date()

  var body: some View {
    TimelineView(.animation) { timeline in
      let t = (timeline.date.timeIntervalSince(start) - Double(flight.id) * 0.0375) / 0.32
      if t > 0, t < 1 {
        let jitter = Double((flight.id * 37) % 11 - 5) * 7
        let mid = CGPoint(x: (flight.from.x + flight.to.x) / 2 + jitter, y: (flight.from.y + flight.to.y) / 2 - 18)
        let p = quad(flight.from, mid, flight.to, easeInOut(t))
        Icon(name: "pawn", size: 18).foregroundStyle(Theme.pawn)
          .scaleEffect(t < 0.55 ? 0.8 + t : 1.3 - (t - 0.55))
          .opacity(t < 0.12 ? t / 0.12 : t > 0.92 ? (1 - t) / 0.08 : 1)
          .position(p)
      }
    }
  }

  private func easeInOut(_ t: Double) -> Double { t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2 }

  private func quad(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: Double) -> CGPoint {
    let u = 1 - t
    return CGPoint(x: u * u * a.x + 2 * u * t * b.x + t * t * c.x, y: u * u * a.y + 2 * u * t * b.y + t * t * c.y)
  }
}

/// An item's icon: the lenses share one.
func shopIcon(_ item: ShopItem) -> String {
  if item.feature?.isLens == true { return "shop.lenses" }
  if item.feature?.endgameFamily != nil { return "shop.endgames" }
  return "shop.\(item.id)"
}

/// Streak freezes: held for a missed day, used on their own, up to 2.
private struct StreakFreezeRow: View {
  @Environment(AppStore.self) private var store
  @State private var confirming = false

  var body: some View {
    let held = store.state.pawnStreak.freezes
    let full = held >= MAX_FREEZES
    let afford = store.state.pawns >= FREEZE_PRICE
    HStack(spacing: 12) {
      Icon(name: "flame", size: 20).foregroundStyle(Theme.ice)
      VStack(alignment: .leading, spacing: 2) {
        Text("Streak freeze").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
        Text("Keeps your streak through a missed day. \(held) of \(MAX_FREEZES) held.")
          .font(.system(size: 13)).foregroundStyle(Theme.text2)
      }
      Spacer(minLength: 0)
      Button { confirming = true } label: { PawnAmount(count: FREEZE_PRICE, size: 15) }
        .buttonStyle(PlayButtonStyle(kind: afford && !full ? .accent : .plain, height: 40, inset: 14))
        .disabled(full || !afford)
        .confirmationDialog("Buy a streak freeze?", isPresented: $confirming, titleVisibility: .visible) {
          Button("Buy for \(FREEZE_PRICE.formatted()) pawns") { store.update { $0.buyFreeze() } }
          Button("Cancel", role: .cancel) {}
        }
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
  }
}
