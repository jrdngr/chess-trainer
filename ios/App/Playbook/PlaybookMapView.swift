import Book
import ChessCore
import Game
import Model
import SwiftUI

/// An opening on one side's tree for the Playbook tab to open at.
struct MapFocus: Equatable {
  var side: ChessCore.Color
  var id: String
}

/// The Playbook tab's tree: first moves on top, and under the open opening its
/// branches, the ones you have first and the locked ones the curve will add
/// after them, then the families you don't have, for sale. The card at the bottom is the open
/// opening: its name and tag, and its lines, its Unlock at its price, or what it still needs.
/// Choosing openings, it shows only the families the slot being filled takes, without prices,
/// and tapping one fills that slot.
struct PlaybookMapView: View {
  let tree: OpeningTree
  let side: ChessCore.Color
  /// The open path on each side, held by the screen around the tree; without it, the tree holds its own.
  var kept: Binding<[ChessCore.Color: [String]]>? = nil
  var focus: MapFocus?
  var onConsumedFocus: () -> Void = {}
  /// The slots being filled, while choosing openings.
  var choosing: Binding<Choosing>? = nil
  /// Open an opening you have on its page.
  var onOpen: (MapNode) -> Void = { _ in }
  /// An opening being bought, and the pawns flying from the balance into its disc; without
  /// them an Unlock buys at once.
  var purchase: Binding<Purchase?>? = nil
  var flights: Binding<[Flight]>? = nil
  /// The balance the pawns fly from, in `space`.
  var balanceFrame: CGRect = .zero

  /// The screen's coordinate space, which the flights are drawn in.
  static let space = "playbook"

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var memo = Memo<[MapNode]>()
  @State private var ownPaths: [ChessCore.Color: [String]] = [:]
  @State private var width: CGFloat = 393
  /// Where the tree's top left corner is in `space`, which moves as the tree scrolls.
  @State private var origin: CGPoint = .zero

