import type { TonTransport } from '@ton-community/ton-ledger';

import type { ApiTonWalletVersion, ContractInfo, ContractName } from './types';

import {
  TONAPIIO_MAINNET_URL,
  TONAPIIO_TESTNET_URL,
  TONCENTER_MAINNET_URL,
  TONCENTER_TESTNET_URL,
} from '../../../config';
import { JettonStakingGas } from './contracts/JettonStaking/imports/constants';

export const TON_BIP39_PATH = 'm/44\'/607\'/0\'';

export const NETWORK_CONFIG = {
  mainnet: {
    toncenterUrl: TONCENTER_MAINNET_URL,
    tonApiIoUrl: TONAPIIO_MAINNET_URL,
    // W5 wallet chain IDs for different subwallet variants
    chainId: -239,
  },
  testnet: {
    toncenterUrl: TONCENTER_TESTNET_URL,
    tonApiIoUrl: TONAPIIO_TESTNET_URL,
    // W5 wallet chain IDs for different subwallet variants
    chainId: -3,
  },
};

export const ONE_TON = 1_000_000_000n;
export const TOKEN_TRANSFER_AMOUNT = 50000000n; // 0.05 TON
export const TINY_TOKEN_TRANSFER_AMOUNT = 18000000n; // 0.018 TON
export const TOKEN_TRANSFER_REAL_AMOUNT = 32100000n; // 0.0321 TON
export const TINY_TOKEN_TRANSFER_REAL_AMOUNT = 8000000n; // 0.008 TON
export const TINIEST_TOKEN_TRANSFER_REAL_AMOUNT = 3000000n; // 0.003 TON
export const TOKEN_TRANSFER_FORWARD_AMOUNT = 1n; // 0.000000001 TON
export const CLAIM_MINTLESS_AMOUNT = 20000000n; // 0.02 TON

/** The amount that MyTonWallet attaches to NFT transfers */
export const NFT_TRANSFER_AMOUNT = 100000000n; // 0.1 TON
export const NFT_TRANSFER_REAL_AMOUNT = 5000000n; // 0.005 TON
export const NFT_TRANSFER_FORWARD_AMOUNT = 1n; // 0.000000001 TON

/**
 * When the NFT contract handles the payload we send, it simply adds its data to the payload. If the resulting payload
 * size becomes greater than the cell capacity, the contract fails to send the NFT. To avoid that, we keep some free
 * space in the payload cell we send. This constant is the size of the free space in bits.
 */
export const NFT_PAYLOAD_SAFE_MARGIN = 14 * 8;

export const TON_GAS = {
  stakeNominators: ONE_TON,
  unstakeNominators: ONE_TON,
  stakeLiquid: ONE_TON,
  unstakeLiquid: ONE_TON,
  stakeJettonsForward: JettonStakingGas.STAKE_JETTONS,
  stakeJettons: JettonStakingGas.STAKE_JETTONS + TOKEN_TRANSFER_AMOUNT,
  unstakeJettons: JettonStakingGas.UNSTAKE_JETTONS,
  claimJettons: JettonStakingGas.JETTON_TRANSFER + JettonStakingGas.SIMPLE_UPDATE_REQUEST,
  changeDns: 15_000_000n, // 0.015 TON
  stakeEthena: TOKEN_TRANSFER_AMOUNT + 100_000_000n, // 0.15 TON
  stakeEthenaForward: 100_000_000n, // 0.1 TON
  unstakeEthena: TOKEN_TRANSFER_AMOUNT + 100_000_000n, // 0.15 TON
  unstakeEthenaForward: 100_000_000n, // 0.1 TON
  unstakeEthenaLocked: 150_000_000n, // 0.15 TON
  unstakeEthenaLockedForward: 70_000_000n, // 0.07 TON
} as const;

export const TON_GAS_REAL = {
  stakeNominators: 1_000_052_853n,
  unstakeNominators: 148_337_433n,
  stakeLiquid: 20_251_387n,
  unstakeLiquid: 18_625_604n,
  stakeJettons: 74_879_996n,
  unstakeJettons: 59_971_662n,
  claimJettons: 57_053_859n,
  stakeEthena: 116_690_790n,
  unstakeEthena: 113_210_330n,
  unstakeEthenaLocked: 37_612_000n,
};

