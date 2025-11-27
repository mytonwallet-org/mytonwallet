import type { ApiActivity } from '../../types';
import type { EmulationResponse } from './toncenter/emulation';
import type { TracesResponse } from './toncenter/traces';

import { tryUpdateKnownAddresses } from '../../common/addresses';
import { parseEmulation } from './emulation';

describe('parseEmulation', () => {
  // The request for the list of trusted collections does not work in the test environment,
  // so we add the trusted collections manually.
  const trustedCollections = [
    'EQCA14o1-VWhS2efqoh_9M1b_A9DtKTuoqfmkn83AbJzwnPi',
  ];

  // You can use a regular trace, as it is converted to emulation format by the convertTraceToEmulation function.
  // Alternatively, you can obtain the emulation format from the `/api/emulate/v1/emulateTrace` response.
  const testCases: {
    name: string;
    walletAddress: string;
    traceResponse: TracesResponse | EmulationResponse;
    expectedActivities: Partial<ApiActivity>[];
    expectedRealFee: bigint;
  }[] = [
    {
      name: 'contract call with excess accounted',
      walletAddress: 'UQAXt7U0eHXLZhcngXzALAryEm_dtkTevqFfa2zc7UfcciR8',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/isExcessAccountedEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -225000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'callContract',
        },
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -62500000n,
          status: 'completed',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 220241200n,
          status: 'completed',
          slug: 'toncoin',
          type: 'excess',
        },
      ],
      expectedRealFee: 9002187n,
    },
    {
      name: 'push transfer',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/pushTransferEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 100000n,
          status: 'completed',
          slug: 'ton-eqcxe6mutq',
        },
        {
          kind: 'transaction',
          amount: -100000000n,
          status: 'completed',
          slug: 'toncoin',
          isIncoming: false,
          type: 'callContract',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 14810689n,
          status: 'completed',
          slug: 'toncoin',
          type: 'excess',
        },
      ],
      expectedRealFee: 87414171n,
    },
    {
      name: 'ton swap usdt (dedust) ',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/dedust/tonSwapUsdtTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'swap',
          from: 'toncoin',
          fromAmount: '1',
          to: 'ton-eqcxe6mutq',
          toAmount: '2.194927',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 231835983n,
          slug: 'toncoin',
          isIncoming: true,
          fee: 0n,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 20967226n,
    },
    {
      name: 'usdt swap ton (dedust)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/dedust/usdtSwapTonTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'swap',
          from: 'ton-eqcxe6mutq',
          fromAmount: '1',
          to: 'toncoin',
          toAmount: '0.471517545',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 280433579n,
          slug: 'toncoin',
          isIncoming: true,
          fee: 0n,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 22972822n,
    },
    {
      name: 'usdt swap gram (dedust)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/dedust/usdtSwapGramTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'swap',
          from: 'ton-eqcxe6mutq',
          fromAmount: '1',
          to: 'ton-eqc47093ox',
          toAmount: '337.73829948',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 261128497n,
          slug: 'toncoin',
          isIncoming: true,
          fee: 0n,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 42284657n,
    },
    {
      name: 'add liquidity (dedust)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/dedust/addLiquidityTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -480332328n,
          status: 'completed',
          type: 'liquidityDeposit',
          slug: 'toncoin',
          metadata: {},
        },
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -1000000000n,
          status: 'completed',
          type: 'liquidityDeposit',
          slug: 'ton-eqblqsm144',
          metadata: {},
        },
        {
          kind: 'transaction',
          amount: 658345290n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 146309136n,
    },
    {
      name: 'output liquidity (dedust)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/dedust/outputLiquidityTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 480332326n,
          status: 'completed',
          type: 'liquidityWithdraw',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 999999998n,
          status: 'completed',
          type: 'liquidityWithdraw',
          slug: 'ton-eqblqsm144',
        },
        {
          kind: 'transaction',
          amount: 460606861n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 41651161n,
    },
    {
      name: 'edit domain record (ton dns)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/editDomainRecordTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: 0n,
          status: 'completed',
          slug: 'toncoin',
          type: 'dnsChangeAddress',
        },
      ],
      expectedRealFee: 2835282n,
    },
    {
      name: 'ton swap ston (stonfi)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/stonfi/tonSwapStonTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'swap',
          from: 'toncoin',
          fromAmount: '1',
          to: 'ton-eqa2kcvnwv',
          toAmount: '3.7185746',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 171030246n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 55188979n, // 55821503n
    },
    {
      name: 'ston swap ton (stonfi)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/stonfi/stonSwapTonTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'swap',
          from: 'ton-eqa2kcvnwv',
          fromAmount: '3',
          to: 'toncoin',
          toAmount: '0.801854785',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 206555525n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 59946890n, // 60619946n
    },
    {
      name: 'ston swap usdt (stonfi)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/stonfi/stonSwapUsdtTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'swap',
          from: 'ton-eqa2kcvnwv',
          fromAmount: '0.5',
          to: 'ton-eqcxe6mutq',
          toAmount: '0.284146',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 207632151n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 58863860n, // 59535849n
    },
    {
      name: 'add liquidity (stonfi)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/stonfi/addLiquidityTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -414716400n,
          status: 'completed',
          type: 'liquidityDeposit',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -877582n,
          status: 'completed',
          type: 'liquidityDeposit',
          slug: 'ton-eqcxe6mutq',
        },
        {
          kind: 'transaction',
          amount: 529798397n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 86351615n,
    },
    {
      name: 'output liquidity (stonfi)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/stonfi/outputLiquidityTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 415351340n,
          status: 'completed',
          type: 'liquidityWithdraw',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 876241n,
          status: 'completed',
          type: 'liquidityWithdraw',
          slug: 'ton-eqcxe6mutq',
        },
        {
          kind: 'transaction',
          amount: 769645577n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 32612434n,
    },
    {
      name: 'buy NFT (getgems)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/getgems/buyNftEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -900000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'nftTrade',
        },
        {
          kind: 'transaction',
          amount: 289544563n,
          slug: 'toncoin',
          isIncoming: true,
          fee: 0n,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 12736242n,
    },
    {
      name: 'transfer NFT (getgems)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/getgems/transferNftEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: 0n,
          status: 'completed',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          amount: 17708068n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 8091143n,
    },
    {
      name: 'pick up sale NFT (getgems)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/getgems/pickUpSaleNftEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: 0n,
          status: 'completed',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          amount: 185059934n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 67152880n,
    },
    {
      name: 'stake (tonstakers)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/tonstakers/stakeTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -1000000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'stake',
        },
        {
          kind: 'transaction',
          amount: 974634405n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 27647479n,
    },
    {
      name: 'unstake pending (tonstakers)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/tonstakers/unstakePendingTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: 0n,
          status: 'completed',
          slug: 'toncoin',
          type: 'unstakeRequest',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 0n,
          status: 'completed',
          shouldHide: true,
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          amount: 931940000n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 120705627n,
    },
    {
      name: 'unstake instant (tonstakers)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/tonstakers/unstakeInstantTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 990815018n,
          status: 'completed',
          slug: 'toncoin',
          type: 'unstake',
        },
        {
          kind: 'transaction',
          amount: 1042786800n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 9858804n,
    },
    {
      name: 'buy NFT (fragment)',
      walletAddress: 'UQDC_A0WpMF1FBW9ez6szePgZ_UxKhtkAQkBns-WVFxDQJQT',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/fragment/buyNftTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -7000000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'nftTrade',
        },
      ],
      expectedRealFee: 2332809n,
    },
    {
      name: 'pick up auction NFT (fragment)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/fragment/pickUpAuctionEmulateNftTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -100000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'callContract',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 95824800n,
          status: 'completed',
          slug: 'toncoin',
          type: 'excess',
        },
      ],
      expectedRealFee: 6807229n, // 7005670n
    },
    {
      name: 'pick up sale NFT (fragment)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/fragment/pickUpSaleEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -100000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'callContract',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 95824800n,
          status: 'completed',
          slug: 'toncoin',
          type: 'excess',
        },
      ],
      expectedRealFee: 6839222n,
    },
    {
      name: 'place bid (fragment)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/fragment/placeBidEmulateTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -2000000000n,
          status: 'completed',
          slug: 'toncoin',
        },
      ],
      expectedRealFee: 2204041n,
    },
    {
      name: 'ton swap usdt (bidask)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/bidask/tonSwapUsdtTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -1500000000n,
          status: 'completed',
          slug: 'toncoin',
          type: 'callContract',
        },
        {
          kind: 'transaction',
          amount: 2202373n,
          slug: 'ton-eqcxe6mutq',
          isIncoming: true,
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 464808177n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 38079117n,
    },
    {
      name: 'usdt swap ton (bidask)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/bidask/usdtSwapTonTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          amount: -1000000n,
          slug: 'ton-eqcxe6mutq',
          isIncoming: false,
          status: 'completed',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 918967397n,
          status: 'completed',
          slug: 'toncoin',
        },
        {
          kind: 'transaction',
          amount: 975358597n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 39872842n,
    },
    {
      name: 'usdt swap tgusd (bidask)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/bidask/usdtSwapTgusdTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -1000000n,
          status: 'completed',
          slug: 'ton-eqcxe6mutq',
        },
        {
          kind: 'transaction',
          isIncoming: true,
          amount: 1000948n,
          status: 'completed',
          slug: 'ton-eqcj7asxok',
        },
        {
          kind: 'transaction',
          amount: 506814520n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 56669485n,
    },
    {
      name: 'transfer token (ton minter)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/transferTokenTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -1000000000n,
          status: 'completed',
          slug: 'ton-eqa60e89jy',
        },
        {
          kind: 'transaction',
          amount: 16951968n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 35888836n,
    },
    {
      name: 'usdt swap build 2 split (swap coffee)',
      walletAddress: 'UQC5p9zhlDG1YEQlTGmFjo3BH-xcB2He1BXjhvvktOEW9Xi0',
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      traceResponse: require('./testData/swapCoffee/usdtSwapBuild2SplitTraceResponse.json'),
      expectedActivities: [
        {
          kind: 'transaction',
          isIncoming: false,
          amount: -17288589n,
          status: 'completed',
          slug: 'ton-eqcxe6mutq',

        },
        {
          kind: 'swap',
          from: 'ton-eqcxe6mutq',
          fromAmount: '12.711411',
          to: 'ton-eqbynurilw',
          toAmount: '147.049519323',
          status: 'completed',
        },
        {
          kind: 'transaction',
          amount: 380918669n,
          slug: 'toncoin',
          isIncoming: true,
          type: 'excess',
          status: 'completed',
        },
      ],
      expectedRealFee: 494980102n,
    },
  ];

  beforeAll(async () => {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    jest.spyOn(require('../../common/backend'), 'callBackendGet')
      .mockResolvedValue({
        knownAddresses: {},
        scamMarkers: [],
        trustedSites: [],
        trustedCollections,
        tonNftSuperCollections: [],
      });

    await tryUpdateKnownAddresses();
  });

  test.each(testCases)('$name', (params) => {
    const {
      walletAddress,
      traceResponse,
      expectedActivities,
      expectedRealFee,
    } = params;

    const emulationResponse = 'traces' in traceResponse ? convertTraceToEmulation(traceResponse) : traceResponse;
    const result = parseEmulation('mainnet', walletAddress, emulationResponse, {});

    expect(result.realFee).toBe(expectedRealFee);
    expect(result.activities).toEqual(
      expectedActivities.map((expectedActivity) => expect.objectContaining(expectedActivity)),
    );
  });
});

function convertTraceToEmulation(traceResponse: TracesResponse): EmulationResponse {
  const trace = traceResponse.traces[0];

  if (!trace) {
    throw new Error('No traces found in TracesResponse');
  }

  return {
    mc_block_seqno: parseInt(trace.mc_seqno_end, 10),
    trace: trace.trace,
    actions: trace.actions,
    transactions: trace.transactions,
    account_states: {},
    rand_seed: '',
    metadata: traceResponse.metadata,
    address_book: traceResponse.address_book,
  };
}
