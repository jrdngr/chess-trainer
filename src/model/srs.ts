import type { Card, CardStage, Grade } from './types';

export const MINUTE = 60_000;
export const DAY = 86_400_000;

/**
 * A small, deliberately boring SM-2 variant. Everything it needs is in the
 * config object, and `review()` is pure, so the whole algorithm can be swapped
 * out later without touching the UI.
 */
export interface SrsConfig {
  /** Learning steps in minutes, walked before a card graduates. */
  learningSteps: number[];
  /** Steps used after a lapse. */
  relearningSteps: number[];
  graduatingInterval: number;
  easyInterval: number;
  startingEase: number;
  minEase: number;
  easeDelta: Record<Grade, number>;
  hardMultiplier: number;
  easyBonus: number;
  /** Fraction of the previous interval kept after a lapse. */
  lapseMultiplier: number;
  maxInterval: number;
}

export const DEFAULT_SRS: SrsConfig = {
  learningSteps: [1, 10],
  relearningSteps: [10],
  graduatingInterval: 1,
  easyInterval: 4,
  startingEase: 2.5,
  minEase: 1.3,
  easeDelta: { again: -0.2, hard: -0.15, good: 0, easy: 0.15 },
  hardMultiplier: 1.2,
  easyBonus: 1.3,
  lapseMultiplier: 0.5,
  maxInterval: 365,
};

export function createCard(
  id: string,
  repertoireId: string,
  key: string,
  fen: string,
  now = Date.now(),
): Card {
  return {
    id,
    repertoireId,
    key,
    fen,
    stage: 'new',
    step: 0,
    interval: 0,
    ease: DEFAULT_SRS.startingEase,
    reps: 0,
    lapses: 0,
    correct: 0,
    incorrect: 0,
    due: now,
    lastReviewed: null,
    createdAt: now,
  };
}

function clampEase(ease: number, cfg: SrsConfig): number {
  return Math.max(cfg.minEase, Math.round(ease * 100) / 100);
}

function clampInterval(days: number, cfg: SrsConfig): number {
  return Math.min(cfg.maxInterval, Math.max(1, Math.round(days * 100) / 100));
}

export interface ReviewOutcome {
  card: Card;
  /** Milliseconds until the card is next due. */
  delay: number;
}

/**
 * Apply a grade to a card. Pure and deterministic: the same (card, grade, now)
 * always produces the same next state. No interval fuzz, on purpose.
 */
export function review(
  card: Card,
  grade: Grade,
  now = Date.now(),
  cfg: SrsConfig = DEFAULT_SRS,
): ReviewOutcome {
  const correct = grade !== 'again';
  const base: Card = {
    ...card,
    reps: card.reps + 1,
    correct: card.correct + (correct ? 1 : 0),
    incorrect: card.incorrect + (correct ? 0 : 1),
    lastReviewed: now,
    ease: clampEase(card.ease + cfg.easeDelta[grade], cfg),
  };

  let stage: CardStage = base.stage;
  let step = base.step;
  let interval = base.interval;
  let lapses = base.lapses;
  let delay: number;

  const inLearning = card.stage === 'new' || card.stage === 'learning';

  if (grade === 'again') {
    if (!inLearning) {
      lapses += 1;
      interval = clampInterval(card.interval * cfg.lapseMultiplier, cfg);
    }
    stage = 'learning';
    step = 0;
    delay = (inLearning ? cfg.learningSteps[0] : cfg.relearningSteps[0]) * MINUTE;
  } else if (inLearning) {
    const steps = card.stage === 'new' ? cfg.learningSteps : cfg.learningSteps;
    if (grade === 'easy') {
      stage = 'review';
      step = 0;
      interval = clampInterval(cfg.easyInterval, cfg);
      delay = interval * DAY;
    } else if (grade === 'hard') {
      // Stay on the current step, but come back a little sooner than "good".
      stage = 'learning';
      step = card.step;
      delay = Math.max(1, steps[Math.min(step, steps.length - 1)]) * MINUTE;
    } else {
      const nextStep = card.step + 1;
      if (nextStep >= steps.length) {
        stage = 'review';
        step = 0;
        interval = clampInterval(
          card.lapses > 0 ? Math.max(cfg.graduatingInterval, card.interval) : cfg.graduatingInterval,
          cfg,
        );
        delay = interval * DAY;
      } else {
        stage = 'learning';
        step = nextStep;
        delay = steps[nextStep] * MINUTE;
      }
    }
  } else if (now < card.due) {
    // Practised ahead of schedule. Getting it right early is not evidence the
    // interval was too short, so the card keeps the date it already had — an
    // endless session cannot push your whole deck into next month. Getting it
    // wrong still counts, through the branch above.
    stage = 'review';
    step = 0;
    delay = card.due - now;
  } else {
    const prev = Math.max(card.interval, 1);
    if (grade === 'hard') interval = clampInterval(prev * cfg.hardMultiplier, cfg);
    else if (grade === 'good') interval = clampInterval(prev * base.ease, cfg);
    else interval = clampInterval(prev * base.ease * cfg.easyBonus, cfg);
    stage = 'review';
    step = 0;
    delay = interval * DAY;
  }

  return {
    card: { ...base, stage, step, interval, lapses, due: now + delay },
    delay,
  };
}

