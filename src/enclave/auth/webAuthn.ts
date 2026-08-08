import { APP_NAME } from '../../config';
import { bufferFromHex, hexFromArrayBuffer } from '../../util/casting';
import { randomBytes } from '../../util/random';

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

export interface SetupResult {
  credentialId: string;
  transports: AuthenticatorTransport[];
  secretMethod: SecretMethod;
  secretArrayBuffer: ArrayBuffer;
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

export async function setup(): Promise<SetupResult> {
  const userHandleSecret = randomBytes(SECRET_SIZE);
  const options = buildCreateCredentialOptions(userHandleSecret);
  const credential = (await navigator.credentials.create(options)) as PublicKeyCredential;
  const credentialId = hexFromArrayBuffer(credential.rawId);
  const transports = credential.response.getTransports?.() ?? [];

  const extensionResults = credential.getClientExtensionResults();
  const secretMethod = extensionResults.prf?.enabled
    ? 'prf'
    : extensionResults.hmacCreateSecret
      ? 'hmacSecret'
      : extensionResults.credBlob
        ? 'credBlob'
        : 'userHandle';
  const secretArrayBuffer = extractSecret(secretMethod, extensionResults, userHandleSecret);

  return {
    credentialId,
    transports,
    secretMethod,
    secretArrayBuffer,
  };
}

function buildCreateCredentialOptions(userHandleSecret: ArrayBuffer): CredentialCreationOptions {
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

export async function authorize({ credentialId, transports, secretMethod }: {
  credentialId: string;
  transports: AuthenticatorTransport[];
  secretMethod: SecretMethod;
}) {
  const signal = new AbortController().signal;
  const options = buildGetCredentialOptions(credentialId, transports, secretMethod, signal);
  const assertion = (await navigator.credentials.get(options)) as PublicKeyCredential;
  if (signal.aborted) throw new Error('Verification canceled');

  const extensionResults = assertion.getClientExtensionResults();
  const userHandleSecret = (assertion.response as AuthenticatorAssertionResponse)?.userHandle ?? undefined;

  return extractSecret(secretMethod, extensionResults, userHandleSecret);
}

function buildGetCredentialOptions(
  credentialId: string,
  transports: AuthenticatorTransport[],
  secretMethod: SecretMethod,
  signal: AbortSignal,
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
    },
    signal,
  };
}

function extractSecret(
  secretMethod: SecretMethod,
  extensionResults: AuthenticationExtensionsClientOutputs,
  userHandle?: ArrayBuffer,
) {
  switch (secretMethod) {
    case 'prf':
      if (!extensionResults.prf?.results?.first) {
        throw new Error('PRF output not found');
      }
      return toArrayBuffer(extensionResults.prf.results.first);

    case 'hmacSecret':
      if (!extensionResults.hmacGetSecret?.output1) {
        throw new Error('HMAC secret not found');
      }
      return toArrayBuffer(extensionResults.hmacGetSecret.output1);

    case 'credBlob':
      if (!extensionResults.getCredBlob) {
        throw new Error('Cred blob not found');
      }
      return toArrayBuffer(extensionResults.getCredBlob);

    case 'userHandle':
      if (!userHandle) {
        throw new Error('User handle not found');
      }
      return userHandle;
  }
}

function toArrayBuffer(bufferSource: BufferSource): ArrayBuffer {
  return bufferSource instanceof ArrayBuffer
    ? bufferSource
    : bufferSource.buffer.slice(
      bufferSource.byteOffset,
      bufferSource.byteOffset + bufferSource.byteLength,
    );
}
