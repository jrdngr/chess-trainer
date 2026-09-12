import { applySan, fenTurn, fullmoveNumber, START_FEN } from './core';

export interface PgnNode {
  san: string;
  comment?: string;
  nags: string[];
  /** children[0] is the main continuation; the rest are variations of it. */
  children: PgnNode[];
}

export interface PgnGame {
  headers: Record<string, string>;
  /** First moves of the game; [0] is the mainline. */
  moves: PgnNode[];
  result: string;
}

const RESULTS = new Set(['1-0', '0-1', '1/2-1/2', '*']);

type Token =
  | { t: 'move'; san: string }
  | { t: 'open' }
  | { t: 'close' }
  | { t: 'comment'; text: string }
  | { t: 'nag'; value: string }
  | { t: 'result'; value: string };

function tokenizeMovetext(text: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  while (i < text.length) {
    const ch = text[i];
    if (/\s/.test(ch)) {
      i += 1;
    } else if (ch === '{') {
      const end = text.indexOf('}', i);
      const stop = end === -1 ? text.length : end;
      tokens.push({ t: 'comment', text: text.slice(i + 1, stop).trim() });
      i = stop + 1;
    } else if (ch === ';') {
      const end = text.indexOf('\n', i);
      const stop = end === -1 ? text.length : end;
      tokens.push({ t: 'comment', text: text.slice(i + 1, stop).trim() });
      i = stop + 1;
    } else if (ch === '(') {
      tokens.push({ t: 'open' });
      i += 1;
    } else if (ch === ')') {
      tokens.push({ t: 'close' });
      i += 1;
    } else if (ch === '$') {
      let j = i + 1;
      while (j < text.length && /\d/.test(text[j])) j += 1;
      tokens.push({ t: 'nag', value: text.slice(i, j) });
      i = j;
    } else if (ch === '<' || ch === '>') {
      i += 1;
    } else {
      let j = i;
      while (j < text.length && !/[\s{}()<>;]/.test(text[j])) j += 1;
      const word = text.slice(i, j);
      i = j;
      if (RESULTS.has(word)) {
        tokens.push({ t: 'result', value: word });
      } else {
        // Strip move numbers and dots: "12." "12..." "12.Nf3" are all valid.
        const san = word.replace(/^\d+\.*/, '').replace(/^\.+/, '');
        if (san && !/^\d+$/.test(san)) {
          // Drop decorations chess.js does not need.
          tokens.push({ t: 'move', san: san.replace(/[?!]+$/, '') });
        }
      }
    }
  }
  return tokens;
}

/**
 * Parse a movetext token stream into a move tree.
 *
 * A `( ... )` group is an alternative to the move that immediately precedes it,
 * so its moves become siblings of that move rather than continuations of it.
 */
function parseMoves(tokens: Token[], start: number, out: PgnNode[]): { end: number; result: string } {
  // `line` is the list the next move is appended to; `last` is the move it follows.
  let siblings = out;
  let last: PgnNode | null = null;
  let prevSiblings = out;
  let result = '*';
  let i = start;

  while (i < tokens.length) {
    const tok = tokens[i];
    if (tok.t === 'close') return { end: i + 1, result };
    if (tok.t === 'result') {
      result = tok.value;
      i += 1;
    } else if (tok.t === 'move') {
      const node: PgnNode = { san: tok.san, nags: [], children: [] };
      siblings.push(node);
      prevSiblings = siblings;
      last = node;
      siblings = node.children;
      i += 1;
    } else if (tok.t === 'comment') {
      if (last) last.comment = last.comment ? `${last.comment} ${tok.text}` : tok.text;
      i += 1;
    } else if (tok.t === 'nag') {
      if (last) last.nags.push(tok.value);
      i += 1;
    } else if (tok.t === 'open') {
      // Variation on `last`: parse into the list `last` itself belongs to.
      const inner: PgnNode[] = [];
      const sub = parseMoves(tokens, i + 1, inner);
      i = sub.end;
      for (const n of inner) prevSiblings.push(n);
    } else {
      i += 1;
    }
  }
  return { end: i, result };
}

