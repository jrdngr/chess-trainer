import { useEffect, useState } from 'react';
import { Icons, ToastHost } from './components/ui';
import { ScoreBar } from './components/ScoreBar';
import { AnalysisScreen } from './screens/AnalysisScreen';
import { StatsScreen } from './screens/StatsScreen';
import { ImportScreen } from './screens/ImportScreen';
import { RepertoireScreen } from './screens/RepertoireScreen';
import { SettingsSheet } from './screens/SettingsSheet';
import { HomeScreen, type ModeId } from './screens/HomeScreen';
import { OnboardingScreen } from './screens/OnboardingScreen';
import { SurvivalScreen } from './screens/survival/SurvivalScreen';
import { RepairScreen } from './screens/repair/RepairScreen';
import { GrowthScreen } from './screens/growth/GrowthScreen';
import { DrillScreen } from './screens/drill/DrillScreen';
import { PlayScreen } from './screens/play/PlayScreen';
import { AutopilotScreen } from './screens/autopilot/AutopilotScreen';
import { DrillSession } from './screens/drill/DrillSession';
import type { SessionMode, TrainingItem } from './model/session';
import type { Selection } from './model/selection';
import { countDue } from './model/srs';
import { needsOnboarding, useStore } from './store/useStore';

type Tab = 'home' | 'repertoire' | 'stats' | 'analysis';

export default function App() {
  const ready = useStore((s) => s.ready);
  const init = useStore((s) => s.init);
  const cards = useStore((s) => s.cards);

  const [tab, setTab] = useState<Tab>('home');
  const [session, setSession] = useState<{
    items: TrainingItem[];
    mode: SessionMode;
    title: string;
  } | null>(null);
  /** The mode open, and for Autopilot, the one opening a session is held to. */
  const [mode, setMode] = useState<{ id: ModeId; scope?: Selection } | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const [explorePath, setExplorePath] = useState<string[] | undefined>();
  const statsTarget = useStore((s) => s.statsTarget);
  const clearStats = useStore((s) => s.clearStats);
  const [statsFor, setStatsFor] = useState<string | undefined>();

  useEffect(() => {
    void init();
  }, [init]);

  /**
   * A stats page asked for from anywhere — the picker, the score bar — opens
   * the Stats tab. Only from a tab screen, though: nothing pulls you out of
   * a game.
   */
  useEffect(() => {
    if (statsTarget === null) return;
    if (!mode && !session && !importing) {
      setStatsFor(statsTarget);
      setTab('stats');
    }
    clearStats();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [statsTarget]);

  const startSession = (items: TrainingItem[], mode: SessionMode, title: string) => {
    if (!items.length) return;
    setSession({ items, mode, title });
  };

  /** Leaving a mode, from anywhere inside it, lands on Home. */
  const leaveMode = () => {
    setMode(null);
    setTab('home');
  };

  const dueCount = countDue(Object.values(cards)).due;
  const onboarding = useStore(needsOnboarding);

  /** Screens that take over the whole app, with no tab bar underneath. */
  const overlay = !ready ? (
    <div className="screen no-nav" style={{ display: 'grid', placeItems: 'center' }}>
      <div className="spinner" />
    </div>
  ) : onboarding ? (
    // Ahead of everything: a profile with nothing in it has nothing to show on
    // any of the tabs until this is answered.
    <OnboardingScreen />
  ) : mode?.id === 'autopilot' ? (
    <AutopilotScreen
      key={mode.scope ? `${mode.scope.color}:${mode.scope.opening}` : 'autopilot'}
      scope={mode.scope}
      onExit={leaveMode}
      onGrow={() => setMode({ id: 'growth' })}
    />
  ) : mode?.id === 'drill' ? (
    <DrillScreen onExit={leaveMode} />
  ) : mode?.id === 'survival' ? (
    <SurvivalScreen onExit={leaveMode} />
  ) : mode?.id === 'repair' ? (
    <RepairScreen
      onImport={() => {
        setMode(null);
        setImporting(true);
      }}
      onExit={leaveMode}
    />
  ) : mode?.id === 'growth' ? (
    <GrowthScreen onExit={leaveMode} onPractice={(scope) => setMode({ id: 'autopilot', scope })} />
  ) : mode?.id === 'play' ? (
    <PlayScreen onExit={leaveMode} />
  ) : session ? (
    <DrillSession
      items={session.items}
      mode={session.mode}
      title={session.title}
      onExit={() => setSession(null)}
    />
  ) : importing ? (
    <ImportScreen onBack={() => setImporting(false)} />
  ) : null;

  return (
    <div className="app">
      {overlay ?? (
        <>
          {tab === 'home' && (
            <HomeScreen
              onStart={startSession}
              onOpenMode={(id) => setMode({ id })}
              onOpenSettings={() => setSettingsOpen(true)}
            />
          )}
          {tab === 'repertoire' && (
            <RepertoireScreen
              onStart={startSession}
              onImport={() => setImporting(true)}
              onExploreFrom={(sans) => {
                setExplorePath(sans);
                setTab('analysis');
              }}
            />
          )}
          {tab === 'stats' && (
            <StatsScreen target={statsFor} onConsumedTarget={() => setStatsFor(undefined)} />
          )}
          {tab === 'analysis' && (
            <AnalysisScreen
              initialPath={explorePath}
              onConsumedInitial={() => setExplorePath(undefined)}
            />
          )}

          <nav className="nav">
            <NavButton
              label="Home"
              active={tab === 'home'}
              badge={dueCount}
              onClick={() => setTab('home')}
              icon={<Icons.home filled={tab === 'home'} />}
            />
            <NavButton
              label="Repertoire"
              active={tab === 'repertoire'}
              onClick={() => setTab('repertoire')}
              icon={<Icons.tree filled={tab === 'repertoire'} />}
            />
            <NavButton
              label="Stats"
              active={tab === 'stats'}
              onClick={() => setTab('stats')}
              icon={<Icons.chart filled={tab === 'stats'} />}
            />
            <NavButton
              label="Analysis"
              active={tab === 'analysis'}
              onClick={() => setTab('analysis')}
              icon={<Icons.chart filled={tab === 'analysis'} />}
            />
          </nav>

          <SettingsSheet open={settingsOpen} onClose={() => setSettingsOpen(false)} />
        </>
      )}
      <ScoreBar />
      <ToastHost />
    </div>
  );
}

function NavButton({
  label,
  icon,
  active,
  badge,
  onClick,
}: {
  label: string;
  icon: React.ReactNode;
  active: boolean;
  badge?: number;
  onClick: () => void;
}) {
  return (
    <button className={active ? 'active' : ''} onClick={onClick}>
      {icon}
      {badge ? <span className="badge">{badge > 99 ? '99+' : badge}</span> : null}
      <span>{label}</span>
    </button>
  );
}
