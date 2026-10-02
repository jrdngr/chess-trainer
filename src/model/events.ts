import type { Color } from '../chess/core';
import { leafLines, pathTo } from './repertoire';
import type { Repertoire } from './types';

/**
 * A log of what changed the repertoire, and what Growth put in front of you.
 *
 * The repertoire says what your prep is, never how it got that way: a reply
 * left with no answer after it could be a delete, a Tidy switch, or a line
 * that was never finished, and nothing in the saved state tells them apart.
 * This is the record that does. It is data for diagnosing, not a screen —
 * synced with everything else, and in Export as JSON.
 */

/** Where in the app an event came from. */
export type EventPlace =
  | 'home'
  | 'repertoire'
  | 'tidy'
  | 'analysis'
  | 'stats'
  | 'growth'
  | 'autopilot'
  | 'survival'
  | 'drill'
  | 'repair'
  | 'play'
  | 'import'
  | 'onboarding'
  | 'session'
  | 'unknown';

interface Base {
  at: number;
  /** Where it happened. */
  via: EventPlace;
}

interface RepertoireBase extends Base {
  repertoireId: string;
  color: Color;
}

export type AppEvent =
  /** Moves written into a tree. `line` is the whole line, `added` how many of it were new. */
  | (RepertoireBase & { kind: 'add'; line: string; added: number; source: string })
  /**
   * A move and everything after it deleted. `removed` is every line that went,
   * as far as it went (capped), and `count` how many moves.
   */
  | (RepertoireBase & { kind: 'remove'; line: string; removed: string[]; count: number })
  /** A derived opening deleted, with the move order that only led to it. */
  | (RepertoireBase & { kind: 'remove-opening'; line: string; removed: string[]; count: number })
  /** A whole side's tree deleted. */
  | (RepertoireBase & { kind: 'remove-repertoire'; count: number })
  /** A move made the preferred one at its position. */
  | (RepertoireBase & { kind: 'prefer'; line: string })
  /** A note written on a move. */
  | (RepertoireBase & { kind: 'note'; line: string })
  /** A move moved up or down among its siblings. */
  | (RepertoireBase & { kind: 'reorder'; line: string; delta: number })
  /** Tidy played another move in place of yours: `line` ends on yours, `to` is the switch. */
  | (RepertoireBase & { kind: 'tidy-switch'; line: string; to: string; removed: string[]; count: number })
  /** A Tidy switch taken back. */
  | (RepertoireBase & { kind: 'tidy-undo'; line: string; to: string })
  /** A reply strong players rarely choose, kept from Tidy's card: `line` ends on it. */
  | (RepertoireBase & { kind: 'tidy-keep'; line: string })
  /** That reply removed from Tidy's card, with everything under it. */
  | (RepertoireBase & { kind: 'tidy-remove'; line: string; removed: string[]; count: number })
  /** A Tidy remove taken back. */
  | (RepertoireBase & { kind: 'tidy-remove-undo'; line: string })
  /** The Growth lobby's Start or a row picked: every row it listed, and the one chosen. */
  | (Base & { kind: 'growth-start'; rows: string[]; picked: string; start: string })
  /**
   * Growth asking you to answer a reply: the line to it, what was offered,
   * and where the offer came from.
   */
  | (Base & {
      kind: 'growth-offer';
      color: Color;
      line: string;
      offered: string[];
      from: 'book' | 'engine' | 'kept';
    })
  /** An answer Growth wrote in, and what else was on offer beside it. */
  | (Base & { kind: 'growth-pick'; color: Color; line: string; picked: string; offered: string[] })
  /** Growth's Undo or Undo all. */
  | (Base & { kind: 'growth-undo'; color: Color; line: string; all: boolean });

/** Distribute Omit over the union, so each kind keeps its own fields. */
type Without<T, K extends keyof never> = T extends unknown ? Omit<T, K> : never;
export type NewEvent = Without<AppEvent, 'at' | 'via'> & { via?: EventPlace };

/** How many events are kept: enough for weeks of use, small enough to sync. */
export const EVENT_CAP = 1000;
/** How many removed lines one event lists; the count says how many moves went in all. */
export const REMOVED_CAP = 20;

let place: EventPlace = 'unknown';

/** Where the app is now, for events that do not say. Set by the app shell as you move around. */
export function setEventPlace(next: EventPlace): void {
  place = next;
}

export function eventPlace(): EventPlace {
  return place;
}

/** The log with one more event on the end, the oldest dropped past the cap. */
export function appendEvent(events: AppEvent[], event: NewEvent, now = Date.now()): AppEvent[] {
  const full = { ...event, at: now, via: event.via ?? place } as AppEvent;
  return [...events.slice(-(EVENT_CAP - 1)), full];
}

/** A saved log, whatever shape it arrived in. */
export function normalizeEvents(saved: unknown): AppEvent[] {
  return Array.isArray(saved) ? (saved.slice(-EVENT_CAP) as AppEvent[]) : [];
}

/** A node's line from the start, as moves. */
export function lineAt(rep: Repertoire, nodeId: string | null): string {
  return pathTo(rep, nodeId)
    .map((move) => move.san)
    .join(' ');
}

/**
 * What went between two versions of a tree: every line of the old one that
 * lost a move, whole, and how many moves went in all.
 */
export function removedBetween(before: Repertoire, after: Repertoire): { removed: string[]; count: number } {
  const gone = (id: string) => !after.nodes[id];
  const count = Object.keys(before.nodes).filter(gone).length;
  const removed = leafLines(before)
    .filter((leaf) => gone(leaf.tipId))
    .map((leaf) => leaf.sans.join(' '))
    .slice(0, REMOVED_CAP);
  return { removed, count };
}
