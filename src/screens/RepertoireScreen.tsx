import { useMemo, useState } from 'react';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { AppBar, Empty, IconButton, Icons, Section, Sheet, Strip, toast } from '../components/ui';
import { fenTurn, lastMoveOf, sansToMoveText, type Color, type LegalMove } from '../chess/core';
import { openingsIn, type DerivedOpening } from '../model/openings';
import { childrenOf, fenAt, pathTo, repertoireName, subtreeIds } from '../model/repertoire';
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

/** Where the browser is pointed: one opening, or a whole side's tree. */
interface Scope {
  repId: string;
  /** The node to land on, or null for the start position. */
  nodeId: string | null;
  title: string;
}

/**
 * Your repertoire: the whole collection, listed as the openings in it.
 *
 * Two trees are stored, one per side, and an opening is a named region of one of
 * them — see `openingsIn`. So this screen lists what you have prepared the way
 * you would describe it out loud ("a King's Indian, a Sicilian") rather than
 * listing the two containers those openings happen to live in.
 */
export function RepertoireScreen({ onStart, onImport, onExploreFrom }: RepertoireScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const index = referenceIndex();
  const [scope, setScope] = useState<Scope | null>(null);
  const [adding, setAdding] = useState(false);
  const [openingMenu, setOpeningMenu] = useState<DerivedOpening | null>(null);
  const [sideMenu, setSideMenu] = useState<string | null>(null);

  const sides = useMemo(
    () =>
      (['w', 'b'] as Color[])
        .map((color) => reps.find((rep) => rep.color === color))
        .filter((rep): rep is Repertoire => !!rep)
        .map((rep) => ({ rep, openings: openingsIn(rep, index) })),
    [reps, index],
  );

  const scoped = scope ? state.repertoires[scope.repId] : null;
  if (scope && scoped) {
    return (
      <RepertoireBrowser
        rep={scoped}
        startNodeId={scope.nodeId}
        title={scope.title}
        onBack={() => setScope(null)}
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
            <IconButton label="Import games" onClick={onImport}>
              <Icons.download size={20} />
            </IconButton>
            <IconButton label="Add an opening" onClick={() => setAdding(true)}>
              <Icons.plus size={20} />
            </IconButton>
          </>
        }
      />

      <div className="screen">
        {sides.length === 0 && (
          <Empty
            title="No openings yet"
            hint="Build a line in Growth, keep one at the end of an Autopilot round, or save the opening from a game in Play. All three write into your repertoire, and nothing else does."
          />
        )}

        {sides.map(({ rep, openings }) => (
          <div key={rep.id}>
            <Section
              title={rep.color === 'w' ? 'As White' : 'As Black'}
              aside={`${openings.length} ${openings.length === 1 ? 'opening' : 'openings'}`}
            />
            <div className="list">
              {openings.map((opening) => (
                <OpeningRow
                  key={opening.id}
                  opening={opening}
                  onOpen={() =>
                    setScope({ repId: rep.id, nodeId: opening.rootId, title: opening.name })
                  }
                  onMenu={() => setOpeningMenu(opening)}
                />
              ))}
              <div className="list-row">
                <button
                  className="grow row"
                  onClick={() =>
                    setScope({ repId: rep.id, nodeId: null, title: repertoireName(rep.color) })
                  }
                >
                  <span className="grow">
                    <div className="title muted">Whole tree, from move one</div>
                    <div className="meta">{Object.keys(rep.nodes).length} moves</div>
                  </span>
                  <Icons.chevron size={18} />
                </button>
                <IconButton
                  label={`Options for the ${rep.color === 'w' ? 'White' : 'Black'} repertoire`}
                  onClick={() => setSideMenu(rep.id)}
                >
                  <Icons.more size={18} />
                </IconButton>
              </div>
            </div>
          </div>
        ))}

        <div className="spacer" />
        <button className="btn soft block" onClick={onImport}>
          <Icons.download size={18} /> Import games
        </button>
      </div>

      <NewOpeningSheet
        open={adding}
        onClose={() => setAdding(false)}
        onReady={(repId, color) =>
          setScope({ repId, nodeId: null, title: repertoireName(color) })
        }
      />
      <OpeningMenu
        opening={openingMenu}
        onClose={() => setOpeningMenu(null)}
        onDrill={(items, title) => {
          setOpeningMenu(null);
          onStart(items, 'branch', title);
        }}
      />
      <SideMenu repId={sideMenu} onClose={() => setSideMenu(null)} />
    </>
  );
}

