import type { TeactNode } from '../lib/teact/teact';
import React from '../lib/teact/teact';

import type { ApiChain, ApiStakingState } from '../api/types';
import type { Account, UserToken } from '../global/types';

import { IS_GRAM_WALLET } from '../config';
import { getAddressLineChains, getChainsWithBalance, getOrderedAccountChains } from './chain';
import { pick } from './iteratees';
import { shortenAddress } from './shortenAddress';
import { shortenDomain } from './shortenDomain';

type FormatVariant = 'x-small' | 'small' | 'medium';

type SizeConfig = {
  single: [left: number, right: number];
  domain: number;
  address: [left: number, right: number];
};

type VariantConfig = {
  size: SizeConfig;
  separator: string;
  // Max number of chains rendered; undefined renders all
  maxChains?: number;
  // How many leading chains render their address; the rest render the icon only
  addressChains?: number;
};

const SMALL_SIZE: SizeConfig = {
  single: [0, 4],
  domain: 8,
  address: [0, 4],
};

const MEDIUM_SIZE: SizeConfig = {
  single: [6, 6],
  domain: 12,
  address: [0, 6],
};

const VARIANT_CONFIG: Record<FormatVariant, VariantConfig> = {
  'x-small': {
    size: SMALL_SIZE,
    separator: ' ',
    maxChains: 3,
    addressChains: 1,
  },
  small: {
    size: SMALL_SIZE,
    separator: ', ',
    maxChains: 3,
    addressChains: 2,
  },
  medium: {
    size: MEDIUM_SIZE,
    separator: ', ',
  },
};

/**
 * The `byChain` to feed into address rendering (`formatAccountAddresses`, the card address menu):
 * the account's chains narrowed by `getAddressLineChains` to the chains the account's funds are in.
 * Returns the input object untouched (same reference) when no chain is hidden, so memoized
 * consumers keep their cache.
 */
export function getAddressDisplayByChain(
  byChain: Account['byChain'],
  accountTokens?: UserToken[],
  stakingStates?: ApiStakingState[],
): Account['byChain'] {
  // The gate applies to the Gram Wallet build only; every other build must not pay for the work below,
  // as the callers sit on hot paths (`withGlobal` mappers)
  if (!IS_GRAM_WALLET || !accountTokens) return byChain;

  // Disabled (hidden) tokens must not expand the line - same as the master-side `getHasOnlyTonTokens`
  const fundedChains = getChainsWithBalance(accountTokens.filter(({ isDisabled }) => !isDisabled), stakingStates);
  const chains = Object.keys(byChain) as ApiChain[];
  const shownChains = getAddressLineChains(chains, fundedChains);
  if (shownChains.length === chains.length) return byChain;

  return pick(byChain, shownChains);
}

export function formatAccountAddresses(
  byChain: Account['byChain'],
  variant: FormatVariant = 'medium',
): TeactNode | undefined {
  const chains = getOrderedAccountChains(byChain);
  if (chains.length === 0) return undefined;

  const config = VARIANT_CONFIG[variant];

  // Single-chain account
  if (chains.length === 1) {
    const chain = chains[0];
    const wallet = byChain[chain];

    if (!wallet) return undefined;

    const text = wallet.domain ?? wallet.address;
    const type = wallet.domain ? 'domain' : 'single';

    return (
      <>
        {renderIcon(chain)}
        {getShortText(text, config.size, type)}
      </>
    );
  }

  // Multi-chain account
  const elements: TeactNode[] = [];
  const visibleChains = config.maxChains ? chains.slice(0, config.maxChains) : chains;

  visibleChains.forEach((chain, index) => {
    const account = byChain[chain];
    if (!account) return;

    if (index > 0) {
      elements.push(config.separator);
    }

    const showAddress = config.addressChains === undefined || index < config.addressChains;
    if (!showAddress) {
      elements.push(renderIcon(chain));
      return;
    }

    const isDomain = Boolean(account.domain);
    const displayText = getShortText(account.domain ?? account.address, config.size, isDomain ? 'domain' : 'address');
    elements.push(renderIcon(chain), displayText);
  });

  return <>{elements}</>;
}

function getShortText(text: string, size: SizeConfig, type: keyof SizeConfig) {
  if (type === 'domain') {
    return shortenDomain(text, size.domain);
  }

  const [left, right] = size[type] as [number, number];
  return shortenAddress(text, left, right);
}

function renderIcon(chain: ApiChain) {
  return <i key={`icon-${chain}`} className={`icon-chain-${chain}`} aria-hidden />;
}
