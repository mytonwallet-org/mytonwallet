import { APP_NAME } from '../../config';
import { bufferFromHex, hexFromArrayBuffer } from '../../util/casting';
import { randomBytes } from '../../util/random';
import { toArrayBuffer } from './untrustedBuffer';

declare global {
  interface AuthenticationExtensionsClientInputs {
    credBlob?: Uint8Array; // max 32 bytes
    getCredBlob?: boolean;
    hmacCreateSecret?: boolean;
    hmacGetSecret?: { salt1: Uint8Array }; // 32-byte random data
  }

  interface AuthenticationExtensionsClientOutputs {
    credBlob?: boolean;
    getCredBlob?: Uint8Array;
    hmacCreateSecret?: boolean;
    hmacGetSecret?: { output1: Uint8Array };
  }

  interface AuthenticatorResponse {
    getTransports?: () => AuthenticatorTransport[];
  }
}

export type SecretMethod = 'prf' | 'hmacSecret' | 'credBlob' | 'userHandle';

export interface CredentialParams {
  credentialId: string;
  transports: AuthenticatorTransport[];
  secretMethod: SecretMethod;
}

enum PubkeyAlg {
  Ed25519 = -8,
  ES256 = -7,
  RS256 = -257,
}

const RP_ID = window.location.hostname;
const RP_NAME = APP_NAME;
const USER_NAME = APP_NAME;
const CREDENTIAL_TIMEOUT = 120000;
const SECRET_SIZE = 32;
const PRF_SALT = new TextEncoder().encode(APP_NAME);

/**
 * `persistParams` runs before any second prompt, so a credential the authenticator has already
 * minted is recorded even when the secret never arrives. Handing it in rather than returning it
 * keeps the order out of the caller's hands.
 */
export async function setup(persistParams: (params: CredentialParams) => Promise<void>): Promise<ArrayBuffer> {
  const userHandleSecret = randomBytes(SECRET_SIZE);
  const options = buildCreateCredentialOptions(userHandleSecret);
  const credential = requireCredential(await navigator.credentials.create(options), 'Credential');
  const credentialId = hexFromArrayBuffer(requireArrayBuffer(credential.rawId, 'Credential id'));
  const transports = credential.response?.getTransports?.() ?? [];

  const extensionResults = readExtensionResults(credential);
  const secretMethod = pickSecretMethod(extensionResults);
  const params = { credentialId, transports, secretMethod };

  await persistParams(params);

  // A registration does not always carry the secret it enables. `prf.enabled` answers whether the
  // PRF may be used with this credential, not whether it was evaluated now: an authenticator that
  // cannot evaluate one during registration reports it enabled and returns no output, which the
  // spec answers with "you could still try evaluating the PRF in an assertion". `hmacGetSecret` and
  // `getCredBlob` are assertion outputs and are never present at registration at all. Whichever
  // method is in play, the fallback costs a second prompt, and only for the credentials that need it.
  return extractSecret(secretMethod, extensionResults, userHandleSecret) ?? authorize(params);
}

function buildCreateCredentialOptions(userHandleSecret: Uint8Array): CredentialCreationOptions {
  const challenge = randomBytes(32);
  const credBlobSecret = randomBytes(SECRET_SIZE);

  return {
    publicKey: {
      challenge,
      rp: {
        name: RP_NAME,
        id: RP_ID,
      },
      user: {
        id: userHandleSecret,
        name: USER_NAME,
        displayName: USER_NAME,
      },
      pubKeyCredParams: [{
        type: 'public-key',
        alg: PubkeyAlg.ES256,
      }, {
        type: 'public-key',
        alg: PubkeyAlg.RS256,
      }, {
        type: 'public-key',
        alg: PubkeyAlg.Ed25519,
      }],
      authenticatorSelection: {
        requireResidentKey: true,
        userVerification: 'preferred',
      },
      extensions: {
        credBlob: credBlobSecret,
        hmacCreateSecret: true,
        prf: {
          eval: {
            first: PRF_SALT,
          },
        },
      },
      timeout: CREDENTIAL_TIMEOUT,
      excludeCredentials: [],
    },
  };
}

