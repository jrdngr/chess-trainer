import { test } from '@playwright/test';
import { classicalAtHome, offPrep, open, openMode, pick, playRun, positionKey, prepared, uciOf, type Session } from './harness';

/**
 * One recorded session per mode, each from a new player's Classical set. The
 * Autopilot flow lives in autopilot.spec.ts. Every step lands in the trace, so
 * a change to what any of these screens says or does shows up as a diff.
 */

type State = Parameters<typeof prepared>[0];

/** Whether it is the player's turn on the main board, with a prompt showing. */
async function ourTurn(s: Session) {
  const prompt = await s.prompt();
  const { fen, orientation } = await s.board();
  const ours = !!fen && !!prompt && fen.split(' ')[1] === orientation && !/Their move|Reply|Judging/.test(prompt);
  return { ours, fen, orientation, prompt };
}

async function prepHere(s: Session, fen: string, orientation: 'w' | 'b') {
  return prepared((await s.saved()) as State, orientation).get(positionKey(fen)) ?? [];
}

/** Play a move after thinking a moment, and note what the screen says. */
async function play(s: Session, label: string, uci: string) {
  await s.wait(2000);
  await s.move(uci);
  await s.wait(2500);
  await s.note(`${label} ${uci}`);
}

test('Survival: setup choices, a miss, a blunder, and a clock', async ({ page }) => {
  const s = await open(page, { seed: 11 });
  await classicalAtHome(s);
  await openMode(s, 'Survival');
  await s.tap('My gaps', true);
  await s.tap('10s', true);
  await s.tap('Undefended flash', true);
  await s.note('choices made');
  await s.tap('Start', true);
  await s.wait(3000);
  await s.note('run 1 start');
  const labels = { end: 'End run', done: 'Next run' };
  await playRun(s, { missAt: 1, pastPrep: 3, blunder: true }, 1, labels);
  await s.tap('Next run', true);
  await s.wait(3000);
  await s.note('run 2 start');
  await playRun(s, { pastPrep: 4, slowAt: { move: 2, ms: 11_000 } }, 2, labels);
  await s.tap('Next run', true);
  await s.wait(3000);
  await s.note('run 3 start');
  await playRun(s, { pastPrep: 2 }, 3, labels);
  await s.expectTrace('survival-runs');
});

test('Drill: positions, then lines', async ({ page }) => {
  const s = await open(page, { seed: 13 });
  await classicalAtHome(s);
  await openMode(s, 'Drill');
  await s.tap('Start', true);
  await s.wait(2000);
  let answered = 0;
  for (let guard = 0; guard < 120 && answered < 10; guard += 1) {
    const { ours, fen, orientation } = await ourTurn(s);
    if (ours) {
      answered += 1;
      // Grade the card before last by hand once, both ways.
      if (answered === 4 && (await s.has('Easy'))) await s.tap('Easy', true);
      if (answered === 7 && (await s.has('Hard'))) await s.tap('Hard', true);
      const prep = await prepHere(s, fen, orientation);
      const miss = answered === 2 || answered === 5 || !prep.length;
      await play(s, `position ${answered}`, miss ? offPrep(fen, prep) : uciOf(fen, prep[0]));
    } else if (await s.has('Continue')) {
      await s.tap('Continue', true);
      await s.note(`position ${answered} continued`);
    } else {
      await s.wait(500);
    }
  }
  await s.tap('Stop', true);
  await s.wait(1500);
  await s.note('positions stopped');
  await openMode(s, 'Drill');
  await s.tap('Lines', true);
  await s.tap('Start', true);
  await s.wait(2000);
  let moves = 0;
  for (let guard = 0; guard < 120 && moves < 10; guard += 1) {
    const { ours, fen, orientation } = await ourTurn(s);
    if (ours) {
      moves += 1;
      const prep = await prepHere(s, fen, orientation);
      const miss = moves === 2 || moves === 7 || !prep.length;
      await play(s, `line move ${moves}`, miss ? offPrep(fen, prep) : uciOf(fen, prep[0]));
    } else if (await s.has('Continue')) {
      await s.tap('Continue', true);
      await s.note(`line move ${moves} continued`);
    } else if (await s.has('Next line')) {
      await s.tap('Next line', true);
      await s.note(`line move ${moves} next line`);
    } else if (await s.has('Next round')) {
      await s.tap('Next round', true);
      await s.note(`line move ${moves} next round`);
    } else {
      await s.wait(500);
    }
  }
  await s.expectTrace('drill-sessions');
});

test('Growth: answer holes, undo one, finish', async ({ page }) => {
  const s = await open(page, { seed: 17 });
  await classicalAtHome(s);
  await openMode(s, 'Growth');
  await s.tap('Start', true);
  await s.wait(3000);
  await s.note('growth start');
  let picks = 0;
  for (let guard = 0; guard < 150 && picks < 9; guard += 1) {
    const prompt = await s.prompt();
    const rows = s.page.locator('.list .list-row');
    if (prompt.startsWith('They played') && (await rows.count())) {
      picks += 1;
      if (picks === 4) {
        await s.page.locator('button[aria-label="Undo"]').first().click({ force: true });
        await s.wait(1500);
        await s.note('undone');
        continue;
      }
      // Mostly the first answer, sometimes the second, so both roles get taken.
      const nth = picks % 3 === 2 && (await rows.count()) > 1 ? 1 : 0;
      await s.wait(1500);
      await rows.nth(nth).click({ force: true });
      await s.wait(2500);
      await s.note(`pick ${picks} row ${nth + 1}`);
      continue;
    }
    const { ours, fen, orientation } = await ourTurn(s);
    if (ours) {
      const prep = await prepHere(s, fen, orientation);
      await play(s, 'walk', prep.length ? uciOf(fen, prep[0]) : pick(fen));
      continue;
    }
    let tapped = false;
    for (const label of ['Next round', 'New run']) {
      if (await s.has(label)) {
        await s.note(`before ${label}`);
        await s.tap(label, true);
        await s.wait(2000);
        await s.note(`after ${label}`);
        tapped = true;
        break;
      }
    }
    if (!tapped) await s.wait(500);
  }
  if (await s.has('Done')) {
    await s.tap('Done', true);
    await s.wait(2000);
    await s.note('done');
  }
  await s.expectTrace('growth-session');
});

test('Play: a casual game with a take-back and a resignation', async ({ page }) => {
  const s = await open(page, { seed: 19 });
  await classicalAtHome(s);
  await openMode(s, 'Play');
  await s.tap('Start', true);
  await s.wait(3000);
  await s.note('game start');
  let moves = 0;
  let tookBack = false;
  for (let guard = 0; guard < 150 && moves < 10; guard += 1) {
    const { ours, fen, orientation } = await ourTurn(s);
    if (!ours) {
      await s.wait(500);
      continue;
    }
    if (moves === 5 && !tookBack) {
      tookBack = true;
      await s.tap('Take back', true);
      await s.wait(1500);
      await s.note('took back');
      continue;
    }
    moves += 1;
    const prep = await prepHere(s, fen, orientation);
    await play(s, `game move ${moves}`, prep.length ? uciOf(fen, prep[0]) : pick(fen));
  }
  await s.tap('Resign', true);
  await s.wait(2000);
  await s.note('resigned');
  await s.expectTrace('play-game');
});
