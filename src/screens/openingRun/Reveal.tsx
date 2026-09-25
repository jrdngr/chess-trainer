import { useEffect, useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import {
  AppBar,
  copyText,
  haptic,
  Icons,
  Section,
  Strip,
  toast,
  type StripItem,
} from '../../components/ui';
import {
  applySan,
  fenTurn,
  lastMoveOf,
  positionStatus,
  sansToMoveText,
  walkSan,
  type Square,
} from '../../chess/core';
import {
  fullLine,
  gradeOf,
  lineName,
  lineToKeep,
  revealText,
  type DeathCause,
  type LineSource,
  type Run,
} from '../../model/openingRun';
import { addLine as addLineTo } from '../../model/repertoire';
import { referenceIndex } from '../../model/referenceIndex';
import type { RatingChange } from '../../model/autopilot';
import { rankOf, UNRATED } from '../../model/scoring';
import { deltaText, ratingText } from '../../components/ScoreBar';
import { repertoireList, useStore } from '../../store/useStore';
import { GRADE_TONES, Record } from './Record';
import { selectionText } from '../../components/Selection';

/** How long the verdict stays over the board when a round ends. */
const FLASH_MS = 2000;

/** Endings whose verdict has already flashed, so a return to the same one does not flash again. */
const flashed = new WeakSet<Run>();

/** How a run ended, when it did not finish. */
export interface Death {
  cause: DeathCause;
  played?: string;
  expected: string[];
  /** Centipawns dropped, for a blunder. */
  lost?: number;
}

export interface RevealProps {
  source: LineSource;
  run: Run;
  /** Null when the line was played out in full. */
  death: Death | null;
  /** Every starred opening this run moved the rating of, shallowest first. */
  moved: RatingChange[];
  /** Autopilot owns the options and the record, so the run shows neither. */
  auto?: boolean;
  /** Said in place of the usual verdict. */
  headline?: string | null;
  /** What the one tap wrote into the repertoire: the opening, and how many moves were new. */
  kept: { name: string; added: number } | null;
  /** Keep the line: the one way a finished run adds to the repertoire. */
  onKeep: () => void;
  /**
   * The offer to grow the opening, on a clean end of prep that earns one:
   * the round asked you nothing, or you finish every line in it cleanly.
   */
  grow: { text: string; onGrow: () => void } | null;
  /**
   * Grow the line just played, at any other clean end of prep. Kept at the
   * bottom of the screen, since it is there to be found rather than to
   * suggest anything.
   */
  growLine: (() => void) | null;
  /** In the button's place, when the line ended because the book did. */
  bookEnded?: boolean;
  onExit: () => void;
  /** Play on from where the round ended; null when the game is over and there is nothing to play. */
  onKeepPlaying: (() => void) | null;
  onNext: () => void;
  onChangeOptions: () => void;
  /**
   * Open the game in Analysis, up to the position the mistake was made in.
   * Only after a blunder or a miss; null otherwise.
   */
  onAnalyze?: (() => void) | null;
}

/**
 * The end of a round, however it ended, and the only screen between one round
 * and the next.
 *
 * The board becomes a replay of the whole line, parked on the position that
 * ended the run — on a miss, the position you were asked about, your move in
 * red and the prepared one in green — and the line is named, which is the
 * reward for the round ending and the one thing that must not be on screen
 * while the run is live. What to do next sits right under the board, always
 * the same two buttons in the same place: Keep playing, and Next run. It is
 * also where the line is offered to the repertoire: playing through a line
 * writes nothing, and keeping it is one tap here.
 */
export function Reveal({
  source,
  run,
  death,
  moved,
  auto,
  headline,
  kept,
  onKeep,
  grow,
  growLine,
  bookEnded,
  onExit,
  onKeepPlaying,
  onNext,
  onChangeOptions,
  onAnalyze,
}: RevealProps) {
  const settings = useStore((s) => s.settings);
  const record = useStore((s) => s.openingRun);
  const repertoires = useStore((s) => s.repertoires);
  const repertoireOrder = useStore((s) => s.repertoireOrder);
  const reps = useMemo(() => repertoireList({ repertoires, repertoireOrder }), [repertoires, repertoireOrder]);
  const survived = death === null;
  /** The most specific opening the run moved: what the round was really about. */
  const narrowest = moved.length ? moved[moved.length - 1] : null;
  const grade = gradeOf(run, death?.cause ?? null);
  const index = referenceIndex();

  /** What keeping the line would add: the theory the run went through, less what is already there. */
  const offer = useMemo(() => {
    const line = lineToKeep(index, run);
    if (!line.length) return { line, added: 0 };
    const rep = reps.find((r) => r.color === run.color);
    return { line, added: rep ? addLineTo(rep, line, 'reference').added : line.length };
  }, [index, run, reps]);

  const line = useMemo(() => {
    const sans = fullLine(source, run);
    return { sans, fens: walkSan(sans).fens, deathPly: run.played.length };
  }, [source, run]);
  const named = useMemo(() => lineName(index, source, run), [index, source, run]);

  /** Where the board is looking; starts where the run ended. */
  const [cursor, setCursor] = useState(line.deathPly);
  useEffect(() => setCursor(line.deathPly), [line.deathPly]);
  const seek = (n: number) => setCursor(Math.max(0, Math.min(line.sans.length, n)));

  const atDeath = cursor === line.deathPly;
  const shownFen = line.fens[cursor] ?? run.fen;

  /**
   * The line as chips: your moves, the opponent's, the move that ended the run
   * beside the one that would have continued it, and the rest of the line in
   * grey. The two moves at the death ply share a move number, which is not
   * notation anybody writes — it is the only honest way to show both.
   */
  const strip = useMemo<StripItem[]>(() => {
    const label = (ply: number) => (ply % 2 === 0 ? `${ply / 2 + 1}.` : undefined);
    const mine = (ply: number) => (ply % 2 === 0) === (run.color === 'w');
    const items: StripItem[] = [];
    // On the losing position the red chip is where you are, so the move that
    // led there does not also claim the cursor.
    const onBlunder = !!death?.played && atDeath;
    const bad = (ply: number): StripItem => ({
      san: death!.played!,
      label: label(ply),
      tone: 'bad',
      seek: line.deathPly,
      current: onBlunder,
    });

    line.sans.forEach((san, ply) => {
      if (ply === line.deathPly && death?.played) {
        items.push(bad(ply));
        items.push({ san, label: label(ply), tone: 'good', seek: ply + 1, current: cursor === ply + 1 });
        return;
      }
      // The way in, played for you, reads like the rest of the line past
      // the end: there, but not yours.
      items.push({
        san,
        label: label(ply),
        tone: ply < line.deathPly && ply >= run.opened ? (mine(ply) ? 'mine' : 'theirs') : 'ghost',
        seek: ply + 1,
        current: !onBlunder && cursor === ply + 1,
      });
    });
    if (death?.played && line.sans.length === line.deathPly) {
      // Nothing was prepared past here, so the losing move is the last chip.
      items.push(bad(line.deathPly));
    }
    return items;
  }, [line, run.color, run.opened, death, cursor, atDeath]);

  /** The mistake's squares, shown only on the position it was made in. */
  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' }[] = [];
    if (!death || !atDeath) return out;
    const wrong = death.played ? applySan(run.fen, death.played) : null;
    if (wrong) out.push({ square: wrong.from, kind: 'bad' }, { square: wrong.to, kind: 'bad' });
    const right = death.expected[0] ? applySan(run.fen, death.expected[0]) : null;
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [death, run.fen, atDeath]);

  /** Why the round ended, in the words and colour of its grade. */
  const verdict = (
    <div className={`verdict ${GRADE_TONES[grade]}`} style={{ padding: 0 }}>
      <span className="ico">
        {!death ? (
          <Icons.check size={18} />
        ) : death.cause === 'offprep' ? (
          <Icons.book size={16} />
        ) : (
          <Icons.cross size={18} />
        )}
      </span>
      {headline ?? (death ? deathTitle(death) : finishedTitle(run))}
    </div>
  );

  /**
   * The verdict flashes over the board as the round ends, then leaves the
   * line under the board to say it. Once per ending: coming back from playing
   * on is the same ending, so it stays quiet.
   */
  const [flashing, setFlashing] = useState(() => !flashed.has(run));
  useEffect(() => {
    flashed.add(run);
    if (!flashing) return;
    const timer = window.setTimeout(() => setFlashing(false), FLASH_MS);
    return () => window.clearTimeout(timer);
  }, [run, flashing]);

  /** The game as played, ending on the move that finished the run. */
  const playedText = sansToMoveText(death?.played ? [...run.played, death.played] : run.played);

  const copyPlayed = async () => {
    if (!playedText) return;
    if (await copyText(playedText)) {
      if (settings.hapticFeedback) haptic(10);
      toast('Moves copied');
    } else {
      toast('Could not copy');
    }
  };

  return (
    <>
      <AppBar
        title={auto ? 'Auto' : 'Run'}
        subtitle={selectionText(run.color, run.enteredIn ?? run.openingId)}
        onClose={onExit}
        actions={
          <span className="row gap-6">
            {narrowest && (
              <span className={`chip num wide ${narrowest.delta < 0 ? 'bad' : 'good'}`}>
                {deltaText(narrowest.delta)}
              </span>
            )}
            <span className="chip num wide">{run.survived}</span>
          </span>
        }
      />

      <div className="screen no-nav">
        <Board
          fen={shownFen}
          orientation={run.color}
          interactive={false}
          lastMove={death && atDeath ? null : lastMoveOf(line.sans.slice(0, cursor))}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={!!death && atDeath}
          captured
          overlay={
            flashing && (
              <div className="board-flash" onPointerDown={() => setFlashing(false)}>
                <div className="flash-pill">{verdict}</div>
              </div>
            )
          }
        />

        {grow && (
          <div className="card grow-offer">
            <span className="grow small">{grow.text}</span>
            <button className="btn accent sm" onClick={grow.onGrow}>
              <Icons.plus size={16} />
              Grow it
            </button>
          </div>
        )}

        <div className="next-row">
          <button className="btn block" disabled={!onKeepPlaying} onClick={onKeepPlaying ?? undefined}>
            <Icons.play size={18} />
            Keep playing
          </button>
          <button className="btn primary block" onClick={onNext}>
            Next run
            <Icons.next size={18} />
          </button>
        </div>
        {/* A row of its own: three buttons side by side wrap their labels on a phone. */}
        {onAnalyze && (
          <button className="btn block mt-8" onClick={onAnalyze}>
            <Icons.search size={18} />
            Analyze
          </button>
        )}

        <div className="spacer sm" />
        <Strip items={strip} cursor={cursor} max={line.sans.length} onSeek={seek} />
        <div className="spacer" />

        <Ratings moved={moved} />

        {death ? (
          <>
            {verdict}
            <div className="compare mt-8">
              <div className="good">
                <div className="k">
                  {death.cause === 'blunder' ? 'Cost' : 'Your prep'}
                </div>
                <div className="v">
                  {death.cause === 'blunder'
                    ? `−${((death.lost ?? 0) / 100).toFixed(2)}`
                    : (death.expected[0] ?? '—')}
                </div>
              </div>
              <div className="bad">
                <div className="k">You played</div>
                <div className="v">{death.played ?? '—'}</div>
              </div>
            </div>
          </>
        ) : (
          verdict
        )}

        {(kept || offer.added > 0) && <div className="spacer" />}
        <div className="actions">
          {kept ? (
            <div className="card small muted center">
              {kept.added > 0
                ? `${kept.added} move${kept.added === 1 ? '' : 's'} saved to ${kept.name}`
                : 'Already in your repertoire'}
            </div>
          ) : offer.added > 0 ? (
            <button className="btn accent block xl" onClick={onKeep}>
              <Icons.plus size={18} />
              Keep this line · {offer.added} new move{offer.added === 1 ? '' : 's'}
            </button>
          ) : null}
        </div>

        <Section title="The line" />
        <div className="card">
          <div className="row between">
            <span className="grow">
              <div className="title">{named.name}</div>
              <div className="meta">
                {named.specific ? `${run.sourceLabel} · ` : ''}
                {survived && run.past === 0 ? 'played in full' : `${run.survived} correct`}
                {run.past > 0 ? ` · ${run.past} past your prep, judged by the engine` : ''}
                {run.added > 0 ? ` · ${run.added} move${run.added === 1 ? '' : 's'} added` : ''}
                {run.hintsUsed > 0 ? ` · ${run.hintsUsed} hint${run.hintsUsed === 1 ? '' : 's'}` : ''}
              </div>
            </span>
            {named.eco && <span className="chip">{named.eco}</span>}
          </div>
          <div className="divider" />
          <div className="movetext">{revealText(source, run)}</div>
        </div>
        <button className="btn sm block mt-8" onClick={copyPlayed} disabled={!playedText}>
          <Icons.download size={16} />
          Copy the moves I played
        </button>


        {!auto && (
          <>
            <Record record={record} />
            <div className="spacer" />
            <button className="btn plain block" onClick={onChangeOptions}>
              Change options
            </button>
          </>
        )}

        {growLine && (
          <button className="btn plain block mt-8" onClick={growLine}>
            <Icons.plus size={18} />
            Grow this line
          </button>
        )}
        {!growLine && bookEnded && <div className="card small muted center mt-8">End of book line</div>}
      </div>
    </>
  );
}

