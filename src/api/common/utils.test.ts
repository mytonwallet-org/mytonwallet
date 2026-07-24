// The production backend load-balances `nominatorsPool.address` between these pools (the active
// entries of STAKING_POOLS in the backend config). `fetchBackendStakingState` throws on any address
// missing from the frontend STAKING_POOLS whitelist, which silently kills staking polling, so a
// build with no STAKING_POOLS env var (e.g. the wallet.ton.org deploy or a local Android build)
// must accept every one of them out of the box.
const ACTIVE_BACKEND_NOMINATORS_POOLS = [
  'Ef-WMmizoLk4CvqTKs-mDrGJwW4fiH5zVd4SaHih7PObxP_0',
  'Ef84o4VJRnlp1wsqSHov1QttqSTQda2Z1vGK-b7EaPQoeJMx',
];

function requireIsKnownStakingPool() {
  let isKnownStakingPool: (address: string) => boolean;
  jest.isolateModules(() => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    ({ isKnownStakingPool } = require('./utils'));
  });
  return isKnownStakingPool!;
}

describe('isKnownStakingPool', () => {
  const prevEnv = process.env.STAKING_POOLS;

  afterEach(() => {
    if (prevEnv === undefined) {
      delete process.env.STAKING_POOLS;
    } else {
      process.env.STAKING_POOLS = prevEnv;
    }
  });

  it.each(ACTIVE_BACKEND_NOMINATORS_POOLS)(
    'accepts the backend-served pool %s when STAKING_POOLS env is not set',
    (pool) => {
      delete process.env.STAKING_POOLS;
      const isKnownStakingPool = requireIsKnownStakingPool();

      expect(isKnownStakingPool(pool)).toBe(true);
    },
  );

  it('rejects an address outside the default whitelist', () => {
    delete process.env.STAKING_POOLS;
    const isKnownStakingPool = requireIsKnownStakingPool();

    expect(isKnownStakingPool('Ef8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')).toBe(false);
  });
});