/** What each button will do. Kept for tests and for anyone adding a preview back. */
export function gradePreview(
  card: Card,
  now = Date.now(),
  cfg: SrsConfig = DEFAULT_SRS,
): Record<Grade, string> {
  const grades: Grade[] = ['again', 'hard', 'good', 'easy'];
  const out = {} as Record<Grade, string>;
  for (const g of grades) out[g] = describeDelay(review(card, g, now, cfg).delay);
  return out;
}

export function describeDelay(ms: number): string {
  const mins = ms / MINUTE;
  if (mins < 60) return `${Math.max(1, Math.round(mins))}m`;
  const hours = mins / 60;
  if (hours < 24) return `${Math.round(hours)}h`;
  const days = hours / 24;
  if (days < 30) return `${days < 10 ? Math.round(days * 10) / 10 : Math.round(days)}d`;
  const months = days / 30.4;
  if (months < 12) return `${Math.round(months * 10) / 10}mo`;
  return `${Math.round((days / 365) * 10) / 10}y`;
}

export function describeDue(due: number, now = Date.now()): string {
  if (due <= now) return 'due now';
  return `in ${describeDelay(due - now)}`;
}

export function isDue(card: Card, now = Date.now()): boolean {
  return card.due <= now;
}

export interface DueCounts {
  due: number;
  new: number;
  learning: number;
  review: number;
  later: number;
  total: number;
}

export function countDue(cards: Card[], now = Date.now()): DueCounts {
  const counts: DueCounts = { due: 0, new: 0, learning: 0, review: 0, later: 0, total: cards.length };
  for (const c of cards) {
    const due = isDue(c, now);
    if (due) {
      counts.due += 1;
      if (c.stage === 'new') counts.new += 1;
      else if (c.stage === 'learning') counts.learning += 1;
      else counts.review += 1;
    } else {
      counts.later += 1;
    }
  }
  return counts;
}

/** Retention across all reviewed cards, 0..1. Null when nothing is reviewed. */
export function retention(cards: Card[]): number | null {
  let correct = 0;
  let total = 0;
  for (const c of cards) {
    correct += c.correct;
    total += c.correct + c.incorrect;
  }
  return total === 0 ? null : correct / total;
}

/** Cards grouped into a rough mastery ladder, for the progress display. */
export function masteryBuckets(cards: Card[]): { unseen: number; learning: number; young: number; mature: number } {
  const out = { unseen: 0, learning: 0, young: 0, mature: 0 };
  for (const c of cards) {
    if (c.stage === 'new') out.unseen += 1;
    else if (c.stage === 'learning') out.learning += 1;
    else if (c.interval < 21) out.young += 1;
    else out.mature += 1;
  }
  return out;
}

/** Forecast of how many cards come due over the next `days` days. */
export function forecast(cards: Card[], days = 7, now = Date.now()): number[] {
  const out = new Array(days).fill(0);
  for (const c of cards) {
    if (c.due <= now) {
      out[0] += 1;
      continue;
    }
    const idx = Math.floor((c.due - now) / DAY);
    if (idx >= 0 && idx < days) out[idx] += 1;
  }
  return out;
}
