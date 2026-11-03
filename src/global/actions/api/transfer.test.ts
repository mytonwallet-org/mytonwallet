import './transfer';

import type { ApiCheckTransactionDraftResult, ApiNft } from '../../../api/types';
import type { ActionPayloads, GlobalState } from '../../types';
import { ApiCommonError, ApiTransactionDraftError, ApiTransactionError } from '../../../api/types';
import { TransferState } from '../../types';

import { SOLANA, TONCOIN } from '../../../config';
import { callApi } from '../../../api';
import { addActionHandler, getActions, getGlobal, setGlobal } from '../../index';
import { INITIAL_STATE } from '../../initialState';

jest.mock('../../../api', () => ({ callApi: jest.fn() }));
jest.mock('./auth', () => ({ switchAccount: jest.fn() }));
jest.mock('../../index', () => ({
  addActionHandler: jest.fn(),
  getActions: jest.fn(() => ({})),
  getGlobal: jest.fn(),
  setGlobal: jest.fn(),
}));

const ACCOUNT_ID = '0-mainnet';
const TO_ADDRESS = '11111111111111111111111111111111';
const AMOUNT = 1n;
const NFT: ApiNft = {
  chain: 'solana',
  address: 'nft-address',
  index: 0,
  isOnSale: false,
  metadata: {},
  interface: 'mplCore',
};
const EXPLAINED_FEE: ApiCheckTransactionDraftResult['explainedFee'] = {
  isGasless: false,
  canTransferFullBalance: false,
  fullFee: { precision: 'exact', terms: { native: 5_000_000n }, nativeSum: 5_000_000n },
};
// A result that the form would show if it applied it
const STALE_RESULT: ApiCheckTransactionDraftResult = {
  error: ApiTransactionDraftError.InactiveContract,
  explainedFee: EXPLAINED_FEE,
};

type TransferChange = { change: string; update: Partial<GlobalState['currentTransfer']> };

type FeeHandler<Name extends 'fetchNftFee' | 'fetchTransferFee'> = (
  global: GlobalState,
  actions: Pick<ReturnType<typeof getActions>, 'showError'>,
  payload: ActionPayloads[Name],
) => Promise<void>;

const fetchNftFee = jest.mocked(addActionHandler).mock.calls
  .find(([name]) => name === 'fetchNftFee')![1] as FeeHandler<'fetchNftFee'>;
const fetchTransferFee = jest.mocked(addActionHandler).mock.calls
  .find(([name]) => name === 'fetchTransferFee')![1] as FeeHandler<'fetchTransferFee'>;
const submitTransfer = jest.mocked(addActionHandler).mock.calls
  .find(([name]) => name === 'submitTransfer')![1] as (
  global: GlobalState, actions: ReturnType<typeof getActions>, payload: { enclaveToken: string },
) => Promise<void>;

function buildGlobal(balance: bigint | undefined, nfts = [NFT]): GlobalState {
  return {
    ...INITIAL_STATE,
    currentAccountId: ACCOUNT_ID,
    currentTransfer: {
      ...INITIAL_STATE.currentTransfer,
      tokenSlug: SOLANA.slug,
      toAddress: TO_ADDRESS,
      amount: AMOUNT,
      nfts,
    },
    tokenInfo: { bySlug: { [SOLANA.slug]: { ...SOLANA, priceUsd: 0, percentChange24h: 0 } } },
    byAccountId: {
      [ACCOUNT_ID]: { balances: { bySlug: balance === undefined ? {} : { [SOLANA.slug]: balance } } },
    },
  };
}

