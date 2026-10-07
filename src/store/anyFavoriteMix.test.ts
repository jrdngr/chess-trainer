import { beforeEach, describe, expect, it } from 'vitest';
import { ANY_FAVORITE } from '../model/anyFavorite';
import { DEFAULT_SELECTION } from '../model/selection';
import { DEFAULT_SETTINGS, useStore } from './useStore';
import { afterRound, nextRound, NO_HISTORY, withSelection, type AutoHistory } from './recommendation';

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
      favoriteOpenings: [RUY, SICILIAN],
      selection: { ...DEFAULT_SELECTION, color: 'random', opening: ANY_FAVORITE },
    },
  });
  const white = useStore.getState().ensureRepertoire('w');
  for (const line of ['e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7', 'e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6', 'e4 e5 Nf3 Nc6 Bb5 d6 d4 Bd7 Nc3 Nf6']) {
    useStore.getState().addLine(white, line.split(' '), 'book');
  }
  const black = useStore.getState().ensureRepertoire('b');
  useStore.getState().addLine(black, 'e4 c5 Nf3 d6'.split(' '), 'book');
});

describe('Autopilot under Any favorite', () => {
  it('weighs what all favorites owe, and drills the favorite owing the most', () => {
    const state = () => useStore.getState();
    const mix = state().settings.selection;
    // Every round lands on the Sicilian, which owes next to nothing.
    const sicilian = { color: 'b' as const, opening: SICILIAN };
    let history: AutoHistory = NO_HISTORY;
    const modes: string[] = [];
    for (let i = 0; i < 4; i += 1) {
      const round = nextRound(withSelection(state(), sicilian), history, mix)!;
      modes.push(round.mode);
      if (round.mode === 'drillPositions' || round.mode === 'drillLines') {
        expect(round.color).toBe('w');
        expect(round.openingId).toBe(RUY);
      }
      history = afterRound(history, round, sicilian);
    }
    expect(modes.some((mode) => mode !== 'survival')).toBe(true);
  });
});
