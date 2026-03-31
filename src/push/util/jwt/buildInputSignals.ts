import { DEBUG } from '../../../config';
import { sha256Pad, toCircomBigIntBytes, Uint8ArrayToCharArray } from '../../lib/zk-email-helpers';
import { bigIntFromBase64, bigIntFromHex } from '../../../util/casting';
import { extractJwtKeyIndices, extractJwtKeyLengths, parseJwt } from './jwt';

const MAX_JWT_PADDED_BYTES = 1088;

export function buildJwtVerifyEmailInputSignals(
  jwt: string,
  pubkeyBase64: string,
  saltHex: string,
) {
  const [headerBase64, payloadBase64, signatureBase64] = jwt.split('.');
  const { headerJson, payloadJson, payload } = parseJwt(jwt);

  const messageBuffer = Buffer.from(`${headerBase64}.${payloadBase64}`);
  const [messagePadded, messagePaddedLen] = sha256Pad(messageBuffer, MAX_JWT_PADDED_BYTES);
  const {
    issKeyStartIndex,
    audKeyStartIndex,
    emailKeyStartIndex,
    emailVerifiedKeyStartIndex,
    nonceKeyStartIndex,
    expKeyStartIndex,
  } = extractJwtKeyIndices(headerJson, payloadJson);
  const { issLength, audLength, emailLength, nonceLength } = extractJwtKeyLengths(payload, payloadJson);
  const inputSignals = {
    message: Uint8ArrayToCharArray(messagePadded),
    messageLength: messagePaddedLen,
    pubkey: toCircomBigIntBytes(bigIntFromBase64(pubkeyBase64)),
    signature: toCircomBigIntBytes(bigIntFromBase64(signatureBase64)),
    periodIndex: jwt.indexOf('.'),
    issKeyStartIndex,
    issLength,
    audKeyStartIndex,
    audLength,
    emailKeyStartIndex,
    emailLength,
    emailVerifiedKeyStartIndex,
    nonceKeyStartIndex,
    nonceLength,
    expKeyStartIndex,
    salt: String(bigIntFromHex(saltHex)),
  };

  if (DEBUG) {
    // eslint-disable-next-line no-console
    console.log('[OK] Built input signals:', { inputSignals });
  }

  return inputSignals;
}