function deathTitle(death: Death): string {
  return death.cause === 'offprep' ? 'Off your prep, but sound' : 'Blunder';
}

/** What a run that was not lost came to: the prep played out, or the game itself. */
function finishedTitle(run: Run): string {
  const status = positionStatus(run.fen);
  if (status.checkmate) return fenTurn(run.fen) === run.color ? 'Checkmate, you lost' : 'Checkmate, you won';
  if (status.gameOver) return 'Drawn';
  if (run.leftPrep) return 'Finished out of prep';
  return run.bookRun ? 'End of the book' : 'End of your prep';
}

/**
 * What the round did to your ratings, one line per starred opening it was
 * played inside. Nothing at all when the run touched none of them — which is
 * the usual case until something on the line is starred.
 */
function Ratings({ moved }: { moved: RatingChange[] }) {
  if (moved.length === 0) return null;
  return (
    <div className="list ratings">
      {moved.map((change) => {
        const rank = rankOf(change.after);
        const color = (rank.held ?? UNRATED).color;
        return (
          <div className="list-row" key={change.id}>
            <span className="side" style={{ background: color }} />
            <span className="grow" style={{ minWidth: 0 }}>
              <div className="title truncate">{change.name}</div>
              <div className="meta truncate">{rank.heldLabel}</div>
            </span>
            <span className={`val num ${change.delta < 0 ? 'bad' : 'good'}`}>{deltaText(change.delta)}</span>
            <span className="val num muted">{ratingText(change.after)}</span>
          </div>
        );
      })}
    </div>
  );
}
