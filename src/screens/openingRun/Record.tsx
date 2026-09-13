import { Section } from '../../components/ui';
import { GRADES, gradeLabel, type OpeningRunRecord, type RunGrade } from '../../model/openingRun';

/** The colour each grade is drawn in, on the record bar and its legend. */
export const GRADE_COLORS: Record<RunGrade, string> = {
  green: 'var(--good)',
  yellow: 'var(--warn)',
  red: 'var(--bad)',
  purple: 'var(--accent)',
};

/** The verdict tone each grade reads in. */
export const GRADE_TONES: Record<RunGrade, 'ok' | 'warn' | 'no' | 'accent'> = {
  green: 'ok',
  yellow: 'warn',
  red: 'no',
  purple: 'accent',
};

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="list-row">
      <span className="grow title">{label}</span>
      <span className="val num">{value}</span>
    </div>
  );
}

/** The global tally. Per-opening records live on the Stats tab. */
export function Record({ record }: { record: OpeningRunRecord }) {
  const total = GRADES.reduce((sum, g) => sum + record.grades[g], 0);
  return (
    <>
      <Section title="Record" />
      <div className="list">
        <Stat label="Best run" value={record.best} />
        <Stat label="Runs" value={record.runs} />
        <Stat label="Lines completed" value={record.survivals} />
      </div>
      {total > 0 && (
        <div className="card mt-8">
          <div className="bar-stack">
            {GRADES.filter((g) => record.grades[g] > 0).map((g) => (
              <i key={g} style={{ background: GRADE_COLORS[g], flex: record.grades[g] }} title={gradeLabel(g)} />
            ))}
          </div>
          <div className="pills mt-12">
            {GRADES.map((g) => (
              <span className="pill" key={g}>
                <i style={{ background: GRADE_COLORS[g] }} />
                <b>{record.grades[g]}</b> {gradeLabel(g).toLowerCase()}
              </span>
            ))}
          </div>
        </div>
      )}
    </>
  );
}
