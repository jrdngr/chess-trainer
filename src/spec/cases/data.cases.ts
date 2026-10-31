import {
  appendEvent,
  EVENT_CAP,
  normalizeEvents,
  removedBetween,
  setEventPlace,
  type AppEvent,
  type EventPlace,
} from "../../model/events";
import {
  addLine,
  createRepertoire,
  nodeAtLine,
  pruneLine,
} from "../../model/repertoire";
import { DEFAULT_SELECTION } from "../../model/selection";
import type { Repertoire } from "../../model/types";
import {
  DEFAULT_SETTINGS,
  repertoireList,
  useStore,
} from "../../store/useStore";
import { describeStatus, type CloudStatus } from "../../store/cloud";
import { cases, range, type CaseFile } from "../caseKit";
import { pinnedClock } from "../scenarioKit";

const split = (line: string) => (line ? line.split(" ") : []);

/**
 * One step on the Playbook: an action, the side, the line it acts on, and
 * for some an argument (the place, a delta, a move).
 */
type Step =
  | ["add", "w" | "b", string, EventPlace?]
  | ["remove", "w" | "b", string]
  | ["removeLine", "w" | "b", string]
  | ["removeOpening", "w" | "b", string]
  | ["removeRepertoire", "w" | "b"]
  | ["prefer", "w" | "b", string]
  | ["note", "w" | "b", string]
  | ["reorder", "w" | "b", string, number]
  | ["tidySwitch", "w" | "b", string, string]
  | ["tidyKeep", "w" | "b", string]
  | ["tidyRemove", "w" | "b", string]
  | ["undo"]
  | ["log", AppEventInput];
type AppEventInput = Parameters<
  ReturnType<typeof useStore.getState>["logEvent"]
>[0];

function fresh() {
  setEventPlace("repertoire");
  useStore.setState({
    ready: true,
    repertoires: {},
    repertoireOrder: [],
    cards: {},
    lineCards: {},
    log: [],
    events: [],
    importedGames: [],
    mistakes: [],
    settings: {
      ...DEFAULT_SETTINGS,
      favoriteOpenings: [],
      selection: { ...DEFAULT_SELECTION },
    },
  });
}

/** Run steps on an empty Playbook and return the event log, without times or ids. */
function play(steps: Step[]) {
  let t = Date.parse("2026-10-31T12:00:00Z");
  return pinnedClock(
    () => (t += 1000),
    () => {
      fresh();
      const s = () => useStore.getState();
      const repOf = (color: "w" | "b") => {
        const id = s().ensureRepertoire(color);
        return s().repertoires[id];
      };
      const at = (color: "w" | "b", line: string) =>
        nodeAtLine(repOf(color), split(line))!.id;
      let undo: (() => void) | null = null;
      for (const step of steps) {
        switch (step[0]) {
          case "add":
            s().addLine(repOf(step[1]).id, split(step[2]), "book", step[3]);
            break;
          case "remove":
            undo = s().removeNode(repOf(step[1]).id, at(step[1], step[2]));
            break;
          case "removeLine":
            undo = s().removeLine(repOf(step[1]).id, at(step[1], step[2]));
            break;
          case "removeOpening":
            s().removeOpening(repOf(step[1]).id, at(step[1], step[2]));
            break;
          case "removeRepertoire":
            s().removeRepertoire(repOf(step[1]).id);
            break;
          case "prefer":
            s().preferMove(repOf(step[1]).id, at(step[1], step[2]));
            break;
          case "note":
            s().annotate(repOf(step[1]).id, at(step[1], step[2]), "a note");
            break;
          case "reorder":
            s().reorder(repOf(step[1]).id, at(step[1], step[2]), step[3]);
            break;
          case "tidySwitch":
            undo = s().tidySwitch(
              repOf(step[1]).id,
              at(step[1], step[2]),
              step[3],
            );
            break;
          case "tidyKeep":
            s().tidyKeep(repOf(step[1]).id, at(step[1], step[2]));
            break;
          case "tidyRemove":
            undo = s().tidyRemove(repOf(step[1]).id, at(step[1], step[2]));
            break;
          case "undo":
            undo?.();
            undo = null;
            break;
          case "log":
            s().logEvent(step[1]);
            break;
        }
      }
      return {
        events: s().events.map((e) => {
          const { at: _at, ...rest } = e as AppEvent & {
            repertoireId?: string;
          };
          delete (rest as { repertoireId?: string }).repertoireId;
          return rest;
        }),
        playbook: repertoireList(s()).map(
          (r) => `${r.color}: ${Object.keys(r.nodes).length} moves`,
        ),
      };
    },
  );
}

function rep(lines: string[]): Repertoire {
  let out = createRepertoire("White", "w", "rep_w");
  for (const line of lines) out = addLine(out, split(line), "seed").rep;
  return out;
}

