import { test } from '@playwright/test';
import { search } from '../src/engine/basic/search';
import { legal, open, positionKey, prepared, uciOf, type Session } from './harness';

/** The test's own choice past prep: best or worst at a shallow depth, so it never varies. */
function pick(fen: string, worst = false): string {
  const result = search(fen, { maxDepth: 2, timeMs: Number.MAX_SAFE_INTEGER, now: () => 0, multiPv: 40 });
  const lines = result?.lines ?? [];
  if (!lines.length) return legal(fen)[0];
  return (worst ? lines[lines.length - 1] : lines[0]).pv[0];
}

/** How a run is played: which prepared move to miss, how far past prep to go, and whether to blunder. */
interface Plan {
  missAt?: number;
  pastPrep: number;
  blunder?: boolean;
}

const THINK = [1200, 4000, 9000];

async function playRun(s: Session, plan: Plan, run: number) {
  let mine = 0;
  let past = 0;
  let prepSeen = 0;
  for (let guard = 0; guard < 400; guard += 1) {
    if (await s.has('Next round')) {
      await s.note(`run ${run} end`);
      return;
    }
    if (await s.has('Continue')) {
      await s.note(`run ${run} blunder shown`);
      await s.tap('Continue', true);
      await s.wait(2500);
      continue;
    }
    const prompt = (await s.page.locator('.prompt').first().innerText().catch(() => '')) ?? '';
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
      if (plan.missAt === prepSeen) {
        const prepUci = prep.map((san) => uciOf(fen, san));
        uci = legal(fen).find((m) => !prepUci.includes(m) && m === pick(fen)) ?? legal(fen).find((m) => !prepUci.includes(m))!;
      } else {
        uci = uciOf(fen, prep[0]);
      }
    } else {
      if (past >= plan.pastPrep) {
        await s.note(`run ${run} ending it`);
        await s.tap('End round', true);
        await s.wait(3000);
        continue;
      }
      past += 1;
      uci = pick(fen, plan.blunder && past === plan.pastPrep);
    }
    await s.wait(THINK[mine % THINK.length]);
    mine += 1;
    await s.move(uci);
    await s.wait(400);
    await s.note(`run ${run} move ${mine} ${uci}, just played`);
    await s.wait(2100);
    await s.note(`run ${run} move ${mine} ${uci}`);
  }
  throw new Error(`run ${run} never ended`);
}

test('Autopilot: a new player\'s first runs', async ({ page }) => {
  const s = await open(page, { seed: 7 });
  await s.note('opened');
  await s.tap('Suggest a set');
  await s.tap('Classical', true);
  await s.tap('Use Classical');
  await s.note('ready');
  await s.tap('Play your first run');
  await s.wait(4000);
  await s.note('first run');
  const plans: Plan[] = [{ pastPrep: 4 }, { missAt: 1, pastPrep: 3 }, { pastPrep: 3, blunder: true }, { pastPrep: 6 }, { pastPrep: 2 }];
  for (const [i, plan] of plans.entries()) {
    await playRun(s, plan, i + 1);
    await s.tap('Next round', true);
    await s.wait(4000);
    await s.note(`run ${i + 2} start`);
  }
  await s.expectTrace('autopilot-first-runs');
});
