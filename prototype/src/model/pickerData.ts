/**
 * The hand-written half of the opening picker: how sharp each opening is, and
 * how the biggest families split into groups.
 *
 * Sharpness is a judgement the book cannot make. Its nearest proxy, the draw
 * rate, puts the Caro-Kann (11% draws) above the Najdorf (21%), because elite
 * players draw sharp openings too. So it is written down: one rating per family,
 * one per group, and overrides for the lines that are nothing like their
 * family — a Marshall Attack is not a Berlin. Difficulty, which the book does
 * measure well, is computed in `picker.ts` instead.
 *
 * Every name and move order here is checked against the book by a test, so a
 * rebuilt book that renames something fails loudly rather than silently
 * dropping a rating.
 */

/** 1 is quiet and positional, 5 is a knife fight from move one. */
export type Sharpness = 1 | 2 | 3 | 4 | 5;

/** Every family the book names. A family missing here reads as 3. */
export const FAMILY_SHARPNESS: Record<string, Sharpness> = {
  'Sicilian Defence': 4,
  'French Defence': 3,
  'Ruy Lopez': 2,
  'English Opening': 2,
  'Caro-Kann Defence': 2,
  "Queen's Gambit Declined": 2,
  "King's Indian Defence": 4,
  'Italian Game': 3,
  'Indian Defence': 3,
  "Queen's Pawn Game": 2,
  'Nimzo-Indian Defence': 3,
  "Petrov's Defence": 1,
  'Scandinavian Defence': 3,
  'Zukertort Opening': 2,
  'Benoni Defence': 4,
  'Slav Defence': 2,
  'Alekhine Defence': 3,
  "Queen's Indian Defence": 2,
  "Queen's Gambit Accepted": 2,
  'Semi-Slav Defence': 4,
  'Grünfeld Defence': 4,
  'Dutch Defence': 4,
  'Four Knights Game': 2,
  'Scotch Game': 3,
  'Vienna Game': 3,
  'Modern Defence': 3,
  'Nimzowitsch Defence': 3,
  'Pirc Defence': 4,
  "King's Indian Attack": 2,
  'Réti Opening': 2,
  'Hungarian Opening': 2,
  "King's Pawn Game": 3,
  "Bishop's Opening": 3,
  "King's Gambit Accepted": 5,
  'Bogo-Indian Defence': 2,
  'Tarrasch Defence': 3,
  'Philidor Defence': 2,
  'Benko Gambit Accepted': 4,
  'Trompowsky Attack': 3,
  'Nimzo-Larsen Attack': 2,
  "King's Gambit Declined": 4,
  'Center Game': 4,
  'Rat Defence': 3,
  'Catalan Opening': 2,
  'Old Indian Defence': 2,
  'Bird Opening': 3,
  'Lion Defence': 3,
  'Neo-Grünfeld Defence': 3,
  'Torre Attack': 2,
  'Pterodactyl Defence': 4,
  "King's Knight Opening": 3,
  'Van Geet Opening': 3,
  'Richter-Veresov Attack': 3,
  'Blackmar-Diemer Gambit': 5,
  'Englund Gambit': 5,
  'Grob Opening': 4,
  'Three Knights Opening': 2,
  'Ponziani Opening': 3,
  'Elephant Gambit': 5,
  'Latvian Gambit': 5,
  'Latvian Gambit Accepted': 5,
  'Benko Gambit': 4,
  'Benko Gambit Declined': 3,
  'Mieses Opening': 2,
  'Barnes Opening': 2,
  'Vienna Gambit, with Max Lange Defence': 5,
  "King's Gambit": 5,
  'Center Game Accepted': 4,
  'Danish Gambit': 5,
  'Czech Defence': 3,
  'Owen Defence': 3,
  'St. George Defence': 3,
  'Barnes Defence': 2,
  'Fried Fox Defence': 2,
  'Duras Gambit': 4,
  'Goldsmith Defence': 2,
  'Carr Defence': 2,
  'Ware Defence': 2,
  'Hippopotamus Defence': 2,
  'Blumenfeld Countergambit': 4,
  'Blumenfeld Countergambit Accepted': 4,
  'Slav Indian': 2,
  "Queen's Indian Accelerated": 2,
  'Mexican Defence': 3,
  'East Indian Defence': 3,
  'London System': 1,
  "Pseudo Queen's Indian Defence": 2,
  'Yusupov-Rubinstein System': 1,
  'Paleface Attack': 3,
  "Queen's Gambit": 2,
  'Semi-Slav Defence Accepted': 4,
  'Rapport-Jobava System': 3,
  'Blackmar-Diemer Gambit Accepted': 5,
  'Rapport-Jobava System, with e6': 3,
  'Horwitz Defence': 2,
  'Kangaroo Defence': 3,
  'Englund Gambit Declined': 3,
  'Mikenas Defence': 3,
  'English Defence': 3,
  'Polish Defence': 3,
  'Wade Defence': 2,
  "King's Indian Attack, with e6": 2,
  "King's Indian Attack, with Bf5": 2,
  'English Orangutan': 3,
  'Lasker Simul Special': 3,
  "Van't Kruijs Opening": 2,
  "Anderssen's Opening": 2,
  'Saragossa Opening': 2,
  'Kádas Opening': 3,
  'Polish Opening': 3,
  'Polish Opening, with d5': 3,
  'Clemenz Opening': 2,
  'Ware Opening': 2,
};

