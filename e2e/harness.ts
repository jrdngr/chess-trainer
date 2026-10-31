import { expect, type Page } from '@playwright/test';
import { Chess } from 'chess.js';

/** Where every recorded session starts its clock. */
const EPOCH = new Date('2026-10-01T09:00:00Z');

/**
 * Open the app for a recorded session: the engine searches to `depth` and no
 * further, `Math.random` is seeded, and time only moves when the test says.
 */
export async function open(page: Page, { seed = 1, depth = 3 } = {}): Promise<Session> {
  await page.addInitScript(
    ({ seed, depth }) => {
      (globalThis as Record<string, unknown>).__CHESS_TEST__ = { engineDepth: depth };
      let a = seed >>> 0;
      Math.random = () => {
        a = (a + 0x6d2b79f5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
      };
    },
    { seed, depth },
  );
  // Installed a moment early, then paused at the epoch: the clock only moves
  // in wait(), never with real time.
  await page.clock.install({ time: new Date(EPOCH.getTime() - 1000) });
  await page.clock.pauseAt(EPOCH);
  await page.goto('http://localhost:4181/');
  const session = new Session(page);
  await session.wait(1500);
  return session;
}

export class Session {
  readonly trace: string[] = [];
  constructor(readonly page: Page) {}

  /** Let this much time pass on the page's clock, then let the page settle. */
  async wait(ms: number) {
    // Small steps, with a real pause after each so React finishes what the
    // timers started before the clock moves on: otherwise when a turn begins
    // drifts by a step, and so does how long a move took.
    const step = 50;
    for (let left = ms; left > 0; left -= step) {
      await this.page.clock.runFor(Math.min(step, left));
      await new Promise((resolve) => setTimeout(resolve, 15));
    }
  }

  async tap(text: string, exact = false) {
    await this.page.getByText(text, { exact }).first().click({ force: true, timeout: 10_000 });
    await this.wait(1200);
  }

  async has(text: string): Promise<boolean> {
    return (await this.page.getByText(text, { exact: true }).count()) > 0;
  }

  /** The position on the main board, and which way up it is. */
  async board(): Promise<{ fen: string; orientation: 'w' | 'b' }> {
    const wrap = this.page.locator('.board-wrap').first();
    const fen = (await wrap.getAttribute('data-fen')) ?? '';
    const orientation = ((await wrap.getAttribute('data-orientation')) ?? 'w') as 'w' | 'b';
    return { fen, orientation };
  }

  /** Play a move on the main board by tapping its squares. */
  async move(uci: string) {
    const { orientation } = await this.board();
    const box = (await this.page.locator('.board-wrap .board').first().boundingBox())!;
    const at = (square: string) => {
      const file = square.charCodeAt(0) - 97;
      const rank = Number(square[1]) - 1;
      const col = orientation === 'w' ? file : 7 - file;
      const row = orientation === 'w' ? 7 - rank : rank;
      return { x: box.x + (col + 0.5) * (box.width / 8), y: box.y + (row + 0.5) * (box.height / 8) };
    };
    for (const square of [uci.slice(0, 2), uci.slice(2, 4)]) {
      const { x, y } = at(square);
      await this.page.mouse.click(x, y);
    }
    if (uci.length === 5) await this.tap({ q: 'Queen', r: 'Rook', b: 'Bishop', n: 'Knight' }[uci[4]]!);
  }

  /** What the screen says now, one line in the trace. */
  async note(label: string) {
    const text = (await this.page.locator('body').innerText()).replace(/\s+/g, ' ').trim();
    const fen = (await this.page.locator('.board-wrap').count()) ? (await this.board()).fen : '';
    this.trace.push(`${label} | ${fen} | ${text}`);
  }

  /** The saved state, with the parts that only say when it was synced left out. */
  async saved(): Promise<unknown> {
    return this.page.evaluate(() => {
      const store = (globalThis as unknown as { __CHESS_TEST__: { store: { getState: () => Record<string, unknown> } } }).__CHESS_TEST__.store;
      const { repertoires, cards, lineCards, score, survival, mistakes, events, settings } = store.getState();
      return { repertoires, cards, lineCards, score, survival, mistakes, events, settings };
    });
  }

  async expectTrace(name: string) {
    expect(this.trace.join('\n') + '\n').toMatchSnapshot(`${name}.trace.txt`);
    expect(JSON.stringify(await this.saved(), null, 1) + '\n').toMatchSnapshot(`${name}.state.json`);
  }
}

/** Prepared moves by position, from the saved Playbook: the side's own answers. */
export function prepared(state: { repertoires: Record<string, { color: 'w' | 'b'; nodes: Record<string, { san: string; parentId: string | null }> }> }, color: 'w' | 'b') {
  const out = new Map<string, string[]>();
  for (const rep of Object.values(state.repertoires)) {
    if (rep.color !== color) continue;
    const kids = new Map<string | null, { id: string; san: string }[]>();
    for (const [id, node] of Object.entries(rep.nodes)) {
      const list = kids.get(node.parentId) ?? [];
      list.push({ id, san: node.san });
      kids.set(node.parentId, list);
    }
    const walk = (parent: string | null, chess: Chess) => {
      for (const kid of kids.get(parent) ?? []) {
        const next = new Chess(chess.fen());
        if (next.turn() === color) {
          const key = next.fen().split(' ').slice(0, 4).join(' ');
          out.set(key, [...(out.get(key) ?? []), kid.san]);
        }
        next.move(kid.san);
        walk(kid.id, next);
      }
    };
    walk(null, new Chess());
  }
  return out;
}

/** A move in UCI from SAN, in this position. */
export function uciOf(fen: string, san: string): string {
  const move = new Chess(fen).move(san);
  return move.from + move.to + (move.promotion ?? '');
}

/** Every legal move here, in UCI, in a stable order. */
export function legal(fen: string): string[] {
  return new Chess(fen)
    .moves({ verbose: true })
    .map((m) => m.from + m.to + (m.promotion ?? ''))
    .sort();
}

export const positionKey = (fen: string) => fen.split(' ').slice(0, 4).join(' ');
