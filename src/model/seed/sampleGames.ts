import { applySan, fenTurn, START_FEN } from '../../chess/core';
import { lookup } from '../reference';
import { referenceIndex } from '../referenceIndex';
import { mulberry32 } from '../session';
import type { ImportedGame } from '../types';

/**
 * A stand-in game archive for the import flow.
 *
 * Real archives come from the Lichess and Chess.com APIs (see
 * `services/gameSources.ts`). Those APIs are unreachable from a published
 * artifact because the page's CSP blocks cross-origin requests, so this
 * generator produces a believable archive — walked from the reference tree with
 * a fixed seed — for the positions where the flow needs data to chew on.
 *
 * Everything here is synthetic. Opponent names are deliberately generic.
 */
const OPPONENTS = [
  'kn1ghtrider', 'pawnstorm88', 'Bishop_Takes', 'rookandroll', 'endgame_enjoyer',
  'zugzwangie', 'TheQueensGambit', 'fianchetto_fan', 'blunder_buss', 'TempoLoss',
  'PassedPawnPete', 'perpetual_check', 'OpenFile', 'luft_or_bust', 'Prophylaxis',
  'timescramble', 'ZwischenZug', 'flagfall', 'DoubledPawns', 'MinorPiece',
];

const TIME_CONTROLS = ['180+0', '300+0', '300+3', '600+0', '600+5', '900+10'];

/** Moves this fictional player reaches for, with a multiplier on their weight. */
const PLAYER_BIAS: Record<string, number> = {
  // As White: a committed 1.e4 player who mostly plays the Open Sicilian.
  e4: 14, Nf3: 0.5, c4: 0.4, d4: 0.6,
  Bb5: 0.8, Be3: 3, Bg5: 1.4, Bc4: 0.6,
  // As Black: Najdorf against 1.e4, Nimzo/QID against 1.d4.
  c5: 10, a6: 8, Nf6: 3, e6: 2.5, Bb4: 6, d6: 4,
  // Moves this player drifts into despite their prep — the interesting cases.
  Nc6: 1.4, g6: 1.2, e5: 2,
};

interface Choice {
  san: string;
  weight: number;
}

export interface SampleArchiveOptions {
  username: string;
  count?: number;
  seed?: number;
  source?: 'lichess' | 'chesscom';
  /** How often the player has White. */
  whiteShare?: number;
}

export function generateSampleArchive(opts: SampleArchiveOptions): ImportedGame[] {
  const { username, count = 60, seed = 20240611, source = 'lichess', whiteShare = 0.5 } = opts;
  const index = referenceIndex();
  const rand = mulberry32(seed);
  const games: ImportedGame[] = [];

  for (let i = 0; i < count; i += 1) {
    const userIsWhite = rand() < whiteShare;
    const userColor = userIsWhite ? 'w' : 'b';
    const moves: string[] = [];
    let fen = START_FEN;
    const maxPlies = 12 + Math.floor(rand() * 12);

    while (moves.length < maxPlies) {
      const entry = lookup(index, fen);
      if (!entry?.moves.length) break;
      const isUserMove = fenTurn(fen) === userColor;
      const choices: Choice[] = [];
      for (const row of entry.moves) {
        const move = applySan(fen, row.san);
        if (!move) continue;
        const bias = isUserMove ? (PLAYER_BIAS[row.san] ?? 1) : 1;
        choices.push({ san: move.san, weight: Math.max(0.01, row.games * bias) });
      }
      if (!choices.length) break;

      const total = choices.reduce((s, c) => s + c.weight, 0);
      let roll = rand() * total;
      let picked = choices[choices.length - 1];
      for (const c of choices) {
        roll -= c.weight;
        if (roll <= 0) {
          picked = c;
          break;
        }
      }
      const move = applySan(fen, picked.san)!;
      moves.push(move.san);
      fen = move.after;
    }

    const opponent = OPPONENTS[Math.floor(rand() * OPPONENTS.length)];
    const roll = rand();
    const userWon = roll < 0.47;
    const drawn = roll >= 0.47 && roll < 0.58;
    const result = drawn ? '1/2-1/2' : userWon === userIsWhite ? '1-0' : '0-1';
    const daysAgo = Math.floor((i / count) * 120) + Math.floor(rand() * 3);
    const date = new Date(Date.now() - daysAgo * 86_400_000).toISOString().slice(0, 10);

    games.push({
      id: `sample_${i}`,
      source,
      white: userIsWhite ? username : opponent,
      black: userIsWhite ? opponent : username,
      result,
      userColor,
      timeControl: TIME_CONTROLS[Math.floor(rand() * TIME_CONTROLS.length)],
      date,
      moves,
    });
  }

  return games.sort((a, b) => (a.date! < b.date! ? 1 : -1));
}
