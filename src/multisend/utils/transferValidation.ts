import { Address } from '@ton/core';

import { TONCOIN } from '../../config';
import safeExec from '../../util/safeExec';
import { trimStringByMaxBytes } from '../../util/text';
import { resolveOrValidate } from '../../util/validateAddress';
import { findTokenInfo } from './tokens';

interface TransferRow {
  receiver: string;
  amount: string;
  tokenIdentifier: string;
  comment?: string;
  resolvedTokenInfo?: { tokenAddress: string; symbol: string; name: string; decimals: number };
  resolvedAddress?: string;
}

export function isNativeTokenIdentifier(identifier: string): boolean {
  const lower = identifier.toLowerCase();
  // The native token slug and its chain name are accepted alongside the current symbol
  return lower === TONCOIN.symbol.toLowerCase() || lower === TONCOIN.slug || lower === TONCOIN.chain;
}

async function validateTokenIdentifier(tokenIdentifier: string): Promise<{
  isValid: boolean;
  error?: string;
  tokenInfo?: { tokenAddress: string; symbol: string; name: string; decimals: number };
}> {
  if (isNativeTokenIdentifier(tokenIdentifier)) {
    return { isValid: true };
  }

  try {
    const tokenInfo = await findTokenInfo(tokenIdentifier);
    if (!tokenInfo) {
      return {
        isValid: false,
        error: safeExec(() => Address.parse(tokenIdentifier))
          ? `Token not found for address "${tokenIdentifier}". Please verify the token address is correct.`
          : `Invalid token identifier "${tokenIdentifier}". Please use a valid token name, symbol, or minter address.`,
      };
    }

    if (!safeExec(() => Address.parse(tokenInfo.tokenAddress))) {
      return {
        isValid: false,
        error: `Invalid token address format for "${tokenIdentifier}".`,
      };
    }

    return { isValid: true, tokenInfo };
  } catch (err: any) {
    return {
      isValid: false,
      error: err?.message || 'Failed to validate token',
    };
  }
}

function isValidAmount(amount: string): boolean {
  const numAmount = Number(amount);
  return !Number.isNaN(numAmount) && numAmount > 0;
}

export async function validateAndProcessTransfer(transfer: {
  receiver: string;
  amount: string;
  tokenIdentifier: string;
  comment?: string;
}): Promise<{
    isValid: boolean;
    error?: string;
    processedTransfer?: TransferRow;
  }> {
  const { receiver, amount, tokenIdentifier, comment } = transfer;

  const { resolvedAddress, error } = await resolveOrValidate(receiver);
  if (error) {
    return { isValid: false, error };
  }

  // Validate amount
  if (!isValidAmount(amount)) {
    return {
      isValid: false,
      error: 'Invalid amount',
    };
  }

  // Validate and process token identifier
  try {
    const tokenValidationResult = await validateTokenIdentifier(tokenIdentifier);
    if (!tokenValidationResult.isValid) {
      return {
        isValid: false,
        error: tokenValidationResult.error || 'Invalid token identifier',
      };
    }

    const processedTransfer: TransferRow = {
      receiver,
      amount,
      tokenIdentifier,
      comment: comment ? trimStringByMaxBytes(comment, 5000) : undefined,
      resolvedTokenInfo: tokenValidationResult.tokenInfo,
      resolvedAddress: resolvedAddress !== receiver ? resolvedAddress : undefined,
    };

    return {
      isValid: true,
      processedTransfer,
    };
  } catch (err) {
    return {
      isValid: false,
      error: err instanceof Error ? err.message : 'Invalid token identifier',
    };
  }
}
