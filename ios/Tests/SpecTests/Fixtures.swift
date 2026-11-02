import Book
import Foundation

/// The book the app ships, shared by every golden case.
let bookIndex: ReferenceIndex = {
  let url = Cases.book
  return try! decodeBook(Data(contentsOf: url))
}()

func line(_ text: String) -> [String] {
  text.isEmpty ? [] : text.split(separator: " ").map(String.init)
}
