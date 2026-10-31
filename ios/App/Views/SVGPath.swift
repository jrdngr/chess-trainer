import SwiftUI

/// A minimal SVG path reader: the commands the piece shapes use (M L H V C S Q A Z, and their relative forms).
struct SVGPath: Shape {
  let d: String

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 45
    return Self.parse(d).applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: rect.minX / scale, y: rect.minY / scale))
  }

  nonisolated(unsafe) private static var cache: [String: Path] = [:]

  static func parse(_ d: String) -> Path {
    if let cached = cache[d] { return cached }
    var tokens: [String] = []
    var current = ""
    for ch in d {
      if ch.isLetter {
        if !current.isEmpty { tokens.append(current) }
        tokens.append(String(ch))
        current = ""
      } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") {
        tokens.append(current)
        current = "-"
      } else if ch == "," || ch == " " {
        if !current.isEmpty { tokens.append(current) }
        current = ""
      } else if ch == "." && current.contains(".") {
        tokens.append(current)
        current = "."
      } else {
        current.append(ch)
      }
    }
    if !current.isEmpty { tokens.append(current) }

    var path = Path()
    var i = 0
    var cmd: Character = "M"
    var pt = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint?
    func num() -> CGFloat {
      defer { i += 1 }
      return CGFloat(Double(tokens[i]) ?? 0)
    }
    while i < tokens.count {
      if let c = tokens[i].first, c.isLetter, tokens[i].count == 1 {
        cmd = c
        i += 1
        if cmd == "z" || cmd == "Z" {
          path.closeSubpath()
          pt = start
          lastCtrl = nil
          continue
        }
      }
      let rel = cmd.isLowercase
      let base = rel ? pt : .zero
      switch cmd.uppercased() {
      case "M":
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        path.move(to: pt)
        start = pt
        cmd = rel ? "l" : "L"
        lastCtrl = nil
      case "L":
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        path.addLine(to: pt)
        lastCtrl = nil
      case "H":
        pt.x = (rel ? pt.x : 0) + num()
        path.addLine(to: pt)
        lastCtrl = nil
      case "V":
        pt.y = (rel ? pt.y : 0) + num()
        path.addLine(to: pt)
        lastCtrl = nil
      case "C":
        let c1 = CGPoint(x: base.x + num(), y: base.y + num())
        let c2 = CGPoint(x: base.x + num(), y: base.y + num())
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        path.addCurve(to: pt, control1: c1, control2: c2)
        lastCtrl = c2
      case "S":
        let c1 = lastCtrl.map { CGPoint(x: 2 * pt.x - $0.x, y: 2 * pt.y - $0.y) } ?? pt
        let c2 = CGPoint(x: base.x + num(), y: base.y + num())
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        path.addCurve(to: pt, control1: c1, control2: c2)
        lastCtrl = c2
      case "Q":
        let c = CGPoint(x: base.x + num(), y: base.y + num())
        pt = CGPoint(x: base.x + num(), y: base.y + num())
        path.addQuadCurve(to: pt, control: c)
        lastCtrl = nil
      case "A":
        let rx = num(), ry = num(), rotation = num(), large = num() != 0, sweep = num() != 0
        let to = CGPoint(x: base.x + num(), y: base.y + num())
        arc(&path, from: pt, to: to, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
        pt = to
        lastCtrl = nil
      default:
        i += 1
      }
    }
    cache[d] = path
    return path
  }

  /// An SVG endpoint arc, as cubic curves through its center parameterisation.
  private static func arc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
    var rx = abs(rxIn), ry = abs(ryIn)
    if rx == 0 || ry == 0 { path.addLine(to: p1); return }
    let phi = rotation * .pi / 180
    let cosP = cos(phi), sinP = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
    let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
    let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var coef = sqrt(max(0, num / den))
    if large == sweep { coef = -coef }
    let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
    let cx = cosP * cx1 - sinP * cy1 + (p0.x + p1.x) / 2
    let cy = sinP * cx1 + cosP * cy1 + (p0.y + p1.y) / 2
    func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
      let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
      return a
    }
    let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep && delta > 0 { delta -= 2 * .pi } else if sweep && delta < 0 { delta += 2 * .pi }
    let segments = Int(ceil(abs(delta) / (.pi / 2)))
    let step = delta / CGFloat(segments)
    let k = 4.0 / 3.0 * tan(step / 4)
    var t = theta1
    for _ in 0..<segments {
      let t2 = t + step
      func point(_ a: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * cos(a) * cosP - ry * sin(a) * sinP, y: cy + rx * cos(a) * sinP + ry * sin(a) * cosP)
      }
      func deriv(_ a: CGFloat) -> CGPoint {
        CGPoint(x: -rx * sin(a) * cosP - ry * cos(a) * sinP, y: -rx * sin(a) * sinP + ry * cos(a) * cosP)
      }
      let a = point(t), b = point(t2), da = deriv(t), db = deriv(t2)
      path.addCurve(to: b, control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y), control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
      t = t2
    }
  }
}
