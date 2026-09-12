/**
 * Optional cloud sync, so the same repertoire and review history follow you
 * between devices.
 *
 * The page asks the artifact runtime for the `db` capability. When it is not
 * there — running locally, a viewer who declined, an older runtime — every
 * function here degrades to "unavailable" and the app carries on with
 * IndexedDB alone. Nothing in the UI depends on this working.
 *
 * A db document holds at most 256 KiB, and a fully-trained state is about
 * 1.8 MB of JSON (mostly FEN strings, which repeat heavily). So the payload is
 * gzipped and base64-encoded, which brings it to roughly 170 KiB. The size is
 * checked before every write rather than discovered as a rejection.
 */

const DOC_PATH = 'state/main';
const MAX_PAYLOAD = 240 * 1024; // leave headroom under the 256 KiB document cap

export type CloudStatus =
  | { kind: 'unavailable' }
  | { kind: 'idle'; lastSyncedAt: number | null }
  | { kind: 'syncing' }
  | { kind: 'synced'; lastSyncedAt: number }
  | { kind: 'error'; message: string }
  | { kind: 'too-large'; bytes: number };

interface DocumentSnapshot {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
}

interface DocumentReference {
  get(): Promise<DocumentSnapshot>;
  set(data: Record<string, unknown>): Promise<void>;
}

interface Db {
  doc(path: string): DocumentReference;
}

interface ClaudeRuntime {
  use(name: string): Promise<unknown>;
}

function runtime(): ClaudeRuntime | null {
  const claude = (globalThis as { claude?: ClaudeRuntime }).claude;
  return claude && typeof claude.use === 'function' ? claude : null;
}

let dbPromise: Promise<Db | null> | null = null;

export function cloudAvailable(): boolean {
  return runtime() !== null;
}

async function getDb(): Promise<Db | null> {
  const claude = runtime();
  if (!claude) return null;
  if (!dbPromise) {
    dbPromise = claude
      .use('db')
      .then((value) => (value as Db | null) ?? null)
      .catch(() => null);
  }
  return dbPromise;
}

/* ── compression ───────────────────────────────────────────────────────── */

function hasCompression(): boolean {
  return typeof CompressionStream === 'function' && typeof DecompressionStream === 'function';
}

function bytesToBase64(bytes: Uint8Array): string {
  // btoa on a single huge string overflows the argument limit, so chunk it.
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function base64ToBytes(value: string): ArrayBuffer {
  const binary = atob(value);
  const out = new Uint8Array(new ArrayBuffer(binary.length));
  for (let i = 0; i < binary.length; i += 1) out[i] = binary.charCodeAt(i);
  return out.buffer;
}

async function gzip(text: string): Promise<string> {
  const stream = new Blob([text]).stream().pipeThrough(new CompressionStream('gzip'));
  const buffer = await new Response(stream).arrayBuffer();
  return bytesToBase64(new Uint8Array(buffer));
}

async function gunzip(base64: string): Promise<string> {
  const bytes = base64ToBytes(base64);
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Response(stream).text();
}

/* ── read / write ──────────────────────────────────────────────────────── */

export interface CloudRecord<T> {
  state: T;
  updatedAt: number;
}

export async function readCloud<T>(): Promise<CloudRecord<T> | null> {
  const db = await getDb();
  if (!db) return null;
  try {
    const snapshot = await db.doc(DOC_PATH).get();
    if (!snapshot.exists) return null;
    const data = snapshot.data() ?? {};
    const updatedAt = typeof data.updatedAt === 'number' ? data.updatedAt : 0;
    if (typeof data.gz === 'string') {
      if (!hasCompression()) return null;
      return { state: JSON.parse(await gunzip(data.gz)) as T, updatedAt };
    }
    if (typeof data.json === 'string') {
      return { state: JSON.parse(data.json) as T, updatedAt };
    }
    return null;
  } catch {
    // Not granted, offline, or a payload this build cannot read: stay local.
    return null;
  }
}

export type WriteResult =
  | { ok: true; bytes: number }
  | { ok: false; reason: 'unavailable' | 'too-large' | 'error'; bytes?: number; message?: string };

export async function writeCloud<T>(state: T, updatedAt: number): Promise<WriteResult> {
  const db = await getDb();
  if (!db) return { ok: false, reason: 'unavailable' };

  try {
    const json = JSON.stringify(state);
    const body: Record<string, unknown> = { updatedAt };
    if (hasCompression()) body.gz = await gzip(json);
    else body.json = json;

    const bytes = new Blob([JSON.stringify(body)]).size;
    if (bytes > MAX_PAYLOAD) return { ok: false, reason: 'too-large', bytes };

    await db.doc(DOC_PATH).set(body);
    return { ok: true, bytes };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { ok: false, reason: 'error', message };
  }
}

export function describeStatus(status: CloudStatus): string {
  switch (status.kind) {
    case 'unavailable':
      return 'Not available here — this device only';
    case 'syncing':
      return 'Syncing…';
    case 'synced':
      return `Synced ${relative(status.lastSyncedAt)}`;
    case 'idle':
      return status.lastSyncedAt ? `Synced ${relative(status.lastSyncedAt)}` : 'Ready';
    case 'too-large':
      return `Too large to sync (${Math.round(status.bytes / 1024)} KiB of 240)`;
    case 'error':
      return status.message;
  }
}

function relative(at: number): string {
  const delta = Date.now() - at;
  if (delta < 60_000) return 'just now';
  if (delta < 3_600_000) return `${Math.round(delta / 60_000)} min ago`;
  if (delta < 86_400_000) return `${Math.round(delta / 3_600_000)} h ago`;
  return `${Math.round(delta / 86_400_000)} d ago`;
}
