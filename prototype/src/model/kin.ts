/**
 * Kin: openings that share their moves.
 *
 * A habit is a move you keep choosing, and the arrows count habits inside
 * one opening. But the book's families are narrower than the ideas in them:
 * the Catalan's g3 and Bg2 are the English's and the Réti's, the Slav's
 * ...c6, ...d5 and ...Bf5 are the Caro-Kann's. Counted family by family, a
 * new opening starts with no habits at all even when every move of it is one
 * you already play.
 *
 * Which openings share which ideas is chess knowledge rather than something to
 * compute, so it is written down here. The sets overlap on purpose: the
 * Catalan is kin to the English for its fianchetto and to the Queen's Gambit
 * Declined for its centre. A habit counts if it shows up anywhere in any set
 * the opening belongs to. An opening in no set counts only itself.
 *
 * Names are the book's family names (see `familyName`), spelled as the book
 * spells them.
 */
export const KIN_SETS: { name: string; families: string[] }[] = [
  {
    name: "Queen's Gambit",
    families: [
      "Queen's Gambit",
      "Queen's Gambit Declined",
      "Queen's Gambit Accepted",
      'Slav Defence',
      'Semi-Slav Defence',
      'Semi-Slav Defence Accepted',
      'Tarrasch Defence',
      'Catalan Opening',
      'Indian Defence',
      "Queen's Pawn Game",
    ],
  },
  {
    name: '...e6 Indians',
    families: [
      'Nimzo-Indian Defence',
      "Queen's Indian Defence",
      "Queen's Indian Accelerated",
      "Pseudo Queen's Indian Defence",
      'Bogo-Indian Defence',
      "Queen's Gambit Declined",
      'Catalan Opening',
      'Indian Defence',
    ],
  },
  {
    name: '...c6 and ...d5',
    families: ['Slav Defence', 'Semi-Slav Defence', 'Semi-Slav Defence Accepted', 'Slav Indian', 'Caro-Kann Defence'],
  },
  {
    name: 'Kingside fianchetto for White',
    families: [
      'Catalan Opening',
      'English Opening',
      'Réti Opening',
      "King's Indian Attack",
      "King's Indian Attack, with e6",
      "King's Indian Attack, with Bf5",
      'Zukertort Opening',
      'Hungarian Opening',
      'Neo-Grünfeld Defence',
      'Indian Defence',
    ],
  },
  {
    name: 'Kingside fianchetto for Black',
    families: [
      "King's Indian Defence",
      'Grünfeld Defence',
      'Neo-Grünfeld Defence',
      'Modern Defence',
      'Pirc Defence',
      'Pterodactyl Defence',
      'East Indian Defence',
      'Old Indian Defence',
      'Benoni Defence',
      'Benko Gambit',
      'Benko Gambit Accepted',
      'Benko Gambit Declined',
      'English Opening',
      'Indian Defence',
    ],
  },
  {
    name: '...c5',
    families: ['Sicilian Defence', 'English Opening', 'Benoni Defence', 'Benko Gambit', 'Benko Gambit Accepted'],
  },
  {
    name: 'Queenside fianchetto',
    families: [
      'Nimzo-Larsen Attack',
      'Zukertort Opening',
      'English Opening',
      "Queen's Indian Defence",
      'Owen Defence',
      'English Defence',
      'Polish Opening',
      'Polish Defence',
    ],
  },
  {
    name: 'Stonewall and Dutch',
    families: ['Dutch Defence', 'Bird Opening', 'Zukertort Opening'],
  },
  {
    name: 'd4 systems',
    families: [
      'London System',
      "Queen's Pawn Game",
      'Indian Defence',
      'Torre Attack',
      'Trompowsky Attack',
      'Richter-Veresov Attack',
      'Rapport-Jobava System',
      'Rapport-Jobava System, with e6',
      'Zukertort Opening',
    ],
  },
  {
    name: '1.e4 e5',
    families: [
      'Italian Game',
      'Ruy Lopez',
      'Scotch Game',
      'Four Knights Game',
      'Three Knights Opening',
      "Petrov's Defence",
      'Philidor Defence',
      'Vienna Game',
      "Bishop's Opening",
      "King's Knight Opening",
      "King's Pawn Game",
      'Ponziani Opening',
      'Center Game',
      "King's Gambit",
      "King's Gambit Accepted",
      "King's Gambit Declined",
      'Danish Gambit',
      'Elephant Gambit',
      'Latvian Gambit',
      'Latvian Gambit Accepted',
    ],
  },
  {
    name: 'French and Caro-Kann',
    families: ['French Defence', 'Caro-Kann Defence'],
  },
  {
    name: 'Pirc and Modern',
    families: ['Pirc Defence', 'Modern Defence', 'Rat Defence', 'Lion Defence', 'Philidor Defence'],
  },
];

const kinCache = new Map<string, Set<string>>();

/** The families a habit may come from for an opening: itself and every set it is in. */
export function kinOf(family: string): Set<string> {
  const cached = kinCache.get(family);
  if (cached) return cached;
  const out = new Set<string>([family]);
  for (const set of KIN_SETS) {
    if (set.families.includes(family)) for (const other of set.families) out.add(other);
  }
  kinCache.set(family, out);
  return out;
}

/** A family as it reads in a sentence: "Réti" for "Réti Opening". */
export function shortFamily(family: string): string {
  return family.replace(/ (Opening|Defence|Game)$/, '').replace(/ (Opening|Defence|Game),/, ',');
}
