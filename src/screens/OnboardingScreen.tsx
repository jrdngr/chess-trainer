import { useMemo, useState } from 'react';
import { fenTurn, walkSan, type Color } from '../chess/core';
import { BoardScreen, type BoardLine } from './BoardScreen';
import { openingsIn } from '../model/openings';
import { pathTo, subtreeIds } from '../model/repertoire';
import { AppBar, IconButton, Icons } from '../components/ui';
import { MiniBoard, OpeningPicker, selectionTrail, shortLabel } from '../components/Selection';
import { PlateBoard, PrepSegments, SideSquare } from '../components/OpeningPlate';
import { roundSpan } from '../model/autopilot';
import { openingTree } from '../model/openingTree';
import { referenceIndex } from '../model/referenceIndex';
import {
  countOwnMoves,
  seedFor,
  seedLines,
  setOpenings,
  setSeed,
  SLOT_COLOR,
  SLOT_LABELS,
  STARTER_SETS,
  type SeedLine,
  type SeedOpening,
  type SetSlot,
  type StarterSet,
} from '../model/starterSets';
import { NO_HISTORY, pickRound } from '../store/recommendation';
import { repertoireList, useStore } from '../store/useStore';

/**
 * The first screens a new profile sees: building the first Playbook.
 *
 * Everything in the app works on a Playbook, and a fresh install has none.
 * There are two ways in: a starter set, picked by style, or the openings you
 * already play, picked one at a time. A starter set's openings go in a few
 * of your moves past their names (see `seedLines`), so the first Autopilot
 * run has prep to drill; an opening you pick goes in as exactly the moves you
 * picked, since nothing past them was ever shown to you.
 *
 * Skipping is a real answer, not a failure. It leaves the profile as it was
 * and is never asked again, short of a full reset.
 */

type Step =
  | { kind: 'path' }
  | { kind: 'sets' }
  | { kind: 'set'; id: string }
  | { kind: 'pick' }
  | { kind: 'board' }
  | { kind: 'ready' };

/** One opening as the ready screen lists what went in. */
interface AddedRow {
  key: string;
  name: string;
  color: Color;
  moves: number;
}

/** A picked opening, waiting to go in. */
interface Picked {
  sans: string[];
  color: Color;
  name: string;
}

export function OnboardingScreen({ onDone }: { onDone: (next: 'autopilot' | 'home') => void }) {
  const finishOnboarding = useStore((s) => s.finishOnboarding);
  const [step, setStep] = useState<Step>({ kind: 'path' });
  /** Everything put in so far: the ready screen can send you back to pick more. */
  const [added, setAdded] = useState<AddedRow[]>([]);

  const ready = (rows: AddedRow[]) => {
    setAdded((had) => [...had.filter((row) => !rows.some((r) => r.key === row.key)), ...rows]);
    setStep({ kind: 'ready' });
  };

  const finish = (openings: SeedOpening[], rows: AddedRow[], plays?: [string, string][]) => {
    finishOnboarding(openings, plays);
    ready(rows);
  };

  const skip = () => {
    finishOnboarding([]);
    onDone('home');
  };

  if (step.kind === 'sets') {
    return <SetList onBack={() => setStep({ kind: 'path' })} onOpen={(id) => setStep({ kind: 'set', id })} />;
  }
  if (step.kind === 'set') {
    const set = STARTER_SETS.find((s) => s.id === step.id)!;
    return (
      <SetDetail
        set={set}
        onBack={() => setStep({ kind: 'sets' })}
        onUse={() => finish(setSeed(set), setRows(set), set.plays)}
      />
    );
  }
  if (step.kind === 'pick') {
    return (
      <PickOpenings
        onBack={() => setStep({ kind: added.length ? 'ready' : 'path' })}
        onAdd={(picked) => {
          // Exactly the moves you picked: nothing past them goes in unseen.
          finishOnboarding(
            picked.map((pick) => seedFor(pick.sans, pick.color)),
            [],
            { seed: false },
          );
          ready(
            picked.map((pick) => ({
              key: pick.sans.join(' '),
              name: pick.name,
              color: pick.color,
              moves: countOwnMoves([seedFor(pick.sans, pick.color)]),
            })),
          );
        }}
      />
    );
  }
  if (step.kind === 'board') {
    return (
      <BoardScreen
        onBack={() => setStep({ kind: 'path' })}
        onDone={(saved) => {
          if (!saved.length) {
            setStep({ kind: 'path' });
            return;
          }
          const rows = boardRows(saved);
          finishOnboarding(
            rows.map((row) => ({ sans: row.path, color: row.color })),
            [],
            { seed: false },
          );
          ready(rows);
        }}
      />
    );
  }
  if (step.kind === 'ready') return <Ready rows={added} onMore={() => setStep({ kind: 'pick' })} onDone={onDone} />;

  return (
    <>
      <AppBar title="Build your Playbook" large />
      <div className="screen no-nav onboard">
        <div className="onboard-paths">
          <button className="onboard-path main" onClick={() => setStep({ kind: 'sets' })}>
            <span className="ico">
              <Icons.star size={22} />
            </span>
            <span className="name">Suggest a set</span>
            <Icons.chevron size={18} />
          </button>
          <button className="onboard-path" onClick={() => setStep({ kind: 'pick' })}>
            <span className="ico">
              <Icons.tree size={22} />
            </span>
            <span className="name">Pick openings</span>
            <Icons.chevron size={18} />
          </button>
          <button className="onboard-path" onClick={() => setStep({ kind: 'board' })}>
            <span className="ico">
              <Icons.play size={22} />
            </span>
            <span className="name">Play on the board</span>
            <Icons.chevron size={18} />
          </button>
        </div>
        <button className="onboard-skip" onClick={skip}>
          Skip for now
        </button>
      </div>
    </>
  );
}

