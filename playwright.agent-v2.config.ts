import type { PlaywrightTestConfig } from '@playwright/test';
import { devices } from '@playwright/test';

const port = Number(process.env.AGENT_E2E_PORT ?? 1235);

const config: PlaywrightTestConfig = {
  testDir: 'tests/playwright/agent-v2',
  timeout: process.env.CI ? 60 * 5 * 1000 : 30 * 1000,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  webServer: {
    command: `npx cross-env APP_ENV=development AGENT_API_URL=http://127.0.0.1:${port}/api vite build --mode development`
      + ' && bash ./deploy/copy_to_dist.sh && node dev/agentV2/e2eServer.mjs',
    port,
    timeout: 180 * 1000,
    reuseExistingServer: !process.env.CI,
  },
  use: {
    baseURL: `http://127.0.0.1:${port}/`,
    video: 'retain-on-failure',
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'agent-v2-chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
};

export default config;
