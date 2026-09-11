import { useState } from 'react';
import { Sheet, toast } from '../components/ui';
import { describeStatus } from '../store/cloud';
import { useStore } from '../store/useStore';
import type { Settings } from '../model/types';

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
        <Toggle
          label="Engine eval while training"
          on={settings.showEvalInTraining}
          onToggle={toggle('showEvalInTraining')}
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

      <div className="section">Board</div>
      <div className="list">
        <div className="list-row" style={{ display: 'block' }}>
          <div className="segmented">
            {(['slate', 'walnut', 'ocean'] as const).map((theme) => (
              <button
                key={theme}
                className={settings.boardTheme === theme ? 'active' : ''}
                onClick={() => setSettings({ boardTheme: theme })}
                style={{ textTransform: 'capitalize' }}
              >
                {theme}
              </button>
            ))}
          </div>
        </div>
        <Toggle label="Coordinates" on={settings.showCoordinates} onToggle={toggle('showCoordinates')} />
        <Toggle label="Haptics" on={settings.hapticFeedback} onToggle={toggle('hapticFeedback')} />
        <Toggle label="Stockfish" on={settings.engineEnabled} onToggle={toggle('engineEnabled')} />
      </div>

      <div className="section">Sync</div>
      <SyncRows />

      <div className="section">Data</div>
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

  const status = !enabled
    ? storage.any
      ? 'Saved on this device'
      : 'Off · nothing is saved'
    : unavailable
      ? 'Not available here'
      : describeStatus(cloud);

  return (
    <div className="list">
      <Toggle
        label="Sync across devices"
        hint={status}
        on={enabled}
        onToggle={async () => {
          const next = !enabled;
          setSettings({ cloudSync: next });
          if (next) {
            setBusy(true);
            await syncNow();
            setBusy(false);
          }
        }}
      />
      {enabled && !unavailable && (
        <button
          className="list-row"
          disabled={busy || cloud.kind === 'syncing'}
          onClick={async () => {
            setBusy(true);
            await syncNow();
            setBusy(false);
            toast('Synced');
          }}
        >
          <span className="grow title" style={{ color: 'var(--accent)' }}>
            {busy || cloud.kind === 'syncing' ? 'Syncing…' : 'Sync now'}
          </span>
        </button>
      )}
    </div>
  );
}

function Toggle({
  label,
  hint,
  on,
  onToggle,
}: {
  label: string;
  hint?: string;
  on: boolean;
  onToggle: () => void;
}) {
  return (
    <button className="list-row" onClick={onToggle}>
      <span className="grow">
        <div className="title">{label}</div>
        {hint && <div className="meta">{hint}</div>}
      </span>
      <span className={`switch${on ? ' on' : ''}`}>
        <i />
      </span>
    </button>
  );
}

function Stepper({
  label,
  value,
  min,
  max,
  step,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (n: number) => void;
}) {
  return (
    <div className="list-row">
      <span className="grow title">{label}</span>
      <div className="stepper">
        <button onClick={() => onChange(Math.max(min, value - step))} aria-label="Decrease">
          −
        </button>
        <span>{value}</span>
        <button onClick={() => onChange(Math.min(max, value + step))} aria-label="Increase">
          +
        </button>
      </div>
    </div>
  );
}
