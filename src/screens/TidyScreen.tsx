import { useEffect, useMemo, useRef, useState } from 'react';
import { applySan, positionKey } from '../chess/core';
import { Board, type Arrow } from '../components/Board';
import { nudgeColor } from '../components/Nudges';
import { ColorSquare, MiniBoard, SelectionBar } from '../components/Selection';
import { AppBar, Empty, haptic, toast } from '../components/ui';
import { useSoundness } from '../engine/soundness';
import { againstReason, goneWith, NOT_IN_BOOK } from '../model/nudge';
import { openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import { pathTo } from '../model/repertoire';
import { regionOf, repertoiresIn } from '../model/selection';
import { findAt, moveLabel, sortFinds, tidyPositions, type TidyFind, type TidyOptions } from '../model/tidy';
import { repertoireList, useStore } from '../store/useStore';

/** Positions looked at between frames, so a big repertoire never freezes the tab. */
const SLICE = 40;
/** Off-book finds put to the engine at once, from the top of the list. */
const CHECK_AHEAD = 12;

/**
 * Tidy: places where your lines could converge.
 *
 * Every move you have chosen, inside the selection, is weighed against the
 * moves you could play instead, by the same rules that colour Growth's arrows.
 * Where another move is closer to the rest of your lines — it transposes into
 * them, heads toward them, or is what you play there everywhere else — that is
 * a find. Switching makes it yours and drops your move with everything under
 * it, so the biggest savings come first.
 *
 * `focus` is a find handed over from the end of a round, shown first and open.
 */
export function TidyScreen({ focus, onConsumedFocus }: { focus?: TidyFind | null; onConsumedFocus?: () => void }) {
  const repertoires = useStore((s) => s.repertoires);
  const repertoireOrder = useStore((s) => s.repertoireOrder);
  const selection = useStore((s) => s.settings.selection);
  const growth = useStore((s) => s.settings.growth);
  const tidySwitch = useStore((s) => s.tidySwitch);
  const index = referenceIndex();
  const tree = openingTree(index);
  const region = regionOf(tree, selection);
  const reps = useMemo(
    () => repertoiresIn(repertoireList({ repertoires, repertoireOrder }), selection.color),
    [repertoires, repertoireOrder, selection.color],
  );
  const opts = useMemo<TidyOptions>(
    () => ({ prefs: { priority: growth.nudgePriority, pawns: growth.nudgePawns }, minShare: growth.minShare }),
    [growth.nudgePriority, growth.nudgePawns, growth.minShare],
  );

  const [pinned, setPinned] = useState<TidyFind | null>(focus ?? null);
  const [open, setOpen] = useState<string | null>(focus?.id ?? null);
  if (focus && focus.id !== pinned?.id) {
    setPinned(focus);
    setOpen(focus.id);
  }
  useEffect(() => {
    if (focus) onConsumedFocus?.();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focus]);

  // The scan runs a slice at a time. A rescan after a switch keeps showing
  // the list it had until the new one is whole, so nothing jumps.
  const [finds, setFinds] = useState<TidyFind[] | null>(null);
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);
  const first = useRef(true);
  useEffect(() => {
    const todo = tidyPositions(reps, tree, region);
    const found: TidyFind[] = [];
    let at = 0;
    let cancelled = false;
    const progressive = first.current;
    first.current = false;
    setProgress({ done: 0, total: todo.length });
    const step = () => {
      if (cancelled) return;
      for (const { rep, node } of todo.slice(at, at + SLICE)) {
        const find = findAt(rep, index, node, opts);
        if (find) found.push(find);
      }
      at += SLICE;
      if (at < todo.length) {
        if (progressive) setFinds(sortFinds(found));
        setProgress({ done: at, total: todo.length });
        timer = window.setTimeout(step, 0);
      } else {
        setFinds(sortFinds(found));
        setProgress(null);
      }
    };
    let timer = window.setTimeout(step, 0);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
    };
  }, [reps, tree, region, index, opts]);

  // A pinned find the switch has already dealt with, or that the tree no
  // longer holds, stops being pinned.
  const pinnedLive = pinned && repertoires[pinned.repertoireId]?.nodes[pinned.nodeId] ? pinned : null;
  const list = useMemo(() => {
    const rest = (finds ?? []).filter((find) => find.id !== pinnedLive?.id);
    return pinnedLive ? [pinnedLive, ...rest] : rest;
  }, [finds, pinnedLive]);

  // Moves the book does not have wait on the engine; one it fails drops out.
  const checks = useMemo(
    () =>
      list
        .filter((find) => find.offBook)
        .slice(0, CHECK_AHEAD)
        .map((find) => ({ fen: find.fen, san: find.suggestion })),
    [list],
  );
  const sound = useSoundness(checks);
  const shown = list.filter((find) => !find.offBook || sound(find.fen, find.suggestion) !== false);

  const onSwitch = (find: TidyFind) => {
    const undo = tidySwitch(find.repertoireId, find.nodeId, find.suggestion);
    if (!undo) {
      toast('That move cannot be played there');
      return;
    }
    haptic(12);
    if (pinned?.id === find.id) setPinned(null);
    toast(`Switched to ${moveLabel(find.path.length, find.suggestion)}`, { label: 'Undo', run: undo });
  };

  const where = region.depth === 0 ? 'your repertoire' : `the ${region.name}`;

  return (
    <>
      <AppBar large title="Tidy" />
      <div className="screen">
        <SelectionBar />
        <p className="muted small tidy-intro">
          Places where another move is closer to the rest of your lines. Switching keeps that move and drops yours,
          with everything under it.
        </p>
        {reps.length === 0 ? (
          <Empty title="No lines yet" hint="Build some in Growth first. Tidy looks for lines that could converge." />
        ) : shown.length === 0 && !progress ? (
          <Empty title={`Nothing to tidy in ${where}`} hint="Your moves here are as close to your other lines as any." />
        ) : null}
        {progress && (
          <div className="faint tiny center tidy-progress">
            Looking through {progress.total} positions{progress.done ? ` · ${Math.round((progress.done / progress.total) * 100)}%` : ''}
          </div>
        )}
        {shown.map((find) => (
          <TidyCard
            key={find.id}
            find={find}
            pinned={find.id === pinnedLive?.id}
            open={open === find.id}
            checking={find.offBook && sound(find.fen, find.suggestion) === undefined}
            opts={opts}
            onToggle={() => setOpen((cur) => (cur === find.id ? null : find.id))}
            onSwitch={() => onSwitch(find)}
          />
        ))}
      </div>
    </>
  );
}

