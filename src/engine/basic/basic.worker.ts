import { search, type SearchOptions } from './search';

/** The backup engine off the main thread: one search per message, a reply per finished depth. */
self.onmessage = (event: MessageEvent<{ id: number; fen: string; options: SearchOptions }>) => {
  const { id, fen, options } = event.data;
  const result = search(fen, {
    ...options,
    onDepth: (depth) => self.postMessage({ id, result: depth, done: false }),
  });
  self.postMessage({ id, result, done: true });
};
