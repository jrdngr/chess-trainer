import Book
import Foundation
import Model
import Observation

/// The app's state and the book, kept on the main actor and saved as JSON.
@MainActor @Observable
final class AppStore {
  private(set) var index: ReferenceIndex?
  private(set) var tree: OpeningTree?
  var state = AppState()
  /// The favorite the last round landed on, so the next one is another.
  var lastFavorite: String?

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

  /// Change the state and save it.
  func update(_ change: (inout AppState) -> Void) {
    change(&state)
    save()
  }
}
