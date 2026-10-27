import type { isWebFunnelOrigin } from './webFunnel';

import { getWebFunnelVisitId } from './webFunnel';

const visitId = '4b1ba9fc-3d32-438e-872a-f2ed83fb375b';

it('captures a single visit UUID independently of marketing or referral parameters', () => {
  expect(getWebFunnelVisitId(`?r=alice&mw_visit_id=${visitId}&utm_source=tc`)).toBe(visitId);
  expect(getWebFunnelVisitId('')).toBeNull();
});

it.each([
  '?mw_visit_id=', '?mw_visit_id=wrong', `?mw_visit_id=${visitId}&mw_visit_id=${visitId}`,
  `?mw_visit_id=${visitId.toUpperCase()}`, '?mw_visit_id=4b1ba9fc-3d32-138e-872a-f2ed83fb375b',
])('rejects ambiguous or malformed handoff %s', (search) => {
  expect(getWebFunnelVisitId(search)).toBeNull();
});

async function loadOriginGate(isGram: boolean, env: string) {
  const previous = { APP_ENV: process.env.APP_ENV, IS_GRAM_WALLET: process.env.IS_GRAM_WALLET };
  process.env.APP_ENV = env;
  process.env.IS_GRAM_WALLET = isGram ? '1' : '0';
  try {
    let gate!: typeof isWebFunnelOrigin;
    await jest.isolateModulesAsync(async () => {
      ({ isWebFunnelOrigin: gate } = await import('./webFunnel'));
    });
    return gate;
  } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

it.each([
  ['https://web.mywallet.io', false, 'production', true],
  ['https://wallet.ton.org', true, 'production', true],
  ['https://web-beta.mywallet.io', false, 'staging', true],
  ['https://beta.mywallet.io', false, 'staging', false],
  ['https://beta.wallet.ton.org', true, 'staging', false],
  ['https://web-beta.mywallet.io', true, 'staging', false],
  ['https://wallet.ton.org', true, 'staging', false],
  ['https://deploy-preview-42--beta-gramwallet-app.netlify.app', true, 'staging', false],
  ['https://web.mywallet.io', true, 'production', false],
  ['https://wallet.ton.org', false, 'production', false],
  ['https://beta.mywallet.io', false, 'production', false],
  ['https://web-beta.mywallet.io', false, 'production', false],
  ['https://web.mywallet.io', false, 'staging', false],
  ['https://mytonwallet.app', false, 'production', false],
  ['http://web.mywallet.io', false, 'production', false],
  ['https://web.mywallet.io:1235', false, 'production', false],
  ['http://localhost:1235', false, 'development', false],
])('gates %s brand=%s env=%s', async (origin, isGram, env, expected) => {
  const isAllowed = await loadOriginGate(isGram, env);
  expect(isAllowed(origin)).toBe(expected);
});