export const STAKE_COMMENT = 'd';
export const UNSTAKE_COMMENT = 'w';

export const ATTEMPTS = 5;

export const DEFAULT_DECIMALS = 9;
export const DEFAULT_IS_BOUNCEABLE = true;
export const WALLET_IS_BOUNCEABLE = false;

// Fee may change, so we add 5% for more reliability. This is only safe for low-fee blockchains such as TON.
export const FEE_FACTOR = 1.05;

export const ALL_WALLET_VERSIONS: ApiTonWalletVersion[] = [
  'simpleR1', 'simpleR2', 'simpleR3', 'v2R1', 'v2R2', 'v3R1', 'v3R2', 'v4R2', 'W5',
];

export const OUR_FEE_PAYLOAD_BOC = 'te6cckEBAQEABgAACE0jhUPUcYAL';

export const RAW_ADDRESS_LENGTH = 66;

export enum Workchain {
  MasterChain = -1,
  BaseChain = 0,
}

export const WORKCHAIN = Workchain.BaseChain;
export const TRANSFER_TIMEOUT_SEC = 600; // 10 min.

export const DEFAULT_MAX_MESSAGES = 4;
export const LEDGER_MAX_MESSAGES = 1;
export const W5_MAX_MESSAGES = 255;

export const LEDGER_WALLET_VERSIONS = {
  v3R2: 'v3r2',
  v4R2: 'v4',
} as const satisfies Partial<Record<
  ApiTonWalletVersion,
  NonNullable<Parameters<TonTransport['getAddress']>[1]>['walletVersion']
>>;

export const LEDGER_DEFAULT_WALLET_VERSION: keyof typeof LEDGER_WALLET_VERSIONS = 'v4R2';
export const LEDGER_VESTING_SUBWALLET_ID = 0x10C;

export enum OpCode {
  Comment = 0,
  Encrypted = 0x2167da4b,
  OurFee = 0x4d238543,
  Bounced = 0xffffffff,
}

export enum JettonOpCode {
  Transfer = 0xf8a7ea5,
  TransferNotification = 0x7362d09c,
  InternalTransfer = 0x178d4519,
  Excesses = 0xd53276db,
  Burn = 0x595f07bc,
  BurnNotification = 0x7bdd97de,
}

export enum NftOpCode {
  TransferOwnership = 0x5fcc3d14,
  OwnershipAssigned = 0x05138d91,
  Excesses = 0xd53276db,
}

export enum LiquidStakingOpCode {
  // Pool
  RequestLoan = 0xe642c965,
  LoanRepayment = 0xdfdca27b,
  Deposit = 0x47d54391,
  Withdraw = 0x319B0CDC,
  Withdrawal = 0x0a77535c,
  DeployController = 0xb27edcad,
  Touch = 0x4bc7c2df,
  Donate = 0x73affe21,
  // NFT
  DistributedAsset = 0xdb3b8abd,
  // Jetton
  Vote = 0x69fb306c,
}

export enum JettonStakingOpCode {
  UnstakeRequest = 0x499a9262,
  ClaimRewards = 0x78d9f109,
}

export enum VestingV1OpCode {
  AddWhitelist = 0x7258a69b,
}

export enum SingleNominatorOpCode {
  Withdraw = 0x1000,
  ChangeValidator = 0x1001,
}

export enum DnsOpCode {
  ChangeRecord = 0x4eb1f0f9,
}

export enum TeleitemOpCode {
  Ok = 0xa37a0983,
}

export enum OtherOpCode {
  TokenBridgePaySwap = 0x8,
}

export enum BidaskOpCode {
  Swap = 0xc09da84e,
  NativeTransferNotification = 0x6edd65f0,
}

export enum ContractType {
  Wallet = 'wallet',
  Staking = 'staking',
}

export enum DnsCategory {
  DnsNextResolver = 'dns_next_resolver',
  Wallet = 'wallet',
  Site = 'site',
  BagId = 'storage',
  Unknown = 'unknown',
}

export const EXCESS_OP_CODES = [
  JettonOpCode.Excesses,
  TeleitemOpCode.Ok,
  0x80f4c55b, // StormTrade excess
  0x76dbd306, // Stonfi excess
];

