import { useEffect, useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, copyText, haptic, Icons, Section, Segmented, Strip, toast, type StripItem } from '../../components/ui';
import { applySan, lastMoveOf, sansToMoveText, walkSan, type Square } from '../../chess/core';
import { selectionText } from '../../components/Selection';
import { formatScore, winFraction } from '../../engine/types';
import { useEngine } from '../../engine/useEngine';
import { useLens } from '../../components/Lenses';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import {
  comboMultiplier,
  moveNumber,
  openingsAlong,
  survivalFor,
  type SurvivalPrefs,
  type SurvivalRecord,
  type SurvivalRun,
} from '../../model/survival';
import { repertoireList, useStore } from '../../store/useStore';
import { offPrepHint, type TidyFind } from '../../model/tidy';
import { OffPrepHint } from '../../components/OffPrepHint';
import { ScoreRow } from './Setup';
import { Ratings, type RatingChange } from '../../components/Ratings';
import { RatingCard, RatingOverBoard, type RatingMoment } from '../../components/RatingCard';
import { useModePrefs } from '../modePrefs';

/** How long the verdict stays over the board when a run ends. */
const FLASH_MS = 2000;
/** The rating card's fade over the board before it shows below the move list. */
const LEAVE_MS = 320;

/** How a run ended. */
export type Ending =
  | {
      kind: 'blunder';
      /** The move that lost, not on the board: the board stops before it. */
      played: string;
      /** The engine's move in the same position. */
      best: string | null;
      lost: number;
      /** The opponent's best answer to it, as a UCI move: the threat that made it a blunder. */
      reply: string | null;
    }
  | { kind: 'won' | 'lost' | 'draw' }
  /** You ended it yourself, off your prep: counted apart from moves survived. */
  | { kind: 'ended' };

export function endingTitle(ending: Ending, plies: number): string {
  switch (ending.kind) {
    case 'blunder':
      return `Blunder on move ${moveNumber(plies)}`;
    case 'won':
      return 'Checkmate, you won';
    case 'lost':
      return 'Checkmate, you lost';
    case 'ended':
      return `Ended on move ${moveNumber(plies)}`;
    default:
      return 'Drawn';
  }
}

/**
 * The end of a Survival run.
 *
 * The board parks on the position you blundered in, your move in red and the
 * engine's in green. Above everything else, the number: moves survived, with
 * the best and recent form of every opening the game went through. The misses
 * — prepared positions answered with something else — are listed, and each
 * one jumps the board there. One way on: Next run.
 *
 * The board opens on the final position. The game can go on for twenty
 * moves past your prep, so "End of prep" jumps back to where it ran out, and
 * "Final position" returns. A run with room to grow where
 * its prep ran out offers it in one button, the same wherever it shows.
 *
 * The run's own opening, if its rating moved, gets its bar here and nowhere
 * during the game: the change plays over the board as the screen opens (after
 * the verdict, when there is one), a tap skips it, and the card then sits
 * below the move list.
 */
