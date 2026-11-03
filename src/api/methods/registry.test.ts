import type { Methods } from './types';

jest.mock('.', () => ({ ping: jest.fn() }));
jest.mock('./extra', () => ({
  loadExploreSites: jest.fn(),
  perpsGetAssets: jest.fn(),
  perpsExecuteReviewedOrder: jest.fn(),
  initPerpsTrading: jest.fn(),
}));
jest.mock('./agentV2', () => ({ getAgentV2RuntimeStatus: jest.fn(), getAgentV2NewsFeed: jest.fn() }));

const ORIGINAL_FLAG = process.env.NO_EXTRA_FEATURES;

describe('API method registry', () => {
  afterEach(() => {
    if (ORIGINAL_FLAG === undefined) {
      delete process.env.NO_EXTRA_FEATURES;
    } else {
      process.env.NO_EXTRA_FEATURES = ORIGINAL_FLAG;
    }
    jest.resetModules();
  });

  it('registers the optional methods by default', () => {
    delete process.env.NO_EXTRA_FEATURES;
    const methods = loadRegistry();

    expect(methods.loadExploreSites).toEqual(expect.any(Function));
    expect(methods.getAgentV2RuntimeStatus).toEqual(expect.any(Function));
    expect(methods.getAgentV2NewsFeed).toEqual(expect.any(Function));
  });

  it('omits the Perps methods while Perps is disabled', () => {
    delete process.env.NO_EXTRA_FEATURES;
    const methods = loadRegistry() as unknown as AnyLiteral;

    expect(methods.perpsGetAssets).toBeUndefined();
    expect(methods.perpsExecuteReviewedOrder).toBeUndefined();
    expect(methods.initPerpsTrading).toBeUndefined();
    expect(methods.loadExploreSites).toEqual(expect.any(Function));
  });

  it('omits the optional methods under `NO_EXTRA_FEATURES`, keeping the common half', () => {
    process.env.NO_EXTRA_FEATURES = '1';
    const methods = loadRegistry();

    expect(methods.loadExploreSites).toBeUndefined();
    expect(methods.getAgentV2RuntimeStatus).toBeUndefined();
    expect(methods.getAgentV2NewsFeed).toBeUndefined();
    expect(methods as unknown as AnyLiteral).toHaveProperty('ping');
  });
});

function loadRegistry() {
  let methods: Methods | undefined;

  jest.isolateModules(() => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    ({ methods } = require('./registry') as typeof import('./registry'));
  });

  return methods!;
}
