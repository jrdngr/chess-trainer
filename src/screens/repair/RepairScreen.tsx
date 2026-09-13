import { useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, toast } from '../../components/ui';
import { applySan, sansToMoveText, type LegalMove, type Square } from '../../chess/core';
import { candidateAnswers } from '../../model/gaps';
import { kindLabel, type RepairPrefs } from '../../model/modes';
import { formatGameCount, movePercent, lookup, totalGamesAt } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { displayName } from '../../model/repertoire';
import { buildRepairs, fixCandidates, isRepaired, lineFor, type RepairItem } from '../../model/repair';
import { repertoireList, useStore } from '../../store/useStore';
import { Setup } from './Setup';

export interface RepairScreenProps {
  /** Skip setup and work through the saved options — Next Up started this. */
  auto?: boolean;
  onImport: () => void;
  onExit: () => void;
}

export function RepairScreen({ auto, onImport, onExit }: RepairScreenProps) {
  const saved = useStore((s) => s.settings.repair);
  const [prefs, setPrefs] = useState<RepairPrefs | null>(() => (auto ? saved : null));
  if (!prefs) return <Setup onStart={setPrefs} onImport={onImport} onExit={onExit} />;
  // A queue nobody set up has no setup screen to fall back to.
  return <Working prefs={prefs} onExit={() => (auto ? onExit() : setPrefs(null))} />;
}

type Phase = 'ask' | 'right' | 'wrong' | 'choose';

