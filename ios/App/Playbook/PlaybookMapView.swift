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
/// after them, then the families you don't have, for sale. The bar at the bottom is the open
/// opening's row, for a locked one when it grows, and for a family Unlock at its price.
/// Choosing openings, it shows only the families the slot being filled takes, without prices,
/// and tapping one fills that slot.
struct PlaybookMapView: View {
  let tree: OpeningTree
  let side: ChessCore.Color
  var focus: MapFocus?
  var onConsumedFocus: () -> Void = {}
  /// The slots being filled, while choosing openings.
  var choosing: Binding<Choosing>? = nil
  /// Open an opening you have on its page.
  var onOpen: (MapNode) -> Void = { _ in }

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var memo = Memo<[MapNode]>()
  @State private var paths: [ChessCore.Color: [String]] = [:]
  /// Each opening's drawn height, so its links start right under its name.
  @State private var heights: [String: CGFloat] = [:]
  @State private var width: CGFloat = 393

  /// The room each opening has on the tree, top to bottom.
  static let nodeHeight: CGFloat = 104

  var body: some View {
    let roots = map
    let path = openPath(roots)
    let rows = mapRows(roots, path: path)
    let layout = mapLayout(rows, width: Double(width), nodeHeight: Double(Self.nodeHeight))
    let open = path.last.flatMap { id in rows.lazy.flatMap { $0 }.first { $0.id == id } }
    ScrollViewReader { reader in
      ScrollView {
        ZStack(alignment: .topLeading) {
          links(rows, path: path, layout: layout)
          ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
            ForEach(row) { node in
              if let spot = layout.spots[node.id] {
                MapNodeView(
                  node: node, width: CGFloat(spot.width), open: node.id == path.last,
                  recede: !path.contains(node.id) && r < rows.count - 1,
                  showPrice: choosing == nil, picked: picked(node)
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights[node.id] = $0 }
                .frame(width: CGFloat(spot.width), height: Self.nodeHeight, alignment: .top)
                .offset(x: CGFloat(spot.x - spot.width / 2), y: CGFloat(spot.y))
                .onTapGesture { tap(roots, path, node.id) }
                .transition(.opacity)
              }
            }
          }
          ForEach(Array(layout.bus.enumerated()), id: \.offset) { r, bus in
            // Placed by padding, not offset: an offset moves only the drawing, and scrolling goes by layout.
            SwiftUI.Color.clear.frame(width: 1, height: 1).padding(.top, CGFloat(bus) + 10).id("row\(r)")
          }
        }
        .frame(width: width, height: CGFloat(layout.height) + 24, alignment: .topLeading)
      }
      .scrollIndicators(.hidden)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if let open, choosing == nil { tray(open) }
      }
      .onChange(of: path) { _, now in
        let rows = mapRows(roots, path: now)
        withAnimation(.easeOut(duration: 0.3)) { reader.scrollTo("row\(rows.count - 1)", anchor: .bottom) }
      }
    }
    .task(id: "\(focus?.id ?? "")|\(focus?.side.rawValue ?? "")|\(side.rawValue)") { takeFocus(roots) }
  }

  /* ── the tree ── */

  /// One side's tree, kept until the Playbook, the games or the form change.
  private var map: [MapNode] {
    if let slot = choosing?.wrappedValue.slot { return memo.get("choosing|\(slot.rawValue)") { choosingMap(tree, slot: slot) } }
    let state = store.state
    let key = "\(side.rawValue)|" + state.playbookList.map { "\($0.id):\($0.nodes.count)" }.joined(separator: ",")
      + "|\(lastAddedAt(state.playbookList))|\(state.games.count)|\(state.form.stamp)"
      + "|\(state.owns(.sidePicker))|\(state.families.price(side))"
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

  /// The links: from the open opening down to each of its branches, and a short
  /// stub under every folded opening that has branches.
  private func links(_ rows: [[MapNode]], path: [String], layout: MapLayout) -> some View {
    let onPath = Set(path)
    let quiet = SwiftUI.Color(hex: 0x3a3a44)
    let heights = self.heights
    func bottom(_ id: String) -> Double {
      guard let spot = layout.spots[id] else { return 0 }
      return spot.y + Double(heights[id] ?? Self.nodeHeight)
    }
    func draw(_ context: GraphicsContext, _ p: Path, hot: Bool, dashed: Bool = false, faint: Bool = false) {
      var layer = context
      layer.opacity = faint ? 0.6 : 1
      layer.stroke(p, with: .color(hot ? Theme.accent : quiet),
        style: StrokeStyle(lineWidth: hot ? 2 : 1.5, lineCap: .round, dash: dashed ? [4, 3] : []))
    }
    return Canvas { context, _ in
      for (r, row) in rows.enumerated() {
        if r > 0, r - 1 < path.count, let parent = layout.spots[path[r - 1]] {
          let bus = layout.bus[r - 1]
          var trunk = Path()
          trunk.move(to: CGPoint(x: parent.x, y: bottom(path[r - 1]) + 5))
          trunk.addLine(to: CGPoint(x: parent.x, y: bus))
          draw(context, trunk, hot: row.contains { onPath.contains($0.id) })
          for node in row.sorted(by: { !onPath.contains($0.id) && onPath.contains($1.id) }) {
            guard let spot = layout.spots[node.id] else { continue }
            let entry = (spot.gate ?? spot.y) + 1, mid = (bus + entry) / 2
            var link = Path()
            link.move(to: CGPoint(x: parent.x, y: bus))
            link.addCurve(
              to: CGPoint(x: spot.x, y: entry), control1: CGPoint(x: parent.x, y: mid + 8), control2: CGPoint(x: spot.x, y: mid - 8))
            if spot.gate != nil { link.addLine(to: CGPoint(x: spot.x, y: spot.y + 1)) }
            draw(context, link, hot: onPath.contains(node.id), dashed: !node.owned)
          }
        }
        for node in row where !node.children.isEmpty && !onPath.contains(node.id) {
          guard let spot = layout.spots[node.id] else { continue }
          let top = bottom(node.id) + 4, count = node.children.count
          for i in 0..<count {
            let dx = (Double(i) - Double(count - 1) / 2) * 9
            var stub = Path()
            stub.move(to: CGPoint(x: spot.x, y: top))
            stub.addCurve(
              to: CGPoint(x: spot.x + dx, y: top + 11), control1: CGPoint(x: spot.x, y: top + 6),
              control2: CGPoint(x: spot.x + dx, y: top + 4))
            draw(context, stub, hot: false, faint: r < rows.count - 1)
          }
        }
      }
    }
    .allowsHitTesting(false)
  }

  /* ── the bar at the bottom ── */

  @ViewBuilder private func tray(_ node: MapNode) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Text(compactMoves(node.line)).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
        if let tag = shelfTag(node) {
          HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).frame(width: 3, height: 13)
            Text(tag.word).font(.system(size: 12, weight: .semibold))
          }
          .foregroundStyle(tag.color)
        }
        Spacer(minLength: 0)
        if node.owned {
          Text("LINES").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(Theme.text3).padding(.trailing, 28)
        }
      }
      .padding(.horizontal, 16).frame(height: 30)
      VStack(spacing: 0) {
        if node.owned { ownedRow(node) } else { lockedRows(node) }
      }
      .background(Theme.surface)
      .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    .padding(.horizontal, 16).padding(.bottom, 10).padding(.top, 4)
    .background(Theme.background)
  }

  private func ownedRow(_ node: MapNode) -> some View {
    Button { onOpen(node) } label: {
      HStack(spacing: 10) {
        Text(node.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
          .frame(maxWidth: .infinity, alignment: .leading)
        FormRing(form: node.form).frame(width: 32, alignment: .trailing)
        Text("\(node.lines)").font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
          .frame(width: 40, alignment: .trailing)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 60).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  @ViewBuilder private func lockedRows(_ node: MapNode) -> some View {
    HStack(spacing: 10) {
      Text(node.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2).lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      if case .forSale(let price) = node.state {
        if store.state.families.tokens > 0, !store.state.ownedFamilies(side).isEmpty { swapMenu(node) }
        Button { buy(node) } label: {
          HStack(spacing: 6) {
            Text("Unlock").foregroundStyle(Theme.text)
            PawnAmount(count: price, size: 15)
          }
          .font(.system(size: 15, weight: .semibold))
          .padding(.horizontal, 12).frame(height: 36)
          .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface3))
          .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(store.state.pawns < price)
        .opacity(store.state.pawns < price ? 0.5 : 1)
      } else if node.state == .way {
        Text("Pick an answer below").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text3)
      }
    }
    .padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 60)
    ForEach(requirements(node), id: \.label) { need in
      Divider().overlay(SwiftUI.Color.white.opacity(0.06))
      HStack(spacing: 0) {
        Text(need.label).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text2)
        Spacer()
        Text(need.value).font(.system(size: 15, weight: .bold).monospacedDigit()).foregroundStyle(Theme.text)
        Group {
          if need.met { Icon(name: "check", size: 14).foregroundStyle(Theme.good) }
        }
        .frame(width: 18).padding(.leading, 8)
      }
      .padding(.horizontal, 16).frame(height: 40)
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

  /// Swap: an opening you have goes, with everything under it, and this one comes in its place.
  private func swapMenu(_ node: MapNode) -> some View {
    Menu {
      Section("Swap out, losing its progress") {
        ForEach(store.state.ownedFamilies(side)) { out in
          Button(out.name) { swap(out.id, for: node) }
        }
      }
    } label: {
      Text("Swap").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
        .padding(.horizontal, 12).frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.surface3, lineWidth: 1.5))
    }
  }

  private func buy(_ node: MapNode) {
    guard let id = node.family else { return }
    var bought = false
    store.update { bought = $0.buyFamily(id, tree) }
    if bought { toasts.show("\(node.name) added") }
  }

  private func swap(_ out: String, for node: MapNode) {
    guard let id = node.family else { return }
    var swapped = false
    store.update { swapped = $0.swapFamily(out, for: id, tree) }
    if swapped { toasts.show("\(node.name) added") }
  }

  private func shelfTag(_ node: MapNode) -> (word: String, color: SwiftUI.Color)? {
    guard let id = node.shelf, let shelf = SHELVES.first(where: { $0.id == id }) else { return nil }
    let word = ["gambits": "Gambit", "systems": "System"][id] ?? shelf.label
    return (word, SwiftUI.Color(hexString: shelf.color))
  }
}