/**
 * Lines that are sharper or quieter than the family around them. An override
 * holds for everything under the name too, until a deeper override says
 * otherwise: the Najdorf's 5 carries into every Najdorf line.
 */
export const SHARPNESS_OVERRIDES: Record<string, Sharpness> = {
  // Sicilian
  'Sicilian Defence: Najdorf Variation': 5,
  'Sicilian Defence: Dragon Variation': 5,
  'Sicilian Defence: Lasker-Pelikan Variation': 5,
  'Sicilian Defence: Richter-Rauzer Variation': 4,
  'Sicilian Defence: Scheveningen Variation': 4,
  'Sicilian Defence: Scheveningen Variation, Keres Attack': 5,
  'Sicilian Defence: Taimanov Variation': 4,
  'Sicilian Defence: Kan Variation': 3,
  'Sicilian Defence: Accelerated Dragon': 3,
  'Sicilian Defence: Accelerated Dragon, Maróczy Bind': 2,
  'Sicilian Defence: Kalashnikov Variation': 4,
  'Sicilian Defence: Four Knights Variation': 4,
  'Sicilian Defence: Classical Variation': 4,
  'Sicilian Defence: Alapin Variation': 2,
  'Sicilian Defence: Nyezhmetdinov-Rossolimo Attack': 2,
  'Sicilian Defence: Moscow Variation': 2,
  'Sicilian Defence: Smith-Morra Gambit': 5,
  'Sicilian Defence: Wing Gambit': 5,
  'Sicilian Defence: Grand Prix Attack': 4,
  'Sicilian Defence: Closed': 3,
  // French
  'French Defence: Winawer Variation': 5,
  'French Defence: Classical Variation': 4,
  'French Defence: Steinitz Variation': 4,
  'French Defence: McCutcheon Variation': 5,
  'French Defence: Alekhine-Chatard Attack': 5,
  'French Defence: Rubinstein Variation': 2,
  'French Defence: Exchange Variation': 1,
  'French Defence: Advance Variation, Milner-Barry Gambit': 5,
  // Caro-Kann
  'Caro-Kann Defence: Advance Variation, Bayonet Attack': 5,
  'Caro-Kann Defence: Panov Attack': 3,
  'Caro-Kann Defence: Tartakower Variation': 3,
  'Caro-Kann Defence: Bronstein-Larsen Variation': 4,
  'Caro-Kann Defence: Maróczy Variation': 4,
  'Caro-Kann Defence: Endgame Variation': 1,
  'Caro-Kann Defence: Apocalypse Attack': 4,
  // Ruy Lopez
  'Ruy Lopez: Morphy Defence': 3,
  'Ruy Lopez: Berlin Defence': 1,
  'Ruy Lopez: Marshall Attack': 5,
  'Ruy Lopez: Schliemann Defence': 5,
  'Ruy Lopez: Open': 4,
  'Ruy Lopez: Exchange Variation': 2,
  'Ruy Lopez: Closed': 2,
  // Italian
  'Italian Game: Two Knights Defence': 4,
  'Italian Game: Two Knights Defence, Knight Attack': 5,
  'Italian Game: Evans Gambit': 5,
  'Italian Game: Giuoco Pianissimo': 2,
  'Italian Game: Scotch Gambit': 4,
  // Queen's Gambit Declined
  "Queen's Gambit Declined: Albin Countergambit": 5,
  "Queen's Gambit Declined: Chigorin Defence": 4,
  "Queen's Gambit Declined: Exchange Variation": 2,
  "Queen's Gambit Declined: Ragozin Defence": 3,
  "Queen's Gambit Declined: Semi-Tarrasch Defence": 3,
  "Queen's Gambit Declined: Tarrasch Defence": 3,
  // King's Indian
  "King's Indian Defence: Four Pawns Attack": 5,
  "King's Indian Defence: Fianchetto Variation": 3,
  "King's Indian Defence: Averbakh Variation": 3,
  "King's Indian Defence: Petrosian Variation": 3,
  "King's Indian Defence: Exchange Variation": 2,
  "King's Indian Defence: Makogonov Variation": 3,
  // Queen's pawn systems
  'Indian Defence: Budapest Gambit': 4,
  'Indian Defence: London System': 1,
  'Indian Defence: Accelerated London System': 1,
  "Queen's Pawn Game: London System": 1,
  "Queen's Pawn Game: Accelerated London System": 1,
  "Queen's Pawn Game: Colle System": 1,
  // Others
  'Nimzo-Indian Defence: Sämisch Variation': 4,
  'Nimzo-Indian Defence: Rubinstein System': 2,
  "Petrov's Defence: Stafford Gambit": 5,
  "Petrov's Defence: Cochrane Gambit": 5,
  'Scandinavian Defence: Portuguese Gambit': 4,
  'Scandinavian Defence: Icelandic-Palme Gambit': 5,
  'Benoni Defence: Modern Variation': 5,
  'Benoni Defence: Czech Benoni Defence': 2,
  'Semi-Slav Defence: Botvinnik Variation': 5,
  'Semi-Slav Defence: Meran Variation': 4,
  'Semi-Slav Defence: Anti-Moscow Gambit': 5,
  'Semi-Slav Defence: Marshall Gambit': 5,
  'Slav Defence: Geller Gambit': 5,
  'Alekhine Defence: Four Pawns Attack': 5,
  'Dutch Defence: Staunton Gambit': 5,
  'Dutch Defence: Leningrad Variation': 4,
  'Scotch Game: Göring Gambit': 5,
  'Vienna Game: Vienna Gambit': 5,
  'Vienna Game: Frankenstein-Dracula Variation': 5,
  'Pirc Defence: Austrian Attack': 5,
  'English Opening: King\'s English Variation': 3,
  'English Opening: Anglo-Dutch Defence': 4,
  'English Opening: Mikenas-Carls Variation': 4,
};

