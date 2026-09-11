import { useEffect, useMemo, useState } from 'react';
import { Sheet, toast } from './ui';
import { sansToMoveText, START_FEN, walkSan } from '../chess/core';
import { repertoireList, useStore } from '../store/useStore';
import type { MoveSource } from '../model/types';

export interface AddLineSheetProps {
  open: boolean;
  onClose: () => void;
  /** Full SAN line from the start position. */
  sans: string[];
  title?: string;
  source?: MoveSource;
  /** Which side the line is meant for, when the caller knows. */
  preferColor?: 'w' | 'b';
  /** Notes to attach to the final move. */
  note?: string;
  onAdded?: (repertoireId: string, added: number) => void;
}

/**
 * Import a line into a repertoire, letting the user choose how much of it to
 * take. Tapping a move sets the cut-off — the common case is "I want this idea
 * but not twenty moves of theory".
 */
export function AddLineSheet({
  open,
  onClose,
  sans,
  title = 'Add to repertoire',
  source = 'reference',
  preferColor,
  note,
  onAdded,
}: AddLineSheetProps) {
  const state = useStore();
  const addLine = useStore((s) => s.addLine);
  const annotate = useStore((s) => s.annotate);
  const reps = repertoireList(state);
  const [depth, setDepth] = useState(sans.length);
  const [repId, setRepId] = useState<string | null>(null);

  // The sheet stays mounted between uses, so reset when a new line arrives.
  useEffect(() => {
    if (!open) return;
    setDepth(sans.length);
    setRepId(null);
  }, [open, sans]);

  const effectiveDepth = Math.min(depth, sans.length);
  const slice = sans.slice(0, effectiveDepth);

  // Suggest the repertoire whose side actually plays the last move of the line.
  const suggested = useMemo(() => {
    if (preferColor) {
      const byColor = reps.filter((r) => r.color === preferColor);
      if (byColor.length) {
        // Prefer one that already contains the start of this line.
        const opener = sans[preferColor === 'w' ? 0 : 1];
        const match = byColor.find((r) =>
          Object.values(r.nodes).some((n) => n.parentId === null && n.san === sans[0]) ||
          (opener && Object.values(r.nodes).some((n) => n.san === opener)),
        );
        return (match ?? byColor[0]).id;
      }
    }
    if (!slice.length) return reps[0]?.id ?? null;
    const lastIsWhite = (slice.length - 1) % 2 === 0;
    const wanted = lastIsWhite ? 'w' : 'b';
    return (reps.find((r) => r.color === wanted) ?? reps[0])?.id ?? null;
  }, [reps, slice.length, preferColor, sans]);

  const targetId = repId ?? suggested;
  const target = targetId ? state.repertoires[targetId] : null;

  const preview = useMemo(() => {
    const { moves } = walkSan(slice, START_FEN);
    return moves.length === slice.length;
  }, [slice]);

  const add = () => {
    if (!target || !slice.length) return;
    const res = addLine(target.id, slice, source);
    if (note) {
      const fresh = useStore.getState().repertoires[target.id];
      const tip = Object.values(fresh.nodes).find(
        (n) => n.san === slice[slice.length - 1] && n.fenAfter === walkSan(slice).fens.at(-1),
      );
      if (tip) annotate(target.id, tip.id, note);
    }
    onAdded?.(target.id, res.added);
    toast(res.added > 0 ? `${res.added} new move${res.added === 1 ? '' : 's'} added` : 'Already in your repertoire');
    onClose();
  };

  return (
    <Sheet open={open} onClose={onClose} title={title}>
      <div className="tiny faint" style={{ marginBottom: 8 }}>
        Tap a move to trim the line. {effectiveDepth} of {sans.length} plies selected.
      </div>

      <div className="card" style={{ padding: '10px 12px' }}>
        <div className="movelist">
          {sans.map((san, i) => {
            const isWhite = i % 2 === 0;
            return (
              <span key={i} style={{ display: 'contents' }}>
                {isWhite && <span className="num">{i / 2 + 1}.</span>}
                <button
                  className={`mv${i < effectiveDepth ? '' : ' future'}${i === effectiveDepth - 1 ? ' current' : ''}`}
                  onClick={() => setDepth(i + 1)}
                >
                  {san}
                </button>
              </span>
            );
          })}
        </div>
      </div>

      <div className="spacer" />
      <div className="section-title" style={{ marginTop: 0 }}>Add to</div>
      <div className="stack">
        {reps.map((rep) => (
          <button
            key={rep.id}
            className={`tree-row${rep.id === targetId ? ' preferred' : ''}`}
            onClick={() => setRepId(rep.id)}
          >
            <span className={`chip ${rep.color === 'w' ? 'white-side' : 'black-side'}`}>
              {rep.color === 'w' ? 'W' : 'B'}
            </span>
            <span className="grow truncate" style={{ fontWeight: 600 }}>{rep.name}</span>
            {rep.id === targetId && <span className="exp-inrep">selected</span>}
          </button>
        ))}
      </div>

      <div className="spacer" />
      <div className="tiny faint" style={{ marginBottom: 8 }}>
        {sansToMoveText(slice)}
      </div>
      <button className="btn primary block" disabled={!target || !slice.length || !preview} onClick={add}>
        Add {Math.ceil(effectiveDepth / 2)} move{Math.ceil(effectiveDepth / 2) === 1 ? '' : 's'} to {target?.name ?? '—'}
      </button>
      <div className="tiny faint center" style={{ marginTop: 8 }}>
        New positions where it is your turn enter the review queue immediately.
      </div>
    </Sheet>
  );
}
