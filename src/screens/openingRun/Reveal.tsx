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
import { applySan, lastMoveOf, sansToMoveText, walkSan, type Square } from '../../chess/core';
import {
  extendedMoves,
  fullLine,
  gradeOf,
  isExtended,
  lineName,
  revealText,
  type DeathCause,
  type LineSource,
  type Run,
} from '../../model/openingRun';
import { referenceIndex } from '../../model/referenceIndex';
import { useStore } from '../../store/useStore';
import { GRADE_TONES, Record } from './Record';
import { selectionText } from '../../components/Selection';

/** How a run ended, when it did not finish the line. */
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
  /** Points this run banked. */
  earned: number;
  /** Autopilot owns what happens next, so the run offers nothing of its own. */
  auto?: boolean;
  /** What the run wrote into the repertoire: the opening, and how many moves were new. */
  saved: { name: string; added: number } | null;
  onExit: () => void;
  onNewRun: () => void;
  onChangeOptions: () => void;
  /** Carry the shown position on against the engine. */
  onPlayOn: (fen: string) => void;
  /** Carry the run itself on under extended rules. */
  onContinueExtended: () => void;
}

/**
 * The post-mortem. The board becomes a replay of the whole line, parked on the
 * position that ended the run, and the line is named — which is the reward for
 * dying, and the one thing that must not be on screen while the run is live.
 */
export function Reveal({
  source,
  run,
  death,
  earned,
  auto,
  saved,
  onExit,
  onNewRun,
  onChangeOptions,
  onPlayOn,
  onContinueExtended,
}: RevealProps) {
  const settings = useStore((s) => s.settings);
  const record = useStore((s) => s.openingRun);
  const survived = death === null;
  const grade = gradeOf(run, survived);
  const past = extendedMoves(run);

  const line = useMemo(() => {
    const sans = fullLine(source, run);
    return { sans, fens: walkSan(sans).fens, deathPly: run.played.length };
  }, [source, run]);
  const named = useMemo(() => lineName(referenceIndex(), source, run), [source, run]);

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

  /** Shared by both endings, which differ in everything but this. */
  const actions = (
    <div className="row gap-8">
      {!auto && (
        <button className="btn primary sm" onClick={onNewRun}>
          New run
          <Icons.next size={16} />
        </button>
      )}
    </div>
  );

  return (
    <>
      <AppBar
        title="Run"
        subtitle={selectionText(run.color, run.openingId)}
        onClose={onExit}
        actions={
          <span className="row gap-6">
            <span className="chip good num wide">+{earned}</span>
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
          dimmed={atDeath}
          captured
        />

        <div className="spacer sm" />
        <Strip items={strip} cursor={cursor} max={line.sans.length} onSeek={seek} />
        <div className="spacer" />

        {death ? (
          <>
            <div className="row between">
              <div className={`verdict ${GRADE_TONES[grade]}`} style={{ padding: 0 }}>
                <span className="ico">
                  {death.cause === 'offprep' ? <Icons.book size={16} /> : <Icons.cross size={18} />}
                </span>
                {deathTitle(death, grade === 'purple')}
              </div>
              {actions}
            </div>
            <div className="compare mt-8">
              <div className="good">
                <div className="k">
                  {death.cause === 'blunder' ? 'Cost' : 'Expected'}
                </div>
                <div className="v">
                  {death.cause === 'blunder'
                    ? `−${((death.lost ?? 0) / 100).toFixed(2)}`
                    : (death.expected[0] ?? '—')}
                </div>
              </div>
              <div className={death.cause === 'time' ? '' : 'bad'}>
                <div className="k">You played</div>
                <div className="v">{death.played ?? '—'}</div>
              </div>
            </div>
          </>
        ) : (
          <div className="row between">
            <div className={`verdict ${GRADE_TONES[grade]}`} style={{ padding: 0 }}>
              <span className="ico">
                <Icons.check size={18} />
              </span>
              {grade === 'yellow' ? 'Complete, out of prep' : 'Line complete'}
            </div>
            {actions}
          </div>
        )}

        <div className="spacer" />
        {!auto && (
          <div className="actions">
            {survived && !isExtended(run) && (
              <button className="btn accent block xl" onClick={onContinueExtended}>
                <Icons.bolt size={18} />
                Continue in extended mode
              </button>
            )}
            <button className="btn block" onClick={() => onPlayOn(shownFen)}>
              <Icons.play size={18} />
              Play from here
            </button>
          </div>
        )}

        <Section title="The line" />
        <div className="card">
          <div className="row between">
            <span className="grow">
              <div className="title">{named.name}</div>
              <div className="meta">
                {named.specific ? `${run.sourceLabel} · ` : ''}
                {survived && past === 0 ? 'played in full' : `${run.survived} correct`}
                {past > 0 ? ` · ${past} past prep` : ''}
                {run.added > 0 ? ` · ${run.added} move${run.added === 1 ? '' : 's'} added` : ''}
                {run.hintsUsed > 0 ? ` · ${run.hintsUsed} hint${run.hintsUsed === 1 ? '' : 's'}` : ''}
                {saved
                  ? saved.added > 0
                    ? ` · ${saved.added} move${saved.added === 1 ? '' : 's'} saved to your repertoire`
                    : ' · already in your repertoire'
                  : ''}
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
        {auto && <div style={{ height: 96 }} />}
      </div>
    </>
  );
}

function deathTitle(death: Death, leftPrep: boolean): string {
  switch (death.cause) {
    case 'time':
      return 'Out of time';
    case 'blunder':
      return 'Blunder';
    case 'offprep':
      return 'Stopped out of prep';
    default:
      return leftPrep ? 'Run over, out of prep' : 'Run over';
  }
}
