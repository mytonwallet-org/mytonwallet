import type { ApiNetwork, ApiSwapActivity, ApiTransactionActivity } from '../../types';
import type { TracesResponse } from './toncenter/traces';

import { makeMockSwapActivity, makeMockTransactionActivity } from '../../../../tests/mocks';
import { fillActivityDetails } from './activities';
import { parseTrace } from './traces';

describe('parseTrace + calculateActivityDetails', () => {
  // How to get the input data:
  // 1. Add `console.log('activity', activity);` at the start of `calculateActivityDetails`,
  // 2. Open a transaction modal in the Activity tab of the app,
  // 3. Get the trace JSON from the `/api/v3/traces` response in the Network tab of the DevTools.

  describe('transactions', () => {
    const testCases: {
      name: string;
      walletAddress: string;
      /** Leave only the fields that are significant for the test */
      activityPart: Partial<ApiTransactionActivity>;
      traceResponse: TracesResponse;
      expectedFee: bigint;
    }[] = [
      {
        name: 'TON transfer',
        walletAddress: 'UQCgf9xAc0HumzY_N2Lgk5oQk3_pL7N04GT0KaP-H7upN-qH',
        activityPart: {
          id: 'eamGZJTFfqWoRX5MgBlLZlJ20372CUiL6uEtKh7xeU8='
            + ':50757011000001-y740RzK3hGPDFSkzvkK40PU7WJMjK00jz+FxBOmitzA=',
          externalMsgHashNorm: 'BSn6jVJGA3/qfCvFaugHNYYsz5fXDUSYd6RTX396e4Q=',
          fromAddress: 'UQCgf9xAc0HumzY_N2Lgk5oQk3_pL7N04GT0KaP-H7upN-qH',
          toAddress: 'UQDxO-azxmbgK2vb_FMPE2y7PMCGeMal0wXqCt9w797d1YFR',
          isIncoming: false,
          normalizedAddress: 'EQDxO-azxmbgK2vb_FMPE2y7PMCGeMal0wXqCt9w797d1dyU',
          amount: -5000000000n,
          slug: 'toncoin',
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/tonTransferTraceResponse.json'),
        expectedFee: 2345629n,
      },
      {
        name: 'USDT transfer',
        walletAddress: 'UQCgf9xAc0HumzY_N2Lgk5oQk3_pL7N04GT0KaP-H7upN-qH',
        activityPart: {
          id: 'OnWzsl9e4nQZd6iCCy6HoFj+grX2RcH68MoNW4Dv5Jw='
            + ':48818110000001-9K6Gj0dR+3KIpfTeQ03h5q22dHTXpco5P7RCqOxzIBs=',
          externalMsgHashNorm: 'Bipiu5Wd8Z87Vz1d8jVXTXPPRJbsT4ydVT2TWrMgmqg=',
          fromAddress: 'UQCgf9xAc0HumzY_N2Lgk5oQk3_pL7N04GT0KaP-H7upN-qH',
          toAddress: 'UQBGDiFhz7JAEYSe7gSYgic5az5ynJnzvL3BcEGMO-M-3iD_',
          isIncoming: false,
          normalizedAddress: 'EQBGDiFhz7JAEYSe7gSYgic5az5ynJnzvL3BcEGMO-M-3n06',
          amount: -90000000n,
          slug: 'ton-eqcxe6mutq',
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/usdtTransferTraceResponse.json'),
        expectedFee: 7220787n,
      },
      {
        name: 'contract call',
        walletAddress: 'UQAD87Hs-_MrShb84GwhM1Mnwe_72i10VWQWU1eQ6v1nGkR8',
        activityPart: {
          id: 'aauhCIOh6YFanxo483sLtzfeVEj05q4HCozrmNGsXdI='
            + ':57371927000002-gbNcDqRV9NJg1oMoOpC0CGXGeHv3/78rwkTj6UkNIgY=',
          externalMsgHashNorm: 'K6gpSRaFh9t4//KLB/+gTL9XDSQJN9apL3VFyYNH4P0=',
          fromAddress: 'UQAD87Hs-_MrShb84GwhM1Mnwe_72i10VWQWU1eQ6v1nGkR8',
          toAddress: 'EQBS114FhHMAASOdTNjHPWUbIG6sZ9tVFTW2ttUF5tQcd-kx',
          isIncoming: false,
          normalizedAddress: 'EQBS114FhHMAASOdTNjHPWUbIG6sZ9tVFTW2ttUF5tQcd-kx',
          amount: -1014280000n,
          slug: 'toncoin',
          type: 'callContract',
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/contractCallTraceResponse.json'),
        expectedFee: 5871974n,
      },
      {
        name: 'NFT transfer',
        walletAddress: 'UQCjWIRxnjt45AgA_IXhXnTfzWxBsNOGvM0CC38GOuS6oYs3',
        activityPart: {
          id: 'eun7tlfTWRISiyMlxIvcoV3YYUqXgCWN4OSDQ4XY57I='
            + ':60137203000002-rwrEnHKahOiufRufNsqf1N+yUKLHNrZ+LjyMGM0iXSs=',
          externalMsgHashNorm: 'zIAYXR0RKCHhodiU73DoaRGQINE0MUiJ/oRWlU1+DJ0=',
          fromAddress: 'UQCjWIRxnjt45AgA_IXhXnTfzWxBsNOGvM0CC38GOuS6oYs3',
          toAddress: 'UQCAHa2hBlZBAFcgYDsBh6KqnUbwKP70I3PbXe_RkJVJL1Rv',
          isIncoming: false,
          normalizedAddress: 'EQCAHa2hBlZBAFcgYDsBh6KqnUbwKP70I3PbXe_RkJVJLwmq',
          amount: 0n,
          status: 'completed',
          slug: 'toncoin',
          nft: {
            interface: 'default',
            chain: 'ton',
            index: 69146,
            name: 'Sins Postmark Series #69147',
            address: 'EQBtqQlC09xW_oOHJOrMofDmFndOrY7zCjd7bYELIoabO9JC',
            thumbnail: 'https://imgproxy.toncenter.com/JuFXGLYNNFbAeGMdWXPiHMdbmWd85cDD6o3J3FrH-qE/pr:medium/aHR0cHM6L'
              + 'y9zLmdldGdlbXMuaW8vbmZ0L2IvYy82Njc1YTRmYjA4NGM0MzAzOGFmMmMyNzMvaW1hZ2VzL2FkNjNlYzgwNDVkMmI1NTdiNGIzYT'
              + 'VlYjNlYjkyM2YyYWUwZWViNmQ',
            image:
              'https://s.getgems.io/nft/b/c/6675a4fb084c43038af2c273/images/ad63ec8045d2b557b4b3a5eb3eb923f2ae0eeb6d',
            description: 'You\'ve got a postmark! Enjoy collecting and exploring the depths of "The Seven Deadly Sins"'
              + ' сollection!',
            isOnSale: false,
            metadata: {},
            collectionAddress: 'EQAkhd9AFlBOiJPwk8jZF9J1uW2t56LU8gECR4FxgvnrkbfZ',
            collectionName: 'Postmarks: The Seven Deadly Sins',
          },
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/nftTransferTraceResponse.json'),
        expectedFee: 8691591n,
      },
      {
        name: 'failed TON transfer',
        walletAddress: 'UQD70btWHfH1rH9t0rp_QdNM5ZUt1eLG74KsvM4iXjmckRuf',
        activityPart: {
          id: 'l7+GoD/KRkT8j4q3IW+1CEOaB/lTGDR6KppdDO7i2uM='
            + ':60205987000001-6zoLHky4RGiaZY13LX1l7Nf43jWKMgXIg79jzs5u9Ss=',
          externalMsgHashNorm: '31DdfXMjXbrmM8tS/Fa1jUHSy1y/x56gQk87pFe7PR8=',
          fromAddress: 'UQD70btWHfH1rH9t0rp_QdNM5ZUt1eLG74KsvM4iXjmckRuf',
          toAddress: 'UQDvONrVcvB3ykXkGUhJsdwLgvgBlz_RFKRxmEktZCgwkXtE',
          isIncoming: false,
          normalizedAddress: 'EQDvONrVcvB3ykXkGUhJsdwLgvgBlz_RFKRxmEktZCgwkSaB',
          amount: -75000000000n,
          status: 'failed',
          slug: 'toncoin',
          comment: '106776',
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/failedTonTransferTraceResponse.json'),
        expectedFee: 2713210n,
      },
      {
        name: 'failed USDT transfer',
        walletAddress: 'UQCZtnMuh6LDmnglxhRDX9f4xJSZy8FZRJ4D8mhow9VpqlxW',
        activityPart: {
          id: 'mVzJxka9Xx7dWcQ3XPD8mJ7fB8mVphpGSUd3/sWfWW8='
            + ':60150639000001-k0KacDttvwAcdpkdz3Bl4IAlXMZYG8i9TbpO8cqt8rI=',
          externalMsgHashNorm: '8iENFUL0TZxSGTrfQhpqqPLsojlZ8Ix0Mw637P8COw4=',
          fromAddress: 'UQCZtnMuh6LDmnglxhRDX9f4xJSZy8FZRJ4D8mhow9VpqlxW',
          toAddress: 'UQA9rS9sWBSGCbvXLummsfADZ6ZR5MLVE6cc0g3Kk8ZdvLsB',
          isIncoming: false,
          normalizedAddress: 'EQA9rS9sWBSGCbvXLummsfADZ6ZR5MLVE6cc0g3Kk8ZdvObE',
          amount: -4850000n,
          status: 'failed',
          slug: 'ton-eqcxe6mutq',
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/failedUsdtTransferTraceResponse.json'),
        expectedFee: 2255794n,
      },
      {
        name: 'failed NFT transfer',
        walletAddress: 'UQCjWIRxnjt45AgA_IXhXnTfzWxBsNOGvM0CC38GOuS6oYs3',
        activityPart: {
          id: 's0cLqMif/nCuZTyG5pvsq3rLd9uVMWeNQG0Mm7HI9Qo='
            + ':60137208000002-PKyDZX5mLor6F5O2/R1s7HZeaSKU/6BBkdZCe9AgFAE=',
          externalMsgHashNorm: 'HqGE7DWcruB8ZA1M+4cqlJRx5XAbQ7Qj8Ez8z73uGFU=',
          fromAddress: 'UQCjWIRxnjt45AgA_IXhXnTfzWxBsNOGvM0CC38GOuS6oYs3',
          toAddress: 'UQCAHa2hBlZBAFcgYDsBh6KqnUbwKP70I3PbXe_RkJVJL1Rv',
          isIncoming: false,
          normalizedAddress: 'EQCAHa2hBlZBAFcgYDsBh6KqnUbwKP70I3PbXe_RkJVJLwmq',
          amount: 0n,
          status: 'failed',
          slug: 'toncoin',
          nft: {
            interface: 'default',
            chain: 'ton',
            index: 3568,
            name: 'USD₮ - pTON Farm NFT',
            address: 'EQCFPen3WvwP0sIr-C4zVQs03UI7SgsFs8mlCWnIkjKNLMsj',
            thumbnail: 'https://imgproxy.toncenter.com/s-UphnJEZ_JbG9klJawCCwRKtuQakd9zAoDUhKpfVGg/pr:medium'
              + '/aHR0cHM6Ly9zdGF0aWMuc3Rvbi5maS9mYXJtLW5mdC9TdG9uX0Zhcm1fTkZULnBuZw',
            image: 'https://static.ston.fi/farm-nft/Ston_Farm_NFT.png',
            description: 'Staked 0.010303812 USD₮ - pTON LPs on STON.fi Farm. ',
            isOnSale: false,
            metadata: {},
            collectionAddress: 'EQDyswfVhGlOue4_a9cAVuDSP0ldWP53jK2jL9qXfPWGhZP4',
            collectionName: 'USD₮ - pTON Farm NFT collection',
          },
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/failedNftTransferTraceResponse.json'),
        expectedFee: 5472803n,
      },
    ];

    test.each(testCases)('$name', (params) => {
      const { walletAddress, activityPart, traceResponse, expectedFee } = params;

      const activity = makeMockTransactionActivity({
        ...activityPart,
        fee: 0n,
        shouldLoadDetails: true,
      });

      const parsedTrace = parseTraceResponse('mainnet', walletAddress, traceResponse);

      expect(fillActivityDetails(activity, parsedTrace)).toEqual({
        ...activity,
        fee: expectedFee,
        shouldLoadDetails: undefined,
      });
    });
  });

  describe('swaps', () => {
    const testCases: {
      name: string;
      walletAddress: string;
      activityPart: Partial<ApiSwapActivity>;
      traceResponse: TracesResponse;
      expectedFee: string;
    }[] = [
      {
        name: 'utya swap to ton',
        walletAddress: 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8',
        activityPart: {
          id: 'OHiU4S9hRHHEPnvR3kISqq0RqhWqR4WvQGz1PpMVAvc='
            + ':61381078000002-HPEZBwAgCEAXuQebK+MFrFFHFzsQAMa3hnrUGO0aVVQ=',
          kind: 'swap',
          timestamp: 1757491121000,
          from: 'ton-eqbacguwoo',
          fromAmount: '196.803411472',
          to: 'toncoin',
          toAmount: '1.031388991',
          networkFee: '0.045536041',
          swapFee: '0',
          ourFee: '1.72202985',
          status: 'completed',
          hashes: [],
          externalMsgHashNorm: '5IvAF0fn34L7MDxzu67m4MzeNp6Mpg2poC9dXE1DdFw=',
        },
        // eslint-disable-next-line @typescript-eslint/no-require-imports
        traceResponse: require('./testData/utyaSwapTraceResponse.json'),
        expectedFee: '0.045536041', // This is the full fee, because the excess is a separate action in this trace
      },
    ];

    test.each(testCases)('$name', (params) => {
      const { walletAddress, activityPart, traceResponse, expectedFee } = params;

      const activity = makeMockSwapActivity(activityPart);
      const parsedTrace = parseTraceResponse('mainnet', walletAddress, traceResponse);

      expect(fillActivityDetails(activity, parsedTrace)).toEqual({
        ...activity,
        networkFee: expectedFee,
      });
    });
  });
});

/**
 * `traceResponse` is the JSON from the https://toncenter.mytonwallet.org/api/v3/traces?... response body
 */
function parseTraceResponse(network: ApiNetwork, walletAddress: string, traceResponse: TracesResponse) {
  return parseTrace({
    network,
    walletAddress,
    actions: traceResponse.traces[0].actions,
    traceDetail: traceResponse.traces[0].trace,
    addressBook: traceResponse.address_book,
    metadata: traceResponse.metadata,
    transactions: traceResponse.traces[0].transactions,
    nftSuperCollectionsByCollectionAddress: {},
  });
}
