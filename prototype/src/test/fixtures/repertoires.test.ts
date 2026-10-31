import { describe, expect, it } from 'vitest';
import { Chess } from 'chess.js';
import { SEED_REPERTOIRES } from './repertoires';
import { fenTurn, positionKey, walkSan } from '../../chess/core';

describe('seed repertoires', () => {
  for (const rep of SEED_REPERTOIRES) {
    describe(rep.name, () => {
      it('has only legal lines', () => {
        const bad: string[] = [];
        for (const line of rep.lines) {
          const c = new Chess();
          for (const san of line.split(' ')) {
            try {
              c.move(san);
            } catch {
              bad.push(`${san} in "${line}"`);
              break;
            }
          }
        }
        expect(bad).toEqual([]);
      });

      it('every line ends on the opponent to move', () => {
        // A line should finish with the user's move, so the next turn is theirs.
        const bad = rep.lines.filter((line) => {
          const fen = walkSan(line.split(' ')).fens.at(-1)!;
          return fenTurn(fen) === rep.color;
        });
        expect(bad).toEqual([]);
      });

      it('never prescribes two different moves for the user in one position', () => {
        // A repertoire is a set of decisions, not a menu: the breadth belongs
        // on the opponent's side of the tree.
        const choices = new Map<string, Set<string>>();
        for (const line of rep.lines) {
          const sans = line.split(' ');
          const { fens } = walkSan(sans);
          sans.forEach((san, i) => {
            if (i >= fens.length - 1) return;
            if (fenTurn(fens[i]) !== rep.color) return;
            const key = positionKey(fens[i]);
            const set = choices.get(key) ?? new Set<string>();
            set.add(san);
            choices.set(key, set);
          });
        }
        const forks = [...choices.entries()]
          .filter(([, set]) => set.size > 1)
          .map(([key, set]) => `${key} -> ${[...set].join('/')}`);
        expect(forks).toEqual([]);
      });

      it('has notes that point at real positions', () => {
        const bad: string[] = [];
        for (const prefix of Object.keys(rep.notes ?? {})) {
          const sans = prefix.split(' ');
          if (walkSan(sans).moves.length !== sans.length) bad.push(prefix);
        }
        expect(bad).toEqual([]);
      });
    });
  }
});
