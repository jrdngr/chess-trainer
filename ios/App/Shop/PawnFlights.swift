import ChessCore
import Game
import Model
import SwiftUI

/// Where pawns pop out and where they land: views mark themselves with `pawnSpot`.
struct PawnSpotsKey: PreferenceKey {
  static var defaultValue: [String: Anchor<CGRect>] { [:] }
  static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
    value.merge(nextValue()) { $1 }
  }
}

extension View {
  /// This view is where pawns pop out from (`board`, `callout`, `prep`, `goal`) or land (`counter`).
  func pawnSpot(_ name: String) -> some View {
    anchorPreference(key: PawnSpotsKey.self, value: .bounds) { [name: $0] }
  }

  /// Earned pawns pop out of what earned them and fly into the counter, over this screen.
  /// `orientation`: the board's, for pawns earned on a square.
  func pawnFlights(orientation: ChessCore.Color = .w) -> some View {
    overlayPreferenceValue(PawnSpotsKey.self) { spots in
      GeometryReader { geo in
        PawnFlightLayer(spots: spots.mapValues { geo[$0] }, orientation: orientation)
      }
      .allowsHitTesting(false)
    }
  }
}

/// The tuned timings and distances (points, milliseconds, degrees).
enum PawnMotion {
  static let popMs = 600.0
  static let holdMs = 0.0
  static let collectMinMs = 500.0
  static let collectMaxMs = 650.0
  static let popDistance = 50.0
  static let spreadDeg = 30.0
  static let spawnStaggerMs = 40.0
  static let leaveStaggerMs = 100.0
  static let bowPx = 18.0
  static let bowPeak = 0.5
  static let popBowPx = 0.0
  static let popEase = Bezier(0.2, 1, 0.4, 1)
  static let collectEase = Bezier(0.55, 0, 0.9, 0.35)
  /// What the movements were first drawn at, so the parts tied to them stretch along.
  static let refPopMs = 190.0, refCollectMin = 260.0, refCollectMax = 370.0, refDistance = 66.0, refSpread = 52.0
  static let popScaleMs = 90.0, popFadeMs = 50.0, fadeMs = 40.0
  static let distanceJitter = 12.0, distanceGap = 5.0, edge = 34.0
  static let fanJitter = 9.0, fanTurn = 12.0, soloMin = 12.0, soloMax = 30.0
  static let washMs = 220.0, sparkMs = 200.0
  static let ghostLags = [25.0, 50.0, 75.0], ghostOpacity = [0.42, 0.26, 0.13], streak = 24.0
  static let size = 28.0
}

/// A CSS cubic-bezier easing.
struct Bezier {
  let x1, y1, x2, y2: Double
  init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
    (self.x1, self.y1, self.x2, self.y2) = (x1, y1, x2, y2)
  }

  func callAsFunction(_ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    var lo = 0.0, hi = 1.0, s = 0.5
    for _ in 0..<26 {
      s = (lo + hi) / 2
      let m = 1 - s
      if 3 * m * m * s * x1 + 3 * m * s * s * x2 + s * s * s < x { lo = s } else { hi = s }
    }
    let m = 1 - s
    return 3 * m * m * s * y1 + 3 * m * s * s * y2 + s * s * s
  }
}

/// One pawn's whole trip, planned when its drop arrives.
struct PawnTrip {
  var drop: Int
  var angle: Double
  /// Where it pops out from, where it stops, and the sideways bow of its flight.
  var origin: CGPoint
  var stop: CGPoint
  var normal: CGVector
  var spawn: Double
  var leave: Double
  var arrive: Double
  var collect: Double
  /// How much the ghost trail's lags stretch with this flight.
  var ghostStretch: Double
  var target: CGPoint

  /// Where it is at `t` ms, its scale and opacity; nil off screen.
  func at(_ t: Double) -> (point: CGPoint, scale: Double, opacity: Double)? {
    guard t >= spawn, t < arrive else { return nil }
    let lerp = { (a: Double, b: Double, u: Double) in a + (b - a) * u }
    let clamp = { (v: Double) in min(1, max(0, v)) }
    if t < spawn + PawnMotion.popMs {
      let k = PawnMotion.popMs / PawnMotion.refPopMs
      let e = PawnMotion.popEase((t - spawn) / PawnMotion.popMs)
      let out = 1 - pow(1 - clamp((t - spawn) / (PawnMotion.popScaleMs * k)), 3)
      return (CGPoint(x: lerp(origin.x, stop.x, e), y: lerp(origin.y, stop.y, e)), lerp(0.3, 1, out), clamp((t - spawn) / (PawnMotion.popFadeMs * k)))
    }
    if t < leave { return (stop, 1, 1) }
    let u = (t - leave) / collect
    let c = PawnMotion.collectEase(u)
    let peak = PawnMotion.bowPeak
    let w = c < peak ? 0.5 * c / peak : 0.5 + 0.5 * (c - peak) / (1 - peak)
    let bow = PawnMotion.bowPx * sin(.pi * w)
    let point = CGPoint(x: lerp(stop.x, target.x, c) + normal.dx * bow, y: lerp(stop.y, target.y, c) + normal.dy * bow)
    return (point, u > 0.65 ? lerp(1, 0.6, (u - 0.65) / 0.35) : 1, clamp((arrive - t) / PawnMotion.fadeMs))
  }
}