export function End({
  name,
  state,
  ending,
  before,
  moved,
  rating,
  grow,
  prepPly,
  prep,
  nextLabel,
  prefs,
  onNext,
  onChangeOptions,
  onAnalyze,
  onTidy,
  onExit,
}: {
  state: SurvivalRun;
  ending: Ending;
  /** The record as it stood before this run, to tell a new best. */
  before: SurvivalRecord;
  /** The ratings this run moved that the end screen names: favorites and the run's own opening. */
  moved: RatingChange[];
  /** The run's own opening's rating change, played on its bar; null when it did not move. */
  rating: RatingMoment | null;
  /** Grow the line from where your prep ran out — see `growOfferAt`. */
  grow: (() => void) | null;
  /**
   * Where your prep ended: the ply of the position it ran out at, or of your
   * first miss. Null when the run never reached your prep.
   */
  prepPly: number | null;
  /** How the run went on your prep, found and how fast — Autopilot's; null to leave it out. */
  prep?: string | null;
  /** Autopilot's name for the run, the opening, in place of "Survival" and the selection. */
  name?: string;
  /** "Next run", or Autopilot's "Next round". */
  nextLabel: string;
  /** Which of moments, missions and the combo the run played with. */
  prefs: Pick<SurvivalPrefs, 'moments' | 'missions' | 'combo'>;
  onNext: () => void;
  /** Back to the setup screen; absent when Autopilot set the run up. */
  onChangeOptions?: () => void;
  /**
   * Open the game in Analysis, up to the position you blundered in (or where you ended the run), so the
   * engine's continuation can be stepped through.
   */
  onAnalyze: () => void;
  /** Open Tidy on a miss whose move was closer to your other lines than your prep. */
  onTidy?: (find: TidyFind) => void;
  onExit: () => void;
}) {
  const settings = useStore((s) => s.settings);
  const record = useStore((s) => s.survival);
  const { run, moves, misses } = state;
  const tree = openingTree(referenceIndex());
  const blunder = ending.kind === 'blunder' ? ending : null;

  /** The misses whose move was closer to the rest of your lines than your prep, by ply. */
  const repertoires = useStore((s) => s.repertoires);
  const repertoireOrder = useStore((s) => s.repertoireOrder);
  const modeGrowth = useModePrefs().growth;
  const hints = useMemo(() => {
    const out = new Map<number, TidyFind>();
    if (!onTidy) return out;
    const rep = repertoireList({ repertoires, repertoireOrder }).find((r) => r.color === run.color);
    const growth = modeGrowth;
    for (const miss of misses) {
      const find = offPrepHint(rep, referenceIndex(), miss.fen, miss.played, miss.expected, {
        prefs: { priority: growth.nudgePriority, pawns: growth.nudgePawns },
        minShare: growth.minShare,
      });
      if (find) out.set(miss.ply, find);
    }
    return out;
  }, [onTidy, misses, repertoires, repertoireOrder, run.color, modeGrowth]);

  const fens = useMemo(() => walkSan(run.played).fens, [run.played]);
  const last = run.played.length;
  const prepAt = prepPly !== null && prepPly < last ? prepPly : null;
  const [cursor, setCursor] = useState(last);
  const seek = (n: number) => setCursor(Math.max(0, Math.min(last, n)));
  const shownFen = fens[cursor] ?? run.fen;
  const missAt = misses.find((miss) => miss.ply === cursor) ?? null;
  const onBlunder = !!blunder && cursor === last;
  const lens = useLens({ fen: shownFen, me: run.color, prevFen: cursor > 0 ? fens[cursor - 1] : null });

  /**
   * The eval bar, hidden while you play, shown once the game is over. On the
   * blunder it weighs the position the blunder left, so the bar shows what it
   * cost; everywhere else, the position on the board.
   */
  const weighed = onBlunder ? (applySan(run.fen, blunder!.played)?.after ?? shownFen) : shownFen;
  const { sanLines } = useEngine(settings.engineEnabled ? weighed : null, {
    enabled: settings.engineEnabled,
    depth: 16,
    multiPv: 1,
  });
  const evalLine = sanLines[0];

  const title = endingTitle(ending, last);
  const verdict = (
    <div className={`verdict ${blunder || ending.kind === 'lost' ? 'no' : ending.kind === 'won' ? 'ok' : 'warn'}`} style={{ padding: 0 }}>
      <span className="ico">
        {blunder || ending.kind === 'lost' ? (
          <Icons.cross size={18} />
        ) : ending.kind === 'ended' ? (
          <Icons.close size={18} />
        ) : (
          <Icons.check size={18} />
        )}
      </span>
      {title}
    </div>
  );

  // A blunder was already shown on the board, with its threat, before this screen.
  const [flashing, setFlashing] = useState(!blunder);
  useEffect(() => {
    if (!flashing) return;
    const timer = window.setTimeout(() => setFlashing(false), FLASH_MS);
    return () => window.clearTimeout(timer);
  }, [flashing]);

  /**
   * Where the rating card is: waiting for the verdict to clear, playing over
   * the board, fading on its way down, or in its place below the move list.
   */
  const [card, setCard] = useState<'wait' | 'play' | 'leave' | 'placed'>(() =>
    !rating || window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 'placed' : flashing ? 'wait' : 'play',
  );
  useEffect(() => {
    if (card === 'wait' && !flashing) setCard('play');
  }, [card, flashing]);
  useEffect(() => {
    if (card !== 'leave') return;
    const timer = window.setTimeout(() => setCard('placed'), LEAVE_MS);
    return () => window.clearTimeout(timer);
  }, [card]);
  const [arrived, setArrived] = useState(card === 'placed');

  /** Red for the move played, green for the one that should have been, on the position they were played in. */
  const highlights = useMemo(() => {
    const out: { square: Square; kind: 'good' | 'bad' }[] = [];
    const pair = onBlunder
      ? { fen: run.fen, played: blunder!.played, right: blunder!.best }
      : missAt
        ? { fen: missAt.fen, played: missAt.played, right: missAt.expected }
        : null;
    if (!pair) return out;
    const wrong = applySan(pair.fen, pair.played);
    if (wrong) out.push({ square: wrong.from, kind: 'bad' }, { square: wrong.to, kind: 'bad' });
    const right = pair.right ? applySan(pair.fen, pair.right) : null;
    if (right) out.push({ square: right.from, kind: 'good' }, { square: right.to, kind: 'good' });
    return out;
  }, [onBlunder, missAt, run.fen, blunder]);

  const strip = useMemo<StripItem[]>(() => {
    const label = (ply: number) => (ply % 2 === 0 ? `${ply / 2 + 1}.` : undefined);
    const mine = (ply: number) => (ply % 2 === 0) === (run.color === 'w');
    const missed = new Set(misses.map((miss) => miss.ply));
    const items: StripItem[] = run.played.map((san, ply) => ({
      san,
      label: label(ply),
      tone: ply < run.opened ? 'ghost' : missed.has(ply) ? 'bad' : mine(ply) ? 'mine' : 'theirs',
      // A miss is shown on the position it was asked in, so its chip seeks there.
      seek: missed.has(ply) ? ply : ply + 1,
      current: missed.has(ply) ? cursor === ply : cursor === ply + 1 && !missed.has(cursor) && !(blunder && cursor === last),
    }));
    if (blunder) {
      items.push({ san: blunder.played, label: label(last), tone: 'bad', seek: last, current: onBlunder });
      if (blunder.best) items.push({ san: blunder.best, label: label(last), tone: 'good', seek: last });
    }
    return items;
  }, [run.played, run.opened, run.color, misses, blunder, cursor, last]);

  /**
   * The openings this run counted for, shallowest first. The book names some
   * positions twice over at different depths, so a name already shown is not
   * shown again.
   */
  const along = useMemo(() => {
    const names = new Set<string>();
    return openingsAlong(tree, run.played).filter((id) => {
      const name = nodeById(tree, id).name;
      if (names.has(name)) return false;
      names.add(name);
      return true;
    });
  }, [tree, run.played]);
  const newBest = ending.kind !== 'ended' && moves > 0 && moves > before.global.best;
  const { extras } = state;
  /** With moments, missions or the combo on, the run is scored in points. */
  const scoredInPoints = prefs.moments || prefs.missions || prefs.combo;
  const newBestPoints =
    scoredInPoints && ending.kind !== 'ended' && extras.points > 0 && extras.points > (before.global.bestPoints ?? 0);
  const extraStats = [
    prefs.moments &&
      extras.moments.found + extras.moments.missed > 0 &&
      `Moments ${extras.moments.found} of ${extras.moments.found + extras.moments.missed}`,
    prefs.missions &&
      extras.missions.done + extras.missions.failed > 0 &&
      `Missions ${extras.missions.done} of ${extras.missions.done + extras.missions.failed}`,
    prefs.combo && extras.bestCombo >= 3 && `Best combo ×${comboMultiplier(extras.bestCombo)}`,
  ].filter(Boolean);

  const playedText = sansToMoveText(blunder ? [...run.played, blunder.played] : run.played);
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
        title={name ?? 'Survival'}
        subtitle={name ? undefined : selectionText(run.color, run.enteredIn ?? run.openingId)}
        onClose={onExit}
        actions={<span className="chip num wide">{moves}</span>}
      />

      <div className="screen no-nav">
        {prepAt !== null && (
          <div style={{ marginBottom: 10 }}>
            <Segmented
              value={cursor === prepAt ? 'prep' : cursor === last ? 'final' : ''}
              options={[
                { value: 'prep', label: 'End of prep' },
                { value: 'final', label: 'Final position' },
              ]}
              onChange={(view) => seek(view === 'prep' ? prepAt : last)}
            />
          </div>
        )}
        {settings.engineEnabled && (
          <div className="row gap-8" style={{ marginBottom: 10 }}>
            <div className="evalbar grow">
              <i style={{ width: `${winFraction(evalLine) * 100}%` }} />
            </div>
            <span className="num small muted" style={{ minWidth: 48, textAlign: 'right' }}>
              {evalLine ? formatScore(evalLine) : '—'}
            </span>
          </div>
        )}
        <Board
          fen={shownFen}
          orientation={run.color}
          interactive={false}
          lastMove={onBlunder || missAt ? null : lastMoveOf(run.played.slice(0, cursor))}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={onBlunder && !lens.marks}
          captured
          marks={lens.marks}
          overlay={
            flashing ? (
              <div className="board-flash" onPointerDown={() => setFlashing(false)}>
                <div className="flash-pill">{verdict}</div>
              </div>
            ) : rating && (card === 'play' || card === 'leave') ? (
              <RatingOverBoard
                moment={rating}
                leaving={card === 'leave'}
                onDone={() => {
                  setArrived(false);
                  setCard((now) => (now === 'play' ? 'leave' : now));
                }}
              />
            ) : null
          }
        />

        {lens.bar}
        {lens.legend}
        <div style={{ display: lens.legend ? 'none' : 'contents' }}>

        {grow && (
          <button className="btn accent block mt-12" onClick={grow}>
            <Icons.plus size={18} />
            Grow this line
          </button>
        )}

        <div className="next-row">
          {(blunder || ending.kind === 'ended') && (
            <button className="btn block" onClick={onAnalyze}>
              <Icons.search size={18} />
              Analyze
            </button>
          )}
          <button className="btn primary block" onClick={onNext}>
            {nextLabel}
            <Icons.next size={18} />
          </button>
        </div>

        <div className="spacer sm" />
        <Strip items={strip} cursor={cursor} max={last} onSeek={seek} />
        {rating && card === 'placed' && (
          <div className="mt-12" onAnimationEnd={() => setArrived(true)}>
            <RatingCard moment={rating} arriving={!arrived} />
          </div>
        )}
        <div className="spacer" />

        <Ratings moved={moved} />

        <div className="card center">
          <div className="small muted">{title}</div>
          {scoredInPoints ? (
            <>
              <div className="title num" style={{ fontSize: 26, marginTop: 4 }}>
                {extras.points} point{extras.points === 1 ? '' : 's'}
              </div>
              <div className="small mt-4">
                Survived {moves} move{moves === 1 ? '' : 's'}
              </div>
              {extraStats.length > 0 && <div className="small muted mt-4">{extraStats.join(' · ')}</div>}
            </>
          ) : (
            <div className="title" style={{ fontSize: 22, marginTop: 4 }}>
              Survived {moves} move{moves === 1 ? '' : 's'}
            </div>
          )}
          {prep && <div className="small muted mt-4 num">{prep}</div>}
          {(newBest || newBestPoints) && (
            <div className="small mt-8" style={{ color: 'var(--good)' }}>
              {newBestPoints && newBest ? 'New best, in points and moves' : newBestPoints ? 'New best score' : 'New best'}
            </div>
          )}
        </div>

        {blunder && (
          <div className="compare mt-8">
            <div className="good">
              <div className="k">Engine</div>
              <div className="v">{blunder.best ?? '—'}</div>
            </div>
            <div className="bad">
              <div className="k">You played · −{(blunder.lost / 100).toFixed(2)}</div>
              <div className="v">{blunder.played}</div>
            </div>
          </div>
        )}

        {misses.length > 0 && (
          <>
            <Section title={`Missed your prep · ${misses.length}`} />
            <div className="list">
              {misses.map((miss) => {
                const hint = hints.get(miss.ply);
                return (
                  <div key={miss.ply}>
                    <button className="list-row" onClick={() => seek(miss.ply)}>
                      <span className="grow">
                        <div className="title">Move {moveNumber(miss.ply)}</div>
                        <div className="meta">
                          You played {miss.played} · your prep {miss.expected}
                        </div>
                      </span>
                      <Icons.chevron size={18} />
                    </button>
                    {hint && onTidy && <OffPrepHint find={hint} onTidy={() => onTidy(hint)} compact />}
                  </div>
                );
              })}
            </div>
          </>
        )}

        <Section title="Moves survived" />
        <div className="list">
          {along.map((id) => (
            <ScoreRow key={id} name={nodeById(tree, id).name} score={survivalFor(record, id)} now={moves} />
          ))}
          <ScoreRow name="All openings" score={record.global} now={moves} />
        </div>

        <button className="btn sm block mt-8" onClick={copyPlayed} disabled={!playedText}>
          <Icons.download size={16} />
          Copy the moves I played
        </button>
        {onChangeOptions && (
          <>
            <div className="spacer" />
            <button className="btn plain block" onClick={onChangeOptions}>
              Change options
            </button>
          </>
        )}
        </div>
      </div>
    </>
  );
}
