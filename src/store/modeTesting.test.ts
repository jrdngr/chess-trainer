import { beforeEach, describe, expect, it } from 'vitest';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { TEST_VARIANTS, testCycle, type TestVariant } from '../model/autopilot';
import { DEFAULT_SELECTION } from '../model/selection';
import { DEFAULT_SETTINGS, useStore } from './useStore';
import { afterRound, NO_HISTORY, pickRound, playedRound, tookTest, type AutoHistory, type AutoRound } from './recommendation';

const RUY = 'e4 e5 Nf3 Nc6 Bb5';
const SICILIAN = 'e4 c5';

beforeEach(() => {
  useStore.setState({
    ready: true,
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    lineCards: {},
    log: [],
    importedGames: [],
    mistakes: [],
    settings: {
      ...DEFAULT_SETTINGS,
      autopilot: { ...DEFAULT_SETTINGS.autopilot, modeTesting: true },
      favoriteOpenings: [RUY, SICILIAN],
      selection: { ...DEFAULT_SELECTION, color: 'random', opening: ANY_FAVORITE },
    },
  });
  const white = useStore.getState().ensureRepertoire('w');
  for (const line of ['e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7', 'e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6', 'e4 e5 Nf3 Nc6 Bb5 d6 d4 Bd7 Nc3 Nf6']) {
    useStore.getState().addLine(white, line.split(' '), 'book');
  }
  const black = useStore.getState().ensureRepertoire('b');
  useStore.getState().addLine(black, 'e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6'.split(' '), 'book');
});

/** The case a round is, read off the round itself. */
function variantOf(round: AutoRound): TestVariant {
  if (round.mode !== 'survival') return round.mode;
  return round.pick.start === 'first' ? 'coldStart' : 'survival';
}

const colorOf = (round: AutoRound) => (round.mode === 'survival' ? round.pick.color : round.color);

describe('Mode Testing', () => {
  it('builds a cycle of every variant on every side', () => {
    const cycle = testCycle(['w', 'b'], Math.random);
    expect(cycle).toHaveLength(TEST_VARIANTS.length * 2);
    expect(new Set(cycle.map((c) => `${c.variant}${c.color}`)).size).toBe(cycle.length);
  });

  it('plays every case once, on its side, before any repeats', () => {
    let history: AutoHistory = NO_HISTORY;
    const seen: string[] = [];
    for (let i = 0; i < 10; i += 1) {
      const picked = pickRound(useStore.getState(), history);
      expect(picked.round).not.toBeNull();
      const round = picked.round!;
      expect(picked.test).toBeDefined();
      expect(variantOf(round)).toBe(picked.test!.variant);
      expect(colorOf(round)).toBe(picked.test!.color);
      seen.push(`${picked.test!.variant}${picked.test!.color}`);
      playedRound(picked.within);
      tookTest(picked.test!);
      history = afterRound(history, round, picked.within);
    }
    // Every case runs here, once each.
    expect(new Set(seen).size).toBe(10);
  });

  it('leaves the mix alone when off', () => {
    useStore.setState({ settings: { ...useStore.getState().settings, autopilot: { ...DEFAULT_SETTINGS.autopilot } } });
    expect(pickRound(useStore.getState(), NO_HISTORY).test).toBeUndefined();
  });
});
