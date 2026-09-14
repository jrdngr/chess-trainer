import { applySan, fenTurn, positionKey, walkSan, START_FEN } from '../chess/core';
import { findGaps } from '../model/gaps';
import { lookup, totalGamesAt, type ReferenceIndex } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { addLine, childrenOf, createRepertoire, setNote } from '../model/repertoire';
import { SEED_REPERTOIRES } from '../model/seed/repertoires';
import type { Repertoire } from '../model/types';

/**
 * What the fixtures promise: an answer to anything played this often.
 *
 * The same number `coverage.test.ts` checks against, and the reason coverage is
 * completed from the book rather than by hand. The authored lines give each
 * repertoire its character — the Exchange QGD move order, the Soltis Dragon —
 * and the book fills in every mainstream reply nobody thought to write down.
 * Authoring that by hand against a real book is days of work that would need
 * redoing on every recrawl.
 */
export const COVER_MIN_SHARE = 3;
const COVER_MAX_PLY = 18;

/** The book's most-played move here. */
function bestMove(index: ReferenceIndex, fen: string): string | null {
  const entry = lookup(index, fen);
  return entry?.moves.length ? entry.moves[0].san : null;
}

/**
 * The move this repertoire already plays in each position it decides.
 *
 * Keyed by position rather than by line, because that is what makes the answer
 * the same however the position was reached — the same collapsing drilling
 * does.
 */
function decisions(rep: Repertoire): Map<string, string> {
  const own = new Map<string, string>();
  for (const node of Object.values(rep.nodes)) {
    if (fenTurn(node.fenBefore) === rep.color) own.set(node.key, node.san);
  }
  return own;
}

/**
 * Carry a line on from the position a gap leaves off at.
 *
 * Where the repertoire has already decided a position, the extension plays that
 * decision — a repertoire is a set of decisions, not a menu, and a line that
 * transposed into a decided position and then answered it differently would put
 * two of the player's moves in one place. Only where there is no decision yet
 * does the book choose, and then it plays the most popular move.
 *
 * For the opponent the book's most popular move is only the most likely
 * continuation; the replies it passes over come back as gaps of their own on
 * the next pass.
 */
function continueLine(
  rep: Repertoire,
  own: Map<string, string>,
  index: ReferenceIndex,
  fen: string,
  fromPly: number,
): string[] {
  const sans: string[] = [];
  let here = fen;
  for (let ply = fromPly; ply < COVER_MAX_PLY; ply += 1) {
    const mine = fenTurn(here) === rep.color;
    const san = (mine ? own.get(positionKey(here)) : null) ?? bestMove(index, here);
    if (!san) break;
    const move = applySan(here, san);
    if (!move) break;
    sans.push(move.san);
    here = move.after;
  }
  return sans;
}

/**
 * Extend a repertoire until nothing the world plays often goes unanswered.
 *
 * Each pass patches the gaps `findGaps` reports and the patches open shallower
 * gaps of their own, so it runs to a fixed point rather than once.
 */
function coverGaps(rep: Repertoire, index: ReferenceIndex): Repertoire {
  for (let pass = 0; pass < 24; pass += 1) {
    const gaps = findGaps(rep, index, { minShare: COVER_MIN_SHARE, maxPly: COVER_MAX_PLY });
    if (!gaps.length) return rep;
    // Rebuilt every pass: the lines added last pass are decisions too.
    const own = decisions(rep);
    for (const gap of gaps) {
      const ply = gap.path.length + 1;
      const line = [...gap.path, gap.san, ...continueLine(rep, own, index, gap.after, ply)];
      rep = addLine(rep, line, 'seed').rep;
    }
  }
  return rep;
}

/**
 * Meet every first move the world plays, for a repertoire that claims it.
 *
 * `findGaps` deliberately says nothing about the opening position — which first
 * moves a Black player must answer is a question about their repertoires taken
 * together, not about any one of them — so responsibility is declared in the
 * seed data and discharged here.
 */
function meetFirstMoves(rep: Repertoire, index: ReferenceIndex, meets: string[]): Repertoire {
  const start = lookup(index, START_FEN);
  const total = totalGamesAt(start);
  const answered = new Set(childrenOf(rep, null).map((node) => node.san));
  for (const san of meets) {
    if (answered.has(san)) continue;
    const move = applySan(START_FEN, san);
    const played = start?.moves.find((m) => m.san === san);
    if (!move || !played || (played.games / total) * 100 < COVER_MIN_SHARE) continue;
    const own = decisions(rep);
    rep = addLine(rep, [move.san, ...continueLine(rep, own, index, move.after, 1)], 'seed').rep;
  }
  return rep;
}

/**
 * Build repertoires from the seed data.
 *
 * Nothing in the app calls this any more — a new install starts with no
 * repertoires at all, because seeded lines were somebody else's openings and
 * every other mode then measured the player against prep they had not chosen.
 * It stays as the fixture the model tests are written against: three real,
 * legal, reasonably deep repertoires are exactly what those tests need, and
 * building them from the same code the app uses keeps the fixture honest.
 */
export function buildSeedRepertoires(): Repertoire[] {
  const index = referenceIndex();
  return SEED_REPERTOIRES.map((seed) => {
    let rep = createRepertoire(seed.name, seed.color, seed.id);
    for (const line of seed.lines) {
      rep = addLine(rep, line.split(' '), 'seed').rep;
    }
    // Attach notes by walking to the position each note describes.
    for (const [prefix, note] of Object.entries(seed.notes ?? {})) {
      const sans = prefix.split(' ');
      const { moves } = walkSan(sans);
      if (moves.length !== sans.length) continue;
      const target = Object.values(rep.nodes).find(
        (n) => n.san === sans[sans.length - 1] && n.fenAfter === moves[moves.length - 1].after,
      );
      if (target) rep = setNote(rep, target.id, note);
    }
    if (seed.meets?.length) rep = meetFirstMoves(rep, index, seed.meets);
    return coverGaps(rep, index);
  });
}
