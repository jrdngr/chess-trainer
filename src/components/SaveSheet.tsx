import { useEffect, useMemo, useState } from 'react';
import { Icons, Segmented, Section, Sheet, toast } from './ui';
import { walkSan, type Color } from '../chess/core';
import { useLineChecks } from '../engine/lineChecks';
import { bookLength, lineKinds, movedBy } from '../model/extensions';
import { BLUNDER_LIMIT } from '../model/openingRun';
import { referenceIndex } from '../model/referenceIndex';
import type { MoveSource } from '../model/types';
import { useStore } from '../store/useStore';

export interface SaveSheetProps {
  open: boolean;
  onClose: () => void;
  /** The whole line, from the start position. */
  sans: string[];
  /** The side it goes in for, when the caller knows. Otherwise the sheet asks. */
  color?: Color;
  /** The side to suggest when the sheet asks. */
  preferColor?: Color;
  /** Let the line be cut short by tapping a move. */
  trim?: boolean;
  title?: string;
  source: MoveSource;
  /** A note for the line's last move. */
  note?: string;
  onSaved?: (repertoireId: string, added: number, sans: string[]) => void;
  /**
   * Take the line instead of saving it, with what the engine said of its
   * moves: onboarding holds its lines until the Playbook is confirmed.
   */
  onKeep?: (sans: string[], color: Color, lost: (number | undefined)[]) => void;
}

/** The most an extension is checked for, from where it leaves the book. */
const CHECK_PLIES = 10;

/**
 * Saving a line, the same sheet everywhere a line comes in by hand.
 *
 * It splits the line where it leaves the book: the Playbook part, and the
 * extension under it, which the engine checks as the sheet opens. A mistake
 * of yours is flagged, and either way you can leave the extension out or save
 * both. The extension's checks are kept on its moves, which is what later
 * tells a saved mistake from a rare move — see `model/extensions.ts`.
 */
