import { useMemo, useState } from 'react';
import { AddLineSheet } from '../components/AddLineSheet';
import { Board } from '../components/Board';
import { AppBar, Empty, IconButton, Icons, Section, Segmented, Sheet, toast } from '../components/ui';

import {
  analyseAgainstRepertoire,
  buildPlayerTree,
  findingToLine,
  measureCoverage,
  type Finding,
} from '../model/gameAnalysis';
import { displayName } from '../model/repertoire';
import { generateSampleArchive } from '../model/seed/sampleGames';
import { importedOnly } from '../model/play';
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

  const imported = importedOnly(state.importedGames);
  const [step, setStep] = useState<Step>(imported.length ? 'games' : 'source');
  const [source, setSource] = useState<SourceId>('lichess');
  const [username, setUsername] = useState(
    state.settings.lichessUsername || state.settings.chesscomUsername || '',
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<{ message: string; blocked: boolean } | null>(null);
  const [pgnOpen, setPgnOpen] = useState(false);
  const [pgnText, setPgnText] = useState('');

  const games = imported;

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
  };

  const loadPgn = () => {
    const name = username.trim() || 'you';
    const parsed = gamesFromPgn(pgnText, name);
    const tagged = parsed.map((g) =>
      g.userColor ? g : { ...g, userColor: guessColor(g, name) },
    );
    if (!tagged.length) {
      toast('No games found');
      return;
    }
    setImportedGames(tagged);
    setPgnOpen(false);
    setStep('games');
    toast(`${tagged.length} games imported`);
  };

  if (step === 'games' && games.length) {
    return <GameReview games={games} onBack={() => setStep('source')} onExit={onBack} />;
  }

  const sourceName = source === 'lichess' ? 'Lichess' : 'Chess.com';

  return (
    <>
      <AppBar title="Import games" onBack={onBack} />

      <div className="screen no-nav">
        <Segmented
          value={source}
          options={[
            { value: 'lichess', label: 'Lichess' },
            { value: 'chesscom', label: 'Chess.com' },
          ]}
          onChange={setSource}
        />

        <div className="spacer sm" />
        <input
          className="field"
          placeholder="Username"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />

        <div className="spacer sm" />
        <button className="btn primary block" disabled={!username.trim() || loading} onClick={run}>
          {loading ? 'Importing…' : 'Import recent games'}
        </button>

        {error && (
          <div className="banner bad" style={{ marginTop: 12 }}>
            <span className="ico"><Icons.warn size={20} /></span>
            <div className="grow">
              {error.blocked ? `Can't reach ${sourceName} from here` : "Couldn't import"}
              <div className="sub">{error.blocked ? 'Paste a PGN or try the sample instead.' : error.message}</div>
            </div>
          </div>
        )}

        <Section title="Or" />
        <div className="list">
          <button className="list-row" onClick={() => setPgnOpen(true)}>
            <span className="grow title">Paste PGN</span>
            <Icons.chevron size={18} />
          </button>
          <button className="list-row" onClick={loadSample}>
            <span className="grow">
              <div className="title">Try sample games</div>
              <div className="meta">60 generated games</div>
            </span>
            <Icons.chevron size={18} />
          </button>
        </div>
      </div>

      <Sheet open={pgnOpen} onClose={() => setPgnOpen(false)} title="Paste PGN">
        <input
          className="field"
          placeholder="Your username in the PGN"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
        <div className="spacer sm" />
        <textarea
          className="field"
          style={{ minHeight: 200 }}
          placeholder="[Event &quot;Rated blitz game&quot;]…"
          value={pgnText}
          onChange={(e) => setPgnText(e.target.value)}
        />
        <div className="spacer sm" />
        <button className="btn primary block" disabled={!pgnText.trim()} onClick={loadPgn}>
          Import
        </button>
      </Sheet>
    </>
  );
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
}: {
  games: ImportedGame[];
  onBack: () => void;
  onExit: () => void;
}) {
  const state = useStore();
  const reps = repertoireList(state);
  const [repId, setRepId] = useState(reps[0]?.id ?? '');
  const rep = state.repertoires[repId] ?? reps[0] ?? null;
  const [kind, setKind] = useState<'gap' | 'deviation' | null>(null);
  const [finding, setFinding] = useState<Finding | null>(null);
  const [addSans, setAddSans] = useState<string[] | null>(null);

  const add = (sans: string[]) => {
    setFinding(null);
    setAddSans(sans);
  };

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
      <AppBar
        title="Your games"
        subtitle={`${games.length} imported`}
        onBack={onExit}
        actions={
          <IconButton label="Import again" onClick={onBack}>
            <Icons.download size={20} />
          </IconButton>
        }
      />

      <div className="screen no-nav">
        <Segmented
          value={rep?.id ?? ''}
          options={reps.map((r) => ({
            value: r.id,
            label: <span className="truncate" style={{ display: 'block' }}>{displayName(r.name)}</span>,
          }))}
          onChange={setRepId}
        />

        <div className="spacer sm" />

        {coverage && (
          <div className="stat-grid">
            <div className="stat">
              <div className="n">{coverage.inPrep}</div>
              <div className="l">In book</div>
            </div>
            <div className="stat">
              <div className="n">{coverage.outOfPrep}</div>
              <div className="l">Off book</div>
            </div>
            <div className="stat">
              <div className="n">{(coverage.averageExitPly / 2).toFixed(1)}</div>
              <div className="l">Exit move</div>
            </div>
          </div>
        )}

        <div className="spacer" />
        <Segmented
          value={activeKind}
          options={[
            { value: 'gap', label: `Gaps · ${gapCount}` },
            { value: 'deviation', label: `Deviations · ${deviationCount}` },
          ]}
          onChange={setKind}
        />
        <div className="spacer sm" />

        {shown.length === 0 && (
          <Empty title={activeKind === 'gap' ? 'No gaps' : 'No deviations'} hint="Import more games to find more" />
        )}

        <div className="stack">
          {shown.slice(0, 25).map((f) => (
            <button key={`${f.kind}-${f.key}`} className="card tap" onClick={() => setFinding(f)}>
              <div className="row between">
                <span className="movetext truncate grow" style={{ lineHeight: 1.4 }}>{f.lineText}</span>
                <span className="chip">{f.games}×</span>
              </div>
              <div className="row wrap" style={{ gap: 6, marginTop: 10 }}>
                {f.played.slice(0, 3).map((p) => (
                  <span key={p.san} className={`chip${f.kind === 'deviation' ? ' bad' : ''}`}>
                    {p.san} ×{p.count}
                  </span>
                ))}
                {f.expected.length > 0 && (
                  <span className="chip good">{f.expected.join(', ')}</span>
                )}
                <span className="tiny faint num" style={{ marginLeft: 'auto' }}>
                  {f.results.wins}W {f.results.draws}D {f.results.losses}L
                </span>
              </div>
            </button>
          ))}
        </div>
      </div>

      <Sheet open={!!finding} onClose={() => setFinding(null)} title={finding?.kind === 'gap' ? 'Gap' : 'Deviation'}>
        {finding && (
          <>
            <div className="movetext" style={{ marginBottom: 10 }}>{finding.lineText}</div>
            <Board
              fen={finding.fen}
              orientation={rep?.color ?? 'w'}
              interactive={false}
              showCoordinates={false}
              theme={state.settings.boardTheme}
            />
            <div className="spacer sm" />
            <div className="list">
              <div className="list-row kv">
                <span className="k">Games</span>
                <span className="v">{finding.games}</span>
              </div>
              <div className="list-row kv">
                <span className="k">Played</span>
                <span className="v">
                  {finding.played.map((p) => `${p.san} ×${p.count}`).join(', ') || '—'}
                </span>
              </div>
              {finding.expected.length > 0 && (
                <div className="list-row kv">
                  <span className="k">Repertoire</span>
                  <span className="v" style={{ color: 'var(--good)' }}>{finding.expected.join(', ')}</span>
                </div>
              )}
              <div className="list-row kv">
                <span className="k">Score</span>
                <span className="v num">
                  {finding.results.wins}W {finding.results.draws}D {finding.results.losses}L
                </span>
              </div>
            </div>
            <div className="spacer" />
            <div className="actions">
              <button className="btn primary block" onClick={() => add(findingToLine(finding))}>
                <Icons.plus size={18} /> Add {finding.played[0]?.san ?? 'line'}
              </button>
              {finding.expected.length > 0 && (
                <button className="btn block" onClick={() => add([...finding.path, finding.expected[0]])}>
                  Drill {finding.expected[0]} instead
                </button>
              )}
            </div>
          </>
        )}
      </Sheet>

      <AddLineSheet
        open={!!addSans}
        onClose={() => setAddSans(null)}
        sans={addSans ?? []}
        source="games"
        title="Add to repertoire"
      />
    </>
  );
}
