import type { NudgedMove, NudgeTone } from '../model/nudge';

/** The colour a nudge is drawn in: green toward, yellow toward from off the list, red away. */
export function nudgeColor(tone: NudgeTone | undefined): string | undefined {
  if (tone === 'toward') return 'var(--good)';
  if (tone === 'toward-far') return 'var(--warn)';
  if (tone === 'away') return 'var(--bad)';
  return undefined;
}

/** The board's arrows for a set of nudged moves. */
export function nudgedArrows(moves: NudgedMove[]) {
  return moves.map((move) => ({ from: move.from, to: move.to, color: nudgeColor(move.tone) }));
}

/** One line per coloured arrow, saying why, in the arrow's colour. Nothing when none is. */
export function NudgeReasons({ moves }: { moves: NudgedMove[] }) {
  const said = moves
    .filter((move) => move.tone && move.reason)
    // Toward before away, so the line you are being steered to reads first.
    .sort((a, b) => Number(a.tone === 'away') - Number(b.tone === 'away'));
  if (!said.length) return null;
  return (
    <div className="nudges">
      {said.map((move) => (
        <div key={move.san} style={{ color: nudgeColor(move.tone) }}>
          {move.reason}
        </div>
      ))}
    </div>
  );
}
