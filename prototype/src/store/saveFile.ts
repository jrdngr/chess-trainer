/**
 * Offering a file to save.
 *
 * Inside the published artifact the page cannot download on its own: it asks
 * the runtime's `downloads` capability, and the viewer confirms. Anywhere else
 * (running locally) a plain link download does the job.
 */

interface Downloads {
  save(request: { filename: string; data: string | Blob }): Promise<{ status: string }>;
}

interface ClaudeRuntime {
  use(name: string): Promise<unknown>;
}

function runtime(): ClaudeRuntime | null {
  const claude = (globalThis as { claude?: ClaudeRuntime }).claude;
  return claude && typeof claude.use === 'function' ? claude : null;
}

/** Saved, declined by the viewer, or not possible here. */
export type SaveOutcome = 'saved' | 'declined' | 'unavailable';

export async function saveFile(filename: string, text: string): Promise<SaveOutcome> {
  const claude = runtime();
  if (claude) {
    const downloads = (await claude.use('downloads').catch(() => null)) as Downloads | null;
    if (!downloads) return 'unavailable';
    try {
      await downloads.save({ filename, data: text });
      return 'saved';
    } catch (error) {
      return (error as { code?: string })?.code === 'declined' ? 'declined' : 'unavailable';
    }
  }
  const url = URL.createObjectURL(new Blob([text], { type: 'application/json' }));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  return 'saved';
}