/* ── starter sets ─────────────────────────────────────────────────────── */

/** An opening's name as a set shows it: the set's own label, else the book's, shortened. */
function openingName(id: string, label?: string): string {
  if (label) return label;
  const node = openingTree(referenceIndex()).byId.get(id);
  return node ? shortLabel(node.name) : id;
}

/** A slot's openings by name, the same name once. */
function slotNames(set: StarterSet, slot: SetSlot): string[] {
  return [...new Set(set.slots[slot].map((opening) => openingName(opening.id, opening.label)))];
}

/** Your moves a set puts in, all of them or one slot's. */
function setMoves(set: StarterSet, slot?: SetSlot): number {
  const openings = setOpenings(set).filter((opening) => !slot || opening.slot === slot);
  // Seeded with the whole set, so a slot counts the moves the set really plays.
  const lines = seedLines(referenceIndex(), setSeed(set), set.plays);
  const mine = (line: SeedLine) =>
    openings.some((opening) => opening.color === line.color && `${line.sans.join(' ')} `.startsWith(`${opening.id} `));
  return countOwnMoves(lines.filter(mine));
}

function setRows(set: StarterSet): AddedRow[] {
  return (Object.keys(set.slots) as SetSlot[]).map((slot) => ({
    key: slot,
    name: slotNames(set, slot).join(' · '),
    color: SLOT_COLOR[slot],
    moves: setMoves(set, slot),
  }));
}

function SetList({ onBack, onOpen }: { onBack: () => void; onOpen: (id: string) => void }) {
  const totals = useMemo(() => new Map(STARTER_SETS.map((set) => [set.id, setMoves(set)])), []);
  return (
    <>
      <AppBar title="Pick a style" large onBack={onBack} />
      <div className="screen no-nav onboard">
        {STARTER_SETS.map((set) => (
          <button key={set.id} className="card tap onboard-set" onClick={() => onOpen(set.id)}>
            <span className="top">
              <span className="title">{set.name}</span>
              <span className="count">{totals.get(set.id)} moves</span>
            </span>
            <span className="desc">{set.description}</span>
            <span className="chips">
              {(Object.keys(set.slots) as SetSlot[]).map((slot) => (
                <span key={slot} className="onboard-chip">
                  <SideSquare color={SLOT_COLOR[slot]} />
                  {slotNames(set, slot).join(' · ')}
                </span>
              ))}
            </span>
          </button>
        ))}
      </div>
    </>
  );
}

function SetDetail({ set, onBack, onUse }: { set: StarterSet; onBack: () => void; onUse: () => void }) {
  const rows = useMemo(() => setRows(set), [set]);
  return (
    <>
      <AppBar title={set.name} large onBack={onBack} />
      <div className="screen no-nav onboard">
        <p className="onboard-desc">{set.description}</p>
        {rows.map((row) => {
          const slot = row.key as SetSlot;
          const first = set.slots[slot][0];
          return (
            <div key={slot} className="card onboard-slot">
              <MiniBoard sans={first.id.split(' ')} orientation={row.color} size={88} lastMove />
              <span className="info">
                <span className="label">
                  <SideSquare color={row.color} />
                  {SLOT_LABELS[slot]}
                </span>
                <span className="name">{row.name}</span>
                <span className="count">{row.moves} moves</span>
              </span>
            </div>
          );
        })}
      </div>
      <div className="onboard-bar">
        <button className="btn accent block xl" onClick={onUse}>
          Use {set.name}
        </button>
      </div>
    </>
  );
}

/* ── picking openings ─────────────────────────────────────────────────── */

