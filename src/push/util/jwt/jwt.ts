import { asciiFromBase64Url, bufferFromBase64Url, stringFromBase64Url } from '../../../util/casting';

export interface JwkRs256 {
  n: string;
  e: string;
  kid: string;
  alg?: 'RS256';
  kty: 'RSA';
  use: 'sig';
}

export function parseJwt(jwt: string) {
  const [headerBase64, payloadBase64] = jwt.split('.');

  return {
    // Circuit expects indexes in ASCII representation
    headerJson: asciiFromBase64Url(headerBase64),
    payloadJson: asciiFromBase64Url(payloadBase64),
    header: JSON.parse(stringFromBase64Url(headerBase64)),
    payload: JSON.parse(stringFromBase64Url(payloadBase64)),
  };
}

export async function verifyJwt(jwt: string, jwk: JwkRs256) {
  try {
    const { header } = parseJwt(jwt);
    if (header.alg !== 'RS256') throw new Error('Unsupported `alg` in JWT');

    const cryptoKey = await crypto.subtle.importKey(
      'jwk',
      jwk,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );

    const [headerBase64Url, payloadBase64Url, signatureBase64Url] = jwt.split('.');
    const dataBuffer = Buffer.from(`${headerBase64Url}.${payloadBase64Url}`);
    const signatureBuffer = bufferFromBase64Url(signatureBase64Url);

    return await crypto.subtle.verify(
      { name: 'RSASSA-PKCS1-v1_5' },
      cryptoKey,
      signatureBuffer,
      dataBuffer,
    );
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('JWT verification failed:', err);

    return false;
  }
}

export function extractJwtKeyIndices(headerJson: string, payloadJson: string) {
  return {
    jwtKidStartIndex: headerJson.indexOf('"kid":'),
    issKeyStartIndex: payloadJson.indexOf('"iss":'),
    audKeyStartIndex: payloadJson.indexOf('"aud":'),
    iatKeyStartIndex: payloadJson.indexOf('"iat":'),
    expKeyStartIndex: payloadJson.indexOf('"exp":'),
    azpKeyStartIndex: payloadJson.indexOf('"azp":'),
    emailKeyStartIndex: payloadJson.indexOf('"email":'),
    emailVerifiedKeyStartIndex: payloadJson.indexOf('"email_verified":'),
    nonceKeyStartIndex: payloadJson.indexOf('"nonce":'),
  };
}

export function extractJwtKeyLengths(payload: any, payloadJson: string) {
  return {
    issLength: extractIssuerLength(payloadJson),
    audLength: payload.aud?.length ?? 0,
    azpLength: payload.azp?.length ?? 0,
    emailLength: extractEmailLength(payloadJson),
    nonceLength: payload.nonce?.length ?? 0,
  };
}

// Some providers add character escaping with `\` which gets lost when parsing with `JSON.parse`,
// resulting in shorter string lengths, so we need to extract the length manually.
function extractIssuerLength(payloadJson: string) {
  const issStartIndex = payloadJson.indexOf('"iss":"') + 7;

  return payloadJson.slice(issStartIndex).indexOf('"');
}

// Extract email length from raw JWT, accounting for escape sequences like \u0040
function extractEmailLength(payloadJson: string) {
  const emailStartIndex = payloadJson.indexOf('"email":"') + 9;

  return payloadJson.slice(emailStartIndex).indexOf('"');
}
