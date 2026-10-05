import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, Strip, toast, type StripItem } from '../../components/ui';
import { applySan, lastMoveOf, sansToMoveText, type LegalMove, type Square } from '../../chess/core';
import {
  addsToFit,
  advance,
  answerHole,
  atHole,
  choicesAt,
  enterHole,
  firstEnd,
  firstHole,
  isUsersTurn,
  lineFor,
  movesToDraw,
  onePerPiece,
  needsEngine,
  nextHole,
  growthRows,
  optionsAt,
  popularReplies,
  preparedHere,
  recommended,
  resumeAdding,
  startGrowth,
  startGrowthAt,
  startGrowthAtEnd,
  steer,
  type GrowthRow,
  type GrowthRun,
  type Hole,
} from '../../model/growth';
import { familiarOffBook, nudgeArrows } from '../../model/nudge';
import { useSoundness } from '../../engine/soundness';
import { useEngineReplies } from '../../engine/engineReplies';
import { useMoveEvals } from '../../engine/moveEvals';
import { formatScore, winFraction } from '../../engine/types';
import { byDelta, deltaFor, deltaTone, formatDelta } from '../../model/evalDelta';
import { nodeAtLine } from '../../model/repertoire';
import { growthSource } from '../../model/moveSource';
import { formatGameCount } from '../../model/reference';
import { NudgeReasons, nudgeColor, nudgedArrows } from '../../components/Nudges';
import type { RoundRecord } from '../../model/scoring';
import { deepestNodeWithin, nodeById, openingTree } from '../../model/openingTree';
import { atPracticeCap, offerOpening, practiceOwed, practiceText } from '../../model/growOffer';
import { regionOf, type Selection } from '../../model/selection';
import { referenceIndex } from '../../model/referenceIndex';
import { selectionText } from '../../components/Selection';
import { useStore } from '../../store/useStore';
import { PlayOn } from '../openingRun/PlayOn';
import { Lobby } from './Lobby';
import { useModePrefs } from '../modePrefs';

/**
 * Growth opened from the end of a Survival run or a line drill, by its offer
 * to grow, or as one of Autopilot's rounds: straight into a run, never the
 * lobby, and the way out is back to practice.
 */
export interface GrowthLaunch {
  row: GrowthRow;
  /** The hole the round ended on, when the first run starts standing on it. */
  hole: Hole | null;
  /** The opening grown, an opening tree node id: what New run looks in. */
  region: string;
  /** "Practice these lines". */
  backLabel: string;
  onBack: () => void;
  /**
   * When the reveal points back: after every batch, for a line grown from the
   * button at the bottom of the round, or once the opening owes its cap of
   * practice, for an opening grown from the offer.
   */
  pointBack: 'batch' | 'cap';
  /** Settings the offer looked past to find this, which every run of the launch searches on. */
  widened?: { minShare: number; maxPly: number } | null;
  /**
   * Growth as one of Autopilot's rounds: New run becomes Next round, which
   * hands the session back to Autopilot.
   */
  next?: () => void;
}

export interface GrowthScreenProps {
  onExit: () => void;
  launch?: GrowthLaunch;
  /**
   * Autopilot held to one opening, for Growth opened from Home: there is no
   * session to go back to, so the card starts one on what was just grown.
   */
  onPractice?: (scope: Selection) => void;
  /** Leave for the Analysis tab on this line, seen from this side. */
  onAnalyze?: (sans: string[], side: 'w' | 'b') => void;
}

export function GrowthScreen({ onExit, launch, onPractice, onAnalyze }: GrowthScreenProps) {
  const [row, setRow] = useState<GrowthRow | null>(launch?.row ?? null);
  /**
   * Counted up for every run started, and used as the run's key: another run
   * on the same row is a run of its own, not the last one carrying on.
   */
  const [started, setStarted] = useState(0);

  const start = (next: GrowthRow) => {
    setRow(next);
    setStarted((n) => n + 1);
  };

  if (!row) return <Lobby onStart={start} onExit={onExit} />;
  return (
    <Run
      key={started}
      row={row}
      // Only the first run of a launch starts where the round ended.
      hole={launch && started === 0 ? launch.hole : null}
      region={launch?.region}
      back={launch ? { label: launch.backLabel, onBack: launch.onBack } : null}
      pointBack={launch?.pointBack ?? 'cap'}
      widened={launch?.widened ?? null}
      onPractice={launch ? undefined : onPractice}
      nextRound={launch?.next}
      onAgain={start}
      onAnalyze={onAnalyze}
      onExit={launch ? launch.onBack : () => setRow(null)}
      onClose={onExit}
    />
  );
}

