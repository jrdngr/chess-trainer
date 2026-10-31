import { defineConfig } from '@playwright/test';

/**
 * The browser safety net: whole flows played against a fixed-depth engine,
 * with a seeded `Math.random` and a fake clock, recorded as traces. A change
 * that should not alter what a player sees must leave every trace as it was.
 * `npm run e2e`; `npm run e2e -- -u` to record new traces on purpose.
 */
export default defineConfig({
  testDir: 'e2e',
  timeout: 300_000,
  fullyParallel: true,
  reporter: 'list',
  snapshotPathTemplate: '{testDir}/traces/{arg}{ext}',
  use: { viewport: { width: 400, height: 860 } },
  webServer: {
    command: 'npx vite --port 4181 --strictPort',
    url: 'http://localhost:4181',
    reuseExistingServer: true,
  },
});
