import type { GraphRow } from '../model/extensionGraph';

/** Grid metrics, in pixels: left margin, column width, node size, row height, band height. */
const X0 = 24;
const CW = 41;
const NW = 37;
const NH = 26;
const RH = 36;
const TOP = 30;

const cx = (col: number) => X0 + col * CW;
const ry = (row: number) => TOP + row * RH;

/**
 * The Extensions review's graph, drawn from `layoutGraph`'s rows: book moves
 * filled, extensions outlined, a saved mistake with a warning mark. White's
 * columns carry the move numbers. Forks leave the parent's right edge and run
 * down the gap before the child's column, which the layout keeps clear.
 */
export function ExtensionGraph({
  rows,
  rootPly,
  selected,
  onSelect,
}: {
  rows: GraphRow[];
  /** The ply of column 0's moves: 0 is White's first move. */
  rootPly: number;
  selected: string | null;
  onSelect: (nodeId: string) => void;
}) {
  const cols = Math.max(1, ...rows.map((r) => r.start + r.cells.length));
  const joins = rows.some((r) => r.cells.some((c) => c.kind === 'join'));
  const width = X0 + cols * CW + (joins ? 18 : 8);
  const height = TOP + rows.length * RH;
  const mid = NH / 2;

  return (
    <svg className="ext-graph" width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      {Array.from({ length: cols }, (_, c) => {
        const ply = rootPly + c;
        if (ply % 2 === 0) {
          return (
            <g key={`b${c}`}>
              <text className="band-n" x={cx(c) + NW / 2} y={14}>
                {ply / 2 + 1}.
              </text>
              <rect className="band" x={cx(c) - 2} y={22} width={CW * 2 - 2} height={height - 22} rx={6} />
            </g>
          );
        }
        return c === 0 ? (
          <text key={`b${c}`} className="band-n" x={cx(c) + NW / 2} y={14}>
            {(ply + 1) / 2}...
          </text>
        ) : null;
      })}

      {rows.length > 0 && <circle className="root" cx={8} cy={ry(0) + mid} r={5} />}
      {rows.map((row, i) =>
        row.parent ? null : (
          <path
            key={`t${i}`}
            className={`edge${row.cells[0]?.kind !== 'book' ? ' ext' : ''}`}
            d={i === 0 ? `M8 ${ry(0) + mid} H${cx(0)}` : `M8 ${ry(0) + mid} V${ry(i) + mid - 8} Q8 ${ry(i) + mid} 16 ${ry(i) + mid} H${cx(0)}`}
          />
        ),
      )}
      {rows.map((row, i) => {
        const y = ry(i) + mid;
        const out = [];
        if (row.parent) {
          const gx = cx(row.start) - 3;
          const py = ry(row.parent.row) + mid;
          out.push(
            <path
              key={`f${i}`}
              className={`edge${row.cells[0]?.kind !== 'book' ? ' ext' : ''}`}
              d={`M${cx(row.parent.col) + NW} ${py} H${gx} V${y - 6} Q${gx} ${y} ${gx + 5} ${y}`}
            />,
          );
        }
        for (let j = 0; j < row.cells.length - 1; j++) {
          const a = cx(row.start + j) + NW;
          const next = row.cells[j + 1];
          out.push(
            <path
              key={`s${i}-${j}`}
              className={`edge${next.kind !== 'book' ? ' ext' : ''}${next.kind === 'join' ? ' join' : ''}`}
              d={`M${a} ${y} H${a + CW - NW}`}
            />,
          );
        }
        return out;
      })}

      {rows.map((row, i) =>
        row.cells.map((cell, j) => {
          const x = cx(row.start + j);
          const y = ry(i);
          const pick = cell.nodeId;
          return (
            <g
              key={`c${i}-${j}`}
              className={`cell ${cell.kind}${pick && pick === selected ? ' selected' : ''}`}
              onClick={pick ? () => onSelect(pick) : undefined}
            >
              {pick === selected && pick && <rect className="ring" x={x - 4} y={y - 4} width={NW + 8} height={NH + 8} rx={9} />}
              <rect className="node" x={x + 0.75} y={y + 0.75} width={NW - 1.5} height={NH - 1.5} rx={7} />
              <text x={x + NW / 2} y={y + 17} className={cell.label.length >= 5 ? 'small' : undefined}>
                {cell.label}
              </text>
              {cell.kind === 'mistake' && <path className="warn" d={`M${x + NW - 2} ${y - 7}l6 11H${x + NW - 8}z`} />}
            </g>
          );
        }),
      )}

      {joins &&
        rows.map((_, i) => (
          <text key={`n${i}`} className="row-n" x={width - 4} y={ry(i) + 17}>
            {i + 1}
          </text>
        ))}
    </svg>
  );
}
