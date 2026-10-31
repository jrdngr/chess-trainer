import Foundation

/// Kin: openings that share their moves. `src/model/kin.ts`.
///
/// A habit is a move you keep choosing, and the arrows count habits inside one
/// opening. But the book's families are narrower than the ideas in them: the
/// Catalan's g3 and Bg2 are the English's and the Réti's. Which openings share
/// which ideas is chess knowledge, so it is written down here. The sets overlap
/// on purpose. An opening in no set counts only itself.
///
/// Names are the book's family names (see `familyName`), spelled as the book
/// spells them.
public struct KinSet: Equatable, Sendable {
  public var name: String
  public var families: [String]
}

public let KIN_SETS: [KinSet] = [
  KinSet(name: "Queen's Gambit", families: [
    "Queen's Gambit", "Queen's Gambit Declined", "Queen's Gambit Accepted", "Slav Defence", "Semi-Slav Defence",
    "Semi-Slav Defence Accepted", "Tarrasch Defence", "Catalan Opening", "Indian Defence", "Queen's Pawn Game",
  ]),
  KinSet(name: "...e6 Indians", families: [
    "Nimzo-Indian Defence", "Queen's Indian Defence", "Queen's Indian Accelerated", "Pseudo Queen's Indian Defence",
    "Bogo-Indian Defence", "Queen's Gambit Declined", "Catalan Opening", "Indian Defence",
  ]),
  KinSet(name: "...c6 and ...d5", families: [
    "Slav Defence", "Semi-Slav Defence", "Semi-Slav Defence Accepted", "Slav Indian", "Caro-Kann Defence",
  ]),
  KinSet(name: "Kingside fianchetto for White", families: [
    "Catalan Opening", "English Opening", "Réti Opening", "King's Indian Attack", "King's Indian Attack, with e6",
    "King's Indian Attack, with Bf5", "Zukertort Opening", "Hungarian Opening", "Neo-Grünfeld Defence", "Indian Defence",
  ]),
  KinSet(name: "Kingside fianchetto for Black", families: [
    "King's Indian Defence", "Grünfeld Defence", "Neo-Grünfeld Defence", "Modern Defence", "Pirc Defence",
    "Pterodactyl Defence", "East Indian Defence", "Old Indian Defence", "Benoni Defence", "Benko Gambit",
    "Benko Gambit Accepted", "Benko Gambit Declined", "English Opening", "Indian Defence",
  ]),
  KinSet(name: "...c5", families: [
    "Sicilian Defence", "English Opening", "Benoni Defence", "Benko Gambit", "Benko Gambit Accepted",
  ]),
  KinSet(name: "Queenside fianchetto", families: [
    "Nimzo-Larsen Attack", "Zukertort Opening", "English Opening", "Queen's Indian Defence", "Owen Defence",
    "English Defence", "Polish Opening", "Polish Defence",
  ]),
  KinSet(name: "Stonewall and Dutch", families: ["Dutch Defence", "Bird Opening", "Zukertort Opening"]),
  KinSet(name: "d4 systems", families: [
    "London System", "Queen's Pawn Game", "Indian Defence", "Torre Attack", "Trompowsky Attack",
    "Richter-Veresov Attack", "Rapport-Jobava System", "Rapport-Jobava System, with e6", "Zukertort Opening",
  ]),
  KinSet(name: "1.e4 e5", families: [
    "Italian Game", "Ruy Lopez", "Scotch Game", "Four Knights Game", "Three Knights Opening", "Petrov's Defence",
    "Philidor Defence", "Vienna Game", "Bishop's Opening", "King's Knight Opening", "King's Pawn Game",
    "Ponziani Opening", "Center Game", "King's Gambit", "King's Gambit Accepted", "King's Gambit Declined",
    "Danish Gambit", "Elephant Gambit", "Latvian Gambit", "Latvian Gambit Accepted",
  ]),
  KinSet(name: "French and Caro-Kann", families: ["French Defence", "Caro-Kann Defence"]),
  KinSet(name: "Pirc and Modern", families: [
    "Pirc Defence", "Modern Defence", "Rat Defence", "Lion Defence", "Philidor Defence",
  ]),
]

/// The families a habit may come from for an opening: itself and every set it is in.
public func kinOf(_ family: String) -> Set<String> {
  var out: Set<String> = [family]
  for set in KIN_SETS where set.families.contains(family) { out.formUnion(set.families) }
  return out
}

/// A family as it reads in a sentence: "Réti" for "Réti Opening".
public func shortFamily(_ family: String) -> String {
  family
    .replacing(#/ (Opening|Defence|Game)$/#, with: "", maxReplacements: 1)
    .replacing(#/ (Opening|Defence|Game),/#, with: ",", maxReplacements: 1)
}
