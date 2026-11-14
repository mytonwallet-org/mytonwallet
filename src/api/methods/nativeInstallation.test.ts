import type { AirInstallationPendingDelivery } from '../../util/windowProvider/methods/airStorage';

import { reportNativeInstallation } from './nativeInstallation';

jest.mock('../../config', () => ({ ...jest.requireActual('../../config'),
  BRILLIANT_API_BASE_URL: 'https://api.example' }));
jest.mock('../common/backend', () => ({ getBackendHeaders: () => ({
  'X-App-ClientID': 'wallet-id', 'X-App-Name': 'My Wallet', 'X-App-Platform': 'android',
}) }));
jest.mock('../../util/windowProvider/connector', () => {
  const actual = jest.requireActual('../air/airAppCallWindow');
  return { callWindow: (...args: unknown[]) => actual.airAppCallWindow(...args) };
});

const body = {
  schemaVersion: 2 as const,
  installationId: '11111111-1111-4111-8111-111111111111',
  eventId: '22222222-2222-4222-8222-222222222222',
  packageInstalledAt: 1791600000789,
  sourceTransport: 'play_referrer' as const,
  collectionStatus: 'pending',
  playInstalledAt: JSON.parse('null'),
  installVersion: '',
  source: JSON.parse('null'),
};
const pending: AirInstallationPendingDelivery[] = [
  { slot: 'play', body },
  { slot: 'deeplink', body: { ...body, eventId: '33333333-3333-4333-8333-333333333333',
    sourceTransport: 'deeplink', source: {
      channel: 'campaign', attributionKind: 'utm' as const, sourceOutcome: 'utm',
    } } },
];
const airWindow = window as import('../types/air').AirWindow;
const native = jest.fn();
const fetchMock = jest.fn();
let items = pending;

const settle = () => Promise.all(Array.from({ length: 20 }, () => Promise.resolve()));
function calls(method: string) {
  return native.mock.calls.filter(([, name]) => name === method);
}

beforeEach(() => {
  jest.useFakeTimers();
  items = pending;
  Object.assign(airWindow, { airBridge: { nativeCallCallbacks: {} }, androidApp: { nativeCall: native },
    webkit: undefined });
  native.mockReset().mockImplementation((number, method) => {
    airWindow.airBridge.nativeCallCallbacks[number]({ ok: true,
      result: method === 'airInstallationGetPending' ? items : true });
  });
  fetchMock.mockReset();
  Object.defineProperty(global, 'fetch', { configurable: true, value: fetchMock });
});
afterEach(() => jest.useRealTimers());

it('posts both immutable native envelopes without wallet identity and returns raw ACKs to their slots', async () => {
  fetchMock.mockImplementation((_url, options) => Promise.resolve({
    status: 200, json: () => Promise.resolve({ eventId: JSON.parse(options.body).eventId }),
  }));
  await reportNativeInstallation();
  pending.forEach((delivery, index) => {
    const [url, options] = fetchMock.mock.calls[index];
    expect(url).toBe('https://api.example/attribution/install');
    expect(options.body).toBe(JSON.stringify(delivery.body));
    expect(options.headers).toEqual({
      'X-App-Name': 'My Wallet', 'X-App-Platform': 'android', 'Content-Type': 'application/json',
    });
  });
  expect(calls('airInstallationAcknowledge').map(([, , slot, ack]) => [slot, ack])).toEqual([
    ['play', JSON.stringify({ eventId: body.eventId })],
    ['deeplink', JSON.stringify({ eventId: pending[1].body.eventId })],
  ]);
});

it('fences an owner replaced while reading the response body', async () => {
  let resolveBody!: (value: unknown) => void;
  const responseBody = new Promise((resolve) => {
    resolveBody = resolve;
  });
  fetchMock.mockResolvedValue({ status: 200, json: () => responseBody });
  let alive = true;
  const reporting = reportNativeInstallation(() => alive);
  await settle();
  alive = false;
  resolveBody({ ok: true });
  await reporting;
  expect(calls('airInstallationAcknowledge')).toHaveLength(0);
});
it.each(['fetch', 'json'])('bounds %s and retries the exact envelope', async (stage) => {
  items = [pending[0]];
  const stalled = new Promise(() => {});
  fetchMock.mockImplementationOnce(() => stage === 'fetch'
    ? stalled : Promise.resolve({ status: 200, json: () => stalled }));
  const first = reportNativeInstallation();
  await settle();
  await jest.advanceTimersByTimeAsync(30000);
  await first;
  fetchMock.mockResolvedValueOnce({ status: 200, json: () => Promise.resolve({ ok: true }) });
  await reportNativeInstallation();
  expect(fetchMock.mock.calls.map(([, options]) => options.body)).toEqual(Array(2).fill(JSON.stringify(items[0].body)));
  expect(calls('airInstallationAcknowledge')).toHaveLength(1);
  expect(jest.getTimerCount()).toBe(0);
});

it.each([false, true])('reports delivery settled only when native persists the ACK (%s)', async (isAccepted) => {
  items = [pending[0]];
  fetchMock.mockResolvedValue({ status: 200, json: () => Promise.resolve({ ok: true }) });
  native.mockImplementation((number, method) => {
    airWindow.airBridge.nativeCallCallbacks[number]({
      ok: true, result: method === 'airInstallationGetPending' ? items : isAccepted,
    });
  });
  expect(await reportNativeInstallation()).toBe(isAccepted);
});

it('keeps delivery unsettled when the server accepted it but its response was lost', async () => {
  items = [pending[0]];
  fetchMock.mockRejectedValue(new Error('Response lost'));
  expect(await reportNativeInstallation()).toBe(false);
  expect(calls('airInstallationAcknowledge')).toHaveLength(0);
});

it('sends omitted native arguments as null, which the Android bridge keeps distinct from "undefined"', async () => {
  items = [];
  expect(await reportNativeInstallation()).toBe(true);
  const nil = JSON.parse('null');
  expect(calls('airInstallationGetPending'))
    .toStrictEqual([[expect.any(Number), 'airInstallationGetPending', nil, nil]]);
});
