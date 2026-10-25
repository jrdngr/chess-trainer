import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_SELECTION } from '../model/selection';
import { DEFAULT_SETTINGS, itemsFor, repertoireList, useStore } from './useStore';
import { startKind } from '../model/autopilot';
import { EMPTY_SCORE } from '../model/scoring';
import { nextRound, NO_HISTORY } from './recommendation';

const RUY = 'e4 e5 Nf3 Nc6 Bb5';

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
    settings: { ...DEFAULT_SETTINGS, favoriteOpenings: [RUY], selection: { ...DEFAULT_SELECTION, color: 'w', opening: RUY } },
  });
  const white = useStore.getState().ensureRepertoire('w');
  for (const line of ['e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7', 'e4 e5 Nf3 Nc6 Bb5 Nf6 O-O Nxe4 d4 Nd6']) {
    useStore.getState().addLine(white, line.split(' '), 'book');
  }
});

/** Every position of the repertoire asked last run, and the one at `path` long enough ago to be due. */
function dueAt(path: string): void {
  const rep = repertoireList(useStore.getState())[0];
  const now = Date.now();
  const cards = Object.fromEntries(
    itemsFor(rep).map((item) => [
      item.cardId,
      {
        id: item.cardId,
        repertoireId: rep.id,
        key: item.key,
        fen: item.fen,
        stage: 'review' as const,
        step: 0,
        interval: 5,
        ease: 2.5,
        reps: 3,
        lapses: 0,
        correct: 3,
        incorrect: 0,
        due: item.pathSans.join(' ') === path ? now - 1000 : now + 86_400_000,
        lastReviewed: now - 86_400_000,
        createdAt: now - 10 * 86_400_000,
        testedRound: item.pathSans.join(' ') === path ? 0 : 19,
      },
    ]),
  );
  useStore.setState({ cards, score: { ...EMPTY_SCORE, lineRounds: 20 } });
  useStore.getState().endRound({ mode: 'survival', openingId: RUY, color: 'w', answered: 1, correct: 1, perfect: false });
}

describe("Autopilot's runs", () => {
  it('are all Survival runs, and start at a position you are due on', () => {
    dueAt('e4 e5 Nf3 Nc6 Bb5 Nf6');
    const round = nextRound(useStore.getState(), NO_HISTORY)!;
    expect(round.at).toEqual('e4 e5 Nf3 Nc6 Bb5 Nf6'.split(' '));
  });

  it('never start deeper in twice running, even across sessions', () => {
    dueAt('e4 e5 Nf3 Nc6 Bb5 Nf6');
    const first = nextRound(useStore.getState(), NO_HISTORY)!;
    useStore.getState().noteStart(startKind(first));
    expect(nextRound(useStore.getState(), NO_HISTORY)!.at).toBeNull();
  });

  it('start at the opening position with nothing due', () => {
    dueAt('-');
    const round = nextRound(useStore.getState(), NO_HISTORY)!;
    expect(startKind(round)).toBe('position');
  });

  it('start from move one when the way in has never been played', () => {
    dueAt('-');
    const cards = { ...useStore.getState().cards };
    for (const id of Object.keys(cards)) if (cards[id].key === itemsFor(repertoireList(useStore.getState())[0])[0].key) delete cards[id].testedRound;
    useStore.setState({ cards });
    expect(startKind(nextRound(useStore.getState(), NO_HISTORY)!)).toBe('cold');
  });

  it('start from move one every third run at the latest', () => {
    dueAt('-');
    const kinds = Array.from({ length: 6 }, () => {
      const kind = startKind(nextRound(useStore.getState(), NO_HISTORY)!);
      useStore.getState().noteStart(kind);
      return kind;
    });
    expect(kinds).toEqual(['position', 'position', 'cold', 'position', 'position', 'cold']);
  });

  it('start the first run of an opening at its position, whatever is owed', () => {
    dueAt('e4 e5 Nf3 Nc6 Bb5 Nf6');
    const cards = { ...useStore.getState().cards };
    for (const id of Object.keys(cards)) delete cards[id].testedRound;
    useStore.setState({ cards, score: { ...EMPTY_SCORE, lineRounds: 20, starts: ['position', 'position'] } });
    expect(startKind(nextRound(useStore.getState(), NO_HISTORY)!)).toBe('position');
  });
});
