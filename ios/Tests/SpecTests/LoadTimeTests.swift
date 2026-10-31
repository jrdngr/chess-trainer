import Book
import Foundation
import Model
import Testing

/// What launch spends on the book: decoding it and building the opening tree.
/// About 0.2s each in a release build; a regression here is a slow launch.
@Test func bookLoadTime() throws {
  let data = try Data(contentsOf: Cases.root.appendingPathComponent("prototype/src/model/book/book.json"))
  let started = Date()
  let index = try decodeBook(data)
  let decoded = Date()
  _ = openingTree(index)
  print("book decode \(Int(decoded.timeIntervalSince(started) * 1000))ms, tree \(Int(Date().timeIntervalSince(decoded) * 1000))ms")
}
