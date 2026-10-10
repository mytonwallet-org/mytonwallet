import { addCallback, removeCallback } from '../../lib/teact/teactn';
import { getGlobal, setGlobal } from '../../global';

import type { GlobalState } from '../../global/types';

import { publishAgentV2Update } from '../../util/agentV2Updates';
import { callApi } from '../../api';
import * as hostContextBuilder from './buildHostContext';
import { startAgentV2HostContextSync } from './hostContextSync';

jest.mock('../../api', () => ({ callApi: jest.fn() }));

const callApiMock = jest.mocked(callApi);
const selectHostContext = jest.spyOn(hostContextBuilder, 'selectAgentV2HostContext');

let stopSync: NoneToVoidFunction | undefined;
let initialGlobal: GlobalState;

beforeEach(() => {
  jest.useFakeTimers();
  initialGlobal = getGlobal();
  stopSync = undefined;
  callApiMock.mockReset();
  callApiMock.mockResolvedValue({ ok: true, value: { generation: 1, authorityChanged: false } });
  selectHostContext.mockClear();
  publishAgentV2Update({ kind: 'runtimeReady', generation: 1 });
});

afterEach(async () => {
  stopSync?.();
  await jest.advanceTimersByTimeAsync(100);
  setGlobal(initialGlobal);
  await jest.advanceTimersByTimeAsync(0);
  jest.useRealTimers();
});

it('coalesces polling updates asynchronously without mounted UI or starving the latest data', async () => {
  stopSync = startAgentV2HostContextSync();
  expect(selectHostContext).not.toHaveBeenCalled();
  await jest.advanceTimersByTimeAsync(100);
  expect(callApiMock).toHaveBeenCalledTimes(1);
  selectHostContext.mockClear();

  for (let rate = 2; rate <= 5; rate++) {
    setGlobal({ ...getGlobal(), currencyRates: { ...getGlobal().currencyRates, USD: String(rate) } });
    await jest.advanceTimersByTimeAsync(1_000);
    expect(selectHostContext).not.toHaveBeenCalled();
  }

  await jest.advanceTimersByTimeAsync(1_000);
  expect(selectHostContext).toHaveBeenCalledTimes(1);
  expect(callApiMock).toHaveBeenCalledTimes(2);
  expect(callApiMock).toHaveBeenLastCalledWith('updateAgentV2HostContext', expect.objectContaining({
    currencyRate: '5',
  }));

  // Equal polling results may have new references, but must not be delivered again.
  setGlobal({ ...getGlobal(), currencyRates: { ...getGlobal().currencyRates } });
  await jest.advanceTimersByTimeAsync(5_000);
  expect(callApiMock).toHaveBeenCalledTimes(2);
});

it('delivers wallet switches and removal promptly even with a polling update pending', async () => {
  setGlobal({
    ...getGlobal(),
    currentAccountId: '0-mainnet',
    accounts: { byId: {
      '0-mainnet': { type: 'view', byChain: { ton: { address: 'EQ-first' } } },
      '1-mainnet': { type: 'view', byChain: { ethereum: { address: '0xsecond' } } },
    } },
  });
  stopSync = startAgentV2HostContextSync();
  await jest.advanceTimersByTimeAsync(100);

  setGlobal({ ...getGlobal(), currencyRates: { ...getGlobal().currencyRates, USD: '2' } });
  await jest.advanceTimersByTimeAsync(100);
  setGlobal({ ...getGlobal(), currentAccountId: '1-mainnet' });
  await jest.advanceTimersByTimeAsync(100);
  expect(callApiMock).toHaveBeenCalledTimes(2);
  expect(callApiMock).toHaveBeenLastCalledWith('updateAgentV2HostContext', expect.objectContaining({
    activeAccountId: '1-mainnet', activeNetwork: 'ethereum', currencyRate: '2',
  }));

  setGlobal({ ...getGlobal(), currentAccountId: undefined, accounts: undefined });
  await jest.advanceTimersByTimeAsync(100);
  expect(callApiMock).toHaveBeenCalledTimes(3);
  expect(callApiMock).toHaveBeenLastCalledWith('updateAgentV2HostContext', expect.objectContaining({ accounts: [] }));
});

