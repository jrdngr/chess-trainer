import { useEffect, useState } from 'react';
import { Section, Segmented, Sheet, toast, Toggle } from '../components/ui';
import { describeStatus } from '../store/cloud';
import { useStore } from '../store/useStore';
import type { Settings } from '../model/types';

const THEMES = (['slate', 'walnut', 'ocean'] as const).map((value) => ({
  value,
  label: value[0].toUpperCase() + value.slice(1),
}));

export function SettingsSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const settings = useStore((s) => s.settings);
  const setSettings = useStore((s) => s.setSettings);
  const resetProgress = useStore((s) => s.resetProgress);
  const resetAll = useStore((s) => s.resetAll);
  /**
   * Which reset is waiting to be confirmed, if either. One at a time, so
   * arming one disarms the other and a tap is never confirming the row above
   * the one it looks like it is on.
   */
  const [armed, setArmed] = useState<'progress' | 'all' | null>(null);

  // Closing the sheet is the plainest way to say no. Nothing stays armed for
  // a tap the next time it is opened.
  useEffect(() => {
    if (!open) setArmed(null);
  }, [open]);

  const toggle = (key: keyof Settings) => () =>
    setSettings({ [key]: !settings[key] } as Partial<Settings>);

  return (
    <Sheet open={open} onClose={onClose} title="Settings">
      <div className="section" style={{ marginTop: 0 }}>Board</div>
      <div className="list">
        <div className="list-row" style={{ display: 'block' }}>
          <Segmented
            value={settings.boardTheme}
            options={THEMES}
            onChange={(boardTheme) => setSettings({ boardTheme })}
          />
        </div>
        <Toggle label="Coordinates" on={settings.showCoordinates} onToggle={toggle('showCoordinates')} />
        <Toggle label="Haptics" on={settings.hapticFeedback} onToggle={toggle('hapticFeedback')} />
      </div>

      <Section title="Engine" />
      <div className="list">
        <Toggle
          label="Run Stockfish"
          hint="Used by Analysis and by Drill's explanations, with a built-in evaluator as fallback"
          on={settings.engineEnabled}
          onToggle={toggle('engineEnabled')}
        />
      </div>
      <div className="note">
        How each mode plays is set on that mode's own screen.
      </div>

      <Section title="Sync" />
      <SyncRows />

      <Section title="Data" />
      <div className="list">
        <button
          className="list-row"
          onClick={() => {
            if (armed !== 'progress') {
              setArmed('progress');
              return;
            }
            resetProgress();
            setArmed(null);
            toast('Progress reset');
          }}
        >
          <span className="grow title">
            {armed === 'progress' ? 'Tap again to confirm' : 'Reset progress'}
          </span>
        </button>
        <button
          className="list-row"
          style={{ color: 'var(--bad)' }}
          onClick={async () => {
            if (armed !== 'all') {
              setArmed('all');
              return;
            }
            await resetAll();
            setArmed(null);
            onClose();
            toast('Reset');
          }}
        >
          <span className="grow title">{armed === 'all' ? 'Tap again to confirm' : 'Reset everything'}</span>
        </button>
      </div>
      <div className="spacer" />
    </Sheet>
  );
}

function SyncRows() {
  const cloud = useStore((s) => s.cloud);
  const storage = useStore((s) => s.storage);
  const enabled = useStore((s) => s.settings.cloudSync);
  const setSettings = useStore((s) => s.setSettings);
  const syncNow = useStore((s) => s.syncNow);
  const [busy, setBusy] = useState(false);
  const unavailable = cloud.kind === 'unavailable';
  const syncing = busy || cloud.kind === 'syncing';

  const status = !enabled
    ? storage.any
      ? 'Saved on this device'
      : 'Off · nothing is saved'
    : unavailable
      ? 'Not available here'
      : describeStatus(cloud);

  const sync = async () => {
    setBusy(true);
    await syncNow();
    setBusy(false);
  };

  return (
    <div className="list">
      <Toggle
        label="Sync across devices"
        hint={status}
        on={enabled}
        onToggle={async () => {
          setSettings({ cloudSync: !enabled });
          if (!enabled) await sync();
        }}
      />
      {enabled && !unavailable && (
        <button
          className="list-row"
          disabled={syncing}
          onClick={async () => {
            await sync();
            toast('Synced');
          }}
        >
          <span className="grow title" style={{ color: 'var(--accent)' }}>
            {syncing ? 'Syncing…' : 'Sync now'}
          </span>
        </button>
      )}
    </div>
  );
}
