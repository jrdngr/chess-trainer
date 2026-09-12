import { useMemo, useState } from 'react';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { AppBar, Empty, IconButton, Icons, Section, Sheet, Strip, toast } from '../components/ui';
import { fenTurn, lastMoveOf, sansToMoveText, type LegalMove } from '../chess/core';
import { childrenOf, displayName, fenAt, pathTo, subtreeIds } from '../model/repertoire';
import { lookup, openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { branchItems, type SessionMode, type TrainingItem } from '../model/session';
import { describeDue } from '../model/srs';
import type { Card, RepMove, Repertoire } from '../model/types';
import { repertoireList, useStore } from '../store/useStore';

export interface RepertoireScreenProps {
  onStart: (items: TrainingItem[], mode: SessionMode, title: string) => void;
  onImport: () => void;
  onExploreFrom: (sans: string[]) => void;
}

export function RepertoireScreen({ onStart, onImport, onExploreFrom }: RepertoireScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const [openId, setOpenId] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);
  const [menuFor, setMenuFor] = useState<string | null>(null);

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
      <AppBar
        large
        title="Repertoire"
        actions={
          <>
            <IconButton label="Import" onClick={onImport}>
              <Icons.download size={20} />
            </IconButton>
            <IconButton label="New repertoire" onClick={() => setCreating(true)}>
              <Icons.plus size={20} />
            </IconButton>
          </>
        }
      />

      <div className="screen">
        {reps.length === 0 && <Empty title="No repertoires" hint="Create one or import your games" />}
        {reps.length > 0 && (
          <div className="list">
            {reps.map((r) => (
              <RepertoireRow
                key={r.id}
                rep={r}
                cards={state.cards}
                onOpen={() => setOpenId(r.id)}
                onMenu={() => setMenuFor(r.id)}
              />
            ))}
          </div>
        )}

        <div className="spacer" />
        <button className="btn soft block" onClick={onImport}>
          <Icons.download size={18} /> Import games
        </button>
      </div>

      <NewRepertoireSheet open={creating} onClose={() => setCreating(false)} />
      <RepertoireMenu repId={menuFor} onClose={() => setMenuFor(null)} />
    </>
  );
}

function RepertoireRow({
  rep,
  cards,
  onOpen,
  onMenu,
}: {
  rep: Repertoire;
  cards: Record<string, Card>;
  onOpen: () => void;
  onMenu: () => void;
}) {
  const nodes = Object.keys(rep.nodes).length;
  const trained = Object.values(cards).filter((c) => c.repertoireId === rep.id).length;
  const firstMoves = childrenOf(rep, null)
    .map((m) => m.san)
    .slice(0, 3);
  return (
    <div className="list-row" style={{ minHeight: 64 }}>
      <button className="grow row" onClick={onOpen}>
        <span className={`side ${rep.color}`} />
        <span className="grow">
          <div className="title truncate">{displayName(rep.name)}</div>
          <div className="meta">
            {nodes} moves{trained ? ` · ${trained} trained` : ''}
            {firstMoves.length > 0 ? ` · ${firstMoves.join(' ')}` : ''}
          </div>
        </span>
        <Icons.chevron size={18} />
      </button>
      <IconButton label={`Options for ${displayName(rep.name)}`} onClick={onMenu}>
        <Icons.more size={18} />
      </IconButton>
    </div>
  );
}

/**
 * What can be done to a whole repertoire.
 *
 * Deleting takes the schedule and the logged mistakes with it, which is a lot
 * to lose by accident, so it asks twice — the same two-tap confirm Settings
 * uses for the other irreversible things.
 */
