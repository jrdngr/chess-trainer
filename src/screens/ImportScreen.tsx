import { useMemo, useState } from 'react';
import { AddLineSheet } from '../components/AddLineSheet';
import { Board } from '../components/Board';
import { Empty, Icons, Sheet, toast } from '../components/ui';

import {
  analyseAgainstRepertoire,
  buildPlayerTree,
  findingToLine,
  measureCoverage,
  type Finding,
} from '../model/gameAnalysis';
import { generateSampleArchive } from '../model/seed/sampleGames';
import type { ImportedGame } from '../model/types';
import { fetchGames, gamesFromPgn, type SourceId } from '../services/gameSources';
import { repertoireList, useStore } from '../store/useStore';

export interface ImportScreenProps {
  onBack: () => void;
}

type Step = 'source' | 'games';

export function ImportScreen({ onBack }: ImportScreenProps) {
  const state = useStore();
  const setSettings = useStore((s) => s.setSettings);
  const setImportedGames = useStore((s) => s.setImportedGames);

  const [step, setStep] = useState<Step>(state.importedGames.length ? 'games' : 'source');
  const [source, setSource] = useState<SourceId>('lichess');
  const [username, setUsername] = useState(
    state.settings.lichessUsername || state.settings.chesscomUsername || '',
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<{ message: string; blocked: boolean } | null>(null);
  const [pgnOpen, setPgnOpen] = useState(false);
  const [pgnText, setPgnText] = useState('');
  const [finding, setFinding] = useState<Finding | null>(null);
  const [addSans, setAddSans] = useState<string[] | null>(null);

  const games = state.importedGames;

  const run = async () => {
    const name = username.trim();
    if (!name) return;
    setLoading(true);
    setError(null);
    const result = await fetchGames(source, { username: name, max: 120 });
    setLoading(false);
    if (!result.ok) {
      setError({ message: result.message, blocked: result.reason === 'blocked' });
      return;
    }
    setImportedGames(result.games);
    setSettings(
      source === 'lichess' ? { lichessUsername: name } : { chesscomUsername: name },
    );
    setStep('games');
    toast(`${result.games.length} games imported`);
  };

  const loadSample = () => {
    const name = username.trim() || 'you';
    const sample = generateSampleArchive({ username: name, count: 60, source });
    setImportedGames(sample);
    setStep('games');
    toast('Loaded the bundled sample archive');
  };

  const loadPgn = () => {
    const name = username.trim() || 'you';
    const parsed = gamesFromPgn(pgnText, name);
    const tagged = parsed.map((g) =>
      g.userColor ? g : { ...g, userColor: guessColor(g, name) },
    );
    if (!tagged.length) {
      toast('No games found in that PGN');
      return;
    }
    setImportedGames(tagged);
    setPgnOpen(false);
    setStep('games');
    toast(`${tagged.length} games read from PGN`);
  };

  if (step === 'games' && games.length) {
    return (
      <GameReview
        games={games}
        onBack={() => setStep('source')}
        onExit={onBack}
        onOpenFinding={setFinding}
        finding={finding}
        onCloseFinding={() => setFinding(null)}
        onAdd={(sans) => {
          setFinding(null);
          setAddSans(sans);
        }}
        addSans={addSans}
        onCloseAdd={() => setAddSans(null)}
      />
    );
  }

  return (
    <>
      <div className="appbar">
        <button className="btn plain sm" onClick={onBack}>
          <Icons.back size={20} />
        </button>
        <div className="appbar-title">
          <h1 style={{ fontSize: 18 }}>Import games</h1>
        </div>
      </div>

      <div className="screen">
        <div className="banner">
          <span className="ico">↯</span>
          <span>
            Pull your recent games and compare them against your repertoire: where you left prep,
            what you reach often with nothing prepared, and which lines never come up.
          </span>
        </div>

        <div className="spacer" />
        <div className="segmented">
          <button className={source === 'lichess' ? 'active' : ''} onClick={() => setSource('lichess')}>
            Lichess
          </button>
          <button className={source === 'chesscom' ? 'active' : ''} onClick={() => setSource('chesscom')}>
            Chess.com
          </button>
        </div>

        <div className="spacer" />
        <input
          className="field"
          placeholder={source === 'lichess' ? 'Lichess username' : 'Chess.com username'}
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />

        <div className="spacer" />
        <button className="btn primary block" disabled={!username.trim() || loading} onClick={run}>
          {loading ? 'Fetching…' : `Fetch last 120 games`}
        </button>

        {error && (
          <div className="banner warn" style={{ marginTop: 12 }}>
            <span className="ico">⚠</span>
            <div>
              <div style={{ fontWeight: 650, color: 'var(--text)', marginBottom: 4 }}>
                {error.blocked ? 'Blocked by the sandbox' : "Couldn't fetch"}
              </div>
              {error.message}
              {error.blocked && (
                <div style={{ marginTop: 8 }}>
                  Use the sample archive below to try the flow, or paste a PGN exported from your
                  account. Running the app locally makes the live fetch work.
                </div>
              )}
            </div>
          </div>
        )}

        <div className="section-title">Other ways in</div>
        <div className="stack">
          <button className="btn ghost block" onClick={() => setPgnOpen(true)}>
            <Icons.note size={18} /> Paste a PGN export
          </button>
          <button className="btn ghost block" onClick={loadSample}>
            <Icons.bolt size={18} /> Load the bundled sample archive
          </button>
        </div>
        <div className="tiny faint" style={{ marginTop: 10 }}>
          The sample archive is 60 generated games, not real ones. It exists so the analysis flow
          has something to chew on when the network is unavailable.
        </div>
      </div>

      <Sheet open={pgnOpen} onClose={() => setPgnOpen(false)} title="Paste PGN">
        <div className="tiny faint" style={{ marginBottom: 8 }}>
          Any number of games. Your username is used to work out which side you had.
        </div>
        <input
          className="field"
          placeholder="Your username as it appears in the PGN"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
        <div className="spacer" />
        <textarea
          className="field"
          style={{ minHeight: 200 }}
          placeholder="[Event &quot;Rated blitz game&quot;]…"
          value={pgnText}
          onChange={(e) => setPgnText(e.target.value)}
        />
        <div className="spacer" />
        <button className="btn primary block" disabled={!pgnText.trim()} onClick={loadPgn}>
          Read games
        </button>
      </Sheet>
    </>
  );
}

/** "Black vs 1.e4 — Najdorf" -> "Najdorf", so tabs stay readable on a phone. */
function shortName(name: string) {
  const tail = name.split('—').pop()?.trim();
  return tail && tail.length <= 14 ? tail : name.slice(0, 12);
}

function guessColor(game: ImportedGame, username: string) {
  const u = username.toLowerCase();
  if (game.white.toLowerCase().includes(u)) return 'w' as const;
  if (game.black.toLowerCase().includes(u)) return 'b' as const;
  return null;
}

/* ── review ────────────────────────────────────────────────────────────── */

function GameReview({
  games,
  onBack,
  onExit,
  onOpenFinding,
  finding,
  onCloseFinding,
  onAdd,
  addSans,
  onCloseAdd,
}: {
  games: ImportedGame[];
  onBack: () => void;
  onExit: () => void;
  onOpenFinding: (f: Finding) => void;
  finding: Finding | null;
  onCloseFinding: () => void;
  onAdd: (sans: string[]) => void;
  addSans: string[] | null;
  onCloseAdd: () => void;
}) {
  const state = useStore();
  const reps = repertoireList(state);
  const [repId, setRepId] = useState(reps[0]?.id ?? '');
  const rep = state.repertoires[repId] ?? reps[0] ?? null;
  const [kind, setKind] = useState<'gap' | 'deviation' | null>(null);

  const tree = useMemo(
    () => (rep ? buildPlayerTree(games, rep.color) : null),
    [games, rep],
  );
  const findings = useMemo(
    () => (tree ? analyseAgainstRepertoire(tree, rep, { minGames: 2 }) : []),
    [tree, rep],
  );
  const coverage = useMemo(() => (rep ? measureCoverage(games, rep) : null), [games, rep]);

  const gapCount = findings.filter((f) => f.kind === 'gap').length;
  const deviationCount = findings.filter((f) => f.kind === 'deviation').length;
  // Open on whichever tab actually has something to look at.
  const activeKind = kind ?? (gapCount === 0 && deviationCount > 0 ? 'deviation' : 'gap');
  const shown = findings.filter((f) => f.kind === activeKind);

  return (
    <>
      <div className="appbar">
        <button className="btn plain sm" onClick={onExit}>
          <Icons.back size={20} />
        </button>
        <div className="appbar-title">
          <div className="line" style={{ fontWeight: 650, fontSize: 16 }}>Your games</div>
          <div className="sub">{games.length} imported</div>
        </div>
        <button className="btn plain sm" onClick={onBack} aria-label="Import again">
          <Icons.download size={19} />
        </button>
      </div>

      <div className="screen">
        <div className="segmented">
          {reps.map((r) => (
            <button key={r.id} className={r.id === rep?.id ? 'active' : ''} onClick={() => setRepId(r.id)}>
              {shortName(r.name)}
            </button>
          ))}
        </div>

        <div className="spacer" />

        {coverage && (
          <div className="card">
            <div className="row between small">
              <span className="muted">{rep?.name}</span>
              <span className="muted">{coverage.games} of your games</span>
            </div>
            <div className="stat-grid" style={{ marginTop: 11 }}>
              <div className="stat">
                <div className="n">{coverage.inPrep}</div>
                <div className="l">In prep</div>
              </div>
              <div className="stat">
                <div className="n">{coverage.outOfPrep}</div>
                <div className="l">Off book</div>
              </div>
              <div className="stat">
                <div className="n">{coverage.averageExitPly.toFixed(1)}</div>
                <div className="l">Avg ply</div>
              </div>
            </div>
            <div className="tiny faint" style={{ marginTop: 10 }}>
              On average your games leave the repertoire after {(coverage.averageExitPly / 2).toFixed(1)}{' '}
              moves.
            </div>
          </div>
        )}

        <div className="spacer" />
        <div className="segmented">
          <button className={activeKind === 'gap' ? 'active' : ''} onClick={() => setKind('gap')}>
            Gaps ({gapCount})
          </button>
          <button className={activeKind === 'deviation' ? 'active' : ''} onClick={() => setKind('deviation')}>
            Deviations ({deviationCount})
          </button>
        </div>

        <div className="spacer" />
        <div className="tiny faint" style={{ marginBottom: 10 }}>
          {activeKind === 'gap'
            ? 'Positions you reach with nothing prepared, most frequent first.'
            : 'Positions where you played something other than your repertoire move.'}
        </div>

        {shown.length === 0 && (
          <Empty
            icon="✓"
            title={activeKind === 'gap' ? 'No frequent gaps' : 'You stuck to your prep'}
            hint="Import more games to find thinner spots."
          />
        )}

        <div className="stack">
          {shown.slice(0, 25).map((f) => (
            <button
              key={`${f.kind}-${f.key}`}
              className="card"
              style={{ width: '100%', textAlign: 'left' }}
              onClick={() => onOpenFinding(f)}
            >
              <div className="row between">
                <span className="small mono truncate grow">{f.lineText}</span>
                <span className="chip">{f.games}×</span>
              </div>
              <div className="row wrap" style={{ gap: 6, marginTop: 9 }}>
                {f.played.slice(0, 3).map((p) => (
                  <span key={p.san} className="chip">
                    {p.san} ×{p.count}
                  </span>
                ))}
                {f.expected.length > 0 && (
                  <span className="chip" style={{ color: 'var(--accent)' }}>
                    prep: {f.expected.join(', ')}
                  </span>
                )}
              </div>
              <div className="tiny faint" style={{ marginTop: 8 }}>
                {f.results.wins}W {f.results.draws}D {f.results.losses}L from here
              </div>
            </button>
          ))}
        </div>
      </div>

      <Sheet
        open={!!finding}
        onClose={onCloseFinding}
        title={finding?.kind === 'gap' ? 'Nothing prepared here' : 'You left your prep'}
      >
        {finding && (
          <>
            <div className="tiny faint" style={{ marginBottom: 10 }}>{finding.lineText}</div>
            <Board
              fen={finding.fen}
              orientation={rep?.color ?? 'w'}
              interactive={false}
              showCoordinates={false}
              theme={state.settings.boardTheme}
            />
            <div className="spacer" />
            <div className="card">
              <div className="row between small">
                <span className="muted">Reached in</span>
                <span style={{ fontWeight: 650 }}>{finding.games} games</span>
              </div>
              <div className="divider" />
              <div className="row between small">
                <span className="muted">You played</span>
                <span style={{ fontWeight: 650 }}>
                  {finding.played.map((p) => `${p.san} ×${p.count}`).join(', ') || '—'}
                </span>
              </div>
              {finding.expected.length > 0 && (
                <>
                  <div className="divider" />
                  <div className="row between small">
                    <span className="muted">Your repertoire</span>
                    <span style={{ fontWeight: 650, color: 'var(--accent)' }}>
                      {finding.expected.join(', ')}
                    </span>
                  </div>
                </>
              )}
              <div className="divider" />
              <div className="row between small">
                <span className="muted">Score from here</span>
                <span style={{ fontWeight: 650 }}>
                  {finding.results.wins}W {finding.results.draws}D {finding.results.losses}L
                </span>
              </div>
            </div>
            <div className="spacer" />
            <button className="btn primary block" onClick={() => onAdd(findingToLine(finding))}>
              Add {finding.played[0]?.san ?? 'this line'} to repertoire
            </button>
            {finding.expected.length > 0 && (
              <button
                className="btn ghost block"
                style={{ marginTop: 8 }}
                onClick={() => onAdd([...finding.path, finding.expected[0]])}
              >
                Drill the prepared move instead
              </button>
            )}
          </>
        )}
      </Sheet>

      <AddLineSheet
        open={!!addSans}
        onClose={onCloseAdd}
        sans={addSans ?? []}
        source="games"
        title="Add from your games"
      />
    </>
  );
}

