import { applySan, legalSans, positionStatus, START_FEN } from "../../chess/core";
import { mulberry32 } from "../../model/session";
import { cases, type CaseFile } from "../caseKit";

/**
 * Games of random legal moves, seeded: every move the chess rules allow, in
 * the order they are listed, written as SAN, and every position after it as
 * FEN. What pins the native app's move generation, SAN and FEN to chess.js
 * beyond the opening lines the book holds — promotions, en passant, castling
 * rights and mates turn up along the way.
 */
function randomGame(seed: number, plies: number) {
  const rand = mulberry32(seed);
  let fen = START_FEN;
  const sans: string[] = [];
  const fens: string[] = [];
  const counts: number[] = [];
  for (let i = 0; i < plies; i++) {
    const moves = legalSans(fen);
    counts.push(moves.length);
    if (!moves.length) break;
    const san = moves[Math.floor(rand() * moves.length)];
    fen = applySan(fen, san)!.after;
    sans.push(san);
    fens.push(fen);
  }
  return { sans, fens, counts, status: positionStatus(fen) };
}

const file: CaseFile = {
  area: "chess",
  functions: [
    cases(
      "core.randomGame",
      "A game of seeded random legal moves: the moves as SAN, the position after each as FEN, how many moves each position had, and how it ended.",
      randomGame,
      Array.from({ length: 40 }, (_, i) => [i + 1, 200] as [number, number]),
    ),
    cases(
      "core.applySan",
      "A move read from what a player or a file might write: SAN, with or without check marks, castling with zeros, squares, or an unneeded disambiguation; null when it is not a legal move.",
      (fen: string, san: string) => applySan(fen, san),
      [
        [START_FEN, "e4"],
        [START_FEN, "Nf3"],
        [START_FEN, "Ng1f3"],
        [START_FEN, "e2e4"],
        [START_FEN, "e2-e4"],
        [START_FEN, "Pe4"],
        [START_FEN, "e5"],
        [START_FEN, "Ke2"],
        [START_FEN, "O-O"],
        [START_FEN, ""],
        [START_FEN, "not a move"],
        ["r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "O-O"],
        ["r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "0-0-0"],
        ["r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "Rh8+"],
        ["r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "Rxh8"],
        ["7k/P7/8/8/8/8/8/K7 w - - 0 1", "a8=Q+"],
        ["7k/P7/8/8/8/8/8/K7 w - - 0 1", "a8Q"],
        ["7k/P7/8/8/8/8/8/K7 w - - 0 1", "a8=N"],
        ["7k/P7/8/8/8/8/8/K7 w - - 0 1", "a7a8n"],
        ["rnbqkbnr/pp1p1ppp/8/2pPp3/8/8/PPP1PPPP/RNBQKBNR w KQkq e6 0 3", "dxe6"],
        ["rnbqkbnr/pp1p1ppp/8/2pPp3/8/8/PPP1PPPP/RNBQKBNR w KQkq e6 0 3", "de6"],
        ["rnbqkbnr/pp1p1ppp/8/2pPp3/8/8/PPP1PPPP/RNBQKBNR w KQkq e6 0 3", "dxc6"],
        ["4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", "Rad1"],
        ["4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", "Rd1"],
        ["4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1", "Rhd1"],
        ["1k6/8/8/8/8/8/R7/R3K3 w Q - 0 1", "R1a2"],
        ["1k6/8/8/8/8/8/R7/R3K3 w Q - 0 1", "R2a3"],
        ["1k6/8/8/8/8/8/R7/R3K3 w Q - 0 1", "Ra3"],
      ],
    ),
  ],
};

export default file;
