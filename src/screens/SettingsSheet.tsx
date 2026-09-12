import { useState } from 'react';
import { Section, Segmented, Sheet, Stepper, toast, Toggle } from '../components/ui';
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
  const [confirmReset, setConfirmReset] = useState(false);

  const toggle = (key: keyof Settings) => () =>
    setSettings({ [key]: !settings[key] } as Partial<Settings>);

  return (
    <Sheet open={open} onClose={onClose} title="Settings">
      <div className="section" style={{ marginTop: 0 }}>Training</div>
      <div className="list">
        <Toggle
          label="Follow the line"
          hint="Keep going after a correct move"
          on={settings.playOpponentReplies}
          onToggle={toggle('playOpponentReplies')}
        />
        <Stepper
          label="New per session"
          value={settings.newCardsPerSession}
          min={0}
          max={40}
          step={2}
          onChange={(newCardsPerSession) => setSettings({ newCardsPerSession })}
        />
        <Stepper
          label="Session length"
          value={settings.maxSessionLength}
          min={5}
          max={80}
          step={5}
          onChange={(maxSessionLength) => setSettings({ maxSessionLength })}
        />
      </div>

      <Section title="Board" />
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
        <Toggle
          label="Engine in Analysis"
          hint="Stockfish, with a built-in evaluator as fallback"
          on={settings.engineEnabled}
          onToggle={toggle('engineEnabled')}
        />
      </div>

      <Section title="Sync" />
      <SyncRows />

      <Section title="Data" />
      <div className="list">
        <button
          className="list-row"
          onClick={() => {
            resetProgress();
            toast('Progress reset');
          }}
        >
          <span className="grow title">Reset progress</span>
        </button>
        <button
          className="list-row"
          style={{ color: 'var(--bad)' }}
          onClick={async () => {
            if (!confirmReset) {
              setConfirmReset(true);
              return;
            }
            await resetAll();
            setConfirmReset(false);
            onClose();
            toast('Reset');
          }}
        >
          <span className="grow title">{confirmReset ? 'Tap again to confirm' : 'Reset everything'}</span>
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
