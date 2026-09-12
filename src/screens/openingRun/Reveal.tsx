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
  BLUNDER_LIMIT,
  canKeepLine,
  extendedMoves,
  fullLine,
  gradeOf,
  isExtended,
  lineName,
  lineToKeep,
  revealText,
  type DeathCause,
  type LineSource,
  type Run,
} from '../../model/openingRun';
import { referenceIndex } from '../../model/referenceIndex';
import { useStore } from '../../store/useStore';
import { GRADE_TONES, Record } from './Record';

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
  /** Write the line into a repertoire; returns what it added. */
  onSaveLine: () => { name: string; added: number } | null;
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
  onSaveLine,
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
  const [saved, setSaved] = useState(false);

  const keep = () => {
    const result = onSaveLine();
    if (!result) return;
    setSaved(true);
    toast(result.added > 0 ? `Saved to ${result.name}` : `Already in ${result.name}`);
  };
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
      items.push({
        san,
        label: label(ply),
        tone: ply < line.deathPly ? (mine(ply) ? 'mine' : 'theirs') : 'ghost',
        seek: ply + 1,
        current: !onBlunder && cursor === ply + 1,
      });
    });
    if (death?.played && line.sans.length === line.deathPly) {
      // Nothing was prepared past here, so the losing move is the last chip.
      items.push(bad(line.deathPly));
    }
    return items;
  }, [line, run.color, death, cursor, atDeath]);

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

  const survivedLabel = run.survived === 1 ? '1 move' : `${run.survived} moves`;
  const prep = run.source === 'book' ? 'the book' : 'your prep';

  /**
   * Shared by both endings, which differ in everything but this.
   *
   * Saving is offered rather than done: a book run can hand you any opening in
   * the database, and keeping every one of them builds a wide, shallow
   * repertoire instead of a coherent one. Deciding at the end, having seen the
   * line, is the only point at which that judgement can be made.
   */
  const actions = (
    <div className="row gap-8">
      {canKeepLine(run.source) && lineToKeep(run).length > 0 && (
        <button className="btn sm" disabled={!!saved} onClick={keep}>
          {saved ? 'Saved' : 'Save line'}
        </button>
      )}
      <button className="btn primary sm" onClick={onNewRun}>
        New run
        <Icons.next size={16} />
      </button>
    </div>
  );

  return (
    <>
      <AppBar
        title="Opening Run"
        subtitle={survived ? 'Survived' : 'Run over'}
        onClose={onExit}
        actions={<span className="chip num wide">{run.survived}</span>}
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
        />

        <div className="spacer sm" />
        <Strip items={strip} cursor={cursor} max={line.sans.length} onSeek={seek} />
        <div className="note center">{whereYouAre(cursor, line.deathPly, survived)}</div>
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
                  {death.cause === 'blunder' ? 'Cost' : run.source === 'book' ? 'Book' : 'Repertoire'}
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
            <div className="note center">{deathNote(death, run)}</div>
          </>
        ) : (
          <>
            <div className="row between">
              <div className={`verdict ${GRADE_TONES[grade]}`} style={{ padding: 0 }}>
                <span className="ico">
                  <Icons.check size={18} />
                </span>
                {grade === 'yellow' ? 'Complete, out of prep' : 'Line complete'}
              </div>
              {actions}
            </div>
            <div className="note center">
              {past > 0
                ? `${survivedLabel} without a slip, ${past} of them past ${prep} — the game itself ran out before you did.`
                : `You played the whole line — ${survivedLabel} without a slip. That is as far as ${prep} goes.`}
            </div>
          </>
        )}

        <div className="spacer" />
        <div className="actions">
          {survived && !isExtended(run) && (
            <>
              <button className="btn accent block xl" onClick={onContinueExtended}>
                <Icons.bolt size={18} />
                Continue in extended mode
              </button>
              <div className="note center" style={{ marginTop: -2 }}>
                The prep is done, so the engine takes over the judging. The run continues and your
                score keeps counting while your moves stay sound.
              </div>
            </>
          )}
          <button className="btn block" onClick={() => onPlayOn(shownFen)}>
            <Icons.play size={18} />
            Play from here
          </button>
          <div className="note center" style={{ marginTop: -2 }}>
            Take the position on the board on against the engine. Nothing there counts against
            your record.
          </div>
        </div>

        <Section title="The line" />
        <div className="card">
          <div className="row between">
            <span className="grow">
              <div className="title">{named.name}</div>
              <div className="meta">
                {named.specific ? `${run.sourceLabel} · ` : ''}
                {run.reverse ? 'reversed · ' : ''}
                {survived && past === 0 ? 'played in full' : `${run.survived} correct`}
                {past > 0 ? ` · ${past} past prep` : ''}
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


        <Record record={record} perLine={settings.openingRun.perLine} />

        <div className="spacer" />
        <button className="btn plain block" onClick={onChangeOptions}>
          Change options
        </button>
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

function deathNote(death: Death, run: Run): string {
  if (death.cause === 'offprep') {
    return 'A real move, just not one you had prepared. Add it to your repertoire and it will not stop a run again.';
  }
  if (death.cause === 'blunder') {
    return `Past your prep the engine allows a drop of ${(BLUNDER_LIMIT / 100).toFixed(2)} before calling it a blunder.`;
  }
  if (death.expected.length > 1) {
    const shown = death.expected.slice(0, 6).join(', ');
    return `Any of these would have counted: ${shown}${death.expected.length > 6 ? '…' : ''}`;
  }
  if (death.expected.length === 1) {
    return run.source === 'book'
      ? 'The only move the database has ever seen here.'
      : 'The only move you have prepared here — your repertoire is one move wide at this position.';
  }
  return 'Nothing is prepared here.';
}

/** Where the post-mortem cursor sits, relative to the end of the run. */
function whereYouAre(cursor: number, deathPly: number, survived: boolean): string {
  if (cursor === deathPly) return survived ? 'The end of the line' : 'Where the run ended';
  const distance = Math.abs(cursor - deathPly);
  const moves = `${distance} move${distance === 1 ? '' : 's'}`;
  const anchor = survived ? 'the end' : 'your mistake';
  return cursor < deathPly ? `${moves} before ${anchor}` : `${moves} after ${anchor}`;
}
