import type { CheckInfo } from '../../api/chains/ton/contracts/PushEscrowJwt';
import type { ApiJwtCheck } from '../types';
import type { JwkRs256 } from './jwt/jwt';

import { NETWORK, PUSH_RROVER_URL } from '../config';
import { bigIntFromHex } from '../../util/casting';
import { fromDecimal } from '../../util/decimals';
import { pause } from '../../util/schedulers';
import { buildTokenTransferBody, resolveTokenWalletAddress } from '../../api/chains/ton/util/tonCore';
import { parseJwt, verifyJwt } from './jwt/jwt';
import { proveJwtVerifyEmail } from './jwt/prove';
import { fetchWellKnownJwks } from './jwt/wellKnownJwks';
import {
  collectAvailablePubkeyIndices,
  fetchCheckInfo,
  fetchPubkeyIndicesByHashes,
  findCheckPubkeyIndex,
} from './contractController';

import { Fees as JwtFees, PushEscrowJwt } from '../../api/chains/ton/contracts/PushEscrowJwt';

const TINY_JETTONS = ['EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs']; // USDT
const JWT_TON_FULL_FEE = JwtFees.TON_CREATE_GAS + JwtFees.TON_CASH_GAS + JwtFees.TON_TRANSFER;
// eslint-disable-next-line @stylistic/max-len
const JWT_JETTON_FULL_FEE = JwtFees.JETTON_CREATE_GAS + JwtFees.JETTON_CASH_GAS + JwtFees.JETTON_TRANSFER + JwtFees.TON_TRANSFER;
// eslint-disable-next-line @stylistic/max-len
const JWT_TINY_JETTON_FULL_FEE = JwtFees.JETTON_CREATE_GAS + JwtFees.JETTON_CASH_GAS + JwtFees.TINY_JETTON_TRANSFER + JwtFees.TON_TRANSFER;

const WARM_UP_INTERVAL = 1000 * 50; // 50 seconds
const WARM_UP_MAX_ATTEMPTS = 6;

let preparedProveJwtArgs: {
  wellKnownJwks: JwkRs256[];
  contractPubkeyIndicesByHashes: Record<string, number>;
  checkInfo: CheckInfo;
} | undefined;

export async function processCreateCheck(check: ApiJwtCheck, userAddress: string) {
  const { id: checkId, type, contractAddress, comment, targetHash3, salt } = check;
  const isJettonTransfer = type === 'coin' && Boolean(check.minterAddress);
  const amount = check.type === 'coin' ? fromDecimal(check.amount, check.decimals) : 0n;
  const pubkeyIndices = await collectAvailablePubkeyIndices(check);
  const createCheckParams = {
    checkId,
    salt: bigIntFromHex(salt),
    targetHash3: bigIntFromHex(targetHash3),
    pubkeyIndices,
    comment,
  };
  const payload = isJettonTransfer
    ? PushEscrowJwt.prepareCreateJettonCheckForwardPayload(createCheckParams)
    : PushEscrowJwt.prepareCreateCheck(createCheckParams);

  let message;

  if (isJettonTransfer) {
    const jettonWalletAddress = await resolveTokenWalletAddress(NETWORK, userAddress, check.minterAddress!);
    if (!jettonWalletAddress) {
      throw new Error('Could not resolve jetton wallet address');
    }

    const isTinyJetton = TINY_JETTONS.includes(check.minterAddress!);
    const messageAmount = String(
      isTinyJetton
        ? JwtFees.TINY_JETTON_TRANSFER + JWT_TINY_JETTON_FULL_FEE
        : JwtFees.JETTON_TRANSFER + JWT_JETTON_FULL_FEE,
    );
    const forwardAmount = isTinyJetton ? JWT_TINY_JETTON_FULL_FEE : JWT_JETTON_FULL_FEE;

    message = {
      address: jettonWalletAddress,
      amount: messageAmount,
      payload: buildTokenTransferBody({
        tokenAmount: amount,
        toAddress: contractAddress,
        responseAddress: userAddress,
        forwardAmount,
        forwardPayload: payload,
        noInlineForwardPayload: true, // Not sure whether it's necessary; setting true to be on the safe side
      }).toBoc().toString('base64'),
    };
  } else {
    const messageAmount = String(amount + JWT_TON_FULL_FEE);

    message = {
      address: contractAddress,
      amount: messageAmount,
      payload: payload.toBoc().toString('base64'),
    };
  }

  return message;
}

export async function prepareProveJwtArgs(check: ApiJwtCheck) {
  void warmUpProverService();

  const [wellKnownJwks, contractPubkeyIndicesByHashes, checkInfo] = await Promise.all([
    fetchWellKnownJwks(),
    fetchPubkeyIndicesByHashes(check),
    fetchCheckInfo(check),
  ]);

  preparedProveJwtArgs = { wellKnownJwks, contractPubkeyIndicesByHashes, checkInfo };
}

export async function processCashCheck(
  _: ApiJwtCheck,
  userAddress: string,
  jwt: string,
) {
  const { wellKnownJwks, contractPubkeyIndicesByHashes, checkInfo } = preparedProveJwtArgs!;
  const { header: { kid } } = parseJwt(jwt);

  const jwk = wellKnownJwks.find((jwk) => jwk.kid === kid);
  if (!jwk) throw new Error('Key not supported');

  const isValid = await verifyJwt(jwt, jwk);
  if (!isValid) throw new Error('Key verification failed');

  const pubkeyIndex = await findCheckPubkeyIndex(contractPubkeyIndicesByHashes, checkInfo, jwk);
  if (pubkeyIndex === -1) throw new Error('Key not expected');

  const { publicSignals, proof } = await proveJwtVerifyEmail(jwt, jwk.n, checkInfo.salt, userAddress);

  return {
    receiverAddress: userAddress,
    pubkeyIndex,
    publicSignals,
    proof,
  };
}

export function processCancelCheck() {
  return JwtFees.TON_CANCEL;
}

let warmUpCount = 0;

async function warmUpProverService() {
  while (++warmUpCount <= WARM_UP_MAX_ATTEMPTS) {
    await fetch(PUSH_RROVER_URL, { method: 'POST' });
    await pause(WARM_UP_INTERVAL);
  }
}
