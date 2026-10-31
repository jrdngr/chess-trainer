import Book
import Foundation

/// The prototype's book, pinned for every parity case.
let bookIndex: ReferenceIndex = {
  let url = Cases.root.appendingPathComponent("prototype/src/model/book/book.json")
  return try! decodeBook(Data(contentsOf: url))
}()

func line(_ text: String) -> [String] {
  text.isEmpty ? [] : text.split(separator: " ").map(String.init)
}
