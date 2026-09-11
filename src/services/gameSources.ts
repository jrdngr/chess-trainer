import { mainline, parsePgn } from '../chess/pgn';
import type { Color } from '../chess/core';
import type { ImportedGame } from '../model/types';

export type SourceId = 'lichess' | 'chesscom';

export interface FetchOptions {
  username: string;
  /** Upper bound on games returned. */
  max?: number;
  signal?: AbortSignal;
}

export type FetchResult =
  | { ok: true; games: ImportedGame[] }
  | { ok: false; reason: 'not-found' | 'network' | 'blocked' | 'rate-limited' | 'empty'; message: string };

/**
 * Live clients for the two public game APIs.
 *
 * These work when the app runs from a normal origin (`npm run dev`, or any
 * static host). A published Claude Artifact runs under a CSP that blocks all
 * cross-origin requests, so there the call fails before it leaves the page and
 * the UI falls back to PGN paste or the bundled sample archive. `reason:
 * 'blocked'` is how that case is reported.
 */
function classify(err: unknown): { reason: 'network' | 'blocked'; message: string } {
  const text = err instanceof Error ? err.message : String(err);
  // A CSP refusal surfaces as a generic TypeError with no status.
  if (/Failed to fetch|NetworkError|Load failed|blocked/i.test(text)) {
    return {
      reason: 'blocked',
      message:
        'The browser blocked the request before it was sent. This happens inside the Claude Artifact sandbox, which does not allow cross-origin requests. Paste a PGN instead, or run the app locally.',
    };
  }
  return { reason: 'network', message: text };
}

function colorOf(game: { white: string; black: string }, username: string): Color | null {
  const u = username.trim().toLowerCase();
  if (game.white.toLowerCase() === u) return 'w';
  if (game.black.toLowerCase() === u) return 'b';
  return null;
}

/** Turn a PGN blob into importable games, tagging which side the user had. */
export function gamesFromPgn(
  pgn: string,
  username: string,
  source: ImportedGame['source'] = 'pgn',
): ImportedGame[] {
  const parsed = parsePgn(pgn);
  const out: ImportedGame[] = [];
  parsed.forEach((game, i) => {
    const moves = mainline(game);
    if (!moves.length) return;
    const white = game.headers.White ?? 'White';
    const black = game.headers.Black ?? 'Black';
    out.push({
      id: `${source}_${game.headers.Site ?? ''}_${i}`,
      source,
      white,
      black,
      result: game.result,
      userColor: colorOf({ white, black }, username),
      timeControl: game.headers.TimeControl,
      date: game.headers.UTCDate ?? game.headers.Date,
      opening: game.headers.Opening,
      moves,
      url: game.headers.Site?.startsWith('http') ? game.headers.Site : undefined,
    });
  });
  return out;
}

export async function fetchLichessGames(opts: FetchOptions): Promise<FetchResult> {
  const { username, max = 100, signal } = opts;
  const url = `https://lichess.org/api/games/user/${encodeURIComponent(
    username,
  )}?max=${max}&rated=true&perfType=blitz,rapid,classical&clocks=false&evals=false&opening=true`;
  try {
    const res = await fetch(url, { headers: { Accept: 'application/x-chess-pgn' }, signal });
    if (res.status === 404) {
      return { ok: false, reason: 'not-found', message: `No Lichess account called "${username}".` };
    }
    if (res.status === 429) {
      return { ok: false, reason: 'rate-limited', message: 'Lichess is rate limiting; try again in a minute.' };
    }
    if (!res.ok) return { ok: false, reason: 'network', message: `Lichess returned ${res.status}.` };
    const pgn = await res.text();
    const games = gamesFromPgn(pgn, username, 'lichess');
    if (!games.length) return { ok: false, reason: 'empty', message: 'No rated games found for that account.' };
    return { ok: true, games };
  } catch (err) {
    const { reason, message } = classify(err);
    return { ok: false, reason, message };
  }
}

export async function fetchChesscomGames(opts: FetchOptions): Promise<FetchResult> {
  const { username, max = 100, signal } = opts;
  const user = encodeURIComponent(username.trim().toLowerCase());
  try {
    const archivesRes = await fetch(`https://api.chess.com/pub/player/${user}/games/archives`, { signal });
    if (archivesRes.status === 404) {
      return { ok: false, reason: 'not-found', message: `No Chess.com account called "${username}".` };
    }
    if (!archivesRes.ok) {
      return { ok: false, reason: 'network', message: `Chess.com returned ${archivesRes.status}.` };
    }
    const { archives } = (await archivesRes.json()) as { archives: string[] };
    const games: ImportedGame[] = [];

    // Newest months first, until we have enough games.
    for (const archiveUrl of [...archives].reverse()) {
      if (games.length >= max) break;
      const monthRes = await fetch(archiveUrl, { signal });
      if (!monthRes.ok) continue;
      const body = (await monthRes.json()) as {
        games: { pgn?: string; time_control?: string; url?: string; rules?: string }[];
      };
      for (const g of body.games ?? []) {
        if (!g.pgn || (g.rules && g.rules !== 'chess')) continue;
        const parsed = gamesFromPgn(g.pgn, username, 'chesscom');
        for (const p of parsed) games.push({ ...p, url: g.url ?? p.url });
      }
    }

    if (!games.length) return { ok: false, reason: 'empty', message: 'No games found for that account.' };
    return { ok: true, games: games.slice(0, max) };
  } catch (err) {
    const { reason, message } = classify(err);
    return { ok: false, reason, message };
  }
}

export function fetchGames(source: SourceId, opts: FetchOptions): Promise<FetchResult> {
  return source === 'lichess' ? fetchLichessGames(opts) : fetchChesscomGames(opts);
}
