/*
 * This file must be imported dynamically via import().
 * This is needed to reduce the app size when Ledger is not used.
 */

import type { DeviceModelId } from '@ledgerhq/devices';
import { TransportStatusError } from '@ledgerhq/errors';
import type { Address, Cell } from '@ton/core';
import type { TonPayloadFormat } from '@ton-community/ton-ledger';
import { KNOWN_JETTONS, parseMessage, TonTransport } from '@ton-community/ton-ledger';

import type { ApiTonConnectProof } from '../../../tonConnect/types';
import type { ApiNetwork, ApiTonWallet } from '../../../types';
import type { ApiTonWalletVersion, PreparedTransactionToSign, TonTransferHints } from '../types';
import { ApiHardwareError } from '../../../types';

import compareVersions from '../../../../util/compareVersions';
import { getLedgerAccountPathByWallet } from '../../../../util/ledger/utils';
import { logDebug, logDebugError } from '../../../../util/logs';
import { WindowTransport } from '../../../common/ledger';
import { ATTEMPTS, TRANSFER_TIMEOUT_SEC, WORKCHAIN } from '../constants';
import { resolveTokenAddress, toBase64Address } from './tonCore';

export type LedgerTransactionParams = Parameters<TonTransport['signTransaction']>[1];

// You can use the https://github.com/LedgerHQ/app-ton history as the version support reference
// Warning! The versions MUST NOT be lower than the actual versions that added support for these features. Otherwise,
// that features fail. If you are not sure, set the version to a higher value. In that case Ledger will display the
// transactions as blind/unknown, but will be able to sign them.
const VERSION_WITH_GET_SETTINGS = '2.1';
const VERSION_WITH_WALLET_SPECIFIERS = '2.1';
/** The values are the TON App versions. The keys are the largest jetton ids (jetton indices) added in that versions. */
const VERSION_WITH_JETTON_ID = {
  6: '2.2',
  9: '2.6.1',
  10: '2.8.0', // TODO Replace to real version
};
const VERSION_WITH_PAYLOAD: Record<TonPayloadFormat['type'], string> = {
  unsafe: '2.1',
  comment: '0',
  'jetton-transfer': '0',
  'nft-transfer': '2.1',
  'jetton-burn': '2.1',
  'add-whitelist': '2.1',
  'single-nominator-withdraw': '2.1',
  'single-nominator-change-validator': '2.1',
  'tonstakers-deposit': '2.1',
  'vote-for-proposal': '2.1',
  'change-dns-record': '2.1',
  'token-bridge-pay-swap': '2.1',
  'tonwhales-pool-deposit': '2.7',
  'tonwhales-pool-withdraw': '2.7',
  'vesting-send-msg-comment': '2.7',
};

// https://github.com/LedgerHQ/app-ton/blob/d3e1edbbc1fcf9a5d6982fbb971f757a83d0aa56/doc/MESSAGES.md?plain=1#L51
const DEVICES_NOT_SUPPORTING_JETTON_ID = new Set<`${DeviceModelId}`>(['nanoS']);

const knownJettonAddresses = Object.fromEntries(
  KNOWN_JETTONS.map(({ masterAddress }, jettonId) => [
    toBase64Address(masterAddress, true, 'mainnet'),
    jettonId,
  ]),
);

const ledgerTransport = new WindowTransport();
const tonTransport = new TonTransport(ledgerTransport);

/** Thrown when and only when the Ledger TON app needs to be updated to support this transaction */
export const unsupportedError = new Error('Unsupported');

export const lacksBlindSigningError = new Error('Lacks blind signing');

