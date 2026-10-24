import { useMemo, useState } from 'react';
import { Board } from '../components/Board';
import { ExplorerPanel } from '../components/ExplorerPanel';
import { AppBar, Empty, IconButton, Icons, Section, Sheet, Strip, toast } from '../components/ui';
import { fenTurn, lastMoveOf, sansToMoveText, type Color, type LegalMove } from '../chess/core';
import { linesOf, openingAt, openingsIn, type DerivedOpening } from '../model/openings';
import { childrenOf, fenAt, pathTo, repertoireName, subtreeIds } from '../model/repertoire';
import { lookup, openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { branchItems, type SessionMode, type TrainingItem } from '../model/session';
import { describeDue } from '../model/srs';
import { setEventPlace, type AppEvent } from '../model/events';
import type { Card, MoveSource, RepMove, Repertoire } from '../model/types';
import { bookLength, lineKinds } from '../model/extensions';
import { SaveSheet } from '../components/SaveSheet';
import { sourceLabel } from '../model/moveSource';
import { TidyScreen, useTidyCount } from './TidyScreen';
import type { TidyFind } from '../model/tidy';
import { saveFile } from '../store/saveFile';
import { repertoireList, useStore } from '../store/useStore';

export interface RepertoireScreenProps {
  onStart: (items: TrainingItem[], mode: SessionMode, title: string) => void;
  onImport: () => void;
  /** Play on the board. */
  onBuild: () => void;
  onExploreFrom: (sans: string[]) => void;
  /** A find handed over from the end of a round: Tidy opens on it. */
  tidyFocus: TidyFind | null;
  onConsumedTidyFocus: () => void;
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
export function RepertoireScreen({
  onStart,
  onImport,
  onBuild,
  onExploreFrom,
  tidyFocus,
  onConsumedTidyFocus,
}: RepertoireScreenProps) {
  const state = useStore();
  const reps = repertoireList(state);
  const index = referenceIndex();
  const [scope, setScope] = useState<Scope | null>(null);
  const [adding, setAdding] = useState(false);
  const [openingMenu, setOpeningMenu] = useState<DerivedOpening | null>(null);
  const [sideMenu, setSideMenu] = useState<string | null>(null);
  const [tidying, setTidying] = useState(false);
  // A find from the end of a round opens Tidy, whatever was showing.
  if (tidyFocus && !tidying) setTidying(true);
  // A switch made in Tidy is logged as made there.
  setEventPlace(tidying ? 'tidy' : 'repertoire');

  const sides = useMemo(
    () =>
      (['w', 'b'] as Color[])
        .map((color) => reps.find((rep) => rep.color === color))
        .filter((rep): rep is Repertoire => !!rep)
        .map((rep) => ({ rep, openings: openingsIn(rep, index) })),
    [reps, index],
  );

  if (tidying) {
    return <TidyScreen focus={tidyFocus} onConsumedFocus={onConsumedTidyFocus} onBack={() => setTidying(false)} />;
  }

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
        title="Playbook"
        actions={
          <>
            {reps.length > 0 && (
              <IconButton label="Export as JSON" onClick={() => void exportReps(reps, useStore.getState().events)}>
                <Icons.export size={20} />
              </IconButton>
            )}
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
            hint="Build a line in Growth, or save the opening from a game in Play. Practice never writes into your Playbook."
          />
        )}

        {sides.length > 0 && <TidyRow onOpen={() => setTidying(true)} />}

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
                  label={`Options for the ${rep.color === 'w' ? 'White' : 'Black'} Playbook`}
                  onClick={() => setSideMenu(rep.id)}
                >
                  <Icons.more size={18} />
                </IconButton>
              </div>
            </div>
          </div>
        ))}

        <div className="spacer" />
        <button className="btn soft block" onClick={onBuild}>
          <Icons.play size={18} /> Play on the board
        </button>
        <button className="btn soft block mt-8" onClick={onImport}>
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
        onOpenLine={(repId, tipId, title) => {
          setOpeningMenu(null);
          setScope({ repId, nodeId: tipId, title });
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
 * What can be done to one opening: drill it, open or delete one of its lines,
 * or delete the whole thing.
 *
 * The opening is re-derived from the live tree, so the list keeps up as lines
 * go (and the sheet closes when the last one takes the opening with it).
 * Deleting a whole opening takes the move order that only led there with it,
 * which is usually more moves than the opening's own region holds, so the
 * count says so before you commit. Both deletes ask twice, the same two-tap
 * confirm Settings uses for the other irreversible things; a line also gets an
 * Undo toast, since pruning several in a row is the point of the list.
 */
function OpeningMenu({
  opening: picked,
  onClose,
  onDrill,
  onOpenLine,
}: {
  opening: DerivedOpening | null;
  onClose: () => void;
  onDrill: (items: TrainingItem[], title: string) => void;
  onOpenLine: (repId: string, tipId: string, title: string) => void;
}) {
  const rep = useStore((s) => (picked ? s.repertoires[picked.repertoireId] : null));
  const removeOpening = useStore((s) => s.removeOpening);
  const removeLine = useStore((s) => s.removeLine);
  const [confirming, setConfirming] = useState(false);
  const [confirmingLine, setConfirmingLine] = useState<string | null>(null);

  const index = referenceIndex();
  const opening = useMemo(
    () => (picked && rep ? openingAt(openingsIn(rep, index), picked.rootId) : null),
    [picked, rep, index],
  );
  const lines = useMemo(() => (opening && rep ? linesOf(rep, opening, index) : []), [opening, rep, index]);

  const close = () => {
    setConfirming(false);
    setConfirmingLine(null);
    onClose();
  };

  if (!picked || !rep || !opening) return null;

  return (
    <Sheet open onClose={close} title={opening.name}>
      <div className="movetext" style={{ marginBottom: 10 }}>
        {sansToMoveText(opening.path)}
      </div>

      <div className="list" onClick={() => setConfirmingLine(null)}>
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
        {lines.map((line) => (
          <div className="list-row" key={line.tipId} style={{ paddingRight: 8 }}>
            <button
              className="row grow"
              style={{ minWidth: 0, gap: 12 }}
              onClick={() => onOpenLine(rep.id, line.tipId, opening.name)}
            >
              <span className="grow row" style={{ minWidth: 0, gap: 6, color: 'var(--text-2)' }}>
                <span className="truncate">{line.name}</span>
                {line.split && <span style={{ flexShrink: 0, color: 'var(--text)' }}>{line.split}</span>}
              </span>
              <span className="num" style={{ fontWeight: 700 }}>{line.removes}</span>
            </button>
            {/* A tap anywhere else in the list cancels a pending delete; this one must not. */}
            <span onClick={(e) => e.stopPropagation()}>
              {confirmingLine === line.tipId ? (
                <button
                  className="btn danger sm"
                  onClick={() => {
                    const undo = removeLine(rep.id, line.tipId);
                    setConfirmingLine(null);
                    if (undo) toast(`Deleted ${line.removes} move${line.removes === 1 ? '' : 's'}`, { label: 'Undo', run: undo });
                  }}
                >
                  Delete?
                </button>
              ) : (
                <IconButton label={`Delete ${line.name}${line.split ? ` ${line.split}` : ''}`} plain onClick={() => setConfirmingLine(line.tipId)}>
                  <Icons.trash size={18} />
                </IconButton>
              )}
            </span>
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
  /** The node whose moves the confirm sheet is about to delete. */
  const [cutting, setCutting] = useState<string | null>(null);
  const removeNode = useStore((s) => s.removeNode);
  // The line you came in on stays on the strip while you step back along it,
  // so you can see what comes after and cut it from any point. Going off it
  // makes wherever you went the new line.
  const [lineTip, setLineTip] = useState<string | null>(startNodeId);

  const fen = fenAt(rep, nodeId);
  const path = useMemo(() => pathTo(rep, nodeId), [rep, nodeId]);
  const pathSans = path.map((n) => n.san);
  const line = useMemo(() => {
    const full = lineTip && rep.nodes[lineTip] ? pathTo(rep, lineTip) : [];
    const onIt = nodeId === null || full.some((n) => n.id === nodeId);
    return onIt && full.length >= path.length ? full : path;
  }, [rep, lineTip, nodeId, path]);
  /** The move after where you stand on the line: deleting cuts from it. */
  const next = line[path.length] ?? null;
  const cutCount = cutting ? subtreeIds(rep, cutting).length : 0;

  const goTo = (id: string | null) => {
    setNodeId(id);
    if (id && !line.some((n) => n.id === id)) setLineTip(id);
  };
  const kids = childrenOf(rep, nodeId);
  const ourTurn = fenTurn(fen) === rep.color;
  const opening = useMemo(() => openingNameForPath(referenceIndex(), pathSans), [pathSans]);
  const refEntry = useMemo(() => lookup(referenceIndex(), fen), [fen]);

  /** A line that leaves the book goes through the Save sheet, which checks the move first. */
  const [saving, setSaving] = useState<{ sans: string[]; source: MoveSource } | null>(null);
  const leavesBook = (san: string) => {
    const kinds = lineKinds(referenceIndex(), [...pathSans, san]);
    return bookLength(kinds) < kinds.length;
  };

  const onBoardMove = (move: LegalMove) => {
    const existing = kids.find((k) => k.san === move.san);
    if (existing) {
      goTo(existing.id);
      return;
    }
    if (leavesBook(move.san)) {
      setSaving({ sans: [...pathSans, move.san], source: 'manual' });
      return;
    }
    setPendingMove(move);
  };

  const addFromBook = (san: string) => {
    if (leavesBook(san)) {
      setSaving({ sans: [...pathSans, san], source: 'book' });
      return false;
    }
    addLine(rep.id, [...pathSans, san], 'book');
    descendTo(san);
    toast(`${san} added`);
    return true;
  };

  const descendTo = (san: string) => {
    const fresh = useStore.getState().repertoires[rep.id];
    const child = childrenOf(fresh, nodeId).find((k) => k.san === san);
    if (child) {
      setNodeId(child.id);
      setLineTip(child.id);
    }
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
            <IconButton label="Playbook options" onClick={() => setSideMenu(true)}>
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
          items={line.map((node, i) => ({
            san: node.san,
            label: i % 2 === 0 ? `${i / 2 + 1}.` : undefined,
            current: node.id === nodeId,
            tone: i >= path.length ? ('ghost' as const) : undefined,
            seek: i + 1,
          }))}
          cursor={path.length}
          max={line.length}
          onSeek={(n) => setNodeId(n === 0 ? null : (line[n - 1]?.id ?? null))}
          hint="Play a move"
          trailing={
            next ? (
              <IconButton label="Delete the moves after here" onClick={() => setCutting(next.id)}>
                <Icons.trash size={18} />
              </IconButton>
            ) : undefined
          }
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
                onOpen={() => goTo(kid.id)}
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
                addFromBook(san);
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
          goTo(id);
        }}
        onDelete={(id) => {
          setMenuFor(null);
          setCutting(id);
        }}
        onDrill={(items, drillTitle) => {
          setMenuFor(null);
          onStart(items, 'branch', drillTitle);
        }}
      />

      <Sheet
        open={!!cutting}
        onClose={() => setCutting(null)}
        title={`Delete ${cutCount} move${cutCount === 1 ? '' : 's'}?`}
      >
        {cutting && rep.nodes[cutting] && (
          <div className="movetext" style={{ marginBottom: 12 }}>
            {sansToMoveText(pathTo(rep, cutting).map((n) => n.san))}
          </div>
        )}
        <div className="row gap-8">
          <button className="btn grow" onClick={() => setCutting(null)}>
            Cancel
          </button>
          <button
            className="btn danger grow"
            onClick={() => {
              if (!cutting) return;
              const count = cutCount;
              const undo = removeNode(rep.id, cutting);
              setCutting(null);
              if (undo) toast(`Deleted ${count} move${count === 1 ? '' : 's'}`, { label: 'Undo', run: undo });
            }}
          >
            <Icons.trash size={18} /> Delete
          </button>
        </div>
        <div className="spacer" />
      </Sheet>

      <SaveSheet
        open={!!saving}
        onClose={() => setSaving(null)}
        sans={saving?.sans ?? []}
        color={rep.color}
        source={saving?.source ?? 'manual'}
        onSaved={(_, __, line) => {
          if (line.length === saving?.sans.length) descendTo(line[line.length - 1]);
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
            addFromBook(san);
            setShowReference(false);
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
    sourceLabel(node.source),
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
  onDelete,
}: {
  rep: Repertoire;
  nodeId: string | null;
  onClose: () => void;
  onNavigate: (id: string) => void;
  onDrill: (items: TrainingItem[], title: string) => void;
  /** Ask before deleting the move and everything after it. */
  onDelete: (id: string) => void;
}) {
  const prefer = useStore((s) => s.preferMove);
  const annotate = useStore((s) => s.annotate);
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
            onClick={() => onDelete(node.id)}
          >
            <Icons.trash size={18} /> Delete branch
          </button>
        </>
      )}
    </Sheet>
  );
}

/** Both sides' trees, as they are stored, in one JSON file. */
/** Your repertoire, with the log of how it got that way. */
async function exportReps(reps: Repertoire[], events: AppEvent[]) {
  const date = new Date().toISOString().slice(0, 10);
  const text = JSON.stringify(
    { format: 'chess-trainer-repertoire', version: 1, exportedAt: date, repertoires: reps, events },
    null,
    2,
  );
  const outcome = await saveFile(`repertoire-${date}.json`, text);
  if (outcome === 'unavailable') toast('Saving files is not available here');
}

/** Tidy, at the top of the list: how much it has found in the selection. */
function TidyRow({ onOpen }: { onOpen: () => void }) {
  const count = useTidyCount();
  return (
    <div className="list tidy-row">
      <button className="list-row" onClick={onOpen}>
        <span className="ico">
          <Icons.merge size={20} />
        </span>
        <span className="grow title">Tidy</span>
        {count === null ? null : count === 0 ? (
          <span className="chip good">clear</span>
        ) : (
          <span className="chip accent">{count}</span>
        )}
        <Icons.chevron size={18} />
      </button>
    </div>
  );
}
