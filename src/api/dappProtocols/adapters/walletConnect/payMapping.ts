import type { PaymentInfo, PaymentOption } from '@walletconnect/pay';

import type { ApiChain } from '../../../types';
import type {
  WcPayContext,
  WcPayMerchant,
  WcPayPaymentAmount,
  WcPayPaymentInfo,
  WcPayPaymentOption,
} from './types';
import { CHAIN_IDS, EVM_CHAIN_IDS, SOLANA_CHAIN_IDS } from './types';

import { parseAccountId } from '../../../../util/account';
import { checkIsKycUrlAllowed } from '../../../../util/walletConnectPay';
import { fetchStoredAccount } from '../../../common/accounts';
import { parseWcPayFiatAmount, resolveWcPayTokenSlug, toWcPayRawAmount } from './payAmount';

export async function buildPayAccounts(accountId: string, isFake?: boolean): Promise<string[]> {
  if (isFake) {
    return ['eip155:1:0x0000000000000000000000000000000000000000'];
  }

  const { network } = parseAccountId(accountId);
  const account = await fetchStoredAccount(accountId);
  const accounts: string[] = [];

  for (const [caip2, entry] of Object.entries(EVM_CHAIN_IDS)) {
    if (entry.network !== network) {
      continue;
    }

    const address = account.byChain[entry.chain]?.address;
    if (address) {
      accounts.push(`${caip2}:${address.toLowerCase()}`);
    }
  }

  const solanaAddress = account.byChain.solana?.address;
  if (solanaAddress) {
    for (const [caip2, entry] of Object.entries(SOLANA_CHAIN_IDS)) {
      if (entry.network !== network) {
        continue;
      }

      accounts.push(`${caip2}:${solanaAddress}`);
    }
  }

  return accounts;
}

export function buildPayMerchant(merchant?: { name: string; iconUrl?: string }): WcPayMerchant {
  return {
    name: merchant?.name ?? 'Merchant',
    iconUrl: merchant?.iconUrl,
  };
}

export function buildPayPaymentAmount(amount: PaymentOption['amount']): WcPayPaymentAmount {
  const rawAmount = toWcPayRawAmount(amount);

  return {
    value: amount.value,
    display: {
      assetSymbol: amount.display.assetSymbol,
      assetName: amount.display.assetName,
      decimals: amount.display.decimals,
      iconUrl: amount.display.iconUrl,
      networkName: amount.display.networkName,
    },
    fiatAmount: parseWcPayFiatAmount(rawAmount),
  };
}

export function buildPayPaymentInfo(info?: Pick<PaymentInfo, 'expiresAt' | 'amount'>): WcPayPaymentInfo | undefined {
  if (!info) {
    return undefined;
  }

  return {
    expiresAt: info.expiresAt,
    amount: info.amount ? buildPayPaymentAmount(info.amount) : undefined,
  };
}

export function parsePayOptionChain(account: string): ApiChain | undefined {
  const parts = account.split(':');
  if (parts.length < 3) {
    return undefined;
  }

  const caip2 = `${parts[0]}:${parts[1]}`;
  return CHAIN_IDS[caip2]?.chain;
}

export function mapPayPaymentOption(option: PaymentOption): WcPayPaymentOption {
  const chainHint = parsePayOptionChain(option.account);
  const rawAmount = toWcPayRawAmount(option.amount);

  return {
    id: option.id,
    account: option.account,
    amountValue: option.amount.value,
    slug: resolveWcPayTokenSlug(rawAmount, chainHint),
    display: {
      assetSymbol: option.amount.display.assetSymbol,
      assetName: option.amount.display.assetName,
      decimals: option.amount.display.decimals,
      networkName: option.amount.display.networkName,
    },
    fiatAmount: parseWcPayFiatAmount(rawAmount),
    etaS: option.etaS,
    expiresAt: option.expiresAt,
    kycUrl: option.collectData?.url && checkIsKycUrlAllowed(option.collectData.url)
      ? option.collectData.url
      : undefined,
  };
}

export function trimPayContextToSigning(ctx: WcPayContext, selectedOption: PaymentOption): WcPayContext {
  return {
    accountId: ctx.accountId,
    paymentId: ctx.paymentId,
    merchant: ctx.merchant,
    paymentInfo: ctx.paymentInfo,
    paymentOption: mapPayPaymentOption(selectedOption),
  };
}
