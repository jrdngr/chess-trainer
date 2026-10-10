import { beforeEach, describe, expect, it } from 'vitest';
import { autopilotModes, AUTO_DRILL, AUTO_GROWTH, DEFAULT_AUTOPILOT } from '../model/autopilotPrefs';
import { DEFAULT_SELECTION } from '../model/selection';
import { DEFAULT_SETTINGS, useStore } from './useStore';
import { nextRound, NO_HISTORY } from './recommendation';

const SOURCES = import.meta.glob<string>(['../screens/**/*.tsx', './recommendation.ts'], {
  query: '?raw',
  import: 'default',
  eager: true,
});

const LINES = [
  'e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6',
  'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6',
  'e4 e6 d4 d5 Nc3 Bb4 e5 c5',
];

beforeEach(() => {
  useStore.setState({
    ready: true,
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    log: [],
    importedGames: [],
    mistakes: [],
    settings: { ...DEFAULT_SETTINGS, favoriteOpenings: [], selection: { ...DEFAULT_SELECTION, color: 'w' } },
  });
  const id = useStore.getState().ensureRepertoire('w');
  for (const line of LINES) useStore.getState().addLine(id, line.split(' '), 'book');
});

describe("Autopilot's settings", () => {
  it('pick the same round whatever the modes are set to', () => {
    const before = nextRound(useStore.getState(), NO_HISTORY);
    expect(before).not.toBeNull();
    const { setModePrefs, setSurvivalPrefs } = useStore.getState();
    setSurvivalPrefs({ steer: 'book', clock: 'move10', moveScores: false, boardGlow: false });
    setModePrefs('drill', { form: 'lines', draw: 'cram', newPerSession: 0, followLine: false, weakFirst: true, explain: false, batchSimilar: false, clock: 'move10' });
    setModePrefs('growth', { minShare: 0.2, maxPly: 8, nudgePriority: 'habit', nudgePawns: true });
    expect(nextRound(useStore.getState(), NO_HISTORY)).toEqual(before);
  });

  it('play every mode on fixed values, with only the feedback toggles yours', () => {
    expect(autopilotModes(DEFAULT_AUTOPILOT)).toEqual({
      survival: { steer: 'lines', clock: 'off', moveScores: true, boardGlow: true, moments: true, missions: true, combo: true },
      drill: AUTO_DRILL,
      growth: AUTO_GROWTH,
    });
    expect(autopilotModes({ moveScores: false, boardGlow: false, modeTesting: false }).survival).toMatchObject({ moveScores: false, boardGlow: false });
    expect(AUTO_DRILL).toMatchObject({ clock: 'off', explain: true, followLine: true, newPerSession: 8, batchSimilar: true });
    expect(AUTO_GROWTH).toEqual({ minShare: 1, maxPly: 18, nudgePriority: 'transposition', nudgePawns: false });
  });

  it('are saved apart from the modes, and come back for an older save', () => {
    useStore.getState().setModePrefs('autopilot', { boardGlow: false });
    const settings = useStore.getState().settings;
    expect(settings.autopilot).toEqual({ moveScores: true, boardGlow: false, modeTesting: false });
    expect(settings.survival.boardGlow).toBe(true);
  });

  /**
   * Every screen an Autopilot round can show reads its options through
   * `useModePrefs`, so a mode's saved setup never reaches a round. A direct
   * read off settings would bypass that.
   */
  it('are the only options any Autopilot screen reads', () => {
    const files = [
      'screens/autopilot/AutopilotScreen.tsx',
      'screens/survival/SurvivalScreen.tsx',
      'screens/survival/End.tsx',
      'screens/growth/GrowthScreen.tsx',
      'screens/drill/LineDrill.tsx',
      'screens/drill/DrillSession.tsx',
      'store/recommendation.ts',
    ];
    for (const file of files) {
      const source = SOURCES[file.startsWith('store/') ? `./${file.slice(6)}` : `../${file}`];
      expect(source, file).toBeDefined();
      expect(source, file).not.toMatch(/settings\.(survival|drill|growth)\b/);
    }
  });
});
