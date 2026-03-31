import type { JwkRs256 } from './jwt';

import { DEBUG } from '../../../config';
import { bufferFromBase64Url } from '../../../util/casting';
import { fetchJson } from '../../../util/fetch';

const DISCOVERY_URLS = [
  'https://accounts.google.com/.well-known/openid-configuration',
  'https://appleid.apple.com/.well-known/openid-configuration',
  'https://login.microsoftonline.com/common/v2.0/.well-known/openid-configuration',

  // Facebook does not return CORS headers for their endpoints, so we have to hardcode the list of keys
  // 'https://facebook.com/.well-known/openid-configuration',
  getHardcodedFacebookKeys,

  // 'https://{tenant}.auth0.com/.well-known/openid-configuration',
];

export async function collectWellKnownPubkeyHashes() {
  const wellKnownJwks = await fetchWellKnownJwks();
  const { calcPubkeyPoseidonHash } = await import('./poseidon');

  return wellKnownJwks.map(({ kid, n }) => {
    const pubkeyHash = String(calcPubkeyPoseidonHash(bufferFromBase64Url(n)));

    if (DEBUG) {
      // eslint-disable-next-line no-console
      console.log({ kid, pubkeyHash });
    }

    return pubkeyHash;
  });
}

export async function fetchWellKnownJwks() {
  const jwkGroups = await Promise.all(DISCOVERY_URLS.map(async (source) => {
    if (typeof source === 'string') {
      const discoveryInfo = await fetchJson(source);
      const { keys: jwks } = await fetchJson<{ keys: JwkRs256[] }>(`${discoveryInfo.jwks_uri}?r=${Math.random()}`);

      return jwks;
    } else {
      return source().keys;
    }
  }));

  return jwkGroups.flat();
}

function getHardcodedFacebookKeys(): { keys: JwkRs256[] } {
  return {
    keys: [
      {
        kid: 'e4f6715b789895089f5c26d53b01a2991ed2772b',
        kty: 'RSA',
        alg: 'RS256',
        use: 'sig',
        // eslint-disable-next-line @stylistic/max-len
        n: 'jqye61CZB8XB1Ezm0sBFvJJA1OpBGVqCwWDsxzHzRYmKZaaYymJnQj_TFJWDwc_8mRBMpbrZInGCxOB_kYuupjTlAIcpjOUsVzNpH1AacAxoBmfZGd4YRDMxBcxDQGI-i2bW3jX2CGA3R4BOxo2uVM4KbcHbu9cz57FLRTAoY-eNAvhGfaR2mhmoTEbpUYz2oI4i65EfoNakYgqy70085AOM0w6-4jnQkOJqlXlxKn-06vEhoF8T_jRsZg6uSWh33ieXjr80eKh3WTF-P-1ZGnUgpUqoUIn_tfbJygLozS9YXW_PYidN6pwaBLTGHmJbRoCUPsh4uO0-iEMJO4xdsQ',
        e: 'AQAB',
      },
      {
        kid: 'de06bc6ae22713d6f462802f9a6b3d9ef8242fd5',
        kty: 'RSA',
        alg: 'RS256',
        use: 'sig',
        // eslint-disable-next-line @stylistic/max-len
        n: 'jULL7Mp7n16RlYMtZerkxbIRlfNacmfHY-pmv7dinyJfmr26ag1iyooyHPZg68Ztwe1ppbHU31j5qA9b2xvulEUG631XYGRu__2albC2gbAI3vIS2AhYOksty-BM_kYyezUd1fCu8GGVsstIXJTj6ZNj1j8GKnIYMZMnyuuQLwWMMpsF19eoqACHFY343911Q7r8fXVaVda4ef8Ec-suA2sjUeDajof44riFcOGBHNacfA9AO9-GAUhJ5wb1Gu3aCdXfS4mR65f1KpFg0NlviF1VtXRNpksA8gNOqdBj_JLuk4R-L9vtLPtI8z-pgdCUbA_qkJrUaC4Qi7pr0pZ4nw',
        e: 'AQAB',
      },
    ],
  };
}