it('applies network and user settings without the polling delay', async () => {
  stopSync = startAgentV2HostContextSync();
  await jest.advanceTimersByTimeAsync(100);

  setGlobal({
    ...getGlobal(),
    settings: { ...getGlobal().settings, isTestnet: true, baseCurrency: 'EUR', theme: 'dark' },
  });
  await jest.advanceTimersByTimeAsync(100);
  expect(callApiMock).toHaveBeenCalledTimes(2);
  expect(callApiMock).toHaveBeenLastCalledWith('updateAgentV2HostContext', expect.objectContaining({
    isTestnet: true, baseCurrency: 'EUR', theme: 'dark',
  }));
});

it.each(['retry', 'runtime recovery'] as const)(
  'preserves freshly synchronized foreground data during %s before the polling batch',
  async (recovery) => {
    setGlobal({ ...getGlobal(), currencyRates: { ...getGlobal().currencyRates, USD: '1' } });
    if (recovery === 'retry') callApiMock.mockResolvedValueOnce(undefined);
    stopSync = startAgentV2HostContextSync();
    await jest.advanceTimersByTimeAsync(100);
    expect(callApiMock).toHaveBeenCalledTimes(1);

    setGlobal({ ...getGlobal(), currencyRates: { ...getGlobal().currencyRates, USD: '2' } });
    await jest.advanceTimersByTimeAsync(100);
    // User runs synchronize fresh context independently of the background polling batch
    await callApi('updateAgentV2HostContext', hostContextBuilder.buildAgentV2HostContext(getGlobal()));
    expect(callApiMock).toHaveBeenCalledTimes(2);
    expect(callApiMock).toHaveBeenLastCalledWith('updateAgentV2HostContext', expect.objectContaining({
      currencyRate: '2',
    }));

    if (recovery === 'runtime recovery') {
      callApiMock.mockResolvedValue({ ok: true, value: { generation: 2, authorityChanged: false } });
      publishAgentV2Update({ kind: 'runtimeReady', generation: 2 });
    }
    await jest.advanceTimersByTimeAsync(300);
    expect(callApiMock).toHaveBeenCalledTimes(3);
    expect(callApiMock).toHaveBeenLastCalledWith('updateAgentV2HostContext', expect.objectContaining({
      currencyRate: '2',
    }));

    await jest.advanceTimersByTimeAsync(5_000);
    expect(callApiMock).toHaveBeenCalledTimes(3);
  },
);

it('cancels scheduled builds and stops observing global state when stopped', async () => {
  stopSync = startAgentV2HostContextSync();
  await jest.advanceTimersByTimeAsync(100);
  setGlobal({ ...getGlobal(), currencyRates: { ...getGlobal().currencyRates, USD: '2' } });
  await jest.advanceTimersByTimeAsync(100);
  stopSync?.();
  await jest.advanceTimersByTimeAsync(100);
  selectHostContext.mockClear();

  setGlobal({ ...getGlobal(), settings: { ...getGlobal().settings, theme: 'dark' } });
  await jest.advanceTimersByTimeAsync(10_000);
  expect(selectHostContext).not.toHaveBeenCalled();
  expect(callApiMock).toHaveBeenCalledTimes(1);
});

it('does not publish global updates while building and delivering context', async () => {
  const onGlobalChange = jest.fn();
  await jest.advanceTimersByTimeAsync(0);
  addCallback(onGlobalChange);
  try {
    const global = getGlobal();
    stopSync = startAgentV2HostContextSync();
    await jest.advanceTimersByTimeAsync(100);
    expect(callApiMock).toHaveBeenCalledTimes(1);
    expect(getGlobal()).toBe(global);
    expect(onGlobalChange).not.toHaveBeenCalled();
  } finally {
    removeCallback(onGlobalChange);
  }
});
