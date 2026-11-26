import Engine
import SwiftUI

/// The open-source code the app ships, each with its license in full.
struct AcknowledgmentsView: View {
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      // The title and Close stay put while the rest scrolls.
      HStack {
        Text("Acknowledgments").font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
        Spacer()
        Button { dismiss() } label: {
          Icon(name: "close", size: 18).foregroundStyle(Theme.text).frame(width: 36, height: 36).background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
      }
      .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 4)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Acknowledgments.all) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
              Text(item.license).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.text3)
                .padding(.top, 8)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
            .padding(.top, 16)
          }
        }
        .padding(.horizontal, 20).padding(.bottom, 20)
      }
    }
  }
}