describe('actions/api/transfer', () => {
  let store: GlobalState;
  const showError = jest.fn();

  beforeEach(() => {
    showError.mockClear();
    jest.mocked(getActions).mockReturnValue({ showError } as unknown as ReturnType<typeof getActions>);
    jest.mocked(getGlobal).mockImplementation(() => store);
    jest.mocked(setGlobal).mockImplementation((next) => {
      store = next;
    });
  });

  it('hands a 255-NFT TON selection to the SDK in one call', async () => {
    const nfts = Array.from({ length: 255 }, (_, index) => ({
      ...NFT, chain: 'ton' as const, address: `nft-${index}`,
    }));
    store = buildGlobal(100_000_000_000n, nfts);
    store.currentTransfer.tokenSlug = TONCOIN.slug;
    store.currentTransfer.resolvedAddress = TO_ADDRESS;
    store.currentTransfer.explainedFee = EXPLAINED_FEE;
    const actions = {
      releaseEnclaveSession: jest.fn(),
      fetchTransferDieselState: jest.fn(),
    } as unknown as ReturnType<typeof getActions>;
    jest.mocked(callApi).mockResolvedValueOnce({ activityIds: nfts.map((nft) => nft.address) } as never);
    const callOffset = jest.mocked(callApi).mock.calls.length;

    await submitTransfer(store, actions, { enclaveToken: 'token' });

    const calls = jest.mocked(callApi).mock.calls.slice(callOffset);
    expect(calls).toHaveLength(1);
    expect(calls[0][0]).toBe('submitNftTransfers');
    expect(calls[0][4]).toEqual(nfts);
    expect(store.currentTransfer.sentNftsCount).toBe(255);
    expect(actions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'token' });
  });

  it.each([0, 4])('finishes a failed NFT submission only when %i NFTs were accepted', async (acceptedCount) => {
    const nfts = Array.from({ length: 5 }, (_, index) => ({ ...NFT, chain: 'ton' as const, address: `nft-${index}` }));
    store = buildGlobal(100_000_000_000n, nfts);
    store.currentTransfer.state = TransferState.Password;
    store.currentTransfer.tokenSlug = TONCOIN.slug;
    store.currentTransfer.resolvedAddress = TO_ADDRESS;
    const actions = { releaseEnclaveSession: jest.fn() } as unknown as ReturnType<typeof getActions>;
    const error = acceptedCount
      ? ApiTransactionError.PartialTransactionFailure
      : ApiTransactionError.InsufficientBalance;
    jest.mocked(callApi).mockResolvedValueOnce({
      activityIds: nfts.slice(0, acceptedCount).map((nft) => nft.address), error,
    } as never);

    await submitTransfer(store, actions, { enclaveToken: 'token' });

    expect(showError).toHaveBeenCalledWith({ error });
    expect(store.currentTransfer.state).toBe(acceptedCount ? TransferState.Complete : TransferState.Password);
    expect(store.currentTransfer.sentNftsCount).toBe(acceptedCount);
    expect(store.currentTransfer.isLoading).toBeUndefined();
    expect(actions.releaseEnclaveSession).toHaveBeenCalledWith({ enclaveToken: 'token' });
  });

  // Keeps the fee check in progress until the test resolves it
  function mockPendingCheck() {
    let resolveCheck!: (result: ApiCheckTransactionDraftResult) => void;
    const check = new Promise((resolve) => {
      resolveCheck = resolve;
    });
    jest.mocked(callApi).mockReturnValueOnce(check as never);
    return resolveCheck;
  }

  function changeCurrentTransfer(update: TransferChange['update']) {
    store = { ...store, currentTransfer: { ...store.currentTransfer, ...update } };
  }

  describe('fetchNftFee', () => {
    async function run(balance: bigint | undefined, result: ApiCheckTransactionDraftResult | undefined) {
      store = buildGlobal(balance);
      jest.mocked(callApi).mockResolvedValue(result);
      await fetchNftFee(store, { showError }, {
        toAddress: TO_ADDRESS,
        nfts: [NFT],
      });
    }

    it('reports insufficient balance when the cached balance still covers the fee', async () => {
      await run(10_000_000n, {
        error: ApiTransactionDraftError.InsufficientBalance,
        explainedFee: EXPLAINED_FEE,
      });

      expect(showError).toHaveBeenCalledWith({ error: ApiTransactionDraftError.InsufficientBalance });
    });

    it('leaves insufficient balance to the inline warning when the cached balance cannot cover the fee', async () => {
      await run(0n, { error: ApiTransactionDraftError.InsufficientBalance, explainedFee: EXPLAINED_FEE });

      expect(showError).not.toHaveBeenCalled();
    });

    it('reports insufficient balance when the cached token balance is unknown', async () => {
      await run(undefined, { error: ApiTransactionDraftError.InsufficientBalance, explainedFee: EXPLAINED_FEE });

      expect(showError).toHaveBeenCalledWith({ error: ApiTransactionDraftError.InsufficientBalance });
    });

    it('reports insufficient balance when diesel authorization hides the inline warning', async () => {
      await run(0n, {
        error: ApiTransactionDraftError.InsufficientBalance,
        explainedFee: EXPLAINED_FEE,
        diesel: { status: 'not-authorized', nativeAmount: 5_000_000n, remainingFee: 0n, realFee: 5_000_000n },
      });

      expect(showError).toHaveBeenCalledWith({ error: ApiTransactionDraftError.InsufficientBalance });
    });

    it('reports other draft errors even when the balance cannot cover the fee', async () => {
      await run(0n, { error: ApiTransactionDraftError.InactiveContract, explainedFee: EXPLAINED_FEE });

      expect(showError).toHaveBeenCalledWith({ error: ApiTransactionDraftError.InactiveContract });
    });

    it('leaves address errors to the submit button', async () => {
      await run(10_000_000n, { error: ApiCommonError.DomainNotResolved, explainedFee: EXPLAINED_FEE });

      expect(store.currentTransfer.toAddressError).toBe(ApiCommonError.DomainNotResolved);
      expect(showError).not.toHaveBeenCalled();
    });

    it.each<TransferChange>([
      { change: 'entered a new address', update: { toAddress: 'new-address' } },
      { change: 'switched to a token transfer', update: { nfts: undefined } },
      { change: 'added a collectible', update: { nfts: [NFT, { ...NFT, address: 'other-nft-address' }] } },
      { change: 'selected another collectible', update: { nfts: [{ ...NFT, address: 'other-nft-address' }] } },
      { change: 'selected a collectible on another chain', update: { nfts: [{ ...NFT, chain: 'ton' }] } },
    ])('ignores the check when the user has $change', async ({ update }) => {
      store = buildGlobal(10_000_000n);
      const resolveCheck = mockPendingCheck();
      const check = fetchNftFee(store, { showError }, { toAddress: TO_ADDRESS, nfts: [NFT] });

      changeCurrentTransfer(update);
      resolveCheck(STALE_RESULT);
      await check;

      expect(store.currentTransfer.isLoading).toBe(false);
      expect(store.currentTransfer.explainedFee).toBeUndefined();
      expect(showError).not.toHaveBeenCalled();
    });

    it('keeps loading while a newer check is pending', async () => {
      store = buildGlobal(10_000_000n);
      const resolveOlder = mockPendingCheck();
      const resolveNewer = mockPendingCheck();
      const payload = { toAddress: TO_ADDRESS, nfts: [NFT] };
      const olderCheck = fetchNftFee(store, { showError }, payload);
      const newerCheck = fetchNftFee(store, { showError }, payload);

      resolveOlder({ error: ApiCommonError.DomainNotResolved });
      await olderCheck;

      expect(store.currentTransfer.isLoading).toBe(true);
      expect(store.currentTransfer.toAddressError).toBeUndefined();

      resolveNewer({ explainedFee: EXPLAINED_FEE });
      await newerCheck;

      expect(store.currentTransfer).toMatchObject({ isLoading: false, explainedFee: EXPLAINED_FEE });
    });

    it('clears loading after a transport error', async () => {
      await run(10_000_000n, undefined);

      expect(store.currentTransfer.isLoading).toBe(false);
      expect(showError).not.toHaveBeenCalled();
    });

    it('stores a successful fee estimate without showing an error', async () => {
      await run(10_000_000n, { explainedFee: EXPLAINED_FEE });

      expect(store.currentTransfer).toMatchObject({ isLoading: false, explainedFee: EXPLAINED_FEE });
      expect(showError).not.toHaveBeenCalled();
    });
  });

  describe('fetchTransferFee', () => {
    async function runWithChange(update: TransferChange['update']) {
      store = buildGlobal(10_000_000n, []);
      const resolveCheck = mockPendingCheck();
      const check = fetchTransferFee(store, { showError }, {
        tokenSlug: SOLANA.slug,
        toAddress: TO_ADDRESS,
        amount: AMOUNT,
        // The form passes an empty comment when the transfer has none
        comment: '',
      });

      changeCurrentTransfer(update);
      resolveCheck(STALE_RESULT);
      await check;
    }

    it('applies the check when the form is unchanged', async () => {
      await runWithChange({});

      expect(store.currentTransfer).toMatchObject({ isLoading: false, explainedFee: EXPLAINED_FEE });
      expect(showError).toHaveBeenCalledWith({ error: ApiTransactionDraftError.InactiveContract });
    });

    it.each<TransferChange>([
      { change: 'entered a new address', update: { toAddress: 'new-address' } },
      { change: 'switched the token', update: { tokenSlug: 'other-token' } },
      { change: 'changed the amount', update: { amount: AMOUNT + 1n } },
      { change: 'changed the comment', update: { comment: 'comment' } },
      { change: 'turned on comment encryption', update: { shouldEncrypt: true } },
      { change: 'opened a link with another payload', update: { binPayload: 'te6cc' } },
      { change: 'opened a link with another state init', update: { stateInit: 'te6cc' } },
    ])('ignores the check when the user has $change', async ({ update }) => {
      await runWithChange(update);

      expect(store.currentTransfer.isLoading).toBe(false);
      expect(store.currentTransfer.explainedFee).toBeUndefined();
      expect(showError).not.toHaveBeenCalled();
    });
  });
});
