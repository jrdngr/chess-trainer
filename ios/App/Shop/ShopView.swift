import AVFoundation
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
  @State private var sheetHeight: CGFloat = 300
  /// Whether `sheetHeight` fits the selected item yet: the sheet waits for it, since a sheet
  /// that opens at a stale height and grows mid-presentation can stay short and cut off its top.
  @State private var measured = false
  /// The shop's width, which is the sheet's: the sheet's picture is sized from it.
  @State private var width: CGFloat = 0
  /// A sheet's picture shown whole: the sheet grows to full height to hold it. A presentation
  /// of its own inside the sheet would keep the sheet from sizing to its content.
  @State private var fullScreen: String?
  /// The pawn sheet: over the item's sheet while one is up, else over the shop.
  @State private var pawnsOpen = false

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Pawn Shop").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        Spacer()
        Button { if purchase == nil { pawnsOpen = true } } label: {
          PawnAmount(count: purchase?.balance ?? store.state.pawns)
            .padding(.horizontal, 14).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.state.pawns) pawns, buy pawns")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames["balance"] = $0 }
      }
      .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
      ScrollView {
        VStack(spacing: 16) {
          ShopTree(selected: selected, purchase: purchase, frames: $frames) { if purchase == nil { selected = $0 } }
        }
        .padding(.horizontal, 16).padding(.bottom, selected == nil ? 24 : sheetHeight + 30)
        // While a sheet is up, a tap behind it closes the sheet and reaches nothing else.
        .overlay {
          if selected != nil {
            SwiftUI.Color.clear.contentShape(Rectangle())
              .onTapGesture { if purchase == nil { selected = nil } }
          }
        }
      }
    }
    .background(alignment: .top) {
      // The selected item's sheet, laid out unseen to size the sheet before it opens.
      if let id = selected, let item = shopItem(id) {
        BuySheet(item: item, purchase: purchase, width: width, measuring: true, fullScreen: .constant(nil), onSelect: { _ in }, onBuy: {}, onShort: {}) {}
          .fixedSize(horizontal: false, vertical: true)
          .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if width > 0 { sheetHeight = min($0, 760); measured = true } }
          .hidden().allowsHitTesting(false).accessibilityHidden(true)
      }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .onChange(of: selected) { if selected == nil { measured = false } }
    .background(Theme.background.ignoresSafeArea())
    .overlay { FlightLayer(flights: flights) }
    .coordinateSpace(name: Self.space)
    .sheet(isPresented: Binding(get: { selected != nil && measured }, set: { if !$0, purchase == nil { selected = nil } })) {
      if let id = selected, let item = shopItem(id) {
        BuySheet(item: item, purchase: purchase, width: width, fullScreen: $fullScreen, onSelect: { selected = $0 }, onBuy: { buy(item) }, onShort: { pawnsOpen = true }) { selected = nil }
          .pawnSheet(isPresented: $pawnsOpen)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxHeight: .infinity, alignment: .top)
          .presentationDetents(fullScreen == nil ? [.height(sheetHeight)] : [.large])
          .presentationBackground(SwiftUI.Color(hex: 0x131317))
          .presentationBackgroundInteraction(.enabled)
          .interactiveDismissDisabled(purchase != nil)
      }
    }
    .pawnSheet(isPresented: Binding(get: { pawnsOpen && selected == nil }, set: { if !$0 { pawnsOpen = false } }))
    .onChange(of: focus, initial: true) {
      guard let focus else { return }
      // An empty focus opens the shop on no item.
      if shopItem(focus) != nil { selected = focus }
      self.focus = nil
    }
  }

  static let space = "shop"

  /// The purchase played out: the sheet closes, pawns fly, the ring fills, the counts run down; then it is yours.
  private func buy(_ item: ShopItem) {
    guard purchase == nil, store.state.status(item) == .buyable else { return }
    let start = store.state.pawns
    purchase = Purchase(id: item.id, start: start, price: item.price, progress: 0)
    selected = nil
    Task { @MainActor in
      // The sheet slides away before the pawns take off, so the whole flight shows.
      try? await Task.sleep(for: .milliseconds(350))
      if let from = frames["balance"], let to = frames[item.id] {
        flights = (0..<10).map { Flight(id: $0, from: CGPoint(x: from.midX, y: from.midY), to: CGPoint(x: to.midX, y: to.midY)) }
      }
      try? await Task.sleep(for: .milliseconds(210))
      withAnimation(.linear(duration: 0.575)) { purchase?.progress = 1 }
      try? await Task.sleep(for: .milliseconds(575))
      flights = []
      store.buy(item.id)
      purchase?.done = true
      try? await Task.sleep(for: .milliseconds(1700))
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

/// The tree: features down the left; the lenses chained down beside them, each with its
/// upgrades on a straight line to its right; Middlegame, Plan and Endgames under them, Endgames
/// with its families; then the styles' row under its heading.
private struct ShopTree: View {
  let selected: String?
  let purchase: Purchase?
  @Binding var frames: [String: CGRect]
  let onTap: (String) -> Void
  @Environment(AppStore.self) private var store
  /// Each node's height, name and price included: lines start under it.
  @State private var heights: [String: CGFloat] = [:]

  static let row: CGFloat = 132
  static let stylesY: CGFloat = 6 * row + 30
  static let height: CGFloat = stylesY + 100

  /// Where each item sits on a grid 358 wide: x is the node's center, y its top.
  static let spots: [String: CGPoint] = {
    let r = row
    return [
      "sidePicker": CGPoint(x: 48, y: 0), "openingPicker": CGPoint(x: 48, y: r), "freeform": CGPoint(x: 48, y: 2 * r),
      "middlegame": CGPoint(x: 48, y: 3 * r), "personalities": CGPoint(x: 48, y: 4 * r),
      "lensPawns": CGPoint(x: 150, y: 0), "lensStructure": CGPoint(x: 234, y: 0), "lensEndgamePawns": CGPoint(x: 314, y: 0),
      "lensPieces": CGPoint(x: 150, y: r), "lensControl": CGPoint(x: 234, y: r), "lensEndgamePieces": CGPoint(x: 314, y: r),
      "lensKings": CGPoint(x: 150, y: 2 * r), "lensEndgameKings": CGPoint(x: 234, y: 2 * r),
      "lensEval": CGPoint(x: 150, y: 3 * r), "lensEvalHistory": CGPoint(x: 234, y: 3 * r),
      "lensPlan": CGPoint(x: 150, y: 4 * r), "endgames": CGPoint(x: 254, y: 4 * r),
      "endgamesPawn": CGPoint(x: 194, y: 5 * r), "endgamesRook": CGPoint(x: 314, y: 5 * r),
      "boards": CGPoint(x: 36, y: stylesY), "pieces": CGPoint(x: 107, y: stylesY), "decks": CGPoint(x: 179, y: stylesY),
      "styles": CGPoint(x: 251, y: stylesY), "icons": CGPoint(x: 322, y: stylesY),
    ]
  }()

  /// A lens upgrade's medallion is smaller, its center level with its lens's.
  static func size(_ item: ShopItem) -> CGFloat { item.feature?.isLensUpgrade == true ? 36 : 48 }

  var body: some View {
    GeometryReader { geo in
      let k = geo.size.width / 358
      let lit = related(selected)
      ZStack(alignment: .topLeading) {
        Canvas { context, _ in
          for item in SHOP {
            for need in item.needs {
              guard let path = line(from: need, to: item, k: k) else { continue }
              let owned = store.state.unlocked.contains(need)
              var layer = context
              layer.opacity = lit == nil || (lit!.contains(need) && lit!.contains(item.id)) ? 1 : 0.28
              layer.stroke(path, with: .color(owned ? Theme.good : Theme.surface3),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
          }
        }
        Text("Styles").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
          .offset(x: 8, y: Self.stylesY - 30).opacity(lit == nil ? 1 : 0.28)
        ForEach(SHOP) { item in
          if let spot = Self.spots[item.id] {
            let size = Self.size(item)
            ShopNode(item: item, status: store.state.status(item), selected: selected == item.id,
              purchase: purchase?.id == item.id ? purchase : nil, balance: store.state.pawns, size: size)
              .frame(width: size < 48 ? 80 : 100)
              .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ShopView.space)) } action: {
                frames[item.id] = CGRect(x: $0.midX - size / 2, y: $0.minY, width: size, height: size)
              }
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[item.id] = $0 }
              .opacity(lit == nil || lit!.contains(item.id) ? 1 : 0.28)
              .offset(x: spot.x * k - (size < 48 ? 40 : 50), y: spot.y + (48 - size) / 2)
              .onTapGesture { onTap(item.id) }
          }
        }
      }
      .animation(.easeOut(duration: 0.35), value: selected)
    }
    .frame(height: Self.height)
  }

  /// The line from an item to one that needs it. A lens upgrade sits on a straight line from
  /// its lens, through the upgrade before it; the lenses chain straight down. Every other line
  /// leaves under its row's names and prices and turns once.
  private func line(from need: String, to item: ShopItem, k: CGFloat) -> Path? {
    guard let a = Self.spots[need], let b = Self.spots[item.id], let needed = shopItem(need) else { return nil }
    var path = Path()
    if item.feature?.isLensUpgrade == true {
      // From the nearest node to its left on the row: the lens or the upgrade before this one.
      let left = Self.spots.filter { $0.value.y == a.y && $0.value.x < b.x }.max { $0.value.x < $1.value.x }
      guard let left, let leftItem = shopItem(left.key) else { return nil }
      let y = a.y + 24
      path.move(to: CGPoint(x: left.value.x * k + Self.size(leftItem) / 2 + 6, y: y))
      path.addLine(to: CGPoint(x: b.x * k - Self.size(item) / 2 - 6, y: y))
      return path
    }
    let bottom = (heights[need] ?? 90) + a.y + (48 - Self.size(needed)) / 2
    if a.x == b.x {
      path.move(to: CGPoint(x: a.x * k, y: bottom + 2))
      path.addLine(to: CGPoint(x: b.x * k, y: b.y - 6))
      return path
    }
    // Under every name and price on the parent's row, so the line never crosses one.
    let rowBottom = Self.spots.filter { $0.value.y == a.y }.map { a.y + (heights[$0.key] ?? 90) }.max() ?? bottom
    path.move(to: CGPoint(x: a.x * k, y: bottom + 2))
    path.addLine(to: CGPoint(x: a.x * k, y: rowBottom + 6))
    path.addLine(to: CGPoint(x: b.x * k, y: rowBottom + 6))
    path.addLine(to: CGPoint(x: b.x * k, y: b.y - 6))
    return path
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
  /// The medallion's width: smaller for a lens upgrade.
  var size: CGFloat = 48

  var body: some View {
    VStack(spacing: 0) {
      medallion.padding(.bottom, 6)
      Text(item.name.replacingOccurrences(of: " styles", with: "")).font(.system(size: 12, weight: .semibold))
        .foregroundStyle(dim ? Theme.text3 : Theme.text).lineLimit(2).minimumScaleFactor(0.85)
        .multilineTextAlignment(.center).frame(maxWidth: size < 48 ? 76 : 100).fixedSize(horizontal: false, vertical: true)
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
        Circle().fill(Theme.key)
      default:
        Circle().fill(Theme.surface2)
      }
      if let purchase, !purchase.done {
        ring(purchase.progress, Theme.pawn)
      } else if case .short = status {
        ring(Double(balance) / Double(item.price), Theme.accent)
      }
      Icon(name: status == .locked ? "lock" : shopIcon(item), size: size < 48 ? 17 : 22).foregroundStyle(glyph(owned))
    }
    .frame(width: size, height: size)
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
    case .buyable: return .white
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

/// The sheet over the tree: the item as it looks in use, one sentence on what it does, and
/// Buy, how short you are, or the item it needs first. Items not built yet share one card.
private struct BuySheet: View {
  let item: ShopItem
  let purchase: Purchase?
  /// The sheet's width. Given, not measured, so the picture has its size on the first layout
  /// and the sheet's height is right before it opens.
  let width: CGFloat
  /// Laid out unseen only to size the sheet: a video is left as its empty frame.
  var measuring = false
  /// The picture shown full screen, by asset name.
  @Binding var fullScreen: String?
  let onSelect: (String) -> Void
  let onBuy: () -> Void
  /// A price you can't pay yet: opens the pawn sheet.
  let onShort: () -> Void
  let onClose: () -> Void
  @Environment(AppStore.self) private var store

  var body: some View {
    if let name = fullScreen {
      Image(name + "-full").resizable().scaledToFit()
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { fullScreen = nil }
        .accessibilityAddTraits(.isButton).accessibilityLabel("Close")
    } else {
      card
    }
  }

  private var card: some View {
    let status = store.state.status(item)
    return VStack(spacing: 0) {
      ZStack {
        Text(status == .soon ? "Coming later" : item.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
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
      if status == .soon {
        SoonGrid()
      } else if let shot = ShopShot.of(item.id) {
        shotView(shot)
      } else {
        ShopPreview(item: item)
          .padding(14).frame(maxWidth: .infinity)
          .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
      }
      Text(status == .soon ? "These items are not built yet." : item.about).font(.system(size: 15)).foregroundStyle(Theme.text2)
        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 14).padding(.horizontal, 4)
      action(status).padding(.top, 16)
    }
    .padding(.horizontal, 16).padding(.top, 10)
  }

  /// The picture's size: the sheet's width inside its padding, unless that would make it
  /// taller than the cap. A resizable image's own size would push the sheet wider than the screen.
  private func size(_ aspect: CGFloat) -> CGSize {
    let height = min(ShopShot.maxHeight, max(0, width - 32) / aspect)
    return CGSize(width: height * aspect, height: height)
  }

  @ViewBuilder private func shotView(_ shot: ShopShot) -> some View {
    let shape = RoundedRectangle(cornerRadius: 16)
    switch shot {
    case .image(let name):
      let box = size(ShopShot.aspect(name))
      Image(name).resizable()
        .frame(width: box.width, height: box.height)
        .clipShape(shape)
        .onTapGesture { fullScreen = name }
        .accessibilityAddTraits(.isButton).accessibilityLabel("Show full screen")
    case .video(let name, let aspect):
      let box = size(aspect)
      Group { if measuring { SwiftUI.Color.clear } else { LoopingVideo(name: name) } }
        .frame(width: box.width, height: box.height)
        .clipShape(shape)
    }
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
            PawnAmount(count: purchase?.left ?? item.price, size: 17, color: .white)
          }
          .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(KeyButtonStyle(kind: .primary, height: 54, radius: 18)).allowsHitTesting(purchase == nil)
      case .short:
        Button(action: onShort) {
          ZStack {
            PawnAmount(count: item.price, size: 17, color: Theme.text2)
            HStack {
              Spacer()
              Icon(name: "chevron", size: 17).foregroundStyle(Theme.text3)
            }
          }
          .font(.system(size: 17, weight: .semibold))
          .padding(.horizontal, 14)
          .frame(maxWidth: .infinity, minHeight: 54).background(shape.fill(Theme.surface2))
          .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.price) pawns, buy pawns")
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
          Text("King\u{2019}s Gambit").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.text)
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
struct FlightLayer: View {
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

/// An item's icon: the board lenses share one; Plan has its own.
func shopIcon(_ item: ShopItem) -> String {
  if item.feature == .lensPlan { return "shop.lensPlan" }
  if item.feature?.isLens == true { return "shop.lenses" }
  if item.feature?.isLensUpgrade == true { return "shop.lensUpgrade" }
  if item.feature?.endgameFamily != nil { return "shop.endgames" }
  return "shop.\(item.id)"
}

/// What an item's sheet shows in place of its control: a game with the item in use.
private enum ShopShot {
  case image(String)
  case video(String, aspect: CGFloat)

  /// Keeps the sheet under three quarters of the screen.
  static let maxHeight: CGFloat = 400

  /// A picture's width over its height, from the asset.
  static func aspect(_ name: String) -> CGFloat {
    guard let size = UIImage(named: name)?.size, size.height > 0 else { return 0.75 }
    return size.width / size.height
  }

  static func of(_ id: String) -> ShopShot? {
    switch id {
    case "middlegame": return .video("shop-middlegame", aspect: 560.0 / 848.0)
    case "lensPawns", "lensStructure", "lensEndgamePawns", "lensPieces", "lensControl", "lensEndgamePieces",
      "lensKings", "lensEndgameKings", "lensEval", "lensEvalHistory", "lensPlan", "endgames", "endgamesPawn", "endgamesRook":
      return .image("shop-\(id)")
    default: return nil
    }
  }
}

/// Every item not built yet, on the one card they share.
private struct SoonGrid: View {
  var body: some View {
    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
      ForEach(SHOP.filter { $0.feature == nil }, id: \.id) { item in
        HStack(spacing: 9) {
          Icon(name: "lock", size: 17).foregroundStyle(Theme.text3)
          Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text2)
            .lineLimit(2).minimumScaleFactor(0.85)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
      }
    }
  }
}

/// A muted clip from the app bundle, looping.
private struct LoopingVideo: UIViewRepresentable {
  let name: String

  final class PlayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var looper: AVPlayerLooper?
  }

  func makeUIView(context: Context) -> PlayerView {
    let view = PlayerView()
    view.backgroundColor = .black
    guard let url = Bundle.main.url(forResource: name, withExtension: "mp4") else { return view }
    let player = AVQueuePlayer()
    player.isMuted = true
    view.looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspectFill
    player.play()
    return view
  }

  func updateUIView(_ uiView: PlayerView, context: Context) {}

  static func dismantleUIView(_ uiView: PlayerView, coordinator: ()) {
    uiView.playerLayer.player?.pause()
  }
}
