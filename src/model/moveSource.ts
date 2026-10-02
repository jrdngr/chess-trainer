import { lookup, type ReferenceIndex } from './reference';
import type { MoveSource, RepMove, Repertoire } from './types';

/**
 * Where a move came from, said in one word or two.
 *
 * Every way into a repertoire has its own label, because "added by you" lumps
 * a move typed in by hand with a line saved from your own games, and the two
 * say different things about how often you will meet it.
 */
export const SOURCE_LABELS: Record<MoveSource, string> = {
  picker: 'Opening picker',
  book: 'Book',
  growth: 'Growth',
  engine: 'Engine',
  manual: 'Entered by hand',
  analysis: 'Analysis',
  import: 'Imported games',
  play: 'Play game',
  tidy: 'Tidy switch',
  seed: 'Sample',
};

export function sourceLabel(source: MoveSource | undefined): string {
  return SOURCE_LABELS[source ?? 'manual'] ?? SOURCE_LABELS.manual;
}

/** Sources that came from strong players' games or the engine, rather than from you. */
const FROM_BOOK: ReadonlySet<MoveSource> = new Set(['picker', 'book', 'growth', 'engine', 'seed']);

/** You chose to put this move in, rather than taking it from the book or the engine. */
export function addedByYou(source: MoveSource | undefined): boolean {
  return !FROM_BOOK.has(source ?? 'manual');
}

/** The book has this move here. */
export function inBook(index: ReferenceIndex, fen: string, san: string): boolean {
  return (lookup(index, fen)?.moves ?? []).some((move) => move.san === san);
}

/** Growth's label for a move: Growth for the book's, Engine past it. */
export function growthSource(index: ReferenceIndex) {
  return (fen: string, san: string): MoveSource => (inBook(index, fen, san) ? 'growth' : 'engine');
}

/** The values saved before the labels were split up. */
type LegacySource = 'reference' | 'pgn' | 'games';

/**
 * Bring saved moves onto the current labels. The old values covered several
 * ways in each, so this is a best reading, not a record:
 *
 * - `reference` was the opening picker, the book list and Growth alike, and
 *   none of them can be told apart now. A move the book has is Book; one it
 *   lacks can only have come from Growth past the book, so it is Engine.
 * - `pgn` was only ever Analysis.
 * - `games` was Play's save and the Import screen. Imported games, if there
 *   are any, are the likelier source; otherwise it was Play.
 * - `manual` was the Repertoire tab's board and Tidy's switch; the board is far
 *   the commoner, so it stays Entered by hand.
 */
export function normalizeSources(
  repertoires: Record<string, Repertoire>,
  index: ReferenceIndex,
  hasImports: boolean,
): Record<string, Repertoire> {
  let changed = false;
  const out: Record<string, Repertoire> = {};
  for (const [id, rep] of Object.entries(repertoires)) {
    let nodes: Record<string, RepMove> | null = null;
    for (const node of Object.values(rep.nodes)) {
      const next = upgrade(node, index, hasImports);
      if (next === node.source) continue;
      nodes ??= { ...rep.nodes };
      nodes[node.id] = { ...node, source: next };
    }
    out[id] = nodes ? { ...rep, nodes } : rep;
    changed ||= !!nodes;
  }
  return changed ? out : repertoires;
}

function upgrade(node: RepMove, index: ReferenceIndex, hasImports: boolean): MoveSource {
  const source = node.source as MoveSource | LegacySource | undefined;
  switch (source) {
    case 'reference':
      return inBook(index, node.fenBefore, node.san) ? 'book' : 'engine';
    case 'pgn':
      return 'analysis';
    case 'games':
      return hasImports ? 'import' : 'play';
    case undefined:
      return 'manual';
    default:
      return source;
  }
}
