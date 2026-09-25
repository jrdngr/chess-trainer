import { useEffect, useMemo, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, copyText, haptic, Icons, Section, Strip, toast, type StripItem } from '../../components/ui';
import { applySan, lastMoveOf, sansToMoveText, walkSan, type Square } from '../../chess/core';
import { selectionText } from '../../components/Selection';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import { moveNumber, openingsAlong, survivalFor, type SurvivalRecord, type SurvivalRun } from '../../model/survival';
import { useStore } from '../../store/useStore';
import { ScoreRow } from './Setup';

/** How long the verdict stays over the board when a run ends. */
const FLASH_MS = 2000;

/** How a run ended. */
export type Ending =
  | {
      kind: 'blunder';
      /** The move that lost, not on the board: the board stops before it. */
      played: string;
      /** The engine's move in the same position. */
      best: string | null;
      lost: number;
    }
  | { kind: 'won' | 'lost' | 'draw' };

export function endingTitle(ending: Ending, plies: number): string {
  switch (ending.kind) {
    case 'blunder':
      return `Blunder on move ${moveNumber(plies)}`;
    case 'won':
      return 'Checkmate, you won';
    case 'lost':
      return 'Checkmate, you lost';
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
 */
export function End({
  state,
  ending,
  before,
  onNext,
  onChangeOptions,
  onAnalyse,
  onExit,
}: {
  state: SurvivalRun;
  ending: Ending;
  /** The record as it stood before this run, to tell a new best. */
  before: SurvivalRecord;
  onNext: () => void;
  onChangeOptions: () => void;
  /**
   * Open the game in Analysis, up to the position you blundered in, so the
   * engine's continuation can be stepped through.
   */
  onAnalyse: () => void;
  onExit: () => void;
}) {
  const settings = useStore((s) => s.settings);
  const record = useStore((s) => s.survival);
  const { run, moves, misses } = state;
  const tree = openingTree(referenceIndex());
  const blunder = ending.kind === 'blunder' ? ending : null;

  const fens = useMemo(() => walkSan(run.played).fens, [run.played]);
  const last = run.played.length;
  const [cursor, setCursor] = useState(last);
  const seek = (n: number) => setCursor(Math.max(0, Math.min(last, n)));
  const shownFen = fens[cursor] ?? run.fen;
  const missAt = misses.find((miss) => miss.ply === cursor) ?? null;
  const onBlunder = !!blunder && cursor === last;

  const title = endingTitle(ending, last);
  const verdict = (
    <div className={`verdict ${blunder || ending.kind === 'lost' ? 'no' : ending.kind === 'won' ? 'ok' : 'warn'}`} style={{ padding: 0 }}>
      <span className="ico">{blunder || ending.kind === 'lost' ? <Icons.cross size={18} /> : <Icons.check size={18} />}</span>
      {title}
    </div>
  );

  const [flashing, setFlashing] = useState(true);
  useEffect(() => {
    if (!flashing) return;
    const timer = window.setTimeout(() => setFlashing(false), FLASH_MS);
    return () => window.clearTimeout(timer);
  }, [flashing]);

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
  const newBest = moves > 0 && moves > before.global.best;

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
        title="Survival"
        subtitle={selectionText(run.color, run.enteredIn ?? run.openingId)}
        onClose={onExit}
        actions={<span className="chip num wide">{moves}</span>}
      />

      <div className="screen no-nav">
        <Board
          fen={shownFen}
          orientation={run.color}
          interactive={false}
          lastMove={onBlunder || missAt ? null : lastMoveOf(run.played.slice(0, cursor))}
          highlights={highlights}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={onBlunder}
          captured
          overlay={
            flashing && (
              <div className="board-flash" onPointerDown={() => setFlashing(false)}>
                <div className="flash-pill">{verdict}</div>
              </div>
            )
          }
        />

        <div className="next-row">
          {blunder && (
            <button className="btn block" onClick={onAnalyse}>
              <Icons.search size={18} />
              Analyse
            </button>
          )}
          <button className="btn primary block" onClick={onNext}>
            Next run
            <Icons.next size={18} />
          </button>
        </div>

        <div className="spacer sm" />
        <Strip items={strip} cursor={cursor} max={last} onSeek={seek} />
        <div className="spacer" />

        <div className="card center">
          <div className="small muted">{title}</div>
          <div className="title" style={{ fontSize: 22, marginTop: 4 }}>
            Survived {moves} move{moves === 1 ? '' : 's'}
          </div>
          {newBest && (
            <div className="small mt-8" style={{ color: 'var(--good)' }}>
              New best
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
              {misses.map((miss) => (
                <button className="list-row" key={miss.ply} onClick={() => seek(miss.ply)}>
                  <span className="grow">
                    <div className="title">Move {moveNumber(miss.ply)}</div>
                    <div className="meta">
                      You played {miss.played} · your prep {miss.expected}
                    </div>
                  </span>
                  <Icons.chevron size={18} />
                </button>
              ))}
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
        <div className="spacer" />
        <button className="btn plain block" onClick={onChangeOptions}>
          Change options
        </button>
      </div>
    </>
  );
}
