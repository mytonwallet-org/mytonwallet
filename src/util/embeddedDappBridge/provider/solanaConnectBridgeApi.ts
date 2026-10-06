import { getActions, getGlobal } from '../../../global';

import type {
  DappProtocolType,
  DappSessionChain,
  DappSignDataRequest,
  DappTransactionRequest,
} from '../../../api/dappProtocols';
import type { WalletConnectSessionProposal } from '../../../api/dappProtocols/adapters/walletConnect/types';
import type { StandardWalletAddress } from '../../injectedConnector/solanaConnector';

import { callApi } from '../../../api';
import { base58FromUint8Array, base64FromBuffer, uint8ArrayFromBase58 } from '../../casting';
import { logDebugError } from '../../logs';

export interface BrowserSolanaConnectBridgeMethods {
  connect(
    metadata: {
      url: string;
      name: string;
      description: string;
      icons: string[];
    },
    silent?: boolean
  ): Promise<{ accounts: StandardWalletAddress[] }>;

  signTransaction(
    input: {
      account: { address: string; chains: string[]; features: string[] };
      transaction: Record<number, number>;
    }): Promise<{ signedTransaction: Uint8Array }[]>;

  signMessage(
    input: {
      account: { address: string; chains: string[]; features: string[] };
      message: Uint8Array;
    }): Promise<{ signature: Uint8Array; signedMessage: Uint8Array }[]>;

  disconnect(): Promise<void>;
}

let requestId = 0;

export function buildSolanaConnectBridgeApi(pageUrl: string): BrowserSolanaConnectBridgeMethods | undefined {
  const {
    openLoadingOverlay,
    closeLoadingOverlay,
  } = getActions();

  const url = new URL(pageUrl).origin.toLowerCase();

  const features = [
    'standard:connect',
    'standard:disconnect',
    'standard:events',
    'solana:signTransaction',
    'solana:signMessage',
    'solana:signIn',
  ];

  function mapSessionChainsToAccounts(chains: DappSessionChain[]): StandardWalletAddress[] {
    return chains.filter((chain) => chain.chain === 'solana').map((chain) => ({
      address: chain.address,
      publicKey: new Uint8Array(uint8ArrayFromBase58(chain.address)),
      chains: [`${chain.chain}:${chain.network === 'mainnet' ? 'mainnet' : 'devnet'}`],
      features,
    }));
  }

  async function connectSilent(): Promise<{ accounts: StandardWalletAddress[] }> {
    const response = await callApi(
      'walletConnect_reconnect',
      buildDappRequest(url),
      requestId,
    );

    if (!response?.success) {
      return { accounts: [] };
    }

    return { accounts: mapSessionChainsToAccounts(response.session.chains) };
  }

  async function connectWithModal(
    metadata: {
      url: string;
      name: string;
      description: string;
      icons: string[];
    },
  ): Promise<{ accounts: StandardWalletAddress[] }> {
    openLoadingOverlay();

    const payload: WalletConnectSessionProposal = {
      id: requestId,
      params: {
        id: requestId,
        expiryTimestamp: 0,
        relays: [],
        proposer: {
          publicKey: '',
          metadata,
        },
        requiredNamespaces: {},
        optionalNamespaces: {
          solana: {
            methods: [],
            events: [],
          },
        },
        pairingTopic: '',
      },
    };

    const response = await callApi(
      'walletConnect_connect',
      buildDappRequest(url),
      {
        protocolType: 'walletConnect',
        transport: 'inAppBrowser',
        protocolData: payload,
        permissions: {
          isAddressRequired: true,
          isPasswordRequired: false,
        },
        requestedChains: [{
          chain: 'solana',
          network: 'mainnet',
        }],
      },
      requestId,
    );

    closeLoadingOverlay();

    if (!response?.success) {
      return { accounts: [] };
    }

    requestId++;

    return { accounts: mapSessionChainsToAccounts(response.session.chains) };
  }

  return {
    connect: async (metadata, silent) => {
      try {
        if (silent) {
          return connectSilent();
        }

        return connectWithModal(metadata);
      } catch (err: any) {
        logDebugError('useDAppBridge:connect', err);

        closeLoadingOverlay();

        return { accounts: [] };
      }
    },

    disconnect: async () => {
      requestId = 0;

      await callApi(
        'walletConnect_disconnect',
        buildDappRequest(url),
        {
          requestId: requestId.toString(),
        },
      );
    },

    signTransaction: async (input) => {
      const unifiedPayload: DappTransactionRequest<DappProtocolType.WalletConnect> = {
        id: String(requestId),
        chain: 'solana',
        payload: {
          isSignOnly: true,
          url,
          address: input.account.address,
          data: base64FromBuffer(Buffer.from(Object.values(input.transaction))),
        },
      };

      const response = await callApi(
        'walletConnect_sendTransaction',
        buildDappRequest(url),
        unifiedPayload,
      );

      if (!response?.success) {
        return [];
      }

      return [{
        signedTransaction: new Uint8Array(uint8ArrayFromBase58(response.result.result)),
      }];
    },

    signMessage: async (input) => {
      const unifiedPayload: DappSignDataRequest<DappProtocolType.WalletConnect> = {
        id: String(requestId),
        chain: 'solana',
        payload: {
          url,
          address: input.account.address,
          data: base58FromUint8Array(new Uint8Array(Object.values(input.message))),
        },
      };

      const response = await callApi(
        'walletConnect_signData',
        buildDappRequest(url),
        unifiedPayload,
      );

      if (!response?.success) {
        return [];
      }

      return [{
        signature: new Uint8Array(uint8ArrayFromBase58(response.result.result)),
        signedMessage: input.message,
      }];
    },
  };
}

function buildDappRequest(origin: string) {
  return {
    url: origin,
    urlTrustStatus: 'verified' as const,
    accountId: getGlobal().currentAccountId,
  };
}
