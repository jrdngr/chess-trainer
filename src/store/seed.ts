import { walkSan } from '../chess/core';
import { addLine, createRepertoire, setNote } from '../model/repertoire';
import { SEED_REPERTOIRES } from '../model/seed/repertoires';
import type { Repertoire } from '../model/types';

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
    return rep;
  });
}
