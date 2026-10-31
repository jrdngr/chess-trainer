import { test } from '@playwright/test';
import { open, playRun, type Plan } from './harness';

const AUTOPILOT = { end: 'End round', done: 'Next round' };

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
    await playRun(s, plan, i + 1, AUTOPILOT);
    await s.tap('Next round', true);
    await s.wait(4000);
    await s.note(`run ${i + 2} start`);
  }
  await s.expectTrace('autopilot-first-runs');
});
