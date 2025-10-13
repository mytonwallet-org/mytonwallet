import type { DeviceModelId } from '@ledgerhq/devices';
import type { Address, Cell } from '@ton/core';
import type { TonPayloadFormat, TonTransport } from '@ton-community/ton-ledger';
import { KNOWN_JETTONS } from '@ton-community/ton-ledger';
import { parseMessage } from '@ton-community/ton-ledger';

import type { ApiNetwork, ApiTonWallet } from '../../../types';
import type { ApiTonWalletVersion, PreparedTransactionToSign, TonTransferHints } from '../types';
import { ApiHardwareError } from '../../../types';

import { logDebug, logDebugError } from '../../../../util/logs';
import { resolveTokenAddress, toBase64Address } from '../util/tonCore';
import { ledgerTransport } from '../../../common/ledger';
import { ATTEMPTS, TRANSFER_TIMEOUT_SEC, WORKCHAIN } from '../constants';
import {
  doesSupport,
  doesSupportKnownJetton,
  doesSupportKnownJettonId,
  doesSupportNonZeroQueryId,
  VERSION_WITH_GET_SETTINGS,
  VERSION_WITH_PAYLOAD,
  VERSION_WITH_WALLET_SPECIFIERS,
} from './support';
import { doesLedgerDeviceMatch, getLedgerAccountPathByWallet, handleLedgerTonError, tonTransport } from './utils';

export type LedgerTransactionParams = Parameters<TonTransport['signTransaction']>[1];

export const knownJettonAddresses = Object.fromEntries(
  KNOWN_JETTONS.map(({ masterAddress }, jettonId) => [
    toBase64Address(masterAddress, true, 'mainnet'),
    jettonId,
  ]),
);

/** Thrown when and only when the Ledger TON app needs to be updated to support this transaction */
export const unsupportedError = new Error('Unsupported');

export const lacksBlindSigningError = new Error('Lacks blind signing');

/**
 * Signs the given TON transactions using Ledger. Because Ledger can't sign multiple messages at once, each transaction
 * must contain exactly 1 message, and the transactions will be signed one by one. If everything is ok, returns the
 * signed transactions in the same order as the input transactions.
 */
export async function signTonTransactionsWithLedger(
  network: ApiNetwork,
  wallet: ApiTonWallet,
  tonTransactions: PreparedTransactionToSign[],
  subwalletId?: number,
  isTonConnect?: boolean,
  maxRetries = ATTEMPTS,
): Promise<Cell[] | { error: ApiHardwareError }> {
  const accountPath = getLedgerAccountPathByWallet(network, wallet);
  let ledgerTransactions: LedgerTransactionParams[];

  try {
    if (!await doesLedgerDeviceMatch(network, wallet)) {
      return { error: ApiHardwareError.WrongDevice };
    }

    const deviceModel = await ledgerTransport.getDeviceModel();
    const ledgerTonVersion = await tonTransport.getVersion();
    const isBlindSigningEnabled = await getIsBlindSigningEnabled(ledgerTonVersion);

    // To improve the UX, making sure all the transactions are signable before asking the user to sign them
    ledgerTransactions = await Promise.all(tonTransactions.map((tonTransaction) => (
      tonTransactionToLedgerTransaction(
        network,
        wallet.version,
        tonTransaction,
        deviceModel?.id,
        ledgerTonVersion,
        isBlindSigningEnabled,
        subwalletId,
        isTonConnect,
      )
    )));
  } catch (err) {
    if (err === unsupportedError) return { error: ApiHardwareError.HardwareOutdated };
    if (err === lacksBlindSigningError) return { error: ApiHardwareError.BlindSigningNotEnabled };
    return handleLedgerTonError(err);
  }

  return signLedgerTransactionsWithRetry(accountPath, ledgerTransactions, maxRetries);
}

async function getIsBlindSigningEnabled(ledgerTonVersion: string) {
  if (!doesSupport(ledgerTonVersion, VERSION_WITH_GET_SETTINGS)) {
    return true; // If Ledger actually doesn't allow blind signing, it will throw an error later
  }

  const { blindSigningEnabled } = await tonTransport.getSettings();
  return blindSigningEnabled;
}

/**
 * Converts a transaction, that you would pass to `TonWallet.createTransfer`, to the format suitable for Ledger's
 * `TonTransport.signTransaction`.
 */
export async function tonTransactionToLedgerTransaction(
  network: ApiNetwork,
  walletVersion: ApiTonWalletVersion,
  tonTransaction: PreparedTransactionToSign,
  ledgerModel: DeviceModelId | undefined,
  ledgerTonVersion: string,
  isBlindSigningEnabled: boolean,
  subwalletId?: number,
  isTonConnect?: boolean,
): Promise<LedgerTransactionParams> {
  const { authType = 'external', sendMode = 0, seqno, timeout, hints } = tonTransaction;
  const message = getMessageFromTonTransaction(tonTransaction);

  if (authType !== 'external') {
    throw new Error(`Unsupported transaction authType "${authType}"`);
  }
  if (message.info.type !== 'internal') {
    throw new Error(`Unsupported message type "${message.info.type}"`);
  }

  const payload = await getPayload(
    network,
    message.info.dest,
    message.body,
    ledgerModel,
    ledgerTonVersion,
    isBlindSigningEnabled,
    hints,
    isTonConnect,
  );

  return {
    to: message.info.dest,
    sendMode,
    seqno,
    timeout: timeout ?? getFallbackTimeout(),
    bounce: message.info.bounce,
    amount: message.info.value.coins,
    stateInit: message.init ?? undefined,
    payload,
    walletSpecifiers: getWalletSpecifiers(walletVersion, ledgerTonVersion, subwalletId),
  };
}