export async function signTonProofWithLedger(
  network: ApiNetwork,
  wallet: ApiTonWallet,
  proof: ApiTonConnectProof,
): Promise<Buffer | { error: ApiHardwareError }> {
  const accountPath = getLedgerAccountPathByWallet(network, wallet);
  const { timestamp, domain, payload } = proof;

  try {
    const result = await tonTransport.getAddressProof(accountPath, {
      domain,
      timestamp,
      payload: Buffer.from(payload),
    });
    return result.signature;
  } catch (err) {
    return handleLedgerError(err);
  }
}

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
  maxRetries = ATTEMPTS,
): Promise<Cell[] | { error: ApiHardwareError }> {
  const accountPath = getLedgerAccountPathByWallet(network, wallet);
  const deviceModel = await ledgerTransport.getDeviceModel();
  const ledgerTonVersion = await tonTransport.getVersion();
  const isBlindSigningEnabled = await getIsBlindSigningEnabled(ledgerTonVersion);
  let ledgerTransactions: LedgerTransactionParams[];

  // To improve the UX, making sure all the transactions are signable before asking the user to sign them
  try {
    ledgerTransactions = await Promise.all(tonTransactions.map((tonTransaction) => (
      tonTransactionToLedgerTransaction(
        network,
        wallet.version,
        tonTransaction,
        deviceModel?.id,
        ledgerTonVersion,
        isBlindSigningEnabled,
        subwalletId,
      )
    )));
  } catch (err) {
    if (err === unsupportedError) return { error: ApiHardwareError.HardwareOutdated };
    if (err === lacksBlindSigningError) return { error: ApiHardwareError.BlindSigningNotEnabled };
    throw err;
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
 *
 * Exported for tests only.
 */
export async function tonTransactionToLedgerTransaction(
  network: ApiNetwork,
  walletVersion: ApiTonWalletVersion,
  tonTransaction: PreparedTransactionToSign,
  ledgerModel: DeviceModelId | undefined,
  ledgerTonVersion: string,
  isBlindSigningEnabled: boolean,
  subwalletId?: number,
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
) {
  const ledgerPayload = tonPayloadToLedgerPayload(tonPayload, ledgerTonVersion);

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
 *
 * Exported for tests only.
 */
export function tonPayloadToLedgerPayload(tonPayload: Cell | undefined, ledgerTonVersion: string) {
  if (!tonPayload) {
    return undefined;
  }

  let ledgerPayload: TonPayloadFormat | undefined;

  try {
    ledgerPayload = parseMessage(tonPayload, {
      disallowUnsafe: true, // Otherwise no error will be thrown, and we won't see why the payload can't be converted
      // We don't use `disallowModification: true`, because it can cause an unnecessary "unsafe" payload, for example,
      // when a token is transferred with a short comment. On the other hand, the fee may increase by about 0.0001 TON.
    });
  } catch (err) {
    logDebug('Unsafe Ledger payload', err);
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
        return handleLedgerError(err);
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

function doesSupport(ledgerTonVersion: string, featureVersion: string) {
  return compareVersions(ledgerTonVersion, featureVersion) >= 0;
}

/**
 * Checks whether the current Ledger device supports `knownJetton` generally
 */
function doesSupportKnownJetton(ledgerModel: DeviceModelId | undefined, ledgerTonVersion: string) {
  return ledgerModel // If the Ledger model is unknown, assuming it can be any model and acting safely
    && !DEVICES_NOT_SUPPORTING_JETTON_ID.has(ledgerModel)
    // Note: JavaScript sorts the numeric `VERSION_WITH_JETTON_ID` keys in ascending order automatically
    && doesSupport(ledgerTonVersion, Object.values(VERSION_WITH_JETTON_ID)[0]);
}

function getKnownJetton(ledgerTonVersion: string, tokenAddress: string) {
  const jettonId = knownJettonAddresses[tokenAddress];
  return jettonId !== undefined && doesSupportKnownJettonId(ledgerTonVersion, jettonId)
    ? { jettonId, workchain: WORKCHAIN }
    : null; // eslint-disable-line no-null/no-null
}

/**
 * Checks that the current Ledger device supports the specific jetton id. This function should be used only if
 * `doesSupportKnownJetton` returns `true`, because it doesn't check what that function checks.
 */
function doesSupportKnownJettonId(ledgerTonVersion: string, jettonId: number) {
  // Note: JavaScript sorts the numeric `VERSION_WITH_JETTON_ID` keys in ascending order automatically
  for (const [candidateJettonId, candidateVersion] of Object.entries(VERSION_WITH_JETTON_ID)) {
    if (jettonId <= Number(candidateJettonId)) {
      return doesSupport(ledgerTonVersion, candidateVersion);
    }
  }

  logDebugError(`The supported version of jetton id ${jettonId} is not set in VERSION_WITH_JETTON_ID`);
  return false;
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

/** Throws unexpected errors (i.e. caused by mistakes in the app code), and returns expected */
function handleLedgerError(error: unknown) {
  if (error instanceof TransportStatusError) {
    // Status code reference: https://github.com/LedgerHQ/app-ton/blob/d3e1edbbc1fcf9a5d6982fbb971f757a83d0aa56/src/sw.h
    switch (error.statusCode) {
      case 0x6985: return { error: ApiHardwareError.RejectedByUser };
      case 0xbd00: return { error: ApiHardwareError.BlindSigningNotEnabled };
      // The limits for Ton Connect proofs are: payload ≤ 128 bytes, domain ≤ 128 bytes, payload + domain ≤ 222 bytes
      case 0xb00b: return { error: ApiHardwareError.ProofTooLarge };
    }
  }

  throw error;
}
