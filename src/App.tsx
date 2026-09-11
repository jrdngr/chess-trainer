import { useEffect, useState } from 'react';
import { Icons, ToastHost } from './components/ui';
import { AnalysisScreen } from './screens/AnalysisScreen';
import { ExploreScreen } from './screens/ExploreScreen';
import { ImportScreen } from './screens/ImportScreen';
import { RepertoireScreen } from './screens/RepertoireScreen';
import { SettingsSheet } from './screens/SettingsSheet';
import { TrainHome } from './screens/TrainHome';
import { TrainSession } from './screens/TrainSession';
import type { TrainingItem } from './model/session';
import { countDue } from './model/srs';
import { useStore } from './store/useStore';

type Tab = 'train' | 'repertoire' | 'explore' | 'analysis';

export default function App() {
  const ready = useStore((s) => s.ready);
  const init = useStore((s) => s.init);
  const cards = useStore((s) => s.cards);

  const [tab, setTab] = useState<Tab>('train');
  const [session, setSession] = useState<{ queue: TrainingItem[]; title: string } | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [importing, setImporting] = useState(false);
  const [explorePath, setExplorePath] = useState<string[] | undefined>();

  useEffect(() => {
    void init();
  }, [init]);

  if (!ready) {
    return (
      <div className="app">
        <div className="screen no-nav" style={{ display: 'grid', placeItems: 'center' }}>
          <div className="spinner" />
        </div>
      </div>
    );
  }

  if (session) {
    return (
      <>
        <TrainSession
          queue={session.queue}
          title={session.title}
          onExit={() => setSession(null)}
        />
        <ToastHost />
      </>
    );
  }

  const startSession = (queue: TrainingItem[], title: string) => {
    if (!queue.length) return;
    setSession({ queue, title });
  };

  const dueCount = countDue(Object.values(cards)).due;

  if (importing) {
    return (
      <div className="app">
        <ImportScreen onBack={() => setImporting(false)} />
        <ToastHost />
      </div>
    );
  }

  return (
    <div className="app">
      {tab === 'train' && (
        <TrainHome onStart={startSession} onOpenSettings={() => setSettingsOpen(true)} />
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
          label="Train"
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
