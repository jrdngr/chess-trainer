import SwiftUI

/// The web app's small pieces this screen uses: `.section`, `.chip`, `.btn`,
/// `IconButton`, `Empty` and a sheet's head, from `styles.css` and `ui.tsx`.

/// A section's title, with something on the right: `.section`.
struct AnalysisSectionHead<Aside: View>: View {
  var title: String
  @ViewBuilder var aside: Aside

  var body: some View {
    HStack {
      Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
      Spacer()
      aside
    }
    .padding(.horizontal, 4).padding(.top, 24).padding(.bottom, 8)
  }
}

extension AnalysisSectionHead where Aside == EmptyView {
  init(title: String) { self.init(title: title) { EmptyView() } }
}

/// A pill: `.chip`, `.chip.on`, `.chip.w` and `.chip.b`.
struct AnalysisChip: View {
  enum Tone { case plain, on, white, black }
  var text: String
  var tone: Tone = .plain

  var body: some View {
    Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
      .foregroundStyle(colors.fg)
      .padding(.horizontal, 10).padding(.vertical, 4)
      .background(Capsule().fill(colors.bg))
  }

  private var colors: (fg: Color, bg: Color) {
    switch tone {
    case .plain: return (Theme.text2, Theme.surface2)
    case .on: return (Theme.accentInk, Theme.accent)
    case .white: return (Color(hex: 0x111111), Color(hex: 0xf2f2f4))
    case .black: return (Color(hex: 0xe8e8ee), Color(hex: 0x2a2a31))
    }
  }
}

/// A full-size button: `.btn` and its kinds.
struct WideButton: View {
  enum Kind { case plain, soft, primary, accent }
  var title: String
  var icon: String?
  var kind: Kind = .plain
  var disabled = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let icon { Icon(name: icon, size: 18) }
        Text(title).font(.system(size: 16, weight: .semibold)).multilineTextAlignment(.leading)
      }
      .foregroundStyle(colors.fg)
      .frame(maxWidth: .infinity, minHeight: 50).padding(.horizontal, 20)
      .background(RoundedRectangle(cornerRadius: 14).fill(colors.bg))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.35 : 1)
  }

  private var colors: (fg: Color, bg: Color) {
    switch kind {
    case .plain: return (Theme.text, Theme.surface2)
    case .soft: return (Theme.text, Theme.surface)
    case .primary: return (Color(hex: 0x0b0b0e), Theme.text)
    case .accent: return (Theme.accentInk, Theme.accent)
    }
  }
}

/// A round button in an app bar: `IconButton`.
struct AnalysisIconButton: View {
  var icon: String
  var label: String
  var size: CGFloat = 38
  var plain = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Icon(name: icon, size: 20).foregroundStyle(plain ? Theme.text2 : Theme.text)
        .frame(width: size, height: size)
        .background(Circle().fill(plain ? .clear : Theme.surface))
    }
    .buttonStyle(.plain).accessibilityLabel(label)
  }
}

/// Nothing to show, said quietly: `Empty`.
struct AnalysisEmpty: View {
  var title: String
  var hint: String?

  var body: some View {
    VStack(spacing: 4) {
      Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text2)
      if let hint { Text(hint).font(.system(size: 14)).foregroundStyle(Theme.text3) }
    }
    .frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 20)
  }
}

/// A bottom sheet's frame: title, close, and its body scrolling under them.
struct SheetFrame<Content: View>: View {
  var title: String
  var detents: Set<PresentationDetent> = [.large]
  var onClose: () -> Void
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.text).lineLimit(1)
        Spacer()
        AnalysisIconButton(icon: "close", label: "Close", action: onClose)
      }
      .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) { content }.padding(.horizontal, 16).padding(.bottom, 16)
      }
    }
    .presentationBackground(Color(hex: 0x141418))
    .presentationDetents(detents)
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(24)
  }
}

/// A card inside a sheet: `.sheet .card`.
struct SheetCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 0) { content }
      .frame(maxWidth: .infinity, alignment: .leading).padding(16)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface2))
  }
}

/// Move text as the web sets it: `.movetext`.
struct MoveText: View {
  var text: String

  var body: some View {
    Text(text).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text2).lineSpacing(6)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
