import Foundation
import Model
import Testing

/// Golden/cases/functions/srs.json
@Test func srs() throws {
  let start = 1_790_845_200_000.0  // 2026-10-01T09:00:00Z
  func schedule(_ grades: [Grade]) -> [Card] {
    var card = createCard("rep_w#key", "rep_w", "key", "fen", start)
    var round = 0
    var out: [Card] = []
    for grade in grades {
      card = review(card, grade, round: round, now: start)
      out.append(card)
      round += Int(runGap(card))
    }
    return out
  }
  func grade(_ j: JSON) -> Grade { Grade(rawValue: j.string)! }
  func base() -> Card { createCard("id", "rep", "key", "fen", start) }

  try check("srs", [
    "srs.gradeForTime": { gradeForTime($0[0].number).rawValue.json },
    "srs.createCard": { a in encoded(createCard(a[0].string, a[1].string, a[2].string, a[3].string, a[4].number)) },
    "srs.review (one grade)": { a in encoded(review(base(), grade(a[0]), round: 0, now: start)) },
    "srs.review (schedule)": { a in .array(schedule(a[0].array.map(grade)).map(encoded)) },
    "srs.runGap": { a in
      var card = base()
      card.interval = a[0].number
      card.stage = CardStage(rawValue: a[1].string)!
      return runGap(card).json
    },
  ])
}
