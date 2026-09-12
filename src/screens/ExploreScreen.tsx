import { useEffect, useMemo, useState } from 'react';
import { AddLineSheet } from '../components/AddLineSheet';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { Empty, IconButton, Icons, MoveStrip, Section, Segmented, Sheet } from '../components/ui';
import { applySan, fenTurn, lastMoveOf, sansToMoveText, START_FEN, walkSan, type LegalMove } from '../chess/core';
import { openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { BOOK_LINES } from '../model/seed/bookLines';
import type { BookLine, ReferenceGame, Repertoire, RepMove } from '../model/types';
import { repertoireList, useStore } from '../store/useStore';
import { childrenOf, displayName, fenAt } from '../model/repertoire';

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
      const nodeId = nodeAlong(rep, visible);
      if (nodeId === undefined || fenAt(rep, nodeId) !== fen) continue;
      out.push({ repId: rep.id, name: rep.name, sans: childrenOf(rep, nodeId).map((k) => k.san) });
    }
    return out;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.repertoires, visible, fen]);

  // Only star moves that are the user's own choice here; a move covered as an
  // opponent reply is listed separately below.
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
          {opening ? (
            <>
              <div className="line" style={{ fontSize: 20 }}>{opening.name}</div>
              <div className="sub">{opening.eco}</div>
            </>
          ) : (
            <h1>Explore</h1>
          )}
        </div>
        <IconButton label="Flip board" onClick={() => setOrientation((o) => (o === 'w' ? 'b' : 'w'))}>
          <Icons.flip size={20} />
        </IconButton>
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

        <div className="spacer sm" />
        <MoveStrip sans={sans} cursor={cursor} onSeek={setCursor} hint="Play a move" />
        <div className="spacer sm" />

        <Segmented
          value={tab}
          options={[
            { value: 'explorer', label: 'Moves' },
            {
              value: 'book',
              label: `Lines${relevantBookLines.length ? ` · ${relevantBookLines.length}` : ''}`,
            },
          ]}
          onChange={setTab}
        />

        <div className="spacer sm" />

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
              <div className="list mt-8">
                {repMoves.map((r) => (
                  <div key={r.repId} className="list-row" style={{ minHeight: 46 }}>
                    <span className={`side ${state.repertoires[r.repId]?.color ?? 'w'}`} />
                    <span className="grow truncate small muted">{displayName(r.name)}</span>
                    <span style={{ fontWeight: 700 }}>{r.sans.join(', ') || '—'}</span>
                  </div>
                ))}
              </div>
            )}
            {visible.length > 0 && (
              <button
                className="btn primary block mt-12"
                onClick={() => setAddLine({ sans: visible, title: 'Add to repertoire' })}
              >
                <Icons.plus size={18} /> Add to repertoire
              </button>
            )}
          </>
        ) : (
          <div className="stack">
            {relevantBookLines.length === 0 && (
              <Empty title="No named lines from here" hint="Step back to see more" />
            )}
            {relevantBookLines.map((line) => (
              <button key={line.id} className="card tap" onClick={() => setBookLine(line)}>
                <div className="row between">
                  <div className="grow" style={{ minWidth: 0 }}>
                    <div style={{ fontWeight: 700 }}>{line.name}</div>
                    <div className="tiny faint" style={{ marginTop: 2 }}>
                      {line.eco} · {line.forColor === 'w' ? 'White' : 'Black'} · {Math.ceil(line.moves.length / 2)} moves
                    </div>
                  </div>
                  <Icons.chevron size={18} />
                </div>
                <div className="small muted" style={{ marginTop: 8 }}>{line.summary}</div>
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
            <div className="row gap-6" style={{ marginBottom: 12 }}>
              <span className="chip">{game.result}</span>
              <span className="tiny faint truncate">{game.event} · {game.year}</span>
            </div>
            <div className="card movetext">{sansToMoveText(game.moves)}</div>
            <div className="spacer" />
            <button
              className="btn primary block"
              onClick={() => {
                setSans(game.moves);
                setCursor(Math.min(game.moves.length, visible.length + 2));
                setGame(null);
              }}
            >
              <Icons.play size={16} /> Replay
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
          <div className="row gap-6" style={{ marginBottom: 12 }}>
            <span className="chip">{line.eco}</span>
            <span className={`chip ${line.forColor}`}>{line.forColor === 'w' ? 'White' : 'Black'}</span>
          </div>
          <div className="muted">{line.summary}</div>
          <div className="spacer sm" />
          <div className="card movetext">{sansToMoveText(line.moves)}</div>
          {line.ideas && (
            <>
              <Section title="Ideas" />
              <div className="list">
                {line.ideas.map((idea, i) => (
                  <div key={i} className="list-row small muted" style={{ minHeight: 44 }}>
                    {idea}
                  </div>
                ))}
              </div>
            </>
          )}
          <div className="spacer" />
          <div className="row gap-8">
            <button className="btn grow" onClick={() => onPlay(line.moves)}>
              <Icons.play size={16} /> Play
            </button>
            <button className="btn primary grow" onClick={() => onAdd(line)}>
              <Icons.plus size={18} /> Add
            </button>
          </div>
        </>
      )}
    </Sheet>
  );
}

/** The node reached by following `sans` down a repertoire, or undefined if it leaves the tree. */
function nodeAlong(rep: Repertoire, sans: string[]): string | null | undefined {
  let nodeId: string | null = null;
  for (const san of sans) {
    const child: RepMove | undefined = childrenOf(rep, nodeId).find((k) => k.san === san);
    if (!child) return undefined;
    nodeId = child.id;
  }
  return nodeId;
}
