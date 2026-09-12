import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Icons } from './Icons';

export { Icons } from './Icons';

/* ── bottom sheet ──────────────────────────────────────────────────────── */
export interface SheetProps {
  open: boolean;
  onClose: () => void;
  title?: ReactNode;
  actions?: ReactNode;
  children: ReactNode;
}

export function Sheet({ open, onClose, title, actions, children }: SheetProps) {
  const startY = useRef<number | null>(null);
  const sheetRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <>
      <div className="sheet-backdrop" onPointerDown={onClose} />
      <div className="sheet" ref={sheetRef}>
        <div
          className="sheet-grip-zone"
          onPointerDown={(e) => {
            startY.current = e.clientY;
          }}
          onPointerMove={(e) => {
            if (startY.current === null || !sheetRef.current) return;
            const dy = Math.max(0, e.clientY - startY.current);
            sheetRef.current.style.transform = `translateY(${dy}px)`;
          }}
          onPointerUp={(e) => {
            if (startY.current === null || !sheetRef.current) return;
            const dy = e.clientY - startY.current;
            sheetRef.current.style.transform = '';
            startY.current = null;
            if (dy > 90) onClose();
          }}
        >
          <div className="sheet-grip" />
        </div>
        {(title || actions) && (
          <div className="sheet-head">
            {typeof title === 'string' ? <h3 className="truncate">{title}</h3> : title}
            {actions}
          </div>
        )}
        <div className="sheet-body">{children}</div>
      </div>
    </>
  );
}

/* ── toast ─────────────────────────────────────────────────────────────── */
let toastSetter: ((msg: string | null) => void) | null = null;

export function toast(message: string) {
  toastSetter?.(message);
}

export function ToastHost() {
  const [message, setMessage] = useState<string | null>(null);
  useEffect(() => {
    toastSetter = (msg) => {
      setMessage(msg);
      if (msg) {
        window.setTimeout(() => setMessage((cur) => (cur === msg ? null : cur)), 2000);
      }
    };
    return () => {
      toastSetter = null;
    };
  }, []);
  if (!message) return null;
  return <div className="toast">{message}</div>;
}

/* ── misc ──────────────────────────────────────────────────────────────── */
export function Empty({ title, hint }: { title: string; hint?: string }) {
  return (
    <div className="empty">
      <div className="t">{title}</div>
      {hint && <div className="h">{hint}</div>}
    </div>
  );
}

/** Round icon button used in app bars. */
export function IconButton({
  onClick,
  label,
  children,
  plain,
  disabled,
}: {
  onClick: () => void;
  label: string;
  children: ReactNode;
  plain?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      className={`icon-btn${plain ? ' plain' : ''}`}
      onClick={onClick}
      aria-label={label}
      disabled={disabled}
    >
      {children}
    </button>
  );
}

/**
 * The bar at the top of a screen. Large-title screens pass `large`; pushed
 * screens pass `onBack` (a chevron) or `onClose` (a cross). When there is a
 * back button but nothing on the right, a blank keeps the title centred.
 *
 * The title is optional: a screen whose sections name themselves does not need
 * the bar to repeat one of them, and a bar with only its actions in it still
 * holds the safe area and keeps them where the thumb expects.
 */
export function AppBar({
  title,
  subtitle,
  large,
  onBack,
  onClose,
  actions,
}: {
  title?: ReactNode;
  subtitle?: ReactNode;
  large?: boolean;
  onBack?: () => void;
  onClose?: () => void;
  actions?: ReactNode;
}) {
  const leading = onBack ? (
    <IconButton label="Back" onClick={onBack}>
      <Icons.back size={20} />
    </IconButton>
  ) : onClose ? (
    <IconButton label="Close" onClick={onClose}>
      <Icons.close size={20} />
    </IconButton>
  ) : null;
  return (
    <div className={`appbar${large ? '' : ' compact'}`}>
      {leading}
      {title === undefined ? (
        <span className="grow" />
      ) : large ? (
        <h1>{title}</h1>
      ) : (
        <div className="appbar-title">
          <div className="line">{title}</div>
          {subtitle && <div className="sub">{subtitle}</div>}
        </div>
      )}
      {actions ?? (leading && <span className="appbar-gap" />)}
    </div>
  );
}

/** A section heading, with an optional aside on the right. */
export function Section({ title, aside }: { title: ReactNode; aside?: ReactNode }) {
  return (
    <div className="section">
      <span>{title}</span>
      {aside && <span className="faint tiny">{aside}</span>}
    </div>
  );
}

/** One row of a grouped list with a switch on the right. */
export function Toggle({
  label,
  hint,
  on,
  onToggle,
}: {
  label: string;
  hint?: string;
  on: boolean;
  onToggle: () => void;
}) {
  return (
    <button className="list-row" onClick={onToggle} role="switch" aria-checked={on}>
      <span className="grow">
        <div className="title">{label}</div>
        {hint && <div className="meta">{hint}</div>}
      </span>
      <span className={`switch${on ? ' on' : ''}`}>
        <i />
      </span>
    </button>
  );
}

