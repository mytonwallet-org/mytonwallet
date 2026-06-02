import { Address } from '@ton/core';
import { Cell, Dictionary, type TupleReader } from '@ton/core';

import type { ApiNetwork } from '../../../types/misc';

import { MFA_EXTENSION_CODE_HASH, MFA_MASTER_ADDRESS } from '../../../../config';
import safeExec from '../../../../util/safeExec';
import { getTonClient } from '../util/tonCore';
import { ApiServerError } from '../../../errors';

import { getContractCode } from './MfaExtension';
import { MfaMaster } from './MfaMaster';

export function readCellOpt(stack: TupleReader): Cell | undefined {
  return safeExec(() => stack.readCellOpt(), {
    shouldIgnoreError: true,
  }) ?? undefined;
}

export async function resolveMfaExtensionAddress(network: ApiNetwork, walletAddress: Address) {
  const client = getTonClient(network);

  const { stack, exit_code } = await client.runMethodWithError(walletAddress, 'get_extensions');

  if (exit_code !== 0) return;

  const cell = stack.readCellOpt();
  if (!cell) return;

  const dict = Dictionary.loadDirect(
    Dictionary.Keys.BigUint(256),
    Dictionary.Values.BigInt(1),
    cell,
  );

  const extensions = dict.keys().map((key) =>
    `0:${key.toString(16).padStart(64, '0')}`,
  );

  const extensionCodeHashLibraryRef = getContractCode().hash();
  const extensionCodeHashFull = MFA_EXTENSION_CODE_HASH
    ? Buffer.from(MFA_EXTENSION_CODE_HASH, 'hex')
    : undefined;

  for (const extension of extensions) {
    const { code } = await client.getAddressInfo(extension);
    // Inactive addresses return `code: ""`.
    if (!code) continue;

    const codeHash = Cell.fromBase64(code).hash();

    if (
      codeHash.equals(extensionCodeHashLibraryRef)
      || (extensionCodeHashFull && codeHash.equals(extensionCodeHashFull))
    ) {
      return extension;
    }
  }
}

export async function getMfaExtensionSeqno(network: ApiNetwork, extensionAddress: string) {
  const client = getTonClient(network);
  const { stack, exit_code } = await client.runMethodWithError(Address.parse(extensionAddress), 'get_seqno');
  if (exit_code !== 0) {
    throw new ApiServerError(
      `MFA extension is not available (exit_code: ${exit_code}). Try reinstalling MFA.`,
      400,
    );
  }
  return stack.readNumber();
}

export function getMfaFees(network: ApiNetwork, forwardMsg: Cell, actions: number, extendedActions: number) {
  const contract = getTonClient(network).open(
    MfaMaster.createFromAddress(Address.parse(MFA_MASTER_ADDRESS)),
  );

  return contract.getEstimatedFee({ forwardMsg, actions, extendedActions });
}
