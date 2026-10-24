import { useEffect, useMemo, useRef, useState } from 'react';
import { Board, type Arrow } from '../components/Board';
import { SaveSheet } from '../components/SaveSheet';
import { SideSquare } from '../components/OpeningPlate';
import { AppBar, IconButton, Icons, MoveStrip, Section } from '../components/ui';
import { lastMoveOf, sansToMoveText, walkSan, type Color, type LegalMove } from '../chess/core';
import {
  arrowChoices,
  bookChoices,
  goals,
  shownStyles,
  stylePick,
  STYLES,
  turnAfter,
  type Style,
} from '../model/boardBuilder';
import { openingTree } from '../model/openingTree';
import { openingNameForPath } from '../model/reference';
import { referenceIndex } from '../model/referenceIndex';
import { useStore } from '../store/useStore';

/** A line saved from the board. */
export interface BoardLine {
  color: Color;
  sans: string[];
}

/** How long the book waits before it answers your move. */
const REPLY_MS = 350;

/** The arrows the style doesn't pick, drawn lighter. */
const OTHER_ARROW = 'rgba(138, 140, 255, 0.5)';

/**
 * Play on the board: build a Playbook by playing the moves in.
 *
 * You play your side and the book answers for the other, with its most
 * played reply, unless Book replies is off and you play both. The arrows are
 * the book's most played moves, one highlighted by
 * the style you pick. Save a line, step back and play another, and save
 * again. The same screen serves a first Playbook in onboarding and adding to
 * one from the Playbook tab.
 */
