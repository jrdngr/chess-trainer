import { beforeEach, describe, expect, it } from 'vitest';
import { positionKey, walkSan } from '../chess/core';
import { DEFAULT_SELECTION } from '../model/selection';
import { cardId } from '../model/session';
import { createCard } from '../model/srs';
import { nodeAtLine } from '../model/repertoire';
import { DEFAULT_SETTINGS, repertoireList, useStore } from './useStore';

const EXCHANGE = 'd4 d5 c4 e6 cxd5 exd5 Nc3 Nf6 Nf3 c6';

beforeEach(() => {
  useStore.setState({
    ready: true,
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    log: [],
    importedGames: [],
    mistakes: [],
    settings: { ...DEFAULT_SETTINGS, favoriteOpenings: [], selection: { ...DEFAULT_SELECTION } },
  });
});

const state = () => useStore.getState();

describe('a Tidy switch', () => {
  it('starts the position over, and undoes cleanly', () => {
    const repId = state().ensureRepertoire('w');
    state().addLine(repId, `${EXCHANGE} Bg5 Be7 e3`.split(' '), 'reference');
    const fen = walkSan(EXCHANGE.split(' ')).fens.at(-1)!;
    const key = positionKey(fen);
    const id = cardId(repId, key);
    useStore.setState({
      cards: { [id]: { ...createCard(id, repId, key, fen), stage: 'review', lapses: 2 } },
      mistakes: [
        { id: `${repId}#${key}`, at: 1, source: 'openingRun', repertoireId: repId, key, fen, played: 'g3', expected: 'Bg5' },
      ],
    });
    const rep = repertoireList(state())[0];
    const node = nodeAtLine(rep, [...EXCHANGE.split(' '), 'Bg5'])!;

    const undo = state().tidySwitch(repId, node.id, 'g3')!;
    const after = repertoireList(state())[0];
    expect(nodeAtLine(after, [...EXCHANGE.split(' '), 'g3'])).not.toBeNull();
    expect(nodeAtLine(after, [...EXCHANGE.split(' '), 'Bg5'])).toBeNull();
    expect(state().cards[id]).toBeUndefined();
    expect(state().mistakes).toHaveLength(0);

    undo();
    expect(nodeAtLine(repertoireList(state())[0], [...EXCHANGE.split(' '), 'Bg5', 'Be7'])).not.toBeNull();
    expect(state().cards[id]?.lapses).toBe(2);
    expect(state().mistakes).toHaveLength(1);
  });
});