export function parsePgn(pgn: string): PgnGame[] {
  const games: PgnGame[] = [];
  const text = pgn.replace(/\r\n?/g, '\n');
  // Split on a header block that follows a blank line.
  const chunks = text
    .split(/\n\s*\n(?=\[)/)
    .flatMap((chunk) => chunk.trim())
    .filter(Boolean);

  // Re-join header/movetext pairs: a chunk that is only headers belongs with
  // the chunk after it.
  const merged: string[] = [];
  for (const chunk of chunks) {
    const onlyHeaders = chunk.split('\n').every((l) => l.trim().startsWith('[') || !l.trim());
    if (onlyHeaders && merged.length === 0) merged.push(chunk);
    else if (onlyHeaders) merged.push(chunk);
    else if (merged.length && merged[merged.length - 1].split('\n').every((l) => l.trim().startsWith('[') || !l.trim()))
      merged[merged.length - 1] += `\n\n${chunk}`;
    else merged.push(chunk);
  }

  for (const chunk of merged) {
    const headers: Record<string, string> = {};
    const lines = chunk.split('\n');
    const bodyLines: string[] = [];
    for (const line of lines) {
      const m = /^\s*\[(\w+)\s+"([^"]*)"\]\s*$/.exec(line);
      if (m) headers[m[1]] = m[2];
      else bodyLines.push(line);
    }
    const body = bodyLines.join('\n').trim();
    if (!body && !Object.keys(headers).length) continue;
    const moves: PgnNode[] = [];
    const { result } = parseMoves(tokenizeMovetext(body), 0, moves);
    if (!moves.length && !Object.keys(headers).length) continue;
    games.push({ headers, moves, result: headers.Result ?? result });
  }
  return games;
}

/** Mainline SAN moves of a parsed game, validated against the rules. */
export function mainline(game: PgnGame, startFen = START_FEN): string[] {
  const out: string[] = [];
  let fen = game.headers.FEN ?? startFen;
  let nodes = game.moves;
  while (nodes.length) {
    const node = nodes[0];
    const move = applySan(fen, node.san);
    if (!move) break;
    out.push(move.san);
    fen = move.after;
    nodes = node.children;
  }
  return out;
}

export interface PgnLine {
  sans: string[];
  comment?: string;
  /** Depth at which this line diverged from the mainline. */
  branchPly: number;
}

/** Flatten a parsed game into every distinct line (mainline + variations). */
export function allLines(game: PgnGame, startFen = START_FEN, maxLines = 200): PgnLine[] {
  const out: PgnLine[] = [];
  const rootFen = game.headers.FEN ?? startFen;

  const walk = (nodes: PgnNode[], fen: string, sans: string[], branchPly: number) => {
    if (out.length >= maxLines) return;
    if (!nodes.length) {
      if (sans.length) out.push({ sans, branchPly });
      return;
    }
    nodes.forEach((node, idx) => {
      const move = applySan(fen, node.san);
      if (!move) return;
      walk(node.children, move.after, [...sans, move.san], idx === 0 ? branchPly : sans.length);
    });
  };

  walk(game.moves, rootFen, [], 0);
  return out;
}

export interface PgnExportNode {
  san: string;
  comment?: string;
  children: PgnExportNode[];
}

/** Render a move tree back to PGN movetext with variations. */
export function renderMovetext(nodes: PgnExportNode[], startFen = START_FEN): string {
  const parts: string[] = [];

  const render = (list: PgnExportNode[], fen: string, forceNumber: boolean) => {
    if (!list.length) return;
    const [main, ...variations] = list;
    const move = applySan(fen, main.san);
    if (!move) return;
    const turn = fenTurn(fen);
    const num = fullmoveNumber(fen);
    if (turn === 'w') parts.push(`${num}.`);
    else if (forceNumber) parts.push(`${num}...`);
    parts.push(main.san);
    if (main.comment) parts.push(`{${main.comment}}`);

    for (const variation of variations) {
      parts.push('(');
      render([variation, ...[]], fen, true);
      parts.push(')');
    }
    render(main.children, move.after, variations.length > 0);
  };

  render(nodes, startFen, false);
  return parts
    .join(' ')
    .replace(/\(\s+/g, '(')
    .replace(/\s+\)/g, ')')
    .replace(/(\d+\.)\s+/g, '$1 ')
    .trim();
}

export function toPgn(
  headers: Record<string, string>,
  nodes: PgnExportNode[],
  startFen = START_FEN,
): string {
  const head = Object.entries(headers)
    .map(([k, v]) => `[${k} "${v}"]`)
    .join('\n');
  const body = renderMovetext(nodes, startFen);
  const result = headers.Result ?? '*';
  return `${head}\n\n${body} ${result}\n`;
}

/** Wrap long movetext for readability. */
export function wrapPgn(text: string, width = 80): string {
  const words = text.split(' ');
  const lines: string[] = [];
  let line = '';
  for (const w of words) {
    if (line.length + w.length + 1 > width) {
      lines.push(line);
      line = w;
    } else {
      line = line ? `${line} ${w}` : w;
    }
  }
  if (line) lines.push(line);
  return lines.join('\n');
}
