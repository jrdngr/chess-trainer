import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Board } from '../../components/Board';
import { AppBar, haptic, Icons, Section, Strip, toast, type StripItem } from '../../components/ui';
import {
  applySan,
  applyUci,
  fenTurn,
  fullmoveNumber,
  positionStatus,
  sansToMoveText,
  START_FEN,
  type Color,
  type LegalMove,
} from '../../chess/core';
import { getEngine } from '../../engine/useEngine';
import { formatScore, winFraction, type EngineSnapshot } from '../../engine/types';
import { chooseMove, levelById, openingLine, playedGame, type GameResult } from '../../model/play';
import type { PlayPrefs } from '../../model/modes';
import { specificNameForColor } from '../../model/reference';
import { referenceIndex } from '../../model/referenceIndex';
import { lineStatus, nodeById, openingTree } from '../../model/openingTree';
import { selectionText } from '../../components/Selection';
import { childrenOf, displayName, fenAt } from '../../model/repertoire';
import { positionKey } from '../../chess/core';
import type { Repertoire } from '../../model/types';
import { repertoireList, useStore } from '../../store/useStore';
import { Setup } from './Setup';

export interface PlayScreenProps {
  onExit: () => void;
}

export function PlayScreen({ onExit }: PlayScreenProps) {
  const [prefs, setPrefs] = useState<PlayPrefs | null>(null);
  if (!prefs) return <Setup onStart={setPrefs} onExit={onExit} />;
  return <Game prefs={prefs} onExit={() => setPrefs(null)} />;
}

/** What the repertoire prepares at a position, by key, for the off-book warning. */
function prepIndex(rep: Repertoire | null): Map<string, string[]> {
  const out = new Map<string, string[]>();
  if (!rep) return out;
  const walk = (nodeId: string | null) => {
    const fen = fenAt(rep, nodeId);
    const kids = childrenOf(rep, nodeId);
    if (kids.length && fenTurn(fen) === rep.color) {
      const key = positionKey(fen);
      const existing = out.get(key) ?? [];
      for (const kid of kids) if (!existing.includes(kid.san)) existing.push(kid.san);
      out.set(key, existing);
    }
    for (const kid of kids) walk(kid.id);
  };
  walk(null);
  return out;
}

