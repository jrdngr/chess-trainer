import { useEffect, useMemo, useState } from 'react';
import { Icons, Section, Sheet, toast } from './ui';
import { START_FEN, walkSan } from '../chess/core';
import { displayName } from '../model/repertoire';
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
 * Import a line into your repertoire, letting the user choose how much of it to
 * take. Tapping a move sets the cut-off.
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

  // Suggest the side that actually plays the last move of the line.
  const suggested = useMemo(() => {
    if (preferColor) {
      const byColor = reps.filter((r) => r.color === preferColor);
      if (byColor.length) {
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
    toast(res.added > 0 ? `${res.added} added` : 'Already in your repertoire');
    onClose();
  };

  const moveCount = Math.ceil(effectiveDepth / 2);

  return (
    <Sheet open={open} onClose={onClose} title={title}>
      <Section title="Line" aside="Tap a move to trim" />
      <div className="card" style={{ padding: '10px 12px' }}>
        <div className="strip wrapped">
          {sans.map((san, i) => (
            <button
              key={i}
              className={`mv${i === effectiveDepth - 1 ? ' current' : ''}${i >= effectiveDepth ? ' ghost' : ''}`}
              onClick={() => setDepth(i + 1)}
            >
              {i % 2 === 0 && <span className="n">{i / 2 + 1}.</span>}
              {san}
            </button>
          ))}
        </div>
      </div>

      <Section title="Side" />
      <div className="list">
        {reps.map((rep) => (
          <button key={rep.id} className="list-row" onClick={() => setRepId(rep.id)}>
            <span className={`side ${rep.color}`} />
            <span className="grow title truncate">{displayName(rep.name)}</span>
            {rep.id === targetId && <span style={{ color: 'var(--accent)' }}><Icons.check size={18} /></span>}
          </button>
        ))}
      </div>

      <div className="spacer" />
      <button className="btn primary block" disabled={!target || !slice.length || !preview} onClick={add}>
        Add {moveCount} move{moveCount === 1 ? '' : 's'}
      </button>
    </Sheet>
  );
}