function PickOpenings({ onBack, onAdd }: { onBack: () => void; onAdd: (picked: Picked[]) => void }) {
  const [picked, setPicked] = useState<Picked[]>([]);
  const [picking, setPicking] = useState(false);

  const add = (sans: string[], side: Color | null) => {
    const key = sans.join(' ');
    if (picked.some((pick) => pick.sans.join(' ') === key)) return;
    const node = openingTree(referenceIndex()).byId.get(key);
    const { color } = seedFor(sans, side ?? undefined);
    setPicked([...picked, { sans, color, name: node ? shortLabel(node.name) : key }]);
  };

  return (
    <>
      <AppBar title="Your openings" large onBack={onBack} />
      <div className="screen no-nav onboard">
        {picked.length > 0 && (
          <div className="list onboard-picked">
            {picked.map((pick, i) => (
              <div key={pick.sans.join(' ')} className="list-row">
                <SideSquare color={pick.color} />
                <span className="title grow name-wrap">{pick.name}</span>
                <IconButton label={`Remove ${pick.name}`} onClick={() => setPicked(picked.filter((_, j) => j !== i))}>
                  <Icons.close size={16} />
                </IconButton>
              </div>
            ))}
          </div>
        )}
        <button className="btn soft block onboard-add" onClick={() => setPicking(true)}>
          <Icons.plus size={18} />
          Add an opening
        </button>
      </div>
      <div className="onboard-bar">
        <button
          className={`btn block xl${picked.length ? ' accent' : ''}`}
          disabled={!picked.length}
          onClick={() => onAdd(picked)}
        >
          <span className="truncate">
            {picked.length === 1 ? `Add ${picked[0].name}` : `Add ${picked.length || ''} openings`.replace('  ', ' ')}
          </span>
        </button>
      </div>
      <OpeningPicker open={picking} onClose={() => setPicking(false)} onChoose={add} />
    </>
  );
}

/* ── played on the board ──────────────────────────────────────────────── */

/**
 * What the board put in, as the Playbook lists it: each opening a saved line
 * ends in, with your moves in it. Read from the store, since the Save sheet
 * has already written the lines.
 */
function boardRows(saved: BoardLine[]): (AddedRow & { path: string[] })[] {
  const state = useStore.getState();
  const index = referenceIndex();
  const rows = new Map<string, AddedRow & { path: string[] }>();
  for (const rep of repertoireList(state)) {
    const tips = saved
      .filter((line) => line.color === rep.color)
      .map((line) => {
        const fen = walkSan(line.sans).fens.at(-1);
        return Object.values(rep.nodes).find((node) => node.fenAfter === fen && node.san === line.sans.at(-1));
      })
      .filter((tip) => !!tip);
    for (const opening of openingsIn(rep, index)) {
      const inside = new Set(subtreeIds(rep, opening.rootId));
      const mine = tips.filter((tip) => inside.has(tip.id));
      if (!mine.length) continue;
      // Your moves on the way to each line, the moves before the name included.
      const own = new Set(mine.flatMap((tip) => pathTo(rep, tip.id)).filter((node) => fenTurn(node.fenBefore) === rep.color).map((node) => node.id));
      // An opening called by Black's first move ("1...e5") is starred at that move, as a starter set stars it.
      const path = /^\d/.test(opening.name) ? opening.path.slice(0, 2) : opening.path;
      rows.set(opening.id, { key: opening.id, name: opening.name, color: rep.color, moves: own.size, path });
    }
  }
  return [...rows.values()];
}

/* ── done ─────────────────────────────────────────────────────────────── */

function Ready({
  rows,
  onMore,
  onDone,
}: {
  rows: AddedRow[];
  onMore: () => void;
  onDone: (next: 'autopilot' | 'home') => void;
}) {
  const state = useStore();
  const first = useMemo(() => pickRound(state, NO_HISTORY).round, [state]);
  const span = useMemo(() => {
    if (!first) return null;
    const rep = repertoireList(state).find((r) => r.color === first.pick.color) ?? null;
    return roundSpan(rep, first.pick, first.at);
  }, [state, first]);
  const moves = rows.reduce((sum, row) => sum + row.moves, 0);

  return (
    <>
      <div className="screen no-nav onboard ready">
        <span className="onboard-check">
          <Icons.check size={22} />
        </span>
        <h1>Your Playbook is ready</h1>
        <p className="onboard-desc">
          {moves} moves across {rows.length} {rows.length === 1 ? 'opening' : 'openings'}
        </p>
        <div className="list">
          {rows.map((row) => (
            <div key={row.key} className="list-row">
              <SideSquare color={row.color} />
              <span className="title grow name-wrap">{row.name}</span>
              <span className="val">{row.moves} {row.moves === 1 ? 'move' : 'moves'}</span>
            </div>
          ))}
        </div>
        <button className="btn soft block onboard-add" onClick={onMore}>
          <Icons.plus size={18} />
          Add more openings
        </button>
        <div className="grow" />
        {first && (
          <div className="autopilot-wrap">
            <button className="autopilot plate" onClick={() => onDone('autopilot')}>
              <PlateBoard sans={first.pick.opening.sans} color={first.pick.color} size={176} />
              <span className="plate-tag">
                <Icons.bolt size={11} />
                Autopilot
              </span>
              <SideSquare color={first.pick.color} />
              <span className="name">{selectionTrail(first.pick.opening.id).at(-1)}</span>
              <PrepSegments span={span} className="edge" />
            </button>
          </div>
        )}
      </div>
      <div className="onboard-bar">
        <button className="btn accent block xl" onClick={() => onDone(first ? 'autopilot' : 'home')}>
          {first ? 'Play your first run' : 'Go to Home'}
        </button>
        {first && (
          <button className="onboard-skip" onClick={() => onDone('home')}>
            Go to Home
          </button>
        )}
      </div>
    </>
  );
}