export function SaveSheet({
  open,
  onClose,
  sans,
  color,
  preferColor,
  trim,
  title = 'Save line',
  source,
  note,
  onSaved,
  onKeep,
}: SaveSheetProps) {
  const addLine = useStore((s) => s.addLine);
  const annotate = useStore((s) => s.annotate);
  const ensureRepertoire = useStore((s) => s.ensureRepertoire);
  const [depth, setDepth] = useState(sans.length);
  const [picked, setPicked] = useState<Color | null>(null);

  // The sheet stays mounted between uses, so start over when a new line arrives.
  useEffect(() => {
    if (!open) return;
    setDepth(sans.length);
    setPicked(null);
  }, [open, sans]);

  const slice = useMemo(() => sans.slice(0, Math.min(depth, sans.length)), [sans, depth]);
  const legal = useMemo(() => walkSan(slice).moves.length === slice.length, [slice]);
  const side: Color = color ?? picked ?? preferColor ?? (slice.length % 2 === 1 ? 'w' : 'b');

  const index = referenceIndex();
  const book = useMemo(() => bookLength(lineKinds(index, slice, side)), [index, slice, side]);
  const extPlies = useMemo(
    () => Array.from({ length: Math.max(0, Math.min(slice.length, book + CHECK_PLIES) - book) }, (_, i) => book + i),
    [slice.length, book],
  );
  const checks = useLineChecks(slice, extPlies, open && extPlies.length > 0);
  const lost = slice.map((_, ply) => checks.get(ply)?.lost);

  const hasExt = book < slice.length;
  const pending = extPlies.some((ply) => !checks.has(ply));
  const mistake = extPlies.find((ply) => movedBy(ply, side) && (checks.get(ply)?.lost ?? 0) > BLUNDER_LIMIT);
  const shownPly = mistake ?? extPlies[extPlies.length - 1];
  const shownEval = shownPly === undefined ? undefined : checks.get(shownPly)?.after;

  const save = (upTo: number) => {
    const line = slice.slice(0, upTo);
    if (!line.length) return;
    if (onKeep) {
      onKeep(line, side, lost.slice(0, upTo));
      toast('Saved');
      onClose();
      return;
    }
    const repId = ensureRepertoire(side);
    const res = addLine(repId, line, source, undefined, lost.slice(0, upTo));
    if (note && upTo === slice.length) {
      const rep = useStore.getState().repertoires[repId];
      const tipFen = walkSan(line).fens.at(-1);
      const tip = Object.values(rep.nodes).find((n) => n.san === line[line.length - 1] && n.fenAfter === tipFen);
      if (tip) annotate(repId, tip.id, note);
    }
    onSaved?.(repId, res.added, line);
    toast(res.added > 0 ? `${res.added} added` : 'Already in your Playbook');
    onClose();
  };

  const firstExt = hasExt ? plyLabel(slice, book) : '';
  const tone = !hasExt ? '' : mistake !== undefined ? ' warn' : pending ? '' : ' good';

  return (
    <Sheet open={open} onClose={onClose} title={title}>
      {trim && (
        <>
          <Section title="Line" aside="Tap a move to trim" />
          <div className="card" style={{ padding: '10px 12px' }}>
            <div className="strip wrapped">
              {sans.map((san, i) => (
                <button
                  key={i}
                  className={`mv${i === slice.length - 1 ? ' current' : ''}${i >= slice.length ? ' ghost' : ''}`}
                  onClick={() => setDepth(i + 1)}
                >
                  {i % 2 === 0 && <span className="n">{i / 2 + 1}.</span>}
                  {san}
                </button>
              ))}
            </div>
          </div>
        </>
      )}

      {!color && (
        <>
          <Section title="Side" />
          <Segmented
            value={side}
            options={[
              { value: 'w', label: 'As White' },
              { value: 'b', label: 'As Black' },
            ]}
            onChange={(c) => setPicked(c)}
          />
        </>
      )}

      {slice.length > 0 && (
        <div className="save-split">
          {book > 0 && (
            <div className="save-row">
              <span className="label">Playbook</span>
              <span className="line">{snippet(slice, 0, book)}</span>
              <span className="val">{moveCount(book)}</span>
            </div>
          )}
          {hasExt && (
            <div className={`save-row ext${tone}`}>
              {mistake !== undefined ? <Icons.warn size={18} /> : !pending ? <Icons.check size={18} /> : null}
              <span className="label">{mistake !== undefined ? 'Mistake' : 'Extension'}</span>
              <span className="line">{mistake !== undefined ? plyLabel(slice, mistake) : snippet(slice, book, slice.length)}</span>
              <span className="val">{shownEval === undefined ? '…' : pawns(shownEval, side)}</span>
            </div>
          )}
        </div>
      )}

      <div className="spacer" />
      {hasExt && book > 0 ? (
        <div className="row gap-8">
          <button className="btn grow" disabled={!legal} onClick={() => save(book)}>
            Leave out {firstExt}
          </button>
          <button className="btn accent grow" disabled={!legal} onClick={() => save(slice.length)}>
            Save both
          </button>
        </div>
      ) : (
        <button className="btn accent block" disabled={!legal || !slice.length} onClick={() => save(slice.length)}>
          Save
        </button>
      )}
    </Sheet>
  );
}

/** "5.Ng5" or "5...Nf6": one move with its number. */
export function plyLabel(sans: string[], ply: number): string {
  const n = Math.floor(ply / 2) + 1;
  return ply % 2 === 0 ? `${n}.${sans[ply]}` : `${n}...${sans[ply]}`;
}

/** Part of a line, short: "1.e4 … 4.d3 Nf6", in full when it is three moves or fewer. */
export function snippet(sans: string[], from: number, to: number): string {
  const parts: string[] = [];
  for (let ply = from; ply < to; ply++) {
    parts.push(ply % 2 === 0 ? `${Math.floor(ply / 2) + 1}.${sans[ply]}` : ply === from ? plyLabel(sans, ply) : sans[ply]);
  }
  if (parts.length <= 3) return parts.join(' ');
  const last = to - 1;
  const tail = last % 2 === 1 && last - 1 > from ? `${parts[parts.length - 2]} ${parts[parts.length - 1]}` : plyLabel(sans, last);
  return `${parts[0]} … ${tail}`;
}

function moveCount(plies: number): string {
  const n = Math.ceil(plies / 2);
  return `${n} move${n === 1 ? '' : 's'}`;
}

/** An eval in pawns from one side: "+0.3", "−0.6". */
export function pawns(whiteCp: number, side: Color): string {
  const cp = side === 'w' ? whiteCp : -whiteCp;
  if (Math.abs(cp) >= 9000) return cp > 0 ? 'Mate' : 'Mated';
  const value = (Math.abs(cp) / 100).toFixed(1);
  return cp > 0 ? `+${value}` : cp < 0 ? `−${value}` : '0.0';
}