/** One row of a grouped list with a − / + stepper on the right. */
export function Stepper({
  label,
  value,
  min,
  max,
  step,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  onChange: (n: number) => void;
}) {
  return (
    <div className="list-row">
      <span className="grow title">{label}</span>
      <div className="stepper">
        <button onClick={() => onChange(Math.max(min, value - step))} aria-label="Decrease">
          −
        </button>
        <span>{value}</span>
        <button onClick={() => onChange(Math.min(max, value + step))} aria-label="Increase">
          +
        </button>
      </div>
    </div>
  );
}

/** A row of mutually exclusive choices. */
export function Segmented<T extends string>({
  value,
  options,
  onChange,
}: {
  value: T;
  options: { value: T; label: ReactNode }[];
  onChange: (value: T) => void;
}) {
  return (
    <div className="segmented">
      {options.map((option) => (
        <button
          key={option.value}
          className={option.value === value ? 'active' : ''}
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

/** A row of a grouped list that selects one option, ticked when chosen. */
export function ChoiceRow({
  title,
  meta,
  selected,
  leading,
  onSelect,
}: {
  title: ReactNode;
  meta?: ReactNode;
  selected: boolean;
  leading?: ReactNode;
  onSelect: () => void;
}) {
  return (
    <button className="list-row" onClick={onSelect} aria-pressed={selected}>
      {leading}
      <span className="grow">
        <div className="title truncate">{title}</div>
        {meta && <div className="meta truncate">{meta}</div>}
      </span>
      {selected && <Icons.check size={18} />}
    </button>
  );
}

/** How a move reads in the strip. */
export type MoveTone = 'mine' | 'theirs' | 'ghost' | 'bad' | 'good';

export interface StripItem {
  san: string;
  /** Move number shown before the move, e.g. "12.". */
  label?: string;
  tone?: MoveTone;
  current?: boolean;
  /** Cursor position this chip jumps to. Omit to make it unclickable. */
  seek?: number;
}

/**
 * A scrolling row of moves with a cursor and arrows, shared by every board
 * screen. Callers hand over already-decorated items, which is what lets the
 * openingRun post-mortem colour the move that ended a run.
 */
export function Strip({
  items,
  cursor = 0,
  max = 0,
  onSeek,
  hint,
}: {
  items: StripItem[];
  cursor?: number;
  /** Highest cursor position the forward arrow can reach. */
  max?: number;
  /** Omit to render the moves without navigation — a game in progress has
      nowhere to scrub to. */
  onSeek?: (n: number) => void;
  hint?: string;
}) {
  const strip = useRef<HTMLDivElement>(null);

  /** Keep the current move in view — a cursor can start mid-line. */
  useEffect(() => {
    const el = strip.current;
    if (!el || items.length === 0) return;
    const index = items.findIndex((item) => item.current);
    const active = el.children[index < 0 ? 0 : index] as HTMLElement | undefined;
    if (!active) return;
    el.scrollTo({
      left: active.offsetLeft - el.clientWidth / 2 + active.offsetWidth / 2,
      behavior: 'smooth',
    });
  }, [cursor, items]);

  return (
    <div className="strip-wrap">
      {onSeek && (
        <>
          <IconButton label="Start" onClick={() => onSeek(0)} disabled={cursor === 0}>
            <Icons.first size={18} />
          </IconButton>
          <IconButton label="Back" onClick={() => onSeek(cursor - 1)} disabled={cursor === 0}>
            <Icons.prev size={18} />
          </IconButton>
        </>
      )}
      <div className="strip" ref={strip}>
        {items.length === 0 && hint && <span className="hint">{hint}</span>}
        {items.map((item, i) => (
          <button
            key={i}
            className={`mv${item.current ? ' current' : ''}${item.tone ? ` ${item.tone}` : ''}`}
            onClick={() => item.seek !== undefined && onSeek?.(item.seek)}
          >
            {item.label && <span className="n">{item.label}</span>}
            {item.san}
          </button>
        ))}
      </div>
      {onSeek && (
        <IconButton label="Forward" onClick={() => onSeek(cursor + 1)} disabled={cursor >= max}>
          <Icons.next size={18} />
        </IconButton>
      )}
    </div>
  );
}

/** The plain case: a line you are scrubbing, numbered from the start position. */
export function MoveStrip({
  sans,
  cursor,
  onSeek,
  hint,
}: {
  sans: string[];
  cursor: number;
  onSeek: (n: number) => void;
  hint?: string;
}) {
  const items = sans.map((san, i) => ({
    san,
    label: i % 2 === 0 ? `${i / 2 + 1}.` : undefined,
    current: i === cursor - 1,
    tone: i >= cursor ? ('ghost' as const) : undefined,
    seek: i + 1,
  }));
  return <Strip items={items} cursor={cursor} max={sans.length} onSeek={onSeek} hint={hint} />;
}

/**
 * Copy text, falling back to a hidden textarea.
 *
 * `navigator.clipboard` needs a secure context and is often withheld inside a
 * sandboxed frame, which is exactly where this app runs when published.
 */
export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    // Fall through to the old way.
  }
  try {
    const area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.top = '-1000px';
    document.body.appendChild(area);
    area.select();
    area.setSelectionRange(0, text.length);
    const ok = document.execCommand('copy');
    document.body.removeChild(area);
    return ok;
  } catch {
    return false;
  }
}

export function haptic(pattern: number | number[] = 12) {
  try {
    navigator.vibrate?.(pattern);
  } catch {
    /* not supported */
  }
}
