/**
 * Mistakes made inside the app.
 *
 * Repair was built on imported games, but a game played against the engine in
 * Play, a line lost in Opening Run and a move missed in Drill are all the same
 * thing: a position where what you played disagreed with what you prepared.
 * They are worth exactly as much as an imported game — more, if anything, since
 * they happened just now — so they are logged here and Repair reads them
 * alongside the archive.
 */

export type MistakeSource = 'drill' | 'openingRun' | 'play';

export interface Mistake {
  id: string;
  /** When it happened, so the most recent can be asked about first. */
  at: number;
  source: MistakeSource;
  repertoireId: string;
  /** positionKey of the position it was made in. */
  key: string;
  fen: string;
  /** SAN path to the position, when the mode knows it. */
  path?: string[];
  played: string;
  expected: string;
}

/**
 * How many to keep. Enough that a long session's worth survives, few enough
 * that the synced document stays small.
 */
export const MISTAKE_LIMIT = 200;

export function sourceLabel(source: MistakeSource): string {
  switch (source) {
    case 'play':
      return 'a game you played';
    case 'openingRun':
      return 'an opening run';
    default:
      return 'a drill';
  }
}

/**
 * Add one, newest last, replacing any earlier miss at the same position.
 *
 * Missing the same position twice is one thing to fix, not two, and keeping
 * only the latest means the record shows what you played most recently rather
 * than the first time you ever went wrong.
 */
export function addMistake(log: Mistake[], mistake: Omit<Mistake, 'id' | 'at'>): Mistake[] {
  const at = Date.now();
  const entry: Mistake = {
    ...mistake,
    at,
    id: `${mistake.repertoireId}#${mistake.key}`,
  };
  const rest = log.filter((m) => m.id !== entry.id);
  return [...rest, entry].slice(-MISTAKE_LIMIT);
}

/** Mistakes still worth asking about, newest first. */
export function recentMistakes(log: Mistake[], repertoireId?: string): Mistake[] {
  return log
    .filter((m) => !repertoireId || m.repertoireId === repertoireId)
    .slice()
    .sort((a, b) => b.at - a.at);
}
