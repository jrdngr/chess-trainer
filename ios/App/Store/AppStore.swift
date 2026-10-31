import Book
import Foundation
import Model
import Observation

/// The app's state and the book, kept on the main actor and saved as JSON.
@MainActor @Observable
final class AppStore {
  private(set) var index: ReferenceIndex?
  private(set) var tree: OpeningTree?
  /// The opening picker's catalogue, built once from the tree.
  private(set) var catalog: PickerCatalog?
  var state = AppState()
  /// The favorite the last round landed on, so the next one is another.
  var lastFavorite: String?
  /// Any favorite resolved ahead of time, so Home's button and the round it starts agree.
  @ObservationIgnored private var ahead: (key: String, selection: Selection)?

  private let file = URL.applicationSupportDirectory.appending(path: "playbook.json")

  /// Load the book (and build the opening tree) off the main actor, then the saved state.
  func load() async {
    guard index == nil else { return }
    let built = await Task.detached(priority: .userInitiated) { () -> (ReferenceIndex, OpeningTree)? in
      guard let url = Bundle.main.url(forResource: "book", withExtension: "json"),
        let data = try? Data(contentsOf: url), let index = try? decodeBook(data)
      else { return nil }
      return (index, openingTree(index))
    }.value
    if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(AppState.self, from: data) {
      state = saved
    }
    if let built {
      index = built.0
      tree = built.1
      catalog = pickerCatalog(built.1)
    }
  }

  func save() {
    do {
      try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try JSONEncoder().encode(state).write(to: file, options: .atomic)
    } catch {
      print("save failed: \(error)")
    }
  }

  /// The next round's selection, without taking it: `peekRoundSelection`.
  func peekRoundSelection() -> Selection {
    let selection = state.settings.selection
    guard isAnyFavorite(selection), let tree else { return selection }
    let key = "\(selection.color.rawValue) \(state.settings.favoriteOpenings.joined(separator: ",")) \(lastFavorite ?? "")"
    if ahead?.key != key { ahead = (key, roundSelection(state, tree, last: lastFavorite, Env.random)) }
    return ahead!.selection
  }

  /// The next round's selection, taken: the one after lands on another favorite.
  func takeRoundSelection() -> Selection {
    let taken = peekRoundSelection()
    if isAnyFavorite(state.settings.selection) {
      if !taken.opening.isEmpty { lastFavorite = taken.opening }
      ahead = nil
    }
    return taken
  }

  /// Change the state and save it.
  func update(_ change: (inout AppState) -> Void) {
    change(&state)
    save()
  }
}
