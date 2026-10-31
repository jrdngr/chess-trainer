import { applySan, START_FEN, type Color } from "../../chess/core";
import type { EngineLine } from "../../engine/types";
import { pickTrade } from "../../engine/cashOut";
import {
  asMover,
  breakCandidates,
  goalRoute,
  kingReport,
  lensMarks,
  LENSES,
  newlyLoose,
  spaceCount,
  type LensKind,
  type LensMarks,
} from "../../model/boardHints";
import {
  planFor,
  STRUCTURE_TEMPLATES,
  structureLabel,
  structureOf,
} from "../../model/structures";
import { cases, grid, type CaseFile } from "../caseKit";

const walk = (line: string) => {
  const fens = [START_FEN];
  for (const san of line ? line.split(" ") : [])
    fens.push(applySan(fens.at(-1)!, san)!.after);
  return fens;
};
const fenOf = (line: string) => walk(line).at(-1)!;
const prevOf = (line: string) => walk(line).at(-2) ?? null;

/** Middlegames the lenses are read in, by name. */
const GAMES: Record<string, string> = {
  start: "",
  "isolated queen pawn":
    "e4 c6 d4 d5 exd5 cxd5 c4 Nf6 Nc3 e6 Nf3 Be7 cxd5 Nxd5",
  carlsbad: "d4 d5 c4 e6 Nc3 Nf6 cxd5 exd5 Bg5 c6 e3 Be7 Bd3 Nbd7",
  stonewall: "d4 e6 c4 f5 g3 Nf6 Bg2 d5 Nf3 c6 O-O Bd6",
  "king's indian": "d4 Nf6 c4 g6 Nc3 Bg7 e4 d6 Nf3 O-O Be2 e5 O-O Nc6 d5 Ne7",
  maroczy: "e4 c5 Nf3 Nc6 d4 cxd4 Nxd4 g6 c4 Bg7 Be3 Nf6 Nc3 d6",
  "french advance": "e4 e6 d4 d5 e5 c5 c3 Nc6 Nf3 Qb6",
  "english attack":
    "e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6 Be3 e5 Nb3 Be6 f3 Be7 Qd2 O-O O-O-O Nbd7 g4",
  "a trap": "e4 e5 Nf3 Nc6 Bc4 Nd4 Nxe5 Qg5 Nxf7 Qxg2",
  "caro advance": "e4 c6 d4 d5 e5 Bf5 Nf3 e6 Be2 c5",
  hedgehog:
    "c4 c5 Nf3 Nf6 Nc3 e6 g3 b6 Bg2 Bb7 O-O Be7 d4 cxd4 Qxd4 d6 Rd1 a6 b3 Nbd7 e4 Qc7",
};
const NAMES = Object.keys(GAMES);

/** A lens's marks, written short. */
function short(m: LensMarks) {
  const out: Record<string, unknown> = {};
  if (m.caption !== undefined) out.caption = m.caption;
  if (m.ghost) out.ghost = true;
  if (m.tints?.length)
    out.tints = m.tints
      .map((t) => `${t.square}:${t.color}:${t.strength}`)
      .sort();
  if (m.tags?.length)
    out.tags = m.tags.map((t) => `${t.square}:${t.tone}`).sort();
  if (m.dots?.length) out.dots = [...m.dots].sort();
  if (m.rings?.length)
    out.rings = m.rings.map((r) => `${r.square}:${r.tone}`).sort();
  if (m.stars?.length)
    out.stars = m.stars.map((s) => `${s.square}:${s.side}`).sort();
  if (m.zone?.length) out.zone = [...m.zone].sort();
  if (m.pips?.length)
    out.pips = m.pips
      .map((p) => `${p.square}:${p.attackers}/${p.defenders}`)
      .sort();
  if (m.shields?.length)
    out.shields = m.shields.map((s) => `${s.square}:${s.grade}`);
  if (m.emptyPawns?.length) out.emptyPawns = [...m.emptyPawns].sort();
  if (m.lines?.length) out.lines = m.lines.map((l) => `${l.from}-${l.to}`);
  if (m.arrows?.length)
    out.arrows = m.arrows.map((a) => `${a.from}-${a.to}:${a.tone}`);
  return out;
}

const line = (cp: number, pv: string[], multipv = 1): EngineLine => ({
  multipv,
  depth: 12,
  cp,
  mate: null,
  pv,
});

