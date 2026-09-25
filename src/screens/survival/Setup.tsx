import { AppBar, Section, Segmented } from '../../components/ui';
import { SelectionBar } from '../../components/Selection';
import { clockLabel, CLOCK_MODES } from '../../model/openingRun';
import { nodeById, openingTree } from '../../model/openingTree';
import { referenceIndex } from '../../model/referenceIndex';
import {
  recentForm,
  SURVIVAL_STEERS,
  survivalFor,
  survivalSteerLabel,
  type SurvivalPrefs,
  type SurvivalScore,
} from '../../model/survival';
import { useStore } from '../../store/useStore';

/**
 * The screen that decides a Survival run: what the opponent steers toward,
 * and the clock. Start sits on top, so the same run as last time is one tap.
 */
export function Setup({ onStart, onExit }: { onStart: (prefs: SurvivalPrefs) => void; onExit: () => void }) {
  const prefs = useStore((s) => s.settings.survival);
  const setPrefs = useStore((s) => s.setSurvivalPrefs);
  const record = useStore((s) => s.survival);
  const selected = useStore((s) => s.settings.selection.opening);
  const opening = selected ? nodeById(openingTree(referenceIndex()), selected) : null;

  return (
    <>
      <AppBar title="Survival" onClose={onExit} />

      <div className="screen no-nav">
        <SelectionBar />

        <button className="btn primary block xl" onClick={() => onStart(prefs)}>
          Start
        </button>

        <Section title="Opponent steers toward" />
        <Segmented
          value={prefs.steer}
          options={SURVIVAL_STEERS.map((steer) => ({ value: steer, label: survivalSteerLabel(steer) }))}
          onChange={(steer) => setPrefs({ steer })}
        />
        <div className="note">
          {prefs.steer === 'gaps'
            ? 'The opponent walks you to a reply you have no answer to, and the game goes on past it.'
            : prefs.steer === 'book'
              ? 'The opponent plays the book by popularity, with no idea what you have prepared.'
              : 'Your lines, as often as you would meet them, leaning toward the ones you miss.'}
        </div>

        <Section title="Clock" />
        <Segmented
          value={prefs.clock}
          options={CLOCK_MODES.map((mode) => ({ value: mode, label: clockLabel(mode) }))}
          onChange={(clock) => setPrefs({ clock })}
        />
        <div className="note">
          A run lasts until your first blunder. A sound move where your prep had another is a miss: it is shown,
          logged for review, and the game goes on.
        </div>

        {record.global.runs > 0 && (
          <>
            <Section title="Moves survived" />
            <div className="list">
              {opening && <ScoreRow name={opening.name} score={survivalFor(record, opening.id)} />}
              <ScoreRow name="All openings" score={record.global} />
            </div>
          </>
        )}
      </div>
    </>
  );
}

/** One opening's best and recent form. */
export function ScoreRow({ name, score, now }: { name: string; score: SurvivalScore; now?: number }) {
  const form = recentForm(score);
  return (
    <div className="list-row">
      <span className="grow" style={{ minWidth: 0 }}>
        <div className="title truncate">{name}</div>
        <div className="meta truncate">
          {score.runs === 0
            ? 'No runs yet'
            : `${score.runs} run${score.runs === 1 ? '' : 's'}${form !== null ? ` · recent form ${form}` : ''}`}
        </div>
      </span>
      {now !== undefined && <span className="val num">{now}</span>}
      <span className="val num muted">best {score.best}</span>
    </div>
  );
}
