import { applySan } from '../../chess/core';
import {
  firstMission,
  judgedExtras,
  missionFor,
  missionText,
  NO_EXTRAS,
  planMission,
  prepExtras,
  stepMission,
  type Extras,
  type Mission,
} from '../../model/survival';
import { cases, grid, type CaseFile } from '../caseKit';

const START = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const after = (line: string) => line.split(' ').reduce((fen, san) => applySan(fen, san)!.after, START);

/** Positions the missions read: the start, a Carlsbad, an open Sicilian, an Italian, and one with a pair of pieces traded off. */
const FENS = {
  start: START,
  carlsbad: after('d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 Be7 e3 O-O Bd3 Nbd7 Qc2 c6'),
  sicilian: after('e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6'),
  italian: after('e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6'),
  traded: after('e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d3 d6 Bg5 h6 Bxf6 Qxf6'),
};
const FEN_LIST = Object.values(FENS);
const COLORS = ['w', 'b'] as const;
const EVALS = [-450, -250, -150, -100, -99, -51, -50, 0, 50, 99, 100, 150, 199, 200, 250, 450];

const mission = (kind: Mission['kind'], over: Partial<Mission> = {}): Mission => ({ kind, moves: 0, held: 0, ...over });

/** Missions part-way through, for stepping. */
const UNDER_WAY: Mission[] = [
  mission('edge'),
  mission('edge', { moves: 9, held: 9 }),
  mission('lead'),
  mission('lead', { moves: 14 }),
  mission('dig'),
  mission('dig', { moves: 14 }),
  missionFor('w', 250, FENS.italian),
  { ...missionFor('w', 250, FENS.italian), moves: 5 },
  planMission(FENS.carlsbad, 'w', 30)!,
  { ...planMission(FENS.carlsbad, 'w', 30)!, moves: 7 },
];

const extras = (over: Partial<Extras>): Extras => ({ ...NO_EXTRAS, ...over });
const EXTRAS: Extras[] = [
  NO_EXTRAS,
  extras({ combo: 2, points: 5 }),
  extras({ combo: 9, points: 40, bestCombo: 9 }),
  extras({ moments: { found: 2, missed: 0, streak: 2 } }),
  extras({ mission: mission('lead', { moves: 3 }) }),
  extras({ mission: mission('edge', { moves: 9, held: 9 }) }),
  extras({ missionBreak: 1 }),
  extras({ missionBreak: 3, missions: { done: 1, failed: 0 } }),
];
const PREFS = [
  { moments: true, missions: true, combo: true },
  { moments: false, missions: false, combo: false },
];
const MOVES = [
  { lost: 0, after: 120, moment: false, found: false },
  { lost: 15, after: 60, moment: false, found: false },
  { lost: 35, after: 20, moment: false, found: false },
  { lost: 90, after: -40, moment: false, found: false },
  { lost: 0, after: 180, moment: true, found: true },
  { lost: 120, after: -10, moment: true, found: false },
];

const file: CaseFile = {
  area: 'missions',
  functions: [
    cases('survival.missionFor', 'The mission the eval calls for: Convert it when well ahead with pieces to trade, else keep, take or dig back to a lead.', missionFor, [
      ...grid(COLORS, EVALS).map(([c, cp]) => [c, cp] as [typeof c, number]),
      ...grid(COLORS, [200, 450, -200, -450], FEN_LIST),
    ]),
    cases('survival.planMission', "The structure's plan as a mission, when a square it names is in reach.", planMission, grid(FEN_LIST, COLORS, [-150, 0, 150])),
    cases('survival.missionText', "The mission's line under Your move.", missionText, UNDER_WAY.map((m) => [m] as [Mission])),
    cases('survival.stepMission', 'One judged move against a mission, with the eval and the position after it.', stepMission, [
      ...grid(UNDER_WAY, ['w'] as const, [-200, -60, -50, 0, 99, 100, 199, 250]),
      ...grid(UNDER_WAY.slice(6), ['w'] as const, [250], [FENS.traded, FENS.italian, FENS.carlsbad]),
    ]),
    cases('survival.judgedExtras', 'One judged move: the combo, its points, a moment settled, a mission stepped or set.', judgedExtras, grid(EXTRAS, PREFS, ['w'] as const, MOVES)),
    cases('survival.prepExtras', 'A move your prep answered: a point, at ×1.', prepExtras, EXTRAS.map((e) => [e] as [Extras])),
    cases('survival.firstMission', 'The first mission, where the prep runs out: the plan when the pawns form one, else from the eval.', firstMission, [
      ...grid([NO_EXTRAS], [{ missions: true }], COLORS, [-150, 0, 150, 300], FEN_LIST),
      ...grid(EXTRAS.slice(4), [{ missions: true }], ['w'] as const, [0], [FENS.carlsbad]),
      [NO_EXTRAS, { missions: false }, 'w', 0, FENS.carlsbad],
      [NO_EXTRAS, { missions: true }, 'w', 150],
    ]),
  ],
};

export default file;