function RepertoireMenu({
  repId,
  onClose,
  onDeleted,
}: {
  repId: string | null;
  onClose: () => void;
  onDeleted?: () => void;
}) {
  const rep = useStore((s) => (repId ? s.repertoires[repId] : null));
  const cards = useStore((s) => s.cards);
  const removeRepertoire = useStore((s) => s.removeRepertoire);
  const [confirming, setConfirming] = useState(false);

  // A fresh sheet always opens un-armed.
  const close = () => {
    setConfirming(false);
    onClose();
  };

  if (!rep) return null;
  const moves = Object.keys(rep.nodes).length;
  const trained = Object.values(cards).filter((c) => c.repertoireId === rep.id).length;
  const name = displayName(rep.name);

  return (
    <Sheet open onClose={close} title={name}>
      <div className="list">
        <div className="list-row kv">
          <span className="k">Moves</span>
          <span className="v num">{moves}</span>
        </div>
        <div className="list-row kv">
          <span className="k">Scheduled positions</span>
          <span className="v num">{trained}</span>
        </div>
      </div>

      <div className="spacer" />
      <button
        className="btn danger block"
        onClick={() => {
          if (!confirming) {
            setConfirming(true);
            return;
          }
          removeRepertoire(rep.id);
          close();
          onDeleted?.();
          toast(`${name} deleted`);
        }}
      >
        <Icons.trash size={18} />
        {confirming ? 'Tap again to delete' : 'Delete repertoire'}
      </button>
      <div className="note center">
        {trained > 0
          ? `Its ${moves} moves and the schedule for ${trained} of them go too. This cannot be undone.`
          : `All ${moves} moves go with it. This cannot be undone.`}
      </div>
      <div className="spacer" />
    </Sheet>
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
        placeholder="Name"
        value={name}
        onChange={(e) => setName(e.target.value)}
      />
      <div className="spacer sm" />
      <div className="segmented">
        <button className={color === 'w' ? 'active' : ''} onClick={() => setColor('w')}>
          White
        </button>
        <button className={color === 'b' ? 'active' : ''} onClick={() => setColor('b')}>
          Black
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
  onStart: (items: TrainingItem[], mode: SessionMode, title: string) => void;
  onExploreFrom: (sans: string[]) => void;
}) {
  const state = useStore();
  const addLine = useStore((s) => s.addLine);
  const [nodeId, setNodeId] = useState<string | null>(null);
  const [pendingMove, setPendingMove] = useState<LegalMove | null>(null);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [showReference, setShowReference] = useState(false);
  const [repMenu, setRepMenu] = useState(false);

  const fen = fenAt(rep, nodeId);
  const path = useMemo(() => pathTo(rep, nodeId), [rep, nodeId]);
  const pathSans = path.map((n) => n.san);
  const kids = childrenOf(rep, nodeId);
  const ourTurn = fenTurn(fen) === rep.color;
  const opening = useMemo(() => openingNameForPath(referenceIndex(), pathSans), [pathSans]);
  const refEntry = useMemo(() => lookup(referenceIndex(), fen), [fen]);
  const name = displayName(rep.name);

  const onBoardMove = (move: LegalMove) => {
    const existing = kids.find((k) => k.san === move.san);
    if (existing) {
      setNodeId(existing.id);
      return;
    }
    setPendingMove(move);
  };

  const descendTo = (san: string) => {
    const fresh = useStore.getState().repertoires[rep.id];
    const child = childrenOf(fresh, nodeId).find((k) => k.san === san);
    if (child) setNodeId(child.id);
  };

  const commitPending = () => {
    if (!pendingMove) return;
    addLine(rep.id, [...pathSans, pendingMove.san], 'manual');
    setPendingMove(null);
    descendTo(pendingMove.san);
    toast(`${pendingMove.san} added`);
  };

  const drillBranch = () => {
    const items = nodeId
      ? branchItems(rep, nodeId)
      : branchItems(rep, childrenOf(rep, null)[0]?.id ?? '');
    if (!items.length) {
      toast('Nothing to drill');
      return;
    }
    onStart(items, 'branch', opening?.name ?? name);
  };

  return (
    <>
      <AppBar
        title={opening?.name ?? name}
        subtitle={`${opening?.eco ? `${opening.eco} · ` : ''}${opening ? name : `${Object.keys(rep.nodes).length} moves`}`}
        onBack={onBack}
        actions={
          <>
            <IconButton label="Reference" onClick={() => setShowReference(true)}>
              <Icons.book size={20} />
            </IconButton>
            <IconButton label="Repertoire options" onClick={() => setRepMenu(true)}>
              <Icons.more size={20} />
            </IconButton>
          </>
        }
      />

      <div className="screen">
        <Board
          fen={fen}
          orientation={rep.color}
          onMove={onBoardMove}
          movableFor="both"
          lastMove={lastMoveOf(pathSans)}
          showCoordinates={state.settings.showCoordinates}
          theme={state.settings.boardTheme}
        />

        <div className="spacer sm" />

        <Strip
          items={path.map((node, i) => ({
            san: node.san,
            label: i % 2 === 0 ? `${i / 2 + 1}.` : undefined,
            current: node.id === nodeId,
            seek: i + 1,
          }))}
          cursor={path.length}
          max={path.length}
          onSeek={(n) => setNodeId(n === 0 ? null : (path[n - 1]?.id ?? null))}
          hint="Play a move"
        />

        {pendingMove && (
          <div className="card accent row between mt-8">
            <div className="grow">
              <div style={{ fontWeight: 700 }}>Add {pendingMove.san}?</div>
              <div className="tiny muted">{ourTurn ? 'Your move' : 'Opponent reply'}</div>
            </div>
            <div className="row gap-6">
              <button className="btn sm" onClick={() => setPendingMove(null)}>
                Cancel
              </button>
              <button className="btn sm primary" onClick={commitPending}>
                Add
              </button>
            </div>
          </div>
        )}

        <Section title={ourTurn ? 'Your move' : 'Replies'} aside={kids.length || undefined} />

        {kids.length === 0 && (
          <Empty title={ourTurn ? 'No move here' : 'No replies'} hint="Play a move to add it" />
        )}

        {kids.length > 0 && (
          <div className="list">
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
        )}

        {refEntry && refEntry.moves.length > 0 && (
          <>
            <Section title="Book" aside="Tap to add" />
            <ExplorerPanel
              fen={fen}
              path={pathSans}
              inRepertoire={kids.map((k) => k.san)}
              compact
              onPlay={(san) => {
                addLine(rep.id, [...pathSans, san], 'reference');
                descendTo(san);
                toast(`${san} added`);
              }}
            />
          </>
        )}

        <div className="spacer" />
        <div className="row gap-8">
          <button className="btn soft grow" onClick={() => onExploreFrom(pathSans)}>
            Explore
          </button>
          <button className="btn primary grow" onClick={drillBranch}>
            <Icons.home size={18} filled /> Drill
          </button>
        </div>
      </div>

      <RepertoireMenu
        repId={repMenu ? rep.id : null}
        onClose={() => setRepMenu(false)}
        onDeleted={onBack}
      />

      <NodeMenu
        rep={rep}
        nodeId={menuFor}
        onClose={() => setMenuFor(null)}
        onNavigate={(id) => {
          setMenuFor(null);
          setNodeId(id);
        }}
        onDrill={(items, title) => {
          setMenuFor(null);
          onStart(items, 'branch', title);
        }}
      />

      <Sheet open={showReference} onClose={() => setShowReference(false)} title="Reference">
        <div className="movetext" style={{ marginBottom: 10 }}>
          {sansToMoveText(pathSans) || 'Start'}
        </div>
        <ExplorerPanel
          fen={fen}
          path={pathSans}
          inRepertoire={kids.map((k) => k.san)}
          onPlay={(san) => {
            addLine(rep.id, [...pathSans, san], 'reference');
            descendTo(san);
            setShowReference(false);
            toast(`${san} added`);
          }}
        />
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
  const stage = !card ? 'none' : card.stage === 'new' ? 'new' : card.stage === 'learning' ? 'learning' : card.interval >= 21 ? 'mature' : 'young';
  const meta = [
    kids === 0 ? 'end of line' : `${kids} ${kids === 1 ? 'branch' : 'branches'}`,
    card && ourTurn ? describeDue(card.due) : null,
  ]
    .filter(Boolean)
    .join(' · ');
  return (
    <div className="list-row" style={{ paddingRight: 8 }}>
      <button className="row grow" style={{ gap: 12, minHeight: 34 }} onClick={onOpen}>
        {ourTurn && <span className={`dot ${stage}`} />}
        <span className="tree-san">{node.san}</span>
        <span className="grow" style={{ minWidth: 0 }}>
          <span className="meta" style={{ display: 'block', marginTop: 0 }}>{meta}</span>
          {node.note && (
            <span className="meta truncate" style={{ display: 'block', color: 'var(--text-2)' }}>
              {node.note}
            </span>
          )}
        </span>
        {node.preferred && ourTurn && <span className="chip accent">main</span>}
      </button>
      <IconButton label="Options" onClick={onMenu} plain>
        <Icons.more size={20} />
      </IconButton>
    </div>
  );
}

function NodeMenu({
  rep,
  nodeId,
  onClose,
  onNavigate,
  onDrill,
}: {
  rep: Repertoire;
  nodeId: string | null;
  onClose: () => void;
  onNavigate: (id: string) => void;
  onDrill: (items: TrainingItem[], title: string) => void;
}) {
  const prefer = useStore((s) => s.preferMove);
  const annotate = useStore((s) => s.annotate);
  const remove = useStore((s) => s.removeNode);
  const reorder = useStore((s) => s.reorder);
  const node = nodeId ? rep.nodes[nodeId] : null;
  const [note, setNote] = useState('');
  const [editingNote, setEditingNote] = useState(false);

  if (!node) return null;

  const ourMove = fenTurn(node.fenBefore) === rep.color;
  const siblings = childrenOf(rep, node.parentId);
  const below = subtreeIds(rep, node.id).length;

  return (
    <Sheet
      open={!!nodeId}
      onClose={() => {
        setEditingNote(false);
        onClose();
      }}
      title={node.san}
    >
      <div className="movetext" style={{ marginBottom: 12 }}>
        {sansToMoveText(pathTo(rep, node.id).map((n) => n.san))}
      </div>

      {editingNote ? (
        <>
          <textarea
            className="field"
            style={{ fontFamily: 'var(--font)', fontSize: 15 }}
            placeholder="Why this move?"
            value={note}
            onChange={(e) => setNote(e.target.value)}
            autoFocus
          />
          <div className="spacer sm" />
          <div className="row gap-8">
            <button className="btn grow" onClick={() => setEditingNote(false)}>
              Cancel
            </button>
            <button
              className="btn primary grow"
              onClick={() => {
                annotate(rep.id, node.id, note);
                setEditingNote(false);
              }}
            >
              Save
            </button>
          </div>
        </>
      ) : (
        <>
          {node.note && <div className="card small muted" style={{ marginBottom: 10 }}>{node.note}</div>}
          <div className="list">
            <button className="list-row" onClick={() => onNavigate(node.id)}>
              <span className="grow title">Go here</span>
              <Icons.chevron size={18} />
            </button>
            <button
              className="list-row"
              onClick={() => {
                const items = branchItems(rep, node.id);
                if (!items.length) {
                  toast('Nothing to drill');
                  return;
                }
                onDrill(items.slice(0, 40), node.san);
              }}
            >
              <span className="grow">
                <div className="title">Drill branch</div>
                <div className="meta">{below} moves</div>
              </span>
              <Icons.chevron size={18} />
            </button>
            {ourMove && siblings.length > 1 && !node.preferred && (
              <button
                className="list-row"
                onClick={() => {
                  prefer(rep.id, node.id);
                  toast(`${node.san} is now main`);
                }}
              >
                <span className="grow title">Set as main</span>
                <Icons.star size={18} />
              </button>
            )}
            <button
              className="list-row"
              onClick={() => {
                setNote(node.note ?? '');
                setEditingNote(true);
              }}
            >
              <span className="grow title">{node.note ? 'Edit note' : 'Add note'}</span>
              <Icons.note size={18} />
            </button>
            {siblings.length > 1 && (
              <div className="list-row">
                <span className="grow title">Reorder</span>
                <IconButton label="Move up" onClick={() => reorder(rep.id, node.id, -1)}>
                  <Icons.up size={16} />
                </IconButton>
                <IconButton label="Move down" onClick={() => reorder(rep.id, node.id, 1)}>
                  <Icons.down size={16} />
                </IconButton>
              </div>
            )}
          </div>
          <div className="spacer sm" />
          <button
            className="btn danger block"
            onClick={() => {
              remove(rep.id, node.id);
              onClose();
              toast(`Removed ${below} move${below === 1 ? '' : 's'}`);
            }}
          >
            <Icons.trash size={18} /> Delete branch
          </button>
        </>
      )}
    </Sheet>
  );
}
