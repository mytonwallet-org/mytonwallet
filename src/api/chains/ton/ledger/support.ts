import type { DeviceModelId } from '@ledgerhq/devices';
import type { TonPayloadFormat } from '@ton-community/ton-ledger';

import compareVersions from '../../../../util/compareVersions';
import { logDebugError } from '../../../../util/logs';

// You can use the https://github.com/LedgerHQ/app-ton history as the version support reference.
// Warning! The versions MUST NOT be lower than the actual versions that added support for these features. Otherwise,
// signing that transactions WILL FAIL. If you are not sure, set the version to a higher value. In that case Ledger will
// display the transactions as blind/unknown, but will be able to sign them.

export const VERSION_WITH_GET_SETTINGS = '2.1';
export const VERSION_WITH_WALLET_SPECIFIERS = '2.1';
export const VERSION_WITH_BROKEN_QUERY_ID = { min: '2.7.0', max: '2.8.0' };

/** The values are the TON App versions. The keys are the largest jetton ids (jetton indices) added in that versions. */
const VERSION_WITH_JETTON_ID = {
  6: '2.2',
  9: '2.6.1',
  10: '2.9.0', // TODO Replace to real version
};

export const VERSION_WITH_PAYLOAD: Record<TonPayloadFormat['type'], string> = {
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

export const DEVICES_WITH_LOCK_DOUBLE_CHECK = new Set<`${DeviceModelId}`>(['nanoS', 'nanoSP']);

// https://github.com/LedgerHQ/app-ton/blob/d3e1edbbc1fcf9a5d6982fbb971f757a83d0aa56/doc/MESSAGES.md?plain=1#L51
const DEVICES_NOT_SUPPORTING_JETTON_ID = new Set<`${DeviceModelId}`>(['nanoS']);

export function doesSupport(ledgerTonVersion: string, featureVersion: string) {
  return compareVersions(ledgerTonVersion, featureVersion) >= 0;
}

/**
 * Checks whether the current Ledger device supports `knownJetton` generally
 */
export function doesSupportKnownJetton(ledgerModel: DeviceModelId | undefined, ledgerTonVersion: string) {
  return ledgerModel // If the Ledger model is unknown, assuming it can be any model and acting safely
    && !DEVICES_NOT_SUPPORTING_JETTON_ID.has(ledgerModel)
    // Note: JavaScript sorts the numeric `VERSION_WITH_JETTON_ID` keys in ascending order automatically
    && doesSupport(ledgerTonVersion, Object.values(VERSION_WITH_JETTON_ID)[0]);
}

/**
 * Checks that the current Ledger device supports the specific jetton id. This function should be used only if
 * `doesSupportKnownJetton` returns `true`, because it doesn't check what that function checks.
 */
export function doesSupportKnownJettonId(ledgerTonVersion: string, jettonId: number) {
  // Note: JavaScript sorts the numeric `VERSION_WITH_JETTON_ID` keys in ascending order automatically
  for (const [candidateJettonId, candidateVersion] of Object.entries(VERSION_WITH_JETTON_ID)) {
    if (jettonId <= Number(candidateJettonId)) {
      return doesSupport(ledgerTonVersion, candidateVersion);
    }
  }

  logDebugError(`The minimum TON App version for jetton id ${jettonId} is not set in VERSION_WITH_JETTON_ID`);
  return false;
}

export function doesSupportNonZeroQueryId(ledgerTonVersion: string) {
  return !(
    compareVersions(ledgerTonVersion, VERSION_WITH_BROKEN_QUERY_ID.min) >= 0
    && compareVersions(ledgerTonVersion, VERSION_WITH_BROKEN_QUERY_ID.max) <= 0
  );
}
