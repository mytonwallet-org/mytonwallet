export interface ApiTransaction {
  payload: string;
  signature: string;
  address: string;
  /** Server-authenticated metadata for an SDK-generated MFA refill, bound to this exact payload. */
  mfaRefill?: {
    amount: string;
    payloadHash: string;
  };
}

export interface ApiInstallRequest {
  address: string;
  telegramId?: string;
}
