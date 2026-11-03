import './tokens';

import type { ApiTokenDetails } from '../../../api/types';
import type { ActionPayloads, GlobalState, TokenDetailsState } from '../../types';
import { ApiCommonError } from '../../../api/types';

import { MINUTE, SECOND } from '../../../util/dateFormat';
import Deferred from '../../../util/Deferred';
import { callApi } from '../../../api';
import { addActionHandler, getGlobal, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getActions: jest.fn(() => ({})),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

type LoadTokenDetailsHandler = (
  global: GlobalState,
  actions: object,
  payload: ActionPayloads['loadTokenDetails'],
) => Promise<void>;

const loadTokenDetailsHandler = jest.mocked(addActionHandler).mock.calls
  .find(([name]) => name === 'loadTokenDetails')![1] as LoadTokenDetailsHandler;
const initApiHandler = jest.mocked(addActionHandler).mock.calls
  .find(([name]) => name === 'initApi')![1] as NoneToVoidFunction;

const NOW = 1_800_000_000_000;
const BTC_DETAILS: ApiTokenDetails = { description: 'Bitcoin' };

let store: GlobalState;

function loadTokenDetails(slugs: string[]) {
  return loadTokenDetailsHandler(store, {}, { slugs });
}

describe('loadTokenDetails', () => {
  let dateNowSpy: jest.SpyInstance;

  beforeEach(() => {
    store = { ...INITIAL_STATE, settings: { ...INITIAL_STATE.settings, langCode: 'en' } };
    jest.mocked(getGlobal).mockImplementation(() => store);
    jest.mocked(setGlobal).mockImplementation((global) => {
      store = global;
    });
    jest.mocked(callApi).mockReset();
    dateNowSpy = jest.spyOn(Date, 'now').mockReturnValue(NOW);
    // Forgets the requests that a previous test left unanswered
    initApiHandler();
  });

  afterEach(() => {
    dateNowSpy.mockRestore();
  });

  it('requests each slug once while its request is in flight', async () => {
    const firstResponse = new Deferred<{ detailsBySlug: Record<string, ApiTokenDetails> }>();
    jest.mocked(callApi)
      .mockReturnValueOnce(firstResponse.promise)
      .mockResolvedValueOnce({ detailsBySlug: {} });

    const firstRequest = loadTokenDetails(['btc', 'trx']);
    await loadTokenDetails(['btc']);
    await loadTokenDetails(['trx', 'sol']);
    firstResponse.resolve({ detailsBySlug: {} });
    await firstRequest;

    expect(jest.mocked(callApi).mock.calls).toEqual([
      ['fetchTokenInfo', ['btc', 'trx']],
      ['fetchTokenInfo', ['sol']],
    ]);
  });

  it('stores the details with their language and time, and an empty entry for a token without info', async () => {
    jest.mocked(callApi).mockResolvedValueOnce({ detailsBySlug: { btc: BTC_DETAILS } });

    await loadTokenDetails(['btc', 'unknown']);

    expect(store.tokenDetails.bySlug).toEqual({
      btc: { data: BTC_DETAILS, langCode: 'en', fetchedAt: NOW },
      unknown: { langCode: 'en', fetchedAt: NOW },
    });
  });

  it('drops a response in the previous language', async () => {
    const enResponse = new Deferred<{ detailsBySlug: Record<string, ApiTokenDetails> }>();
    jest.mocked(callApi).mockReturnValueOnce(enResponse.promise);
    const enRequest = loadTokenDetails(['btc']);

    const ruDetails: TokenDetailsState = { data: { description: 'Биткоин' }, langCode: 'ru', fetchedAt: NOW };
    store = {
      ...store,
      settings: { ...store.settings, langCode: 'ru' },
      tokenDetails: { bySlug: { btc: ruDetails } },
    };
    enResponse.resolve({ detailsBySlug: { btc: BTC_DETAILS } });
    await enRequest;

    expect(store.tokenDetails.bySlug.btc).toEqual(ruDetails);
  });

  it('stops waiting for a request that never answers once it times out', async () => {
    jest.mocked(callApi)
      .mockReturnValueOnce(new Deferred<undefined>().promise)
      .mockResolvedValueOnce({ detailsBySlug: { btc: BTC_DETAILS } });

    void loadTokenDetails(['btc']);
    dateNowSpy.mockReturnValue(NOW + 29 * SECOND);
    await loadTokenDetails(['btc']);
    expect(callApi).toHaveBeenCalledTimes(1);

    dateNowSpy.mockReturnValue(NOW + 30 * SECOND);
    await loadTokenDetails(['btc']);
    expect(callApi).toHaveBeenCalledTimes(2);
    expect(store.tokenDetails.bySlug.btc?.data).toEqual(BTC_DETAILS);
  });

  it('leaves a slug to the newer request when the timed-out one answers late', async () => {
    const lateResponse = new Deferred<{ detailsBySlug: Record<string, ApiTokenDetails> }>();
    const newerResponse = new Deferred<{ detailsBySlug: Record<string, ApiTokenDetails> }>();
    jest.mocked(callApi)
      .mockReturnValueOnce(lateResponse.promise)
      .mockReturnValueOnce(newerResponse.promise);

    const lateRequest = loadTokenDetails(['btc']);
    dateNowSpy.mockReturnValue(NOW + 30 * SECOND);
    const newerRequest = loadTokenDetails(['btc']);

    lateResponse.resolve({ detailsBySlug: { btc: { description: 'Outdated' } } });
    await lateRequest;
    expect(store.tokenDetails.bySlug.btc).toBeUndefined();

    await loadTokenDetails(['btc']);
    expect(callApi).toHaveBeenCalledTimes(2);

    newerResponse.resolve({ detailsBySlug: { btc: BTC_DETAILS } });
    await newerRequest;
    expect(store.tokenDetails.bySlug.btc?.data).toEqual(BTC_DETAILS);
  });

  it('requests again right after the API is initialized anew', async () => {
    jest.mocked(callApi)
      .mockReturnValueOnce(new Deferred<undefined>().promise)
      .mockResolvedValueOnce({ detailsBySlug: { btc: BTC_DETAILS } });

    void loadTokenDetails(['btc']);
    initApiHandler();
    await loadTokenDetails(['btc']);

    expect(callApi).toHaveBeenCalledTimes(2);
    expect(store.tokenDetails.bySlug.btc?.data).toEqual(BTC_DETAILS);
  });

  it('keeps the shown details on a failure and requests them again afterwards', async () => {
    const shown: TokenDetailsState = { data: BTC_DETAILS, langCode: 'en', fetchedAt: NOW - MINUTE };
    store = { ...store, tokenDetails: { bySlug: { btc: shown } } };
    jest.mocked(callApi)
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce({ error: ApiCommonError.Unexpected });

    await loadTokenDetails(['btc']);
    expect(store.tokenDetails.bySlug.btc).toEqual({ ...shown, hasError: true });

    await loadTokenDetails(['btc']);
    expect(callApi).toHaveBeenCalledTimes(2);
    expect(store.tokenDetails.bySlug.btc).toEqual({ ...shown, hasError: true });
  });
});