function Game({ prefs, onExit }: { prefs: PlayPrefs; onExit: () => void }) {
  const state = useStore();
  const settings = state.settings;
  const addLine = useStore((s) => s.addLine);
  const ensureRepertoire = useStore((s) => s.ensureRepertoire);
  const logMistake = useStore((s) => s.logMistake);
  const recordPlayGame = useStore((s) => s.recordPlayGame);
  const reps = repertoireList(state);
  const index = referenceIndex();
  const level = levelById(prefs.level);
  const selection = settings.selection;
  const tree = openingTree(index);
  const region = nodeById(tree, selection.opening);

  /** Fixed for the life of the game, so a random draw does not re-roll. */
  const [color] = useState<Color>(() =>
    selection.color === 'random' ? (Math.random() < 0.5 ? 'w' : 'b') : selection.color,
  );
  const [moves, setMoves] = useState<string[]>([]);
  const [fen, setFen] = useState(START_FEN);
  const [thinking, setThinking] = useState(false);
  const [eval_, setEval] = useState<EngineSnapshot['lines'][number] | null>(null);
  const [over, setOver] = useState<{ result: GameResult; reason: string } | null>(null);
  const [saved, setSaved] = useState(false);
  const [offBook, setOffBook] = useState<string | null>(null);
  const rand = useRef(Math.random);
  /** One id for the life of the game, so ending it twice records it once. */
  const gameId = useRef(`play_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`);

  /** The repertoire this game is measured against and saved into. */
  const target = useMemo(() => reps.find((rep) => rep.color === color) ?? null, [reps, color]);
  const prep = useMemo(() => prepIndex(target), [target]);

  const status = useMemo(() => positionStatus(fen), [fen]);
  const myTurn = fenTurn(fen) === color && !over;

  /** Settle the game when the position is terminal. */
  useEffect(() => {
    if (over || !status.gameOver) return;
    if (status.checkmate) {
      const loserIsMe = fenTurn(fen) === color;
      setOver({ result: loserIsMe ? 'loss' : 'win', reason: 'checkmate' });
    } else {
      setOver({ result: 'draw', reason: status.stalemate ? 'stalemate' : 'the rules' });
    }
  }, [status, fen, color, over]);

  /**
   * A finished game is a game: kept with the imports, so Repair, coverage and
   * Autopilot read what you actually play. Nothing is written to the
   * repertoire by this — saving the opening is the button below, and your
   * choice.
   */
  useEffect(() => {
    if (!over) return;
    const game = playedGame({ id: gameId.current, color, moves, result: over.result, level, at: Date.now() });
    if (game) recordPlayGame(game);
  }, [over, color, moves, level, recordPlayGame]);

  /**
   * The engine's turn.
   *
   * While the game is still on the selected opening's move order the engine
   * plays that move order, so a game in the Najdorf is a Najdorf: it walks
   * you in the same way Run does. Past it, or once you have stepped off it,
   * it searches and picks a move for this level.
   */
  useEffect(() => {
    if (over || fenTurn(fen) === color || status.gameOver) return;
    const scripted =
      region.depth > 0 &&
      moves.length < region.sans.length &&
      moves.every((san, i) => region.sans[i] === san) &&
      lineStatus(tree, region, moves) === 'onWay'
        ? applySan(fen, region.sans[moves.length])
        : null;
    if (scripted) {
      setThinking(true);
      const timer = setTimeout(() => {
        setMoves((m) => [...m, scripted.san]);
        setFen(scripted.after);
        setThinking(false);
      }, 420);
      return () => {
        clearTimeout(timer);
        setThinking(false);
      };
    }
    let cancelled = false;
    setThinking(true);
    const { engine, backend } = getEngine();
    void backend.then(() => {
      if (cancelled) return;
      let best: EngineSnapshot | null = null;
      engine.analyse(fen, { depth: level.depth, multiPv: level.multiPv }, (snap) => {
        if (cancelled) return;
        best = snap;
        if (snap.thinking) return;
        const uci = chooseMove(snap.lines, level, rand.current);
        const move = uci ? applyUci(fen, uci) : null;
        if (!move) {
          // Nothing usable came back; fall back to something legal rather than
          // leaving the game stuck on the engine's turn forever.
          const legal = applySan(fen, '') ?? null;
          if (!legal) setThinking(false);
          return;
        }
        setMoves((m) => [...m, move.san]);
        setFen(move.after);
        setThinking(false);
      });
      // A depth-limited search on the heuristic backend can finish instantly;
      // this only matters when it does not report a final snapshot.
      void best;
    });
    return () => {
      cancelled = true;
      engine.stop();
      setThinking(false);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fen, color, level, over, status.gameOver, region, moves.length]);

  /** A quiet evaluation for the bar, only when asked for. */
  useEffect(() => {
    if (!prefs.showEval || !settings.engineEnabled || over) return;
    if (fenTurn(fen) !== color) return;
    let cancelled = false;
    const { engine, backend } = getEngine();
    void backend.then(() => {
      if (cancelled) return;
      engine.analyse(fen, { depth: 10, multiPv: 1 }, (snap) => {
        if (!cancelled && snap.lines[0]) setEval(snap.lines[0]);
      });
    });
    return () => {
      cancelled = true;
    };
  }, [fen, prefs.showEval, settings.engineEnabled, color, over]);

  const onMove = useCallback(
    (move: LegalMove) => {
      if (!myTurn) return;
      // Leaving your own prep is worth knowing about at the moment it happens,
      // and worth asking about again later.
      const known = prep.get(positionKey(fen));
      if (prefs.warnOffBook && known?.length && !known.includes(move.san) && target) {
        setOffBook(`${move.san} — your prep says ${known.join(' or ')}`);
        logMistake({
          source: 'play',
          repertoireId: target.id,
          key: positionKey(fen),
          fen,
          path: [...moves],
          played: move.san,
          expected: known[0],
        });
      } else {
        setOffBook(null);
      }
      setMoves((m) => [...m, move.san]);
      setFen(move.after);
      if (settings.hapticFeedback) haptic(10);
    },
    [myTurn, prep, fen, prefs.warnOffBook, target, moves, logMistake, settings.hapticFeedback],
  );

  const takeBack = () => {
    if (moves.length < 2) return;
    const trimmed = moves.slice(0, fenTurn(fen) === color ? -2 : -1);
    setMoves(trimmed);
    setFen(replay(trimmed));
    setOver(null);
    setOffBook(null);
  };

  /**
   * Write the opening into the repertoire for the side you played.
   *
   * The opening it becomes is derived from the moves, so nothing here has to
   * name anything: the toast says which opening it landed in, taking the name
   * from the side you played, since "Queen's Pawn Opening" would describe what
   * a Black game's opponent did.
   */
  const save = () => {
    const line = openingLine(moves, color);
    if (!line.length) {
      toast('Too short to save');
      return;
    }
    const repId = ensureRepertoire(color);
    const { added } = addLine(repId, line, 'games');
    setSaved(true);
    const named = specificNameForColor(index, line, color)?.name;
    if (added === 0) toast('Already in your repertoire');
    else toast(named ? `${added} moves saved to ${named}` : `${added} moves saved`);
  };

  const strip: StripItem[] = moves.map((san, i) => ({
    san,
    label: i % 2 === 0 ? `${Math.floor(i / 2) + 1}.` : undefined,
    tone: (i % 2 === 0) === (color === 'w') ? 'mine' : 'theirs',
    current: i === moves.length - 1,
  }));

  const last = moves.length ? lastSquares(moves) : null;

  return (
    <>
      <AppBar
        title="Play"
        subtitle={`${level.name} · ${selectionText(color, selection.opening)}`}
        onClose={onExit}
        actions={
          <span className="num muted small appbar-gap" style={{ textAlign: 'right' }}>
            {fullmoveNumber(fen)}
          </span>
        }
      />

      <div className="screen no-nav">
        {prefs.showEval && settings.engineEnabled && (
          <div className="row gap-8" style={{ marginBottom: 10 }}>
            <div className="evalbar grow">
              <i style={{ width: `${winFraction(eval_ ?? undefined) * 100}%` }} />
            </div>
            <span className="num small muted" style={{ minWidth: 48, textAlign: 'right' }}>
              {eval_ ? formatScore(eval_) : '—'}
            </span>
          </div>
        )}

        <Board
          fen={fen}
          orientation={color}
          interactive={myTurn}
          movableFor={color}
          onMove={onMove}
          lastMove={last}
          showCoordinates={settings.showCoordinates}
          theme={settings.boardTheme}
          dimmed={!!over}
          captured
        />

        <div className="spacer" />

        {over ? (
          <>
            <div className="row between">
              <div
                className={`verdict ${over.result === 'win' ? 'ok' : over.result === 'loss' ? 'no' : 'warn'}`}
                style={{ padding: 0 }}
              >
                <span className="ico">
                  {over.result === 'win' ? <Icons.check size={16} /> : <Icons.cross size={14} />}
                </span>
                {over.result === 'win'
                  ? `Won by ${over.reason}`
                  : over.result === 'loss'
                    ? `Lost by ${over.reason}`
                    : `Drawn by ${over.reason}`}
              </div>
              <button className="btn primary sm" onClick={onExit}>
                New game
                <Icons.next size={16} />
              </button>
            </div>
            {!saved && openingLine(moves, color).length > 0 && (
              <button className="btn block mt-12" onClick={save}>
                <Icons.plus size={18} />
                Save this opening
              </button>
            )}
          </>
        ) : (
          <div className="prompt">
            <div className="who">
              <span className={`side ${fenTurn(fen)}`} />
              {thinking ? 'Thinking…' : myTurn ? 'Your move' : 'Their move'}
            </div>
            {status.check && <div className="ctx">Check</div>}
          </div>
        )}

        {offBook && !over && (
          <div className="banner" style={{ marginTop: 12 }}>
            <span className="ico"><Icons.warn size={20} /></span>
            <div className="grow">
              Out of your prep
              <div className="sub">{offBook}</div>
            </div>
          </div>
        )}

        {moves.length > 0 && (
          <>
            <Section title="Moves" aside={target ? displayName(target.name) : undefined} />
            <Strip items={strip} />
          </>
        )}

        {!over && (
          <div className="row gap-8 mt-12">
            {prefs.takeBacks && (
              <button className="btn soft grow" disabled={moves.length < 2} onClick={takeBack}>
                Take back
              </button>
            )}
            <button
              className="btn soft grow"
              onClick={() => setOver({ result: 'loss', reason: 'resignation' })}
            >
              Resign
            </button>
          </div>
        )}

        {over && moves.length > 0 && (
          <>
            <Section title="The game" />
            <div className="card">
              <div className="movetext">{sansToMoveText(moves)}</div>
            </div>
          </>
        )}
      </div>
    </>
  );
}

/** FEN after a list of SAN moves from the start. */
function replay(sans: string[]): string {
  let fen = START_FEN;
  for (const san of sans) {
    const move = applySan(fen, san);
    if (!move) break;
    fen = move.after;
  }
  return fen;
}

/** The squares of the last move played, for the board highlight. */
function lastSquares(sans: string[]) {
  let fen = START_FEN;
  let move = null;
  for (const san of sans) {
    const next = applySan(fen, san);
    if (!next) break;
    move = next;
    fen = next.after;
  }
  return move ? { from: move.from, to: move.to } : null;
}
