import { expect, type Page } from '@playwright/test';
import { Chess } from 'chess.js';
import { search } from '../src/engine/basic/search';

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
    await this.page.getByText(text, { exact }).filter({ visible: true }).first().click({ force: true, timeout: 10_000 });
    await this.wait(1200);
  }

  async has(text: string): Promise<boolean> {
    return (await this.page.getByText(text, { exact: true }).count()) > 0;
  }

  /** The prompt under the board, or nothing when the screen has none. Never waits. */
  async prompt(): Promise<string> {
    const prompt = this.page.locator('.prompt').first();
    if (!(await this.page.locator('.prompt').count())) return '';
    return (await prompt.innerText({ timeout: 2000 }).catch(() => '')).replace(/\s+/g, ' ').trim();
  }

  /** The labels of the buttons on screen now. */
  async buttons(): Promise<string[]> {
    return this.page.locator('button:visible').evaluateAll((els) =>
      els.map((e) => (e.textContent ?? '').replace(/\s+/g, ' ').trim()).filter((t) => t && t.length < 40),
    );
  }

  /** The position on the main board, and which way up it is. */
  async board(): Promise<{ fen: string; orientation: 'w' | 'b' }> {
    const wrap = this.page.locator('.board-wrap').first();
    if (!(await this.page.locator('.board-wrap').count())) return { fen: '', orientation: 'w' };
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
    const { fen } = await this.board();
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

/** The test's own choice past prep: best or worst at a shallow depth, so it never varies. */
export function pick(fen: string, worst = false): string {
  const result = search(fen, { maxDepth: 2, timeMs: Number.MAX_SAFE_INTEGER, now: () => 0, multiPv: 40 });
  const lines = result?.lines ?? [];
  if (!lines.length) return legal(fen)[0];
  return (worst ? lines[lines.length - 1] : lines[0]).pv[0];
}

/** A move that is legal here and not one of the prepared ones, for a miss. */
export function offPrep(fen: string, prep: string[]): string {
  const prepUci = prep.map((san) => uciOf(fen, san));
  const best = pick(fen);
  return legal(fen).find((m) => !prepUci.includes(m) && m === best) ?? legal(fen).find((m) => !prepUci.includes(m))!;
}

/** How a run is played: which prepared move to miss, how far past prep to go, and whether to blunder. */
export interface Plan {
  missAt?: number;
  pastPrep: number;
  blunder?: boolean;
  /** Think this long before the nth move of the run (1-based), instead of the usual rhythm. */
  slowAt?: { move: number; ms: number };
}

/** The labels of a run screen: the button that ends a run early, and the one that starts the next. */
export interface RunLabels {
  end: string;
  done: string;
}

const THINK = [1200, 4000, 9000];

/** Play one Survival-style run (Autopilot or Survival) to its end screen, noting every move. */
export async function playRun(s: Session, plan: Plan, run: number, labels: RunLabels) {
  let mine = 0;
  let past = 0;
  let prepSeen = 0;
  for (let guard = 0; guard < 400; guard += 1) {
    if (await s.has(labels.done)) {
      await s.note(`run ${run} end`);
      return;
    }
    if (await s.has('Continue')) {
      await s.note(`run ${run} blunder shown`);
      await s.tap('Continue', true);
      await s.wait(2500);
      continue;
    }
    const prompt = await s.prompt();
    const { fen, orientation } = await s.board();
    const ours = fen.split(' ')[1] === orientation;
    if (!prompt.includes('Your move') || !ours) {
      await s.wait(300);
      continue;
    }
    const state = (await s.saved()) as Parameters<typeof prepared>[0];
    const prep = prepared(state, orientation).get(positionKey(fen)) ?? [];
    let uci: string;
    if (prep.length) {
      prepSeen += 1;
      uci = plan.missAt === prepSeen ? offPrep(fen, prep) : uciOf(fen, prep[0]);
    } else {
      if (past >= plan.pastPrep) {
        await s.note(`run ${run} ending it`);
        await s.tap(labels.end, true);
        await s.wait(3000);
        continue;
      }
      past += 1;
      uci = pick(fen, plan.blunder && past === plan.pastPrep);
    }
    const think = plan.slowAt?.move === mine + 1 ? plan.slowAt.ms : THINK[mine % THINK.length];
    await s.wait(think);
    mine += 1;
    await s.move(uci);
    await s.wait(400);
    await s.note(`run ${run} move ${mine} ${uci}, just played`);
    await s.wait(2100);
    await s.note(`run ${run} move ${mine} ${uci}`);
  }
  throw new Error(`run ${run} never ended`);
}

/** A new player takes the suggested Classical set and goes to Home. */
export async function classicalAtHome(s: Session) {
  await s.tap('Suggest a set');
  await s.tap('Classical', true);
  await s.tap('Use Classical');
  await s.tap('Go to Home');
  await s.note('home');
}

/** Open a mode from Home's grid. */
export async function openMode(s: Session, name: string) {
  await s.page.locator('.mode-tile', { hasText: name }).first().click({ force: true });
  await s.wait(1500);
  await s.note(`${name} setup`);
}