/// A seeded random number source, so a drop plays the same however often it is drawn.
private struct Seeded {
  var state: UInt32
  mutating func next() -> Double {
    state = state &+ 0x6D2B_79F5
    var t = state
    t = (t ^ (t >> 15)) &* (t | 1)
    t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
    return Double(t ^ (t >> 14)) / 4_294_967_296
  }
}

/// Plans a drop's pawns: a fan out of the source, up or, where up leaves the screen, down,
/// nearest the counter going first.
func planTrips(drop: Int, count: Int, from source: CGRect, to target: CGPoint, width: Double, start: Double) -> [PawnTrip] {
  var random = Seeded(state: UInt32(truncatingIfNeeded: 9973 &* drop &+ 17))
  let origin = CGPoint(x: source.midX, y: source.midY)
  let dk = PawnMotion.popDistance / PawnMotion.refDistance
  let fanJ = PawnMotion.fanJitter * min(1, PawnMotion.spreadDeg / PawnMotion.refSpread)
  let turn = (random.next() * 2 - 1) * PawnMotion.fanTurn
  let side: Double = random.next() < 0.5 ? -1 : 1
  var raw: [(a: Double, d: Double)] = []
  for i in 0..<count {
    let a = count == 1
      ? side * (PawnMotion.soloMin + (PawnMotion.soloMax - PawnMotion.soloMin) * random.next())
      : (Double(i) - Double(count - 1) / 2) * PawnMotion.spreadDeg + (random.next() * 2 - 1) * fanJ + turn
    var d = 0.0
    var tries = 0
    repeat {
      d = (PawnMotion.refDistance + (random.next() * 2 - 1) * PawnMotion.distanceJitter) * dk
      tries += 1
    } while tries < 20 && raw.contains { abs($0.d - d) < PawnMotion.distanceGap * dk }
    raw.append((a, d))
  }
  // Where popping up would leave the screen, the fan pops down instead.
  if raw.contains(where: { origin.y - $0.d * cos($0.a * .pi / 180) < PawnMotion.edge }) {
    raw = raw.map { (a: 180 - $0.a, d: $0.d) }
  }
  // Near a screen edge the whole fan swings away from it.
  let fits = { (swing: Double) in
    raw.allSatisfy { p in
      let x = origin.x + p.d * sin((p.a + swing) * .pi / 180)
      return x >= PawnMotion.edge && x <= width - PawnMotion.edge
    }
  }
  var swing = 0.0
  var step = 1.0
  while step <= 90 && !fits(swing) {
    swing = fits(step) ? step : fits(-step) ? -step : swing
    step += 1
  }
  var trips: [(trip: PawnTrip, far: Double)] = raw.map { p in
    let a = p.a + swing
    let rad = a * .pi / 180
    let stop = CGPoint(x: min(width - PawnMotion.edge, max(PawnMotion.edge, origin.x + p.d * sin(rad))), y: origin.y - p.d * cos(rad))
    let dx = target.x - stop.x, dy = target.y - stop.y
    let len = max(1, (dx * dx + dy * dy).squareRoot())
    var normal = CGVector(dx: -dy / len, dy: dx / len)
    if normal.dx * (sin(rad) >= 0 ? 1 : -1) < 0 { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
    let trip = PawnTrip(drop: drop, angle: a, origin: origin, stop: stop, normal: normal, spawn: 0, leave: 0, arrive: 0, collect: 0, ghostStretch: 1, target: target)
    return (trip, len)
  }
  trips.sort { $0.far < $1.far }
  for rank in trips.indices {
    let f = min(1, max(0, (trips[rank].far - 80) / 240))
    let collect = PawnMotion.collectMinMs + (PawnMotion.collectMaxMs - PawnMotion.collectMinMs) * f
    let spawn = start + PawnMotion.spawnStaggerMs * Double(rank)
    let leave = max(spawn + PawnMotion.popMs, start + PawnMotion.popMs + PawnMotion.holdMs + PawnMotion.leaveStaggerMs * Double(rank))
    trips[rank].trip.spawn = spawn
    trips[rank].trip.leave = leave
    trips[rank].trip.collect = collect
    trips[rank].trip.arrive = leave + collect
    trips[rank].trip.ghostStretch = collect / (PawnMotion.refCollectMin + (PawnMotion.refCollectMax - PawnMotion.refCollectMin) * f)
  }
  return trips.map(\.trip)
}

/// The pawns in the air, with the wash and sparks where they came from.
private struct PawnFlightLayer: View {
  let spots: [String: CGRect]
  let orientation: ChessCore.Color
  @Environment(AppStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var trips: [PawnTrip] = []
  @State private var bursts: [(drop: Int, rect: CGRect, round: Bool, start: Double)] = []
  @State private var planned: Set<Int> = []
  @State private var landed: Set<String> = []
  @State private var epoch = Date()

  var body: some View {
    GeometryReader { geo in
      TimelineView(.animation(paused: trips.isEmpty && bursts.isEmpty)) { timeline in
        let t = timeline.date.timeIntervalSince(epoch) * 1000
        ZStack(alignment: .topLeading) {
          ForEach(Array(bursts.enumerated()), id: \.offset) { _, burst in
            Burst(rect: burst.rect, round: burst.round, t: t - burst.start)
          }
          ForEach(Array(trips.enumerated()), id: \.offset) { _, trip in
            FlyingCoin(trip: trip, t: t)
          }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        .onChange(of: Int(t / 16)) { settle(t) }
      }
      .onChange(of: store.pawnDrops.map(\.id), initial: true) { plan(width: geo.size.width) }
    }
  }

  /// New drops get their pawns planned; a drop with nowhere to fly lands at once.
  private func plan(width: Double) {
    let now = Date().timeIntervalSince(epoch) * 1000
    for drop in store.pawnDrops where !planned.contains(drop.id) {
      planned.insert(drop.id)
      guard !reduceMotion, let target = spots["counter"], let source = sourceRect(drop.award.source) else {
        for _ in 0..<drop.flying { store.landed(drop.id) }
        continue
      }
      let round = drop.award.source == .counter
      bursts.append((drop.id, source, !round && sourceIsSquare(drop.award.source), now))
      trips += planTrips(drop: drop.id, count: drop.flying, from: source, to: CGPoint(x: target.midX, y: target.midY), width: width, start: now)
    }
  }

  /// Pawns that have arrived count; finished effects go.
  private func settle(_ t: Double) {
    for (i, trip) in trips.enumerated() where t >= trip.arrive && !landed.contains("\(trip.drop)-\(i)") {
      landed.insert("\(trip.drop)-\(i)")
      store.landed(trip.drop)
    }
    if trips.allSatisfy({ t >= $0.arrive }) && !trips.isEmpty {
      trips = []
      landed = []
    }
    bursts.removeAll { t - $0.start > PawnMotion.washMs }
  }

  private func sourceIsSquare(_ source: PawnSource) -> Bool {
    if case .square = source { return true }
    return false
  }

  /// The rect pawns pop out of.
  private func sourceRect(_ source: PawnSource) -> CGRect? {
    switch source {
    case .square(let square):
      guard let board = spots["board"], square.count == 2 else { return nil }
      let chars = Array(square.unicodeScalars)
      let file = Double(Int(chars[0].value) - 97), rank = Double(Int(chars[1].value) - 49)
      let size = board.width / 8
      let col = orientation == .w ? file : 7 - file
      let row = orientation == .w ? 7 - rank : rank
      return CGRect(x: board.minX + col * size, y: board.minY + row * size, width: size, height: size)
    // Out of the Prep complete callout; the prep bar where no callout shows.
    case .prep: return spots["callout"] ?? spots["prep"] ?? spots["board"]
    case .goal: return spots["goal"] ?? spots["board"]
    case .board: return spots["board"].map { CGRect(x: $0.midX - 22, y: $0.midY - 22, width: 44, height: 44) }
    case .counter: return spots["counter"]
    }
  }
}

/// The yellow wash over what earned the pawns, and five spark dashes.
private struct Burst: View {
  let rect: CGRect
  let round: Bool
  let t: Double

  var body: some View {
    let u = t / PawnMotion.washMs
    if u >= 0, u < 1 {
      ZStack(alignment: .topLeading) {
        RoundedRectangle(cornerRadius: round ? 0 : 10).fill(Theme.pawn).opacity(0.45 * (1 - u))
          .frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
        let s = t / PawnMotion.sparkMs
        if s < 1 {
          ForEach(0..<5, id: \.self) { i in
            let a = (Double(i) * 72 + 18) * .pi / 180
            let r = 12 + 16 * (1 - pow(1 - s, 3))
            Capsule().fill(Theme.pawn).frame(width: 6, height: 1.5)
              .rotationEffect(.radians(a))
              .position(x: rect.midX + r * cos(a), y: rect.midY + r * sin(a))
              .opacity(1 - s * s)
          }
        }
      }
    }
  }
}

/// A flying pawn, upright, with its ghost trail on the way in.
private struct FlyingCoin: View {
  let trip: PawnTrip
  let t: Double

  var body: some View {
    if let now = trip.at(t) {
      ZStack {
        if t > trip.leave {
          ForEach(0..<3, id: \.self) { k in
            if let back = trip.at(max(trip.leave, t - PawnMotion.ghostLags[k] * trip.ghostStretch)) {
              let dx = back.point.x - now.point.x, dy = back.point.y - now.point.y
              let len = (dx * dx + dy * dy).squareRoot()
              let cap = PawnMotion.streak * Double(k + 1) / 3
              let f = len > cap ? cap / len : 1
              PawnCoin(stroked: false)
                .scaleEffect(now.scale * (1 - 0.14 * Double(k + 1)))
                .opacity(PawnMotion.ghostOpacity[k] * min(1, len / (5 * Double(k + 1))) * now.opacity)
                .position(x: now.point.x + dx * f, y: now.point.y + dy * f)
            }
          }
        }
        PawnCoin(stroked: true).scaleEffect(now.scale).opacity(now.opacity).position(now.point)
      }
    }
  }
}

/// The flying pawn: the board's pawn in yellow.
struct PawnCoin: View {
  var stroked: Bool
  var size = PawnMotion.size
  var fill = Theme.pawn

  static let shape = "M22.5 9c-2.21 0-4 1.79-4 4 0 .89.29 1.71.78 2.38C17.33 16.5 16 18.59 16 21c0 2.03.94 3.84 2.41 5.03-3 1.06-7.41 5.55-7.41 13.47h23c0-7.92-4.41-12.41-7.41-13.47 1.47-1.19 2.41-3 2.41-5.03 0-2.41-1.33-4.5-3.28-5.62.49-.67.78-1.49.78-2.38 0-2.21-1.79-4-4-4z"

  var body: some View {
    let path = SVGPath(d: Self.shape)
    ZStack {
      path.fill(fill)
      if stroked { path.stroke(Color(hex: 0x3a2a05), style: StrokeStyle(lineWidth: 2 * size / 45, lineJoin: .round)) }
    }
    .frame(width: size, height: size)
  }
}

/// The balance in a box: the pawn and the count. Each pawn landing brightens the pawn
/// and bumps pawn and count together; the box never moves.
struct PawnCounter: View {
  @Environment(AppStore.self) private var store
  @Environment(\.openShop) private var openShop
  @State private var landings = 0

  var body: some View {
    let count = store.shownPawns
    let content = HStack(spacing: 1) {
      PawnCoin(stroked: false, size: 21)
        .keyframeAnimator(initialValue: 0.0, trigger: landings) { coin, lit in
          coin.overlay { PawnCoin(stroked: false, size: 21, fill: Color(hex: 0xfde68a)).opacity(lit) }
        } keyframes: { _ in
          CubicKeyframe(1, duration: 0.001)
          LinearKeyframe(0, duration: 0.18)
        }
      Text("\(count)").font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
        .contentTransition(.numericText(value: Double(count)))
        .animation(.easeOut(duration: 0.09), value: count)
    }
    .keyframeAnimator(initialValue: 1.0, trigger: landings) { view, scale in view.scaleEffect(scale) } keyframes: { _ in
      CubicKeyframe(1.16, duration: 0.1)
      CubicKeyframe(1, duration: 0.1)
    }
    .padding(.horizontal, 8).frame(minWidth: 58, minHeight: 37)
    .background(RoundedRectangle(cornerRadius: 11).fill(Theme.surface2))
    .pawnSpot("counter")
    .onChange(of: count) { old, new in if new > old { landings += 1 } }
    .accessibilityElement()
    .accessibilityLabel("\(count) pawn\(count == 1 ? "" : "s")")
    if let openShop {
      Button { openShop("") } label: { content }.buttonStyle(.plain)
    } else {
      content
    }
  }
}