function OpeningRow({
  opening,
  onOpen,
  onMenu,
}: {
  opening: DerivedOpening;
  onOpen: () => void;
  onMenu: () => void;
}) {
  const meta = [
    opening.eco,
    `${opening.lines} ${opening.lines === 1 ? 'line' : 'lines'}`,
    `${Math.ceil(opening.depth / 2)} moves deep`,
    opening.variations.length
      ? `${opening.variations.length} ${opening.variations.length === 1 ? 'variation' : 'variations'}`
      : null,
  ]
    .filter(Boolean)
    .join(' · ');
  return (
    <div className="list-row" style={{ minHeight: 64 }}>
      <button className="grow row" onClick={onOpen}>
        <span className="grow" style={{ minWidth: 0 }}>
          <div className="title truncate">{opening.name}</div>
          <div className="meta truncate">{meta}</div>
        </span>
        <Icons.chevron size={18} />
      </button>
      <IconButton label={`Options for ${opening.name}`} onClick={onMenu}>
        <Icons.more size={18} />
      </IconButton>
    </div>
  );
}

/**
 * What can be done to one opening.
 *
 * Deleting takes the move order that only led there with it, which is usually
 * more moves than the opening's own region holds, so the count says so before
 * you commit. It asks twice — the same two-tap confirm Settings uses for the
 * other irreversible things.
 */
function OpeningMenu({
  opening,
  onClose,
  onDrill,
}: {
  opening: DerivedOpening | null;
  onClose: () => void;
  onDrill: (items: TrainingItem[], title: string) => void;
}) {
  const rep = useStore((s) => (opening ? s.repertoires[opening.repertoireId] : null));
  const removeOpening = useStore((s) => s.removeOpening);
  const [confirming, setConfirming] = useState(false);

  const close = () => {
    setConfirming(false);
    onClose();
  };

  if (!opening || !rep) return null;

  return (
    <Sheet open onClose={close} title={opening.name}>
      <div className="movetext" style={{ marginBottom: 10 }}>
        {sansToMoveText(opening.path)}
      </div>

      <div className="list">
        <button
          className="list-row"
          onClick={() => {
            const items = branchItems(rep, opening.rootId);
            if (!items.length) {
              toast('Nothing to drill');
              return;
            }
            onDrill(items.slice(0, 40), opening.name);
          }}
        >
          <span className="grow">
            <div className="title">Drill this opening</div>
            <div className="meta">{opening.moves} moves below here</div>
          </span>
          <Icons.chevron size={18} />
        </button>
        {opening.variations.map((variation) => (
          <div className="list-row kv" key={variation.id}>
            <span className="k grow truncate">{variation.name}</span>
            <span className="v num">{variation.moves}</span>
          </div>
        ))}
      </div>

      <div className="spacer" />
      <button
        className="btn danger block"
        onClick={() => {
          if (!confirming) {
            setConfirming(true);
            return;
          }
          removeOpening(opening.repertoireId, opening.rootId);
          close();
          toast(`${opening.name} deleted`);
        }}
      >
        <Icons.trash size={18} />
        {confirming ? 'Tap again to delete' : 'Delete opening'}
      </button>
      <div className="note center">
        {opening.removes} {opening.removes === 1 ? 'move goes' : 'moves go'} with it — the opening
        and the move order that only leads there. This cannot be undone.
      </div>
      <div className="spacer" />
    </Sheet>
  );
}