type Phase = 'walking' | 'hole' | 'answered' | 'done' | 'lost';

function Run({
  row,
  hole,
  region,
  back,
  pointBack,
  widened,
  onPractice,
  nextRound,
  onAgain,
  onAnalyze,
  onExit,
  onClose,
}: {
  row: GrowthRow;
  /** Start standing at this hole rather than walking to the row's. */
  hole?: Hole | null;
  /** The opening New run looks in, when not the selection. */
  region?: string;
  /** The way back to the mode Growth was opened from, in place of the lobby. */
  back?: { label: string; onBack: () => void } | null;
  /** When the reveal's card points back to practising — see `GrowthLaunch`. */
  pointBack: 'batch' | 'cap';
  /** Search past the saved settings — see `GrowthLaunch`. */
  widened?: { minShare: number; maxPly: number } | null;
  /** Where the card goes with no mode to go back to. */
  onPractice?: (scope: Selection) => void;
  /** Autopilot's next round, in place of New run. */
  nextRound?: () => void;
  /** Start another run, on the row this one's work leaves most worth doing. */
  onAgain: (row: GrowthRow) => void;
  /** Leave for the Analysis tab on this line, seen from this side. */
  onAnalyze?: (sans: string[], side: 'w' | 'b') => void;
  /** Back to the lobby. */
  onExit: () => void;
  /** The close button: out of Growth altogether. */
  onClose: () => void;
}) {
  const state = useStore();
  const settings = state.settings;
  const addLine = useStore((s) => s.addLine);
  const removeNode = useStore((s) => s.removeNode);
  const logEvent = useStore((s) => s.logEvent);
  const endRound = useStore((s) => s.endRound);
  /** The round this sitting will log, kept current until the run is left. */
  const pending = useRef<Omit<RoundRecord, 'at'> | null>(null);
  const index = referenceIndex();
  const rep = state.repertoires[row.repertoireId];

  /** The tree as it was when the run began, so adding a move cannot re-steer it. */
  const [tree] = useState(() => rep);
  /** Where the run starts: the hole it was handed, or the one the row most wants answered. */
  const [start] = useState(() => hole ?? firstHole(index, row));
  /** A row with only lines past the book starts at the tip of one, for the engine to reply. */
  const [end] = useState(() => (start ? null : firstEnd(row)));
  const [run, setRun] = useState<GrowthRun>(() =>
    start ? startGrowthAt(tree, row, start) : end ? startGrowthAtEnd(tree, row, end) : startGrowth(tree, row),
  );
  const [phase, setPhase] = useState<Phase>(() => (start ? 'hole' : end ? 'answered' : 'walking'));
  const [wrong, setWrong] = useState<string | null>(null);
  /** Which plies of the line you added, so the strip can mark them. */
  const [added, setAdded] = useState<number[]>([]);
  /**
   * The batch being added: where it began in `added`, and how many it may add.
   *
   * Set when the run arrives at the hole the batch starts from, so the
   * allowance is measured from that depth, and cleared when the reveal is
   * asked for another batch — which is how a second batch gets the smaller
   * allowance its deeper hole has earned.
   */
  const [batch, setBatch] = useState<{ base: number; allowance: number } | null>(null);
  /** The answer just chosen, until they reply to it — the board shows it green. */
  const [answer, setAnswer] = useState<LegalMove | null>(null);
  const [thinking, setThinking] = useState(false);
  /**
   * Every answer added this sitting, oldest first, with the run and batch as
   * they stood at the reply it answered: what Undo steps back to. Only this
   * sitting's moves are here, so Undo can never reach older prep.
   */
  const [history, setHistory] = useState<
    { run: GrowthRun; batch: { base: number; allowance: number } | null; san: string }[]
  >([]);
  /** The position a carry-on game starts from, once one is asked for. */
  const [playFrom, setPlayFrom] = useState<string | null>(null);

  const prefs = useModePrefs().growth;
  /**
   * What the run looks for holes with: the saved settings, or the wider ones
   * the offer needed. A batch is still sized by the saved depth, so past it a
   * line grows a move at a time.
   */
  const find = widened ?? { minShare: prefs.minShare, maxPly: prefs.maxPly };
  const expected = useMemo(() => preparedHere(tree, run), [tree, run]);

  /** The opponent answers on its own, after a beat. */
  useEffect(() => {
    if (phase !== 'walking' || isUsersTurn(run)) return;
    if (atHole(tree, run)) return;
    setThinking(true);
    const timer = setTimeout(() => {
      setThinking(false);
      const reply = steer(tree, index, run, find);
      if (!reply) {
        setPhase('hole');
        return;
      }
      if (reply.hole) {
        setRun(enterHole(run, reply.hole));
        setPhase('hole');
        return;
      }
      const next = advance(tree, run, reply.san);
      if (next) setRun(next);
      else setPhase('hole');
    }, 420);
    return () => clearTimeout(timer);
  }, [phase, run, tree, index, find.minShare, find.maxPly]);

  /** A line that ends on the opponent's move leaves you to move with nothing. */
  useEffect(() => {
    if (phase !== 'walking') return;
    if (isUsersTurn(run) && expected.length === 0) setPhase('hole');
  }, [phase, run, expected.length]);

  /**
   * Past the book the engine is asked what to play, for you at a hole and for
   * them once you have answered. Counted so the screen moves on as it answers.
   */
  const asking = (phase === 'hole' || phase === 'answered') && needsEngine(index, run.fen) ? [run.fen] : [];
  const thinkingFor = useEngineReplies(asking, true);

  /** The moves offered at a hole — undefined while the engine is still working it out. */
  const choices = useMemo(
    () => (phase === 'hole' ? choicesAt(index, run.fen, 4) : []),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [phase, index, run.fen, thinkingFor],
  );
  const options = useMemo(() => choices ?? [], [choices]);
  const pastBook = phase === 'hole' && optionsAt(index, run.fen, 1).length === 0;

  /**
   * The moves drawn on the board, which are also the only ones playable on it,
   * coloured toward the moves that keep your repertoire narrow. The live tree
   * is read, not the one the run began with, so a move added this sitting
   * already counts as a habit.
   */
  /**
   * Familiar moves the book leaves out, or ranks too low to offer. Each is
   * put to the engine first, and only a move it passes can take the yellow
   * arrow, marked as not in the book.
   */
  const offBookAsked = useMemo(
    () =>
      phase === 'hole'
        ? familiarOffBook(rep, index, run.path, run.fen, { priority: prefs.nudgePriority, pawns: prefs.nudgePawns }, find.minShare)
        : [],
    [phase, rep, index, run.path, run.fen, find.minShare, prefs.nudgePriority, prefs.nudgePawns],
  );
  const sound = useSoundness(offBookAsked.map((san) => ({ fen: run.fen, san })));
  const offBook = offBookAsked.filter((san) => sound(run.fen, san) === true);
  const offBookKey = offBook.join(' ');
  /** Colours a set of arrows toward the familiar moves; nothing to draw away from a hole. */
  const nudge = useCallback(
    (drawn: { san: string; from: Square; to: Square }[]) =>
      phase === 'hole'
        ? nudgeArrows(
            rep,
            index,
            run.path,
            run.fen,
            drawn,
            [
              ...(pastBook ? options : popularReplies(index, run.fen, find.minShare)),
              ...(offBookKey ? offBookKey.split(' ') : []).map((san) => ({ san, share: 0 })),
            ],
            { priority: prefs.nudgePriority, pawns: prefs.nudgePawns },
            find.minShare,
            new Set(offBookKey ? offBookKey.split(' ') : []),
          )
        : [],
    [phase, rep, index, run.path, run.fen, find.minShare, prefs.nudgePriority, prefs.nudgePawns, offBookKey, pastBook, options],
  );
  /**
   * The arrows before the engine has weighed anything: past the book its
   * order, in the book the most played move of each piece. These also decide
   * which familiar move is pulled into the list, so the list — and what the
   * engine is asked to weigh — does not shift once the evals come in.
   */
  const unweighed = useMemo(
    () => nudge(pastBook ? onePerPiece(run.fen, options.map((option) => option.san)) : movesToDraw(index, run.fen)),
    [nudge, pastBook, run.fen, options, index],
  );
  /** The list under the board carries a familiar move pulled in from further down the book. */
  const listed = useMemo(() => {
    const far = unweighed.find((move) => move.tone === 'toward-far');
    if (!far || options.some((option) => option.san === far.san)) return options;
    // A move the book does not have at all is listed with nothing to count.
    const option = popularReplies(index, run.fen, 0).find((o) => o.san === far.san) ?? {
      san: far.san,
      games: 0,
      white: 0,
      draw: 0,
      black: 0,
      share: 0,
    };
    return [...options, option];
  }, [unweighed, options, index, run.fen]);

  /**
   * The eval bar, always, over whatever position the run stands on — and at a
   * hole, what each answer would do to it.
   */
  const evals = useMoveEvals(
    run.fen,
    phase === 'hole' ? listed.map((option) => option.san) : [],
  );
  const deltaOf = (san: string): number | null => {
    const after = evals.moves.get(san);
    return after === undefined || evals.position === null ? null : deltaFor(run.color, evals.position, after);
  };
  /** The answers as the engine ranks them, best on top, once it has weighed them. */
  const ranked = byDelta(listed, deltaOf);
  /**
   * Once the engine has weighed the answers, each piece's arrow goes to its
   * best one. Only the answers themselves are drawn from: a familiar move
   * pulled in from further down keeps coming in through the nudge, yellow.
   */
  const weighedOrder = options.some((option) => deltaOf(option.san) !== null)
    ? byDelta(options, deltaOf).map((option) => option.san).join(' ')
    : '';
  const shown = useMemo(
    () =>
      weighedOrder
        ? nudge(onePerPiece(run.fen, weighedOrder.split(' '), pastBook ? Infinity : 3))
        : unweighed,
    [weighedOrder, nudge, run.fen, pastBook, unweighed],
  );
  const toneOf = (san: string) => shown.find((move) => move.san === san)?.tone;

  /** What each hole put in front of you, logged once per position when its moves are in. */
  const offeredAt = useRef<string | null>(null);
  useEffect(() => {
    if (phase !== 'hole' || choices === undefined || !listed.length) return;
    if (offeredAt.current === run.fen) return;
    offeredAt.current = run.fen;
    logEvent({
      kind: 'growth-offer',
      via: 'growth',
      color: run.color,
      line: run.path.join(' '),
      offered: listed.map((option) => option.san),
      from: run.hole?.kept ? 'kept' : pastBook ? 'engine' : 'book',
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, choices, listed, run.fen]);

  /**
   * How many this batch may add, from how deep the hole it starts at is.
   *
   * Read straight from the position until the batch is recorded, so the
   * count under the board is right on the frame the hole appears.
   */
  const allowance = batch?.allowance ?? addsToFit(run.path.length, prefs.maxPly);
  const inBatch = added.length - (batch?.base ?? added.length);

  /**
   * What another batch would answer, once the run has come to rest — null when
   * the book has nothing left there, and the reveal offers nothing.
   */
  const more = useMemo(
    () => (phase === 'done' ? resumeAdding(tree, index, run) : null),
    [phase, tree, index, run],
  );

  /**
   * A hole the book cannot answer ends the batch rather than sitting there.
   *
   * The book stops where a position stops being played often enough to
   * record, and the walk can arrive just past that edge — a King's Indian
   * Sämisch runs out at 7.Nge2 — where there is nothing to choose and no
   * reason to ask. The reveal says so and offers a new run.
   */
  useEffect(() => {
    if (phase === 'hole' && choices !== undefined && choices.length === 0) setPhase('done');
  }, [phase, choices]);

  /** A batch is measured from the first hole it is offered at. */
  useEffect(() => {
    if (phase !== 'hole' || batch) return;
    setBatch({ base: added.length, allowance: addsToFit(run.path.length, prefs.maxPly) });
  }, [phase, batch, added.length, run.path.length, prefs.maxPly]);

  const onMove = (move: LegalMove) => {
    if (phase === 'hole') {
      // The board only offers the drawn moves, and taking one is the choice.
      if (shown.some((drawn) => drawn.san === move.san)) choose(move.san);
      return;
    }
    if (phase !== 'walking' || !isUsersTurn(run)) return;
    const next = advance(tree, run, move.san);
    if (!next) {
      // Your own prep is the only thing that counts here, so anything else
      // ends the run rather than quietly becoming a new line.
      setWrong(move.san);
      setPhase('lost');
      if (settings.hapticFeedback) haptic([18, 50, 18]);
      return;
    }
    setRun(next);
    if (settings.hapticFeedback) haptic(10);
  };

  /**
   * Take a move. The run walks on rather than ending: the answer is played, and
   * unless this was the last one allowed, their commonest reply to it becomes
   * the next thing to answer.
   */
  const choose = (san: string) => {
    const move = applySan(run.fen, san);
    const next = move ? answerHole(run, san) : null;
    if (!next) return;
    addLine(row.repertoireId, lineFor(run, san), growthSource(index), 'growth');
    logEvent({
      kind: 'growth-pick',
      via: 'growth',
      color: run.color,
      line: run.path.join(' '),
      picked: san,
      offered: ranked.map((option) => option.san),
    });
    setHistory((steps) => [...steps, { run, batch, san }]);
    setAdded((plies) => [...plies, run.path.length]);
    setAnswer(move);
    setRun(next);
    setPhase(inBatch + 1 >= allowance ? 'done' : 'answered');
    if (settings.hapticFeedback) haptic(10);
    toast(`${san} added`);
  };

  /**
   * Take back answers added this sitting: the last one, or all of them. The
   * move leaves the repertoire, and the run stands again on the reply it
   * answered, with the batch as it was — so the slot it took is free again.
   * Every answer is on one line, so taking back the oldest takes the rest
   * with it.
   */
  const undo = (all = false) => {
    if (!history.length) return;
    const to = all ? 0 : history.length - 1;
    const step = history[to];
    const live = useStore.getState().repertoires[row.repertoireId];
    // Standing in a hole, the reply being answered had no node either: adding
    // the answer wrote it too, so it goes with it. A line that simply ended on
    // their move had its reply already, and only the answer goes.
    // A reply you had kept stays: only the answer to it was added.
    const line = step.run.hole && !step.run.hole.kept ? step.run.path : lineFor(step.run, step.san);
    const node = live ? nodeAtLine(live, line) : null;
    if (node) removeNode(row.repertoireId, node.id, 'growth');
    logEvent({ kind: 'growth-undo', via: 'growth', color: run.color, line: lineFor(step.run, step.san).join(' '), all });
    setHistory(history.slice(0, to));
    setAdded((plies) => plies.slice(0, to));
    // Nothing left from this sitting means nothing to log on the way out.
    if (to === 0) pending.current = null;
    setAnswer(null);
    setBatch(step.batch);
    setRun(step.run);
    setPhase('hole');
    if (settings.hapticFeedback) haptic(10);
    toast(all ? 'Line undone' : `${step.san} undone`);
  };

  /**
   * Another run on the same side and settings, on whatever is now most worth
   * extending — the moves just added are in the repertoire, so the row is
   * worked out again rather than repeated. With nothing left to answer on this
   * side, the lobby is the honest answer, and it says so.
   */
  const again = () => {
    const live = state.repertoires[row.repertoireId];
    if (!live) return onExit();
    const catalogue = openingTree(index);
    const next = recommended(
      growthRows([live], index, {
        minShare: find.minShare,
        maxPly: find.maxPly,
        starred: settings.favoriteOpenings,
        region: { tree: catalogue, node: region ? nodeById(catalogue, region) : regionOf(catalogue, settings.selection) },
      }),
    );
    if (next) {
      logEvent({ kind: 'growth-start', via: 'growth', rows: [next.name], picked: next.name, start: 'new run' });
      onAgain(next);
    } else onExit();
  };

  /**
   * Take the reveal up on another batch. Nothing here happens on its own: the
   * run has stopped, and this is the tap that starts it answering again.
   */
  const addMore = () => {
    if (!more) return;
    setAnswer(null);
    setBatch(null);
    setRun(more);
    // Standing where they are to reply, past the book: the engine replies first.
    setPhase(atHole(tree, more) ? 'hole' : 'answered');
    if (settings.hapticFeedback) haptic(10);
  };

  /** Their reply to the move you just added, after a beat. */
  useEffect(() => {
    if (phase !== 'answered') return;
    const hole = nextHole(index, run);
    // Past the book, and the engine is still deciding what they play.
    if (hole === undefined) return;
    const timer = setTimeout(() => {
      // No move to make at all: the game is over, and so is the batch.
      if (!hole) {
        setPhase('done');
        return;
      }
      setAnswer(null);
      setRun(enterHole(run, hole));
      setPhase('hole');
    }, 520);
    return () => clearTimeout(timer);
  }, [phase, run, index, thinkingFor]);

  const addedSans = added.map((ply) => run.path[ply]).filter(Boolean);

  /**
   * How much practice the opening being grown is owed, read at the reveal
   * from the live repertoire, so the moves just added count.
   */
  const live = state.repertoires[row.repertoireId];
  const rounds = state.score.rounds;
  const practice = useMemo(() => {
    if (phase !== 'done' || !live) return null;
    const catalogue = openingTree(index);
    const within = nodeById(catalogue, region ?? settings.selection.opening);
    const opening = offerOpening(catalogue, within, null, run.path);
    return { opening, ...practiceOwed(live, catalogue, opening, rounds) };
  }, [phase, live, rounds, index, region, settings.selection.opening, run.path]);

  /**
   * The card that points back to practising: back to the mode that sent you,
   * or Autopilot on this one opening when Growth was opened from Home. Only
   * ever a suggestion: New run is still there underneath it.
   */
  const practiceGo = back
    ? { label: back.label, go: back.onBack }
    : onPractice && practice
      ? {
          label: 'Practice these lines',
          go: () => onPractice({ color: row.color, opening: practice.opening.id }),
        }
      : null;
  const pointingBack =
    !!practice && !!practiceGo && (pointBack === 'batch' || atPracticeCap(practice));

  /**
   * One sitting is one round, whatever it takes: the reveal only draws up what
   * the round would be, and asking for another batch redraws it.
   */
  useEffect(() => {
    if (phase !== 'done' && phase !== 'lost') return;
    const catalogue = openingTree(index);
    const within = nodeById(catalogue, region ?? settings.selection.opening);
    pending.current = {
      mode: 'growth',
      openingId: deepestNodeWithin(catalogue, within, run.path).id,
      color: run.color,
      answered: 0,
      correct: 0,
      perfect: inBatch >= allowance,
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [phase, added.length]);

  /**
   * And it is logged on the way out rather than at the reveal, because the
   * reveal is no longer the end of anything: another batch can follow it.
   */
  useEffect(() => () => {
    if (pending.current) endRound(pending.current);
  }, [endRound]);

  const strip: StripItem[] = run.path.map((san, i) => ({
    san,
    label: i % 2 === 0 ? `${Math.floor(i / 2) + 1}.` : undefined,
    tone: added.includes(i)
      ? 'good'
      : (i % 2 === 0) === (run.color === 'w')
        ? 'mine'
        : 'theirs',
    current: i === run.path.length - 1,
  }));

  if (playFrom) {
    return (
      <PlayOn
        from={playFrom}
        color={run.color}
        label={row.name}
        onBack={() => setPlayFrom(null)}
      />
    );
  }

  if (!rep) {
    return (
      <>
        <AppBar title="Growth" onClose={onClose} />
        <div className="screen no-nav">
          <div className="empty">
            <div className="t">Those lines are gone</div>
          </div>
        </div>
      </>
    );
  }

  return (
    <>
      <AppBar
        title="Growth"
        subtitle={selectionText(run.color, region ?? settings.selection.opening)}
        onClose={onClose}
        actions={
          <span className="num muted small appbar-gap" style={{ textAlign: 'right' }}>
            {Object.keys(rep.nodes).length}
          </span>
        }
      />

      <div className="screen no-nav">
        <div className="row gap-8" style={{ marginBottom: 10 }}>
          <div className="evalbar grow">
            <i style={{ width: `${winFraction(evals.position === null ? undefined : { cp: evals.position, mate: null }) * 100}%` }} />
          </div>
          <span className="num small muted" style={{ minWidth: 48, textAlign: 'right' }}>
            {evals.position === null ? '—' : formatScore({ cp: evals.position, mate: null })}
          </span>
        </div>

        <Board
          fen={run.fen}
          orientation={run.color}
          interactive={(phase === 'walking' && isUsersTurn(run)) || phase === 'hole'}
          movableFor={run.color}
          allowed={phase === 'hole' ? shown.map((move) => move.san) : undefined}
          arrows={nudgedArrows(shown)}
          onMove={onMove}
          // The green highlight below stands in for the usual last-move tint on
          // the move that was just added, so the two do not compete.
          lastMove={answer ? null : lastMoveOf(run.path)}
          highlights={
            answer
              ? [
                  { square: answer.from, kind: 'good' },
                  { square: answer.to, kind: 'good' },
                ]
              : []
          }
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={phase === 'lost'}
          captured
        />

        {phase === 'done' && (
          <div className="next-row">
            {onAnalyze && (
              <button className="btn block" onClick={() => onAnalyze(run.path, run.color)}>
                <Icons.search size={18} />
                Analyze
              </button>
            )}
            <button className="btn primary block" onClick={nextRound ?? again}>
              {nextRound ? 'Next round' : 'New run'}
              <Icons.next size={18} />
            </button>
          </div>
        )}

        <div className="spacer sm" />
        {run.path.length > 0 && <Strip items={strip} />}
        <div className="spacer sm" />

        {phase === 'walking' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${isUsersTurn(run) ? run.color : other(run.color)}`} />
              {thinking ? 'Thinking…' : isUsersTurn(run) ? 'Your move' : 'Their move'}
            </div>
          </div>
        )}

        {phase === 'answered' && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${other(run.color)}`} />
              Thinking…
            </div>
            {inBatch > 0 && (
              <div className="ctx">
                {inBatch} of {allowance} added
              </div>
            )}
          </div>
        )}

        {phase === 'hole' && choices === undefined && (
          <div className="prompt">
            <div className="who">
              <span className={`side ${run.color}`} />
              {run.hole ? `They played ${run.hole.san}` : 'Your prep ends here'}
            </div>
            <div className="ctx">Past the book · the engine is finding moves…</div>
          </div>
        )}

        {phase === 'lost' && (
          <>
            <div className="row between">
              <div className="verdict no" style={{ padding: 0 }}>
                <span className="ico"><Icons.cross size={14} /></span>
                Not your prep
              </div>
              <button className="btn primary sm" onClick={onExit}>
                Back
                <Icons.next size={16} />
              </button>
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">Repertoire</div>
                <div className="v">{expected.map((e) => e.san).join(' / ') || '—'}</div>
              </div>
              <div className="bad">
                <div className="k">Played</div>
                <div className="v">{wrong}</div>
              </div>
            </div>
          </>
        )}

        {phase === 'hole' && options.length > 0 && (
          <>
            <div className="prompt">
              <div className="who">
                <span className={`side ${run.color}`} />
                {run.hole ? `They played ${run.hole.san}` : 'Your prep ends here'}
              </div>
              {run.hole && (
                <div className="ctx">
                  {run.hole.kept
                    ? 'In your repertoire, with no answer yet'
                    : run.hole.engine
                      ? "Engine's pick · past the book"
                      : `${run.hole.share}% of strong players' games · ${formatGameCount(run.hole.games)}`}
                </div>
              )}
            </div>

            <NudgeReasons moves={shown} />

            <Section
              title="Answer it"
              aside={inBatch > 0 ? `${inBatch} of ${allowance} added` : `up to ${allowance}`}
            />
            <div className="list">
              {ranked.map((option) => (
                <button className="list-row" key={option.san} onClick={() => choose(option.san)}>
                  <span className="tree-san" style={{ color: nudgeColor(toneOf(option.san)) }}>
                    {option.san}
                  </span>
                  <span className="grow">
                    <div className="meta">
                      {option.games > 0
                        ? `${option.share}% of strong players' replies · ${formatGameCount(option.games)} games`
                        : 'engine' in option && option.engine
                          ? "Engine's pick · past the book"
                          : 'Not in the book · passed by the engine'}
                    </div>
                  </span>
                  <DeltaTag cp={deltaOf(option.san)} />
                  <Icons.plus size={18} />
                </button>
              ))}
            </div>
            {history.length > 0 && (
              <div className="row mt-8">
                <button className="btn grow" onClick={() => undo()}>
                  <Icons.undo size={18} />
                  Undo
                </button>
                <button className="btn grow" onClick={() => setPhase('done')}>
                  Stop here
                </button>
              </div>
            )}
          </>
        )}

        {phase === 'done' && (
          <>
            {pointingBack && (
              <div className="card grow-offer" style={{ marginTop: 0, marginBottom: 12 }}>
                <span className="grow small">{practiceText(practice!.opening.name, practice!.owed)}</span>
                <button className="btn accent sm" onClick={practiceGo!.go}>
                  {practiceGo!.label}
                  <Icons.next size={16} />
                </button>
              </div>
            )}
            <div className={`verdict ${addedSans.length ? 'ok' : 'warn'}`} style={{ padding: 0 }}>
              <span className="ico">
                {addedSans.length ? <Icons.check size={16} /> : <Icons.warn size={16} />}
              </span>
              {addedSans.length === 0
                ? 'Nothing to add here'
                : addedSans.length === 1
                  ? `${addedSans[0]} added`
                  : `${addedSans.length} moves added`}
            </div>
            <Section title="The line now" />
            <div className="card">
              <div className="movetext">{sansToMoveText(run.path)}</div>
            </div>
            {history.length > 0 && (
              <div className="row mt-8">
                <button className="btn grow" onClick={() => undo()}>
                  <Icons.undo size={18} />
                  Undo
                </button>
                <button className="btn grow" onClick={() => undo(true)}>
                  Undo all
                </button>
              </div>
            )}
            {!more && (
              <div className="card small muted mt-8">There are no moves left to answer here.</div>
            )}
            {more && (
              <button className="btn block mt-12" onClick={addMore}>
                <Icons.plus size={18} />
                Add more moves
              </button>
            )}
            <button className={`btn block ${more ? 'mt-8' : 'mt-12'}`} onClick={() => setPlayFrom(run.fen)}>
              <Icons.play size={18} />
              Play from here
            </button>
            {!(pointingBack && back) && !nextRound && (
              <button className="btn plain block mt-8" onClick={back ? back.onBack : onExit}>
                {back ? back.label : 'Back to openings'}
              </button>
            )}
          </>
        )}
      </div>
    </>
  );
}

/** What an answer does to the eval bar, from your side: "+0.2", "−1.4", or a dash while the engine works. */
function DeltaTag({ cp }: { cp: number | null }) {
  const tone = cp === null ? 'even' : deltaTone(cp);
  const color = tone === 'good' ? 'var(--good)' : tone === 'bad' ? 'var(--bad)' : 'var(--text-3)';
  return (
    <span className="num small" style={{ color, minWidth: 40, textAlign: 'right', marginRight: 8 }}>
      {cp === null ? '…' : formatDelta(cp)}
    </span>
  );
}

function other(color: 'w' | 'b'): 'w' | 'b' {
  return color === 'w' ? 'b' : 'w';
}
