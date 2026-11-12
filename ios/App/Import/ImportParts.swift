import Game
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

