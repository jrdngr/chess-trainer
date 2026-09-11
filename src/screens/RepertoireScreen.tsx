import { useMemo, useState } from 'react';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { Empty, Icons, Sheet, toast } from '../components/ui';
import { fenTurn, sansToMoveText, type LegalMove } from '../chess/core';
import { childrenOf, fenAt, pathTo, subtreeIds } from '../model/repertoire';
import { lookup, openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { branchItems, type TrainingItem } from '../model/session';
import { describeDue } from '../model/srs';
import type { Card, RepMove, Repertoire } from '../model/types';
import { repertoireList, useStore } from '../store/useStore';

export interface RepertoireScreenProps {
  onStart: (queue: TrainingItem[], title: string) => void;
  onImport: () => void;
  onExploreFrom: (sans: string[]) => void;
}

export function RepertoireScreen({ onStart, onImport, onExploreFrom }: RepertoireScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const [openId, setOpenId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const rep = openId ? state.repertoires[openId] : null;

  if (rep) {
    return (
      <RepertoireBrowser
        rep={rep}
        onBack={() => setOpenId(null)}
        onStart={onStart}
        onExploreFrom={onExploreFrom}
      />
    );
  }

  return (
    <>
      <div className="appbar">
        <div className="appbar-title">
          <h1>Repertoire</h1>
        </div>
        <button className="btn plain sm" onClick={onImport} aria-label="Import">
          <Icons.download size={20} />
        </button>
        <button className="btn plain sm" onClick={() => setCreating(true)} aria-label="New repertoire">
          <Icons.plus size={22} />
        </button>
      </div>

      <div className="screen">
        {reps.length === 0 && (
          <Empty icon="♟" title="No repertoires yet" hint="Create one, or import your games." />
        )}
        {reps.map((r) => (
          <RepertoireCard key={r.id} rep={r} cards={state.cards} onOpen={() => setOpenId(r.id)} />
        ))}

        <div className="spacer" />
        <button className="btn ghost block" onClick={onImport}>
          <Icons.download size={18} /> Import games or PGN
        </button>
      </div>

      <NewRepertoireSheet open={creating} onClose={() => setCreating(false)} />
    </>
  );
}

function RepertoireCard({
  rep,
  cards,
  onOpen,
}: {
  rep: Repertoire;
  cards: Record<string, Card>;
  onOpen: () => void;
}) {
  const nodes = Object.keys(rep.nodes).length;
  const trained = Object.values(cards).filter((c) => c.repertoireId === rep.id).length;
  const firstMoves = childrenOf(rep, null)
    .map((m) => m.san)
    .slice(0, 4);
  return (
    <button className="card" style={{ width: '100%', textAlign: 'left' }} onClick={onOpen}>
      <div className="row between">
        <div className="row" style={{ gap: 8 }}>
          <span className={`chip ${rep.color === 'w' ? 'white-side' : 'black-side'}`}>
            {rep.color === 'w' ? 'White' : 'Black'}
          </span>
          <span style={{ fontWeight: 650 }}>{rep.name}</span>
        </div>
        <Icons.chevron size={18} />
      </div>
      <div className="tiny faint" style={{ marginTop: 7 }}>
        {nodes} moves · {trained} positions in rotation
      </div>
      {firstMoves.length > 0 && (
        <div className="row" style={{ gap: 5, marginTop: 9 }}>
          {firstMoves.map((san) => (
            <span key={san} className="chip">{san}</span>
          ))}
        </div>
      )}
    </button>
  );
}

function NewRepertoireSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const add = useStore((s) => s.addRepertoire);
  const [name, setName] = useState('');
  const [color, setColor] = useState<'w' | 'b'>('w');
  return (
    <Sheet open={open} onClose={onClose} title="New repertoire">
      <input
        className="field"
        placeholder="e.g. White — London System"
        value={name}
        onChange={(e) => setName(e.target.value)}
      />
      <div className="spacer" />
      <div className="segmented">
        <button className={color === 'w' ? 'active' : ''} onClick={() => setColor('w')}>
          I play White
        </button>
        <button className={color === 'b' ? 'active' : ''} onClick={() => setColor('b')}>
          I play Black
        </button>
      </div>
      <div className="spacer" />
      <button
        className="btn primary block"
        disabled={!name.trim()}
        onClick={() => {
          add(name.trim(), color);
          setName('');
          onClose();
          toast('Repertoire created');
        }}
      >
        Create
      </button>
    </Sheet>
  );
}

/* ── browser ───────────────────────────────────────────────────────────── */

function RepertoireBrowser({
  rep,
  onBack,
  onStart,
  onExploreFrom,
}: {
  rep: Repertoire;
  onBack: () => void;
  onStart: (queue: TrainingItem[], title: string) => void;
  onExploreFrom: (sans: string[]) => void;
}) {
  const state = useStore();
  const addLine = useStore((s) => s.addLine);
  const [nodeId, setNodeId] = useState<string | null>(null);
  const [pendingMove, setPendingMove] = useState<LegalMove | null>(null);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [showReference, setShowReference] = useState(false);

  const fen = fenAt(rep, nodeId);
  const path = useMemo(() => pathTo(rep, nodeId), [rep, nodeId]);
  const pathSans = path.map((n) => n.san);
  const kids = childrenOf(rep, nodeId);
  const ourTurn = fenTurn(fen) === rep.color;
  const opening = useMemo(() => openingNameForPath(referenceIndex(), pathSans), [pathSans]);
  const refEntry = useMemo(() => lookup(referenceIndex(), fen), [fen]);

  const onBoardMove = (move: LegalMove) => {
    const existing = kids.find((k) => k.san === move.san);
    if (existing) {
      setNodeId(existing.id);
      return;
    }
    setPendingMove(move);
  };

  const commitPending = () => {
    if (!pendingMove) return;
    addLine(rep.id, [...pathSans, pendingMove.san], 'manual');
    setPendingMove(null);
    // Descend into the move we just created.
    const fresh = useStore.getState().repertoires[rep.id];
    const child = childrenOf(fresh, nodeId).find((k) => k.san === pendingMove.san);
    if (child) setNodeId(child.id);
    toast(`${pendingMove.san} added`);
  };

  const trainBranch = () => {
    const items = nodeId
      ? branchItems(rep, nodeId)
      : branchItems(rep, childrenOf(rep, null)[0]?.id ?? '');
    if (!items.length) {
      toast('Nothing to train in this branch yet');
      return;
    }
    onStart(items.slice(0, 40), opening?.name ?? rep.name);
  };

  return (
    <>
      <div className="appbar">
        <button className="btn plain sm" onClick={onBack} aria-label="Back">
          <Icons.back size={20} />
        </button>
        <div className="appbar-title">
          <div className="line" style={{ fontWeight: 650, fontSize: 15 }}>
            {opening?.name ?? rep.name}
          </div>
          <div className="sub">
            {opening?.eco ? `${opening.eco} · ` : ''}
            {opening ? rep.name : `${Object.keys(rep.nodes).length} moves`}
          </div>
        </div>
        <button className="btn plain sm" onClick={() => setShowReference(true)} aria-label="Reference">
          <Icons.book size={19} />
        </button>
      </div>

      <div className="screen">
        <Board
          fen={fen}
          orientation={rep.color}
          onMove={onBoardMove}
          movableFor="both"
          lastMove={path.length ? { from: lastFrom(path), to: lastTo(path) } : null}
          showCoordinates={state.settings.showCoordinates}
          theme={state.settings.boardTheme}
        />

        <div className="spacer" />

        <div className="crumbs">
          <button className={`crumb${nodeId === null ? ' active' : ''}`} onClick={() => setNodeId(null)}>
            Start
          </button>
          {path.map((node, i) => (
            <button
              key={node.id}
              className={`crumb${node.id === nodeId ? ' active' : ''}`}
              onClick={() => setNodeId(node.id)}
            >
              {moveNumberFor(i, rep)}{node.san}
            </button>
          ))}
        </div>

        {pendingMove && (
          <div className="card" style={{ borderColor: 'var(--accent-dim)' }}>
            <div className="row between">
              <div>
                <div style={{ fontWeight: 650 }}>Add {pendingMove.san}?</div>
                <div className="tiny faint">
                  {ourTurn ? 'A new move for you' : "A new opponent move to answer"}
                </div>
              </div>
              <div className="row" style={{ gap: 6 }}>
                <button className="btn sm ghost" onClick={() => setPendingMove(null)}>
                  Cancel
                </button>
                <button className="btn sm primary" onClick={commitPending}>
                  Add
                </button>
              </div>
            </div>
          </div>
        )}

        <div className="section-title">{ourTurn ? 'Your moves here' : 'Opponent replies'}</div>

        {kids.length === 0 && (
          <Empty
            icon="↯"
            title={ourTurn ? 'No move prepared here' : 'No replies covered'}
            hint="Play a move on the board to add it, or open the reference."
          />
        )}

        <div className="stack">
          {kids.map((kid) => (
            <TreeRow
              key={kid.id}
              rep={rep}
              node={kid}
              card={state.cards[`${rep.id}#${kid.key}`]}
              ourTurn={ourTurn}
              onOpen={() => setNodeId(kid.id)}
              onMenu={() => setMenuFor(kid.id)}
            />
          ))}
        </div>

        {refEntry && refEntry.moves.length > 0 && (
          <>
            <div className="section-title">
              What the book plays
              <span className="faint" style={{ textTransform: 'none', letterSpacing: 0, fontWeight: 500 }}>
                {' '}· tap to add
              </span>
            </div>
            <ExplorerPanel
              fen={fen}
              path={pathSans}
              inRepertoire={kids.map((k) => k.san)}
              compact
              onPlay={(san) => {
                addLine(rep.id, [...pathSans, san], 'reference');
                const fresh = useStore.getState().repertoires[rep.id];
                const child = childrenOf(fresh, nodeId).find((k) => k.san === san);
                if (child) setNodeId(child.id);
                toast(`${san} added`);
              }}
            />
          </>
        )}

        <div className="spacer" />
        <div className="row" style={{ gap: 8 }}>
          <button className="btn ghost grow" onClick={() => onExploreFrom(pathSans)}>
            Explore theory
          </button>
          <button className="btn grow" onClick={trainBranch}>
            Train branch
          </button>
        </div>
      </div>

      <NodeMenu
        rep={rep}
        nodeId={menuFor}
        onClose={() => setMenuFor(null)}
        onNavigate={(id) => {
          setMenuFor(null);
          setNodeId(id);
        }}
        onTrain={(items, title) => {
          setMenuFor(null);
          onStart(items, title);
        }}
      />

      <Sheet open={showReference} onClose={() => setShowReference(false)} title="Reference">
        <div className="tiny faint" style={{ marginBottom: 8 }}>
          {sansToMoveText(pathSans) || 'Starting position'}
        </div>
        <ExplorerPanel
          fen={fen}
          path={pathSans}
          inRepertoire={kids.map((k) => k.san)}
          onPlay={(san) => {
            addLine(rep.id, [...pathSans, san], 'reference');
            const fresh = useStore.getState().repertoires[rep.id];
            const child = childrenOf(fresh, nodeId).find((k) => k.san === san);
            if (child) setNodeId(child.id);
            setShowReference(false);
            toast(`${san} added to ${rep.name}`);
          }}
        />
        <div className="tiny faint center" style={{ marginTop: 10 }}>
          Tap a move to add it to this repertoire.
        </div>
      </Sheet>
    </>
  );
}

function TreeRow({
  rep,
  node,
  card,
  ourTurn,
  onOpen,
  onMenu,
}: {
  rep: Repertoire;
  node: RepMove;
  card: Card | undefined;
  ourTurn: boolean;
  onOpen: () => void;
  onMenu: () => void;
}) {
  const kids = childrenOf(rep, node.id).length;
  const depth = subtreeIds(rep, node.id).length;
  const stage = !card ? 'none' : card.stage === 'new' ? 'new' : card.stage === 'learning' ? 'learning' : card.interval >= 21 ? 'mature' : 'young';
  return (
    <div className={`tree-row${node.preferred && ourTurn ? ' preferred' : ''}`}>
      <button className="row grow" style={{ gap: 9, textAlign: 'left' }} onClick={onOpen}>
        {ourTurn && <span className={`dot ${stage}`} />}
        <span className="tree-san">{node.san}</span>
        <span className="grow" style={{ minWidth: 0 }}>
          <span className="tree-meta">
            {kids === 0
              ? 'end of line'
              : `${kids} branch${kids === 1 ? '' : 'es'} · ${depth - 1} move${depth - 1 === 1 ? '' : 's'} below`}
            {node.preferred && ourTurn ? ' · main' : ''}
            {card && ourTurn ? ` · ${describeDue(card.due)}` : ''}
          </span>
          {node.note && (
            <span className="tree-meta truncate" style={{ display: 'block', color: 'var(--text-dim)' }}>
              {node.note}
            </span>
          )}
        </span>
      </button>
      <button className="btn plain sm" onClick={onMenu} aria-label="Move options">
        <Icons.gear size={17} />
      </button>
    </div>
  );
}

function NodeMenu({
  rep,
  nodeId,
  onClose,
  onNavigate,
  onTrain,
}: {
  rep: Repertoire;
  nodeId: string | null;
  onClose: () => void;
  onNavigate: (id: string) => void;
  onTrain: (items: TrainingItem[], title: string) => void;
}) {
  const prefer = useStore((s) => s.preferMove);
  const annotate = useStore((s) => s.annotate);
  const remove = useStore((s) => s.removeNode);
  const reorder = useStore((s) => s.reorder);
  const node = nodeId ? rep.nodes[nodeId] : null;
  const [note, setNote] = useState('');
  const [editingNote, setEditingNote] = useState(false);

  if (!node) return <Sheet open={false} onClose={onClose}>{null}</Sheet>;

  const ourMove = fenTurn(node.fenBefore) === rep.color;
  const siblings = childrenOf(rep, node.parentId);

  return (
    <Sheet
      open={!!nodeId}
      onClose={() => {
        setEditingNote(false);
        onClose();
      }}
      title={`${node.san}`}
    >
      <div className="tiny faint" style={{ marginBottom: 10 }}>
        {sansToMoveText(pathTo(rep, node.id).map((n) => n.san))}
      </div>

      {editingNote ? (
        <>
          <textarea
            className="field"
            placeholder="Why this move? What is the plan?"
            value={note}
            onChange={(e) => setNote(e.target.value)}
          />
          <div className="spacer" />
          <div className="row" style={{ gap: 8 }}>
            <button className="btn ghost grow" onClick={() => setEditingNote(false)}>
              Cancel
            </button>
            <button
              className="btn primary grow"
              onClick={() => {
                annotate(rep.id, node.id, note);
                setEditingNote(false);
                toast('Note saved');
              }}
            >
              Save note
            </button>
          </div>
        </>
      ) : (
        <div className="stack">
          {node.note && <div className="card small">{node.note}</div>}
          <button className="btn ghost block" onClick={() => onNavigate(node.id)}>
            Go to this position
          </button>
          {ourMove && siblings.length > 1 && !node.preferred && (
            <button
              className="btn ghost block"
              onClick={() => {
                prefer(rep.id, node.id);
                toast(`${node.san} is now your main move`);
              }}
            >
              <Icons.star size={17} /> Make this the main move
            </button>
          )}
          <button
            className="btn ghost block"
            onClick={() => {
              setNote(node.note ?? '');
              setEditingNote(true);
            }}
          >
            <Icons.note size={17} /> {node.note ? 'Edit note' : 'Add note'}
          </button>
          <button
            className="btn ghost block"
            onClick={() => {
              const items = branchItems(rep, node.id);
              if (!items.length) {
                toast('Nothing trainable below this move');
                return;
              }
              onTrain(items.slice(0, 40), node.san);
            }}
          >
            <Icons.bolt size={17} /> Train this branch ({subtreeIds(rep, node.id).length} moves)
          </button>
          {siblings.length > 1 && (
            <div className="row" style={{ gap: 8 }}>
              <button className="btn ghost grow sm" onClick={() => reorder(rep.id, node.id, -1)}>
                Move up
              </button>
              <button className="btn ghost grow sm" onClick={() => reorder(rep.id, node.id, 1)}>
                Move down
              </button>
            </div>
          )}
          <button
            className="btn danger block"
            onClick={() => {
              const count = subtreeIds(rep, node.id).length;
              remove(rep.id, node.id);
              onClose();
              toast(`Removed ${count} move${count === 1 ? '' : 's'}`);
            }}
          >
            <Icons.trash size={17} /> Delete branch
          </button>
        </div>
      )}
    </Sheet>
  );
}

function lastFrom(path: RepMove[]) {
  const last = path[path.length - 1];
  return last.uci.slice(0, 2) as never;
}
function lastTo(path: RepMove[]) {
  const last = path[path.length - 1];
  return last.uci.slice(2, 4) as never;
}
function moveNumberFor(i: number, rep: Repertoire) {
  const moveNo = Math.floor(i / 2) + 1;
  const white = i % 2 === 0;
  void rep;
  return white ? `${moveNo}.` : '';
}
