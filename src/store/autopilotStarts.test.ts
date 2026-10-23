import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_SELECTION } from '../model/selection';
import { DEFAULT_SETTINGS, itemsFor, repertoireList, useStore } from './useStore';
import { afterRound, nextRound, NO_HISTORY } from './recommendation';

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

/** Every position of the repertoire answered once, and the one at `path` due now. */
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
      },
    ]),
  );
  useStore.setState({ cards });
}

describe("Autopilot's runs", () => {
  it('are all Survival runs, and start at a position you are due on', () => {
    dueAt('e4 e5 Nf3 Nc6 Bb5 Nf6');
    const round = nextRound(useStore.getState(), NO_HISTORY)!;
    expect(round.at).toEqual('e4 e5 Nf3 Nc6 Bb5 Nf6'.split(' '));
  });

  it('never start at a position twice running', () => {
    dueAt('e4 e5 Nf3 Nc6 Bb5 Nf6');
    const first = nextRound(useStore.getState(), NO_HISTORY)!;
    const history = afterRound(NO_HISTORY, first, useStore.getState().settings.selection);
    expect(nextRound(useStore.getState(), history)!.at).toBeNull();
  });

  it('start inside with nothing due', () => {
    dueAt('');
    expect(nextRound(useStore.getState(), NO_HISTORY)!.at).toBeNull();
  });
});
