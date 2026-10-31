import { DEFAULT_SURVIVAL } from '../../model/survival';
import {
  comboAfter,
  comboMultiplier,
  evalSwing,
  glowFor,
  isMoment,
  missionTitle,
  momentBonus,
  moveNumber,
  moveScore,
  prepSummary,
  secondsText,
  speedTone,
  survivalSteerLabel,
} from '../../model/survival';
import { cases, grid, range, type CaseFile } from '../caseKit';

const COLORS: ('w' | 'b')[] = ['w', 'b'];

const file: CaseFile = {
  area: 'survival',
  functions: [
    cases('survival.moveScore', "A move's score over its square: centipawns gained or lost, and its tone.", moveScore, range(-250, 250).map((n) => [n] as [number])),
    cases('survival.evalSwing', 'What a move changed, from your side; null when either side is a mate.', evalSwing, grid(COLORS, [-10000, -300, -50, 0, 50, 300, 10000, 9999], [-10000, -120, 0, 120, 10000, -9999])),
    cases('survival.glowFor', "The board's edge: green, yellow or red, and how bright.", glowFor, grid(COLORS, [...range(-1200, 1200, 25), -301, -299, -101, -99, 99, 101, 299, 301])),
    cases('survival.speedTone', 'The color of a prepared move found, by how long it took.', speedTone, range(0, 15, 0.1).map((n) => [n] as [number])),
    cases('survival.secondsText', 'How a time is written.', secondsText, [0, 0.04, 0.05, 0.96, 1, 2.94, 2.95, 9.94, 9.95, 10, 10.4, 10.5, 59.4, 59.5, 61, 125].map((n) => [n] as [number])),
    cases('survival.prepSummary', "Autopilot's line on how the run went on your prep.", prepSummary, [
      [0, 0, [], 0],
      [3, 3, [1, 2, 3], 0],
      [2, 3, [1.5, 9], 0],
      [4, 4, [2.9, 3, 3.1, 8], 2],
      [0, 2, [], 1],
      [1, 1, [12], 1],
    ]),
    cases('survival.comboAfter', 'The combo streak after a move that lost this many centipawns.', comboAfter, grid(range(0, 12), [0, 5, 19, 20, 21, 39, 40, 41, 79, 80, 81, 150])),
    cases('survival.comboMultiplier', 'What a streak multiplies points by.', comboMultiplier, range(0, 20).map((n) => [n] as [number])),
    cases('survival.isMoment', 'Whether one move here is far better than the rest.', isMoment, grid(COLORS, [-400, -150, -100, -99, 0, 99, 100, 101, 150, 250, 400, 10000, -10000], [null, -400, -100, -50, 0, 49, 50, 51, 100, 250, 9999])),
    cases('survival.momentBonus', "A moment's bonus, by the streak of moments found.", momentBonus, range(0, 12).map((n) => [n] as [number])),
    cases('survival.missionTitle', "A mission's name.", missionTitle, (['edge', 'lead', 'dig', 'plan', 'convert'] as const).map((kind) => [kind] as [never])),
    cases('survival.moveNumber', 'The move number a ply count is on.', moveNumber, range(0, 40).map((n) => [n] as [number])),
    cases('survival.survivalSteerLabel', "Each steer's name.", survivalSteerLabel, (['lines', 'gaps', 'book'] as const).map((steer) => [steer] as [never])),
    cases('survival.DEFAULT_SURVIVAL', "Survival's options as a new player has them.", () => DEFAULT_SURVIVAL, [[]]),
  ],
};

export default file;
