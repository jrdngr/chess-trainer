import { Chess, type Move as ChessJsMove, type Square, type Color } from 'chess.js';

export type { Square, Color };
export type PieceType = 'p' | 'n' | 'b' | 'r' | 'q' | 'k';

export const START_FEN = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

export interface Piece {
  square: Square;
  type: PieceType;
  color: Color;
}

export interface LegalMove {
  from: Square;
  to: Square;
  san: string;
  uci: string;
  promotion?: PieceType;
  piece: PieceType;
  captured?: PieceType;
  /** FEN after the move */
  after: string;
}

/**
 * A position key ignores the halfmove clock and fullmove number so that
 * transpositions collapse onto the same repertoire node.
 */
export function positionKey(fen: string): string {
  const parts = fen.split(' ');
  return parts.slice(0, 4).join(' ');
}

export function fenTurn(fen: string): Color {
  return fen.split(' ')[1] === 'b' ? 'b' : 'w';
}

export function fullmoveNumber(fen: string): number {
  const n = Number(fen.split(' ')[5]);
  return Number.isFinite(n) ? n : 1;
}

/** Ply index (0-based) of the position, derived from the FEN counters. */
export function plyOf(fen: string): number {
  return (fullmoveNumber(fen) - 1) * 2 + (fenTurn(fen) === 'b' ? 1 : 0);
}

export function piecesFromFen(fen: string): Piece[] {
  const chess = new Chess(fen);
  const out: Piece[] = [];
  for (const row of chess.board()) {
    for (const sq of row) {
      if (sq) out.push({ square: sq.square, type: sq.type as PieceType, color: sq.color });
    }
  }
  return out;
}

/** What a piece is worth, for the material count. */
export const PIECE_VALUES: Record<PieceType, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

/** One full side, in the order captures read best: pawns first, queen last. */
const FULL_SIDE: PieceType[] = ['p', 'p', 'p', 'p', 'p', 'p', 'p', 'p', 'n', 'n', 'b', 'b', 'r', 'r', 'q'];

export interface Material {
  /** Black pieces White has taken. */
  byWhite: PieceType[];
  /** White pieces Black has taken. */
  byBlack: PieceType[];
  /** Points White is ahead by. Negative means Black is. */
  lead: number;
}

/**
 * What has come off the board, and who is ahead.
 *
 * The captures are read backwards from what is left against a full set, which
 * is how every board does it and is only ever wrong about promotions — an extra
 * queen reads as a missing pawn. The lead is counted from the pieces actually
 * on the board instead, so a promotion counts for what it is really worth.
 */
export function material(fen: string): Material {
  const pieces = piecesFromFen(fen);
  const left = { w: [] as PieceType[], b: [] as PieceType[] };
  let lead = 0;
  for (const piece of pieces) {
    left[piece.color].push(piece.type);
    lead += (piece.color === 'w' ? 1 : -1) * PIECE_VALUES[piece.type];
  }
  const taken = (side: PieceType[]): PieceType[] => {
    const rest = [...side];
    const out: PieceType[] = [];
    for (const type of FULL_SIDE) {
      const at = rest.indexOf(type);
      if (at === -1) out.push(type);
      else rest.splice(at, 1);
    }
    return out;
  };
  return { byWhite: taken(left.b), byBlack: taken(left.w), lead };
}

export function legalMoves(fen: string): LegalMove[] {
  const chess = new Chess(fen);
  return chess.moves({ verbose: true }).map(toLegalMove);
}

function toLegalMove(m: ChessJsMove): LegalMove {
  return {
    from: m.from as Square,
    to: m.to as Square,
    san: m.san,
    uci: m.from + m.to + (m.promotion ?? ''),
    promotion: m.promotion as PieceType | undefined,
    piece: m.piece as PieceType,
    captured: m.captured as PieceType | undefined,
    after: m.after,
  };
}

/** The legal moves as SAN only: much cheaper than `legalMoves`, which works out every resulting position. */
export function legalSans(fen: string): string[] {
  return new Chess(fen).moves();
}