const file: CaseFile = {
  area: "lenses",
  functions: [
    cases(
      "boardHints.lensMarks",
      "What each lens draws over a position, from the side you play: Pawns (weak and passed pawns, holes, the structure's name), Pieces (activity green/amber/red, each side's worst piece, outposts, knight routes to your two nearest), Space (who holds each square and by how much, the count in each other's half), Kings (zone, attackers, missing shield pawns, open lines, a grade), Threats (hanging and cheaply attacked men, what the last move newly threatens).",
      (name: string, kind: LensKind, me: Color) =>
        short(lensMarks(kind, fenOf(GAMES[name]), me, prevOf(GAMES[name]))),
      grid(
        NAMES,
        LENSES.map((l) => l.kind),
        ["w", "b"] as Color[],
      ),
    ),
    cases(
      "boardHints.spaceCount",
      "Squares each side holds outright in the other's half.",
      (name: string, me: Color) => spaceCount(fenOf(GAMES[name]), me),
      grid(NAMES, ["w"] as Color[]),
    ),
    cases(
      "boardHints.kingReport",
      "A king's danger: attacks on its zone, missing shield pawns and open lines count up, defenders count down; in check or 7 and up is Under attack, 3 and up Exposed, else Safe.",
      (name: string, color: Color) => {
        const r = kingReport(fenOf(GAMES[name]), color);
        return r && { square: r.square, score: r.score, grade: r.grade };
      },
      grid(NAMES, ["w", "b"] as Color[]),
    ),
    cases(
      "boardHints.breakCandidates",
      "The pawn breaks a side has in a position (a pawn capture, or a push that attacks a pawn), with that side to move; none when the other side is in check.",
      (name: string, color: Color) => {
        const mover = asMover(fenOf(GAMES[name]), color);
        return mover ? breakCandidates(mover, color) : null;
      },
      grid(NAMES, ["w", "b"] as Color[]),
    ),
    cases(
      "boardHints.newlyLoose",
      "The Undefended flash: your men a move of yours leaves loose that were not loose before it.",
      (line: string, san: string) => {
        const before = fenOf(line);
        const move = applySan(before, san)!;
        return newlyLoose(
          before,
          move.after,
          before.split(" ")[1] as Color,
          move,
        );
      },
      [
        ["e4 e5 Nf3 Nc6", "Bc4"],
        ["e4 e5 Nf3 Nc6", "Bb5"],
        ["e4 e5 Nf3 Nc6", "Ng5"],
        ["d4 d5 c4 e6 Nc3 Nf6", "Bg5"],
        ["e4 e5 Nf3 d6", "Bc4"],
        ["e4 d5", "exd5"],
      ],
    ),
    cases(
      "structures.structureOf",
      "The named pawn structure on the board, if any, as the Pawns lens and the plan card call it.",
      (name: string) => {
        const s = structureOf(fenOf(GAMES[name]));
        return s && structureLabel(s);
      },
      NAMES.map((n) => [n] as [string]),
    ),
    cases(
      "structures.planFor",
      "Your plan in a structure, by side: the steps for the side it is named after, or for the other side; squares mirrored when Black owns it, Black's moves given their '...', and the squares each step's goal names.",
      (id: string, a: Color, me: Color) => {
        const template = STRUCTURE_TEMPLATES.find((t) => t.id === id)!;
        return planFor({ template, a }, me).map(
          (s) =>
            `${s.text}${s.goals ? ` [${s.goals.map((g) => `${g.piece}${g.to}`).join(" ")}]` : ""}`,
        );
      },
      grid(
        STRUCTURE_TEMPLATES.map((t) => t.id),
        ["w", "b"] as Color[],
        ["w", "b"] as Color[],
      ),
    ),
    cases(
      "boardHints.goalRoute",
      "Whether a plan step is done (a piece of its kind stands on its square), which ticks it on the card.",
      (
        name: string,
        me: Color,
        piece: "n" | "p" | "b" | "r" | "q",
        to: string,
      ) => goalRoute(fenOf(GAMES[name]), me, { piece, to: to as never }).done,
      [
        ["isolated queen pawn", "w", "n", "e5"],
        ["isolated queen pawn", "w", "p", "d4"],
        ["carlsbad", "w", "p", "b4"],
        ["stonewall", "b", "n", "e4"],
        ["king's indian", "b", "p", "f5"],
        ["king's indian", "w", "p", "d5"],
      ],
    ),
    cases(
      "cashOut.pickTrade",
      "Cash out: at +200 or more, the first of the engine's lines within 30cp of the best and still at +200 that captures a piece (not a pawn, not with the king) taken straight back by one about as valuable.",
      (lines: EngineLine[], me: Color) =>
        pickTrade(fenOf("d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7"), lines, me),
      [
        [[line(250, ["g5f6", "e7f6"]), line(240, ["e2e3", "h7h6"], 2)], "w"],
        [[line(250, ["e2e3", "h7h6"]), line(225, ["g5f6", "e7f6"], 2)], "w"],
        [[line(250, ["e2e3", "h7h6"]), line(215, ["g5f6", "e7f6"], 2)], "w"],
        [[line(220, ["e2e3", "h7h6"]), line(195, ["g5f6", "e7f6"], 2)], "w"],
        [[line(150, ["g5f6", "e7f6"])], "w"],
        [[line(250, ["g5f6", "h7h6"])], "w"],
        [[line(250, ["c4d5", "e6d5"])], "w"],
      ],
    ),
  ],
};

export default file;
