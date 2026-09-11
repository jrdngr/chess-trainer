import { useEffect, useRef, useState, type ReactNode } from 'react';

/* ── icons ─────────────────────────────────────────────────────────────── */
type IconProps = { size?: number };
const s = (p: IconProps) => ({
  width: p.size ?? 22,
  height: p.size ?? 22,
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.8,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const,
});

export const Icons = {
  train: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M12 3v4M5.6 5.6l2.9 2.9M3 12h4M18.4 5.6l-2.9 2.9M21 12h-4" />
      <circle cx="12" cy="15" r="6" />
      <path d="M12 13v2.2l1.6 1" />
    </svg>
  ),
  tree: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M5 4v12a2 2 0 0 0 2 2h3M5 10h5" />
      <rect x="12" y="2" width="8" height="4" rx="1.4" />
      <rect x="12" y="8" width="8" height="4" rx="1.4" />
      <rect x="12" y="16" width="8" height="4" rx="1.4" />
    </svg>
  ),
  book: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M4 4.5A1.5 1.5 0 0 1 5.5 3H19v15H5.5A1.5 1.5 0 0 0 4 19.5z" />
      <path d="M4 19.5A1.5 1.5 0 0 1 5.5 18H19v3H5.5A1.5 1.5 0 0 1 4 19.5z" />
      <path d="M9 7.5h6M9 11h4" />
    </svg>
  ),
  chart: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M3 20h18" />
      <path d="M6 20v-6M11 20V7M16 20v-9M21 20V4" />
    </svg>
  ),
  gear: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-1.8-.3 1.6 1.6 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1A1.6 1.6 0 0 0 9 19.4a1.6 1.6 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.6 1.6 0 0 0 .3-1.8 1.6 1.6 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1A1.6 1.6 0 0 0 4.6 9a1.6 1.6 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 1.8.3H9a1.6 1.6 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 1 1.5 1.6 1.6 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0-.3 1.8V9a1.6 1.6 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.5 1z" />
    </svg>
  ),
  back: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M15 5l-7 7 7 7" />
    </svg>
  ),
  close: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M6 6l12 12M18 6L6 18" />
    </svg>
  ),
  plus: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M12 5v14M5 12h14" />
    </svg>
  ),
  check: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M4 12.5l5 5L20 6.5" />
    </svg>
  ),
  cross: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <circle cx="12" cy="12" r="9" />
      <path d="M9 9l6 6M15 9l-6 6" />
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
    <svg {...s(p)}>
      <path d="M15 5l-7 7 7 7" />
    </svg>
  ),
  next: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M9 5l7 7-7 7" />
    </svg>
  ),
  first: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M18 5l-7 7 7 7M6 5v14" />
    </svg>
  ),
  last: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <path d="M6 5l7 7-7 7M18 5v14" />
    </svg>
  ),
  search: (p: IconProps = {}) => (
    <svg {...s(p)}>
      <circle cx="11" cy="11" r="6.5" />
      <path d="M20 20l-4.2-4.2" />
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
      <path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1.1 5.9-5.3-2.9-5.3 2.9 1.1-5.9L3.5 9.7l5.9-.8z" />
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
        window.setTimeout(() => setMessage((cur) => (cur === msg ? null : cur)), 2200);
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
export function Empty({ icon, title, hint }: { icon: string; title: string; hint?: string }) {
  return (
    <div className="empty">
      <div className="big">{icon}</div>
      <div style={{ fontWeight: 650, color: 'var(--text-dim)' }}>{title}</div>
      {hint && <div className="tiny" style={{ marginTop: 6 }}>{hint}</div>}
    </div>
  );
}

export function haptic(pattern: number | number[] = 12) {
  try {
    navigator.vibrate?.(pattern);
  } catch {
    /* not supported */
  }
}
