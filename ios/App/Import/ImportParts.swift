import Model
import SwiftUI

/// A text input: `.field`. `raised` is the sheet's lighter surface.
struct FieldInput: View {
  var placeholder: String
  @Binding var text: String
  var raised = false

  var body: some View {
    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Theme.text3))
      .textInputAutocapitalization(.never).autocorrectionDisabled()
      .font(.system(size: 16)).foregroundStyle(Theme.text).tint(Theme.accent)
      .padding(.horizontal, 16).padding(.vertical, 14)
      .background(RoundedRectangle(cornerRadius: 12).fill(raised ? Theme.surface2 : Theme.surface))
  }
}

/// A long text input: `textarea.field`.
struct FieldArea: View {
  var placeholder: String
  @Binding var text: String

  var body: some View {
    ZStack(alignment: .topLeading) {
      TextEditor(text: $text).scrollContentBackground(.hidden)
        .font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text).tint(Theme.accent)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .padding(.horizontal, 11).padding(.vertical, 6)
      if text.isEmpty {
        Text(placeholder).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text3)
          .padding(.horizontal, 16).padding(.vertical, 14).allowsHitTesting(false)
      }
    }
    .frame(minHeight: 200)
    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
  }
}

/// Something went wrong, and what to do: `.banner.bad`.
struct BadBanner: View {
  var title: String
  var sub: String

  var body: some View {
    HStack(spacing: 12) {
      Icon(name: "warn", size: 20).foregroundStyle(Theme.bad)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
        Text(sub).font(.system(size: 13)).foregroundStyle(Theme.text2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 14).padding(.vertical, 12)
    .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bad.opacity(0.14)))
  }
}

/// A row of a list that opens something: `.list-row` with a chevron.
struct ChevronRow: View {
  var title: String
  var meta: String?
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
          if let meta { Text(meta).font(.system(size: 12.5)).foregroundStyle(Theme.text3) }
        }
        Spacer()
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text)
      }
      .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 54).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Three numbers in a row: `.stat-grid`.
struct StatGrid: View {
  var stats: [(n: String, label: String)]

  var body: some View {
    HStack(spacing: 8) {
      ForEach(stats, id: \.label) { stat in
        VStack(spacing: 2) {
          Text(stat.n).font(.system(size: 24, weight: .heavy)).monospacedDigit().tracking(-0.5).foregroundStyle(Theme.text)
          Text(stat.label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
      }
    }
  }
}

/// A label and its value: `.list-row.kv`.
struct KVRow: View {
  var key: String
  var value: String
  var tint = Theme.text

  var body: some View {
    HStack(spacing: 12) {
      Text(key).font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize()
      Spacer(minLength: 0)
      Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(tint)
        .lineLimit(1).minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 44)
  }
}

/// "3W 1D 2L".
func scoreText(_ r: GameResults) -> String { "\(r.wins)W \(r.draws)D \(r.losses)L" }

/// One gap or deviation: the line, how often, what you played and what the Playbook says.
struct FindingCard: View {
  var finding: Finding
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          Text(finding.lineText).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.text2)
            .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
          Chip(text: "\(finding.games)×")
        }
        HStack(spacing: 6) {
          ForEach(finding.played.prefix(3), id: \.san) { p in
            Chip(text: "\(p.san) ×\(p.count)", tone: finding.kind == .deviation ? .bad : .plain)
          }
          if !finding.expected.isEmpty { Chip(text: finding.expected.joined(separator: ", "), tone: .good) }
          Spacer(minLength: 0)
          Text(scoreText(finding.results)).font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.text3)
        }
      }
      .padding(16).frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

extension View {
  /// Dimmed and untappable, as the web's `.btn:disabled` (one layer at 0.35, not the label dimmed twice).
  func unavailable(_ off: Bool) -> some View {
    compositingGroup().opacity(off ? 0.35 : 1).allowsHitTesting(!off)
  }
}
