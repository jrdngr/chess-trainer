import SwiftUI

/// The web app's line icons on a 24-unit grid: `Icons.tsx`. `filled` is the
/// solid form some icons take when selected.
struct Icon: View {
  var name: String
  var size: CGFloat = 22
  var filled = false

  var body: some View {
    let spec = Self.specs[name] ?? IconSpec(strokeWidth: 2, parts: [])
    Canvas { context, canvas in
      let k = canvas.width / 24
      context.scaleBy(x: k, y: k)
      let ink = GraphicsContext.Shading.foreground
      let bg = GraphicsContext.Shading.color(Theme.background)
      for part in spec.parts {
        let path = part.shape.path
        var layer = context
        layer.opacity = filled ? part.opacity.filled : part.opacity.plain
        switch part.fill {
        case .current: layer.fill(path, with: ink)
        case .whenFilled: if filled { layer.fill(path, with: ink) }
        case .bgWhenFilled: if filled { layer.fill(path, with: bg) }
        case .none: break
        }
        let style = StrokeStyle(lineWidth: spec.strokeWidth, lineCap: .round, lineJoin: .round)
        switch part.stroke {
        case .current: layer.stroke(path, with: ink, style: style)
        case .bgWhenFilled: layer.stroke(path, with: filled ? bg : ink, style: style)
        case .none, .whenFilled: break
        }
      }
    }
    .frame(width: size, height: size)
  }
}

struct IconSpec {
  var strokeWidth: CGFloat
  var parts: [IconPart]
}

struct IconPart {
  enum Shape {
    case path(String)
    case circle(CGFloat, CGFloat, CGFloat)
    case rect(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)

    var path: Path {
      switch self {
      case .path(let d): return SVGPath.parse(d)
      case .circle(let x, let y, let r): return Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
      case .rect(let x, let y, let w, let h, let rx): return Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: rx)
      }
    }
  }
  enum Paint { case none, current, whenFilled, bgWhenFilled }

  var shape: Shape
  var fill: Paint
  var stroke: Paint
  /// Plain, and when filled.
  var opacity: (plain: Double, filled: Double)

  init(_ shape: Shape, fill: Paint, stroke: Paint, opacity: (Double, Double)) {
    self.shape = shape
    self.fill = fill
    self.stroke = stroke
    self.opacity = (opacity.0, opacity.1)
  }
}