export const DNS_CATEGORY_HASH_MAP = {
  dns_next_resolver: '19f02441ee588fdb26ee24b2568dd035c3c9206e11ab979be62e55558a1d17ff',
  wallet: 'e8d44050873dba865aa7c170ab4cce64d90839a34dcfd6cf71d14e0205443b1b',
  site: 'fbae041b02c41ed0fd8a4efb039bc780dd6af4a1f0c420f42561ae705dda43fe',
  storage: '49a25f9feefaffecad0fcd30c50dc9331cff8b55ece53def6285c09e17e6f5d7',
} as const;

export const KnownContracts: Record<ContractName, ContractInfo> = {
  simpleR1: {
    name: 'simpleR1',
    oldHash: '3232dc55b02b3d2a9485adc151cf29c50b94c374d3571cb59390d761b87af8bd',
    type: ContractType.Wallet,
  },
  simpleR2: {
    name: 'simpleR2',
    oldHash: '672ce2b01d2fd487a5e0528611e7e4fc11867148cc13ff772bd773b72fb368df',
    type: ContractType.Wallet,
  },
  simpleR3: {
    name: 'simpleR3',
    oldHash: 'd95417233f66ae218317f533630cbbddc677d6d893d5722be6947c8fad8e9d52',
    type: ContractType.Wallet,
  },
  v2R1: {
    name: 'v2R1',
    oldHash: 'fb3bd539b7e50166f1cfdc0bbd298b1c88f6b261fe5ee61343ea47ab4b256029',
    type: ContractType.Wallet,
  },
  v2R2: {
    name: 'v2R2',
    oldHash: 'b584b6106753b7f34709df505be603e463a44ff6a85adf7fec4e26453c325983',
    type: ContractType.Wallet,
  },
  v3R1: {
    name: 'v3R1',
    oldHash: '11d123ed5c2055128e75a9ef4cf1e837e6d14a9c079c39939885c78dc13626e6',
    type: ContractType.Wallet,
  },
  v3R2: {
    name: 'v3R2',
    oldHash: 'df7bf014ee7ac0c38da19ef1b7fa054e2cc7a4513df1f1aa295109cf3606ac14',
    type: ContractType.Wallet,
  },
  v4R1: {
    name: 'v4R1',
    oldHash: '1bc0dfa40956c911616f8a5db09ecc217601bae48d7d3f9311562c5afcb66dcf',
    type: ContractType.Wallet,
  },
  v4R2: {
    name: 'v4R2',
    oldHash: '5659ce2300f4a09a37b0bdee41246ded52474f032c1d6ffce0d7d31b18b7b2b1',
    type: ContractType.Wallet,
  },
  W5: {
    name: 'W5',
    oldHash: '7e94eaaeaaa423b9396e79747038c42edc4fe98dce65094071f0e0ad2df22fd5',
    type: ContractType.Wallet,
  },
  highloadV2: {
    name: 'highloadV2',
    oldHash: 'fcd7d1f3b3847f0b9bd44bc64a2256c03450979dd1646a24fbc874b075392d6e',
    type: ContractType.Wallet,
  },
  nominatorPool: {
    name: 'nominatorPool',
    oldHash: '26faa2d0fd2a8197ea36ded8dc50ad081cce5244207e9b05c08c1bb655527bff',
    type: ContractType.Staking,
  },
  multisig: {
    name: 'multisig',
    oldHash: '45d890485cdd6b152bcbbe3fb2e16d2df82f6da840440a5b9f34ea13cb0b92d2',
    type: ContractType.Wallet,
  },
  multisigV2: {
    name: 'multisigV2',
    oldHash: 'eb1323c5544d5bf26248dc427d108d722d5c2922dd97dd0bdf903c4cea73ca97',
    type: ContractType.Wallet,
  },
  vesting: {
    name: 'vesting',
    oldHash: '69dc931958f7aa203c4a7bfcf263d25d2d828d573184b542a65dd55c8398ad83',
    type: ContractType.Wallet,
  },
  multisigNew: {
    name: 'multisigNew',
    oldHash: '7cb3678880388acff45d74b2e7e7544caa8039d20b49f57c75b53c051b6fa30f',
    type: ContractType.Wallet,
  },
  dedustPool: {
    name: 'dedustPool',
    oldHash: 'f216ded2b43d32e2d487db6fa6e4d2387f0ef1d7b53ec1ad85f0b4feb8e4ed62',
    isSwapAllowed: true,
  },
  dedustVaultNative: {
    name: 'dedustVaultNative',
    oldHash: '64a42ad66688097422901ae6188670f0d6292ad3bdb4139289666f24187e86cb',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQAYqo4u7VF0fa4DPAebk4g9lBytj2VFny7pzXR0trjtXQaO
  dedustVaultJetton: {
    name: 'dedustVaultJetton',
    oldHash: '5bc82f0c5972ccc6732e98cbe31ea4795da818f9e06c991331568182a8362307',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQARULUYsmJq1RiZ-YiH-IJLcAZUVkVff-KBPwEmmaQGH6aC
  stonPtonWallet: {
    name: 'stonPtonWallet',
    hash: '8836d2f41b39cd2cbdd8a66c10f9665d075242a66003bd8f14485bd6b140d303',
    isSwapAllowed: true,
  },
  stonRouter: {
    name: 'stonRouter',
    oldHash: '14ce618a0e9a94adc99fa6e975219ddd675425b30dfa9728f98714c8dc55f9da',
    isSwapAllowed: true,
  },
  stonRouterV2_1: {
    name: 'stonRouterV2_1',
    oldHash: 'd61cb7fb7bee0cc414286a482fccdec53c3f8717e4aae4fc362d98ab6254e6cd',
    isSwapAllowed: true,
  },
  stonPoolV2_1: {
    name: 'stonPoolV2_1',
    oldHash: '16cc513c380e329f45d54f294787e2030e289799eca138961c1cd7e26e882c7c',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQCS4UEa5UaJLzOyyKieqQOQ2P9M-7kXpkO5HnP3Bv250cN3
  stonRouterV2_2: {
    name: 'stonRouterV2_2',
    oldHash: '094b5084111addda1b6fac7007c8a8f85ff4ccc63475815ab3dfa3b5b4c6b102',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQBSNX_5mSikBVttWhIaIb0f8jJU7fL6kvyyFVppd7dWRO6M
  stonRouterV2_2_alt: {
    name: 'stonRouterV2_2_alt',
    oldHash: 'd41e7563afa05ee008655e190920d3f53de9cab4c2d4e10ee1d0f158e95e52e5',
    isSwapAllowed: true,
  },
  stonPoolV2_2: {
    name: 'stonPoolV2_2',
    oldHash: '11eaf6db706e63adf9327897aaa845c77a631856abfc14375837f19b617cacb4',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQBiLHuQjDj4fNyCD7Ch5HwpNGldlb5g-LMwQ1kStQ4NM5kv
  stonPtonWalletV2: {
    name: 'stonPtonWalletV2',
    oldHash: '2761042202032258de9eb1b672e1ec2e4f13b2af00700195801ada33f7ced1b6',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQC_-t0nCnOFMdp7E7qPxAOCbCWGFz-e3pwxb6tTvFmshjt5
  toncoRouter: {
    name: 'toncoRouter',
    hash: '9b9891eaa7db7becc6ccdda1bd9a8d25dc3df2817d57e4b27ec003daf81a4439',
    isSwapAllowed: true,
  },
  // Example: https://tonscan.org/address/EQCHHakhWxSQIWbw6ioW21YnjVKBCDd_gVjF9Mz9_dIuFy23
  wrappedToncoTonWallet: {
    name: 'wrappedToncoTonWallet',
    hash: 'c16fb5d47aa4f0ad23057d34490e6f26a62c71e6422e4f6a8648126857c71438',
    isSwapAllowed: true,
  },
  // `oldHash` should no longer be used for new contracts; it is retained for backwards compatibility with
  // contracts for which retrieving the new hash is difficult due to missing address tracking in past.
  // The `hash` field has been added for new contracts. It is a hex hash of the code,
  // and is available on both Tonviewer and Tonscan. Don't forget to add an example link when adding a new contract.
};
