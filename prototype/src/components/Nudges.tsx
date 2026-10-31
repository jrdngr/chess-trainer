import type { AnswerRole } from '../model/answerArrows';
import type { NudgeTone } from '../model/nudge';

/** The colour a nudge is drawn in: green toward, yellow toward from off the list, red away. */
export function nudgeColor(tone: NudgeTone | undefined): string | undefined {
  if (tone === 'toward') return 'var(--good)';
  if (tone === 'toward-far') return 'var(--warn)';
  if (tone === 'away') return 'var(--bad)';
  return undefined;
}

/** The colour of an answer's arrow, and its row, by who recommends it. */
export function roleColor(role: AnswerRole): string {
  if (role === 'strong') return 'var(--book)';
  if (role === 'engine') return 'var(--accent)';
  return 'var(--engine-next)';
}