const file: CaseFile = {
  area: "data",
  functions: [
    cases(
      "events.log",
      "The event log: what each change to the Playbook, and each Growth step, records, and where it was made.",
      play,
      [
        [
          [
            ["add", "w", "d4 d5 c4"],
            ["add", "w", "d4 d5"],
          ],
        ],
        [
          [
            ["add", "w", "d4 d5 c4 c5 cxd5 Qxd5 Nc3"],
            ["remove", "w", "d4 d5 c4 c5 cxd5"],
            ["undo"],
          ],
        ],
        [[["add", "b", "e4 c5", "growth"]]],
        [
          [
            ["add", "w", "d4 d5 c4 e6 Nc3"],
            ["add", "w", "d4 d5 c4 e6 Nf3"],
            ["prefer", "w", "d4 d5 c4 e6 Nf3"],
            ["note", "w", "d4 d5 c4 e6 Nc3"],
            ["reorder", "w", "d4 d5 c4 e6 Nc3", -1],
          ],
        ],
        [
          [
            ["add", "w", "e4 e5 Nf3 Nc6 Bb5 a6"],
            ["add", "w", "e4 e5 Nf3 Nc6 Bc4 Bc5 c3"],
            ["removeLine", "w", "e4 e5 Nf3 Nc6 Bc4 Bc5 c3"],
            ["undo"],
          ],
        ],
        [
          [
            ["add", "w", "d4 d5 c4 e6 Nc3 Nf6 Bg5"],
            ["tidySwitch", "w", "d4 d5 c4 e6 Nc3 Nf6 Bg5", "cxd5"],
            ["undo"],
          ],
        ],
        [
          [
            ["add", "w", "e4 a6 d4 b5 Bd3"],
            ["tidyKeep", "w", "e4 a6"],
            ["tidyRemove", "w", "e4 a6"],
            ["undo"],
          ],
        ],
        [
          [
            ["add", "w", "e4 e5 Nf3 Nc6 Bb5"],
            ["add", "b", "d4 Nf6 c4 g6"],
            ["removeOpening", "w", "e4 e5 Nf3 Nc6 Bb5"],
            ["removeRepertoire", "b"],
          ],
        ],
        [
          [
            [
              "log",
              {
                kind: "growth-offer",
                color: "w",
                line: "e4 c5",
                offered: ["Nf3", "Nc3"],
                from: "book",
              },
            ],
            [
              "log",
              {
                kind: "growth-pick",
                color: "w",
                line: "e4 c5",
                picked: "Nf3",
                offered: ["Nf3", "Nc3"],
              },
            ],
          ],
        ],
      ],
    ),
    cases(
      "events.appendEvent",
      "The log keeps the newest 1000 events.",
      (n: number) => {
        let events: AppEvent[] = [];
        for (const i of range(1, n))
          events = appendEvent(
            events,
            {
              kind: "growth-undo",
              color: "w",
              line: `${i}`,
              all: false,
              via: "growth",
            },
            i,
          );
        return {
          kept: events.length,
          first: events[0]?.at ?? null,
          last: events.at(-1)?.at ?? null,
          cap: EVENT_CAP,
        };
      },
      [[1], [1000], [1001], [1050]],
    ),
    cases(
      "events.normalizeEvents",
      "A saved log of any shape: a list keeps its newest 1000, anything else is empty.",
      (saved: unknown) => normalizeEvents(saved).length,
      [[null], [{}], [[]], [range(1, 1200)]],
    ),
    cases(
      "events.removedBetween",
      "What a delete took: every line of the old tree that lost a move, whole (at most 20 listed), and how many moves went.",
      (lines: string[], cut: string) => {
        const before = rep(lines);
        const after = pruneLine(before, nodeAtLine(before, split(cut))!.id);
        return removedBetween(before, after);
      },
      [
        [["d4 d5 c4 c5 cxd5 Qxd5 Nc3"], "d4 d5 c4 c5 cxd5"],
        [["e4 e5 Nf3 Nc6 Bb5", "e4 e5 Nf3 Nc6 Bc4", "e4 c5 Nf3"], "e4 e5"],
        [
          ["a6", "a5", "b6", "b5", "c6", "c5", "d6", "d5", "e6"].flatMap((b) =>
            ["Nf3", "Nc3", "d4"].map((w) => `e4 ${b} ${w}`),
          ),
          "e4",
        ],
      ],
    ),
    cases(
      "cloud.describeStatus",
      "The Sync row's status line.",
      (status: CloudStatus) =>
        pinnedClock(
          () => Date.parse("2026-10-31T12:00:00Z"),
          () => describeStatus(status),
        ),
      (
        [
          { kind: "unavailable" },
          { kind: "syncing" },
          { kind: "idle", lastSyncedAt: null },
          { kind: "idle", lastSyncedAt: Date.parse("2026-10-31T11:59:30Z") },
          { kind: "synced", lastSyncedAt: Date.parse("2026-10-31T11:40:00Z") },
          { kind: "synced", lastSyncedAt: Date.parse("2026-10-31T09:00:00Z") },
          { kind: "synced", lastSyncedAt: Date.parse("2026-10-28T12:00:00Z") },
          { kind: "too-large", bytes: 250_000 },
          { kind: "error", message: "Sync failed" },
        ] as CloudStatus[]
      ).map((s) => [s] as [CloudStatus]),
    ),
    cases(
      "store.resetProgress",
      "Reset progress: what it clears and what it keeps.",
      () =>
        pinnedClock(
          () => Date.parse("2026-10-31T12:00:00Z"),
          () => {
            fresh();
            const s = useStore.getState;
            s().addLine(s().ensureRepertoire("w"), split("e4 e5 Nf3"), "book");
            useStore.setState({
              cards: { a: {} as never },
              lineCards: { b: {} as never },
              log: [{} as never],
              mistakes: [{} as never],
              score: {
                ...s().score,
                nodes: {
                  e4: { ...(s().score.nodes.e4 ?? {}), rating: 300 } as never,
                },
              },
            });
            s().resetProgress();
            const st = s();
            return {
              cards: Object.keys(st.cards).length,
              lineCards: Object.keys(st.lineCards).length,
              log: st.log.length,
              mistakes: st.mistakes.length,
              ratings: Object.keys(st.score.nodes).length,
              playbookMoves: repertoireList(st).reduce(
                (n, r) => n + Object.keys(r.nodes).length,
                0,
              ),
              events: st.events.length,
            };
          },
        ),
      [[]],
    ),
  ],
};

export default file;
