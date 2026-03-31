import { DEBUG } from '../../../config';
import { PUSH_RROVER_URL } from '../../config';
import { hexFromBigInt } from '../../../util/casting';
import { calcAddressSha256HeadBigInt } from '../addressEncoders';
import { calcProofBuffers } from './bls12381';
import { buildJwtVerifyEmailInputSignals } from './buildInputSignals';

export async function proveJwtVerifyEmail(
  jwt: string,
  pubkey: string,
  salt: bigint,
  userAddress: string,
  isLocal = false,
) {
  const inputSignals = buildJwtVerifyEmailInputSignals(jwt, pubkey, hexFromBigInt(salt));

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log('Proving...');
  }

  const { publicSignalsArray, proofStrings } = isLocal
    ? await proveLocally(inputSignals)
    : await proveRemotely(inputSignals);

  const [expiresAt, targetHash2, pubkeyHash, receiverAddressHashHead] = publicSignalsArray.map(BigInt) as bigint[];

  // Verify prover service integrity
  if (!isLocal) {
    const expectedReceiverAddressHashHead = await calcAddressSha256HeadBigInt(userAddress);
    if (receiverAddressHashHead !== expectedReceiverAddressHashHead) {
      throw new Error('Invalid `receiverAddressHashHead` from the prover service');
    }
  }

  const publicSignals = { expiresAt, targetHash2, pubkeyHash, receiverAddressHashHead };
  const { utils } = await import('ffjavascript');
  const proof = await calcProofBuffers(utils.unstringifyBigInts(proofStrings));

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log('[OK] Proved', { publicSignals, proof });
  }

  return { publicSignals, proof };
}

async function proveLocally(inputSignals: any) {
  const snarkjs = await import('snarkjs');
  const { publicSignals, proof } = await snarkjs.groth16.fullProve(
    inputSignals,
    './zk/JwtVerifyEmail.wasm',
    './zk/JwtVerifyEmail.zkey',
  );

  return { publicSignalsArray: publicSignals, proofStrings: proof };
}

async function proveRemotely(inputSignals: any) {
  const proverResponse = await fetch(PUSH_RROVER_URL, {
    method: 'POST',
    body: JSON.stringify({ input: inputSignals }),
    headers: { 'Content-Type': 'application/json' },
  });

  const result = await proverResponse.json();

  return { publicSignalsArray: result.pub_signals, proofStrings: result.proof };
}
