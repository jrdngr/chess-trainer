import { ANY_FAVORITE } from '../../model/anyFavorite';
import { AppBar, Section, Segmented, Toggle } from '../../components/ui';
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
  const opening = selected && selected !== ANY_FAVORITE ? nodeById(openingTree(referenceIndex()), selected) : null;

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
              ? 'The opponent plays what strong players choose most, with no idea what you have prepared.'
              : 'Your lines, weighted by what strong players choose, every reply you prepared coming up often, leaning toward the ones you miss.'}
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

        <Section title="Feedback" />
        <div className="list">
          <Toggle
            label="Move scores"
            hint="What each move the engine judges cost you, in centipawns, over its square"
            on={prefs.moveScores}
            onToggle={() => setPrefs({ moveScores: !prefs.moveScores })}
          />
          <Toggle
            label="Board glow"
            hint="The board's edge tints green when you are better and red when you are worse"
            on={prefs.boardGlow}
            onToggle={() => setPrefs({ boardGlow: !prefs.boardGlow })}
          />
        </div>

        <Section title="Past the opening" />
        <div className="list">
          <Toggle label="Moments" on={prefs.moments} onToggle={() => setPrefs({ moments: !prefs.moments })} />
          <Toggle label="Missions" on={prefs.missions} onToggle={() => setPrefs({ missions: !prefs.missions })} />
          <Toggle label="Combo" on={prefs.combo} onToggle={() => setPrefs({ combo: !prefs.combo })} />
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
          {score.runs === 0 && score.ended === 0
            ? 'No runs yet'
            : [
                `${score.runs} run${score.runs === 1 ? '' : 's'}`,
                score.ended > 0 && `${score.ended} ended`,
                form !== null && `recent form ${form}`,
              ]
                .filter(Boolean)
                .join(' · ')}
        </div>
      </span>
      {now !== undefined && <span className="val num">{now}</span>}
      <span className="val num muted">best {score.best}</span>
    </div>
  );
}
