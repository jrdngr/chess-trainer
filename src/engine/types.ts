export interface EngineLine {
  multipv: number;
  depth: number;
  /** Score in centipawns from White's point of view. Null when mate is found. */
  cp: number | null;
  /** Moves to mate from White's point of view (positive = White mates). */
  mate: number | null;
  /** Principal variation as UCI moves. */
  pv: string[];
}

export interface EngineSnapshot {
  lines: EngineLine[];
  depth: number;
  nodes: number;
  thinking: boolean;
  fen: string | null;
}

export type EngineBackend = 'stockfish' | 'heuristic' | 'unavailable';

export interface EngineLimits {
  depth?: number;
  movetime?: number;
  multiPv?: number;
}

export interface Engine {
  readonly backend: EngineBackend;
  ready(): Promise<boolean>;
  analyse(fen: string, limits: EngineLimits, onUpdate: (snap: EngineSnapshot) => void): void;
  stop(): void;
  dispose(): void;
}

/** Format a score for display, always from the side-to-move-independent White view. */
export function formatScore(line: Pick<EngineLine, 'cp' | 'mate'>): string {
  if (line.mate !== null) return `${line.mate > 0 ? '' : '-'}M${Math.abs(line.mate)}`;
  if (line.cp === null) return '—';
  const pawns = line.cp / 100;
  return `${pawns > 0 ? '+' : pawns < 0 ? '' : '+'}${pawns.toFixed(2)}`;
}

/** 0..1 white-advantage fraction, for the eval bar. */
export function winFraction(line: Pick<EngineLine, 'cp' | 'mate'> | undefined): number {
  if (!line) return 0.5;
  if (line.mate !== null) return line.mate > 0 ? 1 : 0;
  if (line.cp === null) return 0.5;
  return 1 / (1 + Math.exp(-line.cp / 320));
}
