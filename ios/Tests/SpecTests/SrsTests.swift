import Foundation
import Model
import Testing

/// spec/cases/functions/srs.json
@Test func srs() throws {
  let start = 1_790_845_200_000.0  // 2026-10-01T09:00:00Z
  func schedule(_ grades: [Grade]) -> [Card] {
    var card = createCard("rep_w#key", "rep_w", "key", "fen", start)
    var now = start
    var out: [Card] = []
    for grade in grades {
      card = review(card, grade, now).card
      out.append(card)
      now = max(now, card.due)
    }
    return out
  }
  func grade(_ j: JSON) -> Grade { Grade(rawValue: j.string)! }
  func base() -> Card { createCard("id", "rep", "key", "fen", start) }

  try check("srs", [
    "srs.gradeForTime": { gradeForTime($0[0].number).rawValue.json },
    "srs.gradeForLine": { gradeForLine($0[0].numbers, $0[1].int).rawValue.json },
    "srs.createCard": { a in encoded(createCard(a[0].string, a[1].string, a[2].string, a[3].string, a[4].number)) },
    "srs.createLineCard": { a in encoded(createLineCard(a[0].string, a[1].string, a[2].number)) },
    "srs.review (one grade)": { a in
      let outcome = review(base(), grade(a[0]), start)
      return obj(["card": encoded(outcome.card), "delay": outcome.delay])
    },
    "srs.review (schedule)": { a in .array(schedule(a[0].array.map(grade)).map(encoded)) },
    "srs.isDue": { a in
      var card = base()
      card.due = start
      return isDue(card, start + a[0].number).json
    },
    "srs.runGap": { a in
      var card = base()
      card.interval = a[0].number
      card.stage = CardStage(rawValue: a[1].string)!
      return runGap(card).json
    },
    "srs.describeDelay": { describeDelay($0[0].number).json },
  ])
}
