/** Line icons on a 24-unit grid, drawn inline so nothing is fetched at runtime. */
export type IconProps = { size?: number; filled?: boolean };
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
