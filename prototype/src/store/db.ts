import { del, get, set } from 'idb-keyval';

const KEY = 'chess-repertoire-trainer:v1';

/**
 * Whether this page can persist anything locally at all.
 *
 * Artifacts are framed with a sandbox that withholds `allow-same-origin`, which
 * makes the frame's origin opaque: touching `localStorage` or `indexedDB` there
 * throws `SecurityError` rather than returning empty. Everything below already
 * swallows that, so the app keeps working — but it would forget on every open,
 * silently. Callers probe first and say so.
 */
export interface StorageSupport {
  localStorage: boolean;
  indexedDB: boolean;
  any: boolean;
}

let probed: StorageSupport | null = null;

export async function probeStorage(): Promise<StorageSupport> {
  if (probed) return probed;
  let ls = false;
  try {
    localStorage.setItem(`${KEY}:probe`, '1');
    ls = localStorage.getItem(`${KEY}:probe`) === '1';
    localStorage.removeItem(`${KEY}:probe`);
  } catch {
    ls = false;
  }

  let idb = false;
  try {
    await set(`${KEY}:probe`, 1);
    idb = (await get(`${KEY}:probe`)) === 1;
    await del(`${KEY}:probe`);
  } catch {
    idb = false;
  }

  probed = { localStorage: ls, indexedDB: idb, any: ls || idb };
  return probed;
}

/**
 * IndexedDB with a localStorage fallback. The whole prototype state is a few
 * hundred KB at most, so it is written as a single record — simple to reason
 * about, and trivially replaceable with something finer-grained later.
 */
export async function loadState<T>(): Promise<T | null> {
  try {
    const value = await get<T>(KEY);
    if (value) return value;
  } catch {
    // IndexedDB unavailable (private mode, sandboxed iframe) — fall through.
  }
  try {
    const raw = localStorage.getItem(KEY);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

export async function saveState<T>(value: T): Promise<void> {
  try {
    await set(KEY, value);
    return;
  } catch {
    // ignore and try localStorage
  }
  try {
    localStorage.setItem(KEY, JSON.stringify(value));
  } catch {
    // Nothing persists this session; the app still works in memory.
  }
}

export async function clearState(): Promise<void> {
  try {
    await del(KEY);
  } catch {
    /* ignore */
  }
  try {
    localStorage.removeItem(KEY);
  } catch {
    /* ignore */
  }
}

/** Collapse rapid writes into one. */
export function debounce<T extends (...args: never[]) => void>(fn: T, ms: number): T {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return ((...args: never[]) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  }) as T;
}
