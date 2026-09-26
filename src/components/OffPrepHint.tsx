import { NOT_IN_BOOK } from '../model/nudge';
import { moveLabel, type TidyFind } from '../model/tidy';
import { nudgeColor } from './Nudges';
import { Icons } from './Icons';

/**
 * The line under a round's verdict when a move off your prep was closer to
 * the rest of your lines than the prepared one, in the colour Growth would
 * draw it, and the way to Tidy.
 */
export function OffPrepHint({ find, onTidy, compact }: { find: TidyFind; onTidy: () => void; compact?: boolean }) {
  const color = nudgeColor(find.tone);
  const ply = find.path.length;
  return (
    <div className={`off-prep-hint${compact ? ' compact' : ' card'}`}>
      <div style={{ color }}>
        {moveLabel(ply, find.suggestion)} is closer to the rest of your prep than {moveLabel(ply, find.mine)}.{' '}
        {find.reason}
        {find.offBook ? NOT_IN_BOOK : ''}.
      </div>
      <button className="btn sm mt-8" onClick={onTidy}>
        <Icons.merge size={16} />
        Tidy this
      </button>
    </div>
  );
}
