/* eslint-disable no-null/no-null */
import type { WebFunnelStorageItems } from '../storages/webFunnelState';

import idb from '../storages/idb';
import { initializeWebClientState, readyWebLaunchState } from '../storages/webFunnelState';
import { reportWebFirstLaunch } from './webFunnel';

let mockSaved: WebFunnelStorageItems;
const mockFetch = jest.fn();
let mockClientId = '0123456789abcdefabcd:';
jest.mock('../../config', () => ({
  ...jest.requireActual('../../config'), BRILLIANT_API_BASE_URL: 'https://fixture.invalid',
}));
jest.mock('../common/backend', () => ({ getBackendHeaders: () => ({ 'X-App-ClientID': mockClientId }) }));
jest.mock('../storages/idb', () => ({ __esModule: true, default: {} }));
jest.mock('../storages/webFunnel', () => ({
  mutateWebFunnelStorage: (mutate: (saved: WebFunnelStorageItems) => WebFunnelStorageItems) => {
    mockSaved = mutate(mockSaved);
    return Promise.resolve(mockSaved);
  },
}));
const originalFetch = globalThis.fetch;
afterAll(() => {
  globalThis.fetch = originalFetch;
});

const eventId = '4827b46b-7d3f-4b02-a97c-8f17f64095e7';
const occurredAt = 1791705630000;
beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(occurredAt + 1000);
  mockClientId = '0123456789abcdefabcd:';
  mockSaved = readyWebLaunchState(initializeWebClientState({}, mockClientId, {
    visitId: null, hasExistingState: false,
  }), occurredAt, eventId);
  mockFetch.mockReset();
  globalThis.fetch = mockFetch;
});
afterEach(() => jest.restoreAllMocks());

it.each([
  [200, { ok: false, eventId }], [200, { ok: true, eventId: 'wrong' }],
  [202, { ok: true, eventId }], [429, {}], [500, {}],
])('retains identical pending evidence after non-ACK status=%s body=%s', async (status, body) => {
  mockFetch.mockResolvedValue({ status, json: () => Promise.resolve(body) });
  const event = mockSaved.webFirstLaunch?.event;
  await reportWebFirstLaunch(idb);
  await reportWebFirstLaunch(idb);
  expect(mockSaved.webFirstLaunch?.event).toEqual(event);
  expect(mockFetch.mock.calls[0][1].body).toBe(mockFetch.mock.calls[1][1].body);
  expect(JSON.parse(mockFetch.mock.calls[0][1].body).occurredAt).toBe(occurredAt);
});

it('retires only the matching event on exact HTTP200 acknowledgement', async () => {
  mockFetch.mockResolvedValue({ status: 200, json: () => Promise.resolve({ ok: true, eventId }) });
  await reportWebFirstLaunch(idb);
  await reportWebFirstLaunch(idb);
  expect(mockSaved.webFirstLaunch?.phase).toBe('delivered');
  expect(mockFetch).toHaveBeenCalledTimes(1);
  expect(mockFetch.mock.calls[0][1].headers['X-App-ClientID']).toBe(mockClientId);
});

it('keeps pending evidence on network failure and rejects permanent400', async () => {
  mockFetch.mockRejectedValueOnce(new Error('ACK lost'));
  await reportWebFirstLaunch(idb);
  expect(mockSaved.webFirstLaunch?.phase).toBe('pending');
  mockFetch.mockResolvedValueOnce({ status: 400 });
  await reportWebFirstLaunch(idb);
  expect(mockSaved.webFirstLaunch?.phase).toBe('rejected');
});

it('expires old evidence without creating a replacement launch', async () => {
  jest.spyOn(Date, 'now').mockReturnValue(occurredAt + 30 * 86400000);
  await reportWebFirstLaunch(idb);
  expect(mockSaved.webFirstLaunch?.phase).toBe('expired');
  expect(mockFetch).not.toHaveBeenCalled();
});

it('never submits under a different live SDK client or acknowledges a cleared identity', async () => {
  mockClientId = '22222222222222222222:';
  await reportWebFirstLaunch(idb);
  expect(mockFetch).not.toHaveBeenCalled();
  mockClientId = '0123456789abcdefabcd:';
  mockFetch.mockImplementationOnce(() => {
    mockSaved = { clientId: '22222222222222222222:' };
    return Promise.resolve({ status: 200, json: () => Promise.resolve({ ok: true, eventId }) });
  });
  await reportWebFirstLaunch(idb);
  expect(mockSaved).toEqual({ clientId: '22222222222222222222:' });
});

it('releases a stalled ACK body so the persisted event can retry', async () => {
  jest.useFakeTimers({ now: occurredAt + 1000 });
  try {
    const original = mockSaved.webFirstLaunch?.event;
    mockFetch.mockResolvedValueOnce({ status: 200, json: () => new Promise(() => {}) });
    let settled = false;
    void reportWebFirstLaunch(idb).then(() => {
      settled = true;
    });
    await jest.advanceTimersByTimeAsync(10001);
    expect(settled).toBe(true);
    expect(mockSaved.webFirstLaunch?.event).toEqual(original);
    mockFetch.mockResolvedValueOnce({ status: 200, json: () => Promise.resolve({ ok: true, eventId }) });
    await reportWebFirstLaunch(idb);
    expect(mockSaved.webFirstLaunch?.phase).toBe('delivered');
  } finally {
    jest.useRealTimers();
  }
});
