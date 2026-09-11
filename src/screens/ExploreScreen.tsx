import { useEffect, useMemo, useState } from 'react';
import { AddLineSheet } from '../components/AddLineSheet';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { Empty, Icons, Sheet, toast } from '../components/ui';
import { applySan, fenTurn, sansToMoveText, START_FEN, walkSan, type LegalMove } from '../chess/core';
import { openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { BOOK_LINES } from '../model/seed/bookLines';
import type { BookLine, ReferenceGame } from '../model/types';
import { repertoireList, useStore } from '../store/useStore';
import { childrenOf, fenAt } from '../model/repertoire';

export interface ExploreScreenProps {
  /** Optional starting line, e.g. jumped to from the repertoire browser. */
  initialPath?: string[];
  onConsumedInitial?: () => void;
}

type Tab = 'explorer' | 'book';

export function ExploreScreen({ initialPath, onConsumedInitial }: ExploreScreenProps) {
  const state = useStore();
  const [sans, setSans] = useState<string[]>(initialPath ?? []);
  const [cursor, setCursor] = useState(initialPath?.length ?? 0);
  const [tab, setTab] = useState<Tab>('explorer');
  const [orientation, setOrientation] = useState<'w' | 'b'>('w');
  const [addLine, setAddLine] = useState<
    { sans: string[]; note?: string; title: string; color?: 'w' | 'b' } | null
  >(null);
  const [bookLine, setBookLine] = useState<BookLine | null>(null);
  const [game, setGame] = useState<ReferenceGame | null>(null);

  useEffect(() => {
    if (initialPath) {
      setSans(initialPath);
      setCursor(initialPath.length);
      onConsumedInitial?.();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialPath]);

  const visible = sans.slice(0, cursor);
  const { fens } = useMemo(() => walkSan(visible, START_FEN), [visible]);
  const fen = fens[fens.length - 1];
  const opening = useMemo(() => openingNameForPath(referenceIndex(), visible), [visible]);

  /** Which of the user's repertoires already contain a move from this position. */
  const repMoves = useMemo(() => {
    const out: { repId: string; name: string; sans: string[] }[] = [];
    for (const rep of repertoireList(state)) {
      let nodeId: string | null = null;
      let ok = true;
      for (const san of visible) {
        const child: { id: string } | undefined = childrenOf(rep, nodeId).find((k) => k.san === san);
        if (!child) {
          ok = false;
          break;
        }
        nodeId = child.id;
      }
      if (!ok) continue;
      if (fenAt(rep, nodeId) !== fen) continue;
      out.push({ repId: rep.id, name: rep.name, sans: childrenOf(rep, nodeId).map((k) => k.san) });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.repertoires, visible, fen]);

  // Only star moves that are the user's own choice here — a move covered as an
  // opponent reply is a different thing, and is listed separately below.
  const turn = fenTurn(fen);
  const inRepertoire = repMoves
    .filter((r) => state.repertoires[r.repId]?.color === turn)
    .flatMap((r) => r.sans);

  const play = (san: string) => {
    const move = applySan(fen, san);
    if (!move) return;
    const next = [...visible, move.san];
    setSans(next);
    setCursor(next.length);
  };

  const onBoardMove = (move: LegalMove) => play(move.san);

  const relevantBookLines = useMemo(() => {
    if (!visible.length) return BOOK_LINES;
    return BOOK_LINES.filter((line) => visible.every((san, i) => line.moves[i] === san));
  }, [visible]);

  return (
    <>
      <div className="appbar">
        <div className="appbar-title">
          <div className="line" style={{ fontWeight: 650, fontSize: 17 }}>
            {opening?.name ?? 'Explore'}
          </div>
          <div className="sub">{opening?.eco ?? 'Reference database'}</div>
        </div>
        <button
          className="btn plain sm"
          onClick={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}
          aria-label="Flip board"
        >
          <Icons.flip size={19} />
        </button>
      </div>

      <div className="screen">
        <Board
          fen={fen}
          orientation={orientation}
          onMove={onBoardMove}
          movableFor="both"
          lastMove={lastMoveOf(visible)}
          showCoordinates={state.settings.showCoordinates}
          theme={state.settings.boardTheme}
        />

        <div className="spacer" />

        <div className="row" style={{ gap: 6 }}>
          <button className="btn sm ghost" disabled={cursor === 0} onClick={() => setCursor(0)}>
            <Icons.first size={16} />
          </button>
          <button className="btn sm ghost" disabled={cursor === 0} onClick={() => setCursor((c) => c - 1)}>
            <Icons.prev size={16} />
          </button>
          <div className="strip grow">
            {sans.length === 0 && <span className="tiny faint">Play a move or pick one below</span>}
            {sans.map((san, i) => (
              <button
                key={i}
                className={`mv${i === cursor - 1 ? ' current' : ''}`}
                onClick={() => setCursor(i + 1)}
              >
                {i % 2 === 0 ? `${i / 2 + 1}.` : ''}
                {san}
              </button>
            ))}
          </div>
          <button
            className="btn sm ghost"
            disabled={cursor >= sans.length}
            onClick={() => setCursor((c) => c + 1)}
          >
            <Icons.next size={16} />
          </button>
        </div>

        <div className="spacer" />

        <div className="segmented">
          <button className={tab === 'explorer' ? 'active' : ''} onClick={() => setTab('explorer')}>
            Moves
          </button>
          <button className={tab === 'book' ? 'active' : ''} onClick={() => setTab('book')}>
            Book lines {relevantBookLines.length ? `(${relevantBookLines.length})` : ''}
          </button>
        </div>

        <div className="spacer" />

        {tab === 'explorer' ? (
          <>
            <ExplorerPanel
              fen={fen}
              path={visible}
              inRepertoire={inRepertoire}
              onPlay={play}
              onPickGame={setGame}
            />
            {repMoves.length > 0 && (
              <div className="card" style={{ marginTop: 10 }}>
                <div className="section-title" style={{ margin: '0 0 6px' }}>In your repertoire</div>
                {repMoves.map((r) => (
                  <div key={r.repId} className="row between small" style={{ padding: '3px 0' }}>
                    <span className="muted truncate">
                      {r.name}
                      {state.repertoires[r.repId]?.color !== turn && (
                        <span className="faint"> · replies covered</span>
                      )}
                    </span>
                    <span style={{ fontWeight: 650 }}>{r.sans.join(', ') || '—'}</span>
                  </div>
                ))}
              </div>
            )}
            {visible.length > 0 && (
              <button
                className="btn primary block"
                style={{ marginTop: 12 }}
                onClick={() => setAddLine({ sans: visible, title: 'Add this line' })}
              >
                <Icons.plus size={18} /> Add line to repertoire
              </button>
            )}
          </>
        ) : (
          <div className="stack">
            {relevantBookLines.length === 0 && (
              <Empty icon="📖" title="No book lines from here" hint="Go back a few moves to see named variations." />
            )}
            {relevantBookLines.map((line) => (
              <button
                key={line.id}
                className="card"
                style={{ width: '100%', textAlign: 'left' }}
                onClick={() => setBookLine(line)}
              >
                <div className="row between">
                  <div className="grow" style={{ minWidth: 0 }}>
                    <div style={{ fontWeight: 650 }}>{line.name}</div>
                    <div className="tiny faint" style={{ marginTop: 3 }}>
                      {line.eco} · {Math.ceil(line.moves.length / 2)} moves · for{' '}
                      {line.forColor === 'w' ? 'White' : 'Black'}
                    </div>
                  </div>
                  <Icons.chevron size={18} />
                </div>
                <div className="small muted" style={{ marginTop: 8 }}>{line.summary}</div>
                {line.tags && (
                  <div className="row wrap" style={{ gap: 5, marginTop: 9 }}>
                    {line.tags.map((t) => (
                      <span key={t} className="chip">{t}</span>
                    ))}
                  </div>
                )}
              </button>
            ))}
          </div>
        )}
      </div>

      <BookLineSheet
        line={bookLine}
        onClose={() => setBookLine(null)}
        onPlay={(moves) => {
          setSans(moves);
          setCursor(moves.length);
          setBookLine(null);
          setTab('explorer');
        }}
        onAdd={(line) => {
          setBookLine(null);
          setAddLine({
            sans: line.moves,
            note: line.summary,
            title: line.name,
            color: line.forColor,
          });
        }}
      />

      <Sheet open={!!game} onClose={() => setGame(null)} title={game ? `${game.white} – ${game.black}` : ''}>
        {game && (
          <>
            <div className="tiny faint" style={{ marginBottom: 10 }}>
              {game.event} · {game.year} · {game.result}
            </div>
            <div className="card small mono" style={{ lineHeight: 1.8 }}>
              {sansToMoveText(game.moves)}
            </div>
            <div className="spacer" />
            <button
              className="btn primary block"
              onClick={() => {
                setSans(game.moves);
                setCursor(Math.min(game.moves.length, visible.length + 2));
                setGame(null);
                toast('Loaded — step through with the arrows');
              }}
            >
              Replay this game
            </button>
          </>
        )}
      </Sheet>

      <AddLineSheet
        open={!!addLine}
        onClose={() => setAddLine(null)}
        sans={addLine?.sans ?? []}
        note={addLine?.note}
        preferColor={addLine?.color}
        title={addLine?.title ?? 'Add to repertoire'}
      />
    </>
  );
}

function BookLineSheet({
  line,
  onClose,
  onPlay,
  onAdd,
}: {
  line: BookLine | null;
  onClose: () => void;
  onPlay: (moves: string[]) => void;
  onAdd: (line: BookLine) => void;
}) {
  return (
    <Sheet open={!!line} onClose={onClose} title={line?.name}>
      {line && (
        <>
          <div className="row" style={{ gap: 6, marginBottom: 10 }}>
            <span className="chip">{line.eco}</span>
            <span className={`chip ${line.forColor === 'w' ? 'white-side' : 'black-side'}`}>
              for {line.forColor === 'w' ? 'White' : 'Black'}
            </span>
          </div>
          <div className="small muted">{line.summary}</div>
          <div className="spacer" />
          <div className="card small mono" style={{ lineHeight: 1.9 }}>
            {sansToMoveText(line.moves)}
          </div>
          {line.ideas && (
            <>
              <div className="section-title">Ideas</div>
              <div className="stack">
                {line.ideas.map((idea, i) => (
                  <div key={i} className="card small muted">
                    {idea}
                  </div>
                ))}
              </div>
            </>
          )}
          <div className="spacer" />
          <div className="row" style={{ gap: 8 }}>
            <button className="btn ghost grow" onClick={() => onPlay(line.moves)}>
              Play through
            </button>
            <button className="btn primary grow" onClick={() => onAdd(line)}>
              Add to repertoire
            </button>
          </div>
        </>
      )}
    </Sheet>
  );
}

function lastMoveOf(sans: string[]) {
  if (!sans.length) return null;
  const { fens } = walkSan(sans.slice(0, -1));
  const move = applySan(fens[fens.length - 1], sans[sans.length - 1]);
  return move ? { from: move.from, to: move.to } : null;
}
