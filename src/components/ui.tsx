import { useEffect, useRef, useState, type ReactNode } from 'react';

/* ── icons ─────────────────────────────────────────────────────────────── */
type IconProps = { size?: number; filled?: boolean };
const s = (p: IconProps) => ({
  width: p.size ?? 22,
  height: p.size ?? 22,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
});

export const Icons = {
  train: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M13 2 4.5 13.5H11L10 22l8.5-11.5H13z" fill={p.filled ? 'currentColor' : 'none'} />
    </svg>
  ),
  tree: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <circle cx="6" cy="5" r="2.5" fill={p.filled ? 'currentColor' : 'none'} />
      <circle cx="6" cy="19" r="2.5" fill={p.filled ? 'currentColor' : 'none'} />
      <circle cx="18" cy="9" r="2.5" fill={p.filled ? 'currentColor' : 'none'} />
      <path d="M6 7.5v9M18 11.5c0 3-2.5 4-6 4H9" />
    </svg>
  ),
  book: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <circle cx="12" cy="12" r="9" fill={p.filled ? 'currentColor' : 'none'} />
      <path
        d="m15.5 8.5-2 5-5 2 2-5z"
        fill={p.filled ? 'var(--bg)' : 'none'}
        stroke={p.filled ? 'var(--bg)' : 'currentColor'}
      />
    </svg>
  ),
  chart: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M3 13.5 8 8l4 4 4.5-6L21 9" />
      <path d="M3 20h18" opacity={p.filled ? 1 : 0.5} />
    </svg>
  ),
  gear: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z" />
    </svg>
  ),
  back: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M15 5l-7 7 7 7" />
    </svg>
  ),
  close: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  ),
  plus: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M12 5v14M5 12h14" />
    </svg>
  ),
  check: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={3}>
      <path d="M5 12.5l4.5 4.5L19 7" />
    </svg>
  ),
  cross: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={3}>
      <path d="M7 7l10 10M17 7L7 17" />
    </svg>
  ),
  flip: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M4 8h13a3 3 0 0 1 3 3v1M20 16H7a3 3 0 0 1-3-3v-1" />
      <path d="M7 5L4 8l3 3M17 13l3 3-3 3" />
    </svg>
  ),
  chevron: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M9 5l7 7-7 7" />
    </svg>
  ),
  prev: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M15 5l-7 7 7 7" />
    </svg>
  ),
  next: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M9 5l7 7-7 7" />
    </svg>
  ),
  first: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M17 5l-7 7 7 7M7 5v14" />
    </svg>
  ),
  last: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M7 5l7 7-7 7M17 5v14" />
    </svg>
  ),
  download: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M12 3v12M7.5 10.5L12 15l4.5-4.5" />
      <path d="M4 19h16" />
    </svg>
  ),
  trash: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M4 6h16M9 6V4h6v2M7 6l1 14h8l1-14" />
    </svg>
  ),
  star: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path
        d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1.1 5.9-5.3-2.9-5.3 2.9 1.1-5.9L3.5 9.7l5.9-.8z"
        fill={p.filled ? 'currentColor' : 'none'}
      />
    </svg>
  ),
  note: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M5 4h14v11l-5 5H5z" />
      <path d="M19 15h-5v5" />
      <path d="M8.5 8.5h7M8.5 12h4" />
    </svg>
  ),
  bolt: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M13 2L5 13h6l-1 9 8-11h-6z" />
    </svg>
  ),
  more: (p: IconProps = {}) => (
    <svg {...s(p)} fill="currentColor" stroke="none">
      <circle cx="5" cy="12" r="2" />
      <circle cx="12" cy="12" r="2" />
      <circle cx="19" cy="12" r="2" />
    </svg>
  ),
  play: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M7 4.5v15l12-7.5z" fill="currentColor" />
    </svg>
  ),
  up: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M12 19V5M5 12l7-7 7 7" />
    </svg>
  ),
  down: (p: IconProps = {}) => (
    <svg {...s(p)} strokeWidth={2.4}>
      <path d="M12 5v14M5 12l7 7 7-7" />
    </svg>
  ),
  warn: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M12 3 2.5 20h19z" />
      <path d="M12 9v5M12 17.5v.5" />
    </svg>
  ),
  cloud: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M7 18h10a4 4 0 0 0 .5-8 6 6 0 0 0-11.4 1.6A3.3 3.3 0 0 0 7 18z" />
    </svg>
  ),
};

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
 * permadeath post-mortem colour the move that ended a run.
 */
export function Strip({
  items,
  cursor,
  max,
  onSeek,
  hint,
}: {
  items: StripItem[];
  cursor: number;
  /** Highest cursor position the forward arrow can reach. */
  max: number;
  onSeek: (n: number) => void;
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
      <IconButton label="Start" onClick={() => onSeek(0)} disabled={cursor === 0}>
        <Icons.first size={18} />
      </IconButton>
      <IconButton label="Back" onClick={() => onSeek(cursor - 1)} disabled={cursor === 0}>
        <Icons.prev size={18} />
      </IconButton>
      <div className="strip" ref={strip}>
        {items.length === 0 && hint && <span className="hint">{hint}</span>}
        {items.map((item, i) => (
          <button
            key={i}
            className={`mv${item.current ? ' current' : ''}${item.tone ? ` ${item.tone}` : ''}`}
            onClick={() => item.seek !== undefined && onSeek(item.seek)}
          >
            {item.label && <span className="n">{item.label}</span>}
            {item.san}
          </button>
        ))}
      </div>
      <IconButton label="Forward" onClick={() => onSeek(cursor + 1)} disabled={cursor >= max}>
        <Icons.next size={18} />
      </IconButton>
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
