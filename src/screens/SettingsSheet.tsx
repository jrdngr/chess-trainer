import { useState } from 'react';
import { Sheet, toast } from '../components/ui';
import { describeStatus } from '../store/cloud';
import { DEFAULT_SETTINGS, useStore } from '../store/useStore';
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
      <div className="section-title" style={{ marginTop: 0 }}>Training</div>
      <div className="stack">
        <Row
          label="Follow the line after a correct answer"
          hint="Plays the opponent's reply and asks the next move in the same line."
          on={settings.playOpponentReplies}
          onToggle={toggle('playOpponentReplies')}
        />
        <Row
          label="Show engine evaluation while training"
          hint="Off by default — recall training is about memory, not evaluation."
          on={settings.showEvalInTraining}
          onToggle={toggle('showEvalInTraining')}
        />
        <Stepper
          label="New positions per session"
          value={settings.newCardsPerSession}
          min={0}
          max={40}
          step={2}
          onChange={(newCardsPerSession) => setSettings({ newCardsPerSession })}
        />
        <Stepper
          label="Maximum session length"
          value={settings.maxSessionLength}
          min={5}
          max={80}
          step={5}
          onChange={(maxSessionLength) => setSettings({ maxSessionLength })}
        />
      </div>

      <div className="section-title">Board</div>
      <div className="stack">
        <div className="card">
          <div className="small" style={{ marginBottom: 8, fontWeight: 600 }}>Theme</div>
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
        <Row label="Coordinates" on={settings.showCoordinates} onToggle={toggle('showCoordinates')} />
        <Row label="Haptic feedback" on={settings.hapticFeedback} onToggle={toggle('hapticFeedback')} />
      </div>

      <div className="section-title">Engine</div>
      <div className="stack">
        <Row
          label="Enable Stockfish"
          hint="Runs in a worker. Turn it off if the page feels heavy."
          on={settings.engineEnabled}
          onToggle={toggle('engineEnabled')}
        />
      </div>

      <div className="section-title">Saving</div>
      <SyncCard />

      <div className="section-title">Data</div>
      <div className="stack">
        <button
          className="btn ghost block"
          onClick={() => {
            resetProgress();
            toast('Review history cleared');
          }}
        >
          Reset review progress
        </button>
        {confirmReset ? (
          <button
            className="btn danger block"
            onClick={async () => {
              await resetAll();
              setConfirmReset(false);
              onClose();
              toast('Back to the seeded repertoires');
            }}
          >
            Tap again to erase everything
          </button>
        ) : (
          <button className="btn danger block" onClick={() => setConfirmReset(true)}>
            Reset app to seed data
          </button>
        )}
        <div className="tiny faint">
          Your progress lives in this browser (IndexedDB, with a localStorage fallback) and is
          copied to your Claude account when sync is available. Defaults:{' '}
          {DEFAULT_SETTINGS.newCardsPerSession} new positions per session.
        </div>
      </div>
    </Sheet>
  );
}

function SyncCard() {
  const cloud = useStore((s) => s.cloud);
  const storage = useStore((s) => s.storage);
  const enabled = useStore((s) => s.settings.cloudSync);
  const setSettings = useStore((s) => s.setSettings);
  const syncNow = useStore((s) => s.syncNow);
  const [busy, setBusy] = useState(false);
  const unavailable = cloud.kind === 'unavailable';

  return (
    <div className="card">
      <button
        className="row between"
        style={{ width: '100%', textAlign: 'left' }}
        onClick={async () => {
          const next = !enabled;
          setSettings({ cloudSync: next });
          if (next) {
            setBusy(true);
            await syncNow();
            setBusy(false);
          }
        }}
      >
        <span className="grow" style={{ minWidth: 0 }}>
          <span className="small" style={{ fontWeight: 600 }}>
            Save to my Claude account
          </span>
          <span className="tiny faint" style={{ display: 'block', marginTop: 3 }}>
            {enabled ? describeStatus(cloud) : 'Off'}
          </span>
        </span>
        <span className={`switch${enabled ? ' on' : ''}`} style={{ marginRight: 10 }}>
          <i />
        </span>
      </button>
      {enabled && !unavailable && (
        <button
          className="btn ghost block sm"
          style={{ marginTop: 11 }}
          disabled={busy || cloud.kind === 'syncing'}
          onClick={async () => {
            setBusy(true);
            await syncNow();
            setBusy(false);
            toast('Sync finished');
          }}
        >
          Sync now
        </button>
      )}
      <div className="divider" />
      <div className="row between tiny">
        <span className="faint">This browser</span>
        <span style={{ color: storage.any ? 'var(--good)' : 'var(--bad)', fontWeight: 650 }}>
          {storage.any
            ? storage.indexedDB
              ? 'IndexedDB'
              : 'localStorage'
            : 'blocked by this viewer'}
        </span>
      </div>
      <div className="tiny faint" style={{ marginTop: 10 }}>
        {!storage.any
          ? 'This viewer sandboxes the page, so browser storage throws and nothing can be kept here. Your Claude account is the only place progress can live \u2014 keep this on.'
          : !enabled
            ? 'Progress is saved in this browser. Turn this on to carry it between devices as well.'
            : unavailable
              ? 'The runtime did not grant account storage here, so this stays a local install.'
              : 'Repertoires, review history and settings are saved. Imported games stay on the device that imported them. Whichever device saved last wins, so finish a session before switching.'}
      </div>
    </div>
  );
}

function Row({
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
    <button className="card row between" style={{ width: '100%', textAlign: 'left' }} onClick={onToggle}>
      <span className="grow" style={{ minWidth: 0 }}>
        <span className="small" style={{ fontWeight: 600 }}>{label}</span>
        {hint && <span className="tiny faint" style={{ display: 'block', marginTop: 3 }}>{hint}</span>}
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
    <div className="card row between">
      <span className="small grow" style={{ fontWeight: 600 }}>{label}</span>
      <div className="row" style={{ gap: 8 }}>
        <button
          className="btn sm ghost"
          onClick={() => onChange(Math.max(min, value - step))}
          aria-label="Decrease"
        >
          −
        </button>
        <span className="mono" style={{ minWidth: 24, textAlign: 'center', fontWeight: 700 }}>{value}</span>
        <button
          className="btn sm ghost"
          onClick={() => onChange(Math.min(max, value + step))}
          aria-label="Increase"
        >
          +
        </button>
      </div>
    </div>
  );
}