function getMessageFromTonTransaction({ messages }: PreparedTransactionToSign) {
  if (messages.length === 0) throw new Error('No messages');
  if (messages.length > 1) throw new Error('Ledger doesn\'t support signing more than 1 message');
  return messages[0];
}

function getFallbackTimeout() {
  return Math.floor(Date.now() / 1000 + TRANSFER_TIMEOUT_SEC);
}

/**
 * Like `tonPayloadToLedgerPayload`, but also performs long asynchronous operations such as fetching data for the
 * `knownJetton` field.
 */
async function getPayload(
  network: ApiNetwork,
  toAddress: Address,
  tonPayload: Cell | undefined,
  ledgerModel: DeviceModelId | undefined,
  ledgerTonVersion: string,
  isBlindSigningEnabled: boolean,
  { tokenAddress }: TonTransferHints = {},
  isTonConnect?: boolean,
) {
  const ledgerPayload = tonPayloadToLedgerPayload(tonPayload, ledgerTonVersion, isTonConnect);

  if (ledgerPayload?.type === 'jetton-transfer' && doesSupportKnownJetton(ledgerModel, ledgerTonVersion)) {
    if (!tokenAddress) {
      const tokenWalletAddress = toBase64Address(toAddress, true, network);
      tokenAddress = await resolveTokenAddress(network, tokenWalletAddress);
    }

    if (tokenAddress) {
      ledgerPayload.knownJetton = getKnownJetton(ledgerTonVersion, tokenAddress);
    }
  }

  if (ledgerPayload?.type === 'unsafe' && !isBlindSigningEnabled) {
    throw lacksBlindSigningError;
  }

  return ledgerPayload;
}

/**
 * Converts a TON message body to the Ledger payload format. Doesn't populate the `knownJetton` field.
 */
export function tonPayloadToLedgerPayload(
  tonPayload: Cell | undefined,
  ledgerTonVersion: string,
  isTonConnect?: boolean,
) {
  if (!tonPayload) {
    return undefined;
  }

  let ledgerPayload: TonPayloadFormat | undefined;

  try {
    const options = isTonConnect ? {
      // Modifying the payload generated in the dApp can lead to unpredictable errors
      // (for example, an NFT may get stuck in the contract).
      disallowModification: true,
    } : {
      disallowUnsafe: true, // Otherwise no error will be thrown, and we won't see why the payload can't be converted
      // We don't use `disallowModification: true`, because it can cause an unnecessary "unsafe" payload, for example,
      // when a token is transferred with a short comment. On the other hand, the fee may increase by about 0.0001 TON.
    };
    ledgerPayload = parseMessage(tonPayload, options);
  } catch (err) {
    logDebug('Unsafe Ledger payload', err);
    ledgerPayload = {
      type: 'unsafe',
      message: tonPayload,
    };
  }

  if (
    ledgerPayload
    && 'queryId' in ledgerPayload
    && typeof ledgerPayload.queryId === 'bigint'
    && ledgerPayload.queryId > 0n
    && !doesSupportNonZeroQueryId(ledgerTonVersion)
  ) {
    logDebug(`A non-zero queryId is being used on a TON App version v${ledgerTonVersion} where this is broken.`);
    if (!doesSupport(ledgerTonVersion, VERSION_WITH_PAYLOAD.unsafe)) {
      throw unsupportedError;
    }

    logDebug('Falling back to an unsafe payload');
    ledgerPayload = {
      type: 'unsafe',
      message: tonPayload,
    };
  }

  if (ledgerPayload && !doesSupport(ledgerTonVersion, VERSION_WITH_PAYLOAD[ledgerPayload.type])) {
    logDebug(`The ${ledgerPayload.type} payload type is not supported by Ledger TON v${ledgerTonVersion}`);
    if (!doesSupport(ledgerTonVersion, VERSION_WITH_PAYLOAD.unsafe)) {
      throw unsupportedError;
    }

    logDebug('Falling back to an unsafe payload');
    ledgerPayload = {
      type: 'unsafe',
      message: tonPayload,
    };
  }

  return ledgerPayload;
}

async function signLedgerTransactionsWithRetry(
  accountPath: number[],
  ledgerTransactions: LedgerTransactionParams[],
  maxRetries: number,
) {
  const signedTransactions: Cell[] = [];
  let retryCount = 0;
  let index = 0;

  while (index < ledgerTransactions.length) {
    try {
      signedTransactions.push(await tonTransport.signTransaction(accountPath, ledgerTransactions[index]));
      index++;
    } catch (err) {
      try {
        return handleLedgerTonError(err);
      } catch {
        if (retryCount >= maxRetries) {
          throw err;
        }
        retryCount++;
      }
      logDebugError('signLedgerTransactionsWithRetry', err);
    }
  }

  return signedTransactions;
}

function getKnownJetton(ledgerTonVersion: string, tokenAddress: string) {
  const jettonId = knownJettonAddresses[tokenAddress];
  return jettonId !== undefined && doesSupportKnownJettonId(ledgerTonVersion, jettonId)
    ? { jettonId, workchain: WORKCHAIN }
    : null; // eslint-disable-line no-null/no-null
}

function getWalletSpecifiers(walletVersion: ApiTonWalletVersion, ledgerTonVersion: string, subwalletId?: number) {
  if (walletVersion === 'v3R2') {
    if (!doesSupport(ledgerTonVersion, VERSION_WITH_WALLET_SPECIFIERS)) throw unsupportedError;
    return { includeWalletOp: false };
  }
  if (subwalletId !== undefined) {
    if (!doesSupport(ledgerTonVersion, VERSION_WITH_WALLET_SPECIFIERS)) throw unsupportedError;
    return { subwalletId, includeWalletOp: false };
  }
  return undefined;
}
