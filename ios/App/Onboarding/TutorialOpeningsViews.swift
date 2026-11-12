import Book
import ChessCore
import Game
import Model
import SwiftUI

/// The second screen: the openings the tutorial plays. Recommend some
/// openings starts the tutorial on a set we pick; Choose my own fills three
/// slots first; Skip leaves the tutorial out and goes to adding openings.
struct OpeningChoiceView: View {
  let onRecommend: () -> Void
  let onChoose: () -> Void
  let onSkip: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Your openings").font(.system(size: 30, weight: .heavy)).tracking(-0.9).foregroundStyle(Theme.text)
        .padding(.top, 40)
      VStack(spacing: 12) {
        choice("Recommend some openings", "star", accent: true, action: onRecommend)
        choice("Choose my own", "tree", accent: false, action: onChoose)
      }
      .padding(.top, 28)
      Spacer(minLength: 0)
      SkipButton(label: "Skip", action: onSkip).frame(maxWidth: .infinity).padding(.bottom, 8)
    }
    .padding(.horizontal, 20)
    .background(Theme.background.ignoresSafeArea())
  }

  private func choice(_ title: String, _ icon: String, accent: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Icon(name: icon, size: 22).foregroundStyle(accent ? Theme.accentInk : Theme.accent)
          .frame(width: 44, height: 44)
          .background(RoundedRectangle(cornerRadius: 12).fill(accent ? Theme.accent : Theme.accent.opacity(0.16)))
        Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.text)
        Spacer(minLength: 0)
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(16).frame(maxWidth: .infinity, minHeight: 76)
      .background(RoundedRectangle(cornerRadius: 22).fill(Theme.surface))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// Choose my own: three rows, White, Against 1.e4 and Against 1.d4, each
/// opening a sheet of six openings and More openings. Continue once all three are filled.
struct ChooseOpeningsView: View {
  let onBack: () -> Void
  let onContinue: (TutorialOpenings) -> Void

  @Environment(AppStore.self) private var store
  @Environment(Toasts.self) private var toasts
  @State private var chosen: [TutorialSlot: TutorialOpening] = [:]
  @State private var sheet: TutorialSlot?
  @State private var browsing: TutorialSlot?

  var body: some View {
    VStack(spacing: 0) {
      OnbAppBar(title: "Choose my own", onBack: onBack)
      ScrollView {
        VStack(spacing: 0) {
          ForEach(TutorialSlot.allCases, id: \.self) { slot in row(slot) }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        .padding(.horizontal, 16).padding(.top, 12)
      }
      OnboardBar {
        BigButton(label: "Continue", disabled: chosen.count < TutorialSlot.allCases.count) {
          guard let white = chosen[.white], let e4 = chosen[.e4], let d4 = chosen[.d4] else { return }
          onContinue(TutorialOpenings(white: white, e4: e4, d4: d4))
        }
      }
    }
    .background(Theme.background.ignoresSafeArea())
    .sheet(item: $sheet) { slot in
      SlotSheet(slot: slot, chosen: chosen[slot], onPick: { opening in
        chosen[slot] = opening
        sheet = nil
      }, onMore: {
        sheet = nil
        browsing = slot
      })
      .presentationDetents([.large])
      .presentationBackground(Theme.background)
    }
    .fullScreenCover(item: $browsing) { slot in
      BrowsePicker(onClose: { browsing = nil }, onChoose: { sans, _ in pick(slot, sans) })
        .background(Theme.background)
    }
  }

  private func row(_ slot: TutorialSlot) -> some View {
    Button { sheet = slot } label: {
      HStack(spacing: 12) {
        SideSquare(color: slot.color)
        VStack(alignment: .leading, spacing: 2) {
          Text(slot.label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text2)
          Text(chosen[slot]?.name ?? "Pick an opening").font(.system(size: 16, weight: .bold))
            .foregroundStyle(chosen[slot] == nil ? Theme.text3 : Theme.text).lineLimit(1)
        }
        Spacer()
        Icon(name: "chevron", size: 18).foregroundStyle(Theme.text3)
      }
      .padding(.horizontal, 16).frame(minHeight: 66).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  /// A line from the full browser: it must fit the slot.
  private func pick(_ slot: TutorialSlot, _ sans: [String]) {
    guard slot.fits(sans) else {
      toasts.show(slot == .white ? "Pick a line with a move in it." : "Pick a line that starts with 1.\(slot.rawValue).")
      return
    }
    let name = store.index.flatMap { openingNameForPath($0, sans)?.name } ?? moveText(sans)
    chosen[slot] = TutorialOpening(name: name, sans: sans)
  }
}

/// One slot's six openings, and More openings for the full browser.
private struct SlotSheet: View {
  let slot: TutorialSlot
  let chosen: TutorialOpening?
  let onPick: (TutorialOpening) -> Void
  let onMore: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Text(slot.label).font(.system(size: 22, weight: .heavy)).foregroundStyle(Theme.text)
        VStack(spacing: 0) {
          ForEach(CURATED_OPENINGS[slot] ?? [], id: \.name) { opening in
            Button { onPick(opening) } label: {
              HStack(spacing: 12) {
                MiniBoard(sans: opening.sans, orientation: slot.color, size: 52, lastMove: true)
                  .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                  Text(opening.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                  Text(moveText(opening.sans)).font(.system(size: 12.5)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer()
                if chosen == opening { Icon(name: "check", size: 18).foregroundStyle(Theme.accent) }
              }
              .padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
        Button(action: onMore) {
          HStack {
            Text("More openings").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Icon(name: "chevron", size: 16).foregroundStyle(Theme.text3)
          }
          .padding(.horizontal, 14).frame(height: 48).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
        }
        .buttonStyle(.plain)
      }
      .padding(20)
    }
  }
}
