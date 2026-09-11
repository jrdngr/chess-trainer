import { del, get, set } from 'idb-keyval';

const KEY = 'chess-repertoire-trainer:v1';

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