/** What can be done to a whole side's tree: every opening you play as it. */
function SideMenu({
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

  const close = () => {
    setConfirming(false);
    onClose();
  };

  if (!rep) return null;
  const moves = Object.keys(rep.nodes).length;
  const trained = Object.values(cards).filter((c) => c.repertoireId === rep.id).length;
  const side = rep.color === 'w' ? 'White' : 'Black';

  return (
    <Sheet open onClose={close} title={repertoireName(rep.color)}>
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
          toast(`Everything you play as ${side} deleted`);
        }}
      >
        <Icons.trash size={18} />
        {confirming ? 'Tap again to delete' : `Delete everything as ${side}`}
      </button>
      <div className="note center">
        {trained > 0
          ? `Every opening you play as ${side} goes, along with the schedule for ${trained} positions. This cannot be undone.`
          : `Every opening you play as ${side} goes — all ${moves} moves. This cannot be undone.`}
      </div>
      <div className="spacer" />
    </Sheet>
  );
}

/**
 * Start an opening by hand.
 *
 * Openings are derived from the moves, so there is no name to type: you pick a
 * side and play the moves in. The side is the only thing the app cannot work
 * out for itself.
 */
function NewOpeningSheet({
  open,
  onClose,
  onReady,
}: {
  open: boolean;
  onClose: () => void;
  onReady: (repId: string, color: Color) => void;
}) {
  const ensureRepertoire = useStore((s) => s.ensureRepertoire);
  const [color, setColor] = useState<Color>('w');
  return (
    <Sheet open={open} onClose={onClose} title="Add an opening">
      <div className="segmented">
        <button className={color === 'w' ? 'active' : ''} onClick={() => setColor('w')}>
          As White
        </button>
        <button className={color === 'b' ? 'active' : ''} onClick={() => setColor('b')}>
          As Black
        </button>
      </div>
      <div className="note">
        Play the moves in and the book names the opening for you. It joins whatever you already have
        for that side.
      </div>
      <div className="spacer" />
      <button
        className="btn primary block"
        onClick={() => {
          onReady(ensureRepertoire(color), color);
          onClose();
        }}
      >
        Start playing moves
      </button>
    </Sheet>
  );
}

/* ── browser ───────────────────────────────────────────────────────────── */

function RepertoireBrowser({
  rep,
  startNodeId,
  title,
  onBack,
  onStart,
  onExploreFrom,
}: {
  rep: Repertoire;
  startNodeId: string | null;
  title: string;
  onBack: () => void;
  onStart: (items: TrainingItem[], mode: SessionMode, title: string) => void;
  onExploreFrom: (sans: string[]) => void;
}) {
  const state = useStore();
  const addLine = useStore((s) => s.addLine);
  const [nodeId, setNodeId] = useState<string | null>(startNodeId);
  const [pendingMove, setPendingMove] = useState<LegalMove | null>(null);
  const [menuFor, setMenuFor] = useState<string | null>(null);
  const [showReference, setShowReference] = useState(false);
  const [sideMenu, setSideMenu] = useState(false);

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
    onStart(items, 'branch', opening?.name ?? title);
  };

  return (
    <>
      <AppBar
        title={opening?.name ?? title}
        subtitle={`${opening?.eco ? `${opening.eco} · ` : ''}${rep.color === 'w' ? 'as White' : 'as Black'}`}
        onBack={onBack}
        actions={
          <>
            <IconButton label="The book" onClick={() => setShowReference(true)}>
              <Icons.book size={20} />
            </IconButton>
            <IconButton label="Repertoire options" onClick={() => setSideMenu(true)}>
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
            <Section title="The book" aside="Tap to add" />
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

      <SideMenu
        repId={sideMenu ? rep.id : null}
        onClose={() => setSideMenu(false)}
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
        onDrill={(items, drillTitle) => {
          setMenuFor(null);
          onStart(items, 'branch', drillTitle);
        }}
      />

      <Sheet open={showReference} onClose={() => setShowReference(false)} title="The book">
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