export async function authorize({ credentialId, transports, secretMethod }: CredentialParams) {
  const options = buildGetCredentialOptions(credentialId, transports, secretMethod);
  const assertion = requireCredential(await navigator.credentials.get(options), 'Assertion');

  const extensionResults = readExtensionResults(assertion);
  const userHandleSecret = toArrayBuffer((assertion.response as AuthenticatorAssertionResponse)?.userHandle);
  const secret = extractSecret(secretMethod, extensionResults, userHandleSecret);

  if (!secret) {
    throw new Error(`${SECRET_NAME[secretMethod]} not found`);
  }

  return secret;
}

function buildGetCredentialOptions(
  credentialId: string,
  transports: AuthenticatorTransport[],
  secretMethod: SecretMethod,
): CredentialRequestOptions {
  const challenge = randomBytes(32);

  const extensions: Record<string, any> = {};

  if (secretMethod === 'prf') {
    extensions.prf = {
      eval: {
        first: PRF_SALT,
      },
    };
  }

  if (secretMethod === 'hmacSecret') {
    extensions.hmacGetSecret = {
      salt1: PRF_SALT,
    };
  }

  if (secretMethod === 'credBlob') {
    extensions.getCredBlob = true;
  }

  return {
    publicKey: {
      challenge,
      allowCredentials: [{
        id: bufferFromHex(credentialId),
        type: 'public-key',
        transports,
      }],
      userVerification: 'required',
      extensions,
      timeout: CREDENTIAL_TIMEOUT,
    },
  };
}

const SECRET_NAME: Record<SecretMethod, string> = {
  prf: 'PRF output',
  hmacSecret: 'HMAC secret',
  credBlob: 'Cred blob',
  userHandle: 'User handle',
};

/**
 * The PRF is claimed on either signal: `enabled` is the authenticator's answer about the credential,
 * `results` is an evaluation it already performed, and an implementation that reports one without
 * the other still supports the method. Reading `enabled` alone would file such a credential under
 * `userHandle`, which is persisted and governs every later authorization.
 */
function pickSecretMethod(extensionResults: AuthenticationExtensionsClientOutputs): SecretMethod {
  if (extensionResults.prf?.enabled || extensionResults.prf?.results) return 'prf';
  if (extensionResults.hmacCreateSecret) return 'hmacSecret';
  if (extensionResults.credBlob) return 'credBlob';

  return 'userHandle';
}

function extractSecret(
  secretMethod: SecretMethod,
  extensionResults: AuthenticationExtensionsClientOutputs,
  userHandle?: BufferSource,
) {
  const secret = toArrayBuffer(rawSecret(secretMethod, extensionResults, userHandle));
  return secret?.byteLength ? secret : undefined;
}

function rawSecret(
  secretMethod: SecretMethod,
  extensionResults: AuthenticationExtensionsClientOutputs,
  userHandle?: BufferSource,
) {
  switch (secretMethod) {
    case 'prf':
      return extensionResults.prf?.results?.first;

    case 'hmacSecret':
      return extensionResults.hmacGetSecret?.output1;

    case 'credBlob':
      return extensionResults.getCredBlob;

    case 'userHandle':
      return userHandle;
  }
}

/**
 * The credential object is as untrusted as the binaries inside it: the same patched API that hands
 * over a foreign buffer may resolve `null`, which the spec allows, or an object missing the members
 * read below. Dereferencing one of those raises a bare TypeError with no name for what failed.
 */
function requireCredential(value: unknown, name: string): PublicKeyCredential {
  if (!value || typeof value !== 'object') {
    throw new Error(`${name} not returned`);
  }

  return value as PublicKeyCredential;
}

/** An implementation that reports no extension results at all leaves the methods it would have named unclaimed */
function readExtensionResults(credential: PublicKeyCredential): AuthenticationExtensionsClientOutputs {
  const results = credential.getClientExtensionResults?.();

  return results && typeof results === 'object' ? results : {};
}

function requireArrayBuffer(value: unknown, name: string): ArrayBuffer {
  const buffer = toArrayBuffer(value);
  if (!buffer?.byteLength) {
    throw new Error(`${name} not found`);
  }

  return buffer;
}