/// The moves of a line, as "1.e4 e5 2.Nf3".
func compactMoves(_ sans: [String]) -> String {
  sansToMoveText(sans).replacingOccurrences(of: ". ", with: ".")
}

/// One opening on the tree: its disc with the move and the form arc, its name,
/// and for a locked one when it grows.
private struct MapNodeView: View {
  let node: MapNode
  let width: CGFloat
  let open: Bool
  let recede: Bool
  /// A family's price under it; choosing openings shows none.
  var showPrice = true
  /// Picked for a slot while choosing openings.
  var picked = false

  private var isNext: Bool { if case .next = node.state { return true } else { return false } }
  private var top: Bool { node.line.count == 1 }

  var body: some View {
    VStack(spacing: 0) {
      disc.padding(.top, 8)
      if !(top && (node.owned || node.forSale || node.state == .way)) {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          if let color = shelfColor {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 11).opacity(node.owned ? 1 : 0.55)
          }
          Text(node.label).font(.system(size: width < 76 ? 10.5 : 12, weight: .semibold))
            .foregroundStyle(node.owned ? Theme.text : Theme.text3)
            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
        }
        .padding(.top, 6)
      }
      if let when = mapWhen(node.state) {
        Text(when).font(.system(size: 11, weight: .semibold).monospacedDigit())
          .foregroundStyle(isNext ? Theme.accent : Theme.text3).lineLimit(1)
      } else if case .forSale(let price) = node.state, showPrice {
        PawnAmount(count: price, size: 11)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .frame(width: width)
    .opacity(recede ? 0.5 : 1)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isButton)
  }

  private var shelfColor: SwiftUI.Color? {
    node.shelf.flatMap { id in SHELVES.first { $0.id == id } }.map { SwiftUI.Color(hexString: $0.color) }
  }

  private var disc: some View {
    ZStack {
      if node.owned {
        Circle().fill(Theme.surface2)
        if !top { FormArc(form: node.form) }
      } else if picked {
        Circle().strokeBorder(Theme.accent, lineWidth: 2)
      } else {
        Circle().strokeBorder(isNext ? Theme.accent : SwiftUI.Color(hex: 0x3a3a44), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
      }
      if node.forSale || node.state == .way {
        Text(node.move).font(.system(size: 12, weight: .bold)).foregroundStyle(picked ? Theme.accent : Theme.text2)
          .minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 4)
      } else if !node.owned {
        Icon(name: "lock", size: 18).foregroundStyle(isNext ? Theme.accent : Theme.text3)
      } else if top {
        Text(node.move).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
      } else {
        Text(node.move).font(.system(size: 12, weight: .bold)).foregroundStyle(node.form == nil ? Theme.text3 : Theme.text2)
          .minimumScaleFactor(0.7).lineLimit(1).padding(.horizontal, 4)
      }
    }
    .frame(width: 48, height: 48)
    .overlay {
      if open { Circle().strokeBorder(Theme.text, lineWidth: 2).padding(-5) }
    }
    .overlay(alignment: .top) {
      if isNext {
        Text("Next").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accentInk)
          .padding(.horizontal, 5).frame(height: 14)
          .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent))
          .offset(y: -8)
      }
    }
  }
}