function TidyCard({
  find,
  pinned,
  open,
  checking,
  opts,
  onToggle,
  onSwitch,
}: {
  find: TidyFind;
  pinned: boolean;
  open: boolean;
  checking: boolean;
  opts: TidyOptions;
  onToggle: () => void;
  onSwitch: () => void;
}) {
  const repertoires = useStore((s) => s.repertoires);
  const rep = repertoires[find.repertoireId];
  const index = referenceIndex();
  const color = nudgeColor(find.tone);

  /** Why your move works against your lines: the dearest signal, worked out only for an open card. */
  const against = useMemo(() => {
    if (!open || !rep?.nodes[find.nodeId]) return null;
    const line = pathTo(rep, rep.nodes[find.nodeId].parentId);
    return againstReason(rep, index, find.path, find.fen, find.mine, opts.prefs, opts.minShare, {
      gone: goneWith(rep, index, find.nodeId),
      pathKeys: [positionKey(rep.rootFen), ...line.map((move) => positionKey(move.fenAfter))],
    });
  }, [open, rep, index, find, opts]);

  const arrows = useMemo<Arrow[]>(() => {
    const out: Arrow[] = [];
    const mine = applySan(find.fen, find.mine);
    const theirs = applySan(find.fen, find.suggestion);
    if (mine) out.push({ from: mine.from, to: mine.to, color: against ? nudgeColor('away') : undefined });
    if (theirs) out.push({ from: theirs.from, to: theirs.to, color });
    return out;
  }, [find, color, against]);

  const reason = find.offBook ? `${find.reason}${NOT_IN_BOOK}` : find.reason;

  return (
    <div className={`card tidy-card${pinned ? ' pinned' : ''}`}>
      {pinned && <div className="tidy-kicker">From your last round</div>}
      <button className="tidy-head" onClick={onToggle}>
        {!open && <MiniBoard sans={find.path} orientation={find.color} size={76} />}
        <span className="grow" style={{ minWidth: 0 }}>
          <span className="tidy-moves">
            <ColorSquare choice={find.color} size={14} />
            <span className="mine">{moveLabel(find.path.length, find.mine)}</span>
            <span className="faint">{'→'}</span>
            <span style={{ color }}>{moveLabel(find.path.length, find.suggestion)}</span>
          </span>
          <span className="tidy-reason" style={{ color }}>
            {reason}
          </span>
        </span>
      </button>
      {open && (
        <div className="tidy-board">
          <Board fen={find.fen} orientation={find.color} interactive={false} arrows={arrows} />
          {against && (
            <div className="tidy-reason" style={{ color: nudgeColor('away') }}>
              {against}
            </div>
          )}
        </div>
      )}
      <button className="btn accent block mt-8" onClick={onSwitch} disabled={checking}>
        {checking
          ? 'Checking with the engine…'
          : `Switch · removes ${find.removes} move${find.removes === 1 ? '' : 's'}`}
      </button>
    </div>
  );
}