  var body: some View {
    let roots = map
    let path = openPath(roots)
    let rows = mapRows(roots, path: path)
    let layout = mapLayout(rows, path: path, width: Double(width))
    let open = path.last.flatMap { id in rows.lazy.flatMap { $0 }.first { $0.id == id } }
    ScrollViewReader { reader in
      ScrollView {
        ZStack(alignment: .topLeading) {
          MapLinks(segments: mapLinks(layout, rows, path: path))
          ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
            ForEach(row) { node in
              if let spot = layout.spots[node.id] {
                MapNodeView(
                  node: node, open: node.id == path.last, onPath: path.contains(node.id),
                  recede: !path.contains(node.id) && r < rows.count - 1,
                  more: !node.children.isEmpty && !path.contains(node.id),
                  showPrice: choosing == nil, picked: picked(node),
                  purchase: purchase?.wrappedValue?.id == node.id ? purchase?.wrappedValue : nil
                )
                .frame(width: CGFloat(spot.width), height: CGFloat(MAP_DISC + MAP_NAME + MAP_FOOT), alignment: .top)
                .contentShape(Rectangle())
                .offset(x: CGFloat(spot.x - spot.width / 2), y: CGFloat(spot.y))
                .onTapGesture { if purchase?.wrappedValue == nil { tap(roots, path, node.id) } }
                .transition(.opacity)
              }
            }
          }
          ForEach(Array(layout.bottoms.enumerated()), id: \.offset) { r, bottom in
            // Placed by padding, not offset: an offset moves only the drawing, and scrolling goes by layout.
            SwiftUI.Color.clear.frame(width: 1, height: 1).padding(.top, CGFloat(bottom) + 10).id("row\(r)")
          }
        }
        .frame(width: width, height: CGFloat(layout.height) + 12, alignment: .topLeading)
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named(Self.space)).origin } action: { origin = $0 }
      }
      .scrollIndicators(.hidden)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let open, choosing == nil { card(open) }
      }
      // Back from a page: the open opening's row in view again, as it was left.
      .onAppear { DispatchQueue.main.async { reader.scrollTo("row\(rows.count - 1)", anchor: .bottom) } }
      .onChange(of: path) { _, now in
        let rows = mapRows(roots, path: now)
        withAnimation(.easeOut(duration: 0.3)) { reader.scrollTo("row\(rows.count - 1)", anchor: .bottom) }
      }
    }
    .task(id: "\(focus?.id ?? "")|\(focus?.side.rawValue ?? "")|\(side.rawValue)") { takeFocus(roots) }
  }

  private var paths: [ChessCore.Color: [String]] {
    get { kept?.wrappedValue ?? ownPaths }
    nonmutating set {
      if let kept { kept.wrappedValue = newValue } else { ownPaths = newValue }
    }
  }

  /* ── the tree ── */

  /// One side's tree, kept until the Playbook, the games or the form change.
  private var map: [MapNode] {
    if let slot = choosing?.wrappedValue.slot { return memo.get("choosing|\(slot.rawValue)") { choosingMap(tree, slot: slot) } }
    let state = store.state
    let key = "\(side.rawValue)|" + state.playbookList.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ",")
      + "|\(lastAddedAt(state.playbookList))|\(state.games.count)|\(state.form.stamp)|\(state.formAtMove.stamp)"
      + "|\(state.owns(.sidePicker))|\(state.families.price(side))|\(state.families.off.sorted())|\(state.playGamesPlayed)"
      + "|\(state.levelsOpened.sorted())"
    return memo.get(key) { playbookMap(state, tree, side: side) }
  }

  /// The open path on this side: what was last opened while it is still on the tree, else the first opening.
  private func openPath(_ roots: [MapNode]) -> [String] {
    if let kept = paths[side], let last = kept.last, let found = mapPath(roots, to: last) { return found }
    return roots.first.map { [$0.id] } ?? []
  }

  private func tap(_ roots: [MapNode], _ path: [String], _ id: String) {
    if let choosing, let family = find(roots, id)?.family {
      withAnimation(.easeOut(duration: 0.2)) { _ = choosing.wrappedValue.pick(family) }
      return
    }
    let next = mapTap(roots, path: path, id)
    withAnimation(.easeOut(duration: 0.26)) { paths[side] = next }
  }

  /// Whether a family is picked for its slot, while choosing.
  private func picked(_ node: MapNode) -> Bool {
    guard let choosing, let family = node.family, let slot = choiceSlot(family) else { return false }
    return choosing.wrappedValue.picks[slot] == family
  }

  private func find(_ roots: [MapNode], _ id: String?) -> MapNode? {
    for node in roots {
      if node.id == id { return node }
      if let found = find(node.children, id) { return found }
    }
    return nil
  }

  private func takeFocus(_ roots: [MapNode]) {
    guard let focus, focus.side == side else { return }
    if let found = mapPath(roots, to: focus.id) { paths[side] = found }
    onConsumedFocus()
  }

  /* ── the card at the bottom ── */

  private func card(_ node: MapNode) -> some View {
    let opens = node.owned && !node.off
    return HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(node.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
          .lineLimit(2).minimumScaleFactor(0.85)
        if let tag = tag(node) {
          Text(tag.word).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(tag.color)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      action(node)
    }
    .padding(.horizontal, 16).frame(height: 70)
    .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.surface2, lineWidth: 1))
    .contentShape(RoundedRectangle(cornerRadius: 20))
    .onTapGesture { if opens { onOpen(node) } }
    .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 10)
    .background(Theme.background)
  }

  /// The card's one key, or for a locked opening what it still needs.
  @ViewBuilder private func action(_ node: MapNode) -> some View {
    if node.owned && node.off, let id = node.family {
      Button { store.update { $0.setOpening(id, on: true) } } label: {
        Text("Enable").font(.system(size: 15, weight: .semibold))
      }
      .buttonStyle(KeyButtonStyle(kind: .primary, height: 45, radius: 12))
      .frame(width: 116)
    } else if node.owned {
      Button { onOpen(node) } label: {
        HStack(spacing: 8) {
          Text("View").font(.system(size: 15, weight: .semibold))
          Icon(name: "chevron", size: 14).opacity(0.85)
        }
      }
      .buttonStyle(KeyButtonStyle(kind: .primary, height: 45, radius: 12))
      .frame(width: 116)
    } else if case .forSale(let price) = node.state {
      Button { buy(node) } label: {
        HStack(spacing: 0) {
          Text("Unlock").font(.system(size: 15, weight: .semibold))
          Spacer(minLength: 8)
          PawnAmount(count: purchase?.wrappedValue?.left ?? price, size: 15).fixedSize()
        }
        .padding(.horizontal, 14)
      }
      .buttonStyle(KeyButtonStyle(kind: .primary, height: 45, radius: 12))
      .frame(width: 140)
      .disabled(store.state.pawns < price)
      .allowsHitTesting(purchase?.wrappedValue == nil)
    } else {
      let needs = requirements(node)
      if !needs.isEmpty {
        Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 5) {
          ForEach(needs, id: \.label) { need in
            GridRow {
              Text(need.label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
              Text(need.value).font(.system(size: 14, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
            }
          }
        }
        .fixedSize()
      }
    }
  }

  private struct Requirement {
    var label: String
    var value: String
    var met: Bool
  }

  /// What a locked opening waits for, one value each in an aligned column.
  private func requirements(_ node: MapNode) -> [Requirement] {
    switch node.state {
    case .owned, .forSale, .way: return []
    case .next, .locked(.inLine):
      return [Requirement(label: "Opens", value: mapWhen(node.state) ?? "", met: false)]
    case .locked(.games), .locked(.green):
      let gate = curveGate(store.state, tree)
      let games = node.gap.flatMap { CURVE_LEVEL_GAMES[curveLevel($0)] } ?? 0
      return [
        Requirement(label: "Games", value: "\(min(gate.games, games)) / \(games)", met: gate.games >= games),
        Requirement(label: "Green openings", value: "\(gate.green) / \(gate.openings)", met: gate.allGreen),
      ]
    }
  }

  /// Buy an opening as the Shop buys: pawns fly from the balance into its disc while its ring
  /// fills and the prices count down; then it is yours, and the tree opens at it.
  private func buy(_ node: MapNode) {
    guard let id = node.family, case .forSale(let price) = node.state, store.state.pawns >= price else { return }
    guard let purchase, let flights else {
      finish(node, id)
      return
    }
    guard purchase.wrappedValue == nil else { return }
    let roots = map
    let path = openPath(roots)
    let layout = mapLayout(mapRows(roots, path: path), path: path, width: Double(width))
    let start = store.state.pawns
    purchase.wrappedValue = Purchase(id: node.id, start: start, price: price, progress: 0)
    Task { @MainActor in
      if let spot = layout.spots[node.id] {
        let to = CGPoint(x: origin.x + CGFloat(spot.x), y: origin.y + CGFloat(spot.y + MAP_DISC / 2))
        let from = CGPoint(x: balanceFrame.midX, y: balanceFrame.midY)
        flights.wrappedValue = (0..<10).map { Flight(id: $0, from: from, to: to) }
      }
      try? await Task.sleep(for: .milliseconds(210))
      withAnimation(.linear(duration: 0.575)) { purchase.wrappedValue?.progress = 1 }
      try? await Task.sleep(for: .milliseconds(575))
      flights.wrappedValue = []
      if let opened = finish(node, id) {
        // The opening's own disc, new on the tree, pops as the Shop's medallion does.
        purchase.wrappedValue = Purchase(id: opened, start: start, price: price, progress: 1)
        try? await Task.sleep(for: .milliseconds(60))
        purchase.wrappedValue?.done = true
        try? await Task.sleep(for: .milliseconds(400))
      }
      purchase.wrappedValue = nil
    }
  }

  /// The opening bought, and the tree open at it. Returns the bought opening's node.
  @discardableResult
  private func finish(_ node: MapNode, _ id: String) -> String? {
    var bought = false
    store.update { bought = $0.buyFamily(id, tree) }
    guard bought else { return nil }
    toasts.show("\(node.name) added")
    // The bought opening is a new node on the rebuilt tree: open the tree at it.
    guard let found = mapPath(map, family: id) else { return nil }
    withAnimation(.easeOut(duration: 0.26)) { paths[side] = found }
    return found.last
  }

  /// An opening's tag as a word in the tag's color.
  private func tag(_ node: MapNode) -> (word: String, color: SwiftUI.Color)? {
    switch node.shelf {
    case "sharp": ("Sharp", SwiftUI.Color(hex: 0xf87171))
    case "solid": ("Solid", SwiftUI.Color(hex: 0x4fd8c4))
    case "gambits": ("Gambit", SwiftUI.Color(hex: 0xfb923c))
    case "systems": ("System", SwiftUI.Color(hex: 0x6ea4f9))
    default: nil
    }
  }
}

/// The moves of a line, as "1.e4 e5 2.Nf3".
func compactMoves(_ sans: [String]) -> String {
  sansToMoveText(sans).replacingOccurrences(of: ". ", with: ".")
}

/// The colors of what sits off the open path, above the last row.
private enum Recede {
  static let text = SwiftUI.Color(hex: 0x8b8b95)
  static let line = SwiftUI.Color(hex: 0x34343d)
  static let gold = SwiftUI.Color(hex: 0xb8923a)
}

/// The tree's links, each turn rounded.
private struct MapLinks: View {
  let segments: [MapSegment]

  var body: some View {
    Canvas { context, _ in
      for segment in segments {
        let (color, width): (SwiftUI.Color, CGFloat) =
          switch segment.kind {
          case .path: (Theme.accent, 2)
          case .owned: (SwiftUI.Color(hex: 0x50505c), 1.75)
          case .other: (SwiftUI.Color(hex: 0x3a3a44), 1.5)
          }
        context.stroke(path(segment.points), with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
      }
    }
    .allowsHitTesting(false)
  }

  private func path(_ points: [MapPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    func point(_ p: MapPoint) -> CGPoint { CGPoint(x: p.x, y: p.y) }
    path.move(to: point(first))
    for i in points.indices.dropFirst() {
      let here = points[i]
      guard i < points.count - 1 else {
        path.addLine(to: point(here))
        break
      }
      let before = points[i - 1], after = points[i + 1]
      func toward(_ to: MapPoint) -> CGPoint {
        let dx = to.x - here.x, dy = to.y - here.y, length = max(0.001, (dx * dx + dy * dy).squareRoot())
        let reach = min(MAP_CORNER_ROOM, length)
        return CGPoint(x: here.x + dx / length * reach, y: here.y + dy / length * reach)
      }
      path.addLine(to: toward(before))
      path.addQuadCurve(to: toward(after), control: point(here))
    }
    return path
  }
}

/// One opening on the tree: its disc with the move and the form arc, its name,
/// and under it its price, or for a locked one when it grows.
private struct MapNodeView: View {
  let node: MapNode
  let open: Bool
  /// On the open path, above the open opening.
  let onPath: Bool
  let recede: Bool
  /// It has branches, folded.
  let more: Bool
  /// A family's price under it; choosing openings shows none.
  var showPrice = true
  /// Picked for a slot while choosing openings.
  var picked = false
  /// This opening being bought.
  var purchase: Purchase? = nil

  private var isNext: Bool { if case .next = node.state { return true } else { return false } }
  private var top: Bool { node.line.count == 1 }
  private var locked: Bool { !node.owned && !node.forSale && node.state != .way }

  var body: some View {
    VStack(spacing: 0) {
      disc
      if mapShowsName(node) {
        Text(node.label).font(.system(size: 12, weight: .semibold))
          .foregroundStyle(recede ? Recede.text : Theme.text)
          .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
          .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .bottom)
          .padding(.top, 7)
        Group {
          if let when = mapWhen(node.state) {
            Text(when).font(.system(size: 11, weight: .medium).monospacedDigit())
              .foregroundStyle(recede ? Recede.text : Theme.text2).lineLimit(1)
          } else if case .forSale(let price) = node.state, showPrice {
            PawnAmount(count: purchase?.left ?? price, size: 11, color: recede ? Recede.gold : Theme.pawn)
          }
        }
        .frame(height: CGFloat(MAP_FOOT))
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  private var ink: SwiftUI.Color {
    if open { return .white }
    if picked { return Theme.accent }
    if onPath { return Theme.selectedInk }
    if recede { return Recede.text }
    return node.owned ? Theme.text : Theme.text2
  }

  private var disc: some View {
    ZStack {
      if node.owned {
        Circle().fill(open ? Theme.key : onPath ? Theme.selected : recede ? Theme.surface : Theme.surface2)
        Circle().stroke(open ? Theme.keyLip : onPath ? SwiftUI.Color(hex: 0x40417c) : recede ? Theme.surface3 : SwiftUI.Color(hex: 0x3a3a44), lineWidth: 3)
          .padding(1.5)
        if !top, let form = node.form {
          Circle().trim(from: 0, to: max(0.001, min(1, form)))
            .stroke(formColor(form), style: StrokeStyle(lineWidth: 3, lineCap: form >= 1 ? .butt : .round))
            .rotationEffect(.degrees(-90))
            .padding(1.5)
        }
      } else if open {
        Circle().fill(Theme.key)
      } else {
        Circle().fill(Theme.background)
        Circle().strokeBorder(picked ? Theme.accent : recede ? Recede.line : SwiftUI.Color(hex: 0x4a4a55), lineWidth: picked ? 2 : 1.5)
      }
      if locked {
        Icon(name: "lock", size: 16).foregroundStyle(open ? .white : recede ? Theme.text3 : Theme.text2)
      } else {
        Text(node.move).font(.system(size: 13, weight: .bold)).foregroundStyle(ink)
          .minimumScaleFactor(0.6).lineLimit(1).padding(.horizontal, 4)
          .offset(y: more ? -2.5 : 0)
      }
      if more {
        Chevron().stroke(Theme.text2, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          .frame(width: 11, height: 4.5).offset(y: 12.5)
      }
    }
    .frame(width: CGFloat(MAP_DISC), height: CGFloat(MAP_DISC))
    .overlay {
      if let purchase, !purchase.done {
        Circle().trim(from: 0, to: max(0, min(1, purchase.progress)))
          .stroke(Theme.pawn, style: StrokeStyle(lineWidth: 3, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .padding(-4)
      }
    }
    .keyframeAnimator(initialValue: 1.0, trigger: purchase?.done == true) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
      CubicKeyframe(1.18, duration: 0.14)
      CubicKeyframe(1, duration: 0.18)
    }
    .overlay(alignment: .topTrailing) {
      if isNext || node.off {
        Text(isNext ? "Next" : "Off").font(.system(size: 10, weight: .bold)).foregroundStyle(isNext ? .white : Theme.text2)
          .padding(.horizontal, 5).frame(height: 16)
          .background(RoundedRectangle(cornerRadius: 4.5).fill(isNext ? Theme.key : Theme.key2))
          .background(RoundedRectangle(cornerRadius: 5.5).fill(Theme.background).padding(-2))
          .offset(x: 7, y: -5)
      }
    }
  }
}

/// The mark under a folded opening's move: more below.
private struct Chevron: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    return path
  }
}
