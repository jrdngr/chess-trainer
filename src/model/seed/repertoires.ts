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

/**
 * Two repertoires, matching what the user actually plays:
 * the Queen's Gambit with White and the King's Indian with Black.
 *
 * Within each repertoire there is exactly one move for the user in any given
 * position — a repertoire is a set of decisions, not a menu. The breadth is all
 * on the opponent's side: every mainstream system they can throw at you.
 */
export const SEED_REPERTOIRES: SeedRepertoire[] = [
  {
    id: 'rep_white_qg',
    name: "White — Queen's Gambit",
    color: 'w',
    lines: [
      // ── 1.d4 d5 2.c4 e6 — Queen's Gambit Declined ──────────────────────
      // House move order in the Exchange: Bg5, e3, Bd3, Qc2, Nge2, O-O, then
      // Rab1/a3/b4. Keeping it fixed means Black's move order is the only
      // thing that varies.
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 O-O Bd3 Nbd7 Qc2 Re8 Nge2 Nf8 O-O c6 Rab1 a5 a3',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 c6 Bd3 Nbd7 Qc2 O-O Nge2 Re8 O-O Nf8 Rab1 a5 a3',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Be7 Bd3 Nbd7 Qc2 O-O Nge2 Re8 O-O Nf8 Rab1',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Nbd7 e3 Be7 Bd3 O-O Qc2 Re8 Nge2 Nf8 O-O c6 Rab1',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 Ne4 Bxe7 Qxe7 Bd3 Nxc3 bxc3 O-O Ne2',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 h6 Bh4 Be7 e3 O-O Bd3 c6 Qc2 Nbd7 Nge2',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Bf5 Qf3 Bg6 Bxf6 Qxf6 Qxf6 gxf6 Nge2',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Bb4 e3 c6 Bd3 Nbd7 Qc2 O-O Nge2 Re8 O-O',
      'd4 d5 c4 e6 Nc3 Be7 cxd5 exd5 Bf4 Nf6 e3 O-O Bd3 c6 Qc2 Nbd7 Nge2 Re8 O-O',
      'd4 d5 c4 e6 Nc3 Bb4 cxd5 exd5 Bg5 Nf6 e3 c6 Bd3 Nbd7 Qc2 O-O Nge2 Re8 O-O',
      'd4 d5 c4 e6 Nc3 a6 cxd5 exd5 Bf4 Nf6 e3 Bd6 Bxd6 Qxd6 Bd3 O-O Nge2',
      'd4 d5 c4 e6 Nc3 c5 cxd5 exd5 Nf3 Nc6 g3 Nf6 Bg2 Be7 O-O O-O Bg5 cxd4 Nxd4',
      'd4 d5 c4 e6 Nc3 c5 cxd5 exd5 Nf3 Nc6 g3 c4 Bg2 Bb4 O-O Nge7 e4 dxe4 Ng5',
      'd4 d5 c4 e6 Nc3 dxc4 e4 b5 a4 c6 axb5 cxb5 Nxb5 Bb4+ Bd2 Bxd2+ Qxd2 Nf6 e5',
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 Nxd5 e4 Nxc3 bxc3 c5 Nf3 cxd4 cxd4 Bb4+ Bd2 Bxd2+ Qxd2',
      // ── 1.d4 d5 2.c4 c6 — Slav and Semi-Slav ───────────────────────────
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4 O-O Nbd7 Qe2 Bg6 e4 O-O Bd3',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 Na6 Bxc4 Nb4 O-O e6 Qe2 Bg4 Rd1',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 e6 e3 Bb4 Bxc4 O-O O-O Nbd7 Qe2 Bd6 e4',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4 Na6 e4 Bg4 Bxc4 e6 Be3 Bb4 Qb3',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 dxc4 e4 b5 e5 h6 Bh4 g5 Nxg5 hxg5 Bxg5 Nbd7 exf6 Bb7 g3 c5 d5 Qb6 Bg2',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 h6 Bh4 dxc4 e4 g5 Bg3 b5 Be2 Bb7 O-O Nbd7 Qc2',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 Be7 e3 O-O Rc1 h6 Bh4 b6 cxd5 Nxd5 Bxe7 Qxe7 Nxd5',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 Nbd7 e3 Qa5 Nd2 Bb4 Qc2 O-O Be2',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 Nbd7 e3 Be7 Bd3 O-O O-O dxc4 Bxc4 b5 Bd3 Bb7 e4',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 a6 e3 Bg4 h3 Bxf3 Qxf3 e6 Bd3 Nbd7 O-O',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 a6 e3 b5 b3 Bg4 Be2 e6 O-O Nbd7 h3 Bh5 Bb2',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 g6 cxd5 cxd5 Bf4 Bg7 e3 O-O Be2 Nc6 O-O',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 Bf5 cxd5 cxd5 Qb3 Qc8 Bf4 e6 e3 Nc6 Bb5',
      'd4 d5 c4 c6 Nf3 dxc4 e3 b5 a4 e6 axb5 cxb5 b3 Bb7 bxc4 bxc4 Bxc4',
      // ── 1.d4 d5 2.c4 dxc4 — Queen's Gambit Accepted ────────────────────
      // House move order: Nf3, e3, Bxc4, O-O, then a4 against ...a6.
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6 a4 Nc6 Qe2 cxd4 Rd1 Be7 exd4',
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6 a4 Nbd7 Nc3 b6 Qe2 Bb7 Rd1 Qb8 d5',
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O Nc6 Qe2 a6 Rd1 b5 Bb3 c4 Bc2 Nb4 Nc3',
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 Be7 O-O O-O Qe2 c5 Rd1 Qc7 Nc3 a6 dxc5',
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 Bg4 Bxc4 e6 h3 Bh5 Nc3 Nbd7 O-O Bd6 e4 e5 Be3',
      'd4 d5 c4 dxc4 Nf3 a6 e3 Bg4 Bxc4 e6 h3 Bh5 Nc3 Nf6 O-O Nbd7 e4',
      'd4 d5 c4 dxc4 Nf3 c5 d5 Nf6 Nc3 e6 e4 exd5 e5 Nfd7 Bg5 Be7 Bxe7 Qxe7 Nxd5',
      'd4 d5 c4 dxc4 Nf3 b5 a4 c6 axb5 cxb5 b3 e6 bxc4 bxc4 Nc3',
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 c5 Bxc4 e6 O-O a6 a4 Nc6 Qe2 cxd4 Rd1 Be7 exd4',
      // ── 1.d4 d5 2.c4 — the rest ────────────────────────────────────────
      'd4 d5 c4 Nc6 Nf3 Bg4 cxd5 Bxf3 gxf3 Qxd5 e3 e5 Nc3 Bb4 Bd2 Bxc3 bxc3 Qd6 Rb1',
      'd4 d5 c4 e5 dxe5 d4 Nf3 Nc6 g3 Be6 Nbd2 Qd7 Bg2 O-O-O O-O Nge7 Nb3',
      'd4 d5 c4 Bf5 cxd5 Bxb1 Rxb1 Qxd5 a3 Nc6 Nf3 e5 e3 exd4 Nxd4',
      'd4 d5 c4 Nf6 cxd5 Nxd5 e4 Nf6 Nc3 e5 dxe5 Qxd1+ Kxd1 Ng4 Ke1 Nc6 Bf4',
      'd4 d5 c4 c5 cxd5 Nf6 Nc3 Nxd5 e4 Nxc3 bxc3 g6 Nf3 Bg7 Rb1',
      'd4 d5 c4 Nd7 cxd5 Ngf6 Nc3 Nxd5 e4 Nxc3 bxc3 e5 Nf3',
      'd4 d5 c4 h6 cxd5 Qxd5 Nc3 Qa5 Nf3 Nf6 Bd2 c6 e4',
      // ── 1.d4 Nf6 2.c4 g6 — King's Indian and Grünfeld ──────────────────
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 Nd3 f5 Bd2 Nf6 f3 f4 c5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nbd7 Re1 c6 Rb1 Re8 d5 Nc5 Bf1',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O exd4 Nxd4 Re8 f3 c6 Kh1',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Na6 Be3 Ng4 Bg5 Qe8 dxe5 dxe5 h3',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 c6 O-O Bg4 Be3 Nfd7 Rc1',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 Nc6 d5 Nb8 O-O e5 dxe6 Bxe6 Bf4',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 Bg4 Be2 Nfd7 Be3 O-O Qd2 e5 d5',
      'd4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Nf3 c5 Rb1 O-O Be2 cxd4 cxd4 Qa5+ Bd2 Qxa2 O-O',
      'd4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 Bg7 Nf3 c5 Rb1 O-O Be2 Nc6 d5 Ne5 Nxe5 Bxe5 O-O',
      'd4 Nf6 c4 g6 Nc3 d5 cxd5 Nxd5 e4 Nb6 Nf3 Bg7 Be3 O-O Qd2 Nc6 O-O-O',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d5 cxd5 Nxd5 e5 Nxc3 bxc3 c5 Nf3 Nc6 Be2',
      // ── 1.d4 Nf6 2.c4 e6 — the Nimzo is allowed, so 3.Nc3 ──────────────
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 d5 Nf3 c5 O-O dxc4 Bxc4 cxd4 exd4 b6 Bg5 Bb7 Qe2',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 c5 Bd3 Nc6 Nf3 O-O O-O d5 a3 Bxc3 bxc3 dxc4 Bxc4',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 b6 Nf3 Bb7 Bd3 O-O O-O d5 cxd5 exd5 a3 Bd6 b4',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 Ne4 Qc2 d5 Bd3 f5 Nge2 O-O O-O Nd7 f3 Nef6 cxd5',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 d5 Nf3 O-O Bd3 c5 O-O Nc6 a3 Bxc3 bxc3 dxc4 Bxc4',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 O-O Bd3 c5 Nf3 d5 O-O b6 cxd5 exd5 dxc5 bxc5 Ne2',
      'd4 Nf6 c4 e6 Nc3 d5 cxd5 exd5 Bg5 Be7 e3 O-O Bd3 c6 Qc2 Nbd7 Nge2 Re8 O-O',
      'd4 Nf6 c4 e6 Nc3 b6 e4 Bb7 Bd3 d5 cxd5 exd5 e5 Ne4 Nge2 Bb4 O-O',
      'd4 Nf6 c4 e6 Nc3 c5 d5 exd5 cxd5 d6 e4 g6 Nf3 Bg7 h3 O-O Bd3 Re8 O-O',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3 Nc6 Nf3 d5 Bd3 O-O O-O dxc4 Bxc4 Bd6 Bb5',
      // ── 1.d4 Nf6 2.c4 c5 — Benoni and Benko ────────────────────────────
      'd4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6 Nf3 Bg7 h3 O-O Bd3 Re8 O-O',
      'd4 Nf6 c4 c5 d5 e6 Nc3 exd5 cxd5 d6 e4 g6 Nf3 Bg7 h3 O-O Bd3 Na6 O-O Nc7 a4',
      'd4 Nf6 c4 c5 d5 b5 cxb5 a6 bxa6 Bxa6 Nc3 d6 e4 Bxf1 Kxf1 g6 g3 Bg7 Kg2 O-O Nf3',
      'd4 Nf6 c4 c5 d5 b5 cxb5 a6 bxa6 g6 Nc3 Bxa6 Nf3 d6 g3 Bg7 Bg2 Nbd7 O-O',
      'd4 Nf6 c4 c5 d5 b5 cxb5 a6 bxa6 Qa5+ Nc3 Bxa6 e4 Bxf1 Kxf1 d6 Nf3',
      'd4 Nf6 c4 c5 d5 e5 Nc3 d6 e4 Be7 Nf3 O-O Be2 Ne8 O-O',
      'd4 Nf6 c4 c5 d5 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e6 O-O exd5 cxd5',
      'd4 Nf6 c4 c5 d5 d6 Nc3 g6 e4 Bg7 Nf3 O-O Be2 e6 O-O exd5 cxd5',
      // ── 1.d4 Nf6 2.c4 — other Indians ──────────────────────────────────
      'd4 Nf6 c4 e5 dxe5 Ng4 Bf4 Nc6 Nf3 Bb4+ Nbd2 Qe7 a3 Ngxe5 Nxe5 Nxe5 e3 Bxd2+ Qxd2',
      'd4 Nf6 c4 d6 Nc3 e5 Nf3 Nbd7 e4 Be7 Be2 O-O O-O c6 Qc2 Re8 Rd1',
      'd4 Nf6 c4 d6 Nc3 g6 e4 Bg7 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1',
      'd4 Nf6 c4 b6 Nc3 Bb7 Qc2 e6 e4 Bb4 Bd3 Bxc3+ bxc3 d6 Ne2 e5 O-O',
      'd4 Nf6 c4 Nc6 Nf3 e6 Nc3 Bb4 Bg5 h6 Bh4 Bxc3+ bxc3 d6 e3',
      'd4 Nf6 c4 c6 Nf3 d5 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4 O-O Nbd7 Qe2',
      'd4 Nf6 c4 g5 Bxg5 Ne4 Bf4 d5 e3 Bf5 Nc3 Nxc3 bxc3',
      'd4 Nf6 c4 a6 Nc3 d5 cxd5 Nxd5 e4 Nxc3 bxc3 e6 Nf3 c5 Bd3',
      'd4 Nf6 c4 Ne4 Qc2 d5 cxd5 Qxd5 Nf3 Nc6 e3 Bf5 Nc3',
      // ── 1.d4, other Black first moves ──────────────────────────────────
      'd4 f5 c4 Nf6 g3 e6 Bg2 Be7 Nf3 O-O O-O d5 b3 c6 Ba3 Bxa3 Nxa3 Qe7 Qc1',
      'd4 f5 c4 Nf6 g3 g6 Bg2 Bg7 Nf3 O-O O-O d6 Nc3 Qe8 d5 Na6 Rb1',
      'd4 f5 c4 Nf6 g3 e6 Bg2 Be7 Nf3 O-O O-O d6 Nc3 Qe8 Re1 Qg6 e4',
      'd4 f5 c4 e6 g3 Nf6 Bg2 Be7 Nf3 O-O O-O d5 b3 c6 Ba3',
      'd4 g6 c4 Bg7 Nc3 d6 e4 Nf6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1',
      'd4 e6 c4 f5 g3 Nf6 Bg2 Be7 Nf3 O-O O-O d5 b3 c6 Ba3',
      'd4 d6 c4 e5 Nf3 e4 Ng5 f5 Nc3 Nf6 f3 exf3 Nxf3 Be7 e4',
      'd4 c5 d5 d6 c4 g6 Nc3 Bg7 e4 Nf6 Nf3 O-O Be2 e6 O-O',
      'd4 b6 c4 Bb7 Nc3 e6 a3 f5 d5 Nf6 g3 Na6 Bg2',
      'd4 Nc6 Nf3 d5 c4 Bg4 cxd5 Bxf3 gxf3 Qxd5 e3 e5 Nc3 Bb4 Bd2',
      'd4 e5 dxe5 Nc6 Nf3 Qe7 Bf4 Qb4+ Bd2 Qxb2 Nc3 Bb4 Rb1 Qa3 Rb3',
      'd4 c6 c4 d5 Nf3 Nf6 Nc3 dxc4 a4 Bf5 e3 e6 Bxc4 Bb4 O-O',
      'd4 g5 Bxg5 c6 e4 Qb6 Nc3 Qxb2 Bd2',
      'd4 b5 e4 Bb7 Bd3 a6 Nf3 e6 O-O Nf6 Re1 c5 c3',
    ],
    notes: {
      'd4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5':
        'Exchange Variation. The whole plan is the minority attack: Rab1, b4-b5, and Black is left with a weak c6 pawn. Nge2 rather than Nf3 keeps the f-pawn free.',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 e6 Bg5 dxc4 e4 b5 e5 h6 Bh4 g5 Nxg5':
        'Botvinnik Variation. A piece for three pawns and an attack, analysed to move thirty. Only enter it if you keep the theory up.',
      'd4 d5 c4 c6 Nf3 Nf6 Nc3 dxc4 a4':
        'a4 stops ...b5 and is the reason the Slav main line exists. Black gets ...Bf5 in first, which is the whole point of the Slav over the QGD.',
      'd4 d5 c4 dxc4 Nf3 Nf6 e3 e6 Bxc4 c5 O-O a6':
        'QGA tabiya. Black wants ...b5 and ...Bb7; you want to meet it with a4 or dxc5 and play against the isolated or hanging pawns.',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7':
        'You get this position from the other side too. Race: Black attacks on the kingside, you break with c5 on the queenside. Count moves, not pawns.',
      'd4 Nf6 c4 e6 Nc3 Bb4 e3':
        'Rubinstein. Against the Nimzo the safest practical choice — you accept doubled pawns in some lines in return for the bishop pair and a big centre.',
      'd4 Nf6 c4 c5 d5 b5 cxb5 a6 bxa6':
        'Benko accepted. Give the pawn back at the right moment rather than clinging to it; the a- and b-files are the real compensation.',
    },
  },
  {
    id: 'rep_black_kid',
    name: "Black — King's Indian",
    color: 'b',
    lines: [
      // ── Classical: 5.Nf3 O-O 6.Be2 e5 7.O-O Nc6 8.d5 Ne7 ───────────────
      // House move order: ...Bg7, ...d6, ...O-O, ...e5, ...Nc6. One Black move
      // per position; all the breadth is on White's side.
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 Nd3 f5 Bd2 Nf6 f3 f4 c5 g5 Rc1 Ng6 cxd6 cxd6 Nb5 Rf7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 f3 f5 Be3 f4 Bf2 g5 a4 Ng6 a5 Nf6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 Nd3 f5 f3 f4 Bd2 g5 Rc1 Ng6 c5 Nf6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 b4 Nh5 Re1 f5 Ng5 Nf6 Bf3 c6 Bb2 h6 Ne6 Bxe6 dxe6 fxe4',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 b4 Nh5 g3 f5 Ng5 Nf6 f3 c6 Be3 cxd5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Nd2 a5 a3 Nd7 Rb1 f5 b4 Kh8 f3 Ng8',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Nd2 a5 Rb1 Nd7 a3 f5 b4 Kh8 f3 Ng8',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Bd2 Ne8 Rc1 f5 Qb3 b6 c5 h6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Be3 Ng4 Bg5 f6 Bh4 Nh6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 dxe5 dxe5 Qxd8 Rxd8 Bg5 Re8 Nd5 Nxd5 cxd5 Nd4',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 Be3 Ng4 Bg5 Qe8 dxe5 dxe5 h3 h6 Bd2 Nf6',
      // ── Classical: White deviates before castling ───────────────────────
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 dxe5 dxe5 Qxd8 Rxd8 Bg5 Re8 Nd5 Nxd5 cxd5 c6 Bc4 cxd5 Bxd5 Nd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 d5 a5 Bg5 h6 Bh4 Na6 Nd2 Qe8 O-O Bd7 a3 Nh7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 d5 a5 O-O Na6 Bg5 h6 Bh4 Qe8 Nd2 Bd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 Be3 Ng4 Bg5 f6 Bh4 Nc6 d5 Ne7 Nd2 Nh6 O-O Nf7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 Be3 Ng4 Bg5 f6 Bd2 Nc6 d5 Ne7 h4 f5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 h3 Nc6 d5 Ne7 Be3 Nd7 Nd2 f5 g4 Kh8',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 Qc2 Nc6 d5 Ne7 Be3 Nd7 O-O-O f5',
      // ── Anti-KID set-ups ────────────────────────────────────────────────
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O h3 e5 d5 a5 Bg5 h6 Be3 Na6 Nd2 Nc5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Bd3 e5 O-O Nc6 d5 Ne7 Ne1 Nd7 f3 f5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be3 e5 dxe5 dxe5 Qxd8 Rxd8 Nxe5 Nxe4',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Qc2 e5 d5 a5 Be2 Na6 O-O Nc5',
      'd4 Nf6 c4 g6 Nc3 Bg7 Nf3 d6 Bf4 O-O e3 b6 Be2 Bb7 O-O Nbd7 h3 Re8 Qc2 e5',
      'd4 Nf6 c4 g6 Nc3 Bg7 Nf3 d6 Bg5 h6 Bh4 O-O e3 c5 Be2 cxd4 exd4 Nc6',
      'd4 Nf6 c4 g6 Nc3 Bg7 Nf3 d6 e3 O-O Be2 e5 O-O Nc6 d5 Ne7 e4 Nd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 Bg5 h6 Bh4 d6 e3 O-O Be2 Nbd7 Nf3 e5 O-O Qe8',
      'd4 Nf6 c4 g6 Nc3 Bg7 Bf4 d6 e3 O-O Be2 c5 dxc5 dxc5 Qxd8 Rxd8 Bxb8 Rxb8',
      'd4 Nf6 c4 g6 Nc3 Bg7 h4 d6 e4 h5 Nf3 O-O Be2 e5 d5 Na6',
      // ── Sämisch: 5.f3 ───────────────────────────────────────────────────
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 d5 Nh5 Qd2 f5 O-O-O Nd7 Bd3 Nc5 Bc2 a6 Nge2 b5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 Nge2 c6 Qd2 Nbd7 O-O-O a6 Kb1 b5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 d5 Nh5 Nge2 f5 exf5 gxf5 Qd2 Nd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 dxe5 dxe5 Qxd8 Rxd8 Nd5 Nxd5 cxd5 c6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Bg5 e5 d5 c6 Qd2 cxd5 cxd5 Nbd7 Nge2 a6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Nge2 e5 Bg5 c6 Qd2 Nbd7 d5 c5',
      'd4 Nf6 c4 g6 f3 Bg7 e4 d6 Nc3 O-O Be3 e5 d5 Nh5 Qd2 f5 O-O-O Nd7',
      // ── Averbakh, Makogonov and other fifth moves ───────────────────────
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5 c5 d5 e6 Qd2 exd5 exd5 Re8 Nf3 Bg4 O-O Nbd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5 c5 dxc5 Qa5 Bd2 Qxc5 Nf3 Bg4 Be3 Qa5 O-O Nc6',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Be3 e5 d5 Nbd7 Qd2 Nc5 f3 a5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 h3 O-O Be3 e5 d5 Nh5 Qd2 f5 exf5 gxf5 O-O-O Nd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 h3 O-O Bg5 Na6 Bd3 e5 d5 Qe8 Nge2 Nh5 Qd2 Bd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nge2 O-O Ng3 e5 d5 a5 Be2 Na6 O-O Nc5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Bd3 O-O Nge2 e5 O-O Nc6 d5 Ne7 f3 Nd7',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Qd2 O-O Nf3 e5 d5 a5 Be2 Na6 O-O Nc5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Bd2 O-O Nf3 e5 d5 a5 Be2 Na6 O-O Nc5',
      // ── Four Pawns Attack ───────────────────────────────────────────────
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4 O-O Nf3 c5 d5 e6 Be2 exd5 cxd5 Re8 e5 dxe5 fxe5 Ng4 Bg5 Qb6 O-O Nxe5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4 O-O Nf3 c5 dxc5 Qa5 Bd3 Qxc5 Qe2 Nc6 Be3 Qa5',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4 O-O Nf3 c5 d5 e6 dxe6 fxe6 Be2 Nc6 O-O e5',
      // ── Fianchetto systems ──────────────────────────────────────────────
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O O-O Nbd7 Nc3 e5 e4 c6 h3 Qb6 Re1 exd4 Nxd4 Re8',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O O-O Nbd7 Nc3 e5 e4 c6 d5 c5 Ne1 Ne8 Nd3 f5',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O O-O Nbd7 Nc3 e5 h3 Qe8 e4 exd4 Nxd4 Nc5',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O O-O Nbd7 Qc2 e5 Rd1 Re8 Nc3 c6 b3 Qe7',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O Nc3 Nbd7 O-O e5 e4 c6 h3 Qb6 Re1 exd4',
      'd4 Nf6 c4 g6 g3 Bg7 Bg2 d6 Nc3 O-O Nf3 Nbd7 O-O e5 e4 c6 h3 Qb6',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O O-O Nbd7 b3 e5 Bb2 Re8 Nc3 c6 e4 Qb6',
      // ── Other move orders and first moves ───────────────────────────────
      'd4 Nf6 Nf3 g6 c4 Bg7 Nc3 d6 e4 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7',
      'd4 Nf6 Nf3 g6 Bf4 Bg7 e3 d6 Be2 O-O h3 Nbd7 O-O Qe8 c4 e5 Bh2 Qe7',
      'd4 Nf6 Nf3 g6 Bg5 Bg7 Nbd2 d6 e4 O-O c3 Nbd7 Bc4 e5 O-O h6',
      'd4 Nf6 Nf3 g6 e3 Bg7 Be2 d6 O-O O-O c4 Nbd7 Nc3 e5 b3 Re8',
      'd4 Nf6 Nf3 g6 g3 Bg7 Bg2 d6 O-O O-O c4 Nbd7 Nc3 e5 e4 c6 h3 Qb6',
      'd4 Nf6 Nf3 g6 c4 Bg7 Nc3 d6 Bg5 h6 Bh4 O-O e3 c5 Be2 cxd4 exd4 Nc6',
      'd4 Nf6 Bg5 Ne4 Bf4 d5 e3 c5 Bd3 Nc6 Nf3 Qb6 Qc1 Bf5 c3 e6',
      'd4 Nf6 Bf4 g6 e3 Bg7 Nf3 d6 Be2 O-O h3 Nbd7 O-O Qe8 c4 e5 Bh2 Qe7',
      'd4 Nf6 Nc3 g6 Bf4 d6 e3 Bg7 Be2 O-O Nf3 Nbd7 h3 e5 Bh2 Qe7',
      'd4 Nf6 Nc3 g6 e4 d6 f4 Bg7 Nf3 O-O Bd3 Na6 O-O c5',
      'd4 Nf6 e3 g6 Nf3 Bg7 Be2 d6 O-O O-O c4 Nbd7 Nc3 e5 b3 Re8',
      'd4 Nf6 g3 g6 Bg2 Bg7 Nf3 d6 O-O O-O c4 Nbd7 Nc3 e5 e4 c6',
      'd4 Nf6 f3 d5 e4 dxe4 Nc3 exf3 Nxf3 g6 Bc4 Bg7 O-O O-O',
      'd4 Nf6 c4 g6 Nc3 Bg7 g3 d6 Bg2 O-O Nf3 Nbd7 O-O e5 e4 c6 h3 Qb6',
      'c4 Nf6 Nc3 g6 e4 d6 d4 Bg7 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7',
      'c4 Nf6 Nc3 g6 g3 Bg7 Bg2 d6 Nf3 O-O O-O Nbd7 d4 e5 e4 c6 h3 Qb6',
      'c4 Nf6 g3 g6 Bg2 Bg7 Nc3 d6 Nf3 O-O O-O Nbd7 d4 e5 e4 c6 h3 Qb6',
      'c4 Nf6 Nf3 g6 Nc3 Bg7 e4 d6 d4 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7',
      'Nf3 Nf6 c4 g6 Nc3 Bg7 e4 d6 d4 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7',
      'Nf3 Nf6 d4 g6 c4 Bg7 Nc3 d6 e4 O-O Be2 e5 O-O Nc6 d5 Ne7 Ne1 Nd7',
      'Nf3 Nf6 g3 g6 Bg2 Bg7 O-O O-O d3 d6 e4 e5 Nc3 Nc6 Rb1 a5',
      'Nf3 Nf6 c4 g6 b3 Bg7 Bb2 d6 g3 O-O Bg2 e5 d3 Nc6 O-O a5',
      'g3 Nf6 Bg2 g6 Nf3 Bg7 O-O O-O d3 d6 e4 e5 Nc3 Nc6 Rb1 a5',
      'b3 Nf6 Bb2 g6 g3 Bg7 Bg2 d6 Nf3 O-O O-O e5 d3 Nc6 Nbd2 a5',
      'f4 Nf6 Nf3 g6 g3 Bg7 Bg2 d6 O-O O-O d3 Nc6 Nc3 e5 fxe5 dxe5',
      'b4 Nf6 Bb2 g6 Nf3 Bg7 e3 d6 Be2 O-O O-O e5 d3 Nbd7 Nbd2 a5',
    ],
    notes: {
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7':
        'The Mar del Plata tabiya and the heart of the whole repertoire. Your pieces go ...Ne8/...Nd7, ...f5-f4, ...g5-g4, and you never look at the queenside. If White breaks through on c7 first you are simply lost — commit fully.',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7 b4':
        'Bayonet Attack, the critical modern try. ...Nh5 and ...f5 fast; the Ne6 exchange sacrifice is the main line and you should know it rather than meet it over the board.',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 dxe5':
        'Exchange Variation. Queens come off and White hopes you have nothing to attack. Play for ...Nd4 and the dark squares; a draw is not automatic for either side.',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f3 O-O Be3 e5 d5 Nh5':
        'Sämisch. ...Nh5 stops g4 ideas and prepares ...f5. White castles long, so the attack is mutual — your ...b5 comes with the a- and b-files opening.',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Be2 O-O Bg5 c5':
        'Averbakh. The reason to hit the centre with ...c5 instead of ...e5 is that Bg5 has taken the bite out of ...e5; you transpose into a favourable Benoni.',
      'd4 Nf6 c4 g6 Nc3 Bg7 e4 d6 f4 O-O Nf3 c5':
        'Four Pawns. Do not let the centre scare you — it is overextended, and ...c5 followed by ...e6 hits it before White finishes developing.',
      'd4 Nf6 c4 g6 Nf3 Bg7 g3 d6 Bg2 O-O O-O Nbd7 Nc3 e5':
        'Fianchetto Variation, the most respectable anti-KID system. The g2 bishop takes the sting out of a kingside attack, so play in the centre first and reach for ...f5 only when it works.',
      'd4 Nf6 Nf3 g6 Bf4 Bg7 e3 d6 Be2 O-O h3 Nbd7 O-O Qe8':
        'London. ...Qe8 and ...e5 is the cleanest set-up: you get the ...e5 break in without allowing the Bf4 pin to matter.',
    },
  },
];
