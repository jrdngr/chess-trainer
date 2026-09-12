import { useEffect, useState } from 'react';
import { Icons, ToastHost } from './components/ui';
import { AnalysisScreen } from './screens/AnalysisScreen';
import { ExploreScreen } from './screens/ExploreScreen';
import { ImportScreen } from './screens/ImportScreen';
import { RepertoireScreen } from './screens/RepertoireScreen';
import { SettingsSheet } from './screens/SettingsSheet';
import { TrainHome } from './screens/TrainHome';
import { PermadeathScreen } from './screens/permadeath/PermadeathScreen';
import { TrainSession } from './screens/TrainSession';
import type { SessionMode, TrainingItem } from './model/session';
import { countDue } from './model/srs';
import { useStore } from './store/useStore';

type Tab = 'train' | 'repertoire' | 'explore' | 'analysis';

export default function App() {
  const ready = useStore((s) => s.ready);
  const init = useStore((s) => s.init);
  const cards = useStore((s) => s.cards);

  const [tab, setTab] = useState<Tab>('train');
  const [session, setSession] = useState<{
    items: TrainingItem[];
    mode: SessionMode;
    title: string;
  } | null>(null);
  const [permadeath, setPermadeath] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const [explorePath, setExplorePath] = useState<string[] | undefined>();

  useEffect(() => {
    void init();
  }, [init]);

  const startSession = (items: TrainingItem[], mode: SessionMode, title: string) => {
    if (!items.length) return;
    setSession({ items, mode, title });
  };

  const dueCount = countDue(Object.values(cards)).due;

  /** Screens that take over the whole app, with no tab bar underneath. */
  const overlay = !ready ? (
    <div className="screen no-nav" style={{ display: 'grid', placeItems: 'center' }}>
      <div className="spinner" />
    </div>
  ) : permadeath ? (
    <PermadeathScreen onExit={() => setPermadeath(false)} />
  ) : session ? (
    <TrainSession
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
          {tab === 'train' && (
            <TrainHome
              onStart={startSession}
              onStartPermadeath={() => setPermadeath(true)}
              onOpenSettings={() => setSettingsOpen(true)}
            />
          )}
          {tab === 'repertoire' && (
            <RepertoireScreen
              onStart={startSession}
              onImport={() => setImporting(true)}
              onExploreFrom={(sans) => {
                setExplorePath(sans);
                setTab('explore');
              }}
            />
          )}
          {tab === 'explore' && (
            <ExploreScreen
              initialPath={explorePath}
              onConsumedInitial={() => setExplorePath(undefined)}
            />
          )}
          {tab === 'analysis' && <AnalysisScreen />}

          <nav className="nav">
            <NavButton
              label="Home"
              active={tab === 'train'}
              badge={dueCount}
              onClick={() => setTab('train')}
              icon={<Icons.train filled={tab === 'train'} />}
            />
            <NavButton
              label="Repertoire"
              active={tab === 'repertoire'}
              onClick={() => setTab('repertoire')}
              icon={<Icons.tree filled={tab === 'repertoire'} />}
            />
            <NavButton
              label="Explore"
              active={tab === 'explore'}
              onClick={() => setTab('explore')}
              icon={<Icons.book filled={tab === 'explore'} />}
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