/** Apply a move given as SAN. Returns null when the move is illegal. */
export function applySan(fen: string, san: string): LegalMove | null {
  const chess = new Chess(fen);
  try {
    const m = chess.move(san);
    return m ? toLegalMove(m) : null;
  } catch {
    return null;
  }
}

/** Apply a move given as from/to (+promotion). Returns null when illegal. */
export function applyMove(
  fen: string,
  from: Square,
  to: Square,
  promotion?: PieceType,
): LegalMove | null {
  const chess = new Chess(fen);
  try {
    const m = chess.move({ from, to, promotion });
    return m ? toLegalMove(m) : null;
  } catch {
    return null;
  }
}

export function applyUci(fen: string, uci: string): LegalMove | null {
  if (uci.length < 4) return null;
  const from = uci.slice(0, 2) as Square;
  const to = uci.slice(2, 4) as Square;
  const promo = uci.length > 4 ? (uci[4] as PieceType) : undefined;
  return applyMove(fen, from, to, promo);
}

/** Walk a list of SAN moves from a starting FEN. Stops at the first illegal move. */
export function walkSan(sans: string[], startFen = START_FEN): { fens: string[]; moves: LegalMove[] } {
  const fens = [startFen];
  const moves: LegalMove[] = [];
  let fen = startFen;
  for (const san of sans) {
    const m = applySan(fen, san);
    if (!m) break;
    moves.push(m);
    fen = m.after;
    fens.push(fen);
  }
  return { fens, moves };
}

export function isPromotion(fen: string, from: Square, to: Square): boolean {
  return legalMoves(fen).some((m) => m.from === from && m.to === to && !!m.promotion);
}

/** The squares of the last move in a line, for highlighting on a board. */
export function lastMoveOf(
  sans: string[],
  startFen = START_FEN,
): { from: Square; to: Square } | null {
  if (!sans.length) return null;
  const { fens } = walkSan(sans.slice(0, -1), startFen);
  const move = applySan(fens[fens.length - 1], sans[sans.length - 1]);
  return move ? { from: move.from, to: move.to } : null;
}

export interface PositionStatus {
  check: boolean;
  checkmate: boolean;
  stalemate: boolean;
  draw: boolean;
  gameOver: boolean;
}

export function positionStatus(fen: string): PositionStatus {
  const chess = new Chess(fen);
  return {
    check: chess.isCheck(),
    checkmate: chess.isCheckmate(),
    stalemate: chess.isStalemate(),
    draw: chess.isDraw(),
    gameOver: chess.isGameOver(),
  };
}

export function kingSquare(fen: string, color: Color): Square | null {
  return piecesFromFen(fen).find((p) => p.type === 'k' && p.color === color)?.square ?? null;
}

export const FILES = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'] as const;
export const RANKS = ['1', '2', '3', '4', '5', '6', '7', '8'] as const;

export function squareToCoords(square: Square): { file: number; rank: number } {
  return { file: square.charCodeAt(0) - 97, rank: Number(square[1]) - 1 };
}

export function coordsToSquare(file: number, rank: number): Square {
  return (FILES[file] + RANKS[rank]) as Square;
}

export function isLightSquare(square: Square): boolean {
  const { file, rank } = squareToCoords(square);
  return (file + rank) % 2 === 1;
}

/** Render a SAN sequence as a numbered move string starting from `startFen`. */
export function sansToMoveText(sans: string[], startFen = START_FEN): string {
  let fen = startFen;
  const parts: string[] = [];
  let first = true;
  for (const san of sans) {
    const turn = fenTurn(fen);
    const n = fullmoveNumber(fen);
    if (turn === 'w') parts.push(`${n}.`);
    else if (first) parts.push(`${n}...`);
    parts.push(san);
    first = false;
    const m = applySan(fen, san);
    if (!m) break;
    fen = m.after;
  }
  return parts.join(' ');
}
