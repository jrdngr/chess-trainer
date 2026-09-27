import { beforeEach, describe, expect, it } from 'vitest';
import { DEFAULT_SELECTION } from '../model/selection';
import { nodeAtLine } from '../model/repertoire';
import { appendEvent, EVENT_CAP, REMOVED_CAP, setEventPlace, type AppEvent } from '../model/events';
import { DEFAULT_SETTINGS, repertoireList, useStore } from './useStore';

beforeEach(() => {
  setEventPlace('repertoire');
  useStore.setState({
    ready: true,
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    log: [],
    events: [],
    importedGames: [],
    mistakes: [],
    settings: { ...DEFAULT_SETTINGS, favoriteOpenings: [], selection: { ...DEFAULT_SELECTION } },
  });
});

const state = () => useStore.getState();
const last = () => state().events.at(-1)!;

describe('the event log', () => {
  it('records an added line with where it was made', () => {
    const repId = state().ensureRepertoire('w');
    state().addLine(repId, 'd4 d5 c4'.split(' '), 'reference');
    expect(last()).toMatchObject({ kind: 'add', line: 'd4 d5 c4', added: 3, via: 'repertoire', color: 'w' });
    // Nothing new, nothing logged.
    state().addLine(repId, 'd4 d5'.split(' '), 'reference');
    expect(state().events).toHaveLength(1);
  });

  it('records a delete, and the reply it left behind can be read off it', () => {
    // The case that started this: deleting the answer to 3...c5 leaves 3...c5.
    const repId = state().ensureRepertoire('w');
    state().addLine(repId, 'd4 d5 c4 c5 cxd5 Qxd5 Nc3'.split(' '), 'reference');
    const node = nodeAtLine(repertoireList(state())[0], 'd4 d5 c4 c5 cxd5'.split(' '))!;
    state().removeNode(repId, node.id);
    expect(last()).toMatchObject({
      kind: 'remove',
      line: 'd4 d5 c4 c5 cxd5',
      removed: ['d4 d5 c4 c5 cxd5 Qxd5 Nc3'],
      count: 3,
    });
  });

  it('says where a change came from when the screen does not', () => {
    setEventPlace('autopilot');
    const repId = state().ensureRepertoire('b');
    state().addLine(repId, 'e4 c5'.split(' '), 'reference', 'growth');
    expect(last().via).toBe('growth');
  });

  it('records a preferred move and a Tidy switch with what it replaced', () => {
    const repId = state().ensureRepertoire('w');
    state().addLine(repId, 'd4 d5 c4 e6 Nc3'.split(' '), 'reference');
    state().addLine(repId, 'd4 d5 c4 e6 Nf3'.split(' '), 'reference');
    const rep = repertoireList(state())[0];
    state().preferMove(repId, nodeAtLine(rep, 'd4 d5 c4 e6 Nf3'.split(' '))!.id);
    expect(last()).toMatchObject({ kind: 'prefer', line: 'd4 d5 c4 e6 Nf3' });

    state().addLine(repId, 'd4 d5 c4 e6 Nc3 Nf6 Bg5'.split(' '), 'reference');
    const bg5 = nodeAtLine(repertoireList(state())[0], 'd4 d5 c4 e6 Nc3 Nf6 Bg5'.split(' '))!;
    const undo = state().tidySwitch(repId, bg5.id, 'cxd5')!;
    expect(last()).toMatchObject({ kind: 'tidy-switch', line: 'd4 d5 c4 e6 Nc3 Nf6 Bg5', to: 'cxd5', count: 1 });
    undo();
    expect(last()).toMatchObject({ kind: 'tidy-undo', to: 'cxd5' });
  });

  it('records what Growth offered and what was picked', () => {
    state().logEvent({ kind: 'growth-offer', via: 'growth', color: 'w', line: 'd4 d5 c4 c5', offered: ['cxd5', 'Nf3'], from: 'kept' });
    expect(last()).toMatchObject({ kind: 'growth-offer', from: 'kept', offered: ['cxd5', 'Nf3'] });
  });

  it('keeps the newest events up to the cap', () => {
    let events: AppEvent[] = [];
    for (let i = 0; i < EVENT_CAP + 5; i += 1) {
      events = appendEvent(events, { kind: 'growth-start', rows: [], picked: String(i), start: 'test' }, i);
    }
    expect(events).toHaveLength(EVENT_CAP);
    expect(events[0]).toMatchObject({ picked: '5' });
  });

  it('lists at most a handful of the lines a big delete took', () => {
    const repId = state().ensureRepertoire('w');
    for (const reply of ['a6', 'a5', 'b6', 'b5', 'c6', 'c5', 'd6', 'd5', 'e6', 'e5', 'f6', 'f5', 'g6', 'g5', 'h6', 'h5', 'Na6', 'Nc6', 'Nf6', 'Nh6', 'Nf6']) {
      state().addLine(repId, ['e4', reply, 'Nf3'], 'reference');
    }
    const e4 = nodeAtLine(repertoireList(state())[0], ['e4'])!;
    state().removeNode(repId, e4.id);
    const event = last() as Extract<AppEvent, { kind: 'remove' }>;
    expect(event.removed).toHaveLength(REMOVED_CAP);
    expect(event.count).toBe(41);
  });
});
