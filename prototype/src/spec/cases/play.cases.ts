import type { EngineLine } from "../../engine/types";
import {
  chooseMove,
  levelById,
  LEVELS,
  mergeGames,
  openingLine,
  playedGame,
  withPlayGame,
  type GameResult,
} from "../../model/play";
import type { ImportedGame } from "../../model/types";
import { cases, grid, range, type CaseFile } from "../caseKit";

const AT = Date.parse("2026-10-01T12:00:00Z");
const LONG =
  "e4 e5 Nf3 Nc6 Bb5 a6 Ba4 Nf6 O-O Be7 Re1 b5 Bb3 d6 c3 O-O h3 Nb8 d4 Nbd7 c4 c6 cxb5 axb5 Nc3 Bb7 Bg5 b4 Nb1 h6 Bh4 c5 dxe5 Nxe5 Nxe5 dxe5 Qxd8 Rfxd8 Nd2 Bd6 f3";

/** Five candidate lines, best first, as the engine reports them. */
const lines = (n: number): EngineLine[] =>
  range(1, n).map((i) => ({
    multipv: i,
    depth: 5,
    cp: 40 - i * 10,
    mate: null,
    pv: [`m${i}`, "x"],
  }));

const game = (
  id: string,
  source: ImportedGame["source"],
  date: string,
): ImportedGame => ({
  id,
  source,
  white: "a",
  black: "b",
  result: "1-0",
  userColor: "w",
  date,
  moves: ["e4", "e5"],
});

const ids = (games: ImportedGame[]) => games.map((g) => `${g.id}:${g.source}`);

const file: CaseFile = {
  area: "play",
  functions: [
    cases(
      "play.levelById",
      "A strength by id; an unknown id is Club.",
      (id: string) => levelById(id).name,
      [...LEVELS.map((l) => l.id), "nope"].map((id) => [id] as [string]),
    ),
    cases(
      "play.chooseMove",
      "Which candidate the engine plays at a strength, for a draw of the dice: the best with 1 - slip, each worse one half as likely as the one before; Full always plays the best.",
      (level: string, n: number, roll: number) =>
        chooseMove(lines(n), levelById(level), () => roll),
      [
        ...grid(
          LEVELS.map((l) => l.id),
          [1, 3, 5],
          [0, 0.2, 0.4, 0.6, 0.75, 0.9, 0.999],
        ),
        ["club", 0, 0.5],
      ],
    ),
    cases(
      "play.openingLine",
      "What Save this opening writes: the first 16 plies of the game, trimmed to end on your own move.",
      (n: number, color: "w" | "b") =>
        openingLine(LONG.split(" ").slice(0, n), color).join(" "),
      grid([0, 1, 2, 5, 15, 16, 17, 30], ["w", "b"] as const),
    ),
    cases(
      "play.playedGame",
      "A finished Play game, kept as a game like an import: You against Engine (level), the result from White's side, the date, and its first 40 plies. An unfinished game, or one under 2 plies, is not kept.",
      (result: GameResult, color: "w" | "b", plies: number) =>
        playedGame({
          id: "play_1",
          color,
          moves: LONG.split(" ").slice(0, plies),
          result,
          level: levelById("strong"),
          at: AT,
        }),
      [
        ...grid(
          ["win", "loss", "draw"] as GameResult[],
          ["w", "b"] as const,
          [41],
        ),
        ["unfinished", "w", 20],
        ["win", "w", 1],
      ],
    ),
    cases(
      "play.withPlayGame",
      "Keeping a Play game: newest first ahead of the imports, the same game recorded again replaces itself, at most 200 kept.",
      (before: [string, ImportedGame["source"]][], add: string) =>
        ids(
          withPlayGame(
            before.map(([id, source]) => game(id, source, "2026-10-01")),
            game(add, "play", "2026-10-02"),
          ),
        ),
      [
        [[], "p1"],
        [
          [
            ["p1", "play"],
            ["l1", "lichess"],
          ],
          "p2",
        ],
        [
          [
            ["p2", "play"],
            ["p1", "play"],
            ["l1", "lichess"],
          ],
          "p1",
        ],
      ],
    ),
    cases(
      "play.withPlayGame (cap)",
      "Only the newest 200 Play games are kept.",
      (n: number) => {
        let games: ImportedGame[] = [game("l1", "lichess", "2026-01-01")];
        for (const i of range(1, n))
          games = withPlayGame(games, game(`p${i}`, "play", "2026-10-01"));
        return {
          kept: games.length,
          first: games[0].id,
          last: ids(games.slice(-2)),
        };
      },
      [[199], [200], [205]],
    ),
    cases(
      "play.mergeGames",
      "Games from two devices: this device's imports, and both devices' Play games merged by id, newest date first.",
      (
        local: [string, ImportedGame["source"], string][],
        remote: [string, ImportedGame["source"], string][],
      ) =>
        ids(
          mergeGames(
            local.map(([id, s, d]) => game(id, s, d)),
            remote.map(([id, s, d]) => game(id, s, d)),
          ),
        ),
      [
        [
          [
            ["p1", "play", "2026-10-01"],
            ["l1", "lichess", "2026-09-01"],
          ],
          [
            ["p2", "play", "2026-10-03"],
            ["p1", "play", "2026-10-01"],
            ["c1", "chesscom", "2026-10-05"],
          ],
        ],
        [[], []],
      ],
    ),
  ],
};

export default file;
