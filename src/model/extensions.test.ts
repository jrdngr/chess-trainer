import { describe, expect, it } from 'vitest';
import { walkSan } from '../chess/core';
import { bookLength, lineKinds, moveKind, treeKinds } from './extensions';
import { referenceIndex } from './referenceIndex';
import { addLine, createRepertoire, recordLosses } from './repertoire';

const index = referenceIndex();
const at = (line: string) => walkSan(line ? line.split(' ') : []).fens.at(-1)!;
const ITALIAN = 'e4 e5 Nf3 Nc6 Bc4 Bc5';

describe('what kind of move it is', () => {
  it('is a book move when strong players choose it often enough', () => {
    expect(moveKind(index, at(ITALIAN), 'c3')).toBe('book');
  });

  it('is rare when the book has it, but seldom', () => {
    // 2.Qh5 is in the book against 1...e5, far below the share a book move needs.
    expect(moveKind(index, at('e4 e5'), 'Qh5')).toBe('rare');
  });

  it('is past the book where the book has no games at all', () => {
    expect(moveKind(index, at('a4 h5 b4 g5 c4 f5'), 'd4')).toBe('past');
  });

  it('is a mistake once the engine has said it gives too much away', () => {
    expect(moveKind(index, at(ITALIAN), 'c3', 150)).toBe('mistake');
    expect(moveKind(index, at(ITALIAN), 'c3', 30)).toBe('book');
  });
});

describe('a line by kind', () => {
  it('is an extension from where it leaves the book, everything under it included', () => {
    // A reply the book would play after 2.Qh5 is still an extension: the line has left the book.
    const kinds = lineKinds(index, 'e4 e5 Qh5 Nc6 Bc4'.split(' '));
    expect(kinds.slice(0, 2)).toEqual(['book', 'book']);
    expect(kinds[2]).toBe('rare');
    expect(kinds.slice(3).every((kind) => kind !== 'book')).toBe(true);
    expect(bookLength(kinds)).toBe(2);
  });

  it('is all book when it never leaves it', () => {
    const sans = ITALIAN.split(' ');
    expect(bookLength(lineKinds(index, sans))).toBe(sans.length);
  });

  it('reads a tree the same way, with the engine\'s word kept on its moves', () => {
    let rep = createRepertoire('White Playbook', 'w', 'w');
    rep = addLine(rep, `${ITALIAN} d3 Nf6 Ng5`.split(' '), 'board').rep;
    rep = recordLosses(rep, `${ITALIAN} d3 Nf6 Ng5`.split(' '), [, , , , , , , , 120]);
    const kinds = treeKinds(rep, index);
    const kindOf = (san: string) => kinds.get(Object.values(rep.nodes).find((n) => n.san === san)!.id);
    expect(kindOf('Bc5')).toBe('book');
    expect(kindOf('Ng5')).toBe('mistake');
  });
});