export function BoardScreen({
  onBack,
  onDone,
  doneLabel = 'Done',
}: {
  onBack: () => void;
  onDone: (saved: BoardLine[]) => void;
  doneLabel?: string;
}) {
  const settings = useStore((s) => s.settings);
  const index = referenceIndex();
  const tree = useMemo(() => openingTree(index), [index]);
  const [color, setColor] = useState<Color>('w');
  const [flipped, setFlipped] = useState(false);
  const [replies, setReplies] = useState(true);
  const [moves, setMoves] = useState<string[]>([]);
  const [cursor, setCursor] = useState(0);
  const [style, setStyle] = useState<Style>('popular');
  const [saved, setSaved] = useState<BoardLine[]>([]);
  const [saving, setSaving] = useState<string[] | null>(null);
  /** Bumped whenever the line changes by hand, so a book reply on its way to an older line is dropped. */
  const replyFor = useRef(0);

  const visible = useMemo(() => moves.slice(0, cursor), [moves, cursor]);
  const fen = useMemo(() => walkSan(visible).fens.at(-1)!, [visible]);
  const turn = turnAfter(visible);
  const mine = turn === color;
  const choices = useMemo(() => bookChoices(index, fen), [index, fen]);
  const picks = useMemo(() => {
    const out: Partial<Record<Style, string | null>> = {};
    for (const s of STYLES) out[s.id] = mine ? stylePick(index, tree, visible, choices, s.id) : null;
    return out;
  }, [index, tree, visible, choices, mine]);
  const highlight = mine ? (picks[style] ?? picks.popular ?? null) : (choices[0]?.san ?? null);
  const arrows: Arrow[] = useMemo(
    () =>
      arrowChoices(choices, highlight).flatMap((choice) => {
        const move = walkSan([...visible, choice.san]).moves.at(-1);
        return move
          ? [{ from: move.from, to: move.to, color: choice.san === highlight ? 'var(--accent)' : OTHER_ARROW }]
          : [];
      })
        // Longest first, so a short arrow along the same file as a long one is drawn on top of it.
        .sort((a, b) => reach(b) - reach(a)),
    [choices, highlight, visible],
  );
  const styles = mine ? shownStyles(picks, style) : [];
  const opening = useMemo(() => openingNameForPath(index, visible), [index, visible]);
  const [family, variation] = splitName(opening?.name);

  /** The line as it can be saved: up to your last move, so it never ends on a reply you have no answer to. */
  const toSave = visible.length && turnAfter(visible) === color ? visible.slice(0, -1) : visible;
  const savable = toSave.length > 0 && toSave.some((_, ply) => (ply % 2 === 0) === (color === 'w'));

  const setLine = (next: string[]) => {
    replyFor.current += 1;
    setMoves(next);
    setCursor(next.length);
  };

  const onMove = (move: LegalMove) => {
    const next = [...visible, move.san];
    setLine(next);
    if (!replies || turnAfter(next) === color) return;
    const token = replyFor.current;
    window.setTimeout(() => {
      if (replyFor.current !== token) return;
      const reply = bookChoices(index, walkSan(next).fens.at(-1)!)[0];
      if (reply) setLine([...next, reply.san]);
    }, REPLY_MS);
  };

  // Playing Black from the start, the book makes White's first move for you.
  useEffect(() => {
    if (!replies || mine || cursor > 0) return;
    const reply = choices[0];
    const token = replyFor.current;
    if (!reply) return;
    const timer = window.setTimeout(() => {
      if (replyFor.current === token) setLine([...visible, reply.san]);
    }, REPLY_MS);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [color, replies]);

  const seek = (n: number) => {
    replyFor.current += 1;
    setCursor(Math.max(0, Math.min(moves.length, n)));
  };

  return (
    <>
      <AppBar
        title={family ?? 'On the board'}
        subtitle={variation}
        onBack={onBack}
        actions={
          <IconButton label="Flip board" onClick={() => setFlipped(!flipped)}>
            <Icons.flip size={20} />
          </IconButton>
        }
      />
      <div className="screen no-nav board-build">
        <div className="build-top">
          <div className="segmented build-side">
            {(['w', 'b'] as Color[]).map((c) => (
              <button key={c} className={c === color ? 'active' : ''} onClick={() => setColor(c)}>
                <SideSquare color={c} />
                {c === 'w' ? 'White' : 'Black'}
              </button>
            ))}
          </div>
          <button
            className={`build-replies${moves.length === 0 && saved.length === 0 ? ' coach' : ''}`}
            onClick={() => setReplies(!replies)}
            aria-pressed={replies}
          >
            Book replies
            <span className={`state${replies ? ' on' : ''}`}>{replies ? 'On' : 'Off'}</span>
          </button>
        </div>

        <Board
          fen={fen}
          orientation={flipped ? (color === 'w' ? 'b' : 'w') : color}
          onMove={onMove}
          movableFor="both"
          lastMove={lastMoveOf(visible)}
          arrows={arrows}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
        />

        <div className="spacer sm" />
        <MoveStrip sans={moves} cursor={cursor} onSeek={seek} hint="Play a move" />

        {styles.length > 1 && (
          <>
            <Section title="Style" />
            <div className="build-styles">
              {STYLES.filter((s) => styles.includes(s.id)).map((s) => (
                <button key={s.id} className={`chip${s.id === style ? ' on' : ''}`} onClick={() => setStyle(s.id)}>
                  {s.label}
                </button>
              ))}
            </div>
          </>
        )}

        <Section title="Goals" />
        <div className="list">
          {goals(fen, color).map((goal) => (
            <div key={goal.label} className="list-row kv">
              <span className="k">{goal.label}</span>
              <span className={`v${goal.moves ? ' mono' : ''}`}>{goal.value}</span>
            </div>
          ))}
        </div>

        {saved.length > 0 && (
          <>
            <Section title="Saved" aside={`${saved.length} ${saved.length === 1 ? 'line' : 'lines'}`} />
            <div className="list">
              {saved.map((line, i) => (
                <div key={i} className="list-row build-saved">
                  <SideSquare color={line.color} />
                  <span className="movetext grow">{sansToMoveText(line.sans)}</span>
                </div>
              ))}
            </div>
          </>
        )}
      </div>
      <div className="onboard-bar build-bar">
        <button className="btn accent grow xl" disabled={!savable} onClick={() => setSaving(toSave)}>
          Save line
        </button>
        <button className="btn xl build-done" onClick={() => onDone(saved)}>
          {doneLabel}
        </button>
      </div>

      <SaveSheet
        open={!!saving}
        onClose={() => setSaving(null)}
        sans={saving ?? []}
        color={color}
        source="board"
        onSaved={(_, __, line) => setSaved((list) => [...list, { color, sans: line }])}
      />
    </>
  );
}

/** How far an arrow goes, in squares. */
function reach(arrow: Arrow): number {
  const df = arrow.to.charCodeAt(0) - arrow.from.charCodeAt(0);
  const dr = Number(arrow.to[1]) - Number(arrow.from[1]);
  return Math.hypot(df, dr);
}

/** "Italian Game: Giuoco Pianissimo" as its family and the rest. */
function splitName(name: string | undefined): [string | undefined, string | undefined] {
  if (!name) return [undefined, undefined];
  const at = name.indexOf(': ');
  return at < 0 ? [name, undefined] : [name.slice(0, at), name.slice(at + 2)];
}