function Working({ prefs, onExit }: { prefs: RepairPrefs; onExit: () => void }) {
  const state = useStore();
  const addLine = useStore((s) => s.addLine);
  const endRepair = useStore((s) => s.endRepair);
  const repaired = useStore((s) => s.repairedPosition);
  const settings = state.settings;
  const reps = repertoireList(state);
  const index = referenceIndex();

  /** Built once per visit: fixing an item changes the repertoire underneath. */
  const [queue] = useState<RepairItem[]>(() =>
    buildRepairs(state.importedGames, reps, {
      repertoireId: prefs.repertoireId,
      kinds: prefs.kinds,
      minGames: prefs.minGames,
      lossesOnly: prefs.lossesOnly,
      sort: prefs.sort,
      // The slips you made in the app count here too. Setup counts them, and
      // the home screen counts them, so a queue built without them promises a
      // number of positions and then opens onto nothing.
      mistakes: state.mistakes,
    }),
  );

  const [at, setAt] = useState(0);
  const [phase, setPhase] = useState<Phase>('ask');
  const [played, setPlayed] = useState<LegalMove | null>(null);
  const [done, setDone] = useState({ relearned: 0, added: 0 });

  const item = queue[at];

  const book = useMemo(
    () => (item ? candidateAnswers(index, item.fen, 5).map((m) => m.san) : []),
    [item, index],
  );
  const total = useMemo(
    () => (item ? totalGamesAt(lookup(index, item.fen)) : 0),
    [item, index],
  );

  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' | 'hint' }[] = [];
    if (!item || phase === 'ask' || phase === 'choose') return out;
    if (phase === 'wrong' && played) {
      out.push({ square: played.from, kind: 'bad' }, { square: played.to, kind: 'bad' });
    }
    const right = applySan(item.fen, item.expected[0]);
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [item, phase, played]);

  const next = () => {
    setPhase('ask');
    setPlayed(null);
    setAt((i) => i + 1);
  };

  const onMove = (move: LegalMove) => {
    if (!item || phase !== 'ask' || item.kind !== 'offprep') return;
    const right = isRepaired(item, move.san);
    setPlayed(move);
    setPhase(right ? 'right' : 'wrong');
    // The schedule hears about it either way: this is a real answer from a
    // real position, and getting it wrong is exactly what a lapse is.
    repaired(item.repertoireId, item.fen, move.san, item.expected[0] ?? '', right);
    endRepair({ relearned: right });
    if (right) setDone((d) => ({ ...d, relearned: d.relearned + 1 }));
    if (settings.hapticFeedback) haptic(right ? 12 : [18, 50, 18]);
  };

  const prepare = (san: string) => {
    if (!item) return;
    addLine(item.repertoireId, lineFor(item, san), 'manual');
    endRepair({ added: true });
    setDone((d) => ({ ...d, added: d.added + 1 }));
    toast(`${san} prepared`);
    next();
  };

  if (!item) {
    return (
      <>
        <AppBar title="Repair" onClose={onExit} />
        <div className="screen no-nav">
          <div className="hero" style={{ marginTop: 8 }}>
            <div className="big">{done.relearned + done.added}</div>
            <div className="lbl">
              {done.relearned + done.added === 1 ? 'repair made' : 'repairs made'}
            </div>
            <div className="pills">
              <span className="pill">
                <b>{done.relearned}</b> relearned
              </span>
              <span className="pill">
                <b>{done.added}</b> added
              </span>
            </div>
          </div>
          <button className="btn primary block xl mt-16" onClick={onExit}>
            Back to options
          </button>
        </div>
      </>
    );
  }

  const rep = state.repertoires[item.repertoireId];
  const unprepared = item.kind === 'unprepared';
  const answered = phase === 'right' || phase === 'wrong';

  return (
    <>
      <AppBar
        title={kindLabel(item.kind)}
        subtitle={rep ? displayName(rep.name) : undefined}
        onClose={onExit}
        actions={
          <span className="num muted small appbar-gap" style={{ textAlign: 'right' }}>
            {at + 1}/{queue.length}
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={answered && played ? played.after : item.fen}
          orientation={item.color}
          interactive={phase === 'ask' && !unprepared}
          movableFor={item.color}
          onMove={onMove}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'wrong'}
          captured
        />

        <div className="spacer" />

        {phase === 'ask' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${item.color}`} />
              {unprepared ? 'Nothing prepared here' : 'Your move'}
            </div>
            <div className="ctx">
              {item.games} of your games · {item.results.wins}W {item.results.draws}D{' '}
              {item.results.losses}L
            </div>
          </div>
        )}

        {answered && (
          <>
            <div className="row between">
              <div className={`verdict ${phase === 'right' ? 'ok' : 'no'}`} style={{ padding: 0 }}>
                <span className="ico">
                  {phase === 'right' ? <Icons.check size={16} /> : <Icons.cross size={14} />}
                </span>
                {phase === 'right' ? 'That is your prep' : 'Not your prep'}
              </div>
              <button className="btn primary sm" onClick={next}>
                Next
                <Icons.next size={16} />
              </button>
            </div>
            {phase === 'wrong' && (
              <div className="compare mt-8">
                <div className="good">
                  <div className="k">Repertoire</div>
                  <div className="v">{item.expected[0]}</div>
                </div>
                <div className="bad">
                  <div className="k">Played</div>
                  <div className="v">{played?.san}</div>
                </div>
              </div>
            )}
          </>
        )}

        {unprepared && (
          <>
            <Section title="Pick what to prepare" />
            <div className="list">
              {fixCandidates(item, book).map((san) => {
                const mine = item.played.find((p) => p.san === san);
                const entry = lookup(index, item.fen)?.moves.find((m) => m.san === san);
                return (
                  <button className="list-row" key={san} onClick={() => prepare(san)}>
                    <span className="tree-san">{san}</span>
                    <span className="grow">
                      <div className="meta">
                        {mine ? `you played it ${mine.count}×` : ''}
                        {mine && entry ? ' · ' : ''}
                        {entry
                          ? `${formatGameCount(entry.games)} games · ${Math.round(movePercent(entry, total))}% of replies`
                          : mine
                            ? ''
                            : 'not in the book here'}
                      </div>
                    </span>
                    <Icons.plus size={18} />
                  </button>
                );
              })}
            </div>
            <button className="btn block mt-8" onClick={next}>
              Skip this one
            </button>
          </>
        )}

        <Section title="How you got here" />
        <div className="card">
          <div className="movetext">{item.lineText}</div>
        </div>

        {answered && item.path.length > 0 && (
          <div className="note">
            The full line: {sansToMoveText([...item.path, item.expected[0]])}
          </div>
        )}
      </div>
    </>
  );
}
