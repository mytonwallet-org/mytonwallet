import type { TeactNode } from '../lib/teact/teact';
import React from '../lib/teact/teact';

import type { ApiChain } from '../api/types';
import type { Account } from '../global/types';

import { getOrderedAccountChains } from './chain';
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