/**
 * Branches the book names a move late, like the two families in
 * `onboarding.ts`: the Taimanov is Black's 4...Nc6, named on White's 5.Nc3.
 */
export const BRANCH_SIDES: Record<string, 'w' | 'b'> = {
  'Sicilian Defence: Taimanov Variation': 'b',
};

/** A group inside a big family: every branch that can be reached from one of its positions. */
export interface GroupSpec {
  label: string;
  /** Move orders to the positions that define the group. Any of them counts. */
  from: string[];
  sharpness: Sharpness;
}

export interface FamilySplit {
  groups: GroupSpec[];
  /** What the branches no group reaches are called. */
  rest: string;
  /** Their sharpness, where the family's own would overstate it. */
  restSharpness?: Sharpness;
}

/**
 * The families big enough to need grouping — about a dozen with fourteen or
 * more branches. A branch belongs to the group whose position it passes
 * through (the deepest, if several), or failing that one it can transpose
 * from (the most played, if several). Groups are by position, so a
 * Scheveningen reached by a Najdorf move order still lands in the Open
 * Sicilian.
 */
export const FAMILY_GROUPS: Record<string, FamilySplit> = {
  'Sicilian Defence': {
    groups: [
      {
        label: 'Open Sicilian',
        from: [
          'e4 c5 Nf3 d6 d4 cxd4 Nxd4',
          'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4',
          'e4 c5 Nf3 e6 d4 cxd4 Nxd4',
          'e4 c5 Nf3 g6 d4 cxd4 Nxd4',
          'e4 c5 Nf3 a6 d4 cxd4 Nxd4',
          // The book names the Open Sicilian a move before the recapture.
          'e4 c5 Nf3 Nc6 d4 cxd4',
        ],
        sharpness: 5,
      },
      { label: '2.Nf3 sidelines', from: ['e4 c5 Nf3'], sharpness: 3 },
      { label: 'Alapin', from: ['e4 c5 c3'], sharpness: 2 },
      { label: 'Closed and Grand Prix', from: ['e4 c5 Nc3'], sharpness: 3 },
      { label: 'Smith-Morra Gambit', from: ['e4 c5 d4'], sharpness: 5 },
    ],
    rest: 'Other second moves',
    restSharpness: 3,
  },
  'French Defence': {
    groups: [
      { label: '3.Nc3', from: ['e4 e6 d4 d5 Nc3'], sharpness: 4 },
      { label: 'Advance', from: ['e4 e6 d4 d5 e5'], sharpness: 3 },
      { label: 'Other third moves', from: ['e4 e6 d4 d5'], sharpness: 2 },
    ],
    rest: 'Other lines',
  },
  'Caro-Kann Defence': {
    groups: [
      { label: 'Main lines (3.Nc3 and 3.Nd2)', from: ['e4 c6 d4 d5 Nc3', 'e4 c6 d4 d5 Nd2'], sharpness: 2 },
      { label: 'Advance', from: ['e4 c6 d4 d5 e5'], sharpness: 3 },
      { label: 'Exchange and Panov', from: ['e4 c6 d4 d5 exd5'], sharpness: 3 },
      { label: 'Two Knights and 2.Nf3', from: ['e4 c6 Nc3 d5 Nf3', 'e4 c6 Nf3 d5'], sharpness: 2 },
    ],
    rest: 'Other lines',
  },
  'Ruy Lopez': {
    groups: [
      { label: 'Morphy Defence (3...a6)', from: ['e4 e5 Nf3 Nc6 Bb5 a6'], sharpness: 3 },
      { label: 'Berlin Defence (3...Nf6)', from: ['e4 e5 Nf3 Nc6 Bb5 Nf6'], sharpness: 1 },
    ],
    rest: 'Other third moves',
  },
  'English Opening': {
    groups: [
      { label: "1...e5 King's English", from: ['c4 e5'], sharpness: 3 },
      { label: '1...Nf6 Anglo-Indian', from: ['c4 Nf6'], sharpness: 2 },
      { label: '1...c5 Symmetrical', from: ['c4 c5'], sharpness: 2 },
      { label: '1...e6 Agincourt', from: ['c4 e6'], sharpness: 2 },
    ],
    rest: 'Other replies',
  },
  "Queen's Gambit Declined": {
    groups: [
      { label: '3.Nc3', from: ['d4 d5 c4 e6 Nc3'], sharpness: 2 },
      { label: '3.Nf3', from: ['d4 d5 c4 e6 Nf3'], sharpness: 2 },
    ],
    rest: 'Second-move alternatives',
  },
  "King's Indian Defence": {
    groups: [
      { label: 'Classical (5.Nf3)', from: ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3'], sharpness: 4 },
      { label: 'Sämisch and Four Pawns', from: ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3', 'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4'], sharpness: 5 },
      { label: 'Averbakh and Be2 systems', from: ['d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2'], sharpness: 3 },
    ],
    rest: 'Other lines',
  },
  'Indian Defence': {
    groups: [
      { label: '2.c4', from: ['d4 Nf6 c4'], sharpness: 3 },
      { label: '2.Nf3', from: ['d4 Nf6 Nf3'], sharpness: 2 },
    ],
    rest: 'Other second moves',
  },
  "Queen's Pawn Game": {
    groups: [
      { label: '1...d5', from: ['d4 d5'], sharpness: 2 },
      { label: '1...Nf6', from: ['d4 Nf6'], sharpness: 2 },
    ],
    rest: 'Other replies',
  },
  'Zukertort Opening': {
    groups: [
      { label: '1...Nf6', from: ['Nf3 Nf6'], sharpness: 2 },
      { label: '1...d5', from: ['Nf3 d5'], sharpness: 2 },
    ],
    rest: 'Other replies',
  },
  'Benoni Defence': {
    groups: [
      { label: 'Modern Benoni', from: ['d4 Nf6 c4 c5 d5 e6'], sharpness: 5 },
      { label: 'Old Benoni (1...c5)', from: ['d4 c5'], sharpness: 3 },
    ],
    rest: 'Other lines',
  },
  'Scandinavian Defence': {
    groups: [
      { label: '2...Qxd5', from: ['e4 d5 exd5 Qxd5'], sharpness: 3 },
      { label: '2...Nf6', from: ['e4 d5 exd5 Nf6'], sharpness: 3 },
    ],
    rest: 'Other lines',
  },
  'Dutch Defence': {
    groups: [{ label: '2.c4 main lines', from: ['d4 f5 c4'], sharpness: 3 }],
    rest: 'Anti-Dutch lines',
  },
};
