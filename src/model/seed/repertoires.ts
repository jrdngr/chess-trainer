import type { Color } from '../../chess/core';

export interface SeedRepertoire {
  id: string;
  name: string;
  color: Color;
  /** Space-separated SAN lines. Shared prefixes merge into one tree. */
  lines: string[];
  /** Notes attached to the position reached by a SAN prefix. */
  notes?: Record<string, string>;
}

export const SEED_REPERTOIRES: SeedRepertoire[] = [
  {
    id: 'rep_white_e4',
    name: 'White — 1.e4',
    color: 'w',
    lines: [
      // Ruy López
      'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Na5 Bc2 c5 d4',
      'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7 Nbd2',
      'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Bb7 d4 Re8 Nbd2',
      'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Nxe4 d4 b5 Bb3 d5 dxe5 Be6 c3 Bc5 Nbd2 O-O Bc2',
      'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 d6 c3 Bd7 d4 Nf6 O-O',
      'e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6 Bxc6 dxc6 dxe5 Nf5 Qxd8+ Kxd8 h3 Ke8 Nc3 h5 Bf4',
      'e4 e5 Nf3 Nc6 Bb5 f5 Nc3 fxe4 Nxe4 d5 Nxe5 dxe4 Nxc6 Qg5 Qe2 Nf6 f4 Qxf4 Ne5+ c6 d4',
      'e4 e5 Nf3 Nc6 Bb5 Bc5 c3 Nf6 O-O O-O d4',
      'e4 e5 Nf3 Nc6 Bb5 g6 c3 a6 Ba4 d6 d4',
      'e4 e5 Nf3 Nf6 Nxe5 d6 Nf3 Nxe4 d4 d5 Bd3 Be7 O-O Nc6 Re1 Bg4 c3',
      'e4 e5 Nf3 d6 d4 exd4 Nxd4 Nf6 Nc3 Be7 Be2 O-O O-O',
      // Open Sicilian
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O Nbd7 g4 b5 g5',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 h5 Qd2 Nbd7 O-O-O Rc8 Kb1',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e6 g4 h6 Qd2 Nc6 O-O-O Bd7 h4',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 Ng4 Bg5 h6 Bh4 g5 Bg3',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 g6 Be3 Bg7 f3 O-O Qd2 Nc6 Bc4 Bd7 O-O-O Rc8 Bb3 Ne5 h4',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 Nc6 Bg5 e6 Qd2 a6 O-O-O Bd7 f4 Be7 Nf3 b5 Bxf6',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 e6 Be3 Be7 f3 O-O Qd2 Nc6 O-O-O',
      'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 e5 Ndb5 d6 Bg5 a6 Na3 b5 Bxf6 gxf6 Nd5 f5 Bd3 Be6 O-O',
      'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 c4 Nf6 Nc3 d6 Be2 Nxd4 Qxd4 Bg7 Bg5 O-O Qd2',
      'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 e5 Nb5 d6 N1c3 a6 Na3 b5 Nd5 Nge7 Bd3',
      'e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nc6 Nb5 d6 c4 Nf6 N1c3 a6 Na3 Be7 Be2 O-O O-O',
      'e4 c5 Nf3 e6 d4 cxd4 Nxd4 a6 Bd3 Bc5 Nb3 Ba7 Qe2 Nc6 Be3 d6 O-O',
      'e4 c5 Nf3 e6 d4 cxd4 Nxd4 Nf6 Nc3 d6 Be2 Be7 O-O O-O f4 Nc6 Be3',
      'e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 Nf6 Nc3 d6 Bg5 e6 Qd2 Be7 O-O-O O-O f4',
      // French
      'e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7 Qg4 Qc7 Qxg7 Rg8 Qxh7 cxd4 Ne2 Nbc6 f4 Bd7 Qd3',
      'e4 e6 d4 d5 Nc3 Nf6 Bg5 Be7 e5 Nfd7 Bxe7 Qxe7 f4 O-O Nf3 c5 Qd2',
      'e4 e6 d4 d5 Nc3 dxe4 Nxe4 Nd7 Nf3 Ngf6 Nxf6+ Nxf6 Bd3 c5 dxc5 Bxc5 Qe2',
      'e4 e6 d4 d5 Nc3 Bb4 e5 Ne7 a3 Bxc3+ bxc3 c5 Qg4 O-O Bd3',
      // Caro-Kann
      'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6 Nf3 Nd7 h5 Bh7 Bd3 Bxd3 Qxd3 e6 Bf4 Ngf6 O-O-O',
      'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Nd7 Ng5 Ngf6 Bd3 e6 N1f3 Bd6 Qe2 h6 Ne4 Nxe4 Qxe4',
      'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Nf6 Nxf6+ exf6 Bc4 Bd6 Qh5 O-O Ne2',
      'e4 c6 d4 d5 Nc3 g6 Nf3 Bg7 h3 Nf6 Bd3',
      // Pirc / Modern
      'e4 d6 d4 Nf6 Nc3 g6 Be3 Bg7 Qd2 c6 f3 b5 Nge2 Nbd7 Bh6 Bxh6 Qxh6',
      'e4 g6 d4 Bg7 Nc3 d6 Be3 a6 Qd2 b5 f3 Nd7 h4',
      // Scandinavian
      'e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 c6 Bc4 Bf5 Bd2 e6 Nd5 Qd8 Nxf6+',
      'e4 d5 exd5 Nf6 d4 Nxd5 Nf3 g6 Be2 Bg7 O-O O-O c4',
      // Alekhine
      'e4 Nf6 e5 Nd5 d4 d6 Nf3 Bg4 Be2 e6 O-O Be7 c4 Nb6 exd6 cxd6 Nc3',
      // Nimzowitsch
      'e4 Nc6 d4 d5 Nc3 dxe4 d5 Ne5 Qd4 Ng6 Nxe4',
    ],
    notes: {
      'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3':
        'The main tabiya. Black chooses between Na5 (Chigorin), Nb8 (Breyer) and Bb7 (Zaitsev) — know the difference before move 10.',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3':
        'English Attack. Against ...e5 play Nb3 and f3; against ...e6 the immediate g4 is the critical try.',
      'e4 e6 d4 d5 Nc3 Bb4 e5 c5 a3 Bxc3+ bxc3 Ne7 Qg4':
        'Poisoned Pawn Winawer. Take on g7 — the h-pawn decides the game if you survive the middlegame.',
      'e4 c6 d4 d5 Nc3 dxe4 Nxe4 Bf5 Ng3 Bg6 h4 h6':
        'h4-h5 first, then develop. Getting this move order wrong lets Black equalise comfortably.',
    },
  },
  {
    id: 'rep_black_e4',
    name: 'Black vs 1.e4 — Najdorf',
    color: 'b',
    lines: [
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6 Qd2 Qxb2 Rb1 Qa3 e5 dxe5 fxe5 Nfd7 Ne4 h6 Bh4 Qxa2',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6 Qd2 Qxb2 Rb1 Qa3 f5 Nc6 fxe6 fxe6 Nxc6 bxc6 Be2 Be7',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6 Nb3 Qe3+ Qe2 Qxe2+ Bxe2 Nbd7',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O Nbd7 g4 b5 g5 b4 Ne2 Ne8',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 Qd2 Nbd7 f3 Be7 g4 O-O O-O-O Nb6',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be2 e5 Nb3 Be7 O-O O-O Be3 Be6 Qd2 Nbd7 a4 Rc8',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bc4 e6 Bb3 b5 O-O Be7 Qf3 Qc7 Qg3 O-O Bh6 Ne8',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 f4 e5 Nf3 Nbd7 a4 Be7 Bd3 O-O O-O b6',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 h3 e5 Nde2 h5 g3 Be6 Bg2 Nbd7 O-O Rc8',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 g3 e5 Nde2 Be7 Bg2 b5 O-O O-O',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 a4 e5 Nf3 Qc7 Bg5 Nbd7 Bc4 Be7',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 f3 e5 Nb3 Be6 Be3 Nbd7 Qd2 Be7',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Qf3 e5 Nde2 Nbd7 g3 b5 Bg2 Bb7',
      // Anti-Sicilians
      'e4 c5 Nf3 d6 Bb5+ Bd7 Bxd7+ Qxd7 O-O Nc6 c3 Nf6 Re1 e6 d4 cxd4 cxd4 d5 e5 Ne4',
      'e4 c5 Nf3 d6 c3 Nf6 Be2 g6 O-O Bg7 d4 cxd4 cxd4 O-O',
      'e4 c5 Nf3 d6 c4 Nf6 Nc3 g6 d4 cxd4 Nxd4 Bg7',
      'e4 c5 c3 d5 exd5 Qxd5 d4 Nf6 Nf3 e6 Be3 cxd4 cxd4 Nc6 Nc3 Qd6 a3 Be7',
      'e4 c5 Nc3 d6 g3 Nc6 Bg2 g6 d3 Bg7 f4 e6 Nf3 Nge7 O-O O-O',
      'e4 c5 d4 cxd4 c3 dxc3 Nxc3 Nc6 Nf3 d6 Bc4 e6 O-O Nf6 Qe2 Be7',
      'e4 c5 f4 d5 exd5 Nf6 Bb5+ Nbd7 Nc3 a6 Bxd7+ Qxd7',
      'e4 c5 b4 cxb4 a3 d5 exd5 Qxd5 Nf3 e5',
      'e4 c5 Ne2 Nf6 Nbc3 d6 g3 Nc6 Bg2 g6',
    ],
    notes: {
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6':
        'The Najdorf tabiya. ...a6 controls b5 and prepares ...e5 without allowing Ndb5.',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Bg5 e6 f4 Qb6':
        'Poisoned Pawn. Sharpest line in the repertoire — if you are not confident here, 7...Be7 is the practical alternative.',
      'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O':
        'Race position. Black plays ...b5-b4 hitting c3; do not waste a tempo on the h-file.',
      'e4 c5 Nf3 d6 Bb5+ Bd7':
        'Trading on d7 with the queen keeps the structure healthy and heads for a comfortable ...d5 break.',
    },
  },
  {
    id: 'rep_black_d4',
    name: 'Black vs 1.d4 — Nimzo / QID',
    color: 'b',
    lines: [
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5 O-O dxc4 Bxc4 cxd4 exd4 b6 Bg5 Bb7 Qe2 Nbd7',
      'd4 Nf6 c4 e6 Nc3 Bb4 Qc2 O-O a3 Bxc3+ Qxc3 b6 Bg5 Bb7 f3 h6 Bh4 d5 e3 Nbd7',
      'd4 Nf6 c4 e6 Nc3 Bb4 f3 d5 a3 Bxc3+ bxc3 c5 cxd5 Nxd5 dxc5 f5',
      'd4 Nf6 c4 e6 Nc3 Bb4 Bg5 h6 Bh4 c5 d5 d6 e3 e5',
      'd4 Nf6 c4 e6 Nc3 Bb4 Nf3 b6 Bg5 Bb7 e3 h6 Bh4 g5 Bg3 Ne4',
      'd4 Nf6 c4 e6 Nc3 Bb4 g3 c5 Nf3 cxd4 Nxd4 O-O Bg2 d5',
      'd4 Nf6 c4 e6 Nf3 b6 g3 Ba6 b3 Bb4+ Bd2 Be7 Bg2 c6 Bc3 d5 Ne5 Nfd7',
      'd4 Nf6 c4 e6 Nf3 b6 g3 Bb7 Bg2 Be7 O-O O-O Nc3 Ne4 Qc2 Nxc3 Qxc3 c5',
      'd4 Nf6 c4 e6 g3 d5 Bg2 Be7 Nf3 O-O O-O dxc4 Qc2 a6 Qxc4 b5 Qc2 Bb7 Bd2 Be4',
      'd4 Nf6 c4 e6 Nf3 d5 Nc3 Be7 Bg5 h6 Bh4 O-O e3 b6 Be2 Bb7',
      'd4 Nf6 c4 e6 a3 d5 Nc3 Be7 Bg5 O-O',
      'd4 Nf6 Nf3 e6 c4 b6 g3 Ba6 b3 Bb4+ Bd2 Be7',
      'd4 Nf6 Nf3 e6 g3 d5 Bg2 Be7 O-O O-O c4 dxc4',
      'd4 Nf6 Nf3 e6 Bg5 h6 Bh4 b6 e3 Bb7 Bd3 Be7',
      'd4 Nf6 Bg5 Ne4 Bf4 d5 e3 c5 Bd3 Nc6 Nf3 Qb6',
      'd4 Nf6 Nc3 d5 Bg5 Nbd7 f3 c6 Qd2 Qa5',
      'd4 Nf6 g3 e6 Bg2 d5 Nf3 Be7 O-O O-O',
      'd4 Nf6 e3 e6 Nf3 b6 Bd3 Bb7 O-O Be7',
      // Against other first moves
      'c4 e6 Nc3 d5 d4 Nf6 Nf3 Be7 Bg5 h6',
      'c4 e6 Nf3 d5 g3 Nf6 Bg2 Be7 O-O O-O',
      'Nf3 Nf6 c4 e6 Nc3 d5 d4 Be7',
      'Nf3 Nf6 g3 e6 Bg2 d5 O-O Be7 d4 O-O',
      'g3 d5 Bg2 Nf6 Nf3 e6 O-O Be7',
      'b3 d5 Bb2 Nf6 Nf3 e6 e3 Be7',
      'f4 d5 Nf3 Nf6 e3 e6 Be2 Be7',
    ],
    notes: {
      'd4 Nf6 c4 e6 Nc3 Bb4':
        'The Nimzo. Keep the bishop on b4 until trading it wins the two bishops or a structural concession.',
      'd4 Nf6 c4 e6 Nf3 b6':
        'No Nimzo available, so switch to the Queen’s Indian. ...Ba6 hits c4 immediately.',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5':
        'The critical moment: the game becomes an isolated-queen-pawn fight, and Black is fine in all of them.',
    },
  },
];
