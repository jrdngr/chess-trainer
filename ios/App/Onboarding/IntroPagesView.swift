import ChessCore
import Model
import SwiftUI

/// How the app works, in four pages: openings as flash cards, lenses, goals
/// and plans. Shown once to every profile before anything else, and again
/// from Settings. Skip and Get started both close it.
struct IntroPagesView: View {
  let onDone: () -> Void

  @State private var page = 0
  @State private var lens: LensKind?

  /// A Carlsbad, where every lens has something to show (...h6 puts the bishop on g5 at risk) and Plan has a plan.
  static let line = ["d4", "d5", "c4", "e6", "Nc3", "Nf6", "cxd5", "exd5", "Bg5", "c6", "e3", "Be7", "Bd3", "Nbd7", "Nf3", "h6"]
  private static let fen = walkSan(line).fens.last!
  private static let pages = 4

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        SkipButton(label: "Skip", action: onDone).opacity(page < Self.pages - 1 ? 1 : 0)
      }
      .padding(.horizontal, 8).frame(height: 44)
      TabView(selection: $page) {
        flashCards.tag(0)
        boardPage(marks: lens.map { heldLens($0, Self.fen, .w) }, plan: nil, title: "Lenses",
                  text: "Hold a lens button to get extra info about the board.") {
          EmptyView()
        }
        .tag(1)
        boardPage(marks: lens.map { heldLens($0, Self.fen, .w) }, plan: false, title: "Goals",
                  text: "Past your prep, you get a goal with a deadline.") {
          GoalCard(mission: Mission(kind: .convert)).padding(.top, 12)
        }
        .tag(2)
        boardPage(marks: lens.map { heldLens($0, Self.fen, .w) }, plan: true, title: "Plans",
                  text: "Hold Plan for the ideas behind the position.") {
          PlanLegend(fen: Self.fen, me: .w).padding(.top, 12)
        }
        .tag(3)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      OnboardBar {
        HStack(spacing: 6) {
          ForEach(0..<Self.pages, id: \.self) { i in
            Capsule().fill(i == page ? Theme.text : Theme.surface3).frame(width: i == page ? 16 : 6, height: 6)
          }
        }
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.2), value: page)
        BigButton(label: page < Self.pages - 1 ? "Next" : "Get started") {
          if page < Self.pages - 1 { withAnimation { page += 1 } } else { onDone() }
        }
      }
    }
    .background(Theme.background.ignoresSafeArea())
    .onChange(of: page) { lens = nil }
  }

  /// Page one: your openings are the cards.
  private var flashCards: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        card(["e4", "c5"], .b).rotationEffect(.degrees(-11)).offset(x: -78, y: 14).opacity(0.75)
        card(["d4", "d5", "c4", "e6"], .b).rotationEffect(.degrees(11)).offset(x: 78, y: 14).opacity(0.75)
        card(["e4", "e5", "Nf3", "Nc6", "Bc4"], .w)
          .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.accent, lineWidth: 1.5))
      }
      .frame(maxWidth: .infinity).frame(height: 190).padding(.top, 8)
      Text("Flash cards you play").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        .padding(.top, 24)
      VStack(alignment: .leading, spacing: 16) {
        point("\u{265F}\u{FE0E}", "Your openings are the cards.")
        point("\u{265A}", "Each one is a real game until you blunder.")
        point("\u{265E}", "Autoplays to the position you need to drill most.")
      }
      .padding(.top, 22)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 20)
  }

  private func card(_ sans: [String], _ color: ChessCore.Color) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      MiniBoard(sans: sans, orientation: color, size: 116, lastMove: true).clipShape(RoundedRectangle(cornerRadius: 6))
      Capsule().fill(Theme.surface3).frame(width: 80, height: 6)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    .shadow(color: .black.opacity(0.55), radius: 15, y: 14)
  }

  /// The pawn has an emoji form, so its glyph carries the text-style selector to take the accent like the others.
  private func point(_ glyph: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(glyph).font(.system(size: 21)).foregroundStyle(Theme.accent)
        .frame(width: 32, height: 32).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
      Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
    }
  }

  /// A page about the play screen: the board, its lenses right under it, what the page shows, and its two lines.
  private func boardPage<Extra: View>(
    marks: LensMarks?, plan: Bool?, title: String, text: String, @ViewBuilder extra: () -> Extra
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      BoardView(fen: Self.fen, orientation: .w, interactive: false, marks: marks) { _ in }
      LensBar(held: $lens, plan: plan.map { Binding.constant($0) }, planEnabled: plan != nil)
      extra()
      Text(title).font(.system(size: 26, weight: .heavy)).tracking(-0.8).foregroundStyle(Theme.text).padding(.top, 18)
      Text(text).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
  }
}
