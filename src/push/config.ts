export const PUSH_APP_URL = process.env.PUSH_APP_URL || 'https://push.bot';
export const PUSH_API_URL = process.env.PUSH_API_URL;
export const PUSH_RROVER_URL = process.env.PUSH_PROVER_URL
  || 'https://mytonwalletorg--jwt-prover-v0-1-0-jwtprover-endpoint.modal.run';
export const PUSH_START_PARAM_DELIMITER = '=';
export const PUSH_CHAIN = 'ton';
export const PUSH_SC_VERSIONS = {
  v1: [
    'EQD0BinUPHBWioBD4gODJND4YEeYn_D_WE_C8LZqypxB3xAb',
    'EQBF7iKdVdO-cmUISlG2zUM97JeP2KiTUPL-e4EaemRpVafX',
  ],
  v2: 'EQDsLumYtKM8Awld7pYy_0w2Hb-T5MbRdKko5gWAY824nWf8',
  v3: ['EQABWqk6gBER4RsJpjbXmDnWP7KD3PMQ-SvI5O8mSzOibnA-', 'EQBNl2Hnxgc-olNY_Qq9iB3Rd3P7GGrW2oUzLc47BW3EjHNy'],
  NFT: 'EQDU7oPG3BqQWckIoit8tjGC4txNt2Pv-QcyptuPn2_ZKOkm',
  jwtV1: 'EQDJvWeZswAfKkx1PQZaBxQAOIIZVzYx0SQ8WoiZXoAwIO-m',
};
export const PUSH_GOOGLE_OAUTH_CLIENT_ID = process.env.PUSH_GOOGLE_OAUTH_CLIENT_ID;
export const PUSH_APPLE_OAUTH_CLIENT_ID = process.env.PUSH_APPLE_OAUTH_CLIENT_ID;
export const PUSH_MICROSOFT_OAUTH_CLIENT_ID = process.env.PUSH_MICROSOFT_OAUTH_CLIENT_ID;
export const PUSH_FACEBOOK_OAUTH_CLIENT_ID = process.env.PUSH_FACEBOOK_OAUTH_CLIENT_ID;
export const NETWORK = 'mainnet';
